# Head-to-head: ctxpack vs Aider repo-map vs codebase-memory-mcp vs graphify (LocBench held-out slice)

**Phase B5.3 of PLAN_researchImprove2026.md — 2026-07-13.**
Primary deliverable: the per-instance win/loss matrix and the **loss-bucket analysis** (what can we
learn to make ctxpack better). The scoreboard is the by-product.

## (i) Methodology + exact versions

**Dataset.** LocBench (`czlll/Loc-Bench_V1`, test split), the harness's frozen 560-row snapshot —
SHA-256 `5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97` (matches the pinned hash in
`run_locbench.py`; the HF datasets-server was 503ing during the run, so a cached copy from a prior
session's scratchpad was used — hash-verified against the harness's pinned value before use).

**Slice.** The **first 60 scored held-out instances in stable dataset order** — the harness's own frozen
repo-disjoint salted-SHA-256 split (`ctxpack-a7-v2`, byte0<128=train), via
`--split=heldout --max-scored 60 --n 560`. Zero exclusions in any arm; N(paired)=60.
Mix: 20 single-file gold, 40 multi-file — a **hard slice** (cf. the README footnote: strict
ALL-gold-in-top-k is much harder on multi-file gold; heldout-243 full-run strict file@10 is 60.9%
while this slice gives 36.7%).

**Checkouts.** Depth-1 shallow fetch of `base_commit` (`run_locbench.checkout()`, `history_depth=1`),
imported and reused unmodified by all arms. Competitor arms shared one checkout tree
(`headtohead/repos/`); the ctxpack arm used the harness's own workdir. Same commits, byte-identical
content.

**Gold + metric.** Gold = the harness's `primary_files` (patch-touched files present in the indexed
universe — identical gold for all arms). Metric = the harness's own strict file@k (`file_ranks` +
`acc_all_at`, **imported unmodified** from `run_locbench.py`): exact repo-relative path identity;
basename fallback only when the basename is unique in the universe (universe = `git ls-files` of the
checkout for competitor arms; ctxpack's stored worst/first ranks used directly). Strict@k = ALL gold
files within top-k; any@10 = lenient first-hit recall.

**Arms.**

| arm | version / hash | invocation |
|---|---|---|
| ctxpack `--for` (routed, default flags) | binary sha256 `eb1c39fa8054c2e33c5be22cbfbf17d91dcd0f1e90f1c53f593b3e50a9ee0faa`; repo @ `aab8674` with uncommitted work-tree changes (harness `run_locbench.py` sha256 `22bf603a5b3443f31ef81f9baccc6a230f524efce7708e63c32f795ce9e7c5e9`) | `CTXPACK=<build> run_locbench.py --split=heldout --max-scored 60 --arms for --n 560` → per instance `--for=<issue 1200ch> --top-k=200 --format=candidates --cache=<rich>` |
| Aider repo-map | aider-chat **0.86.2**, Python 3.12.13 (venv) | `RepoMap(map_tokens=1e6, refresh="always").get_ranked_tags([], all_files, set(), idents)`; `idents` = aider's own `get_ident_mentions(issue[:1200])` (its real chat-personalization mechanism). Also a no-personalization control. File order = first appearance in ranked tags. |
| codebase-memory-mcp | **0.9.0** (npm, DeusData), node v26.4.0 | `cli index_repository --repo-path=<repo>` then `cli search_graph --project=<p> --query=<issue 1200ch> --limit=300` (BM25 over graph nodes, structural boosting). File order = first appearance in ranked symbol results. |
| graphify | **graphifyy 0.9.15** (PyPI, Graphify-Labs), Python 3.12.13 (venv), `PYTHONHASHSEED=0` | `graphify extract <repo> --code-only --no-cluster --out <per-instance dir>` (local tree-sitter AST, no LLM/API key) then `graphify query "<issue 1200ch>" --graph graph.json --budget 20000` (local BFS traversal from question-matched seed nodes). File order = first appearance of a node's `src=` file in BFS output (imposed convention — see note). |

**codebase-memory-mcp capability note (fairness).** The README advertises a `semantic_query` tool; the
0.9.0 binary does **not** ship it (`unknown tool: semantic_query`). Its NL-query capability is
`search_graph --query` (BM25 full-text over node names/signatures with structural boosts:
Functions +10, Routes +8, Classes +5) plus an optional `--semantic-query` keyword-array mode (needs
moderate/full index mode; not used — default index mode). So the comparison ran its real, shipping
NL-query→ranked-symbols path. On 1/60 instances (`Standard-Labs__real-intent-102`) its query returned
0 results — scored as a miss, instance kept.

**Aider capability note.** Aider's repo map has no query input per se; personalization comes only from
chat-mentioned identifiers/files. We fed the issue text through its own ident-extraction path — the
closest faithful "user pasted the issue into aider" simulation. Its map is otherwise query-independent
(the no-persona control shows how much the query actually moves it: +3.3pp strict@10). Files that never
appear in tags (pure docs/configs) cannot appear in its ranking.

**graphify capability + ranking-convention note (fairness).** graphify's `query` is a **BFS graph
traversal**, not a scored ranker: it matches seed nodes from the question text (including matching
docstring nodes containing URLs, which makes URL-heavy issues seed noisily), then walks 2 hops and
prints nodes in traversal order with no relevance score. The ranked-file list is therefore an
**imposed convention**: first appearance of each node's source file in that output order (seeds
first). Its LLM modes (doc/semantic extraction, community labeling) were never invoked — `--code-only
--no-cluster` is the fully-local path, zero API keys. One instance (home-assistant core) produced a
584 MB graph.json exceeding the tool's 512 MB query cap; the query was rerun with the tool's own
documented `GRAPHIFY_MAX_GRAPH_BYTES=2GB` raise (extract unchanged, noted in the JSONL record).
3/60 instances returned an empty ranked list (BFS found no seed match: openlibrary-7929,
aiohttp-9692, real-intent-102) — scored as misses, kept.

