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
| **Differential argv harness** | `test/argvdiffcheck.sh` | That a refactor changed *nothing observable*: two binaries, every argv vector, stdout + stderr + exit code byte-identical. |
| **The gate suite** | `test/regression.sh`, `test/pargates.py` | 311 gate scripts plus the determinism, cache-transparency and golden contracts. |
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

**Root-neutralised on this repository (re-derived 2026-07-31):**

| Result size | Byte reduction |
| --- | --- |
| top-10 | 59.1% |
| **top-50** | **68.4%** |
| top-100 | 66.5% |

**Quote the top-50 figure.** The signature payload is top-50 regardless of `--top-k`, so it is what
the command actually emits. A "~70%" headline is reachable at larger N but overstates the smaller
shapes people actually run.

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
naming **311 gate scripts**, all of which exist on disk.

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
single-file 47.2%, multi-file **7.0%**. Every corpus shows the same cliff. Complete-blast-radius
retrieval on large patches is open headroom, not a solved problem.

**The public C++ number is materially lower than an earlier private one.** SFML: strict file@10
**31.3%**, any@10 **45.2%**, first-hit MRR **0.22** — against roughly 89% any@10 and 0.62 MRR on a
private corpus that is no longer reproducible from this tree. The mechanism is visible in the query
shape: the private corpus's commit messages were long, identifier-dense technical notes (an easy
retrieval shape); SFML's are terse changelog summaries whose vocabulary barely overlaps the code. A
benchmark that produced *easier-looking* numbers from a *harder-to-publish* corpus is exactly the
non-portable claim the caveats warn about. **The public number is the baseline going forward.**

**Two ranking experiments produced no confirmed lift and did not ship.** `--anchor` and
`--cochange-boost` are dropped from `--help` and refuse to run without an explicit development
environment variable. One anchor-expansion candidate scored **+0.41pp** paired with a 95% lower bound
of **+0.00pp** and was rejected outright by the acceptance gate. A negative result recorded is worth
more than a feature shipped on a hunch.

---

## 8. Claims this project does *not* publish

Listed because the reason is more useful than the silence.

- **"~76% of an agent's token cost is file reads."** This figure appears in a skill description in
  this repository with **no citation**, while every neighbouring claim in the same paragraph carries
  one. The research note it referenced does not ship here. Until a source can be named, it is not a
  published number.
- **"+66.7% held-out strict@10" for the mention anchor.** The 66.7% figure that circulates is an
  *absolute* strict file@10 belonging to the *baseline* arm of a *different* experiment
  (anchor-hop expansion, train slice), and that experiment's candidate was **rejected and never
  shipped**. See `bench/locbench/anchorhop_calib.json`. The mention anchor's reproducible numbers are
  the ablations in §4.
- **A single round gate-count.** Two in-tree numbers disagree (`test/pargates.py`'s docstring says
  ~210; `test/argvdiffcheck.sh` says 200+), while the loop in `test/regression.sh` names 311. The
  loop is the authority; the stale docstrings are a known drift.
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

## 9. Reproducing

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
