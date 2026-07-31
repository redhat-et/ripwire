# bench/multiswe — the first public C++ localization eval mined from Multi-SWE-bench

`bench/cppbench/` mines commit-message queries from one repo's own history (SFML). `bench/locbench/`
is Python-only public data (LocBench / SWE-bench-Lite). Neither is a public, human-verified, **issue-
report-shaped** C++ localization benchmark. `run_multiswe.py` closes that gap by mining
[**Multi-SWE-bench**](https://arxiv.org/abs/2504.02605) (ByteDance-Seed, NeurIPS 2025) — a multilingual
issue-resolving benchmark curated by 68 expert annotators from real, merged, test-verified GitHub pull
requests across 8 languages — down to its **C** and **C++** splits, and scores ctxpack against them the
same way `bench/locbench/` scores LocBench: same metric shapes, same zero-silent-skip discipline, same
determinism contract.

## What it measures

Each instance = one human-verified, test-passing PR from a public C or C++ repo in the Multi-SWE-bench
dataset. **query** = the linked GitHub **issue**'s title + body (`resolved_issues`, not the PR
description — the issue is written by someone who does **not** yet know the fix, the same query shape
LocBench uses and a meaningfully harder/more honest shape than a post-hoc commit message). **gold** =
the source files (and, where derivable from git's own hunk-header function context, the functions) the
PR's `fix_patch` touches, filtered to the language's own extensions and excluding newly-added files
(structurally absent from the indexed base tree — the same convention `bench/cppbench` and
`bench/locbench` use for `added_functions`). The harness, per instance:

1. **shallow-checkout the repo AT `base.sha`** (never the fix commit — the linked issue must not
   already show the fix);
2. run ctxpack as the localizer in three arms — `--for` (shipping default, incl. the B8 query-mention
   anchor), `--for --no-mention-boost` (the anchor switched off), `--query` (pure lexical BM25);
3. **parse** the flat `--format=candidates` export;
4. **score** strict file@1/3/5/10 (ALL gold files within the top-k of one flat rank — LocAgent's
   definition, arXiv 2503.09089 §4.1), lenient any-gold-within-top-10, and first-hit MRR.

Deterministic given `(dataset.lock, ctxpack binary)`: no LLM, no RNG, frozen instance order, and every
arm run is verified byte-identical twice before it is scored (zero-silent-skip contract — a checkout,
index, or ctxpack failure aborts loudly rather than dropping an instance).

## Dataset + license

Source: [`ByteDance-Seed/Multi-SWE-bench`](https://huggingface.co/datasets/ByteDance-Seed/Multi-SWE-bench)
on Hugging Face (the full 1,632-instance release; `Multi-SWE-bench_mini` is a 400-instance,
50-per-language curated subset of the same data — this harness mines the full release's `c/` and `cpp/`
directories, one JSONL file per source repo). Pinned revision `56ff018c04a38e27ada1e9d0a6d5839a51f88f0d`
(recorded in `dataset.lock`).

**License, checked and recorded (task requirement):** the dataset card's license section reads *"The
dataset is licensed under CC0, subject to any intellectual property rights in the dataset owned by
Bytedance. The data is adapted from the listed open source projects; your use of that data must comply
with their respective licenses."* (the HF repo's metadata tag shows `other` — the card's own prose above
is the operative statement, and is what `dataset.lock`'s `license` field and every JSON result carry
verbatim.) The underlying source repos mined here are themselves permissively licensed: Catch2 (BSL-1.0),
fmt (MIT), nlohmann/json (MIT), simdjson (Apache-2.0), cpp-httplib (MIT).

**The raw per-repo JSONL files are NOT committed to this repo** — CC0 permits caching them, but repo
weight is a separate concern (`ponylang/ponyc`'s C-split file alone is 26 MB); only the derived, compact
`dataset.lock` (instance ids, query hashes, gold sets, base SHAs) is committed, the same posture
`bench/cppbench` takes with its git-log mining source. `--refresh-dataset` re-downloads the raw files
into a scratch `--raw-dir` and re-mines.

## C/C++ source repos in this split

| lang | org/repo | license |
|---|---|---|
| C | facebook/zstd | BSD |
| C | jqlang/jq | MIT/CC0 |
| C | ponylang/ponyc | BSD-2-Clause |
| C++ | catchorg/Catch2 | BSL-1.0 |
| C++ | fmtlib/fmt | MIT |
| C++ | nlohmann/json | MIT |
| C++ | simdjson/simdjson | Apache-2.0 |
| C++ | yhirose/cpp-httplib | MIT |

## Mining rules (`dataset.lock`)

Deterministic filtering over each repo's raw JSONL rows (already human-verified PRs — Multi-SWE-bench's
own curation is the quality bar; this harness adds only the filters needed to build a real query and a
real gold set), frozen by a canonical `content_sha256` over `(instance_id, base_sha, gold_files,
query_sha256)` — a second run **trusts** the lock file (self-consistency check against a hand-edit or
corruption) rather than re-mining, unless `--refresh-dataset` is passed:

- `resolved_issues` must be non-empty (the PR must link a real issue — this is what makes the query an
  issue REPORT, not a post-hoc fix description) and the joined issue title+body must be ≥4 words;
- `fix_patch` must be non-empty and touch at least one non-added file in the split's own language
  extensions (`.c/.h` for C; `.cpp/.cc/.cxx/.hpp/.hh/.h/.ipp/.tpp/.mm` for C++);
- the issue text must not embed a contributor's own local home-directory path (an absolute macOS
  `Users`, Linux `home`, or Windows `C:\Users` path — a common compiler-error/backtrace copy-paste
  artifact; the same hygiene rule `bench/cppbench` applies, reusing its regex) — excluded so the
  shipped dataset never carries a third-party username;