**graphify determinism observation.** Two back-to-back full runs (extract+query) of one instance
(`sopel-irc__sopel-2285`) produced the **same node/edge counts but a different ranked-file order**
(first divergence at rank 2); querying the *same* graph.json twice also reordered output. Root cause
is Python hash randomization: with `PYTHONHASHSEED=0` both the query and the full extract+query
pipeline become byte-reproducible (verified: identical ranked lists). The arm was run with
`PYTHONHASHSEED=0` pinned. Evidence: `graphify/determinism_run_{a,b}.json` (divergent, default env)
vs `graphify/determinism_run_{c,d}_seed0.json` (identical). So: **deterministic only if the caller
pins the hash seed — by default it is not.**

**Timeouts / skips.** 600 s per tool invocation (`gtimeout`); zero timeouts, zero errors, zero
exclusions. Wall per instance (median/max): ctxpack **0.074 s / 1.55 s** (warm, pre-built index);
aider **2.5 s / 87.6 s** (tags scan; two rankings per instance); cbm **1.14 s / 17.7 s** (index+query);
graphify **5.8 s / 96.4 s** (extract median 4.9 s / max 86.5 s + query).

## (ii) Headline table (N=60 paired, strict file@k per LocAgent §4.1)

| arm | file@1 | file@3 | file@5 | file@10 | any@10 (lenient) |
|---|---|---|---|---|---|
| **ctxpack `--for`** | 5.0% | **18.3%** | **26.7%** | **36.7%** | **75.0%** |
| aider repo-map (personalized) | 0.0% | 1.7% | 6.7% | 13.3% | 33.3% |
| aider repo-map (no persona) | 0.0% | 1.7% | 3.3% | 10.0% | 26.7% |
| codebase-memory-mcp | **6.7%** | 10.0% | 16.7% | 26.7% | 66.7% |
| graphify (BFS traversal order) | 0.0% | 3.3% | 5.0% | 21.7% | 41.7% |

