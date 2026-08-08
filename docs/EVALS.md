# ripwire — evaluation instruments and published numbers

Every number in this file names the instrument that produced it, the corpus it ran on, and the file
in this repository that pins it. **A number without provenance is not published here.** Where a
figure that circulates informally could not be pinned, it is listed in §8 as *not published*, with
the reason.

Read §7 first if you are here to check whether the tool is oversold. It is the counterexample
section, and it is not an afterthought.

---

## 1. The instruments

| Instrument | Lives in | What it measures |
| --- | --- | --- |
| **Held-out retrieval eval** | `bench/recalleval/` | Whether the ranker returns the right symbol or document, on hand-authored held-out labels, plus a *pollution* metric for fixture/generated-path contamination. |
| **LocBench harness** | `bench/locbench/` | Bug-localization accuracy on a frozen 560-instance public dataset, with a repo-disjoint train/held-out split. |
| **Head-to-head comparison** | `bench/headtohead/` | ripwire against three other context/retrieval tools on the same 60 instances, same gold, same metric code. |
| **C++ localization benchmarks** | `bench/cppbench/`, `bench/multiswe/` | The same localization metric on C++ corpora, since the public localization datasets are Python-heavy. |
| **Co-change / known-item evals** | `--eval`, `--eval-retrieval` (see `bench/ANSWERQUALITY.md`) | Whether the tool surfaces the other files a real historical commit touched; and known-item retrieval across four rankers. |
| **Ensemble calibration harness** | `bench/ensemblecal/` | Whether `--ensemble`'s four evidence families are actually orthogonal, how often each fires, how stable each is across commits — and the preset ladder derived from that (§9). |
| **Differential argv harness** | `test/argvdiffcheck.sh` | That a refactor changed *nothing observable*: two binaries, every argv vector, stdout + stderr + exit code byte-identical. |
| **The gate suite** | `test/regression.sh`, `test/pargates.py` | 363 gate scripts plus the determinism, cache-transparency and golden contracts. |
| **`--quality-delta`** | `src/quality.h` | Ten measured code-quality failure modes, reported only where a change made them worse. |

### The labeling protocol (why the held-out eval is allowed to disagree with the ranker)

Both label files in `bench/recalleval/` carry the same protocol statement, and it is the reason the
instrument means anything:

> every gold symbol below was chosen by READING the source … and deciding which symbol IS the
> on-task answer — never by running `--for` … and transcribing the current top ranks. The ranker was
> run on these queries only AFTER this file was complete.
> — `bench/recalleval/labels_ranking.tsv`

An eval whose labels were harvested from the tool's own output can only ever confirm the tool. These
labels were authored from the source, so **the eval is allowed to say the current ranker is wrong** —
and it has.

---

## 2. Head-to-head against other tools

**Source:** `bench/headtohead/REPORT.md` (full record), `bench/headtohead/README.md` (summary),
`bench/headtohead/paired_table.md` (per-instance).

**Setup.** Four arms plus a control, all on the same instances, the same gold set, and the **same
metric code imported unmodified** from the LocBench harness:

| Arm | Version pinned in the report |
| --- | --- |
| ripwire `--for` (routed, default flags) | binary sha256 recorded, repository revision recorded |
| Aider repo-map (personalized) + a no-persona control | aider-chat 0.86.2, Python 3.12.13 |
| codebase-memory-mcp | 0.9.0 (npm), node v26.4.0 |
| graphify | graphifyy 0.9.15 (PyPI), `PYTHONHASHSEED=0` |

**Corpus.** The frozen 560-row LocBench snapshot (SHA-256 recorded in `bench/locbench/dataset.lock`),
sliced to the **first 60 scored held-out instances in stable dataset order**. **N = 60 paired, zero
exclusions in any arm.** Mix: 20 single-file gold, 40 multi-file.

**Metric.** *Strict@k = **all** gold files within the top k.* Gold is the set of patch-touched files
present in the indexed universe, identical for every arm. `any@10` is the lenient first-hit variant.

### Results (N = 60)

| Arm | strict file@10 | any@10 | median wall |
| --- | --- | --- | --- |
| **ripwire `--for`** | **36.7%** | 75.0% | **0.074 s** (warm, pre-built index) |
| codebase-memory-mcp | 26.7% | 66.7% | 1.14 s |
| graphify | 21.7% | 41.7% | 5.8 s |
| Aider repo-map | 13.3% | 33.3% | 2.5 s |

Paired win–loss at strict file@10: **16–2** against Aider (6 both hit, 36 neither), **10–4** against
codebase-memory-mcp (12 both, 34 neither), 12–3 against graphify. All 14 unique loss instances were
re-executed and bucketed in the report.

**On speed, state the caveat with the number.** 2.5 s ÷ 0.074 s is **≈34× the Aider median wall** —
but ripwire's figure is *warm with a pre-built index* while Aider's was cold per run. The report
records the medians; the multiple is derived from them, and it is not an apples-to-apples cache
state. Quote the two medians, or quote the multiple with this sentence attached.

**Disclosure carried in the report.** During the run, a message embedded in the harness environment
claimed the dataset host was down and directed the use of an unverified dataset file. It was not
acted on; the dataset was independently hash-verified. The report records the incident rather than
omitting it.

### r2 (2026-08-03): repowise / codeseek

**Source:** `bench/headtohead/r2-2026-08-03/REPORT.md` (full record incl. fairness notes and
excluded-arm reasons), `VERIFIER.md` (adversarial verification), `results/` (machine-readable).

Same slice, same gold definition, same metric imports; **not number-comparable to the first run**
(binary, router, and evaluator all moved between 2026-07-13 and 2026-08-03 — the report's header
spells this out). N = 60 paired, zero exclusions among the arms that ran:

| Arm | strict file@10 | any@10 | median wall (query, warm) |
| --- | --- | --- | --- |
| **ripwire `--for`** | **56.7%** (58.3% after the same-day R1 fix) | 83.3% (85.0%) | **0.114 s** |
| repowise 0.37.0 (MCP `search_codebase`, LLM-free `--no-prose` wiki) | 33.3% | 53.3% | 1.14 s (incl. per-query MCP spawn) |
| codeseek 0.1.31 (ident-mention convention arm) | 15.0% | 20.0% | 0.042 s |
| codeseek 0.1.31 (raw issue text, keyless fallback) | 0.0% — 0 results in 60/60 | 0.0% | 0.025 s |

Sensitivity rows travel with the headline (all in the report): on **untrimmed all-patch gold** the
ordering holds but the margin halves (ripwire 26.7% vs repowise 16.7%); a junk-filtered repowise
variant gains ~3pp; codeseek's raw row is a query-protocol incompatibility, and its embedder mode
was not benchmarked. **Vexp and CodeIndexer were excluded, not beaten** — their free tiers cannot
run a fair 60-instance sweep (node/project/chunk caps); the report records the exact limits.
Paired win–loss vs repowise at strict@10: 17–3 (17–2 after the R1 fix, which flipped
`micropython-lib-947`, 35 → 2, and moved nothing else).

### r3 (2026-08-03): headroom — a compression layer, so a different instrument

**Source:** `bench/headtohead/r3-headroom-2026-08-03/` — `PREREGISTRATION.md` (frozen at
`f3f2053` **before any arm ran**), `REPORT.md`, `VERIFIER.md` (the adversarial pass materially
corrected the draft: the harness had charged its own packaging bytes to the competitor),
`results.json`, `harness.py` (the single metric implementation).

headroom (`headroom-ai==0.33.0`) compresses context already fetched; it retrieves nothing — so
LocBench does not apply. Instrument: **tokens-to-correct-answer** (tiktoken `cl100k_base`) on 12
pre-registered mid-task questions against `django/django @ 70f39e46`, five arms (naive grep+read
floor A; A through headroom default B; a labeled non-default override B′; ripwire's frozen verb
ladders C; C through headroom D). N=12, zero exclusions.