- `--cap-per-lang` (default 0 = no cap) can bound the mined set per language for a faster ablation.

Every exclusion is counted in `dataset.lock`'s `mining_stats` per language, not a silent drop.

## Gold-function derivation

Best-effort, from git's own hunk-header function context (`@@ ... @@ <context>`) in `fix_patch` — the
identical, no-LLM, no-heuristic-beyond-git's-own-xfuncname-patterns extraction `bench/cppbench` uses,
imported rather than re-derived. Recorded per instance in the JSON output (`gold_funcs`) for future work;
**not** part of the scored metrics here (file-level only), for the same reason `bench/cppbench` doesn't
score it — hunk context is frequently empty or coarse, and a strict function-level score would overstate
precision this harness cannot back up.

## Offline test fixture

`test/multiswecheck.sh` validates the harness's mining, tamper-rejection, offline-checkout, scoring, and
determinism contracts against **3 hand-vendored fixture rows** (2 eligible, 1 with no linked issue) that
reference a tiny local git repo built at test time — zero network, wired into `test/regression.sh`'s
absorb list. It exercises `--offline` + `--repo-map ORG/REPO=local_path`, the same escape hatch a
future re-run against a private mirror or an air-gapped CI runner would use.

## Arms

| arm | invocation | what it is |
|---|---|---|
| `for` | `ctxpack <repo> --for="<issue title+body>"` | shipping default task lens, incl. the B8 mention anchor |
| `for-no-mention` | `ctxpack <repo> --for="<issue title+body>" --no-mention-boost` | ablation: anchor OFF |
| `query` | `ctxpack <repo> --query="<issue title+body>"` | pure lexical BM25, no lens framing |

## How to run

```sh
# one-command reproduction: mine (network: HF + GitHub) + score the full C++ split with the shipped lock
CTXPACK=./build/ctxpack python3 bench/multiswe/run_multiswe.py \
    --lang cpp --work-dir /tmp/multiswe \
    --json-out bench/multiswe/results/cpp.json \
    --scoreboard-out bench/multiswe/results/cpp_scoreboard.md

# offline smoke gate — no network, no dependency on GitHub/HuggingFace
bash test/multiswecheck.sh

# re-mine from scratch (both languages, no cap)
python3 bench/multiswe/run_multiswe.py --languages=c,cpp --refresh-dataset --cap-per-lang=0 \
    --raw-dir /tmp/multiswe-raw --work-dir /tmp/multiswe --dataset-lock /tmp/other.lock

# score the C split once it's been mined into a lock alongside cpp
CTXPACK=./build/ctxpack python3 bench/multiswe/run_multiswe.py --lang c \
    --work-dir /tmp/multiswe --dataset-lock /tmp/other.lock --json-out /tmp/c.json
```