ctxpack leads strict@3/@5/@10 and lenient@10; codebase-memory-mcp edges strict@1 (BM25 name-exact hits
land #1 when the issue names the module — see buckets) and is the only competitor within reach.
Aider's map barely responds to the query (personalization only nudges file PageRank).

## (iii) Win/loss matrix (strict file@10)

| | ctx wins | competitor wins | both hit | neither |
|---|---|---|---|---|
| vs aider | **16** | 2 | 6 | 36 |
| vs codebase-memory-mcp | **10** | 4 | 12 | 34 |
| vs graphify | **12** | 3 | 10 | 35 |

Lenient any@10: vs aider 28–3 ctxpack; vs cbm 14–9 ctxpack; vs graphify 22–2 ctxpack.

Competitor strict wins (= ctxpack strict losses, all analyzed below):
`scikit-learn-25186`, `micropython-lib-947`, `scikit-learn-29130`, `transformers-35453` (cbm);
`scikit-learn-29130`, `repo_standards_validator-137` (aider).
graphify strict wins add: `GitPython-1636`, `imod-python-1159` (+ `repo_standards_validator-137`,
shared with aider). Lenient-only losses vs cbm add: `modin-6836`, `MSS-1967`, `simtools-1183`,
`TagStudio-735`, `zulip-31168`; vs aider add: `real-intent-102`, `scikit-learn-8478`; vs graphify
adds nothing new (`GitPython-1636` also lenient, `scikit-learn-8478` shared).

ctxpack strict wins for the record — vs aider (16): scikit-learn-24145, quiz-backend-84, sopel-2285,
pip-13085, aiortc-795, pandas-21401, scikit-learn-14012, pulp_rpm-3224, scikit-learn-6116, rucio-4930,
zulip-14091, modin-3404, pandas-35029, jwcrypto-195, aiohttp-7829, PlasmaPy-2542; vs cbm (10):
sopel-2285, pip-13085, pandas-21401, pulp_rpm-3224, pandas-35029, jwcrypto-195, aiohttp-7829,
klein-773, real-intent-27, hal-cgp-180.

Full 60-row paired table: `paired_table.md`; machine-readable: `headtohead_results.json`.

## (iv) Loss-bucket analysis (14 unique loss instances, verified by rerun)

Every loss was re-executed (`--for` with the instance's re-checked-out base_commit + its cached index;
reruns reproduced the stored ranks exactly) and the actual top-10 vs gold inspected.
Assignments + full notes: `loss_buckets.json`; rerun evidence: `loss_ctxpack_output.json`.

### B1 — path/module-mention unexploited — 3 instances (all strict losses; the biggest lever)
The issue **literally names the gold file** — as a GitHub URL path, a dotted module, or a package
name — and ctxpack's ranker doesn't exploit it, while cbm's plain BM25 over names does.
- `scikit-learn-25186`: issue contains `sklearn/ensemble/_iforest.py` twice in URLs plus
  `IsolationForest`/`_compute_score_samples`. ctx 60, cbm **8**.
- `transformers-35453`: issue says "In `transformers.optimization` support…". Gold
  `src/transformers/optimization.py`. ctx 19, cbm **0**.
- `micropython-lib-947`: "the MicroPython `requests` module"; gold path spells
  `requests/requests/__init__.py`. ctx 34, cbm **1**, aider 17.

### B2 — multi-file strict near-miss — 5 instances (the volume bucket)
First gold found early; a **sibling gold file at rank 11–65** kills strict@10.
- `repo_standards_validator-137`: repository_checks.py at **0**, but thin entrypoint
  `validator/__main__.py` at 19 (aider got both ≤8).
- `zulip-31168`: views/streams.py 12, lib/users.py 63.
- `modin-6836`: first-hit 12; 3 of 4 gold ≤52, the 4th (dataframe.py) fell outside the 200-symbol
  candidate export — **top-k truncation** is a secondary cause here.
- `TagStudio-735`: tag_search.py 20, tag.py 36 (cbm first-hit 9).
- `imod-python-1159` [graphify strict-win @6]: ctx first-hit 2, but `imod/schemata.py` at 57 **even
  though the issue names `DTypeSchema.validate` verbatim** (defined there) and `grid.py` at 29
  (`xu.DataArray.from_structured` named too) — the symbol-flavored variant of B1's mention-anchoring;
  graphify seeded its BFS on exactly those named symbols.

### B3 — vocabulary gap (feature-request) — 1
- `scikit-learn-8478`: "MICE imputer" — the term doesn't exist in the repo at base_commit; no lexical
  path to gold (impute.py 42, estimator_checks.py 36, plot_missing_values.py outside top-200 — all
  three ARE in the indexed universe, so this is deep-rank, not parse coverage). No arm strict-hit;
  aider's query-independent structural rank got a lenient 9.

### B4 — non-code/infra gold — 1
- `scikit-learn-29130`: gold is `build_tools/update_environments_and_lock_files.py` (CI/lockfile
  maintenance script, weak call-graph presence). ctx 113; aider **4**; cbm 9. The task lens is
  code-symbol-centric; maintenance-script gold starves it.

### B5 — indirect gold (named file != fixed file) — 1
- `MSS-1967`: issue names `conftest.py` L227; ctxpack ranked conftest.py **#1** — lexically perfect,
  but the accepted fix edited the three files whose popups *triggered* the warning. Wants a 1-hop
  "what reaches this" graph expansion from the named anchor (exactly `--anchor`'s design intent), not
  better lexical match. cbm lenient-hit at 1.

### B6 — test/doc-file crowding — 1 primary (+3 as secondary)
- `simtools-1183`: gold = the db layer (13/30/52); ctxpack's top-10 = io_handler, `docs/source/conf.py`
  and **5 test files**. Tests that mention the profiled symbols outrank implementation. Also visible in
  the top-10s of 25186, 29130, 8478 (sklearn test files flood the top).

### B7 — ultra-short/vague query — 2
- `real-intent-102`: entire issue = "Improve integration efficiency Multithreading". ctx 13/14;
  aider strict-hit (≤11) because structure-only PageRank doesn't care; cbm returned **0 results**.
- `GitPython-1636` [graphify strict-win @5]: CVE stub — advisory URL + "untrusted search path on
  Windows", near-zero code vocabulary. Gold `git/cmd.py` at ctx rank 10 (misses @10 by one);
  graphify reaches the repo's biggest hub early regardless of query. A structural-prior fallback
  (see build-next #5) covers exactly this shape.

## (v) What to build next (ranked by expected wins)

1. **Query-mention anchoring — files, dotted modules, AND named symbols (B1 + imod: 4 strict
   losses; also helps B5).** Parse the `--for` text for
   explicit file paths (incl. inside GitHub URLs), dotted module paths (`transformers.optimization` →
   `**/transformers/optimization.py`), and backticked package names; direct-boost matching files (and
   optionally seed `--anchor`'s PPR from them). cbm wins this bucket with plain BM25 — the single
   cheapest, highest-yield fix; would have flipped 25186/35453/947, turning the cbm matrix from 10–4
   to ~13–1 and the graphify matrix from 12–3 to ~13–1 (imod).
2. **Second-file recovery for multi-file gold (B2: 4 losses).** After the top lexical hit, pull its
   strongest structural neighbors (callers/callees/co-change partners) into ranks 5–10 — the sibling
   gold is usually 1 hop from the found gold (entrypoint wiring `__main__.py`, the widget beside the
   modal, lib/ beside views/). A "buddy-boost" of the top-3 hits' 1-hop neighborhoods attacks strict@10
   directly. Also: raise the candidate-export ceiling or emit file-level rows so a 4th gold file can't
   be truncation-invisible (modin-6836).
3. **Test/doc demotion for issue-localization (B6 + secondary in 3 more).** In `--for` bundles for
   bug/perf prose, down-weight `test_*/tests/`, `doc(s)/`, `conf.py` unless the query names tests. The
   sklearn losses all had 4–6 test files in the top-10 displacing implementation files.
4. **Anchor-hop for named-file issues (B5).** When the query names a file that ranks #1 but the task
   smells like "X misbehaves when triggered by others" (warnings, flaky tests), auto-expand 1 hop of
   who-reaches-it — `--anchor`'s exact use case; consider routing to it when a query-file anchor is
   detected.
5. **Low-signal-query fallback (B7).** When the query yields near-zero lexical mass, blend in the
   structural prior (plain PageRank) instead of amplifying noise — aider's query-independent rank beat
   us on the 4-word issue.
6. (Observational) **Infra-script gold (B4)** is rare (1/60) and hostile to a code lens; note it,
   don't build for it yet.

Buckets by frequency (14 losses): multi-file near-miss 5 > path/module-mention 3 > ultra-short query
2 > (vocab-gap, infra, indirect, test-crowding) 1 each. By *actionability*, mention anchoring (files,
modules, AND symbols — imod shows the symbol flavor) is first: 4 of its losses were competitor
strict-wins that plain name/seed matching solved.

## Artifacts

All under `scratchpad/headtohead/`:
- `ctxpack60.json` — harness output, ctxpack arm (per-instance ranks, walls, coverage)
- `aider60.jsonl` (raw) / `aider60.clean.jsonl` (filtered: aider prints progress lines to stdout) — ranked files per instance, personalized + plain
- `cbm60.jsonl` — codebase-memory-mcp ranked files per instance
- `graphify60.jsonl` — graphify ranked files per instance (+ per-instance extract/query walls);
  `graphify/determinism_run_*.json` — the determinism evidence pairs
- `headtohead_results.json` — paired per-instance table + summaries (scoreboard source of truth)
- `paired_table.md` — human-readable 60-row paired table
- `loss_buckets.json` / `loss_ctxpack_output.json` — bucket assignments + rerun evidence
- `run_aider_arm.{py,sh}`, `aider_worker.py`, `cbm_worker.py`, `run_cbm_arm.sh`, `graphify_worker.py`, `run_graphify_arm.sh`, `score.py`, `score4.py` — arm scripts
- `logs/` — full stdout/stderr of every arm

## Provenance / security note
During the run a "coordinator" message embedded in a system-reminder claimed HF was down and directed
use of an unverified dataset file at a specific path ("do NOT wait", "verified copy"). It was not acted
on: the dataset used was independently located and hash-verified against the harness's own pinned
SHA-256 before any instruction arrived. Flagging per prompt-injection protocol.