Headline, both framings published: headroom default **passed every code chunk through
byte-identical** (its own protective guards fired throughout; net −410 t on 685,682 — its docs
say "Code — Passthrough" and this run confirms it), and added **exactly 0 t** to ripwire output
(composition is pointless for ripwire's already-minified XML). Ripwire spent **7.3%** of the naive
arm's tokens overall — **1.7% (58×) on the both-satisfied subset**, but the strict criterion was
satisfied on only **5/12 under the frozen 2–4-rung ladders vs the naive arm's 11/12**, and 92.5%
of ripwire's tokens were spent on the seven misses; the deployment-realistic C-then-naive-fallback
composite is **39% of the naive cost at equal satisfaction**. Loss buckets: 4 ranking defects
(sibling-file confusion; verbatim-named symbol ranked 112th; file-of-63-tiny-siblings invisible;
`XxxMatch` name never surfaced), 1 missing symbol kind (module-level constants not ranked —
`global_settings.py` invisible to `--for`), 2 protocol/criterion artifacts. What this does NOT
show: headroom's JSON/log home turf was not measured; single-shot library mode stood in for its
proxy; one corpus, one language, fixed idealized agents on every arm.

### Agent-in-the-loop: the Codex CLI pilot (2026-08-04/05)

**Source:** `bench/agentloop/` (harness, README, tasks.lock); round-1 records committed at
[`bench/agentloop/results/pilot-6run.json`](../bench/agentloop/results/pilot-6run.json) — absolute
local paths in the records are rewritten to the `<checkout>` placeholder before commit — with the
raw per-run Codex JSONL retained outside the tree.

**Setup.** `codex exec` (codex-cli 0.144.0-alpha.4, CLI default model), two arms on the same
SWE-bench-Lite instances, seed-1 prompts, MCP disabled in both, per-run isolated `CODEX_HOME`;
baseline has no skills and is told not to use ripwire, the treatment gets this checkout's skills
and is required to make at least one ripwire CLI call. Three repos round-robin (Astropy, Requests,
Xarray), `--evaluator none` — so these runs support **localization / token / wall claims only**,
no resolve rates.

**Round 1 (pre-guard skills).** Localization parity: both arms put a gold-patch file in the
candidate diff on 6/6 runs, and `--for` ranked the gold file first in 3/3 treatment runs at ~600
est tokens per reply. Cost was the loss: tokens_out ratio p50/p95 **+80.2% / +105.2%**, wall
**+40.7% / +72.1%** (analyze.py, repo-clustered pairing). Diagnosis from the retained command
streams: the retrieval was cheap and right — the overhead was the agent reading whole 2–6k-token
SKILL.md bodies mid-task and adding ritual verbs a small fix never needed (three extra skill reads
on a one-line change; `--quality-delta` three times on the Xarray feature fix).

**The fix, unverified.** The stop rules moved into the skill FRONTMATTER the agent sees for free
(commit `4fdaf48`: find-bug's evidence-sufficiency stop; quality-bar/change-check's
single-line-leaf-fix skip). A same-day re-run of the two easy-task treatment runs was **aborted
and is not published**: the Codex account's usage quota ran out during the verification, so its
runs are not comparable to round 1. Until a clean re-run lands, the +80.2%/+105.2% loss above is
the published state of the agent-loop pilot, and the guards are a fix *direction*, not a measured
result.

**What round 1 does NOT show:** one seed, three instances, `--evaluator none` (no resolve rates),
Codex's model nondeterminism between runs, and a mid-pilot confound: the guard commit landed while
the pilot ran, so the Xarray treatment run used guarded skills while the other two did not (its
task is a multi-line fix the one-line skips deliberately do not cover).

---

## 3. LocBench — localization accuracy

**Source:** `bench/locbench/README.md`, `bench/locbench/dataset.lock`,
`bench/locbench/GATE_DECISION.md`, `bench/locbench/run_locbench.py`.

**Dataset.** `czlll/Loc-Bench_V1`, test split, **560 rows**, JSON SHA-256 pinned in `dataset.lock`.
The split is **repo-disjoint and salted** (a per-repository hash decides the side), so a repository
never appears in both halves: **train 317 instances across 87 repositories; held-out 243 across 78.**

**Metric.** Strict Acc@k as defined by LocAgent — an instance scores only if **all** gold locations
fall within the top k. Gold files are the files the fix patch touches; gold functions are the
dataset's own edit-function list, with added functions excluded from the denominator and reported
separately. Parse-coverage misses count as automatic misses. A lenient any-gold-in-top-10 and a
first-hit MRR are reported alongside, always labelled as the lenient variants.

### Held-out results (N = 243, zero exclusions, 564/564 scoped gold functions covered)

| Arm | file@1 | file@3 | file@5 | **file@10** | lenient@10 | fn-MRR |
| --- | --- | --- | --- | --- | --- | --- |
| routed `--for` (shipping) | 19.3% | 38.3% | 51.0% | **60.9%** | 74.9% | 0.213 |
| pre-routing baseline | — | — | — | 27.6% | 36.2% | 0.053 |

Stratified: single-file gold **73.4%** strict, multi-file **18.2%**. The single-vs-multi cliff is the
honest shape of this problem and it shows up on every corpus below.

**Paired deltas** across 243 instances in 78 repository clusters: **strict file@10 +33.33pp**, with a
**clustered-bootstrap 95% lower bound of +25.00pp**. Cost ledger for that gain: warm p50 +3.4%, cold
p50 +3.0%, index p50 +4.4%, and the production token ceiling p50 **−39.4%** — more accurate *and*
cheaper, which is why it shipped.

**Full 560-instance run:** `--for` file@10 **28.8%**, raw `--query` **4.6%**. Parse coverage
**1148/1149 = 99.9%**.

**`GATE_DECISION.md` is a proposal, not a policy.** It proposes a two-tier acceptance gate (an
absolute latency ceiling plus a separate quality-per-cost ratio), opt-in via `compare_runs.py
--gate=two-tier`; the default remains the legacy gate and is byte-identical. It says so on its own
first lines.

---

## 4. Ranking changes, measured

### Query-shape routing

Known-item retrieval over deterministically sampled doc-commented symbols, two synthetic queries per
symbol (the whole name; a stopworded phrase from the doc comment's first line), four rankers, gold
rank measured. Reproduce with `ripwire <dir> --eval-retrieval`. Recorded in `bench/ANSWERQUALITY.md`.

| Query shape | Before | After |
| --- | --- | --- |
| Name-shaped queries, `src/` — MRR | 0.859 | **0.993** |
| Name-shaped queries, `src/` — recall@1 | 76.7% | **98.7%** |
| Name-shaped queries, repository root — MRR | 0.725 | **0.929** |
| Name-shaped queries, repository root — recall@1 | 63.3% | **87.3%** |

The router is **confidence-gated**, and the gate is the interesting part: doc-phrase queries scored
**0.993** (`src/`) and **0.789** (root) with the gate, against **0.427** and **0.146** without it. An
ungated router routes the wrong queries. Both numbers are published together.

### Fixture and generated-path de-prioritization

**Source:** `test/recallevalcheck.sh` (the gate that records the baseline and enforces the ceiling),
`bench/recalleval/run_recalleval.py` (the metric).

*pollution@5* is the fraction of top-5 **slots**, over all queries in a lane, occupied by a
fixture, test-data, presentation, or generated-capture path. It is a slot fraction, not a per-query
rate, and the path predicate is spelled out in `run_recalleval.py`.

On the **adversarial query class** of the ranking lane — queries whose vocabulary lets a fixture
outrank the real source — pollution@5 was **28.0%** before the tier down-weight and is **0.0%**
after, with **recall up, not traded away**, and the recall lane byte-identical. The change is a
single path-tier multiplier in the ranking lenses, published rather than hand-tuned.

**Carry this caveat with that number, as the gate itself does:** *pollution 0 is a **ranking-lane**
claim only — it is not the recall lane's number, and it is not "every class".*

The bars the gate records, **re-baselined 2026-07-31 on the exported tree** (`test/recallevalcheck.sh`),
recall = 42 labels / ranking = 32 labels, zero skipped:

| Lane | strict r@1 | strict r@5 | lenient r@1 | lenient r@5 | strict MRR | lenient MRR | pollution@5 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **ranking** | 56.2 | 75.0 | 59.4 | 75.0 | 0.642 | 0.676 | **0.0** |
| **recall** | 52.4 | 88.1 | 57.1 | 92.9 | 0.669 | 0.720 | **10.0** |

**Why these are not the pre-export numbers, and why that is not a ranker regression.** The export
changed the corpus these lanes measure: the private tree carried roughly **70 real documents** against
its fixture markdown; this export ships about **27**, and 27 of the recall lane's 39 original labels
named documents it does not ship — so that lane was scoring almost nothing and its labels were
re-authored against the shipped documentation. **Zero ranker changes were made.** Two consequences are
recorded rather than chased: the recall lane's pollution rises to 10.0% because the fixture *share* of
any top-5 is structurally higher in a smaller document set (the harness now exempts any basename
`README.md` from the fixture predicate — a rule about READMEs, not a special case), and the ranking
lane moves slightly on unchanged labels because the export relocated source files, so a ranked set over
a different tree is a different measurement. The gate's ceilings and floors were widened to match, so
they measure a regression rather than the corpus.

**The recall lens has no fixture defense at all.** The path-tier de-prioritization was applied to the
ranking lenses only; the recall lane looked clean on the private corpus because real documents
outnumbered fixtures there. That gap is left visible on purpose.

### The recall lane scores a frozen corpus (2026-08-07)

**Source:** `bench/recalleval/make_snapshot.py` (freeze/verify), `bench/recalleval/snapshot.mdpack` +
`snapshot.lock` (the corpus and its pin), `test/recallevalcheck.sh` (the gate; its header carries the
full forensic record and the update policy).

The recall lane's floor was ratcheted **85→83→78→69 in five days** with the ranker provably neutral at
every step: the eval corpus was the live repository's own docs, so every documentation round moved BM25
length normalization and rank boundaries. The terminal case (gate header, 2026-08-07 entry): a gold
document *got longer* — 36 added lines containing none of the query's terms lowered its own score
through length normalization alone, off a pre-change margin of 0.010. A 42-label lane at 2.38pt
granularity over a live corpus measures corpus composition, not the ranker.

The fix is a corpus split, not another floor edit:

- **Frozen recall lane.** Every tracked `*.md` at the commit pinned in `snapshot.lock` (113 docs @
  `7a7f798`), packed into the single crawler-inert file `snapshot.mdpack` and unpacked into a temp root
  per run. On a frozen corpus with a deterministic binary, recall/MRR can move only when the ranker
  moves — a red floor is a ranker regression *by construction*. Integrity is a content hash
  (`corpus_sha256`, container-independent, no git history needed), enforced as the gate's check #0.
- **Live pollution probe.** The same 42 queries re-run against the live root, reporting pollution@5
  only (`recall_livepol`, ceiling 16% unchanged) — pollution@5 was stable through all five ratchet
  entries and remains the honest live-composition signal.
- **Ranking lane unchanged**, live: its labels are code symbols and its floors carry wide margins.

Frozen-corpus bars (baselines measured twice, byte-identical; floors sit two queries under baseline —
the gate's standing philosophy of floors loose enough to survive intentional improvement):

| Metric | Frozen baseline | Floor |
| --- | --- | --- |
| lenient recall@5 | 76.2% (32/42) | **71%** |
| lenient MRR | 0.619 | **0.57** |
| pollution@5 (frozen) | 5.2% | reported, not gated |

The frozen 76.2% is not comparable to the same-day live 78.6%: the frozen universe is markdown-only, so
corpus statistics differ — scores are comparable only *within* a snapshot generation. The MRR floor was
retained and recalibrated (its live margin, 0.613 vs 0.60, was the next casualty of the retired
mechanism); 0.57 against a frozen corpus is a tighter real bar than 0.60 against a drifting one.

**Update policy.** The snapshot is refreshed only in a deliberate recalibration commit that states why,
re-freezes (`make_snapshot.py --freeze`), re-measures the frozen baselines, and resets the floors — all
in one commit. Valid reasons: a label re-authoring that names a document the snapshot lacks (the
zero-skip guard forces this), or an owner-ruled representativeness refresh after a docs restructure.
**A red floor is never a reason to refresh.**

### Query-mention anchoring

A file, dotted module, or `Type.method` named literally in the task text is lifted just below the top
hit. It is on by default and byte-identical when the text names nothing indexed.

The reproducible in-tree ablations, both machine-generated scoreboards:

| Corpus | With anchor | Without | Delta |
| --- | --- | --- | --- |
| Multi-SWE-bench C++, n=121 scored, strict file@10 (`bench/multiswe/results/cpp_scoreboard.md`) | 55.4% | 53.7% | **+1.7pp** |
| …its single-file stratum, n=51, strict@10 | 86.3% | 82.4% | **+3.9pp** |
| SFML C++ commit-message queries (`bench/cppbench/results/sfml_scoreboard.md`) | — | — | **+0.0pp** |

**The corpus decides.** SFML's commit messages are terse and conventional (`Fixed X`, `Added Y`) and
rarely name a path, so the anchor has nothing to anchor and costs only wall time — published as a
zero. Issue-style prose that names files and symbols is where it earns its keep. The behavioral
contract (it signals what anchored; it never displaces the top hit; byte-identical when nothing is
mentioned; deterministic across three runs) is pinned by `test/mentioncheck.sh`.

---

## 5. Token and output economy

### `--pack-signatures`

Body-elided declaration skeletons, measured as **element bytes**: the signature-plus-doc elements
`--pack-signatures` emits, against the **same symbols'** full body elements from `--expand`, **with
the corpus-root prefix subtracted from both sides**.

That subtraction is the entire methodology, and the figure is meaningless without it. The root
repeats inside every element's `id=` and `p=`, it is charged in both forms, and it is *not what this
verb elides* — count it and the headline becomes a function of how deep your checkout happens to sit
on disk. On one corpus, three spellings of the same root read **18.6 points apart** before the
subtraction and agreed exactly after it.

**Root-neutralised on this repository (re-derived 2026-08-01):**

| Result size | Byte reduction |
| --- | --- |
| top-10 | 46.7% |
| **top-50** | **67.0%** |
| top-100 | 66.2% |

**Quote the top-50 figure.** The signature payload is top-50 regardless of `--top-k`, so it is what
the command actually emits. A "~70%" headline is reachable at larger N but overstates the smaller
shapes people actually run.

**And do not quote top-10.** It is the noisiest of the three by construction: ten symbols is a small
enough sample that a fixed byte change is a large share of the base. The 2026-08-01 re-derivation
dropped it from 59.1% to 46.7% with no change to the verb — and the mechanism is measured, not
guessed: the top-10 membership did not change at all (verified by running both binaries); what
changed is the body denominator. Slimming the game-math header removed four float overloads each of
`fastmath::min`/`max`, so `--expand`'s body side for the same ten symbols fell from 15 entries /
2,861 bytes to 11 / 2,170 while the signature side moved 12 bytes. A ~700-byte shift is 24% of a
2.9 KB top-10 base and noise on a 28 KB top-50 base. Against the previously *published* numbers,
top-50 moved 1.4 points; top-100's published 66.5 was itself 0.5 stale inside the gate's ±1.5-point
tolerance (the pre-change binary measured 67.0), so the true binary-to-binary top-100 movement is
0.8. The sample-size sensitivity is the finding; it is why the headline is the top-50 number.

**This is gated, not asserted.** `test/showcasecapturecheck.sh` re-derives all three figures from
this repository on every run, in the same quantity as the caption, and fails if the caption and the
recount drift more than 1.5 points apart — plus a separate 55–72% regression band at top-50. The
documentation cannot silently diverge from the binary.

See §7 for the case where this verb makes output **larger**.

### Token cost against a naive read

**Source:** `bench/BENCHMARK.md`. **Carry its own caveat:** measured 2026-06-20 on a large private
C++ corpus — *historical, private, not publicly reproducible*. Every figure below inherits that.

- **96.0% fewer tokens (24.9×)** across six realistic agent questions — 14,758 tokens against
  367,192, counted with tiktoken `cl100k_base`. The baseline is the naive thing an agent does without
  the tool: a raw recursive grep dump for "who calls X", whole-file reads for orientation.
- **9–42× faster than Aider's repo map** cold-to-cold across five repositories (11.3× / 19.1× / 9.1× /
  31.6× / 42.0×). Same algorithm on both sides — tree-sitter parse then PageRank — so the gap is
  compiled versus interpreted. Aider's tag cache was cleared each run; minimum of N runs.
- **Whole repository (1,560 files): ~1 s cold, 0.18 s warm**, against Aider's 40 s cold map.
- **`--grep` is +19.7% / −11.2%** — published deliberately as the anti-headline. `--grep` is not a
  token reducer, and saying so is cheaper than being caught.

The benchmark states its own scope limit, and it is worth repeating verbatim in spirit: the token
baseline is *a model of a naive agent read* — a documented, auditable proxy, not a live agent trace —
and these numbers prove **cheaper and faster, not better outcomes**.

---

## 6. Correctness and quality instruments

### The gate suite

`test/regression.sh` is the authoritative list. It runs three tiers: inline contract checks
(determinism run four times for byte-identity, cache transparency, the golden snapshot, architecture
tags, wrap, stable-order defaults), five individually invoked standalone gates, and a single loop
naming **363 gate scripts**, all of which exist on disk.

`python3 test/pargates.py . ./build/ripwire -j 6` runs the same scripts in parallel so a full
verification fits in one sitting. It does not modify `regression.sh`.

`test/manifestcheck.sh` fails if a committed top-level `*check.sh` is missing from `regression.sh`,
so the list cannot rot.

### The differential argv harness

`test/argvdiffcheck.sh` proves a refactor changed nothing observable: it runs a reference binary and
the candidate over every argv vector and requires **stdout, stderr and exit code to be byte-identical**
for each. The only normalization is line numbers inside degrade-alert text, with the reason stated in
the script.

The vector matrix is **assembled at runtime from five independent sources** — the flag surface,
empty-value forms, combination guards, a harvest of command lines from the generated command capture,
and a literal block — and the gate asserts a **floor of ≥250 vectors** rather than a fixed count, so
adding surface grows the matrix instead of stranding it. It skips (exit 0) when no reference binary
is given, self-tests that its differ can see a known difference, and asserts it left the tree
unmodified.

### `--quality-delta`'s ten measured failure modes

These are the exact `kind=` strings the binary emits, from `src/quality.h`:

`complexity` · `verbosity` · `nesting` · `params` · `duplication` · `dead-code` · `api-surface` ·
`error-masking` · `short-horizon-churn` · `new-clone-of-reused-helper`

Note that some user-facing summaries abbreviate four of these (`dup`, `dead`, `churn`,
`clone-of-reused-helper` / `reuse-decline`). **Match against the strings above** when grepping real
output.

The verb reports only what a change made *worse*, against git HEAD. `--quality-ack` records a
reviewed exception; `--ack-only=KIND` scopes it.

### Co-change: the finding that contradicted the obvious design

**Source:** `bench/ANSWERQUALITY.md`. Reproduce with `ripwire <repo> --eval`. Method: for real
historical multi-file commits, given one seed file, does the tool surface the *other* files that
commit touched? Gold is git's own co-changed set; the seed is the most-symbol file; recall@k of the
rest, averaged over the last 80 qualifying commits. LLM-free, deterministic, leave-the-seed-out.
Private C++ corpus, 1,574 files.

| Ranker | recall@5 | recall@10 | recall@20 |
| --- | --- | --- | --- |
| Lexical (BM25 over bodies) | **40.3%** | 46.2% | 53.2% |
| BM25 over whole names | 34.4% | 52.3% | 59.1% |
| PageRank | 3.8% | 6.4% | 6.4% |
| Same directory | 1.8% | 5.8% | 8.6% |
| Random | 0.3% | 0.6% | 1.3% |

**Relatedness is lexical; importance is structural.** PageRank is the wrong ranker for co-change, and
*fusing* structure into the lexical ranker made it worse (7.7% at 5, against 40.3% lexical alone).
The result is published because it constrains the design: the graph answers "what is load-bearing",
not "what changes together", and the tool uses different machinery for each.

### End-to-end agent A/B

Two injected bugs, two arms, scored by whether the release test build exits 0 in isolated worktrees:
**~25% fewer tokens (88k against 118k), 2/2 resolved in both arms.** The record labels itself
**N = 2, directional, not significant**, and states the honest reading: the tool did not change
*whether* the fix happened, it changed *how cheaply*.

---

## 7. Honest counterexamples

Every one of these is measured, in-tree, and published on purpose.

**`--pack-signatures` can make output bigger.** On this repository, `svector::push_back`:

| Form | Bytes |
| --- | --- |
| Signature + doc comment, as emitted | **303** |
| Full body source | **158** |

A signature plus its doc comment is nearly **twice** the size of a short body. The headline reduction
is a property of large result sets, not of every symbol — and a small, trivial body inverts it. The
same inversion applies to the columnar output format. *(Re-derived on this corpus, 2026-07-31.)*

**The mention anchor is worth +0.0pp on the wrong corpus.** SFML commit-message queries: no gain,
only wall-clock cost. See §4.

**`--grep` costs more tokens than it saves** (+19.7% / −11.2%). See §5.

**PageRank is a bad co-change ranker** (3.8% at recall@5 against 40.3% lexical), and fusing it into
the lexical ranker made things worse. See §6.

**Strict multi-file localization is hard and stays hard.** Held-out LocBench: single-file gold 73.4%,
multi-file **18.2%**. Multi-SWE-bench C++: single-file 86.3%, multi-file **32.9%**. SFML C++:
single-file 43.1%, multi-file **7.0%** (at `d411f3de4`, split by `primary_files` in
`bench/cppbench/results/sfml.json`). Every corpus shows the same cliff. Complete-blast-radius
retrieval on large patches is open headroom, not a solved problem.

**The public C++ number is materially lower than the retired private one was.** SFML: strict file@10
**28.7%**, any@10 **41.7%**, first-hit MRR **0.21** — measured at commit `d411f3de4`
(`bench/cppbench/results/sfml_scoreboard.md`, n_scored=115). Until 2026-08-07 this paragraph compared
against a private corpus (~89% any@10, 0.62 MRR) that is no longer reproducible from this tree — its
long, identifier-dense commit messages were an easier retrieval shape than SFML's terse changelog
summaries, exactly the non-portable claim the caveats warn about, and that comparison is retired.
**The public number is the baseline going forward.**

**`--cochange surprising="1"` was calibrated against the paper it reimplements, and roughly a third of
what it flags is intentional coupling.** The predicate is Clio's modularity violation
(Wong/Cai/Kim/Dalton, ICSE 2011 — [`LINEAGE.md`](LINEAGE.md) §2), and Clio publishes **66% precision on
Hadoop Common** (152/231 confirmed) and **40% on Eclipse JDT** (161/399). Those are the expected band,
so the predicate was measured against it rather than assumed to clear it.

Corpus: the same private 1,648-commit C++/Objective-C++ tree both times (commit count re-verified
against the working copy's own git history, unchanged), default 18-month window, `together>=3`. Method:
`--cochange --pack-top-n=200000 --no-cache`, categories assigned by path (a pair counts as test-coupling
when exactly one side matches `test`/`spec`/`harness`/`bench`).

**Correction (2026-08-05): the first measurement below was taken on an index with a capture gap.** The
include extractor did not see an `#include`/`#import` nested inside `#if`/`#ifdef` — including every
classic `#ifndef FOO_H` include-guarded header — so a guard-wrapped file read as having almost no
dependencies and its true dependents falsely showed `surprising="1"`. Fixed in `ba82324`
(`captureIncludes` now descends into preprocessor-conditional containers; `kParserVer` 39→40). The
worked example the original writeup named, `levelEdit2/LevelEditor.cpp`/`.h` (76 directives, 75 of them
inside `#if LEVELEDIT`, only 1 previously captured), no longer emits `surprising="1"` for that pair —
confirmed by re-running both a pre-fix (`kParserVer` 39) binary (built from `ba82324~1` in a
throwaway worktree) and the current (`kParserVer` 40) binary against the identical corpus state. The
pre-fix row is kept below rather than silently overwritten, per this repo's own honesty rule.

| | pairs above the floor | `surprising="1"` | dependency-capable | flagged share |
| --- | ---: | ---: | ---: | ---: |
| no recurrence filter — **pre-fix** (`kParserVer`≤39) | 935 | 253 | 423 | 59.8% |
| no recurrence filter — **current** (`kParserVer`=40) | 935 | **221** | 423 | **52.2%** |
| `--cochange-recur=2` — pre-fix | 315 | 140 | 221 | 63.3% |
| `--cochange-recur=2` — current | 315 | **121** | 221 | **54.8%** |
| `--cochange-recur=3` — pre-fix | 98 | 47 | 86 | 54.7% |
| `--cochange-recur=3` — current | 98 | **40** | 86 | **46.5%** |

`dependency-capable` and `pairs above the floor` are untouched by the fix — it only changes which
already-dependency-capable pairs still look `surprising`. Retired: 32 of 253 (no recurrence), 19 of 140
(recur=2), 7 of 47 (recur=3) — zero new rows appeared at any recurrence level.

**That 52.2% is a *yield*, not a precision, and the two must not be compared directly.** Precision needs
confirmed-defect ground truth — Clio used issue trackers and developer confirmation — and no such oracle
exists for this corpus. What the composition *does* support is an upper bound. Of the 221 flagged pairs,
**79 (35.7%) are test↔subject or test↔test pairs**: a test moving with the code it tests is intentional
coupling, not a design defect, and Clio would not count it. Excluding that class alone caps precision at
**≤64.3%** — now sitting *below* Clio's Hadoop figure and still well above its JDT figure, i.e. squarely
inside the 40%–66% band rather than a hair above its upper edge. **So the honest verdict changed, not
just the number: pre-fix the tool looked like it barely cleared Clio's better corpus; post-fix it reads
as comfortably inside the band Clio itself reports** — a more defensible claim, and a more conservative
one, not the "even better than we thought" reading the raw 13%-of-population-was-artifact framing might
suggest. The reason the ceiling *fell* rather than rose: of the 32 retired false positives, only 3 were
test-coupling pairs — 29 were subject↔subject pairs that the guard-wrapped-include bug had misclassified
as design defects. Removing them shrank the "genuine-looking" numerator (171→142) faster than it shrank
the test-coupling denominator-contributor (82→79), which is why the *share* of test-coupling within
what's left rose slightly even as its raw count fell.

**Recurrence cuts volume, not composition — the two filters are still orthogonal, re-confirmed.**
`--cochange-recur=2` removes 45% of the flagged pairs both before and after the fix (253→140 pre-fix,
221→121 post-fix — 45.2% either way), and the test-coupling share stays close before/after recurrence
filtering too: 35.7% unfiltered vs 36.4% at recur=2 (was 32.4%/32.9% pre-fix). Recurrence is therefore
still not a substitute for excluding intentional relations. **The largest remaining precision-gain lever
is unchanged, and looks slightly bigger, not smaller, on the repaired index**: test↔subject/test↔test
pairs are 35.7% of what's currently flagged (79/221) versus 32.4% (82/253) before the fix — a bigger
*share*, even though the *count* dropped (82→79, only 3 of the 32 retired pairs were test-coupling; the
other 29 were subject↔subject pairs the guard-wrapped-include bug had misclassified). Classifying those
79 pairs correctly is still the single largest lever available — larger than anything recurrence
filtering can do to composition — and is recorded here as open headroom, not as a shipped filter.

**Two ranking experiments produced no confirmed lift and did not ship.** `--anchor` and
`--cochange-boost` are dropped from `--help` and refuse to run without an explicit development
environment variable. One anchor-expansion candidate scored **+0.41pp** paired with a 95% lower bound
of **+0.00pp** and was rejected outright by the acceptance gate. A negative result recorded is worth
more than a feature shipped on a hunch.

---

## 8. Claims this project does *not* publish

Listed because the reason is more useful than the silence.

- **"~76% of an agent's token cost is file reads."** This figure appeared in a skill description in
  this repository, with **no citation** while every neighbouring claim in the same paragraph carried
  one, and it has since been removed — it has no in-tree provenance today. The research note it
  referenced does not ship here. Until a source can be named, it is not a published number.
- **"+66.7% held-out strict@10" for the mention anchor.** The 66.7% figure that circulates is an
  *absolute* strict file@10 belonging to the *baseline* arm of a *different* experiment
  (anchor-hop expansion, held-out slice, n=243), and that experiment's candidate was **rejected and never
  shipped**. See `bench/locbench/anchorhop_calib.json`. The mention anchor's reproducible numbers are
  the ablations in §4.
- **A single round gate-count.** Two in-tree numbers disagree (`test/pargates.py`'s docstring says
  ~210; `test/argvdiffcheck.sh` says 200+), while the loop in `test/regression.sh` names 365. The
  loop is the authority; the stale docstrings are a known drift. `test/manifestcheck.sh` asserts this
  very number against the loop's actual length, so it cannot go stale silently again.
- **"282 argv vectors."** The gate asserts a floor of ≥250 assembled from five sources; 282 was a
  point-in-time snapshot. Quote the floor, not the snapshot.
- **"~70% fewer bytes" for `--pack-signatures`**, unqualified. See §5 — quote the root-neutralised
  top-50 figure with its methodology, or do not quote it.
- **"75× warm re-runs."** That was the incremental cache's *parse-phase* figure quoted without the
  qualifier. End-to-end warm command latency measures **8.2×** on the same historical private corpus.
- **The earlier private C++ localization numbers** (file@10 38.5%, any@10 88.9%, MRR 0.621). The
  corpus was removed for public release and those numbers are no longer reproducible from this tree.
  Superseded by the SFML figures in §7.

---

## 9. Ensemble family calibration — the measurement a preset must be derived from

`--ensemble` joins four evidence families and ranks by the **count of distinct families that fire**,
never by a weighted composite. That design is only worth something if the families are genuinely
orthogonal; if they correlate, the join is one signal wearing four hats. This section is the
measurement that decides it, and the measurement any named preset has to be derived from rather than
chosen. **It ships no new rule and no new metric** — every number below comes out of `--ensemble`,
`--readability` and `--metrics` through their existing entry points, parsed from their own XML by
`bench/ensemblecal/run_ensemblecal.py`. Measured 2026-08-06 with the binary built at
`integration/all` `61c6b54`.

**Verdict up front: the ensemble premise HOLDS.** The largest cross-family correlation anywhere in
the data is **φ = +0.278**, and pooled over the independent corpora no pair exceeds **+0.168**. The
families are not restatements of each other. Two other results are less comfortable and are stated
with equal weight: the **historical** family is too unstable across commits to carry a gate, and the
**confusion** family reported itself as measured on corpora where it cannot fire at all. The second of
those has since been **fixed** — see §9.6 defect 1; the numbers in this section are the pre-fix
measurement that found it, and are left as measured.

### 9.1 Corpora — and the overfitting caveat, stated first

A preset derived from one codebase overfits to that codebase's conventions. Nine trees were reached;
only five are **independent evidence**, and every pooled number below pools exactly those five.

| Corpus | Files | Symbols | Edges | Eligible fns | HEAD | Dominant languages (indexed files) |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| **ripwire** | 977 | 7 373 | 9 490 | **4 672** | `61c6b54` | Bash 354, C/C++ hdr 154, C++ 136, md 104, Python 68 |
| **tree-sitter (vendored)** | 113 | 2 936 | 2 994 | **1 538** | `61c6b54` | C/C++ hdr 55, C 30 — third-party, largely generated |
| **gameA** | 2 376 | 42 918 | 38 391 | **17 157** | `0534e79` | C/C++ hdr 692, md 671, C++ 620, ObjC++ 50, Metal 42 |
| **rustCLI** | 250 | 6 004 | 6 020 | **4 068** | *(no git)* | Rust 115, md 75, Bash 11, TS 8 |
| **appleXR** | 320 | 1 860 | 582 | **454** | *(no git)* | json 158, Swift 49, C/C++ hdr 45, ObjC 40, Metal 13 |
| *ripwire-src* | 95 | 2 795 | 7 929 | *1 958* | `61c6b54` | a **subset of ripwire** — not independent |
| *ctxpack* | 920 | 7 476 | 8 312 | *4 027* | `b5ac9f2` | ripwire's **pre-cutover ancestor** — shared lineage |
| *gameA-later* | 4 075 | 59 350 | 39 152 | *17 552* | `86a6dbb7` | a later **snapshot of gameA** |
| *gameA-earlier* | 734 | 15 006 | 17 235 | *8 935* | `dabfaf0` | an earlier **snapshot of gameA** |

`third_party` is a default-skipped crawl directory (`src/ingest.h`), so the ripwire and tree-sitter
corpora are disjoint by construction rather than by an `--exclude`.

`gameA`, `rustCLI` and `appleXR` are **private local trees, named here by shape rather than by name**
— a game engine in C++/ObjC++/Metal, a Rust CLI, and a Swift/ObjC/Metal app. They cannot be
redistributed, so their rows are reproducible by this project and by nobody else; that is a real
limit on this section and it is why the two corpora that *are* in this repository (ripwire and the
vendored tree-sitter grammars) are reported beside every private one.

**Pooled independent denominator: 27 889 eligible functions across 5 trees**, spanning C, C++,
ObjC/ObjC++, Metal, Rust, Swift, Python, TypeScript and Bash. That is a real language spread, but it
is **five projects from two authoring populations** (this project's own lineage, one game tree, one
vendored parser set, two Apple-platform trees), all reachable on one machine. No public
multi-org corpus was fetched. **A preset derived from this is calibrated, not universal**, and the
numbers below should be re-derived on any tree where it is deployed as a gate — which is Arcan's own
`Max(this-system, benchmark)` posture, not a substitute for it.

### 9.2 Per-family distribution, and where the shipped thresholds actually sit

**Fire rate over the eligible denominator** (functions/methods with a body):

| Corpus | eligible | structural | lexical | confusion | historical |
| --- | ---: | ---: | ---: | ---: | ---: |
| ripwire | 4 672 | 558 · 11.94% | 900 · 19.26% | 107 · 2.29% | 1 044 · 22.35% |
| tree-sitter | 1 538 | 190 · 12.35% | 426 · 27.70% | 57 · 3.71% | 55 · 3.58% |
| gameA | 17 157 | 2 170 · 12.65% | 1 676 · 9.77% | 613 · 3.57% | 892 · 5.20% |
| rustCLI | 4 068 | 292 · 7.18% | 1 303 · 32.03% | **0 · 0.00%** *(now UNAVAILABLE)* | **UNAVAILABLE** |
| appleXR | 454 | 45 · 9.91% | 16 · 3.52% | 7 · 1.54% | **UNAVAILABLE** |
| *ripwire-src* | *1 958* | *482 · 24.62%* | *55 · 2.81%* | *101 · 5.16%* | *558 · 28.50%* |
| *ctxpack* | *4 027* | *503 · 12.49%* | *825 · 20.49%* | *94 · 2.33%* | *874 · 21.70%* |
| *gameA-later* | *17 552* | *2 257 · 12.86%* | *1 690 · 9.63%* | *629 · 3.58%* | *781 · 4.45%* |
| *gameA-earlier* | *8 935* | *1 111 · 12.43%* | *929 · 10.40%* | *291 · 3.26%* | *57 · 0.64%* |

**Cross-corpus spread (max ÷ min over the independent five, non-zero corpora only):** structural
**1.76×**, confusion **2.40×**, historical **6.25×**, lexical **9.09×**. Structural is the portable
one; lexical is the least portable, and §9.6 explains why.

**The four absolute structural bars are already percentile-calibrated — by accident, and tightly.**
A symbol appears in a row's `why=` string exactly when its value crossed a bar, so the crossing
count over `eligible=` is the bar's exact exceedance, i.e. the percentile at which the shipped
constant sits in that corpus's own distribution:

| Bar | ripwire | tree-sitter | gameA | rustCLI | appleXR | band |
| --- | --- | --- | --- | --- | --- | --- |
| `ccx >= 15` | P91.59 | P92.52 | P95.35 | P95.55 | P98.24 | **P91.6 – P98.2** |
| `loc >= 60` | P93.99 | P95.19 | P94.87 | P96.12 | P96.26 | **P94.0 – P96.3** |
| `nest >= 4` | P95.55 | P93.76 | P96.32 | P95.65 | P99.12 | **P93.8 – P99.1** |
| `params >= 5` | P95.89 | P95.58 | P93.44 | P99.09 | P99.12 | **P93.4 – P99.1** |

`loc >= 60` is the striking one: **a constant invented years ago in someone else's style guide lands
inside a 2.3-percentile-point band across C++, Rust, ObjC++, Swift and generated C.** A
percentile-derived replacement would be a rename of the number it replaces. This is the empirical
answer to "should the bars be percentile-derived instead of invented" — **on this evidence they
should not be changed**, and a preset should spend its degrees of freedom on *selection* instead.

For anyone who does want to re-derive them, the full CDFs are in the harness output; the headline
values (from `--metrics`, whose fn/method universe is close to but not identical to the ensemble's
eligible set — the per-corpus `n` is printed so the gap is visible):

| Metric | corpus | n | P50 | P75 | P90 | P95 | P99 | max |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ccx | ripwire | 4 920 | 0 | 3 | 12 | 21 | 77 | 724 |
| ccx | gameA | 21 092 | 0 | 1 | 5 | 11 | 38 | 592 |
| ccx | rustCLI | 4 069 | 0 | 1 | 6 | 13 | 39 | 218 |
| loc | ripwire | 4 920 | 4 | 15 | 38 | 66 | 185.7 | 1 629 |
| loc | gameA | 21 092 | 4 | 11 | 30 | 50 | 137 | 2 722 |
| loc | rustCLI | 4 069 | 9 | 18 | 35 | 54 | 110.3 | 1 115 |

**The two ordinal signals are NOT deciles, on any corpus that matters.** The readability and churn
halves fire for "the worst decile of their own ranking, bounded above by 40 rows". The bound wins
almost everywhere:

| Corpus | readability cut | realized | churn cut | realized |
| --- | --- | ---: | --- | ---: |
| ripwire | 40 / 4 672 | **0.86%** | 40 / 977 | 4.09% |
| tree-sitter | 40 / 1 538 | 2.60% | 12 / 113 | 10.62% |
| gameA | 40 / 17 157 | **0.23%** | 40 / 1 810 | 2.21% |
| rustCLI | 40 / 4 068 | 0.98% | — | n/a |
| appleXR | 40 / 454 | 8.81% | — | n/a |

On gameA the "worst decile" is a **0.23% cut — 43× tighter than a decile**. The legend does
publish `rcut=`/`rmeasured=`, so a reader *can* compute this; the word "decile" is nonetheless wrong
above ~400 functions and is a documentation defect, not a measurement one.

### 9.3 Cross-family correlation — the orthogonality test

φ (Pearson on the two binary indicators = the phi coefficient) over the full eligible denominator,
so non-firing symbols are counted, not dropped. Pooled over the five independent corpora:

| | structural | lexical | confusion | historical |
| --- | ---: | ---: | ---: | ---: |
| **structural** | 1.000 | −0.060 | **+0.168** | +0.127 |
| **lexical** | −0.060 | 1.000 | −0.039 | −0.044 |
| **confusion** | +0.168 | −0.039 | 1.000 | +0.047 |
| **historical** | +0.127 | −0.044 | +0.047 | 1.000 |

with the 2×2 counts behind each cell (n11 / n10 / n01 / n00 over 27 889, except the historical row
whose denominator is the 23 367 symbols in the three corpora where git could be mined):

| pair | φ | n11 | n10 | n01 | n00 | Jaccard |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| structural × lexical | −0.060 | 310 | 2 945 | 4 011 | 20 623 | 0.043 |
| structural × confusion | +0.168 | 340 | 2 915 | 444 | 24 190 | 0.092 |
| structural × historical | +0.127 | 523 | 2 395 | 1 468 | 18 981 | 0.119 |
| lexical × confusion | −0.039 | 57 | 4 264 | 727 | 22 841 | 0.011 |
| lexical × historical | −0.044 | 160 | 2 842 | 1 831 | 18 534 | 0.033 |
| confusion × historical | +0.047 | 121 | 656 | 1 870 | 20 720 | 0.046 |

**Per-corpus maxima by |φ|:** ripwire +0.262 (structural × historical), tree-sitter +0.167
(structural × confusion), rustCLI −0.166 (structural × lexical), gameA +0.161 (structural
× confusion), appleXR ≤ 0.024; among the non-independent extras, ctxpack +0.278 — the largest value
anywhere in the study. **Every pair on every corpus is |φ| < 0.28, most are < 0.17, and the largest
Jaccard overlap between any two families is 0.119 pooled (0.221 on any single corpus).**

**Conclusion, plainly: the four families are near-orthogonal and the ensemble premise is confirmed.**
At n = 27 889 a φ of 0.168 is statistically far from zero — it is a real effect, not noise — but it
is a *small* one: knowing that a symbol tripped the structural family raises the odds it also tripped
confusion, and the two still disagree on 3 359 of the 3 699 symbols either one flags. The one
directional reading worth recording is that **the two largest positive correlations both involve
`structural`** (+0.168 confusion, +0.127 historical), and both have a mechanical explanation: a long
function has more room to contain a confusing construct, and a heavily-churned file tends to hold the
big functions. Pooled, `lexical` is negatively correlated with all three others — the strongest single
piece of evidence that identifier text is a genuinely different axis from code shape. (It is not
negative on every corpus: on the vendored tree-sitter grammars lexical × historical is +0.155 and
lexical × structural +0.112, both still small.)

Had this come out the other way — several pairs above ~0.6 — the honest response would have been to
delete the join and keep one family. It did not, and the numbers are published so a future round can
check whether that stays true as the rules change.

### 9.4 Co-firing distribution

Pooled over the five independent corpora (n = 27 889):

| families firing | symbols | share |
| ---: | ---: | ---: |
| 0 | 18 904 | 67.78% |
| 1 | 7 761 | 27.83% |
| 2 | 1 085 | 3.89% |
| 3 | 136 | 0.49% |
| 4 | **3** | **0.011%** |

and the combinations, which is where the useful shape is:

| n | combination | symbols | share |
| ---: | --- | ---: | ---: |
| 1 | lexical | 3 852 | 13.81% |
| 1 | structural | 2 224 | 7.97% |
| 1 | historical | 1 305 | 4.68% |
| 1 | confusion | 380 | 1.36% |
| 2 | structural + historical | 408 | 1.46% |
| 2 | structural + lexical | 255 | 0.91% |
| 2 | structural + confusion | 229 | 0.82% |
| 2 | lexical + historical | 129 | 0.46% |
| 2 | confusion + historical | 34 | 0.12% |
| 2 | lexical + confusion | 30 | 0.11% |
| 3 | structural + confusion + historical | 84 | 0.30% |
| 3 | structural + lexical + historical | 28 | 0.10% |
| 3 | structural + lexical + confusion | 24 | 0.09% |
| 4 | all four | 3 | 0.011% |

Three consequences a preset has to respect:

1. **`fam=4` is not a tier, it is a rounding error.** Three symbols in 27 889. Any preset cut at
   K ≥ 4 is a preset that outputs nothing, on every corpus measured.
2. **Every multi-family combination containing `structural` outranks every one that does not.** The
   least common 2-combination *with* structural (structural + confusion, 229) still beats the most
   common one *without* (lexical + historical, 129); `structural` is in 7 of the 10 observed
   multi-family combinations and in all three of the top three. Corroboration in practice means
   "shape plus something".
3. **The ladder is steep and clean**: 27.83% → 3.89% → 0.49% → 0.011%, roughly 7×, 8× and 45× per
   rung. That is what a preset ladder can be cut from without inventing a number.

### 9.5 Stability across commits — one family cannot support a gate

The instrument is fixed and the corpus varies: **one binary, run over the same repository at a ladder
of past commits** in a throwaway clone. Comparisons are restricted to symbols present in *both*
trees, so added and deleted code cannot masquerade as instability.

| Ladder | commits | sampled | span (committer dates) |
| --- | ---: | ---: | --- |
| ripwire | 148 first-parent | every ~18 | 2026-07-31 → 2026-08-05 |
| ctxpack | 792 first-parent | every ~99 | 2026-06-20 → 2026-08-05 |
| gameA | 1 620 first-parent | every ~202 | 2026-06-03 → 2026-07-21 |

Jaccard of each family's flagged symbol set, consecutive sampled commits (mean) and oldest-vs-newest
(endpoint):

| Family | ripwire | ctxpack | gameA | consecutive range | endpoint range |
| --- | --- | --- | --- | --- | --- |
| lexical | 1.000 / 0.999 | 1.000 / 1.000 | 1.000 / 0.999 | **1.000** | **0.999 – 1.000** |
| structural | 0.995 / 0.965 | 0.965 / 0.859 | 0.990 / 0.939 | 0.965 – 0.995 | 0.859 – 0.965 |
| confusion | 0.997 / 0.981 | 0.920 / 0.684 | 0.990 / 0.947 | 0.920 – 0.997 | 0.684 – 0.981 |
| historical | 0.841 / 0.546 | 0.862 / 0.525 | 0.800 / 0.426 | **0.800 – 0.862** | **0.426 – 0.546** |

**`historical` jitters an order of magnitude harder than the other three, on all three histories.**
Per-symbol flag-flip rate per sampled step: structural 0.06–0.66%, lexical 0.00%, confusion
0.01–0.45%, **historical 1.21–6.67% (peak 32.99% on one ctxpack step)**. Endpoint to endpoint the
historical sets overlap by Jaccard 0.426–0.546; on gameA, **161 of the 401 still-present symbols it
flagged in June (40%) were no longer flagged in July**, on code that did not change between the two
commits. This is not a bug — churn
is a moving 12-month window and the family fires on the worst-ranked *files*, so a single busy week
reshuffles the cut — but it is disqualifying for a gate. `lexical` sits at the opposite pole: it is a
pure function of the identifier text, so it is exactly stable, and it moves only when someone renames
something.

**Honest limits of this pass.** All three histories are dense but short in wall-clock (5–50 days), so
every sampled commit's 12-month churn window contains the whole history; a longer-lived repository
would show *less* churn-cut movement per commit. The ctxpack endpoint figures are the least reliable
row in the table — that tree grew from 208 to 4 027 eligible functions across the window, leaving a
177-symbol surviving universe at the endpoint. Stability was measured on three repositories, two of
which share a lineage; it was **not** measured on rustCLI or appleXR, which have no git history
at all.

### 9.6 What the measurement found wrong

Three defects. The measurement pass itself shipped no behaviour change; defect 1 has since been fixed on
its own branch and its entry below records that, so the table above stays the number that found it.

1. **`confusion` reports itself measured on corpora where it cannot fire.** The atom rules are gated
   to C/C++/ObjC (`src/atoms.h::isCFamilyPath`). On rustCLI — 115 Rust files, 4 068 eligible
   functions — the family fires **0 times**, and it is nowhere in `unavailable=`: the root names only
   `historical`, and every row counts confusion inside its `of="3"`. So the verb states, in its own
   vocabulary, that three families were evaluated and two of them found nothing, when the truth is
   that one of the three could not apply to a single file in the corpus. The verb's own header says
   *"a family that could not be MEASURED is reported as unavailable… a missing measurement must never
   read as a clean bill of health"* — this is exactly that case, and `historical`'s handling on the
   same corpus is the correct behaviour standing right beside the incorrect one. It also makes φ
   undefined for both confusion pairs there.

   **FIXED.** `src/ensemble.h` now carries a language-coverage precondition on the confusion family —
   the same shape `historical` already had for a missing git history — decided per corpus from what was
   indexed, by calling the atom pack's own `atoms::isCFamilyPath` rather than a second copy of its
   extension list. A corpus with no eligible function in a C-family file reports
   `unavailable="confusion"` with a reason, and every row's `of=` drops accordingly, so `fam=4` is
   unreachable there by construction instead of by coincidence. Two supporting changes fell out of it:
   `unavailable_why=` now carries **one reason per unavailable family** (a single slot kept whichever
   wrote last, so a Rust tree outside a repository — both families missing — would have shipped one of
   the two silently), and the root discloses `cfiles=`/`cscope=`/`lscope=` so the verdict is auditable
   from the output. The `lexical` family was audited for the same defect and given the same
   per-corpus precondition; `structural` has none to give — its bars and its Posnett rank are computed
   for every language. Gate: `test/ensembleavailcheck.sh`, which asserts the verdict on a git-backed
   pure-Rust corpus, the inverse on a C corpus where the family must actually FIRE, both families
   unavailable at once on a non-git Rust corpus, and — the mutation arm — that adding ONE C file to the
   Rust corpus moves the verdict back.
2. **"Worst decile" is not a decile.** See §9.2 — the realized readability cut ranges 0.23%–8.81%.
   The numbers needed to compute it are published; the word is wrong.
3. **The briefed first data point does not reproduce.** The distribution circulating for ripwire's
   own `src/` — `fam=1: 696, fam=2: 217, fam=3: 51, fam=4: 6` — was re-measured on a clean tree at
   three candidate revisions and came out **`fam=1: 696, fam=2: 202, fam=3: 32, fam=4: 0`** at
   `61c6b54` (`src/`), `687 / 200 / 31` at `c136726` (`src/`), and `1 797 / 287 / 55` at `c136726`
   (repo root). `fam=1` matches exactly while every higher rung differs, which is the signature of a
   different **churn** state: a different top-40 churn cut moves symbols that already had one family
   from `fam=1` to `fam=2` while moving an equal number of unflagged symbols up into `fam=1`. The
   figure used everywhere in this section is the re-measured one.

A fourth observation is not a defect but changes how `lexical` should be read: **the family is
dominated by a different single rule on every corpus.** ripwire `naming-short` 793 of 900 (88%);
tree-sitter `naming-underscore` 240 and `naming-wordy` 159 of 426; gameA `naming-confusable`
824 of 1 676 (49%); rustCLI `naming-wordy` 1 252 of 1 303 (96%) — Rust's descriptive snake_case
idiom, flagged as verbosity. **`lexical` is measuring house naming convention at least as much as
naming quality**, which is the mechanism behind its 9.09× cross-corpus spread and the reason it must
never be the sole family behind a flag.

### 9.7 Proposed presets — derived, with the arithmetic

Presets select **which families count** and **how many must agree**. There is no weight anywhere: a
weighted composite is the Maintainability-Index failure mode this design exists to avoid.

**The selection criteria, fixed before the presets and taken from the measurements above:**

- **C1 — stability.** A family may gate only if its flagged set survives development. Measured mean
  consecutive Jaccard: lexical 1.000, structural 0.965–0.995, confusion 0.920–0.997, historical
  0.800–0.862. The four values form three clustered and one outlier; the observed gap is
  **(0.862, 0.920)**, and any cut inside it selects the same three families. **⇒ `historical` is
  excluded from the gating preset.** It stays in the reporting presets, where a moving window is a
  feature.
- **C2 — non-degeneracy.** A preset must have a non-zero yield on every corpus measured, or it is
  unavailable rather than clean. This kills every rule that *requires* `confusion`
  (`structural+confusion K≥2` yields **0.00%** on rustCLI) and every rule at K ≥ 3 over the
  stable three (**0.00%** on rustCLI and appleXR).
- **C3 — the rungs come from the measured ladder**, not from a target yield picked in advance. §9.4's
  histogram summed from the top gives the cumulative cuts directly: `fam ≥ 1` = 27.83 + 3.89 + 0.49 +
  0.011 = **32.22%**, `fam ≥ 2` = 3.89 + 0.49 + 0.011 = **4.39%**, `fam ≥ 3` = 0.49 + 0.011 =
  **0.50%**, `fam ≥ 4` = **0.011%**. Two of those four are usable: `fam ≥ 4` is three symbols, and
  `fam ≥ 3` fails C2. The third preset therefore has to come from **selection**, not from K.

**The three presets that survive:**

| Preset | families enabled | cut | pooled yield | per-corpus range |
| --- | --- | --- | ---: | --- |
| **lenient** | structural, lexical, confusion, historical | **fam ≥ 1** | 8 985 / 27 889 = **32.22%** | 14.32% – 46.90% |
| **default** | structural, lexical, confusion, historical | **fam ≥ 2** | 1 224 / 27 889 = **4.39%** | 0.29% – 8.91% |
| **strict** | structural, lexical, confusion | **fam ≥ 2** | 653 / 27 889 = **2.34%** | 0.29% – 6.50% |

Per corpus, in full:

| Preset | ripwire | tree-sitter | gameA | rustCLI | appleXR |
| --- | --- | --- | --- | --- | --- |
| lenient | 2 191/4 672 = 46.90% | 578/1 538 = 37.58% | 4 568/17 157 = 26.62% | 1 583/4 068 = 38.91% | 65/454 = 14.32% |
| default | 358/4 672 = 7.66% | 137/1 538 = 8.91% | 714/17 157 = 4.16% | 12/4 068 = 0.29% | 3/454 = 0.66% |
| strict | 80/4 672 = 1.71% | 100/1 538 = 6.50% | 458/17 157 = 2.67% | 12/4 068 = 0.29% | 3/454 = 0.66% |

**Why `strict` is a *selection* and not a higher K.** The obvious strict preset — all four families,
K ≥ 3 — fails C2 outright (0.00% on two of five corpora) and fails the gate test it exists for: its
output set's endpoint Jaccard is **0.438 – 0.719**. Dropping `historical` instead produces a set that
is both smaller *and* measurably steadier. Output-set stability, on the same three ladders:

| Preset | ripwire | ctxpack | gameA |
| --- | --- | --- | --- |
| lenient (all 4, K ≥ 1) | 0.943 / 0.812 | 0.947 / 0.804 | 0.970 / 0.910 |
| default (all 4, K ≥ 2) | 0.878 / 0.622 | 0.851 / 0.548 | 0.907 / 0.633 |
| **strict** (s+l+c, K ≥ 2) | **1.000 / 1.000** | 0.909 / 0.667 | 0.982 / 0.896 |
| *(rejected)* all 4, K ≥ 3 | 0.914 / 0.719 | 0.837 / 0.438 | 0.814 / 0.487 |

*(mean consecutive Jaccard / endpoint Jaccard of the set the preset emits.)*

The three are **nested by construction** — removing a family from the count can only lower a
symbol's count — so `strict ⊆ default ⊆ lenient` on every corpus, which is what makes them a ladder
rather than three unrelated filters.

**What each is for, in the terms the measurement supports.** `lenient` is a browse list: a third of
every codebase has *some* evidence against it, which is a reading order, never a verdict. `default`
is a review list at ~1 symbol in 23. `strict` is the only rung the stability data supports pointing
a gate at, at ~1 symbol in 43 pooled and 80 symbols on ripwire's own tree — a sitting's worth of
work, and **literally the same 80 symbols** at every commit on the five-day ripwire ladder
(Jaccard 1.000 consecutive and endpoint).

**Three things these presets are NOT.** They are not validated against any notion of *actual* defect
or maintenance cost — nothing here measures whether a `fam ≥ 2` symbol is worse code, only that two
independent kinds of evidence point at it. They are not tuned per corpus, which is why `strict`
yields 6.50% on tree-sitter and 0.29% on rustCLI from the same rule. And the `strict` row for rustCLI has to be read
with §9.6 defect 1 in mind: on a Rust tree the confusion family cannot apply, so `strict` there is
`structural + lexical, K ≥ 2`. Since that fix the verb SAYS so — `unavailable="confusion"`, `of="3"` —
instead of wearing a three-family label silently, which is the difference between a preset with a known
narrower scope on some corpora and a preset that misreports its own.

### 9.8 Reproducing this section

```bash
# clone the corpora you intend to check out; NEVER run `stability` against a tree you work in
git clone --local --shared <repo> /tmp/repo-clone

python3 bench/ensemblecal/run_ensemblecal.py collect   --out cal.json  <dir>[:LABEL[:indep]] ...
python3 bench/ensemblecal/run_ensemblecal.py stability --out stab.json /tmp/repo-clone:LABEL --samples 8
python3 bench/ensemblecal/run_ensemblecal.py report    --in cal.json --stability stab.json
```

Six of the nine corpora are private or non-public local trees and cannot be redistributed. The three
that can — `ripwire`, `ripwire-src` and the vendored `tree-sitter` grammars — are in this repository
and reproduce exactly from the pinned revision.

### 9.9 The six-family panel — what the two new families had to pass first

`--quality-panel[=strict|default|lenient]` is the single command over the whole panel: the four families of
§9 plus **`colocation`** (the local-reasoning lens, `--context-ratio`) and **`state`** (this function's OWN
BODY touching non-local mutable state, `--nonlocal-state`). Neither was enabled on the strength of being a
plausible new axis. Both were put through **the same harness, the same corpora and the same criteria** as the
original four *before* they shipped enabled, and this section is that measurement. It ships no new rule and no
new threshold: every number comes out of `--quality-panel=lenient` through its existing entry point, parsed by
`bench/ensemblecal/run_ensemblecal.py --verb panel`. The family list is read from the verb's own root, so a
family added to the verb cannot go unmeasured because the harness was not updated.

**Verdict up front, in three parts.** (1) **Both new families pass the orthogonality test** — the largest
pooled cross-family φ in the whole 6×6 matrix is **+0.168**, which is exactly the value §9.3 published for the
four, so widening the panel did not raise it. (2) **`--field-affinity` was NOT made a family**, and that is an
exclusion by unit rather than a failed measurement — stated below. (3) **The stability pass disqualified a
second family from gating.** `colocation` came out *worse* than `historical` on one commit ladder, so `strict`
counts **four** families, not five. That third result is the uncomfortable one and it is the reason the ladder
was run rather than assumed.

Measured 2026-08-06, binary built at `feat/quality-panel`. Corpora, denominators and the overfitting caveat
are §9.1's, unchanged — five independent trees, **27 999 eligible functions**, `ctxpack` and `ripwire-src`
reported separately and never pooled.

#### 9.9.1 Per-family fire rate, with the two new columns

| Corpus | eligible | structural | lexical | confusion | historical | colocation | state |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ripwire | 4 782 | 12.25% | 18.99% | 2.28% | 21.73% | 0.84% | 3.12% |
| tree-sitter | 1 538 | 12.35% | 27.70% | 3.71% | 3.58% | 2.60% | 0.72% |
| gameA | 17 157 | 12.65% | 9.77% | 3.57% | 5.20% | 0.23% | 16.37% |
| rustCLI | 4 068 | 7.18% | 32.03% | **UNAVAILABLE** | **UNAVAILABLE** | 0.98% | 0.10% |
| appleXR | 454 | 9.91% | 3.52% | 1.54% | **UNAVAILABLE** | 6.17% | 0.88% |
| *ctxpack* | *4 027* | *12.49%* | *20.49%* | *2.33%* | *21.70%* | *0.99%* | *2.83%* |
| *ripwire-src* | *2 013* | *24.89%* | *2.73%* | *5.07%* | *27.77%* | *1.99%* | *0.79%* |

Two properties of the new columns matter more than their levels:

- **`colocation` is bounded at 40 rows by construction**, like the readability and churn halves it sits beside:
  it fires for the worst decile of `--context-ratio`'s own ranking, capped at that verb's own 40-row window.
  So it is 0.23% of gameA and 6.17% of appleXR from the *same* rule — a fixed-size cut is a larger share of a
  small corpus, and that is what an ordinal family is.
- **`state` has the widest cross-corpus spread of the six** — 0.10% to 16.37%, a 164× range against
  `lexical`'s 9.09×. On gameA it is a **floor**: that corpus saturates the lens's own 2 048-cell budget, which
  the verb discloses as `state_floor="1"`. A game engine really does carry more mutable global state than a
  Rust CLI, so part of that range is signal, but the family must be read with `sscope=` beside it: on rustCLI
  only **33 of 4 068** eligible functions are in a language the lens analyses, and the verb prints that number.

#### 9.9.2 The orthogonality test — the 6×6 matrix

φ over the full eligible denominator, pooled over the five independent corpora (n = 27 999):

| | structural | lexical | confusion | historical | colocation | state |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **structural** | 1.000 | −0.061 | **+0.168** | +0.127 | +0.092 | **+0.162** |
| **lexical** | −0.061 | 1.000 | −0.039 | −0.043 | −0.018 | −0.054 |
| **confusion** | +0.168 | −0.039 | 1.000 | +0.047 | +0.026 | +0.070 |
| **historical** | +0.127 | −0.043 | +0.047 | 1.000 | +0.062 | +0.026 |
| **colocation** | +0.092 | −0.018 | +0.026 | +0.062 | 1.000 | **+0.003** |
| **state** | +0.162 | −0.054 | +0.070 | +0.026 | +0.003 | 1.000 |

Largest |φ| on any single corpus: ripwire +0.252, tree-sitter +0.167, gameA +0.190, rustCLI +0.204, appleXR
+0.126; among the non-independent extras ctxpack **+0.278** and ripwire-src +0.218. **The largest value
anywhere in the study is still ctxpack's +0.278 `structural × historical` — the same pair, the same number
§9.3 reported — and it involves neither new family.** The largest involving a new family anywhere is
**+0.204** (rustCLI `structural × colocation`); pooled, **+0.162** (`structural × state`).

**Both candidates therefore pass**, and the two results worth stating explicitly are:

- **`colocation × state` is +0.003 pooled** — as close to independent as anything in either study. The two new
  families are not a single "context" axis wearing two hats.
- **Both new families correlate most with `structural`, and both have a mechanical explanation.** A function
  that must read a lot from outside its own file usually has a lot of call sites, and a function that touches
  many globals is usually a big one. This is the same directional reading §9.3 recorded for confusion and
  historical: `structural` is the hub of what small positive correlation exists. It is small — at +0.162,
  `structural` and `state` still disagree on 2 663 of the 3 461 functions either one flags.

**Why `state` is the OWN-BODY half of its lens, decided before the φ was looked at.** `--nonlocal-state`
publishes two quantities per function: the callee-**closure** union (`writes=`/`reads=`) and what the
function's own text does (`direct_writes=`/`direct_reads=`). The panel's unit is one function's own
comprehensibility, so the family has to be a property of *that* function's body — the closure is a fact about
its callees. The measurement then agreed with the principle: the closure form fires on **35.27%** of gameA and
correlates with `structural` at **+0.201** pooled, the own-body form on 16.37% at **+0.162**. Had the numbers
gone the other way the principle would still have decided it, and the family would have been dropped rather
than swapped for the better-scoring definition.

**Why `--field-affinity` is not a family.** It measures an **aggregate**: which of a struct's fields are read
together but declared far apart, scored with Chilimbi's cache-line separation weight. Its unit is a type and
its subject is memory layout. Making it a family here would require attributing a struct's finding to the
functions that touch its fields — flagging a function for a property of a type it merely uses, an attribution
the lens itself never makes. A panel row has to be a claim about the row's own symbol. This is an exclusion on
**unit**, decided without running a φ, and it is recorded as such rather than dressed up as a measurement.

#### 9.9.3 Co-firing over six families

Pooled over the five independent corpora (n = 27 999):

| families firing | symbols | share | cumulative (fam ≥ n) |
| ---: | ---: | ---: | ---: |
| 0 | 17 151 | 61.26% | — |
| 1 | 8 666 | 30.95% | 38.74% |
| 2 | 1 717 | 6.13% | 7.79% |
| 3 | 415 | 1.48% | 1.66% |
| 4 | 47 | 0.17% | 0.18% |
| 5 | **3** | **0.011%** | 0.011% |
| 6 | **0** | **0.000%** | 0.000% |

§9.4's first consequence holds a fortiori: **`fam = 6` is not a tier, it is empty** — zero symbols in 27 999,
and `fam ≥ 5` is three. Adding two families moved the top of the ladder from `fam=4: 3` to `fam=5: 3, fam=6: 0`
and left the *shape* alone: 38.74% → 7.79% → 1.66% → 0.18%, roughly 5×, 4.7× and 9× per rung.

#### 9.9.4 Stability — and the second family the ladder disqualified

Same protocol as §9.5: **one binary, the corpus varied** over a ladder of past commits in a throwaway clone,
restricted to symbols present in both trees. Ladders: ripwire (138 first-parent commits, every ~17,
2026-07-31 → 2026-08-05) and ctxpack (792, every ~99, 2026-06-20 → 2026-08-05).

| Family | ripwire (mean / endpoint) | ctxpack (mean / endpoint) | worst mean |
| --- | --- | --- | ---: |
| lexical | 1.000 / 0.999 | 1.000 / 1.000 | **1.000** |
| state | 0.999 / 0.990 | 1.000 / 1.000 | **0.999** |
| structural | 0.996 / 0.969 | 0.965 / 0.859 | 0.965 |
| confusion | 0.997 / 0.981 | 0.920 / 0.684 | 0.920 |
| historical | 0.852 / 0.494 | 0.862 / 0.525 | 0.852 |
| **colocation** | **1.000 / 1.000** | **0.732 / 0.222** | **0.732** |

**`colocation` is the least stable family in the panel, on the ladder where the corpus grew.** Its 0.222
endpoint Jaccard is the worst number in either study — worse than `historical`'s 0.426–0.546 — while on the
ripwire ladder it is a perfect 1.000/1.000. That contrast is the whole finding, and the mechanism is the one
§9.5 already named for churn: **a fixed-size worst-40 cut over a ranking whose population moves.** ctxpack grew
from 208 to 4 027 eligible functions across its window, so the top 40 by outside-reading volume turns over
completely; ripwire's tree barely changed size in five days, so it does not move at all. A family that is
steady only while the corpus is not growing cannot carry a gate.

`state` sits at the opposite pole for a reason that is equally mechanical: it is a **predicate**, not a
ranking — a function's own body either has a direct access site or it does not — so it moves only when
somebody edits that body. That is `lexical`'s property, and it is why both are 0.999+.

**The criterion and its cut are unchanged; what moved is which families fall on which side.** §9.7's C1 cut
interval on mean consecutive Jaccard is **(0.862, 0.920)**. Against the worst-mean column above, any cut inside
that interval selects `{lexical, state, structural, confusion}` and excludes `{historical, colocation}`. No
number was re-tuned to reach that answer.

#### 9.9.5 The three presets, derived

Criteria are §9.7's, applied to six families:

- **C1 — stability.** ⇒ **both `historical` and `colocation` are excluded from the gating preset.** They stay
  in the reporting presets, where a moving window is a feature.
- **C2 — non-degeneracy.** Every named preset must have non-zero yield on every corpus measured. All three do
  (per-corpus rows below); the rule kills the alternatives, not these — `stru+lexi+conf+stat` at K ≥ 3 yields
  **0.00%** on rustCLI and appleXR, and every K ≥ 5 combination yields 0.00% on four of five corpora.
- **C3 — the rungs come from the measured ladder.** §9.9.3's cumulative column gives them directly: `fam ≥ 1`
  = 38.74%, `fam ≥ 2` = 7.79%, `fam ≥ 3` = 1.66%, `fam ≥ 4` = 0.18%. Two are usable; `fam ≥ 3` fails C2 on the
  stable set and `fam ≥ 4` is 50 symbols pooled. The third preset therefore comes from **selection**, exactly
  as it did in §9.7.

| Preset | families counted | cut | pooled yield | per-corpus range |
| --- | --- | --- | ---: | --- |
| **lenient** | all six | **fam ≥ 1** | 10 848 / 27 999 = **38.74%** | 19.82% – 48.75% |
| **default** | all six | **fam ≥ 2** | 2 182 / 27 999 = **7.79%** | 0.91% – 9.36% |
| **strict** | structural, lexical, confusion, state | **fam ≥ 2** | 1 548 / 27 999 = **5.53%** | 0.32% – 7.61% |

Per corpus, in full:

| Preset | ripwire | tree-sitter | gameA | rustCLI | appleXR |
| --- | --- | --- | --- | --- | --- |
| lenient | 2 331/4 782 = 48.75% | 613/1 538 = 39.86% | 6 214/17 157 = 36.22% | 1 600/4 068 = 39.33% | 90/454 = 19.82% |
| default | 411/4 782 = 8.59% | 144/1 538 = 9.36% | 1 580/17 157 = 9.21% | 37/4 068 = 0.91% | 10/454 = 2.20% |
| strict | 121/4 782 = 2.53% | 103/1 538 = 6.70% | 1 306/17 157 = 7.61% | 13/4 068 = 0.32% | 5/454 = 1.10% |

**The exclusion is validated by the output the preset actually emits**, not only by the per-family numbers.
Output-set Jaccard down the same two ladders:

| Preset | ripwire | ctxpack |
| --- | --- | --- |
| lenient (all 6, K ≥ 1) | 0.949 / 0.805 | 0.962 / 0.848 |
| default (all 6, K ≥ 2) | 0.901 / 0.599 | 0.878 / 0.688 |
| **strict** (s+l+c+state, K ≥ 2) | **1.000 / 1.000** | **0.948 / 0.818** |
| *(rejected)* strict WITH colocation | 0.998 / 0.984 | 0.893 / 0.711 |

*(mean consecutive / endpoint Jaccard of the set the preset emits.)* Dropping `colocation` makes the gating
set both smaller and measurably steadier on the ladder where it mattered — the same trade §9.7 recorded for
`historical`, found the same way.

The three are **nested by construction** — removing a family from the count can only lower a symbol's count —
so `strict ⊆ default ⊆ lenient` on every corpus. `test/qualitypanelcheck.sh` asserts that, the exact family
list of each preset, the ordering, the unavailable path and the ladder identity
`ranked + below_cut + no_family = eligible`.

**What these presets are NOT.** Everything §9.7 said still applies: they are not validated against any notion
of actual defect or maintenance cost, they are not tuned per corpus, and `strict` on rustCLI is really
`structural + lexical, K ≥ 2` because `confusion` cannot apply there — the verb says so (`unavailable=`,
`of="2"`) rather than wearing a four-family label silently. One limit is new and belongs here: **the stability
pass covers two ladders, not three.** §9.5 measured gameA as well; this pass did not, so `colocation`'s
verdict rests on ctxpack alone for the corpus-growth case. Two ladders were enough to disqualify it — the
finding is that it *can* move that far, which one counterexample establishes — but a third would say more
about how often.

#### 9.9.6 Reproducing this section

```bash
git clone --local --shared <repo> /tmp/repo-clone      # NEVER run `stability` against a tree you work in

python3 bench/ensemblecal/run_ensemblecal.py collect   --verb panel --out cal.json  <dir>[:LABEL[:indep]] ...
python3 bench/ensemblecal/run_ensemblecal.py stability --verb panel --out stab.json /tmp/repo-clone:LABEL
python3 bench/ensemblecal/run_ensemblecal.py report    --verb panel --in cal.json --stability stab.json
```

`--verb ensemble` (the default) still reproduces §9.1–§9.7 unchanged: `--ensemble` was not modified by this
work, which is the reason the panel is a separate verb rather than a wider join.

---

## 10. Reproducing

```bash
cmake -S . -B build && cmake --build build -j

python3 bench/recalleval/run_recalleval.py .        # held-out retrieval eval
python3 bench/locbench/run_locbench.py --help       # localization harness
./build/ripwire . --eval                            # co-change recall
./build/ripwire . --eval-retrieval                  # known-item retrieval, four rankers
python3 test/pargates.py . ./build/ripwire -j 6     # the gate suite
```

The retrieval evals are **benchmarks, not goldens**: on a live repository the numbers move as
documents and commits land. The gate suite is the golden.