## Results — C++ split, n=122 mined / 121 scored (1 unindexable-gold, printed reason) (2026-07-22)

| arm | file@1 | file@3 | file@5 | file@10 | any@10 | MRR | wall/inst |
|---|---|---|---|---|---|---|---|
| `--for` (shipping default) | 8.3% | 36.4% | 47.9% | **55.4%** | **89.3%** | 0.465 | 0.17s |
| `--for --no-mention-boost` | 8.3% | 35.5% | 45.5% | 53.7% | 86.8% | 0.447 | 0.09s |
| `--query` (raw BM25) | 8.3% | 35.5% | 45.5% | 53.7% | 86.8% | 0.447 | 0.09s |

Strata: **single-file instances (n=51): strict@10 86.3%** (`--for`; 82.4% without the mention anchor);
**multi-file instances (n=70): strict@10 32.9%** (all arms — strict requires EVERY gold file in the top-10,
and Multi-SWE C++ patches average 200+ lines across many files). Mention-anchor ablation: +1.7pp file@10,
+4.9pp on the single-file stratum — issue text that names a file/symbol is where the anchor earns its keep.

**Honest reading (the losses with the wins), pre-R1 baseline:**

- The headline `any@10 89.3%` says the bundle almost always surfaces at least one right file; the
  hard, honest number is multi-file strict@10 32.9% — complete-blast-radius retrieval on big C++ patches
  is open headroom (R1-class graph expansion is the designed lever; its first attempt was rejected by the
  held-out gate on the Python set but gained +2.6pp on C++ cppbench — a C++-side retry is future work).
- `file@1 8.3%` is low by construction: strict@1 on multi-file gold can only score when the patch touches
  one file; read @1 with the single-file stratum, not the pooled row.
- All three arms tie on the multi-file stratum: terse issue reports on these libraries rarely name enough
  files for any query-side lever to separate arms there.
- Scoring this benchmark flushed out two real ctxpack bugs (JSON data-file symbol explosion + tree-sitter
  error-recovery blowup on nlohmann/json's parser-torture suite, 43s for one 100KB file) — fixed at
  `kMaxJsonConfigBytes`/`kMaxJsonNestDepth` (parserVer 28) before these numbers were produced.

This is the **pre-R1 baseline** (`PLAN_audit5Public2026.md` R1 = anchor-hop expansion, not yet landed).
Re-run after R1 lands and append a second dated results block below rather than overwriting this one —
the whole point of a frozen `dataset.lock` is that the before/after comparison is apples-to-apples.

Reproduce: see the one-command block above. Per-instance rows (including derived `gold_funcs`) are in
`bench/multiswe/results/cpp.json`; the frozen instance list is `bench/multiswe/dataset.lock`.

## Future set: MULocBench (documented, not yet built)

[**MULocBench**](https://arxiv.org/abs/2509.25242) (arXiv 2509.25242, 2025) is adopted here as the next
public set — no harness built yet. It measures what this bench, `bench/cppbench`, and `bench/locbench`
all structurally cannot: **non-code gold** — 1,100 issues (46 Python projects) localized to configs and
docs, not just functions. R5 (`PLAN_audit5Public2026.md`) has now shipped the mechanism this benchmark
would score (doc-mention surfacing on `--for`, `src/mention.h::applyDocMentionBoost` — proved by
`test/docmentioncheck.sh` and a byte-identical LocBench Python held-out no-regression check), but building
the full 46-repo/1,100-issue harness itself (mining, a frozen `dataset.lock`, an offline gate — the same
shape of effort R3's Multi-SWE-bench harness took) was judged too heavy for that round and is carried
forward as the explicit residual: an honest partial beats a rushed eval (B3). Scoring against it would
still be the honest external check on R5's actual value once built (the paper reports every method
tested, including LLM-prompted ones, under 40% Acc@5/F1 at file level — the ceiling is open).
