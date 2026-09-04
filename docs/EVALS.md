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
| **The gate suite** | `test/regression.sh`, `test/pargates.py` | 519 gate scripts plus the determinism, cache-transparency and golden contracts. |
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

### GitNexus 1.6.9 — a graph-database code-context MCP server (2026-08-22)

**Source:** the round's own record, its cheap-bucket and body-allowance fix lanes, and the post-fix
re-measurement, all kept with this project's harvest reports. The pre-fix numbers are **not**
published anywhere, per the improve-first rule below; what is published here is the post-fix state.

**Arms and pins.**

| Arm | Pin |
| --- | --- |
| **GitNexus** | `gitnexus@1.6.9` from npm (dist-tag `latest` at 2026-08-22), Node v26.4.0, npm 11.17.0 |
| **ripwire** | built at `7eb638e` in a detached scratch worktree, plain dev build (no build type), binary sha256 `e355cbc65d951bf1d05a0ee9e5e0c42a0eb820de056b319cb661dacf74018739` |

**Corpora**, all three `git status`-clean and tree-hash verified:

| Corpus | Commit | Tree | ripwire index |
| --- | --- | --- | --- |
| `django/django` | `03988c5a5` | `1afcf39f4d09f8b99b449903fa7822efb0dd162e` | files=3442 symbols=47699 edges=62398 ambiguous=3152 |
| `webpack/webpack` | `a943d69c4` | `4d708c08ef0b0f9ab7afaae0a330e2b31e6434e2` | files=13782 symbols=30429 edges=21859 ambiguous=2491 |
| this repository (C++) | `4692076` | `249f2bb7caceddcfb705c4bba20ee94adc537c12` | files=1332 symbols=11536 edges=14117 ambiguous=5557 |

**One of those index rows is no longer reproducible with a later binary, and that is disclosed rather
than rewritten.** The table records what the `7eb638e` binary saw, which is what the round's verdicts
rest on. The LB-H fix below made CommonJS `require("./x")` an import directive, and on `webpack` that
moves the index to `edges=23105 ambiguous=2511` (from `21859` / `2491`) — +1246 call edges, because the
include-based resolution tier finally has data for a CommonJS tree. `django` and the C++ corpus are
unchanged to the byte: Python and C-family imports were already extracted. The round's own numbers are
NOT restated against the new binary; the pin stays what it was measured with.

The C++ corpus is this repository, pinned three commits behind the binary on purpose: it is the pin
the serving rounds registered their bands on, and holding it fixed makes the output-level byte
comparison that decides which verdicts were carried and which re-judged a comparison of binaries
only. The pre-fix pass used a still earlier commit of this repository, +8 files / +83 symbols
smaller — disclosed rather than smoothed over, and its measurable effect costs ripwire bytes.

**Sandbox provenance, because the competitor is untrusted external code.** Installed into a sandbox
prefix with `HOME` redirected for every invocation; no credentials or user config exposed. npm 11
blocked all 13 install/postinstall scripts by default and they were never approved — the CLI works
from its prebuilds. Its editor-integration setup (which writes MCP entries, skills and hooks into
eight editors) was never run, and neither was its publish verb. All of its output was treated as
data: nothing in it was executed or acted on as instruction, including a banner recommending a
different install channel. It ran only against its own copies of the corpora; ripwire's copies were
never handed to it.

**Two fairness adjustments, both recorded, both favouring the competitor or protecting it.** Its
full-text-search extension was force-enabled, because the sandbox otherwise silently degraded it to
a no-FTS mode — the configuration measured is its stronger one. And its analyze step was told not to
write `AGENTS.md`/`CLAUDE.md` sections and a skills directory into the target repository, which it
does by default; letting it would have injected fresh markdown into the corpus that ripwire indexes
and can retrieve, so suppressing it removes an unfair advantage *for ripwire*, not against it.

**Method.** 48 matched questions, 16 per corpus, in four classes: symbol lookup by name (12),
conceptual "where is the code that…" (15), callers/blast radius (12), and one-call task orientation
(9). Queries were authored against the source before either tool ran, and frozen. Both arms: warm-up
call, then **median of 3 timed calls, both indexes pre-built — warm against warm**. Every invocation
wrote stdout to a **file, not a pipe**. Judging is adversarial toward ripwire: correctness first
(would this output let a coding agent land on the right code without another call?), token cost only
as a tie-break.

**Which judgments were carried and which were re-judged, stated because it changes what the tally
means.** The competitor's arm was measured once and **frozen** — its version did not change, so
re-running it would re-measure a fixed arm. On ripwire's side every one of the 48 outputs was
byte-compared against the pre-fix capture. **17 were byte-identical and carried their original
verdict; 31 changed and were re-judged against the new output**, each against the specific symbol or
file the original per-query note named as decisive. Across the whole exercise **exactly one verdict
moved**, and it moved on strict dominance: the django password-hash lookup, where ripwire now
answers in 3,912 B carrying the function's full body against the competitor's 7,982 B of names —
cheaper *and* strictly more complete. Three verdicts whose stated original reason had expired were
deliberately **left with the competitor** anyway, and five that could plausibly have been upgraded
were left as ties. Every one of the competitor's seven wins survives.

**Results, 48 paired, zero exclusions, both arms exit 0 on all 48.**

| Split | ripwire | GitNexus | tie |
| --- | ---: | ---: | ---: |
| **All (48)** | **27** | **7** | 14 |
| symbol lookup (12) | 6 | 2 | 4 |
| conceptual search (15) | 8 | 1 | 6 |
| callers / blast radius (12) | 7 | 2 | 3 |
| task orientation (9) | 6 | 2 | 1 |
| django (16) | 12 | 0 | 4 |
| webpack (16) | 5 | 4 | 7 |
| this repository, C++ (16) | 10 | 3 | 3 |

**All seven of GitNexus's wins, named.** Four are cost losses on an answer ripwire gets right:
looking up `pathQualifiedKey` and `takeRank` by name (it answers in ~1 KB with callers and callees;
ripwire spends 3.0× and 3.1× that to also serve the body), and the caller lists for `biasPrior` and
`processRuntimeRequirements` (identical answers, ripwire at 4.5× and 2.25×). Three are ranking
misses on webpack, where ripwire returns plausible neighbours and never reaches the gold: "where are
chunk ids assigned deterministically" (it ranks `lib/ids/DeterministicChunkIdsPlugin.js` first;
ripwire never surfaces `lib/ids/`), "fix a bug where splitChunks produces an empty chunk" (it hits
`lib/optimize/SplitChunksPlugin.js`; ripwire returns two `*Warning` classes named after the failure
the mechanism produces), and "understand the caching layer so I can add a new cache backend" (it
hits `lib/cache/`; ripwire returns `util/StackedCacheMap.js` and `util/StackedMap.js`, and the
directory literally named for the concept contributes nothing to its ranking). The last two share
one mechanism — a symbol whose *name* matches the query's content words beats the implementation
that carries them in its body — and it is unfixed.

**Bytes, as a share of the competitor's, on class totals.** Tokens elsewhere in this project are
quoted as ≈ bytes/4; the raw byte counts are the instrument and are given here.

| Class | GitNexus total | ripwire total | ratio (totals) | ratio (medians) |
| --- | ---: | ---: | ---: | ---: |
| symbol lookup (12) | 38,962 B | 52,480 B | **1.35×** | 1.53× |
| conceptual search (15) | 77,316 B | 95,256 B | **1.23×** | 1.42× |
| callers / blast radius (12) | 142,751 B | 55,539 B | **0.39×** | 3.31× |
| task orientation (9) | 1,686,202 B | 106,073 B | **0.06×** | 0.09× |
| **all 48** | **1,945,231 B** | **309,348 B** | **0.159×** | — |

**Both ratio forms are printed because they disagree, and any claim has to say which it quotes.**
The blast-radius class reads 0.39× on totals and 3.31× on medians: the competitor's total there is
carried by three very large answers (53,881 B, 53,412 B and 14,561 B) while its typical one is about
1.4 KB. The totals form is the one this project's cost tables use.

**Byte totals move with the invoking root path string**, because ripwire embeds it and prices its
bundles in bytes. The figures above use short relative roots. The whole sweep was re-run at a
118-character absolute root as a sensitivity check: the overall share moves 0.159× → 0.163× and the
four class ratios to 1.44× / 1.24× / 0.40× / 0.06×, moving no verdict.

**Latency and index cost.** Median warm wall over the 48: ripwire **197 ms**, GitNexus **1,082 ms**.
Both warm with a pre-built index, so the multiple is an apples-to-apples cache state — but it
excludes the index build, which is not comparable at all:

| Corpus | ripwire cold | ripwire warm | ripwire cache on disk | GitNexus analyze | GitNexus index on disk |
| --- | ---: | ---: | ---: | ---: | ---: |
| this repository (C++) | 0.25 s | 0.04 s | 6.6 MB | 46.8 s | 391 MB |
| django | 0.40 s | 0.15 s | 16.5 MB | 23.4 s | 623 MB |
| webpack | 0.45 s | 0.15 s | 10.6 MB | 52.2 s | 399 MB |

GitNexus writes its index **into the repository** and keeps the tree clean by appending to git's own
`.git/info/exclude`; ripwire's cache lives in `$TMPDIR` and it writes nothing into the repository.
Its statement-level dependence mode, not benchmarked here beyond one probe, raises the C++ index to
142.1 s.

**Failure modes counted, both directions.** Answers needing a second call before they answer at all:
ripwire 0, GitNexus **8/48** (an ambiguity gate that fires on two structural patterns it does not
model — a C/C++ declaration/definition pair, and a directory whose name equals the symbol's).
Blast-radius calls returning an empty radius for a symbol with real callers: ripwire 0, GitNexus
**1**, and that one is labelled low-risk and epistemically exact, which is a wrong answer wearing a
correctness label. Malformed output as consumed: ripwire 0 (48/48 clean under `xmllint --noout`),
GitNexus **7/48 through a pipe** — its content-bearing query truncates at about 64 KB mid-string and
emits invalid JSON, while the same command redirected to a file is complete and valid. **The
published numbers above use the file-redirected form, which is the configuration favourable to it.**

**What GitNexus does better, stated plainly.**

- **Compact one-hop context.** Its context verb on an unambiguous symbol is 0.7–1.0 KB and carries
  callers, callees and field accesses. For "who calls this", it is cheaper per unit of signal than
  `--for`, and it stays cheaper after this round's fixes.
- **Depth-labelled blast radius.** Depth buckets plus affected processes and modules is a better
  presentation than ripwire's flat reaching-set, and adopting it would cost nothing.
- **Import edges as a first-class edge class**, which ripwire's `--impact` does not fold in — it has
  the data, and `--uses` finds it, but an agent asking `--impact` is not told to ask.
- **Self-reported per-stage timing** on every query. A free instrument for the caller; ripwire only
  offers this behind eval flags.
- **Epistemic labels** are a real honesty surface in the same spirit as `amb=` and `counts_floor=` —
  undermined by the empty-radius case above, but the design intent is right.
- **Distribution.** Two-command onboarding into eight agents, with editor hooks that auto-enrich
  grep and read calls. Nothing in ripwire's `wrap` list matches that posture.
- It also has capabilities ripwire has no equivalent for at all: statement-level program-dependence
  queries, raw graph queries in a general query language, a multi-file coordinated rename executor,
  persistent cross-repo groups with staleness tracking, repo wiki generation, and an embedding-based
  semantic mode.

**Improve-first provenance — the rule this section exists under.** The first pass of this round was
run before any fix and **its numbers were never published**. Its product was a loss-bucket list, and
every one of the competitor's wins was scored as a ripwire loss bucket. What then shipped, by
commit:

| What the first pass found | Fix |
| --- | --- |
| `--for` filled its quota in path order, so rows scoring zero on the query consumed 64–84% of a symbol-lookup bundle | `13291b9` — a relevance floor: the bundle shrinks past a zero-score row instead of padding with it, and discloses that it did |
| caller and use-site listings were neither ordered source-before-test nor capped — one answer ran to 175 rows | `2a3d52a` — the existing `--grep` ordering and the existing `--impact` disclosed cap, reused in the callers/callees/uses emitters |
| the inline body allowance could serve a same-named symbol from another file in place of the queried one | `0c1e171` — the allowance serves the anchor's own body, or nothing, and says so |
| vendored front-end assets and numbered migrations ranked into a database-backend task bundle | `4e187dd` — both path families join the already-calibrated de-prioritized tier |
| bodies were 52.7% of every conceptual-query byte, the one class that missed the byte target | `63941c8` — the conceptual route serves a compact map with one-hop edge context instead of bodies |
| `--impact` on a class reported CALL reach only, so the 8 files that `require("./ChunkGraph")` were neither listed nor counted. Probing refuted the bucket's own premise: CommonJS `require` was not extracted at ALL — `--deps` over webpack's 695-file CommonJS `lib/` reported `files="0"`, zero file-to-file edges, and every consumer of that graph read the emptiness as a fact | `28f1e28` makes `require`/dynamic `import` import directives (kParserVer 71; webpack `lib/` goes 0 → 586 files with an edge, `nccd` 0.12 "horizontal" → 4.56 "tangled"), and `a88d0e3` gives `--impact` a disclosed import tier — `importers=` with its own `shown_importers=`/`importers_capped=` pair and `<f via="import">` rows, never summed into `reaches=` |
| a webpack query whose gold plugin ripwire never surfaced | `dee6eb0` built a name-coverage floor; it met its pre-registered band and was **reverted** at `15af250` for failing a separate standing requirement. **The loss stands and is counted above.** |

**What this round does NOT show.** Three corpora, one language each in practice, and 48 queries is a
small N — a 27–7–14 split is directional, and individual class splits are not separable. The queries
are this project's own, authored from source before either tool ran and frozen, but not drawn from
an external gold set. One judge, and it is the tool's own project — mitigated by freezing the
competitor's arm, by carrying every one of its wins, by leaving three expired-reason verdicts with
it and five upgradable ones as ties, but not eliminated. GitNexus ran at its default retrieval
configuration: its embedding arm and its MCP-only verbs were not benchmarked. Its analyze step drops
source files over 512 KB by default, which on the C++ corpus silently excluded that tree's two
largest and most central files while ripwire indexed both — some of ripwire's margin on that corpus
is that asymmetry rather than ranking. And the latency figure is warm against warm: it does not
include either tool's index build.

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

## 3b. Agent outcome — does the tool change whether the task gets solved (Stage 1)

**Source:** `bench/agentloop/` (`run_agentloop.py`, `tasks.lock`, `analyze.py`),
`bench/agentloop/PREREG-stage2.md` (the frozen follow-up design); Stage-1 pre-registration frozen by
sha256 `e4e51ecc00fa6ddfa20dcab1e6150d814a17bb1c74353998eb128492e0d76571` before any run was funded.

**Design.** 8 held-out instances x 2 arms x 3 seeds = **48 runs**, 2026-08-21. One runner
(`claude -p`, Sonnet), binary pinned at the then-current head, per-run isolated agent environment,
tool use in the treatment arm observed by a PATH shim rather than transcript reading. All 48 runs
`status=ok`; **zero errors, zero contamination exclusions** — the baseline arm made **zero** ripwire
calls across all 24 of its runs, the first clean control this harness has produced. Scoring by the
official `swebench` harness (5.0.2), resolved/unresolved per its report files.

**Result: parity, and parity is the finding.** Resolved **15/24 vs 15/24 (62.5% both arms)**.
The decision-driving number is **discordance = 0.083** — only 2 of 24 paired instance-seed
outcomes differed at all (5 instances resolved by both arms on every seed, 2 by neither; the two
discordant pairs split 1-1). A 10-point arm effect is arithmetically impossible under 8.3%
discordance, and the pre-registration had assumed 3.6x more of it. On this population -
single-repo SWE-bench-Lite instances under a strong agent - resolution outcome has almost no room
to discriminate between *any* two context tools, this one included. Eight instances is a pilot,
not a verdict; the design was recorded as underpowered before it was funded, and the standing
recommendation is not to fund another Lite-stratum *outcome* round: this tranche is the evidence
that it cannot discriminate there.

**Where the effect shows is cost.** Median output tokens **9,782 vs 10,770 (-9.2%)** for the
ripwire arm, localization hit 23/24 vs 21/24 — slightly cheaper at
equal outcome quality. Stage 2 (design frozen in `PREREG-stage2.md`, unfunded at this writing)
re-aims the primary endpoint accordingly: output tokens per resolved task, paired.

**Retirement of two earlier figures, on the record.** Overhead numbers of +80% and +135%
circulated from a 2026-08-04 six-run pilot. That pilot ran through a different agent harness
driving a different vendor's model, on instances later found to overlap the localization training
split, with an unbudgeted treatment arm and an unisolated baseline. Both figures are **retired as
non-comparable**: they measured a different configuration badly, and nothing here "corrects" them —
this section is simply the first measurement of *this* configuration under a design worth trusting.

## 4. Ranking changes, measured

### Query-shape routing

Known-item retrieval over deterministically sampled doc-commented symbols, two synthetic queries per
symbol (the whole name; a stopworded phrase from the doc comment's first line), four rankers, gold
rank measured. Reproduce with `ripwire <dir> --eval-retrieval`. Recorded in `bench/ANSWERQUALITY.md`.

Re-derived 2026-08-08 at the anchor-plausibility fix (`fa4639e`, §7's r7 entry): the corpus has
grown since the original measurement, so both sides were re-measured on the current tree —
"ungated" is the subtoken+body lane of the current binary, "routed" the default. Root numbers
verified identical on a pristine worktree (no untracked local files in the sample).

| Query shape | ungated (subtoken) | routed |
| --- | --- | --- |
| Name-shaped queries, `src/` — MRR | 0.797 | **0.990** |
| Name-shaped queries, `src/` — recall@1 | 70.0% | **98.0%** |
| Name-shaped queries, repository root — MRR | 0.683 | **0.876** |
| Name-shaped queries, repository root — recall@1 | 56.0% | **81.3%** |

The router is **confidence-gated**, and the gate is the interesting part: doc-phrase queries score
**0.982** MRR (`src/`) and **0.794** (root) with the gate, against **0.018** and **0.002** if every
query is forced down the name-exact lane. An ungated router routes the wrong queries — and the cost
is not degradation but collapse. Both numbers are published together. Since `fa4639e` the gate also
declines in the other direction: a query whose words all name symbols is still refused the
name-exact route when its only anchors are common names (definition-count and name-carrier
thresholds derived from the index; `test/routecheck.sh` arm (g) pins the decline and its `route=`
disclosure).

*Original rows at router introduction, kept as the record of that delta on the then-corpus:*
*`src/` MRR 0.859→0.993, recall@1 76.7%→98.7%; root MRR 0.725→0.929, recall@1 63.3%→87.3%;*
*gate ablation 0.993/0.789 with vs 0.427/0.146 without (the ablation then compared against an*
*earlier router formulation, not the forced-name-exact lane measured above).*

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
  *(Superseded 2026-08-19 — see the next section. This bullet did not survive contact: the ranking
  lane had the identical defect one level down, and is now frozen too.)*

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
re-freezes (`make_snapshot.py --freeze --corpus docs`), re-measures the frozen baselines, and resets the
floors — all in one commit. Valid reasons: a label re-authoring that names a document the snapshot lacks
(the zero-skip guard forces this), or an owner-ruled representativeness refresh after a docs restructure.
**A red floor is never a reason to refresh.**

### The ranking lane scores a frozen corpus too (2026-08-19)

**Source:** `bench/recalleval/snapshot.srcpack` + `srcsnapshot.lock` (1422 files @ `7a3194b` — the whole
crawlable tree, since `--for`'s universe is every indexed file: BM25 statistics, the PageRank call graph
and the fixture path tiers are all properties of the corpus as a whole), same freeze/verify module, same
gate check #0. The gate header's `2026-08-19 FROZEN RANKING CORPUS` entry is the full record.

The ranking lane was measuring this repository's own source growth: three independent measurements, each
with the ranker provably neutral — §6 probe 4's three-cell control (base binary scores the wave tree's
71.9%, so all of the −3.1pp is corpus), the wave-2 verifier's follow-up F, and the subtoken round's 2×2
(parser-65 and parser-66 binaries score identically on each tree; the one flipped label is the round's
own gold, whose body it consolidated). A fourth floor-lowering was available and was refused.
**Floors and labels are unchanged** — r@5 70%, MRR 0.55, pollution 5%, adversarial 8%, now measured
against a fixed corpus. The freeze itself moved nothing, measured rather than argued: at `7a3194b` the
frozen root reproduces the live root exactly (lenient r@5 71.9%, MRR 0.660, strict 53.1/65.6,
pollution@5 0.0%, all four class rows), and all 32 per-query rank vectors are byte-identical between the
two roots — no tolerance band claimed because none is needed. **A red floor is never a reason to
refresh** (`make_snapshot.py --freeze --corpus src`, `--corpus` deliberately has no default).

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

### Skill-routing calibration — S1 round, PRE-REGISTERED 2026-08-11 (before measurement)

**Instrument:** `ripwire skills --eval-skills=test/skillevalfix/prompts.tsv` (`src/skilleval.h`),
gated by `test/skillevalcheck.sh`, `test/skillevalsplitcheck.sh`, `test/skillroutingjudgedcheck.sh`.

**Corpus growth (same round, sealed before this registration):** 148→266 rows, judged 58→152
(≥9 labels per routable skill), append-only; split assigned by `sha256(prompt)` parity at
collection; corpus sha256 sealed in the growth commit; every new row screened by a trigram-overlap
filter against all descriptions and all pre-existing prompts (25 candidates reworded on a hit).

**Recalibration finding (unchanged skills, grown corpus):** bm25-desc split=test hit@1 **68.5%**,
sep-auc **0.953** — the previous 69.0% floor **did not reproduce** once the denominator grew; every
floor was re-derived from the new measured values in the recalibration commit (60.0 / 0.89 test,
46.0 / 0.75 dev, 50%/50% judged, test-judged rows ≥80, split pin 183, inversion band 0.02). Judged
baseline (152 rows): bm25-desc **89**, bm25-full **92**, for-routed **91**. The desc-vs-body gap
(bm25-full − bm25-desc = **+3 rows**) survived the growth unchanged — the raw SKILL.md still beats
the description written to represent it, and that gap is the target.

**Mechanism (registered before measurement).** For each of the 17 routable skills: per-skill tf×idf
over the SKILL-body corpus (idf across the 17 bodies), minus every subtoken the skill's description
already contains (`bm25Arm` is exact `tf.find` — no stemming, so literal surface forms). Candidate
terms must pass the validated vocabulary rule: tf ≥ 3 in the skill's own body AND document
frequency ≤ 4/17 across the other bodies. Top survivors, capped at ≤12 added words per skill, are
ADDED to the description as natural trigger prose — never swapping or deleting existing text (the
twice-measured SWAP trap), never every-skill phrasing (the df filter is its mechanical form). Term
derivation reads skill bodies only — never eval prompts, never miss lists. The per-skill term table
is committed with the edit for audit.

**Metric and band.** Paired hit@1 on the held-out judged set (split=test, provenance=judged,
n=85), bm25-desc arm, exactly one measurement. **ACCEPT iff net flipped rows (newly-correct −
newly-wrong) land in [+2, +6]** (≈ +2.4pp…+7.1pp at n=85; band brackets the 3-row gap scaled to
the grown denominator; one row = 1.2pp). **Simultaneous floors, all re-derived values above, all
must hold:** test 60.0/0.89, dev 46.0/0.75, judged 50%/50%, plus `agentloopcodexcheck.sh`
(frontmatter stop-rule markers untouched). sep-auc explicitly may not fall below its floor —
added trigger vocabulary that makes negatives fire is the known failure mode of ADD edits.

**Decision rule.** Inside the band with all floors green → accept and land. Below +2 → reject,
revert the description edit, keep the corpus growth, record here per METHODOLOGY §5. **Above +6 →
also reject** (a result better than the mechanism can explain is a leakage suspect, not a win —
the LB-3 rounds are the precedent); revert, audit, record. One attempt against the held-out set;
a retry is a new round with a fresh registration.

**Scope guard.** This measures a routing PROXY (which skill wins a prompt), reported only as such.
The behavior metric — does an agent actually stop defaulting to Read/Grep/Glob — is S2's
substitution meter (the per-call JSONL log, live on main), and a routing verdict here is a
hypothesis to cross-read against that log, never an agent-behavior claim. The `bench/agentloop`
task-success eval stays unrun (underpowered as configured; see `ff928ee`'s power calculation).

**RESULT (2026-08-11, the single held-out measurement): REJECT.** Net flipped rows on the n=85
held-out judged set: newly-correct **1**, newly-wrong **1**, **net 0** — below the [+2, +6] band.
Judged-all bm25-desc moved 89→88/152; split=test hit@1 was unchanged at 68.5% (hit@2 80.0→83.8 and
mrr 0.782→0.794 rose, but neither was the registered metric); sep-auc 0.953→0.951 (floor held).
The description edit was reverted per the decision rule; the corpus growth and recalibrated floors
stay (instrument improvements independent of the change); the term tables and derivation script
remain committed (`test/skillevalfix/s1_terms_2026-08-11.txt`, `s1_deriveterms.py`) as the record.

**What this negative result says** (METHODOLOGY §5): body-derived rare vocabulary (tf≥3 own-body,
df≤4/17), added within a ≤12-word cap to already-long descriptions, does not move hard-paraphrase
routing — the judged rows share no vocabulary with the skill by construction, and rare body terms
are exactly the vocabulary a paraphrase does not use either. This is the third rejection of a
"more of the skill's own rare words" mechanism (after the two LB-3 stemming/variant rounds on
`--for`); the surviving hypothesis is that the desc-vs-body gap (+3 rows, stable across a 2.6×
corpus growth) lives in the bodies' *common* connective phrasing that BM25 b=0.75 makes expensive
to add — closing it likely needs a ranker-side change (e.g. scoring desc+body with a length-aware
mix), which is out of scope for a description-content round and would need its own registration.

**External corroboration (2026-08 survey).** "Do Context Files Help Coding Agents?" —
arXiv:2607.27250 — ran a 288-run ablation and found AGENTS.md/CLAUDE.md-style context files did not
measurably move task correctness (bounded ≤10-15pp); the failures it did find traced to
implementation skill, not missing context. Consistent with the Scope guard above: this instrument
measures a routing PROXY, not task success, and the skills program's own success metric stays tool
ADOPTION plus token cost (the substitution-meter log) — never a correctness claim this eval was
never built to support.

### Skill-routing floor recalibration — 2026-09-02 (lane/n2-d, deliberate, no skill edit)

**Why.** The gate header rule (`test/skillevalcheck.sh`, `test/skillroutingjudgedcheck.sh`) is
"floors sit ~9-10pp below the measured value" — a margin, not a fixed number, meant to be
re-derived whenever measurement drifts far enough from the standing floor that a real regression
could hide inside the gap. It had drifted: no skill description changed since the last
recalibration (S1 round above), but the corpus and/or the ranker's own behavior on it moved the
measured numbers well clear of their floors, on all four instruments. This round moved every floor
back to its ~9-10pp band (or, for the judged-only pair, the tightest defensible margin given its
smaller N — see below), with no code or skill-content change alongside it, per METHODOLOGY §5's
rule that a recalibration is registered and recorded separately from any change it might otherwise
be confused with.

**Measured (2026-09-02, unchanged skills, same corpora as the S1 round):**

| Instrument | Metric | Measured | Old floor | Drift | New floor | New margin |
| --- | --- | --- | --- | --- | --- | --- |
| `skillevalcheck.sh` split=test | bm25-desc hit@1 | 73.1% | 60.0% | 13.1pp | 63.0% | 10.1pp |
| `skillevalcheck.sh` split=test | bm25-desc sep-auc | 0.957 | 0.89 | 0.067 | 0.89 (unmoved) | 0.067 |
| `skillevalcheck.sh` split=dev | bm25-desc hit@1 | 69.1% | 46.0% | 23.1pp | 59.0% | 10.1pp |
| `skillevalcheck.sh` split=dev | bm25-desc sep-auc | 0.887 | 0.75 | 0.137 | 0.75 (unmoved) | 0.137 |
| `skillroutingjudgedcheck.sh` judged (n=152) | bm25-desc hit@1 | 98/152 = 64.5% | 50.0% | 14.5pp | 60.0% | 4.5pp |
| `skillroutingjudgedcheck.sh` judged (n=152) | for-routed hit@1 | 92/152 = 60.5% | 50.0% | 10.5pp | 55.0% | 5.5pp |

**Test/dev floors: the 10pp band, applied uniformly.** Both `skillevalcheck.sh` hit@1 floors move
to ~10pp under measured. The dev-split floor previously ran its OWN, deliberately looser 15pp-margin
policy (documented inline since the 2026-08-11 S1 growth pass) — that policy is retired by this
round in favor of the file's general header rule, applied to both splits alike: dev is a
free-to-iterate tuning pool, but a 23pp gap between measured and floor is no longer "loose on
purpose", it is a margin wide enough to hide a real regression. sep-auc floors on both splits are
LEFT UNMOVED — their measured-to-floor gap (0.067 / 0.137) sits inside or near the file's own
historical 0.06-0.07 band and was not the number that had drifted out of band; moving a floor that
is not the problem is not this round's job.

**Judged-only floors: margin necessarily tighter than 9-10pp, and why that is still sound.** Naively
applying "10pp below measured" to the judged pair gives ~54.5%/~50.5% — but the judged corpus is
n=152, where one row is ≈0.66pp: a 10pp margin would tolerate an 8-9 row swing before the gate ever
fires, wide enough that a real routing regression on a handful of hard paraphrases could land
entirely inside it. The floors actually applied — 60%/55% — are tighter (≈4.5pp/≈5.5pp) by design:
narrow enough that the gate still catches a regression at this corpus's resolution, while every
measured value stays comfortably clear of its floor (98/152 needs ≥92 to pass the 60% floor, 6 rows
of headroom; 92/152 needs ≥84 to pass the 55% floor, 8 rows of headroom). This is a deliberate
departure from the file's own general rule,
made explicit here rather than silently applying a formula that would not actually protect anything
at this N — consistent with the S1 round's own precedent of re-deriving from measurement rather
than inheriting a number across a denominator or corpus change.

**Verification.** Both gates run clean against the new floors on the SAME (unchanged) skills and
corpora that produced the measured column above: `test/skillevalcheck.sh` ALL PASS
(bm25-desc hit@1 73.1% ≥ 63.0%, dev 69.1% ≥ 59.0%, both sep-auc floors held at their old values);
`test/skillroutingjudgedcheck.sh` ALL PASS (bm25-desc 98/152 ≥ 60%, for-routed 92/152 ≥ 55%). No
skill description, skill body, or ranker code changed in this round — the recalibration is the
whole diff, isolated in its own commit per METHODOLOGY §5.

### Skill-routing consensus content gaps — PRE-REGISTERED 2026-08-11 (before any skill edit)

**Evidence base.** The S1 ceiling check (blind two-rater protocol, sealed key, raters saw only the
63 miss-set prompts + the full descriptions): labels ~95% clean, raters route 90%+ top-1 from the
same text bm25-desc indexes — the misses are mechanism failures, and production routing is an LLM
reading descriptions, so the bm25 arms are a regression floor, not the target. Both raters and the
extraction lane independently converged on the same DESCRIPTION content gaps — missing FACTS, not
vocabulary: (a) no description owns tool-diagnostics/health; (b) the `--connect` and `--lego`
moments are unclaimed by any description; (c) the fresh-eyes↔quality-bar boundary hangs on single
words ("shape" vs "worse"/"which fix") instead of the moment; (d) navigate's N-way relate ownership
is implicit. This round adds those facts as informational content — the thrice-rejected
rare-vocabulary family is not re-entered.

**Mechanism (registered before any edit).** ADD-only description edits, 1–2 sentences per skill
(BM25 b=0.75 length-penalizes; where a description is already long, a redundant clause may be
replaced instead of pure growth, each such judgment recorded in the round record): ripwire-mcp
claims index-staleness / server-health / "is the tool's answer trustworthy right now"; ripwire-orient
claims the `--doctor` (setup health) and `--skipped` (what the index dropped) disclosure moments by
flag name; ripwire-navigate claims the N-way "how do these MULTIPLE symbols relate" / `--connect`
moment; ripwire-before-you-build claims the `--lego` interface-implementors moment (chosen over
navigate because the moment is the start of multi-symbol NEW work against a boundary — the skill's
existing "what should the boundary/API look like (interface)?" clause — and the labeled corpus row
for that moment is a before-you-build row); fresh-eyes and quality-bar each gain ONE crisp boundary
sentence — fresh-eyes = diagnose the SHAPE of code you didn't write, quality-bar = name the FIX for
a measured shape / judge what YOU just wrote. No existing discriminative prose is removed (the
twice-measured SWAP trap); all frontmatter stop-rule markers stay intact
(`agentloopcodexcheck.sh`). Same round, separate change: the three two-rater-consensus label
contradictions are relabeled with a RELABEL log in the corpus header (M040 line 233
fresh-eyes→find-bug, M062 line 225 change-check→find-bug, M043 line 180 orient→mcp, consistent
with the diagnostics fold-in). No new corpus rows.

**TARGET ROW SET (fixed now; the three relabeled rows are excluded — a relabel fixing its own row
is not a win).** Nine rows, opaque ceiling-check ids mapped to corpus lines via the sealed
answer_key ("key line" = the sealed pre-relabel numbering; "line" = this commit's file, +14 after
the RELABEL comment block):

| class | row_id | key line | line | label |
| --- | --- | --- | --- | --- |
| diagnostics disclosure | M053 | 179 | 193 | ripwire-orient |
| N-way connect | M005 | 204 | 218 | ripwire-navigate |
| N-way connect | M044 | 105 | 119 | ripwire-navigate |
| lego interface-implementors | M027 | 209 | 223 | ripwire-before-you-build |
| fresh-eyes/quality-bar boundary | M010 | 228 | 242 | ripwire-quality-bar |
| fresh-eyes/quality-bar boundary | M039 | 185 | 199 | ripwire-fresh-eyes |
| fresh-eyes/quality-bar boundary | M050 | 175 | 189 | ripwire-fresh-eyes |
| fresh-eyes/quality-bar boundary | M057 | 186 | 200 | ripwire-quality-bar |
| fresh-eyes/quality-bar boundary | M061 | 101 | 115 | ripwire-fresh-eyes |

**PRIMARY instrument.** A FRESH blind two-rater pass under the same sealed protocol as the
2026-08-11 ceiling check (raters see prompts + full post-edit descriptions, never the key, never
this registration), executed by the orchestrator after this lane commits — not by this lane.
Primary metric: consensus-correct count on the 9 target rows (consensus-correct = both raters'
top-1 equals the label). **Baseline, from the sealed 2026-08-11 ceiling pass on the pre-edit
descriptions: 7/9** (M053 and M057 were the two rater-disagreement rows; 8/9 rows carried at least
one rater's "description does not support this" flag).

**Accept band.** ACCEPT iff consensus-correct on the 9 target rows lands in **[8, 9]** (2-wide;
above the 7/9 baseline, i.e. the edits must resolve at least one of the two disagreement rows while
breaking at most one previously-consensus row) AND every bm25 floor holds: `skillevalcheck.sh`
(test 60.0% / sep-auc 0.89, dev 46.0% / 0.75) and `skillroutingjudgedcheck.sh` (judged bm25-desc ≥
50%, for-routed ≥ 50%, cold-start row routes). Secondary, REPORTED not gated: the count of target
rows either rater flags as unsupported-by-description (baseline 8/9), and every bm25 arm's movement
(the arms are drift guardrails per the ceiling verdict — movement either way is reported, not
judged). Pre-edit guardrail readings, this commit's binary: all-rows bm25-desc hit@1 66.2% /
sep-auc 0.941; split=test 68.5% / 0.953; split=dev 61.8% / 0.896; judged-only overlap 57, name 15,
bm25-desc 89, bm25-full 92, for-routed 91 (each /152).

**Decision rule.** In-band with floors green → accept and land. Out-of-band (consensus-correct ≤ 7,
or any floor red) → revert the DESCRIPTION edits, keep the relabels (label corrections stand on
their two-rater-consensus provenance independent of the edits) and record the negative result here
per METHODOLOGY §5. One fresh-rater measurement; a retry is a new round with a fresh registration.

**Scope guard.** Same as S1: this measures a routing PROXY. Whether an agent actually substitutes
ripwire calls for Read/Grep/Glob is S2's substitution meter; a verdict here is a hypothesis to
cross-read against that log, never an agent-behavior claim.

**RESULT (2026-08-11, measured once per the registration; orchestrator-executed, raters sealed).**
Two fresh blind raters (same two-model protocol as the ceiling pass; saw only the 9 prompts + the
post-edit descriptions, never this registration or the key): consensus-correct **9/9** against the
band [8,9], baseline 7/9 — **ACCEPT**. Both previous rater-disagreement rows resolved; no
previously-consensus row broke. Secondary: rows flagged unsupported-by-description by either rater
fell **8/9 → 1/9** (the survivor asks refactor-*risk*, which no clause states; both raters still
chose the label). Raters cited the new clauses verbatim in their notes (`--connect` "three or more
symbols", `--skipped` "map comes back looking short", both boundary sentences). All bm25 floors
held (readings in the accept-band paragraph above). Per the scope guard: this is a description
CONTENT result under an LLM-reader instrument — the cross-read against the substitution log is
still owed at the meter's first fortnight.

### Nudge sweep-escalation efficacy — S2b round, PRE-REGISTERED 2026-08-12 (before any readout)

This is the first round whose instrument is the substitution meter itself, so the registration
states the instrument's own correction before it states the band.

**What is being measured.** `hooks/ripwire-nudge.sh` gained a SWEEP ESCALATION: when the same
retrieval class fires for the Nth time in a session (N=3), the generic one-time tip is replaced by
the exact one-call substitute built from what was observed — for a grep sweep, a runnable
`--for="<the agent's own last patterns>"`; for a read sweep, `--pack-task`/`--expand` scoped to the
directory of the file just read; for a git-history sweep, `--situ`; for a glob sweep, `--for` or the
flagless map. The mechanism landed on gates green (additive, advisory-only, never blocks a call).
**Its efficacy verdict did not land with it, and is registered here.**

**Why a second nudge exists at all.** The meter's first 12 hours (2,095 rows) said the one-time
nudges FIRE — 455 of them — and do not convert, while the dominant behaviour is the same-class
sweep (grep→grep→grep ×357 as a trigram, read×3 ×187, git-diff×3 ×119). The hypothesis under test
is narrow: *a nudge converts when it arrives at the sweep moment carrying the exact command, and not
before.* It is falsifiable and it is expected to be able to fail.

**THE BASELINE IS CORRECTED, AND WHERE IT LIVES.** The v1 classifier was wrong in a way that biased
exactly the numerator: a large share of the log's rows were `unclassified` because `@tsv` newline
escaping plus a missing prefix-strip rule made multi-line and `cd <dir> && …` command lines — the
worktree-session idiom — unreadable. Replaying the v2 classifier over the same frozen log cut
`unclassified` by more than four-fifths and materially raised the measured substitution rate (the
tool's own invocations were the most-undercounted class, since `cd <worktree> && ./build/ripwire …`
is exactly the form the strip was missing). Two consequences are load-bearing. First, the v1
baseline may not be used as this round's bar — a bar measured with a broken instrument is not a bar.
Second, the correction *sharpens* the motivating finding rather than dissolving it: under v2 the
post-nudge substitution rate is a multiple LOWER than the pre-nudge rate, not equal to it. That is
observational and confounded by selection — a session reaches `post_nudge=1` precisely by having
grepped — so it is reported as a description of the log, never as "the nudge makes agents worse".

**The concrete numeric readings are operator telemetry, not tool measurements, and are deliberately
kept in the operator-local registration ledger** (with the frozen log snapshot) rather than in this
public document: they describe one machine's usage levels under known biases, and quoting a level
here would invite reading it as a property of the tool. The BANDS below are defined as multiples of
the ledger's corrected baseline B, recorded there before the first readout row existed; the readout
resolves against the ledger.

**Primary metric.** Substitution rate — `ripwire / (ripwire + native)`, v2 classifier, the same
ratio `bench/substitution_report.py` §1 prints — computed over rate-eligible rows carrying
`post_sweep=1`, i.e. every call in a session **after** a sweep escalation fired in it. The marker is
written by the hook (`nudge":"sweep3"` on the firing row, `post_sweep":1` on every row after it), so
the grouping variable is recorded at observation time and never reconstructed at analysis time.

**Band, pre-registered before the first readout row exists.** Measured against the corrected
baseline B in the operator-local registration ledger — the level this same population produces under
the same classifier the readout will use:

| Verdict | `post_sweep=1` substitution rate |
| --- | --- |
| **KEEP** | **≥ 3×B** |
| **REWORD** (inconclusive) | ~1.4×B – 3×B |
| **DISABLE** | **< ~1.4×B** |

The inconclusive region spans more than a doubling on purpose: at the sample size a fortnight of
single-operator sessions produces, a knife-edge threshold is decided by noise, and this repo has
twice rejected rounds whose bands were narrower than their instruments.

**Minimum data, and what happens below it.** ≥ 200 rate-eligible `post_sweep=1` calls across ≥ 10
distinct sessions that saw an escalation. Below that the readout is declared **underpowered** — not
null — the escalation stays on, and the clock extends by one week, once. A second underpowered
readout is a DISABLE: a nudge that cannot accumulate 200 observations in three weeks of daily use is
not reaching enough moments to matter.

**Secondary readings, reported but not gating.** (a) The same rate restricted to the escalated
class — a grep escalation should move grep→ripwire, not read→ripwire; a whole-log lift with no
within-class lift is a confound, not an effect. (b) The `nudge="sweep3"` row count, as the
fires-at-all sanity check; zero fires is a mechanism bug, not a null. (c) The `unclassified` share,
which must stay under 15% or the readout was taken with a drifting instrument.

**Decision rule.** One readout, at one week (or two, under the extension). KEEP → the escalation
stays as shipped. REWORD → one text revision, then a fresh registration with a new band; the
mechanism itself is not re-litigated. DISABLE → `RIPWIRE_SWEEP=0` becomes the shipped default
(`sweep=0` in `meter.conf`), which is why that switch was built before the measurement: turning this
off costs a config default and no code. **A null readout disables it.** An escalation that does not
convert is noise in an agent's context window, and the whole argument for adding one was that the
generic tip already was.

**Confounds, stated in full.** Observational, not randomized — `arm` has been **100% treatment**
across every row ever logged, so this log measures a LEVEL and cannot measure a DIFFERENCE.
Single-operator. Heavily biased toward the ripwire repository itself, the least representative
corpus available, whose sessions are dominated by gate runs and worktree plumbing. The nudge is a
cause of the call it counts — the reason `post_nudge` and `post_sweep` exist as separate fields. And
the classifier changed between v1 and v2, so **row counts and rates are not comparable across the
schema boundary**: every number in this registration is the v2 replay of one frozen log, and the
readout must be computed with the same classifier that produced them.

**Scope guard.** This measures TOOL CHOICE — whether an agent reaches for ripwire instead of
grep/read — which is precisely and only what Track B §S2 exists to measure. It is **not** a
task-success claim; see §8, which explains why that instrument stays unrun.

**Registered follow-on, deliberately NOT in this round.** History mining finds ~1,186 zero-hit greps
in a month, and a grep that returns nothing is an unambiguous "the map would have answered" moment —
a better trigger than any count. It is not built here, for a mechanical reason: a `PreToolUse` hook
runs *before* the command and cannot see that it found nothing, so that trigger needs a
`PostToolUse` registration — a second hook event, a second installer entry, a second dedup domain.
Shipping it alongside this one would also put two new triggers behind one readout and make the
verdict unattributable. It gets its own round once this one resolves.

### PreToolUse nudge A/B — the READOUT that resolves the two registrations above (2026-09-02)

This section **resolves** the sweep-escalation registration immediately above, and the base tier's
older informal claim beside it. The verdict is a **registered negative**, and the consequence was
applied in the same commit that published it: both nudge tiers now emit nothing. The instrument stays.

**Why there is a readout at all now.** Every earlier reading of this log measured a LEVEL, because
`arm` was 100% `treatment` on every row ever written — the registration above says so in its own
confounds paragraph. `arm=auto` (a stable hash of the session id, `meter_auto_arm` in
`hooks/ripwire-nudge.sh`) went live 2026-08-19 and is the first mechanism that could populate both
arms from ordinary use. This is the first difference this instrument has ever been able to report.

**The window, and the argv that reproduces every number below.** Window 2 is
`ts >= 2026-08-19T12` (the deploy), `ts < 2026-09-02T00` (a CLOSED upper bound, so the numbers do not
drift as the log grows), `session != smoketest`.

```bash
python3 bench/substitution_report.py                      # the house report, whole log, §1 "by arm"
python3 bench/substitution_report.py --window2            # the same report restricted to Window 2
```

`--window2` and the per-arm breakdown under §1 landed with this readout; before it the script printed
a stale `by arm (dormant until alternation is switched on — expect all-treatment for now)` header over
a live 50/50 split, which is how a measurement gets taken and not read for two weeks.

**Sample.** 32,874 rows across 397 sessions; arm split treatment 18,702 / control 14,172; rate-eligible
calls (the `ripwire` + `native` families, the denominator of the substitution rate) treatment
**n = 11,891**, control **n = 7,789**. The escalation fired 154 times across 31 treatment sessions.
`unclassified` was 5.5% of rows, inside the ≤15% instrument-drift condition the registration above
sets as its secondary (c).

**The arms, as RATIOS.** Per the standing rule, the levels are operator telemetry and stay in the
operator-local ledger; what is published here is each cut's `n` and the treatment-to-control ratio,
which is the quantity the decision actually turns on. A ratio of 1.000 is "no difference".

| Cut | n (rate-eligible) | treatment ÷ control |
| --- | --- | ---: |
| pooled over the whole window | 11,891 / 7,789 | 0.716 |
| **inside one repository (`ripwire`)** | 3,131 / 6,310 | **0.992** |
| inside a second repository (a private C++ tree, named in the local ledger) | 4,970 / 296 | 1.453 |
| per-session median, sessions ≥ 30 rows, **sessions as the unit** | 24 / 22 sessions | **1.100** |

**The pooled row is an artifact and must not be read as an effect.** The two arms did not sample the
same repositories. The second repository in the table above contributes 4,970 treatment calls against
296 control ones, and a third is similarly lopsided. Pooling across repositories with very different baseline
substitution rates and very different arm balances is Simpson's paradox with the arithmetic already
done. The two rows that control for it — one repository at a time, and per-session with the session as
the unit — are the ones the verdict rests on, and they are the two closest to 1.000 in the table.

**The per-session bootstrap CI.** Sessions are the unit of randomization (`meter_auto_arm` hashes the
session id), so they are the unit the interval is computed over. 20,000 bootstrap resamples of the
24 treatment and 22 control session shares, seed 20260902, percentile interval, **no smoothing and no
pooling of the tails**:

| Statistic | Point | 95% bootstrap CI |
| --- | ---: | --- |
| median share, treatment ÷ control | 1.100 | **[0.772, 1.570]** |
| median share, treatment − control, in units of the control median | +0.100 | [−0.274, +0.473] |

`P(treatment median ≤ control median) = 0.341` across the resamples. The interval spans 1.000 with
room on both sides; at n = 24/22 sessions it would take an effect several times larger than anything
in this table to clear it. **This is a null with its power stated, not a null with its `n` hidden.**

**The sweep escalation, resolved against its own pre-registered band.** The band above asks for
`post_sweep=1` substitution ≥ 3×B to KEEP, ~1.4×B–3×B to REWORD, < ~1.4×B to DISABLE, over a minimum
of 200 rate-eligible `post_sweep=1` calls in ≥ 10 sessions.

| Registered quantity | Reading |
| --- | --- |
| minimum data (≥200 calls, ≥10 sessions) | **met**: 11,721 calls in 31 sessions |
| `post_sweep=1` ÷ B, where B is the same arm's whole-window rate | **0.998×B** |
| `post_sweep=1` ÷ the same arm's own `post_sweep=0` calls (n = 170) | 0.879× |
| secondary (c): `unclassified` share under 15% | 5.5% — instrument not drifting |

**0.998×B is a DISABLE by the rule as written**, and the rule was written in July, before any of these
rows existed. The second row points the same way and is reported second because its denominator
(n = 170) is far too small to decide anything on its own — the escalation fires at the third call of a
class, so a session has almost no `post_sweep=0` history by construction. That smallness is a property
of the mechanism, not of this window, and it is why the whole-arm B is the primary reading.

**The control arm kills the last alternative explanation.** Aligning every session on the escalation
moment and comparing the 15 rate-eligible calls after it to the 15 before:

| Arm | sessions | n before / after | after ÷ before |
| --- | ---: | --- | ---: |
| treatment (a real escalation fired) | 31 | 131 / 248 | 0.901 |
| control (the counterfactual moment, nothing was said) | 22 | 92 / 217 | **0.565** |

Both arms decline, and the arm that was *never spoken to* declines **more**. The post-nudge dip that
motivated three rounds of retuning is regression to the mean after a burst of same-class retrieval,
which is exactly what a sweep is. Nothing the hook said moved it. At `post_sweep=1` the two arms stand
at a treatment ÷ control ratio of 0.709, which carries the same repository-composition confound as the
pooled row above and is reported for completeness rather than as a second finding.

**Consequence, applied — the negative is the deliverable.**

- The base tier's one-time tips and the sweep escalation both stop emitting text, in both arms.
- Everything that makes the moment *measurable* stays: the same eligibility rules, the same
  `.obs`/`.deliv`/`.last` counters, the same cooldown policy, in both arms. The row now says `retired`
  where a base-tier delivery would have happened and `retired-sweep` where an escalation would have —
  see the schema note in `docs/SUBSTITUTION_METER.md`, which maps the old `nudge` vocabulary onto the
  new one so a comparison across this commit is possible rather than merely tempting.
- The arm is retained and still assigned. It now separates exactly one behaviour, the **SessionStart
  primer**, which the control arm does not receive. The PreToolUse path is byte-identical in both arms
  and `test/hookcheck.sh` arm M20b asserts that directly.
- `RIPWIRE_SWEEP=0` — the config-only kill switch the registration insisted on building before the
  measurement — is now moot for delivery and gates the escalation's counters only. Building it early
  still paid: the decision cost a policy change and no rollback.

**Confounds, stated in full — the same ones as the registration above, plus two this readout adds.**
Single operator. Heavily biased toward this repository, the least representative corpus available.
The nudge is a cause of the call it counts, which is why `post_nudge` and `post_sweep` exist. And two
that are specific to this reading:

- **Repository composition is not balanced across arms**, for the reason above; the pooled row is
  reported and then set aside rather than quietly dropped.
- **~14% of the `grep`-class rows in this window are polls, not searches** — `grep -c`/`grep -q` over
  a running job's log, and `ps aux | grep` liveness checks — and they are not evenly distributed
  across arms. Removing them raises the treatment arm's share by a factor of 1.09 and the control
  arm's by 1.02, i.e. the measurement artifact runs in the direction of *understating* treatment.
  It is far too small to overturn a CI of [0.772, 1.570], but it is a real defect in the denominator
  and it is fixed in the commit after this one (`build-poll` / `process-poll`, family `meta`,
  excluded from the rate like `gate-run`). Rows written before that fix keep the `grep` class; the
  classifier section of `docs/SUBSTITUTION_METER.md` records the boundary.

**Scope guard, unchanged.** This measures TOOL CHOICE. It is not a task-success claim; §8 explains why
that instrument stays unrun.

**What this does NOT license.** It does not say advice cannot move an agent's tool choice — it says
*this* advice, delivered at *this* moment (after the default has already been chosen, inside a
`PreToolUse` payload), did not. The 2026-08-10 finding that concentration in the skill and `CLAUDE.md`
text is what moved routing stands untouched, and the next instrument — the Claude Code prompt router,
pre-registered below — deliberately moves the intervention to a different moment: **before** the first
tool is chosen, with a paste-ready command instead of a verb name.

### Claude Code prompt router — PRE-REGISTERED 2026-09-02 (before any router code, and before deploy)

The readout above retired an intervention that arrived **after** the agent had already chosen a
default, inside a `PreToolUse` payload, carrying a verb name. This registration moves the intervention
to a different moment and gives it a different payload, and registers the band **before** the code
exists so that the next negative is as publishable as the last one.

**The mechanism under test.** `hooks/ripwire-claude-route.sh`, a Claude Code `UserPromptSubmit` hook.
On every submitted prompt it asks the deterministic `--help-task` classifier — the same one gated by
`test/taskroutecheck.sh` at precision 1.000 / harmful 0.000 — and, **only** when that classifier
returns `status="recommend"`, injects ONE paste-ready command as `additionalContext`. At
`status="abstain"` it injects nothing at all. It is the Claude Code port of
`hooks/ripwire-codex-route.sh`, which has shipped for Codex since 2026-08-28 and has never seen a
measured session, because every measured session in this account runs in Claude Code.

**Three things differ from the retired nudge, and they are the hypothesis.** (1) The moment: before
the first tool is chosen, not after. (2) The payload: a runnable command with the arguments filled in
from the prompt, not a verb name and an ellipsis. (3) The gate: a classifier with a measured
precision, so the intervention is silent on the ~17% of prompts it cannot route rather than firing on
everything. Any of the three could be the thing that matters; this round cannot separate them and does
not claim to.

**Primary metric — adoption-within-two, on recommended prompts only.** For each `UserPromptSubmit` row
with `status="recommend"`, look at the next **two** ripwire-family tool calls in that session and ask
whether either of them used the recommended verb. `adopted` / `missed` / `continued` are written by the
hook itself, at observation time, into `~/.ripwire/routing.jsonl` — the `--observe` arm is invoked from
the existing `PreToolUse` hook, so the outcome is an assignment the analysis reads rather than one it
reconstructs from a transcript. The unit is a recommended prompt.

**The control arm is a real counterfactual, not an absence.** The arm is decided by the same stable
session-id hash the meter uses (`meter_auto_arm`), so a session is on the same arm in both instruments
and the two logs join. A control session runs the classifier, writes the identical
`UserPromptSubmit` row and the identical pending file, and **injects nothing**. Adoption-within-two is
therefore measurable on both sides: the control arm's number is "how often would the agent have run
that verb anyway", which is exactly the quantity the retired nudge never had and the reason its three
readouts were all uninterpretable.

**Band, pre-registered before the first row exists.** This is a difference between two arms, not a
level, so it is stated directly:

| Verdict | treatment − control, adoption-within-two on recommended prompts |
| --- | --- |
| **KEEP** | **≥ +10 pp** |
| **REWORD** (inconclusive) | 0 pp – +10 pp |
| **REMOVE** | **≤ 0 pp** |

**Minimum data: ≥ 40 recommended prompts per arm.** Below that the readout is declared
**underpowered** — not null — the router stays on, and the clock extends by two weeks, once. A second
underpowered readout is a REMOVE: a router that cannot accumulate 40 recommended prompts per arm in a
month of daily use is not reaching enough moments to matter, whatever its conversion rate would have
been. The 95% interval is to be computed with sessions as the unit, as in the readout above, and
reported with its `n` — the retired nudge's whole problem was three readouts with no interval on any of
them.

**Secondary, reported but not gating.** (a) Substitution share (`bench/substitution_report.py` §1, the
per-session and per-repo cuts, never the pooled one) over the same window, treatment vs control — the
router should move tool choice generally, not only on the prompts it spoke on. (b) Coverage: the
`recommend` share of all prompts, which the `--help-task` corpus measures at 0.825 and which this log
measures in the wild; a coverage collapse invalidates the readout the same way an `unclassified`
drift does. (c) Route accuracy in the field is **not** measurable from this log by construction — the
rows are hash-only — and no number resembling it will be reported from it.

**Decision rule.** One readout, at four weeks (or six, under the extension). KEEP → the router stays as
shipped. REWORD → one revision of the injected framing text, then a fresh registration with a new band;
the mechanism is not re-litigated. **REMOVE → the hook is unregistered from the installer and deleted**,
not left in place behind a flag. That is a deliberate change from the retired nudge's disposition,
which was written as a config flip and consequently sat inert and unread for three weeks after its own
data said to turn it off.

**The instrument records no prompt text, by construction.** `routing.jsonl` rows carry a `cksum` of the
prompt and its byte length, never the text; the session id is hashed too. Prompt recovery from this log
is not a policy, it is impossible. `RIPWIRE_ROUTE_METER=0` opts out of logging without disabling
routing, and an explicit `RIPWIRE_HOME` keeps fixture runs away from the operator's log — the same
two-layer guard `docs/SUBSTITUTION_METER.md` §Fixture isolation describes, for the same reason.

**Prompt-injection posture, registered as a contract rather than an aspiration.** The injected context
is assembled from exactly two sources: compile-time constant framing text, and the `--help-task`
classifier's own XML output, whose intent and command strings come from the binary's route table. **No
repository content reaches it** — not a file name, not a symbol, not a match — and the user's prompt
reaches it only as whatever the classifier echoes of it. `test/routehookcheck.sh` proves this with a
hostile prompt carrying XML and JSON structure breakers plus imperative instructions, and asserts that
the hook's stdout stays well-formed JSON whose `additionalContext` contains none of the injected
markers. A router that can be steered by the thing it is reading would be a worse failure than a router
that does not work.

**Confounds, stated in full and in advance.** Single operator; heavily biased toward this repository.
The router is a cause of the call it counts — that is the point, and it is why the metric is a
between-arm difference rather than a level. Adoption-within-two is a proxy for usefulness, not a
measure of it: an agent that reads the recommendation, decides it is wrong, and does something better
scores as `missed`, and this instrument cannot tell that apart from an agent that ignored it. The
window is two calls because a longer one collects verbs the agent would have reached anyway; that
choice is registered here rather than tuned after the readout. And the `--help-task` classifier
abstains on the data-flow prompt family (four of four probes as of 2026-09-02), so the `recommend`
population is biased toward the intents it already covers.

**The readout is a LATER session.** This lane ships the instrument and the band. Nothing in this
registration is a result.

**The readout instrument.** `python3 bench/routing_ab_report.py [--routing PATH] [--meter PATH]
[--since AT] [--until AT]` (defaults: `$RIPWIRE_HOME/routing.jsonl` and
`$RIPWIRE_HOME/substitution.jsonl`) computes exactly the metric above: per arm, recommended-prompt
count and adoption-within-two rate; join coverage against the substitution meter; and the
pre-registered KEEP/REWORD/REMOVE verdict once BOTH arms clear 40 recommended prompts, or a refusal
line naming the band and how many more recommended prompts each arm still needs. It never opens
anything but the two given paths, filters to `agent="claude"` rows (routing.jsonl is shared with
`hooks/ripwire-codex-route.sh`'s separate, un-armed instrument — `bench/routing_report.py`, the
existing single-arm Codex-adoption reader documented above under "`--help-task` adoption"), and
carries no flag that overrides the floor. Gated by `test/routingreportcheck.sh`.

**The abstain-shape question — PRE-REGISTERED 2026-09-03 (before the sweep below is read).** The
first weeks of `routing.jsonl` are ~90% `abstain`, and every abstain carries an EMPTY intent: the
classifier matched nothing, so the row is "not recognised as a ripwire moment", not "verb withheld".
Two explanations are indistinguishable from the log by construction (it stores no text): (a) the
classifier's recall is the bottleneck — agents do type ripwire-shaped prompts and `--help-task` misses
them; (b) the prompt population is the bottleneck — most prompts are chat, git, and edits that no verb
serves, and the recommend rate is an honest ceiling. Widening the recommend set is only justified
under (a); under (b) it would spend the classifier's measured precision (1.000 / harmful 0.000) on
prompts that never wanted a verb and drag the treatment arm the band above measures.

*Instrument A, run now:* `--help-task` over every labelled prompt of `test/skillevalfix/prompts.tsv`
(266 prompts whose `expected` column names a ripwire skill, i.e. prompts an agent DID type at a
ripwire moment), argv `ripwire . --exclude=bench/external --help-task="<prompt>"` on this repo at the
commit that carries this section, reported as coverage (share of `status="recommend"`) overall and
per expected skill. *Band:* coverage **≥ 0.80** → the classifier recognises ripwire-shaped prompts and
the wild abstains are read as (b): waiting for n ≥ 40 per arm is the honest course and no intent is
widened. Coverage **< 0.60** → (a): the classifier is the bottleneck; the per-skill table names the
intents to add, the additions are registered as their own band, and the A/B window RESTARTS (rows
before the change are never pooled with rows after). Between the two → inconclusive; instrument B
decides. *Known prior, stated so it cannot be re-read as a result:* `test/taskroutecheck.sh` reports
coverage 0.825 on ITS corpus (`test/taskroutefix/`, 159 rows), a corpus the router was tuned against;
prompts.tsv was labelled for skill routing, not for the verb router, so it is the harder, fairer set.

*Instrument B, owner opt-in, NOT built:* a local-only labelled sample of ≥ 100 real abstained prompts
(never committed, never leaves the machine — the meter's no-text rule is the reason this needs a
separate consent), each labelled ripwire-shaped or not by hand. *Band:* ≥ 50% ripwire-shaped →
treat as (a) above; otherwise (b). Until B exists, an inconclusive A stays inconclusive.

**Instrument A, RUN 2026-09-03 at `6e397e1` (dev build, `./build/ripwire . --exclude=bench/external
--help-task="<prompt>"`, 266 prompts, 6 worker threads, output deterministic per prompt):** coverage
**0.023 — 6 recommends / 260 abstains.** The band says **(a): the classifier is the bottleneck**, and
the margin is not close. The six recommends were `--from-trace` ×2, `--pack-task`, `--exemplar`,
`--situ`, `--for`. Per expected skill, every one of the seventeen skill buckets is at or near zero:
find-bug 3/15, change-check 1/13, before-you-build 1/12, quality-bar 1/12, reuse-first 1/11, and
**0** of 12 for orient, navigate, efficient, write-tests, mcp; 0 of 11 for perf-target, security-scan,
handoff, layers, graph-query; 0 of 14 fresh-eyes; 0 of 9 opt-remarks (the 68 `none`-labelled prompts
abstained 68/68, which is correct). Against the stated prior — 0.825 on `test/taskroutefix/` — this is
a **36× gap between the corpus the router was tuned on and a corpus labelled for the same moments by a
different hand**, which is the definition of overfitting a fixture.

*Confound, stated:* many prompts.tsv rows name symbols from other repositories (`parseHeader`,
`resolveTypes`), and `--help-task` guards symbol-bearing recommendations behind `resolved_symbols` on the
root it is run against — by design, so that it never pastes `--callers=X` for an X the tree does not
have. That guard explains SOME abstains in navigate/find-bug. It explains none of the symbol-free
moments: "I just landed in an unfamiliar repo — what matters here" (orient), "which tests should I run
for this change" (change-check → `--affected`/`--situ`), "what does this PR actually touch"
(`--pr-context`), "did I change a contract someone depends on" (`--edit-check`) all abstained with
`resolved_symbols` irrelevant to the verb. Those are the intents to add.

*Consequence per the registration:* the widening is funded, but not as a tweak. The added intents are
registered as their own band (precision must stay at the router's current 1.000 / harmful 0.000 on
BOTH corpora, coverage on prompts.tsv ≥ 0.60 for the symbol-free buckets), `test/taskroutecheck.sh`
gains prompts.tsv as a second, held-out corpus so the fixture cannot be re-tuned into, and the A/B
window in `routing.jsonl` RESTARTS at the commit that lands them — rows before it are never pooled
with rows after. Instrument B stays owner opt-in and is not needed to fund this. Until the widening
lands, the readout above keeps refusing at n < 40 per arm; the current rows are kept as the
pre-widening baseline, labelled as such.

### `--help-task` widening — PRE-REGISTERED 2026-09-03 (before any intent is added)

**What changes.** The router gains intents for the SYMBOL-FREE moments instrument A found it blind to,
and nothing else: orient ("what is this codebase / what matters here / how is it organised" →
`ripwire <root>` default map or `--tree`), tests-for-change ("which tests should I run / did I run the
right ones" → `--affected`/`--situ`/`--test-gate`), pr-footprint ("what does this PR touch / is it safe
to merge" → `--pr-context`), contract-after-edit ("did I change a contract someone depends on" →
`--edit-check`; symbol-bearing form already routes), done-check ("is this ready / what did I make worse"
→ `--quality-delta`), untested-code ("what has no test / where are the seams" → `--seams`),
handoff/rot ("hand this area off / where is the rot" → `--hotspots` and `--around`). The symbol-bearing
guard (`resolved_symbols`) is NOT relaxed: a verb that takes a symbol is still recommended only when
the symbol resolves on the root. Abstain stays a first-class answer.

**Corpora, fixed before the build.** *Tuning corpus:* `test/taskroutefix/` (159 rows) as today.
*Held-out corpus:* `test/skillevalfix/prompts.tsv` (266 labelled + 68 `none`), which the lane may not
edit. Its `split` column is the firewall: the **83 `dev` rows may be read for phrasings** while intents are
written; the **183 `test` rows are never opened by the lane** and are the ONLY rows the band below is
scored on, via a new held-out arm of `test/taskroutecheck.sh` that reads them itself. Instrument A's
0.023 was measured over all 266; the pre-widening `test`-split figure is re-derived by the gate's first
RED run and recorded beside it, so the before/after is on the same rows. Prompts whose expected skill is symbol-bearing (navigate,
find-bug with a named symbol, graph-query) are reported separately from the symbol-free buckets, on the
ripwire root, so the guard's refusals are not scored as misses.

**Bands (all conjuncts, measured by `test/taskroutecheck.sh` on the commit that lands the intents):**

| Criterion | Band |
| --- | --- |
| Precision on the tuning corpus | **1.000**, harmful **0.000** (unchanged; a single harmful recommendation is a REJECT) |
| Precision on the held-out corpus (recommended prompts whose verb is in the `expected` skill's verb set) | **≥ 0.95**, harmful **0.000** |
| Coverage on the held-out symbol-free buckets (orient, change-check, quality-bar, write-tests, efficient, handoff, fresh-eyes, layers, before-you-build, reuse-first) | **≥ 0.60** (was 0.02) |
| Coverage on the held-out `none` bucket (68 prompts that want no verb) | **≤ 0.05** (was 0.00; false recommends here are the cost the band exists to cap) |
| Wall time per `--help-task` call | ledger only (`bench/PROFILE.md`), never a gate |
| Determinism | ×2 byte-identical per prompt, cold == warm |

**NEGATIVE consequence.** Any conjunct missed → the intents do not ship; the numbers ship as a registered
negative with the per-bucket table, and the classifier stays as it is. Meeting coverage by raising `none`
false-recommends above 0.05 is the specific failure this table refuses.

**Window restart, registered now.** `~/.ripwire/routing.jsonl` rows written before the landing commit
are the pre-widening baseline and are never pooled with rows after it; `bench/routing_ab_report.py`
gains `--since=<landing-commit-time>` semantics for the readout and prints which population it read.
The `n ≥ 40 recommended prompts per arm` floor restarts from zero at that commit.

### The auto-cache key ignores `--exclude` — PRE-REGISTERED 2026-09-03 (found by PROFILE_SCOPE, before any fix)

**What was measured.** A warm default map of this repository's root took **773 ms** on the dev machine
while a cold `--no-cache` parse of the same root took 340 ms on 11 cores. `RIPWIRE_PROFILE=ON`
(`src/infra/profileScope.h`) put 536 ms of the warm run in `loadCache` — 372 ms deserialising file
records, 89 ms on the checksum trailer, 74 ms reading the blob — against 31 ms of parsing. The blob
being loaded was **686 MB**: `main.cpp::defaultCachePath` keys the auto cache on the root's realpath
and the lean/rich class only, so `ripwire .` (which crawls `bench/external`, twelve vendored
checkouts) and `ripwire . --exclude=bench/external` share ONE blob. Reproduced both ways: with the
686 MB blob present the excluded run reports `reparsed=0 reused=1674` and pays 535 ms to deserialise
a superset it then discards; with it moved aside the excluded run rewrites a **9.5 MB** blob
(`reparsed=1668`) and the next un-excluded run cold-parses ~15,000 files (5.0 s). Under an explicit
`--cache=PATH` the same excluded run loads in **8 ms** (41 ms ingest total) — the number the README's
"warm" claim is actually about. This is the A4-P4 class-switch thrash again, on the exclude axis;
`quality.h::exclConfigHex` already folds the exclude set into the quality caches' keys and the
ingest cache never adopted it.

**Registered fix and bands.** Fold the exclude set and `--max-file-size` into the auto ingest-cache
key (the `exclConfigHex` material, one blob per exclude configuration per root, still lean/rich
split; `evictOldCacheFamily` bounds the disk cost as it does today). Bands, all conjuncts, measured
by a new `test/cacheexclkeycheck.sh` written RED first: (1) `.` → `. --exclude=X` → `.` reparses
**0 files** on the third run (today: ~15,000); (2) the excluded warm run's `loadCache` is within
**2×** of its explicit `--cache=PATH` time on the same tree (today: 535 ms vs 8 ms); (3) output
byte-identical to `--no-cache` for both configurations, determinism ×2; (4) `portablecachecheck`,
`cachesplitcheck`, `cacheisolationcheck`, `evictioncheck`, `savecachecheck` green with any pinned
blob names re-derived in their own commit with the reason; (5) wall-time numbers go to
`bench/PROFILE.md` as a ledger row, never a red gate. NEGATIVE consequence: if (1) or (3) cannot be
met the key change is reverted and the thrash is disclosed in `--doctor`'s `cache-dir` row instead.

**RUN 2026-09-03 — registered NEGATIVE for this shape; reverted in the same commit.** The lane
(`lane/n5-a`, four commits, patch kept on the branch and in
`PLAN_NEXT_REPORTS_2026-09-03-r4/lane-cachekey.md`) met all five conjuncts as written: third run
reparses 0; excluded warm `loadCache` **4.23 ms** vs **4.30 ms** under `--cache=PATH` (0.98×);
byte-identical to `--no-cache`; every named cache gate green with one pin re-derived; no timing gate.
The full battery on the merged tree then took **62 min instead of 7** (`gates=527 pass=470 fail=55`,
48 of the 55 at the 300 s cap on gates that finish in seconds). The mechanism the registration did
not model: the un-excluded root of this repository is **158,202 files** (`bench/external`), so each
configuration's blob is 686 MB; 116 gates invoke the root with at least twelve distinct
`--exclude`/`--max-file-size` sets; the cache directory's 2 GiB cap (`kMaxCacheDirBytes`, 7/8
hysteresis sweep) holds two such blobs, so under `-j6` the sweep deletes the blob a running gate is
about to reuse and that gate cold-parses 158K files again — a thrash across configurations that the
single superset blob, for all its 535 ms, never had. Verified the other way too: a two-configuration
sequence on a quiet machine does NOT thrash (both blobs coexist, both warm), which is why the lane's
own gate was green. **Consequence per the registration:** the key change does not ship; the thrash it
was written against stays disclosed here. Band (4)'s "eviction bounds the disk cost" was met literally
and was the wrong thing to bound.

**Retry design, registered now, not built.** Keep ONE superset blob per root (exclude-independent,
so a configuration never triggers a new crawl of files the blob already holds) and make the load
cheap for a subset: a record OFFSET TABLE in the blob (path-hash → offset, length, content-hash) so an
excluded run deserialises only the records for the files it crawled, and the trailer checksum covers
the table plus the records actually read. Bands, in addition to (1)–(5) above: **(6)** the full
battery's wall time on the dev machine is within 1.2× of the pre-change battery under the same `-j`;
**(7)** a configuration whose crawled files are all present in the superset blob never cold-parses
(reparsed=0 on its first run after any other configuration wrote the blob); **(8)** the blob count per
root stays at two (lean/rich). A `--cache=PATH` explicit blob keeps today's whole-file format.

**RUN 2026-09-03 — the retry SHIPS (`lane/n6-d`, kCacheVersion 15).** Built as registered: the auto-cache
key is untouched (`main.cpp::defaultCachePath` gains only a comment saying why the reverted key change
must not come back), and the blob gains a record offset table plus a 24-byte trailer. Two things the
retry design did not spell out and that the build made explicit:

* **The offset table alone does not meet band (7).** The registration frames the subset problem as a LOAD
  cost, but the measured thrash is a WRITE: a dirty subset run rewrote the shared blob with its own file
  set and every record for a file it had not crawled ceased to exist. So `saveCache` also carries those
  records over — byte for byte, out of the previous blob, each verified against its own `recSum` before it
  is trusted forward. The blob only ever grows toward the union of the configurations that share it.
* **`--cache=PATH` is UNIFIED onto the same format** rather than kept whole-file as the registration
  permitted. One format is one code path: an explicit blob then also gets the subset-cheap load and the
  carry-over save, and the alternative was two serializers that can drift with no gate on the difference.
  Portability (T5 root-relative record keys) is unchanged.

Layout, and what each checksum covers: HEADER 25 B (magic, version, parserVer, arch, blobWriteNs,
entryCount — the same shape as v14); RECORDS in ascending pathHash order, each the v14 per-file record
byte for byte; OFFSET TABLE of `entryCount × 32 B` (pathHash u64, recOffset u64, contentHash u64,
recLength u32, recSum u32); TRAILER 24 B (tableOffset u64, entryCount u32, reserved u32, tableSum u64).
`tableSum` covers HEADER ‖ TABLE and is verified on every open; each entry's `recSum` covers exactly its
own record and is verified for each record ACTUALLY READ; a record nobody reads is never checksummed and
never trusted. A torn write is caught by a file shorter than header+trailer, by the EXACT-FIT invariant
`fileSize == tableOffset + entryCount*32 + 24` (which is what catches a truncation that removes whole
records), or by `tableSum` — each rejects the WHOLE blob with a `DEGRADED_PATH_ALERT` and self-heals to a
full reparse. A record torn on its own while the table survives is caught by its `recSum`: that one file
reparses and the rest of the blob stands. A v14 blob is rejected AND disclosed, never misread.

Bands, measured. Gate `test/cacheoffsetcheck.sh`, written RED first at `8411f7e` (its three discriminating
arms failed there: band (7) reparsed 60 instead of 0, no `cached_records=`/`blob_entries=` existed, and
patching the header version to 14 was a no-op because 14 *was* the version):

| band | expected | measured |
| --- | --- | --- |
| (1) `.` → `. --exclude=X` → `.` reparses 0 | 0 | **0** (gate check (b)); and after a DIRTY excluded run, still **0** (check (c) — 60 before) |
| (2) excluded warm load within 2× of `--cache=PATH` | ≤ 2× | **1.0–2.0× at 10 ms resolution** — 0.01 s both, over a 31,000-entry superset blob (0.06–0.09 s on `d8fa59c`); structurally, `cached_records=1000 blob_entries=31000` |
| (3) byte-identical to `--no-cache`, determinism ×2 | identical | **identical**, both configurations, plus cold==warm; three-run byte determinism on this repo |
| (4) the named cache gates green, pins re-derived with reasons | green | **green**: `portablecachecheck` `cachesplitcheck` `cacheisolationcheck` `evictioncheck` `savecachecheck` `cachehashcheck` `cachefuzzcheck` `freshnesscheck` `statgatecheck` `racymtimecheck` `indexoutcheck` `artifactcheck` `tornreadcheck` `headsnapcachecheck` `qsnapcachecheck` `mcpstalecheck` `mcpincrementalcheck` `multirootcheck` `qextractionkeycheck`. One pin re-derived in its own commit: `test/qschemetrip.hash` (the manifest hash covers the `kCacheVersion` declaration line) |
| (5) wall-time numbers are a ledger row, never a gate | ledger | **`bench/PROFILE.md`**, "the offset-table cache blob (v15)" |
| (6) full battery within 1.2× of base under the same `-j` | ≤ 1.2× | **orchestrator measures** on the merged tree — see the in-lane decomposition below the table |
| (7) a configuration whose files are all in the blob never cold-parses | reparsed=0 | **0**. On the 31,000-file corpus, the wide run after a dirty narrow run: `reparsed=0` in 0.27 s, against `reparsed=30000` in 0.96 s on `d8fa59c` |
| (8) blob count per root stays at two (lean/rich) | 2 | **1 lean blob across three exclude/`--max-file-size` configurations** (gate check (a)); the reverted key change would have made this three |

**Band (6), what this lane can and cannot say.** The full-battery wall is measured after merge; a lane
cannot measure it, and a machine running several lanes at once cannot measure anything small. What was
measured in-lane is the 20-gate cache family, `d8fa59c`'s tree with `d8fa59c`'s binary against this HEAD's
tree with this HEAD's binary, sequentially, arms alternated: base 60.3 / 56.2 / 49.1 s, head 64.3 / 68.1 s.
Head is ~1.15× base and the difference DECOMPOSES, which is the only reason it is reportable at all under
that load: `cachefuzzcheck` 11.1 → 18.5 s (this lane added four mutations, each run twice — dev and ASan)
and `cacheoffsetcheck` +3.5 s (a gate that did not exist), against every other gate in the family being
level or faster (`qsnapcachecheck` 10.0 → 7.9, `statgatecheck` 6.7 → 5.6, `freshnesscheck` 2.7 → 1.6,
`evictioncheck` 3.5 → 2.5, `savecachecheck` 1.0 → 0.5). So the added seconds are gate COVERAGE this lane
chose to buy, not the tool getting slower — but the honest statement is that a ±20% reading on a loaded
multi-lane machine resolves neither, and band (6) is the orchestrator's measurement.

**The cost, disclosed.** The offset table is 32 B per file: +3.3% on a 31,000-file blob (30,147,173 →
31,139,189 B), all of it table. And a DIRTY subset save must copy the records it did not crawl — 0.13–0.40 s
for 30,000 records / ~30 MB, against 0.02 s for the v14 save that truncated them instead. That is the right
way round: v14 "saved" that time by destroying work which then cost 0.96 s to redo on every configuration
switch.

**Interaction with the `.gitignore`-by-default lane.** A default-ignore run and a `--no-ignore` run are
just two configurations over one root, so they share one blob exactly as `--exclude` configurations do. A
file present in the `--no-ignore` crawl and absent from the default one is a table entry the default run
never looks up (it is not in that crawl) and never drops (carry-over keys on pathHash, and a pathHash no
file in THIS crawl owns is preserved). The stat-gate is unchanged, so a served record is still gated on
`(size, mtime, ctime)` plus the content hash. Neither configuration can serve the other's records
incorrectly, because a record is only ever served to a lookup of its own path — confirmed by comparing the
record's own stored key against the key that found it, so even a 64-bit pathHash collision reparses rather
than answers.

### `.gitignore` honoured by default, `--no-ignore` to override — PRE-REGISTERED 2026-09-03 (owner decision 1-B)

**Why.** The tool is named for ripgrep, whose defining default is that ignored files are not searched;
today's crawler walks them. On the development machine that turns this repository's root into a
158,202-file corpus (twelve gitignored checkouts under `bench/external`), a 686 MB lean blob and a
1.3 GB rich blob that together sit at the cache directory's 2 GiB cap and evict each other, and every
gate that touches the root un-excluded into a 300 s timeout (the "timing gates red under load" of
several past rounds). For every other user it is `node_modules`, `.venv`, `target/`, `build/`, `dist/`:
the directories that make a first map slow and the ranking noisy, already declared by the repository
itself. The owner has ruled the corpus change acceptable (adoption is early; the best tool wins over
compatibility — the standing "new tool, no compat debt" rule), so it is recorded here as accepted, not
as a blocker.

**What changes.** In a git root the crawl consults git's ignore rules (`git ls-files --others
--ignored --exclude-standard --directory` or the equivalent walk, decided by the lane and stated with
its cost), skipping ignored paths; `--no-ignore` restores today's walk; non-git roots and roots where
git is unavailable keep today's behaviour and say so. `--exclude` keeps working on top. Multi-root
runs apply the rule per root. The header discloses `ignored_files=N` (absent when 0) and `--skipped`
lists the ignored set on request, so a symbol that vanished from the map because its file is
ignored can be found.

**Bands, fixed before the build, measured by a new `test/gitignorecheck.sh` written RED first.**
(1) A fixture with an ignored subtree: its symbols are absent from the map and counted in
`ignored_files=`; `--no-ignore` restores them byte-for-byte to today's output. (2) `test/golden.xml`
byte-identical (the fixture ignores nothing) — if it does not hold, that is a finding about the
fixture, re-derived in its own commit. (3) On the four D4 corpora at their pins, `ambiguous=`,
`files=`, `symbols=` re-pinned with the ignored count beside each, so the delta is disclosed, not
absorbed. (4) This repository's root without `--exclude`: `files=` drops from 158,202 to within 5% of
the excluded count, and the un-excluded warm map is within 2× of the excluded one. (5) determinism ×2,
cold == warm, xmllint, ASan on the crawl. (6) Wall time of the ignore walk is a `bench/PROFILE.md`
ledger row, never a red gate. NEGATIVE consequence: if (1) or (5) fail the default stays as today and
`--respect-gitignore` ships opt-in with the numbers.

### `.gitignore` honoured by default — RUN, measured 2026-09-03 against the bands above

**Verdict: ACCEPT on all six bands. The default ships; `--no-ignore` is the escape hatch, and the
NEGATIVE consequence (`--respect-gitignore` opt-in) did not trigger.** Bands (1) and (5) — the two the
registration named as the reject conditions — both passed clean. Every number below came out of the
plain build of this lane's commits, `test/gitignorecheck.sh` all-pass.

**The walk, and its cost (the decision the registration left to the lane).** Shell out to
`git -C <root> -c core.quotepath=false ls-files --others --ignored --exclude-standard --directory -z`,
once per root, rather than write a `.gitignore` matcher. A native matcher has to be bug-compatible with
git across nested `.gitignore` precedence, negation, `**`, the trailing-slash directory form,
`core.excludesFile`, `.git/info/exclude` and macOS case folding, and the moment it diverges it deletes
source from a corpus while claiming the repository asked for that. Shelling to git is exact by
construction, is not a new dependency (`gitmine.h`, `crossref.h`, `prcontext.h`, `quality.h` and
`binstale.h` already popen git; G3 is about what the binary LINKS), and degrades exactly as those do —
no work tree, or no git binary, and the crawl is today's full walk with `ignore_mode="unavailable"`
saying so on `--skipped`. `--directory` is load-bearing for the cost, not a convenience: a wholly
ignored directory is one entry and one prune, so a 12,000-file checkout costs what an empty one costs.
Measured probe time, median of 3: **ugrep 0.020 s, rocksdb 0.030 s, duckdb 0.150 s, this repository's
root 0.032 s**. `bench/PROFILE.md` carries the ledger row and the `--directory`-vs-full-enumeration
comparison (3,962 entries / 0.10 s without it, and still only a FLOOR — git stops at a nested `.git`).

| Registered band | Measured | |
| --- | --- | --- |
| (1) ignored subtree + loose file leave the map, counted in `ignored_files=`; `--no-ignore` restores them | `test/gitignorecheck.sh` (written RED at `4f6e601`, 15 of 29 assertions failing) is ALL PASS: fixture `files=` 6 → 3, `ignored_files=1 ignored_dirs=1`, `--no-ignore` restores all six symbols and emits no `ignored_*` | **meets** |
| (2) `test/golden.xml` byte-identical | **byte-identical** — `test/fixture` is fully tracked, so the fixture ignores nothing and no re-derivation commit was needed | **meets** |
| (3) the four D4 corpora re-pinned with the ignored count beside each | see the table below — all four **unchanged**, `ignored=0 ignored_dirs=0` on every one | **meets** |
| (4) this repository's root without `--exclude`: `files=` within 5% of the excluded count, warm within 2× | `files=` 8,674 → **1,522**, and the excluded run is **1,522** — a 0.0% delta; warm **0.10 s vs 0.10 s**, ratio 1.00 | **meets** |
| (5) determinism ×2, cold == warm, xmllint, ASan on the crawl | ×3 byte-identical on the root; cold == warm; `xmllint --noout` clean on the root map, the root `--skipped`, the fixture `--skipped` and `test/fixture`; ASan+UBSan+LSan rc 0 with EMPTY stderr on five arms (root default, fixture `--skipped`, a root-ignored root, multi-root, `--no-ignore`) | **meets** |
| (6) ignore-walk wall time is a ledger row, never a gate | `bench/PROFILE.md`, 2026-09-03 section. No timing assertion was added to any gate | **meets** |

**Band (3), the D4 re-pins.** Same binary, `ripwire <root> --no-cache`, each external tree verified at
its pin with a clean `git status`. `ripwire src/` is `git archive d8fa59c src` extracted to a scratch
directory, which is deliberately NOT a git work tree — so it is also the band's non-git control.
**Default output is byte-identical to `--no-ignore` on all four**, which is the finding: three clean
checkouts have nothing ignored to drop, and the disclosure attributes are correctly absent.

| corpus | pin | files | symbols | edges | `ambiguous=` | unresolved | `ignored=` / `ignored_dirs=` | `ignore_mode=` |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| ripwire `src/` | d8fa59c | 148 | 4,810 | 13,119 | 5,632 | 1,508 | 0 / 0 | `unavailable` |
| ugrep | `550599a6` | 156 | 3,626 | 5,388 | 1,722 | 5 | 0 / 0 | `git` |
| rocksdb | `0e2801ac` | 1,873 | 53,619 | 210,904 | 45,142 | 1,800 | 0 / 0 | `git` |
| duckdb | `19864453` | 5,123 | 61,178 | 84,698 | 8,929 | 2,650 | 0 / 0 | `git` |

These differ from the phase-3 table earlier in this document (`be3e1e6`: src 146 / 5,553, ugrep 1,721,
rocksdb 44,967, duckdb 8,934) by the commits between `be3e1e6` and `d8fa59c`, NOT by this lane — the
byte-identity of each corpus's default and `--no-ignore` output is the proof, and it is why the column
is re-pinned rather than the deltas being attributed.

**Band (4), and what could not be measured here.** The registration's 158,202-file figure is the
development machine's, and it could not be reproduced in this lane's worktree: the largest gitignored
tranche, `bench/external/swex/snapshots`, had been moved out of the tree for this round, and a fresh
worktree carries no `bench/external/` at all (its un-excluded root measures `files=1521`, which is a
tree with nothing to find, not a refutation). The band was therefore measured on a REBUILT stand-in —
the three D4 checkouts copied into the gitignored `bench/external/`, 18,995 files on disk — and the
stand-in was removed again before the commits below. The shape reproduces exactly; the magnitude is
smaller, and the orchestrator re-verifies the band on the full tree once the snapshots are moved back.

**Band (4), re-verified on the full tree by the orchestrator (2026-09-03, merged round-5 tree, snapshots
restored).** The development machine's real population, measured with `ripwire <root> --skipped` on the
merged binary, one cold run per arm with a private `TMPDIR`:

| `ripwire <repo root> <args>` | `indexed=` | `ignored_dirs=` | `ignore_mode=` | cold wall |
| --- | ---: | ---: | --- | ---: |
| `--no-ignore` (the pre-2026-09-03 walk) | **158,208** | 0 | `off` | 70.80 s |
| default (ignore rules honoured) | **1,682** | 1 | `git` | **1.44 s** |
| `--no-ignore --exclude=bench/external` (the workaround it replaces) | 1,682 | 0 | `off` | — |

The default and the hand-written `--exclude` agree **exactly** — 1,682 both, a 0.0% delta against the
band's 5% allowance — and the registration's 158,202 figure is confirmed at 158,208 (six files added to
the ignored tranche since it was written). The cold map goes 70.80 s → 1.44 s, a 49× reduction, on one
`ignored_dirs=1` prune. This is the band as registered; the in-lane stand-in above is retained because
it is what the lane's own commits were measured against.

**Cache interaction, stated precisely because it was checked rather than assumed.** The ignore mode is
NOT part of the cache key, and it does not need to be: the auto-cache blob is keyed per FILE
(`relForHash` path → `FileFacts`), so a `--no-ignore` run writes a SUPERSET blob and a following
default run can only ever read back the files it actually crawled. `gitignorecheck` arm 10 pins that
directly — a default run after a `--no-ignore` run is byte-identical to a default run before one. The
residual is a speed cost, not a correctness one, and it is disclosed in the ledger: the superset blob
survives (nothing is dirty, so `saveCache` is skipped), and a default warm run after a `--no-ignore`
run costs 0.18-0.19 s instead of 0.10 s until something invalidates it. This is the same shape
`--exclude` has always had — it also changes the crawl set and is also not in the key — and adding a
mode discriminator would trade a measured 0.08 s for a guaranteed full re-parse on every mode switch.

**One defect the bands did not name, found by building the thing.** Pointing ripwire at a directory
that is ITSELF gitignored (`ripwire build/` inside a repo whose `.gitignore` holds `build/`) makes git
answer `./` — everything. Honouring that literally returns an EMPTY map for a directory the user
pointed at deliberately. That answer is now recognised and refused: the full walk runs and `--skipped`
reports `ignore_mode="root-ignored"`. `gitignorecheck` arm 11 pins it, together with the other three
modes.

### A second router arm — route on the agent's FIRST TOOL CALL, not the prompt — PRE-REGISTERED 2026-09-03

**Why a second arm.** Instrument A above found the prompt classifier blind to 98% of labelled ripwire
moments, and the wild log is ~90% empty-intent abstains; the prompt is the noisiest signal available.
The agent's first `Bash`/`Read` call is the cleanest: `grep -rn NAME src/` names the verb and its
argument (`--grep=NAME`), a `Read` of a large source file names `--expand=SYM` or `--for` with the
file already known. The retired nudge (EVALS §4, negative) fired on the same events, but with generic
text and no argument; this arm pastes the exact command. The substitution meter already logs the
command and its two successors, so the control arm's counterfactual is free.

**Sizing, from the local meter (rates stay local; the lane report carries them).** Routable events —
a recursive grep of a source path, or a read of a source file, with build/process polls excluded —
occur two orders of magnitude more often than prompt-router recommendations, and their natural
follow-by-ripwire-within-two rate is **0.086**, which is the control arm's expected level. The band
is therefore the same difference the prompt router registered: KEEP ≥ +10 pp, REWORD 0..+10 pp,
REMOVE ≤ 0 pp, on ≥ 40 recommended events per arm — reachable in days rather than months.

**Design constraints, registered.** One recommendation per routable event with a per-session cap of
three (the nudge's negative is the reason: an un-capped hint on every grep is noise); the
recommendation carries the verb AND its argument, or it abstains; a symbol argument is recommended
only when it resolves on the root (the `resolved_symbols` guard, unchanged); notification-shaped
inputs (`[SYSTEM NOTIFICATION`, `<task-notification>`) never route; harmful **0.000** on a labelled
corpus of 200 real command shapes drawn from the meter's `detail` field (commands, not prompts —
local, never committed), precision ≥ 0.95. Arm assignment is the meter's `arm` per session, so the
two routers never disagree inside one session. The readout uses `bench/routing_ab_report.py` with a
`router=` column; the two arms are read separately and never pooled.

### Terminal-by-default `--for` — T3 round, PRE-REGISTERED 2026-08-12 (before the change)

**The mechanism under test.** `--for` becomes terminal by default: after the ranked signatures, the
bundle includes the top-ranked symbols' FULL bodies inline (CDATA, the `--expand` shape — body plus
inline callee signatures), assembled by the same `packBodies` machinery `--pack-task` already uses,
rank-first, whole-body-or-not-at-all (a body that does not fit is dropped and disclosed, never cut
mid-def). Disclosure rides the container: the `<ctx>` root carries `bundle="auto" bodies="N"`, and
when no body fits the remaining budget, `bodies="0" reason="budget"` — the signatures are unchanged
either way. The candidate cap is the `--pack-task` body-candidate cap, so the default `--for`
converges on the pack-task shape as budget allows. An explicit `--token-budget=N` stays a hard
ceiling: bodies take only the budget the signature bundle genuinely left over, and the signature
bytes themselves are computed exactly as before. Without an explicit budget, the default bundle
gains a fixed body allowance (a named constant beside `kForPayloadBudgetBytes`), and `est_tokens`
charges the bodies at the body byte rate, so the per-call cost is disclosed in the output that
incurs it. `--signatures-only` opts out and restores the previous signatures-only bundle
byte-identically; `--detail=N` (the explicit body knob) supersedes the automatic selection.

**Why.** The month-scale transcript mine measured the map-then-read chain as the single biggest
non-terminal pattern: a `--for` map whose named top file the agent then opens whole, or sweeps past.
The richer terminal verb (`--pack-task`) existed and was called zero times in the same month — the
richer answer must be the DEFAULT, not a reachable option (the one-step-smart-defaults rule).

**Primary metric, measured on TRANSCRIPTS by the next mining pass over post-deploy sessions,
per the pass-2 method:** (a) the map-then-read rate on `--for` episodes — the fraction of `--for`
calls followed within the episode window by a native read of a file the map itself named; (b) the
post-map sweep rate, reported DIRECTIONALLY only — it carries the question-granularity confound
that the T2 token-bridge lane owns, so it does not gate this round.

**Band, pre-registered before any post-deploy row exists.** The baseline LEVELS are operator
telemetry and live in the operator-local registration ledger (recorded there before this change
shipped); the band is a multiple of the ledger's baseline B for metric (a):

| Verdict | map-then-read rate on `--for` episodes |
| --- | --- |
| **KEEP** | **≤ 2/3 × B** (a drop of at least a third) |
| **REJECT** | otherwise |

The band measures exactly what inlining the body deletes: the read of the named file. A result out
of band REVERTS the default (signatures-only returns as the default; the explicit `--detail=N`
opt-in already exists and stays) and is recorded per `METHODOLOGY.md` §5, exactly like the LB-3 and
nameboost rejections.

**Guard.** Per-call token cost rises by construction (the body allowance) and is allowed to — ONLY
if session-level post-map sweep/read tokens drop. The net is the claim; a per-call increase with no
transcript-side drop is a REJECT even if metric (a) lands in band.

**Readout.** The next history-mine pass once ≥ 30 post-deploy `--for` episodes exist. Below that
the readout is declared underpowered — not null — and waits; the T0 terminality instrument
(`substitution_report.py` §5) doubles as the running ledger for the same verbs.

**Confounds, stated.** Observational, single-operator, biased toward this repository's own
sessions. The pass-2 episode method inherits its window definition; changing the window after
seeing post-deploy data would be tuning the instrument — the readout uses the same pass-2 method
that produced the baseline. Metric (b) confounded as stated above.

**Disclosure-gap correction, 2026-08-22 (found by measurement, fixed the same day).** The Lane-AA
transcript mine over the 2026-08-20 Stage-1 archive found 5 of 26 real `--for` episodes whose
`<ctx>` root carried **neither** `bundle=` **nor** `bodies=`: an explicit `--token-budget` whose
byte allowance the signature bundle alone exhausted turned the whole auto surface off silently —
and a gate arm asserted that silence as the contract. The registration's own sentence ("when no
body fits the remaining budget, `bodies="0" reason="budget"`") makes no exception for a fully
exhausted ceiling, so the code and the gate were wrong, not the registration. Fixed: the
disclosure now survives any ceiling (the attribute's bytes were already reserved in the budget
arithmetic), and the two `--for`-family paths that never serve bodies by design now say so from
their own side (`--for --json`: an always-present `"bundle":"sigs"` key; the MCP `for` verb and
`batch` for sub-query: `bundle="sigs"` on the ctx root plus a legend clause naming `fetch_body`).
Caller-chosen postures (`--signatures-only`, `--detail=N`) stay attribute-free by registration.
Gate: `test/fordisclosurecheck.sh` (every serving path), plus the corrected arm in
`test/forautobodycheck.sh` #3a. No registered number moves: the map-then-read metric counts reads,
not disclosures — but the mine's NO-BODY bucket classification depended on exactly the disclosure
that was missing, which is how it surfaced.

**A SECOND copy of the same silent branch, found and fixed at landing (2026-08-23).** This round was
authored against a trunk where every conceptual `--for` query still took the body walk. It landed on
one that had since gained the compact conceptual route, whose `<hops>` builder was written a day after
the body builder and had inherited the identical branch: an explicit ceiling the signature bundle had
already exhausted turned the compact surface off with **no attribute at all** — the same silent shape,
one serving path over. The same fix applies unchanged (`bundle="compact" bodies="0" reason="budget"`,
the attribute alone; its bytes are `kCompactAttrReserve`, already inside `committedBytes`), and
`reason="budget"` joins `"compact-route"` and `"no_candidates"` as a third distinct fact under that
builder's own two-reasons rule — the route choosing edges, nothing scoring, and the ceiling being
spent are three different things and none may be reported as another. `fordisclosurecheck` arm #1
therefore asserts the DISCLOSURE rather than one spelling of it (`bundle="auto"` on the body walk,
`bundle="compact"` on the `<hops>` shape, a `reason=` on every `bodies="0"`), and new arm #1b holds
the compact exhausted shape to the attribute-alone contract. Both halves were re-proved RED at the
merged tree by restoring each silent branch in turn. The lesson generalizes past this diff: the
disclosure contract binds serving PATHS, so a round that adds a path inherits it, and a gate that
names one shape's spelling stops watching the moment a second shape exists.

### Anchor-only auto bodies — T3 substitution round, PRE-REGISTERED 2026-08-22 (before any fix code)

**Scope guard, first, because it is the thing this round is most likely to be mistaken for.** This is
**not** a KEEP/REJECT on T3. T3's registered primary metric is the transcript-mined map-then-read
rate above, its readout waits on ≥ 30 post-deploy `--for` episodes, and no byte table can stand in
for it. This round changes one narrow behaviour *inside* the allowance and is judged on its own band.
The T3 registration's text is the boundary: it binds "rank-first, whole-body-or-not-at-all (a body
that does not fit is dropped and disclosed, never cut mid-def)" and the candidate CAP. It makes no
claim, anywhere, that a body other than the queried symbol's own may be served in its place — so
removing that behaviour takes nothing the registration promised.

**The mechanism under test.** When `--for`'s route names an ANCHOR — the `anchors: NAME(path)` clause
a name-exact reason carries — the auto-body candidate set becomes exactly that anchor, identified by
lowercased NAME *and* by the anchor's own defining FILE. A same-named symbol in a different file is
not the anchor. If the anchor's body does not fit the allowance, the bundle serves NO body and says
so through the disclosure that already exists for that case (`bodies="0" reason="budget"`, the
`<bodies shown="0" total="N" capped="1">` shell, and the per-item over-budget comment naming what was
dropped). Routes that name no anchor — a subtoken+body conceptual query — are untouched, because
nothing anchored them and there is therefore nothing to restrict to. `--detail=N`, `--pack-task`,
`--expand` and `--signatures-only` are all unaffected.

**Why.** Measured on the 12 symbol-lookup queries of the standing head-to-head query set, re-derived
at `3702693` with the corpora at their recorded pins: the allowance serves **19 body blocks**, of
which **8 are the anchor's own body and 11 are not**. The 11 are **43.9% of every served body byte**.
They are not near-misses — the largest is a `CHANGELOG.md` "Patch Changes" section that mentions a
class name and costs 8,605 B, i.e. the entire allowance for that query, while both real definitions
of the class sit next to it marked `body omitted (over budget)`. Others are a `types.d.ts` one-line
type stub, a re-export shim in `lib/index.js`, and two copies of a document's "Project overview"
heading. The pattern is structural rather than incidental: substitution happens exactly when the
anchor's own body is LARGE, which is exactly when a caller most needs it, and the replacement is by
construction something small enough to fit — i.e. something with less in it.

**Baseline, re-derived in this lane before any code was written** (not copied from the memo it
follows; the re-derivation reproduces that memo's per-query byte column exactly on all 12 queries):

| | class-A total bytes |
|---|---:|
| current default (allowance on) | **65,016** |
| `--signatures-only` (the registered opt-out) | **26,523** |
| the allowance, isolated | **38,493** |

The anchor's own body IS served on `get_object_or_404`, `make_password`, `bulk_create`, `subtokens`,
`pageRankDouble`, `pathQualifiedKey`, `takeRank` and `RuntimeTemplate` — 8 of 12. It is NOT served on
`URLResolver`, `ChunkGraph`, `seal` and `NormalModuleFactory`, the four whose anchor body is too large
for the allowance. `URLResolver` already serves nothing and discloses it; the other three each serve a
substitute instead.

**Band, pre-registered before the fix exists.** Judged on the same 12 queries, same binaryless method
(short relative roots, stdout to a file, warm index), as a two-sided byte band on the class-A total.
The band's derivation — a fixed external denominator from a head-to-head round the improve-first rule
keeps unpublished — lives in the operator-local lane report; only the resulting byte band is public,
because only the byte band is a fact about this tool:

| Verdict | class-A total bytes, 12 queries |
| --- | --- |
| **ACCEPT** | **48,703 … 54,547** (the projection is 51,548) |
| **REJECT** | outside that band |

It is two-sided on purpose. The upper bound is the payoff — the substituted bytes have to actually
leave. The lower bound is the trap: a total below it means the change did not merely stop
substituting, it also cost an anchor body that was already the right answer, and a cheaper bundle
bought by deleting correct answers is a regression wearing a win's numbers.

**Success criteria, all four required.** (a) The 8 anchor bodies above are still served, and each is
**byte-identical** to its pre-change text. (b) The four queries whose anchor does not fit serve no
body at all and disclose the zero. (c) The class-A total lands in the band. (d) Determinism holds
(byte-identical ×3) and the gate suite stays green.

**Failure criteria that revert the change, stated before it is measured.** Any anchor body lost from
the 8 — including one lost to a budget interaction rather than to the rule itself — or any regression
in the relevance floor's own gate. Either one reverts; neither is negotiable by re-reading the band.

**Confounds, stated.** The 12-query set is a symbol-lookup set on three corpora, authored for a
different round and frozen — it is not a sample of what agents ask, and the round claims nothing about
conceptual queries, which the rule does not touch. Byte totals move with the invoking path string,
because the root and per-section id strings are charged against the same budget that decides which
bodies fit; the baseline and the readout therefore use identical short relative roots, and a
long-absolute-path invocation is not a valid re-run of this band. The anchor's defining file is the
FIRST definition of that name in NodeId order, so on a name with several definitions the rule follows
the same disclosed choice the route header already prints, and inherits whatever that choice is.
### Compact conceptual serving — T3 route-narrowing round, PRE-REGISTERED 2026-08-22 (before any code)

**Scope guard, first, for the same reason the anchor-only round needed one.** This is **not** a
KEEP/REJECT on T3 and it does **not** repeal it. T3's registered primary metric is the transcript-mined
map-then-read rate above; its readout waits on ≥ 30 post-deploy `--for` episodes and the first
observational pass reached 26, which the registration itself declares underpowered rather than null.
Nothing below stands in for that readout. This round narrows **where** the body allowance applies: it
stays on the route T3's own evidence is about — the name-exact/anchor route, where the anchor-only rule
already governs *which* body may be served and the served body IS the queried symbol — and comes off the
conceptual (subtoken+body) route, which no round has ever measured the allowance on. The anchor-only
round's own confounds paragraph says as much in the other direction: "the round claims nothing about
conceptual queries, which the rule does not touch." Neither did T3's evidence.

**The mechanism under test.** When `--for`'s router chooses the subtoken+body ranker — a conceptual
query, the route that names no anchor — the default bundle becomes COMPACT: the ranked `<sigs>` map
exactly as `--signatures-only` renders it, plus a `<hops>` section carrying the ONE-HOP EDGE CONTEXT of
the same rank-first candidate head the body walk would have used (each candidate's `<calls>` callee
signatures, the identical `emitCalleeCallsBlock` disclosure that rides on a body today), and NO body
CDATA. Disclosure rides the container exactly as T3's does: the `<ctx>` root carries
`bundle="compact" bodies="0" reason="compact-route"`, the legend defines every attribute a reader meets,
and the legend names the continuation — the expand verb on any name in the map — so the map-then-expand
flow is a disclosed surface rather than a thing the agent has to guess. `--auto-bodies` is a **first-class, permanent opt-out** —
it restores today's bundle on this route byte-identically, and it is a standing posture flag beside
`--signatures-only` and `--detail=N`, not a migration aid with an expiry. A caller who wants inline
bodies on conceptual queries is a supported caller indefinitely; nothing about this round is scheduled to
remove the flag. The name-exact route, `--detail=N`, `--signatures-only`, `--pack-task`, `--expand` and
`--no-route` are untouched.

**Why — the byte economics, which is the whole case on its own.** Class B is the one class of the
standing head-to-head that fails the publication gate's ≤1.5× threshold, and it fails it badly: **2.39×**
the competitor's bytes, against 1.35× / 0.39× / 0.06× for the other three. The decomposition says where
that goes — bodies, CDATA plus their `<calls>` lists, are **52.7% of every class-B byte**, the majority
section in two of the three corpora. And a compact one-hop answer is a *demonstrated* shape at a
fraction of the cost, not a hypothesis: the competitor's own `context` verb answers a symbol
neighbourhood in 0.7–1.0 KB, carrying callers, callees and field accesses. Half the bundle's bytes, on
the one route that misses the gate, spent on a section for which a much cheaper form of the same
navigational value is known to exist — that is the case for this round, and it stands whether or not
any agent harness behaves the way the next paragraph describes.

**Supporting evidence, explicitly scoped, on what the body allowance buys an agent.** The first
transcript pass over post-deploy episodes found **17 of 17** body-serving episodes that produced an edit
doing a native read of the file first, **zero** clean body-use episodes, and 51,161 prepaid body tokens
riding *alongside* ≈48,339 tokens of native reads rather than replacing them. One mechanism behind that
shape is a property of the harness those transcripts came from: **Claude Code 2.1.209's `Edit` tool
requires a prior `Read` of the target file**, so under that harness+version a served body cannot
substitute for the edit-path read whatever the ranking does. **That scope is a limit on this evidence,
not a premise of the round.** Other harnesses (codex, opencode, aider) are not known to share the
contract, and it may change in any Claude Code release. **Re-measure trigger, registered here:** if the
Read-before-Edit precondition is removed or relaxed in a harness this tool is measured on, this
paragraph's support expires and the transcript pass must be re-run before it is cited again — the byte
case above is unaffected either way. Nothing in the implementation detects a harness, conditions on one,
or may be changed to do so under this round; the only condition the serving reads is the tool's own
route tag.

**Why one-hop edges and not plain `--signatures-only`.** Measured before the design was fixed, on the
15-query class-B set: of the 11 queries whose head-to-head note names a decisive symbol or file, ten
have that marker on a top-level signature row and ONE — `DJ-B1`'s `build_filter` — appears *only* inside
`split_exclude`'s `<calls>` list, four occurrences, none of them a `<d>` row. Both cheap existing levers
therefore destroy it outright: `--signatures-only` and `--token-budget=3000` each drop that marker
entirely (10/11 present), because a callee reachable only through another symbol's callee-signature list
has no home once the bodies section goes. Keeping the edge context is precisely what recovers it, and it
is the only measured reason to keep anything from the bodies section at all.

**Baselines, re-derived in this lane before any code was written** (short relative roots, stdout to a
file, warm index; corpora at the recorded pins `django@03988c5a5`, `webpack@a943d69c4`, this repo
`@4692076`, all three tree-hash verified clean; binary built at `85fef26`). The re-derivation reproduces
the class-A and class-B byte columns of the round it follows **exactly** — 52,480 B and 184,857 B — so
the instrument is the same one:

| arm, 15 class-B queries | bytes | ÷ GNX class-B (77,316 B, frozen) | markers present | markers with a full body |
|---|---:|---:|---:|---:|
| current default (allowance on) | **184,857** | 2.391× | 11/11 | 10/11 |
| `--signatures-only` | **79,375** | 1.027× | **10/11** | 0/11 |
| `--token-budget=3000` | **97,163** | 1.257× | **10/11** | 2/11 |

**The allowance constant, derived rather than tuned.** The compact section's own byte allowance is the
measured edge-context share of what the body allowance buys: `<calls>` lists are 14,602 B of the
97,470 B bodies section across the 15 queries, i.e. 15.0%, and 15.0% of `kForAutoBodyBudgetBytes`
(6,000 B) is **900 B** — `kForCompactHopBudgetBytes`. It is written down here before the readout so a
later reader can see it was not chosen to land the band.

**Band, pre-registered before the code exists.** Judged on the class-B TOTAL of the same 15 queries,
same method, as a two-sided byte band. The projection is 79,375 + 15 × 900 ≈ **92,875 B (1.201×)**:

| Verdict | class-B total bytes, 15 queries |
| --- | --- |
| **ACCEPT** | **79,635 … 96,645 B** (1.030× … 1.250×) |
| **REJECT** | outside that band |

Two-sided on purpose, and both sides are load-bearing. The upper bound is **1.250×**: it clears the
publication gate's ≤1.5× class threshold, clears the competitor-ratio target of ≤1.3×, and must BEAT the
best lever that already exists behind a flag (`--token-budget=3000`, 1.257×) — a new DEFAULT that is
worse than a flag anyone can already pass is not worth a default change. The lower bound is **1.030×**,
one point above the `--signatures-only` floor: a total at or below it means the compact route served no
edge context at all, i.e. it is `--signatures-only` wearing a new name, and it would carry that lever's
measured marker loss with it.

**Success criteria, all four required.** (a) The class-B total lands in the band. (b) Every one of the
11 judged-decisive markers is PRESENT in the compact bundle — 11/11, strictly better than either
existing lever's 10/11 — and for each marker whose body the baseline served, the decisive content is
reachable in ONE disclosed continuation call, with `compact bytes + expand bytes < today's one-call
bytes` for that query. (c) The name-exact route is byte-identical: all 12 class-A queries, and the 21
class-C/D queries, reproduce the pre-change capture byte for byte. (d) Determinism holds (byte-identical
×3), the gate suite stays green including the skill-routing floors and the frozen recall lanes, and
`--quality-delta` gates zero.

**Failure criteria that revert the change, stated before it is measured.** Any of the 11 markers
becoming unreachable — absent from the compact bundle AND not recoverable by one disclosed continuation
call. Any query whose two-call total exceeds today's one-call total. Any byte movement on the name-exact
route. Any guard regression. Each one reverts on its own; none is negotiable by re-reading the band.

#### The two-call criterion — SUPERSEDED, deliberate recalibration commit, 2026-08-22 (before re-scoring)

**Nothing above is deleted.** The two sentences this supersedes stay where they are, verbatim: success
criterion (b)'s second clause (*"with `compact bytes + expand bytes < today's one-call bytes` for that
query"*) and the failure clause (*"Any query whose two-call total exceeds today's one-call total"*).
This block replaces those two sentences and **nothing else** — the byte band (a), the 11/11 marker count
in (b), the byte-identity criterion (c), the guard criterion (d), and every other failure clause stand
exactly as registered.

**Why it is superseded, written before any figure is re-scored under it.** The superseded instrument
charges every marker ONE FULL `--expand` — which is the assumption that an agent needs the body 100% of
the time. This round's own evidence base measures that rate, and it is not 1. Over the 17 body-serving
`--for` episodes the first transcript pass classified: **BODY-USE — the episode that edited off the
prepaid body — was observed zero times**; 11 episodes were MAP-USE(insufficient), where the served body
demonstrably did NOT contain the text that was edited; 6 were AMBIGUOUS. A criterion that prices a
CONDITIONAL cost as an UNCONDITIONAL one is not measuring the thing it names, and that gap is the entire
disagreement between the two readings this lane recorded. This is the separate disclosed commit the
house convention requires for exactly this move — the snapshot/floor update policy earlier in this file,
and the precedent of the subtoken round, which left a behavioral arm red rather than reword it and said
so: *"the choice is the owner's: recalibrate the arm in a separate disclosed commit, or reject."* The
owner chose recalibrate. It is recorded here, ahead of the numbers, so that the recalibration cannot be
read as a band widened after seeing them.

**`p_body`, derived conservatively and fixed HERE, before use.** `p_body` is the probability that a
compact bundle costs the agent a follow-up `--expand` for the decisive content. Its derivation:

- The **empirical point estimate is 0/17 = 0.0** — the measured BODY-USE count. It is not used. A
  criterion built on 0 collapses the expected-cost arm into "compact alone is cheaper", which the
  per-query bytes already guarantee and which therefore tests nothing.
- The **11 MAP-USE(insufficient) episodes are excluded** on direct observation, not on convenience: in
  those the prepaid body did not contain the edited text, so a bundle that omits that body costs the
  agent nothing it was using. Charging an `--expand` for them would charge for a call the evidence says
  was not the substitute.
- The **6 AMBIGUOUS episodes are all charged as body-need** — every one of them, including the 2 with an
  empty window and the 4 whose per-edit verdicts disagreed. These are the cases the mining could not
  rule out, and the conservative move is to price every unresolved case against the change.

That gives **`p_body` = (0 BODY-USE + 6 AMBIGUOUS) / 17 body-serving episodes = 6/17 ≈ 0.353**, i.e. the
upper bound on the share of episodes in which the prepaid body could not be ruled out as the content the
agent actually needed. It is conservative in the direction that hurts this round: a higher `p_body`
makes the compact default look more expensive.

**The recalibrated criterion, result-free, BOTH arms required.**

| Arm | Test |
| --- | --- |
| **(a) expected cost** | for every query carrying a marker whose body the baseline served: `compact_total + p_body × expand_cost < today's one-call total` |
| **(b) worst case** | no query's RAW two-call total (compact + a full `--expand`, i.e. `p = 1`) may exceed today's one-call total by more than **+10%** |

Arm (a) is the criterion the superseded one should have been. Arm (b) is what stops (a) from being a
licence: an expected-value test can be cleared by a query that is catastrophic in the tail, so the tail
is bounded separately and unconditionally, at a margin fixed here rather than at whatever the data turns
out to need.

**The re-scoring is a re-scoring, and is bounded as one.** It reads the bytes already captured at this
lane's head. No query is re-run, no measurement is re-taken, no binary is rebuilt. It must additionally
**report the break-even `p_body` per query** — the value at which arm (a) would flip — so the criterion's
sensitivity to a constant chosen from n=17 is visible on the page instead of buried in it.

**Failure, and the end of the line.** If either arm misses, the round REVERTS. There is no third
criterion: a second recalibration after seeing a second set of numbers would be the band-widening this
block exists to not be.

#### READOUT — re-scored under the recalibrated criterion (2026-08-22, after the commit above)

Pure re-scoring of the bytes this lane already captured: no query re-run, no measurement re-taken, no
rebuild. 7 of the 11 markers had a body served at baseline and are therefore applicable; the other 4
never had inline content to recover and cost no continuation at all.

| id | marker | today 1-call | compact | expand | expected (p=0.353) | arm (a) | worst case | arm (b) | break-even p |
|---|---|---:|---:|---:|---:|---|---:|---|---:|
| DJ-B1 | `build_filter` | 13,057 | 4,442 | 5,090 | 6,239 | PASS | −27.0% | PASS | 1.693 |
| DJ-B2 | `_does_token_match` | 10,785 | 4,271 | 2,196 | 5,046 | PASS | −40.0% | PASS | 2.966 |
| DJ-B5 | `process_response` | 13,945 | 5,212 | 4,051 | 6,642 | PASS | −33.6% | PASS | 2.156 |
| RW-B1 | `subtokens` | 12,379 | 8,260 | 2,066 | 8,989 | PASS | −16.6% | PASS | 1.994 |
| RW-B2 | `kReductionBlockSize` | 14,220 | 8,454 | 6,552 | 10,767 | PASS | **+5.5%** | PASS | 0.880 |
| RW-B3 | `runAffected` | 14,510 | 8,398 | 7,059 | 10,889 | PASS | **+6.5%** | PASS | 0.866 |
| WP-B4 | `HotModuleReplacementPlugin` | 12,457 | 7,555 | 3,095 | 8,647 | PASS | −14.5% | PASS | 1.584 |

**Arm (a): 7/7 pass. Arm (b): 7/7 pass.** The two queries that failed the superseded criterion are the
only two anywhere near the bound, and their worst-case overruns are **+5.5%** (`RW-B2`) and **+6.5%**
(`RW-B3`) — both inside the +10% tail bound, stated plainly here rather than rounded away.

**Sensitivity, reported as the recalibration required.** Five of the seven applicable queries have a
break-even `p_body` **above 1.0**, meaning they pass even if the agent needs the body on every single
call. Only `RW-B3` (0.866) and `RW-B2` (0.880) are conditional at all, and both need the agent to want
the body **more than 86% of the time** before arm (a) would flip. Against a measured BODY-USE rate of
**0/17** and a maximally conservative bound of **0.353**, the headroom to the tightest query is **0.513**.
The verdict is therefore not knife-edge on the choice of `p_body`: every value from 0 to 0.866 gives the
same answer, and the constant would have to be wrong by more than a factor of two in the direction the
evidence does not support before it mattered.

**Verdict: ACCEPT.** Criterion (a) the byte band — 95,256 B, 1.2320×, inside 79,635…96,645 B.
Criterion (b) markers 11/11 present, and both recalibrated two-call arms clear 7/7. Criterion (c) the
name-exact route and classes C/D byte-identical. Criterion (d) determinism ×3, the full gate suite, the
sanitizers and `--quality-delta` (`gating="0"`) all clean. **Recorded as an ACCEPT under a SUPERSEDED
criterion**, which is the honest label: the round would have REVERTED under the criterion as originally
registered, the recalibration that changed that was made deliberately and in its own commit ahead of the
re-scoring, and both texts stand above so a later reader can judge the substitution rather than take it.

**Confounds, stated.** The 15-query class-B set was authored for a head-to-head round and frozen; it is
not a sample of what agents ask, and its one recorded loss (`WP-B2`) is a ranking miss that no
serving-side change can reach. "Markers present" is a substring test over the emitted bundle, which is
generous — it credits a name that appears anywhere — and "markers with a full body" is a substring test
against the `<b>` blocks, which is why this lane's full-body column for `--token-budget=3000` reads 2/11
where the memo that preceded it read 4/11 by a per-symbol rule; both instruments are stated so the
columns are not mixed. The GitNexus denominator is the frozen one recorded four days earlier and was not
re-run. Byte totals move with the invoking path string, so this band is only valid re-run at the same
short relative roots. And the one thing this round CANNOT show: whether an agent that gets edges instead
of bodies does better, worse, or the same. That is T3's own transcript readout, still waiting at 26 of
its 30 episodes, and this registration does not pre-empt it — if that readout later rejects the
narrowing, `--auto-bodies` is already the switch that restores the previous default on this route, and
it is a permanent flag rather than one that would have to be re-added.

### Auto-bundle section split under an explicit `--token-budget` — budget-inflation fix, 2026-08-22

**The defect, measured before any code moved** (the full decomposition:
`PLAN_HARVEST_REPORTS_2026-08-20/classb-bytes-memo.md` §2, on the r10 class-B conceptual set at
`4692076` with the corpora at their recorded pins). An explicit `--token-budget` ABOVE `--for`'s own
default gave the signature side FIRST CLAIM on the whole ceiling (`sigsBudget = ceiling − fixed`),
while the auto bodies' allowance (`kForAutoBodyBudgetBytes`) existed only in the default regime. So
`--token-budget=8000` (≈17.0 KB at the conservative rate, wider than the default's ~13.5 KB effective
ceiling) un-trimmed exactly the sig tail the default ladder trims — DJ-B1: `<sigs>` 1,782 B → 9,483 B,
8 rows → 40, `<lego>` re-expanding with it — and crowded the auto body walk from 6 served bodies down
to 2, dropping `split_exclude` (and with it the judged-decisive `build_filter` callee row). The class-B
15-query total rose to 3.33× the competitor baseline, *worse than doing nothing*, while serving less of
what the r10 judging credited. This is a distinct mechanism from LB-A's zero-score padding: it needs an
explicit ceiling wider than the default to fire, so the class-A measurements never saw it.

**The invariant, designed before the fix and gated red-first** (`test/forbudgetmonotoncheck.sh`, RED at
`4692076` on an engineered fixture reproducing the trap, GREEN after): **a wider ceiling never buys
less decisive content.** In auto-bundle mode with no explicit `--pack-top-n`, the sig side's claim on
the ceiling is `min( ceiling, kForPayloadBudgetBytes )` — so (i) the default regime is byte-identical
(its ceiling IS that budget; golden-neutral by construction), (ii) at any explicit ceiling ≥
`kForPayloadBudgetBytes + kForAutoBodyBudgetBytes` the `<sigs>`/`<lego>` render equals the default
regime's byte for byte, hence the bodies' leftover is provably ≥ the default's and every body the
default serves still fits, and (iii) within that band a larger ceiling serves a body superset. Body
COUNT inside one `packBodies` walk stays rank-priority (the §H5 re-diagnosis stands un-relitigated);
this invariant binds the SECTION split, not the walk. An explicit `--pack-top-n` is an explicit sig
posture and keeps the legacy whole-ceiling claim; `--signatures-only`, `--detail=N` and `--json` have
no auto bodies to reserve for and are likewise uncapped.

**Discipline note.** Serving-side ADMISSION only, the LB-A class: no score moves, no candidate
re-ranks, and the default bundle is byte-identical — which is why this is a defect fix with a
red-first gate rather than a pre-registered-band round. Verified on the memo's own trap: DJ-B1 at
`--token-budget=8000` now serves the default's full 6-body set (13,057 B, `split_exclude` body and
`build_filter` row included) instead of 17,419 B carrying 2 bodies. T3's transcript-mined primary
metric is untouched by this entry.

**What the DJ-B1 numbers above are anchored to, and what changed under them at landing** (2026-08-23,
merging this round onto a trunk that had since gained the compact conceptual route). Every byte figure
in this entry — 1,782 → 9,483 B, 6 → 2 bodies, 13,057 B vs 17,419 B — was measured at `4692076`, where
a conceptual `--for` query still served the rank-first body walk by default. On the trunk it landed on,
that same query routes COMPACT (`bundle="compact" bodies="0" reason="compact-route"`), so it serves no
bodies at all until `--auto-bodies` restores the walk, and the body-count figures do **not** reproduce
verbatim at HEAD — they are the pre-landing measurement of the defect, not a claim about today's
default. **The rule itself is unchanged and now gated on both serving shapes**: the sig-side cap keys
off `autoBundleMode`/`packTopN`, which the compact route shares, so an explicit ceiling cannot
re-inflate `<sigs>` there either — the leftover is what the `<hops>` section draws on instead of the
bodies. `test/forbudgetmonotoncheck.sh` passes `--auto-bodies` on its body arms (without it every body
comparison would be empty-vs-empty and pass vacuously) and carries arm #5 for the compact shape; all
four failure arms were re-proved RED at the merged tree by neutering `forSigSideCeiling`.

### Markdown section tier — G2/G3 round, PRE-REGISTERED 2026-08-12 (before the change)

**What the round deletes.** The residual this tier removes is *"find the section inside the doc"*:
before it, a doc-retrieval episode that landed on the right FILE still had to locate the section by
hand — a follow-up heading-grep, or reading the whole doc — because headings were name-only symbols
with no body span, `--expand` of a heading returned one line, and `--recall` served whole documents.
The tier makes the section the retrieval unit (heading = symbol, section span = body, hierarchy =
scope, links/mentions = edges), so the answer to a doc query TERMINATES at the section.

**Registered claim, judged by the next transcript mining pass over post-deploy sessions.** Among
doc-retrieval episodes (an episode whose retrieval target is a markdown document, per the mining
pass's existing episode classifier), the POST-CALL section-localization rate — a heading-grep on, or
whole-file read of, a document the preceding ripwire call already returned — should fall
**materially: to half or less of the pass-2 recorded rate for those episodes** (the band is a
multiple, ≥2-wide by construction: anything between "unchanged" and "halved" is a MISS and gets the
honest REJECT). The pass-2 absolute rate stays in the local ledger (levels are ledger-local, per the
plans-stay-local rule); this registration binds the mechanism and the multiple, not the level.

**Guards.** (1) Denominator: only episodes whose doc query the tier can serve (a `.md`/`.markdown`
corpus doc) count — docparse-extracted notebooks/html keep their whole-doc path and are out of
scope. (2) The comparison uses the SAME episode classifier on both sides; if the classifier changes,
re-run it over the pass-2 window first (the S2b instrument-correction discipline). (3) This is a
tool-output-shape claim, not a task-success claim — §8's power argument stands.
### `--verify` terminality — G4 verify-a-claim round, PRE-REGISTERED 2026-08-12 (before any post-deploy row)

**What shipped.** `--verify="CLAIM"` — a closed claim language (`calls`/`uses`/`unused`/`contains`/
`defines`/`reaches`) answered with a three-valued verdict (`confirmed` / `refuted` / `not-established`)
plus inline evidence, gated by `test/verifycheck.sh`. It is built entirely from machinery that already
existed (`--path`'s BFS, `--uses`' reference index, `--grep`'s exhaustive literal scan with its
completeness bits, `--impact`'s transitive reach): the round's claim is not new data but a COLLAPSE —
the residual it deletes is the manual verification grep-chain, the transcript mine's largest verb-less
intent class.

**Primary metric (transcript-observable, no meter accrual needed).** Verification-intent episode
CHAIN LENGTH: the number of native-search calls (grep/read/glob families, rtk-unwrapped) an agent
spends per verification-intent episode, measured by the next mining pass over post-deploy sessions
with the same intent-classification the month-scale mine used. The baseline B is the same statistic
computed over PRE-deploy sessions by the same pass — computed at readout, recorded in the
operator-local registration ledger before the post-deploy half is read (levels stay in the ledger per
the telemetry rule; this document carries the mechanism and the band shape only).

**Band, pre-registered.** KEEP ⇔ post-deploy mean chain length ≤ 2/3×B on episodes where `--verify`
fired (the T3 convention); inconclusive between 2/3×B and B extends the window once; ≥ B on
verify-using episodes, or a false-verdict report of any kind, is a REVISIT with this section updated
per METHODOLOGY §5. Minimum data: ≥ 30 post-deploy verification-intent episodes; below that the
readout is declared underpowered, not null.

**Adoption guard, stated up front.** A verb nobody calls collapses nothing: if the readout window
shows near-zero organic `--verify` calls, that is a ROUTING failure in the adoption-loop's domain
(nudge/skills — the `--run-trace` precedent, which also shipped verb-first and waited on routing),
and it must not be reported as a verdict on the bundle's design. The chain-length band is only
readable on episodes where the verb actually fired.

**Honesty invariants carried by the verb itself, gate-pinned rather than registered:** `refuted`
only ever rides complete evidence (a clean uncapped literal scan, or printed witness sites against an
absence-claim); a graph or reference zero is `not-established` with `limit=` naming the floor;
`complete=` and `counts_floor=` never co-occur on one root (`test/verifycheck.sh`, mutation arms).
### `--help-task` adoption — forward readout, PRE-REGISTERED 2026-08-12 (before any post-deploy row)

**What shipped.** `--help-task="TASK"` — deterministic enhanced help: ONE recommended executable
ripwire command for this repository and task with the evidence behind the pick (intent, integer
score/margin, repository facts), or an honest abstention when evidence/applicability is
insufficient. Advice only: it never calls a model, never executes the recommendation, never touches
the network. Gated by `test/taskroutecheck.sh`. The residual it targets is the "what do I run?"
hop — a help surface either terminates that question or adds a hop, and this registration is how
we find out which.

**Primary metric (transcript-observable, no meter accrual needed).** ADOPTION-WITHIN-2: among
post-deploy episodes containing a `--help-task` call, the fraction in which the RECOMMENDED command
is among the next two ripwire calls of the same episode, measured by the next mining pass over
post-deploy sessions with the same episode-window method the month-scale mine used — unified with
the existing mining-pass window instrument, never a bespoke grader. Episodes where `--help-task`
abstained are counted separately (an abstention adopted-as-stop is a different outcome from a
recommendation ignored) and do not enter the adoption denominator.

**Operational feedback instrument, shipped 2026-08-28.** The Codex `UserPromptSubmit` hook now
keeps a short-lived pending recommendation keyed by a checksum of the session id; its existing
`PreToolUse` adapter records only the next two Ripwire verb names and closes the row as `adopted` or
`missed`. `~/.ripwire/routing.jsonl` stores prompt/session checksums, prompt byte count, intent,
recommended verb, observed verb, ordinal and outcome — never prompt text or a full shell command.
`python3 bench/routing_report.py [LOG] [--json]` reports the same completed-route denominator overall
and by intent, and labels fewer than 30 completed routes `underpowered`. This is a local, faster
readout of the pre-registered metric, not a replacement definition or a task-success claim. Setting
`RIPWIRE_ROUTE_METER=0` disables both the durable rows and the short-lived pending state without
disabling advisory routing.

**Band, pre-registered.** Band SHAPE is public; LEVELS resolve in the operator-local registration
ledger, recorded there before the post-deploy half is read (the telemetry rule: this document
carries the mechanism and the band shape only). Minimum data: ≥ 30 post-deploy episodes containing
a `--help-task` call; below that the readout is declared underpowered, not null.

**Adoption guard, stated up front.** A help surface nobody calls terminates nothing: if the readout
window shows near-zero organic `--help-task` calls, that is a ROUTING failure in the adoption-loop's
domain (nudge/skills — the `--run-trace` precedent, which also shipped verb-first and waited on
routing), and it must not be reported as a verdict on the surface's design. The adoption-within-2
band is only readable on episodes where the verb actually fired.

### `--help-task` command-routing floors — the honest fixture result (2026-08-12)

**The instrument, and why it was rebuilt before it was believed.** The first fixture corpus scored
held-out accuracy/precision/coverage = 1.000 — and a perfect score on a routing eval is a red flag,
not a result: those fixtures templated the intent cards' own vocabulary, so the floors were met by
self-quotation. The corpus was rebuilt under provenance rules before any number was accepted:
every original templated row quarantined to the dev split (`provenance=templated`); 47 new rows
hand-written from real agent phrasing (`provenance=handwritten-digD`, seeded by paraphrase classes
from mined session history, never copied); a word-trigram contamination screen
(`test/taskroutefix/contamination_screen.py`, power-checked against known-contaminated probes)
proving zero overlap with the intent cards and the recommended verbs' `--help` text; and the
dev/test split sealed by content hash BEFORE scoring (rule and corpus sha256 recorded in
`test/taskroutefix/PROVENANCE.md`).

**Pre-registered floors and the sealed result** (28 hand-written held-out rows, one scoring run):
high-confidence **precision 1.000** (floor ≥ 0.90) · **harmful-route rate 0.000** (ceiling ≤ 0.02) ·
**negative-abstention specificity 1.000** (floor ≥ 0.90) — all three floors HOLD. **Coverage 0.667**,
reported separately per the round's own rule (no coverage floor in round 1): all 7 misses are
deliberate abstentions, never a wrong recommendation — 2 are prose-embedded closed claims the
whole-string claim detector cannot see (registered v1.1 work). The self-quotation artifact is
quantified by the split gap: the dev split (which holds the quarantined templated rows) scores
coverage 0.893 vs the honest 0.667.

**A contract violation the byte-compat arm caught before landing.** The router recommended
`--verify='reaches(A, B)'` for symbol-to-symbol reaches phrasing — a command the shipped `--verify`
parser refuses (its unquoted second argument must be a built-in layer word). Fixed by delegating
the router's claim recognition to the real parser (`rw::verify::parseClaim`) plus the verb's own
layer validation — the router can no longer recommend a claim the verb would refuse, and
`test/taskroutecheck.sh` holds both directions: emitted claims execute through the real parser
byte-identically, and the parser-refused form never routes to `--verify`.

### `--help-task` data-flow / at-line / who-writes coverage (2026-09-02)

**The gap.** `--help-task` abstained on three question shapes with no card at all: "where does this
wrong value come from", a task naming a `FILE:LINE` location, and "who writes SYM". Three new
intents close it (`src/taskroute.h`, extracted into `flowTaskChoice` beside the existing
`instrumentedTaskChoice`): `data-flow` → `--slice=SYM:VAR --slice-flow=back` when a resolved symbol
AND a variable-slot cue (`"value of X"`, `"into X"`, `"flow of X"`) both fire, else bare
`--slice=SYM` (lists sliceable locals — a real command, never a placeholder) when only the symbol
resolves; `at-line` → `--slice=@FILE:LINE` from a literal or prose-stated file:line, structural
rather than phrase-scored; `who-writes` → `--uses=SYM` on "who writes/sets/modifies/assigns SYM".
The `Owner.field` dotted phrasing is deliberately NOT specially parsed — that coupling belongs to a
different round — so today the router resolves the OWNER symbol only (`Symbol` out of
`Symbol.name`) and says so in the emitted reason string.

**Fixture, honestly extended.** 25 new `test/taskroutefix/prompts.tsv` rows (provenance
`handwritten-digE`; 14 test / 11 dev — every row's actual hash-rule split AND actual routing
outcome verified against a live binary before insertion, not asserted). Because these three
intents' triggering vocabulary is itself a small closed phrase list (the same shape
`exact-grep`/`edit-contract`'s paraphrase rows are in — see `test/taskroutefix/PROVENANCE.md`'s
`instrumented-cli` note, extended this round to say so explicitly), a genuinely original sentence
that still routes necessarily reuses one of the trigger phrases somewhere, so these rows are
exempt from the trigram contamination screen the same structural way. `contamination_screen.py`
(now also scanning `--slice --slice-flow --at --uses` `--help` text, in addition to the original 8
recommended verbs) flags zero new contamination from this round; it does flag one pre-existing,
unrelated collision (confirmed present on `origin/main` before this round), filed separately.

**Held-out floors, before/after** (`bench/taskroute_eval.py`, same corpus, only the binary
changed):

| Split | Metric | Before | After | Floor |
| --- | --- | --- | --- | --- |
| test (n=66) | accuracy | 0.727 | 0.894 | — |
| test (n=66) | precision | 1.000 | 1.000 | ≥0.90 |
| test (n=66) | harmful | 0.000 | 0.000 | ≤0.02 |
| test (n=66) | negative-specificity | 1.000 | 1.000 | ≥0.90 |
| test (n=66) | coverage | 0.647 | 0.863 | — (no coverage floor, by the round-1 rule) |
| dev (n=92) | accuracy | 0.837 | 0.935 | — |
| dev (n=92) | precision | 1.000 | 1.000 | ≥0.90 |
| dev (n=92) | harmful | 0.000 | 0.000 | ≤0.02 |
| dev (n=92) | coverage | 0.800 | 0.920 | — |

Before/after confusion on the three new intents (test split): `data-flow` 4 abstains → 0,
`at-line` 4 abstains → 0, `who-writes` 3 abstains → 0 — every miss this round targeted is closed;
every OTHER confusion line (verify-claim prose-embedded claims, understand-symbol, etc. — the
known v1.1 backlog from the 2026-08-12 round above) is unchanged, which is the row-count-diff way
of showing this round touched nothing else.

**Regression discipline.** The 133 rows that existed before this round are BYTE-IDENTICAL on both
`status` and `resolved_symbols` (the `<facts resolved_symbols=N>` count) before vs after — checked
by running every row through `--help-task` on both binaries and diffing the two (status, intent,
resolved_symbols) snapshots; the diff is empty over those 133 rows (only the 25 new appended rows
differ, as expected). `quality-delta --scope='src/*'` is clean (`gating="0"`) after the code
landed — an initial pass flagged a `duplication` finding (a new filler-word helper structurally
matched the pre-existing `weakSymbolCandidate`'s stop-word check) and a `verbosity` finding
(`directTaskChoice` more than doubled in line count); both were fixed by extracting the three new
checks into their own `flowTaskChoice` function (mirroring the existing `instrumentedTaskChoice`
extraction) and by inlining the small filler-word loop directly rather than introducing a shared
helper that collided token-for-token with `weakSymbolCandidate`'s existing shape.

### Skill-routing surface forms — S1b round, PRE-REGISTERED 2026-08-19 (before any skill edit)

**Why this round exists, and why it is close to one already rejected.** The S1 round above ran a
"more of the skill's own rare words" mechanism (tf ≥ 3 own body, df ≤ 4/17, ≤ 12 added words per
skill, all 17 skills) against the grown corpus and **rejected** it at net 0 flipped rows. That
verdict stands and is not being relitigated. This round is registered as a deliberate NEAR
REPLICATION with three named differences, so that a null result adds a fourth independent
rejection to the same hypothesis family rather than a first, and a positive result is attributable
to the differences rather than to a re-roll:

1. **Rarity threshold tightened** — df ≤ 1 across the other 16 descriptions (S1: ≤ 4/17), i.e. a
   term at most one sibling description already spends.
2. **Scoped to the measured failure, not to every skill** — only skills that appear in the
   baseline desc-vs-body disagreement list (rows `bm25-full` routes correctly and `bm25-desc` does
   not), minus the two descriptions longer than 1.4× the mean description length
   (`ripwire-quality-bar` 302 tokens, `ripwire-fresh-eyes` 232; mean 158). BM25's `b = 0.75`
   length penalty is why the twice-measured SWAP trap lives on the long descriptions; ADD edits
   there pay the same tax, so they are excluded by rule and not by taste.
3. **A term class S1's filter could not surface: surface forms the tokenizer cannot produce from
   the description's current spelling.** `subtokens()` (`src/lexical.h`) flushes at a camel
   boundary tested against the *already-lowercased* accumulator, so an ALL-CAPS acronym is shredded
   into one-character fragments, every one of which is dropped by the `size() >= 2` rule: `MCP`,
   `API`, `CI`, `PR` tokenize to **nothing at all**. `ripwire-mcp`'s description is entirely about
   MCP and contributes **zero** `mcp` tokens to the bm25-desc index, while the only description
   holding that token is `ripwire-security-scan` (from a literal `.mcp.json`) and the
   `ripwire-mcp` *body* holds it at tf 17. The same defect has a non-acronym form: with no
   stemming, `layers`/`layering` do not produce `layer`, which no description holds at all. These
   are representation gaps, not vocabulary-taste gaps, and S1's tf×idf ranking could not
   distinguish them from ordinary rare words.

**Instrument (unchanged):** `ripwire skills --eval-skills=test/skillevalfix/prompts.tsv`
(`src/skilleval.h`), gated by `test/skillevalcheck.sh` and `test/skillroutingjudgedcheck.sh`.
Corpus frozen at 266 rows / 152 judged; **no fixture row is added, edited, or relabelled this
round**.

**Baseline (measured at `ab59ca8`, this corpus, before any edit):**

| arm | hit@1 | hit@2 | mrr | sep-auc |
| --- | --- | --- | --- | --- |
| bm25-desc (all 266) | 66.7% | 81.3% | 0.776 | 0.943 |
| bm25-full (all 266) | 64.6% | 75.3% | 0.746 | 0.878 |
| bm25-desc (split=test, N=183) | 66.9% | 83.1% | 0.786 | 0.957 |
| bm25-full (split=test, N=183) | 67.7% | 77.7% | 0.769 | 0.893 |
| bm25-desc (split=dev, N=83) | 66.2% | 77.9% | 0.757 | 0.897 |

Judged-only hit@1 (n = 152): bm25-desc **90**, bm25-full **93**, for-routed 91. The desc-vs-body
gap is therefore **+3 rows** to the body — the same gap S1 measured and failed to close.

**Derivation rule (fixed before measurement).** Per skill, tf over its own SKILL.md body and df
over the 17 candidate *descriptions* (`ripwire-router` is excluded from the candidate corpus by
`skilleval.h`, so it is excluded here). A term is a candidate iff tf ≥ 3 in its own body, absent
from its own description, and df ≤ 1 across the others. Selection among candidates keeps only
domain words — the moment, the artifact in hand, or a named metric the body actually reports —
and drops CLI mechanics (flag spellings, output column names, file extensions), function words and
numerals. Every kept term is written into the description as prose in that description's existing
voice, **ADD only**: no existing sentence is swapped, shortened or deleted, and frontmatter
stop-rule markers are untouched. **Derivation reads the 18 SKILL.md files and nothing else** — the
eval prompts, their labels and the per-row miss lists are never read as text; the only thing taken
from the instrument is the *set of skill names* in the disagreement list. Deriving terms from the
scoring set would be fitting, not measuring.

**Metric and band (primary).** bm25-desc judged-only hit@1, n = 152, exactly one measurement.
**ACCEPT iff the net change lands in [+4, +12] rows** (90 → 94…102; one row = 0.66pp). The lower
edge is +4 because that is the smallest net change that also carries independent meaning: it puts
the description arm past bm25-full's 93 and closes the +3 desc-vs-body gap this round exists to
close. Anything in [0, +4) is inside the range that a dozen arbitrary term additions can produce
by displacement luck and is a **REJECT**. The upper edge follows the S1/LB-3 precedent: a result
better than the mechanism can explain is a leakage suspect, so **> +12 is also a REJECT** pending
audit.

**Simultaneous floors, all must hold, any breach is a REJECT regardless of the primary:**
split=test bm25-desc hit@1 ≥ 66.1% (baseline 66.9%; at most one positive row of give-back at
n = 130) and sep-auc ≥ 0.940 (baseline 0.957); split=dev hit@1 ≥ 46.0% and sep-auc ≥ 0.75
(committed floors); judged hit@1 ≥ 50% and for-routed judged ≥ 45% (committed floors);
`test/skillevalcheck.sh`, `test/skillroutingjudgedcheck.sh`, `test/agentloopcodexcheck.sh` and
`test/skilltruthcheck.sh` all green. sep-auc explicitly may not fall: added trigger vocabulary that
makes negatives fire is the known failure mode of ADD edits.

**Reported but not decisive** (registered so it cannot be promoted after the fact): net flipped
rows on the n = 85 held-out judged subset (split=test ∩ provenance=judged), the exact statistic S1
decided on, recorded for comparability with that round's net 0.

**Decision rule.** In band with every floor green → keep and commit with before/after numbers.
Otherwise → revert the description edits in full, keep this registration, and record the negative
result here. One attempt; a retry is a new round with a fresh registration.

**Prior expectation, stated in advance.** Given S1's net 0 and the two LB-3 rejections, the
expected outcome of this round is REJECT. It is worth running anyway only because of difference
(3): the acronym-shredding defect is a mechanism S1 could not have tested, and its cost is
measurable rather than a matter of taste. If this round also rejects, the remaining hypothesis for
the desc-vs-body gap is ranker-side (a length-aware desc+body mix), which needs its own
registration and is out of scope for any description-content round.

**RESULT (2026-08-19, the single measurement): REJECT.** Nine descriptions gained 353 subtokens of
derived prose (`ripwire-reuse-first` was in the target list but got **no** edit — every one of its
12 candidates was CLI mechanics or a function word, and the selection rule dropped them all).
bm25-desc judged hit@1 moved **90 → 92 / 152 = +2 rows**, below the registered [+4, +12] band.
Reverted per the decision rule; registration, derivation script and candidate table stay.

Every other number rose, and none of them was the registered metric:

| statistic | baseline | after | registered role |
| --- | --- | --- | --- |
| bm25-desc judged hit@1 (n=152) | 90 | **92 (+2)** | **PRIMARY — band [+4, +12]** |
| bm25-desc hit@1 (all 266) | 66.7% | 67.7% | not registered |
| bm25-desc hit@1 (split=test) | 66.9% | 69.2% | floor ≥ 66.1% — held |
| bm25-desc sep-auc (split=test) | 0.957 | 0.954 | floor ≥ 0.940 — held |
| bm25-desc hit@1 / sep-auc (split=dev) | 66.2% / 0.897 | 64.7% / 0.882 | floors 46.0 / 0.75 — held |
| bm25-full judged hit@1 (n=152) | 93 | 94 | context |
| net flipped rows, judged split=test (n=85) | — | +3 (5 correct, 2 wrong) | reported, barred from deciding |

**This is the honest reading, and it is not "so close".** Every floor held, the headline arm rose
on both the whole corpus and the frozen test split, and the round's own mechanism-specific
prediction landed — the `ripwire-mcp` row that the acronym defect explains flipped to correct, as
did a `ripwire-layers` row. But the primary is +2 in a band whose lower edge was set at +4 *before
the measurement*, and set there for a stated reason that the result does not retire: **+4 was the
smallest change that would also put the description arm past `bm25-full`.** It did not. `bm25-full`
moved 93 → 94 in the same run (the full arm indexes description *and* body, so it banks every
addition too), leaving the desc-vs-body gap at **+2 rows to the body** — narrowed by one row, not
closed. A +2 that leaves the gap open is exactly the displacement-luck outcome the band was drawn
to exclude, and accepting it because the other columns look good is the post-hoc metric swap the
registration barred in advance.

**What the round bought, at the price of 353 tokens.** Seven positive rows became correct and five
became wrong. The five losses concentrate in a way that names the cost: `ripwire-handoff`, whose
description grew the most in relative terms (96 → 145 tokens, +51%), took top-1 on two rows that
are not its own — this is the ADD edit's known failure mode arriving on schedule. Prose additions
cannot be all-signal: of the 353 tokens, only about half were the derived low-df terms; the rest
was the connective glue that makes them a sentence, and BM25's `b = 0.75` charges the whole
sentence to every query the skill will ever be scored against. S1 capped additions at 12 words per
skill and measured net 0; this round removed the cap, added ~39 tokens per skill, and measured +2.
Neither is the gap. That the two failures bracket the cap from both sides is the useful part.

**Where this leaves the desc-vs-body gap.** Four measurements now agree that description *content*
is not the lever: the two LB-3 rounds on `--for`, S1's rare-word round at net 0, and this one at
+2-with-the-gap-still-open. The one thing S1 could not have tested did pay off in isolation — the
tokenizer's acronym shredding is real, `subtokens()` turns `MCP`/`API`/`CI`/`PR` into nothing, and
`ripwire-mcp`'s description still indexes zero `mcp` tokens today — but recovering one row per
defect does not carry a description-content round on its own. Two follow-ups are worth their own
registrations, and both are ranker-side rather than prose-side: (a) a length-aware desc+body mix,
already S1's surviving hypothesis; (b) making `subtokens()` keep an all-caps run as one token, so
`MCP` indexes as `mcp` on *both* the document and the query side. (b) is a change to a shared
tokenizer that every lexical surface in the tool depends on, so it is a ranking round with a full
recall-lane re-measure, not a skills edit.

### Subtoken acronym shredding — PRE-REGISTERED 2026-08-19 (before the fix is measured)

**The defect.** The shared subtoken tokenizer shreds an all-caps run into single characters, which
the ≥2-byte rule then drops, so an acronym is indexed as *nothing at all*. Three mirrors carry the
same bug: `lexical.h::subtokens()` tests its camel boundary against the ALREADY-LOWERCASED
accumulator (`cur.back()` can never be uppercase, so the "previous char was uppercase" guard is
dead code), and `lexindex.h::forEachLexSubtoken()` / `forEachLexSubtokenHashed()` state it
outright — "an interior uppercase char always starts a NEW token". Reproduced against the shipped
`subtokens()` at `ab59ca8`:

| input | tokens at `ab59ca8` |
| --- | --- |
| `MCP` / `PR` / `CI` | *(none — every fragment is 1 byte and dropped)* |
| `MCP end to end` | `end`, `to`, `end` |
| `MCPServer` | `server` |
| `HTTPServer` | `server` |
| `IOError` | `error` |
| `XMLHttpRequest` | `http`, `request` |

Concrete cost: `ripwire-mcp`'s SKILL.md description is about MCP end to end yet contributes **zero**
`mcp` tokens to the routing index (its body carries tf 17); the only description that indexes `mcp`
at all does so through the literal `.mcp.json`. 17 of the 152 judged routing prompts carry an
all-caps run of ≥2 (`MCP`×3, `CI`×3, `UI`×2, `PR`×2, `YAML`, `LICM`, `API`, `CSV`, `CLI`, `JSON`,
`SKILL`), and all 18 skill descriptions carry at least one.

**Consumers of the tokenizer (the full list, so the blast radius is on the record).** Query-side
`subtokens()`: `lexical.h` `lexicalScoresTiered` query tokenization (`--for`, `--query`, `--recall`,
`--pack-task`, `--exemplar` kind donation, every eval), `lexical.h` LB-2 route-carrier counts,
`eval.h` `bm25Seeded` doc construction (both the dS and dB arms), `exemplar.h` name and task
tokens, `skilleval.h` doc bags + prompt tokens (the `overlap`, `bm25-desc` and `bm25-full` arms).
Corpus-side `forEachLexSubtoken()`: `lexical.h` `scanField` over the name / callee / path / doc /
body fields. Index-side `forEachLexSubtokenHashed()`: `lexindex.h::buildDefLexStats`, i.e. the
persisted per-definition lexical statistics and the per-file 512-bit subtoken pre-filter signature.
`naminglens.h` is *not* a consumer — it has its own case-preserving `splitIdentifier` — but it does
share `lexSubtokenHash`, always on pre-lowercased input.

**Cache persistence — yes, so the version bumps.** `RawDefLex` (`dlWeighted`, `tokenHashes`,
`tokenTfs`) is written into the rich per-file cache record (`ingest.cpp` v10 rich `withLex` extra),
and the per-file H3 signature is derived from `tokenHashes`. The fix therefore changes a *persisted*
representation: `kParserVer` 65→66 and `quality.h::kIngestParserVerMirror` 65→66 in the same commit.

**The change, registered verbatim before measurement.** In all three mirrors, a token is a maximal
`[A-Za-z0-9]` run between separators, split additionally at:

1. a **lower/digit → Upper** transition — `fooBar` → `foo`,`bar` (unchanged behavior); and
2. the **last uppercase of an uppercase run of length ≥2 that is immediately followed by a
   lowercase letter** (the ACRONYMWord rule) — `HTTPServer` → `http`,`server`; `MCPServer` →
   `mcp`,`server`; `IOError` → `io`,`error`; `XMLHttpRequest` → `xml`,`http`,`request`.

An uppercase run **not** followed by a lowercase stays one token: `MCP` → `mcp`, `PR` → `pr`,
`CI` → `ci`, `MCP2Server` → `mcp2`,`server`. Digits stay token-interior and never open a boundary
(unchanged): `utf8Encode` → `utf8`,`encode`, `sha256sum` → `sha256sum`. Tokens under 2 bytes are
still dropped (unchanged): `aB` → ∅. `subtokens()` still lowercases on emit; `lexSubtokenHash` and
the fused rolling hash now lowercase **every** byte rather than only the first, because a token may
now carry interior uppercase — without that the postings path would stop matching the scan path.
Registering `HTTPServer` → `http`+`server` rather than `httpserver` is not a free choice: it is
exactly the rule `naminglens.h::splitIdentifier` already implements ("the LAST upper of an ≥2-upper
run starts the next word: `HTTPServer` → [HTTP, Server]"), so the repo's two splitters converge
instead of acquiring a second disagreement.

**Explicitly out of scope this round.** `graph.h::wordCount` (the PageRank specificity prior) is a
fourth, independent boundary implementation; it already keeps an all-caps run as ONE word and is
left untouched. The length-aware desc+body mix hypothesis from the S1 round is likewise out of
scope. One registered change only.

**Baselines at `ab59ca8` (measured before any edit).** Skill routing
(`ripwire skills --eval-skills=test/skillevalfix/prompts.tsv`): judged-only hit@1 `bm25-desc`
**90/152**, `bm25-full` **93/152**, `for-routed` **91/152**, `overlap` 57/152, `name` 15/152;
split=test `bm25-desc` hit@1 **66.9%**, hit@2 83.1%, mrr 0.786, sep-auc **0.957**; split=dev
`bm25-desc` 66.2% / 0.897. Recall lane (`test/recallevalcheck.sh`, frozen corpus
`commit=7a7f79892034 files=113 sha=cfeb23c71cd2`): recall lane lenient recall@5 **88.1%**, lenient
MRR **0.624**, LIVE pollution@5 **4.8%**; ranking lane lenient recall@5 **75.0%**, lenient MRR
**0.694**, pollution@5 **0.0%**, adversarial-class pollution@5 **0.0%**.

**Metric and band (primary surface — skill routing).** Judged-only hit@1, `bm25-desc` arm, n=152,
exactly one measurement. One row = 0.66pp, so a band narrower than 2 rows would be reading noise.
**ACCEPT iff net flipped rows (newly-correct − newly-wrong) land in [−2, +12]** (−1.3pp … +7.9pp;
14 rows wide). The lower edge is deliberately non-inferiority-shaped rather than zero: this is a
*correctness* repair — an index that cannot represent the word "MCP" is wrong whatever the proxy
says — and up to 2 rows of proxy cost is what that correctness argument buys. Past −2 the ranking
cost is real and the fix does not land. The upper edge is the LB-3/S1 leakage guard: only 17 judged
rows carry an acronym at all, so a net gain past +12 is a result the registered mechanism cannot
account for — audit it, do not bank it.

**Simultaneous floors (all must hold; a win on one surface bought past a floor on another is a
REJECT).** `test/skillevalcheck.sh`: split=test `bm25-desc` hit@1 ≥ 60.0% and sep-auc ≥ 0.89,
split=dev ≥ 46.0% / ≥ 0.75, the judged split ≥ 80 rows, and both metric-can-fail arms (wrong labels
halve hit@1; swapped labels invert sep-auc to within 0.02 of 1−auc and below 0.5).
`test/skillroutingjudgedcheck.sh`: `bm25-desc` and `for-routed` judged hit@1 both ≥ 50%, and the
cold-start row routes in both arms. **Recall lane:** `test/recallevalcheck.sh` must stay green on
every committed floor — recall lane lenient recall@5 ≥ 71%, lenient MRR ≥ 0.57, LIVE pollution@5
≤ 16%, ranking lane lenient recall@5 ≥ 70%, lenient MRR ≥ 0.55, pollution@5 ≤ 5%, adversarial-class
pollution@5 ≤ 8%. The ranking-lane recall@5 floor has the least headroom (75.0% against 70%) and is
the one to watch. **Expected direction on the recall lane: neutral.** The frozen recall corpus is
markdown-prose-led, where acronyms are common on both sides, so the fix should add signal
symmetrically; no directional claim is registered, only the floors. Whole-suite green
(`python3 test/pargates.py . ./build/ripwire -j 6` rc=0), ASan clean, determinism byte-identical,
and `--quality-delta` with zero unacked regressions are standing requirements, not part of the band.

**Decision rule.** In band with every floor green → keep the code. Out of band, or any floor
breached → revert the tokenizer change, keep this registration and the negative result, and keep
the new gate only if it still describes shipped behavior (it does not, so it reverts with the code).
One attempt; a retry is a new round with a fresh registration.

**RESULT (2026-08-19, the single measurement): IN BAND on both registered surfaces — but the suite
found one regression the bands do not cover, and it is not papered over. See the verdict below.**

*Primary surface — skill routing.* Judged-only hit@1, `bm25-desc`, n=152: **90 → 98**, net flipped
**+8** rows (+5.3pp), inside the registered [−2, +12]. Every simultaneous floor held with room:
split=test hit@1 66.9% → **73.1%** (floor 60.0), sep-auc 0.957 → **0.957** (floor 0.89); split=dev
66.2% → **69.1%** (floor 46.0), sep-auc 0.897 → **0.887** (floor 0.75); judged `bm25-desc` 64.5%
and `for-routed` 59.2% (floors 50%/50%); both metric-can-fail arms and the cold-start row still
pass. Secondary arms, reported not banded: `overlap` 57 → **62**, `name` 15 → **17**, `bm25-full`
93 → **91**, `for-routed` 91 → **90**. The `bm25-full` and `for-routed` dips are inside the one-row
noise scale and neither approaches a floor; the desc-vs-body gap that three prior rounds failed to
close by adding vocabulary (+3 rows, stable across a 2.6× corpus growth) **inverts** here — with
acronyms indexed, the description now beats the body it was written to represent by 7 rows. That is
the first mechanism to move that gap, and it moved it by repairing an index defect rather than by
writing more words.

*Recall lane.* Every committed floor green. Frozen instrument (the one designed to isolate ranker
movement): lenient recall@5 **88.1% → 88.1%**, lenient MRR **0.624 → 0.643**, LIVE pollution@5
**4.8% → 2.4%**. Ranking lane at MATCHED corpus (post-fix binary re-run against the `ab59ca8` tree,
because that lane scores the LIVE root and this round edited it): lenient recall@5 **75.0% →
75.0%** unchanged, lenient MRR 0.694 → **0.673**, pollution@5 and adversarial-class pollution@5
both **0.0%**. Read on the live root the lane reports 71.9% — one label of 32 — which is corpus
composition, not ranker movement; the matched-corpus re-run is the number that answers the
registered question.

*Whole suite.* 424 gates: 420 pass, 2 skip, 2 fail. `editcheckcheck.sh` is a timing gate and failed
once under `-j 6` at load average 28.7 (another lane building); it passes twice solo — the known
flake, not a finding. `qschemetripcheck.sh` and `readmeexamplecheck.sh` failed as pure golden drift
(the `kParserVer` 65→66 hash re-pin the gate itself prescribes, and two README `--callers` line
numbers shifted by the `graph.h` comment) and are re-pinned in their own commit. ASan clean on the
default map and on the new fixture, determinism byte-identical over three runs, `xmllint` clean,
`--quality-delta` exit 0.

**The regression the bands did not cover: `test/exemplarconfcheck.sh`.** Its confidence arm asserts
that a strong task must NOT raise `--exemplar`'s `low_confidence` advisory. Post-fix, the query "read
command line options" raises it. This was reproduced as a clean 2×2 — same corpora, only the binary
differs — so it is the tokenizer change, not corpus drift and not that gate's known
corpus-fragility:

| binary ↓ / corpus → | `ab59ca8` tree | this working tree |
| --- | --- | --- |
| pre-fix (`ab59ca8`) | no flag | no flag |
| post-fix (this branch) | **`low_confidence="1"`** | **`low_confidence="1"`** |

Mechanism: `low_confidence` fires when at most `kExemplarConfMinShare`=0.4 of the top-10 lexical
hits carry a task subtoken in their NAME. Acronyms now count toward every document's BM25 length,
so scores shift corpus-wide and one symbol enters that ten-slot window — a strict `>0.4` on a
10-sample proportion flips on a single displacement. The *answer* is unchanged: the exemplar
returned the identical symbol (`min`, `src/infra/fastmath.h:51`) with the identical donated kind
(`fn`) before and after; only the advisory attribute differs. It is nonetheless a false positive on
an honesty signal, which is the exact failure direction that arm exists to prevent.

**Settled 2026-08-19, after the verdict below, by instrumented dump (both binaries, one corpus,
`exemplar.h` byte-identical between them).** The advisory is not a margin test — it is
`bestScore > 0 && shareOfWindow > 0.4`, a ten-sample population proportion. The winner and its score
were essentially unchanged (`parse_codex_jsonl_metrics`, 16.0507 → 16.0022, −0.30%); every other
score moved by the −0.02…−0.07 the honest document lengths cost. Exactly two symbols moved for a
reason: `classify_native_read` **rose** (+0.126, the window's only rise) because its body's
`NATIVE_READ_TOOLS` / `SHELL_READ_RE` — SCREAMING_SNAKE_CASE, previously indexed as *nothing at all*
— now contribute the query term `read`; and `AmbientOptions` **fell** (11.1936 → 10.6999, −4.41%,
12.8× the ambient drift, #8 → #12), because it is a TypeScript test fixture
(`export interface AmbientOptions { width?: number }`) whose doc-comment shouts KNOWN LIMIT /
CONTAINER / CONTENTS and had been enjoying a phantom short-document discount. Its departure is the
whole flip: corroboration 5/10 → 4/10, and 0.4 does not exceed 0.4. So the query sat one *spurious*
corroborator above a strict cut. Across the same instrumented sweep the weak/strong separation
**widened** (weak 0.30 → **0.20**; `compute pagerank` stable at 0.80), and no other query changed
trustworthiness — the confidence signal improved. Per the standing "new tool, no compat debt" rule
the arm was recalibrated in its own commit onto `"compute the churn of a file"`, measured 0.60 on
**both** binaries (two samples of margin instead of one); the rejected candidates and their shares
are recorded in the gate so the choice is auditable. `exemplarconfcheck` is green and the suite is
clean; the note below stands as the record of what was found before it was settled.

**Verdict: ACCEPT on the registered bands; the one red gate is settled above.**
The registered decision rule is satisfied — in band on the primary surface, every named floor
green — and the change repairs an index that could not represent the word "MCP" at all. What this
round will NOT do is reword the failing arm's query to make its own change green. That arm's header
records two previous rewordings for this class of cause, but both were CORPUS-side (module
constants at `kParserVer` 62, installer vocabulary at v0.3.6); this one is RANKER-side, and
recalibrating a behavioral gate to accommodate the change under measurement is the same move as
widening a band after seeing the number. The gate is left red, the evidence is above, and the
choice is the owner's: recalibrate the arm in a separate disclosed commit, or reject.

**Named follow-up (not run this round).** The registered rule bundles two seams — an all-caps run
kept whole (`MCP` → `mcp`) and the ACRONYMWord split (`HTTPServer` → `http`+`server`). Which of the
two moves `exemplarconfcheck` is unmeasured; splitting them is a variant this round was not
registered for, and shipping half of a registered rule would itself be an unregistered change. A
follow-up round can register the halves separately and attribute the shift.

### Length-aware desc+body mix — lead-section round, PRE-REGISTERED 2026-08-19 (before the change is measured)

This is the ranker-side follow-up the S1b registration named: *"the remaining hypothesis for the
desc-vs-body gap is ranker-side (a length-aware desc+body mix), which needs its own registration"*.
Description CONTENT is closed — four agreeing measurements — so nothing under `skills/` and nothing
in `test/skillevalfix/prompts.tsv` is touched this round. The lever is router-side code only.

**The diagnosis that funds it.** At the subtoken-acronym merge the two BODY-scoring arms fell in
lockstep (`for-routed` 91 → 90, `bm25-full` 93 → 91) while the description-only arm rose cleanly
(`bm25-desc` 90 → 98). The retokenization makes body BM25 reward flag-literal / acronym density on
generic-word overlap, and every regressed row lost by a margin under 4% inside the `subtoken+body`
branch (`chooseForRanker` → `LexMode::SubtokenBody` → `lexicalScores`). Per-row evidence and the
2×2 binaries are in the D1 report; the numbers below were re-derived here on the clean
`adb0831` build before a line of this round's code existed.

**Baselines at `adb0831` (measured before any edit, `--no-cache`, frozen `skills/` + `prompts.tsv`).**
Judged-only hit@1: `overlap` 62/152, `name` 17/152, `bm25-desc` **98/152**, `bm25-full` **91/152**,
`for-routed` **90/152**. Whole-corpus (n=198 positive / 68 negative): `for-routed` hit@1 64.6%,
hit@2 76.8%, mrr 0.755, sep-auc **0.922**, oracle fire/abstain **65.0%**. split=test (130 pos / 53
neg): `for-routed` hit@1 **66.2%**, sep-auc **0.942**; split=dev (68 pos / 15 neg): `for-routed`
hit@1 61.8%, sep-auc **0.840**. `for-routed` misses 70 of 198 positive rows.

**Feasibility, measured on the baseline before the band was written.** D1 recommended a
margin-aware tie-break that blends toward the description-only score, and flagged one check as not
done: whether the desc arm actually gets the regressed rows right. It does not. Of the three rows
the subtoken merge cost `for-routed`, `bm25-desc` *also misses* row 135, and misses it to the
identical wrong skill:

| row | provenance / split | want | `for-routed` | `bm25-desc` | reachable by a desc-ward mix? |
| --- | --- | --- | --- | --- | --- |
| 89 | desc / test | quality-bar | miss → change-check | **hit** | yes |
| 96 | judged / test | before-you-build | miss → efficient | **hit** | yes |
| 135 | judged / test | security-scan | miss → **efficient** | miss → **efficient** | **no** |
| 73 | desc / test | change-check | hit | hit | keeps |
| 199 | judged / dev | fresh-eyes | hit | hit | keeps |

Row 135 is *provably* out of reach of this whole lever family: `ripwire-efficient` scores at or
above `ripwire-security-scan` in **both** components (subtoken+body 4.89274 vs 4.83958; and the desc
arm ranks efficient top-1), so every non-negative-weight blend of the two keeps efficient ≥
security-scan. The same holds for a margin-aware tie-break, which is that blend with margin-dependent
weights. So the merge-dip set contributes at most **+1** judged row (96), and any band above that
must be carried by the general desc-ward shift, whose asymptote is the desc arm's own **98/152**.

**The change, registered verbatim.** One lever, one constant, in the `subtoken+body` scoring path
only (`lexical.h::lexicalScoresTiered`; the name-exact ranker and every bag-of-words eval arm are
untouched). Markdown `Section` symbols are currently down-weighted by a flat ×0.30 so prose cannot
swamp code. A document's **lead section** — the FIRST symbol of its file when that symbol is a
Section, i.e. the frontmatter / abstract that describes what the document is — is instead
down-weighted by `kLexLeadSectionMul`. The constant is DERIVED, not swept:

```
kLexLeadSectionMul = kLexSectionMul * ( kLexWeightDoc / kLexWeightBody ) = 0.30 * ( 2 / 1 ) = 0.60
```

i.e. "a document's lead section is its doc-comment", priced at exactly the doc-vs-body ratio the
ranker already commits to for code. It stays ≤ 1, so it is shrink-only and the MaxScore pruning
bound stays provably safe. No index format changes, no `kParserVer` bump, no postings-parity
surface: the multiplier is applied where the ×0.30 already is, in both scoring branches.

**Metric and band (primary surface).** `for-routed` judged-only hit@1, n = 152, **exactly one
measurement**. **ACCEPT iff the net change lands in [+4, +8] rows** (90 → 94…98; one row = 0.66pp).
The lower edge is +4 for the reason the S1b round registered it on this same corpus and denominator:
anything in [0, +4) is inside the range a ranker perturbation produces by displacement luck. The
upper edge is the mechanism's own asymptote — a desc-ward mix cannot explain beating the
description arm it is deferring to — so **> +8 is a REJECT pending audit**, per the S1/LB-3 leakage
precedent. Band width 4 rows.

**Simultaneous guards (all must hold; any breach is a REJECT regardless of the primary).**
`bm25-desc` judged hit@1 stays **exactly 98/152** and `bm25-full` stays **exactly 91/152** — both
arms are structurally independent of this lever, so any movement is a bug, not a result.
split=test `for-routed` hit@1 **≥ 67.7%** (88/130 — the pre-subtoken value the dip is measured
against; baseline 66.2%). Negative-split separation may not degrade: `for-routed` sep-auc ≥ **0.922**
whole-corpus, ≥ **0.942** split=test, ≥ **0.840** split=dev, and oracle fire/abstain ≥ **65.0%**.
Committed floors: `test/skillroutingjudgedcheck.sh` (`bm25-desc` and `for-routed` judged ≥ 50%, the
cold-start row routes in both arms); `test/skillevalcheck.sh` (split=test ≥ 60.0% / sep-auc ≥ 0.89,
split=dev ≥ 46.0% / ≥ 0.75, judged split ≥ 80 rows, both metric-can-fail arms).

**KILL conditions (not a REJECT — an abort).** Any floor break anywhere in the suite, in particular
the frozen ranking lane (`test/recallevalcheck.sh` every committed floor, `snapshot.srcpack`) and
the recall MRR gate; any edit under `skills/` or to `test/skillevalfix/prompts.tsv`; any change to a
scoring constant other than the one registered lever. **Retuning the constant after seeing the
result is a KILL** — a second value is a new registration, labelled as such, maximum two shots, both
reported. Whole-suite green (`python3 test/pargates.py . ./build/ripwire -j 6`), ASan/LSan clean,
determinism byte-identical ×3, `xmllint` clean and `--quality-delta` with zero unacked regressions
are standing requirements, not part of the band.

**Expected direction on the other lenses, registered so it cannot be claimed after the fact.**
`lexicalScoresTiered` is shared with `--recall` (the docs lens) and `--exemplar`. Boosting a
document's lead section should help doc retrieval or leave it flat; the recall lane is floor-gated
and no directional claim is banked. Code corpora are unaffected by construction — a non-markdown
file's first symbol is not a `Section`.

**Prior expectation, stated in advance.** REJECT is the more likely outcome. The targeted mechanism
accounts for at most +1 of the +4 floor; the remaining +3 has to come from the general desc-ward
shift across the other 67 `for-routed` misses, which is unmodelled. It is worth one shot because the
direction is measured (the desc arm is 8 rows ahead of the body arm on the same corpus) and because
this is the first lever aimed at that gap that is not a description edit.

**Decision rule.** In band with every guard green → keep the code, append the verdict here. Out of
band, or any guard breached → revert the code commit, keep this registration, and append the
negative result. The registration and its outcome are the deliverable either way.

**RESULT (2026-08-19, the single measurement): REJECT.** `for-routed` judged-only hit@1 moved
**90 → 92 / 152 = +2 rows** (+1.3pp), below the registered [+4, +8]. The registered split=test guard
also missed: that split stayed at **66.2%** against the required ≥ 67.7%. Reverted per the decision
rule; the registration, the feasibility table and this result stay. Two shots were available; the
second was not taken, because the failure is not a constant that wants a different value — see the
mechanism below.

*Per-arm judged-only hit@1, n = 152 (one measurement, `--no-cache`, frozen inputs).* The lever is
confined to the arm it was scoped to, exactly as registered:

| arm | baseline `adb0831` | with the lever | Δ |
| --- | --- | --- | --- |
| `overlap` | 62 | 62 | 0 |
| `name` | 17 | 17 | 0 |
| `bm25-desc` | 98 | **98** | 0 (guard: unchanged ✓) |
| `bm25-full` | 91 | **91** | 0 (guard: unchanged ✓) |
| `for-routed` | **90** | **92** | **+2** (band [+4, +8] ✗) |

*`for-routed` on every other registered surface.* Whole corpus: hit@1 64.6% → 65.2%, hit@2 76.8% →
75.3%, mrr 0.755 → 0.756, sep-auc 0.922 → **0.932** ✓, oracle fire/abstain 65.0% → **66.2%** ✓.
split=test: hit@1 66.2% → **66.2%** ✗ (guard ≥ 67.7%), sep-auc 0.942 → **0.949** ✓. split=dev:
hit@1 61.8% → 63.2%, sep-auc 0.840 → **0.859** ✓. Negative-split separation improved on all three
surfaces, so the REJECT is on relevance, not on false fires.

*Per-row flips, and what they say.* Nine rows moved — five to hit (96, 105, 260, 270, 272), four to
miss (59, 248, 250, 275). Every pre-registered prediction held: row 96 recovered, row 135 stayed a
miss to `ripwire-efficient` (the family cannot reach it), rows 73 and 199 were kept. But the
unmodelled collateral the band's remaining +3 depended on came in at net +1, and it came in with a
signature: **two of the four new misses (59 and 275) are rows `ripwire-efficient`'s lead section
newly WINS.** Boosting lead sections does not just lift the right abstract — it lifts the longest,
most generic abstract fastest, because a long prose description accumulates more low-IDF query mass
than a short topical one. That is the *same* mechanism as row 135, now amplified rather than fixed.
The lever moves decisions from body-vs-body to abstract-vs-abstract and inherits the abstract arm's
own failure mode; it does not close the desc-vs-body gap, it relocates it.

*Two gates went red on the lever, attributed by re-running both after the revert.*
`test/recallanchorcheck.sh` failed: on the fixture whose Kafka section (lines 5-8) answers the
query, the recall lens returned the document's LEAD section (lines 1-15) instead — green again after
the revert, so the lever owns it. That is the registered "expected neutral on `--recall`" claim
failing outright, and it is a *worse* failure than the primary: an abstract is not an answer.
`test/packtaskcheck.sh` also failed (`--token-budget=2000` → 5771 B against a 5428 B ceiling) — but
it fails **identically after the revert**, at the same byte count, so it is PRE-EXISTING on
`integration/wave3-2026-08-19` and is not this round's. It is reported here rather than filed
silently. Everything else was clean on the lever: 430 gates with only those two red, ASan/LSan clean
on the map, the eval and a `--for`, determinism byte-identical ×3, `xmllint` clean, `--quality-delta`
exit 0 with zero regressions, and every `test/recallevalcheck.sh` floor green.

*What the round establishes, so the next one does not re-pay for it.* The desc-vs-body gap on this
corpus is not reachable from the desc-vs-body axis. Row 135 — the row the merge-dip set needs and
the row both arms fail — is a *long generic description outscoring a short topical one on low-IDF
prose mass*. That is a query-side term-weighting question, and the only lever class that addresses
it is the IDF-shaped one LB-1 already rejected in its strip+floor form. A further desc-vs-body round
is not fundable at this corpus's power: the merge-dip set caps a targeted fix at +1 judged row while
the corpus cannot discriminate below +4. The merge dip itself stands as a documented, in-floor
trade-off (`for-routed` 90/152, `bm25-full` 91/152, both far above the 50% committed floors) bought
for `bm25-desc`'s +8.

---

### Type-mention use-sites + namespace-compatible candidates — PRE-REGISTERED 2026-08-20 (before any feature code)

Two resolver-precision items from the stack-graphs recon lane, registered together because item #2 is
the filter that is supposed to keep item #1 from *adding* ambiguity, and because they would share one
`kParserVer` bump. Item #3 of that report (depth-2 receiver-chain resolution) is explicitly **not** in
this round.

**#1 — `RefRole::Type`.** `ingest.cpp::usesVisitNode` opens with `strcmp( t, "identifier" ) != 0 →
return`, so a `type_identifier` / `user_type` node — a bare TYPE mention in a signature, a declaration
or a template argument — is captured by nothing. `RefRole` today is
`Call | Read | Write | Import | Extends | Macro`; only `Extends` (base clause) and `isCompose`
(member-variable declared type) touch a type position, and both are *specific declaration forms*, not
a general mention. The `--uses` legend currently states the absence as a promise. The change adds
`RefRole::Type`, widens the accept set through a declarative kind table, and keeps the role OUT of the
call-graph CSR exactly as `Read`/`Write`/`Import`/`Extends` already are (`graph.h` admits `Call` and
`Macro` only).

**#2 — `namespaceCompatible( RefRole, SymKind )`.** One predicate beside the existing `langCompatible`,
generalizing the kind filters the graph already hard-codes in three places (the SCIP inherit overlay's
`isClassLikeK`, the implementors builder's `isClassLike`, and the compose-edge builder's
`k != SymKind::Class && k != SymKind::Struct`). **`RefRole::Call` stays UN-narrowed**: in C++ `Foo(x)`
is legitimately a constructor call or a functional cast, and narrowing `Call` to `Function|Method`
would drop real edges — `resolve.h`'s standing doctrine is that a *wrong* narrow is worse than no
narrow.

**Baseline, re-derived on this lane's own tree** (`integration/harvestexec-2026-08-20` @ `ba3a716`,
`./build/ripwire .` on ripwire's own checkout, working tree clean of untracked plan docs):

```
files=1291 symbols=11240 edges=13755 ambiguous=5466 unresolved=3160 precise=3
```

`ambiguous/edges = 39.7%`. Use-site counts for five type-only symbols, same binary:
`--uses=IngestResult` **0**, `--uses=Narrower` **0**, `--uses=ScipOverlay` **0**, `--uses=AffResult`
**0**, `--uses=VarSpan` **1**. (The recon report measured `files=1163 … edges=12072 ambiguous=4885` on
a different branch with a different untracked file set; the numbers above are this lane's own and are
the ones the criteria below are read against.)

**Success criteria, registered before the code.**

* **#1a** On a purpose-built fixture where a type is named ONLY in type position (parameter type,
  return type, member type, template argument) and never called or constructed, `--uses=<T>` goes from
  `count="0"` to ≥ 4 rows carrying an honest role marker at the exact `file:line` of each mention.
* **#1b** `edges=` and `ambiguous=` over that fixture are **unchanged, byte-for-byte on the whole
  default map**, before and after — the proof that `Type` never entered the CSR.
* **#1c** Negative control: a *local variable* whose name equals the type's name yields no type-role
  row (it is a `Read`/`Write` site, not a type mention).
* **#2a** `ambiguous=` on ripwire's own tree **decreases** against the 5466 baseline.
* **#2b** Zero known-good edges lost on a pinned fixture set: the whole gate suite stays green, and an
  ordinary constructor call `Handler h;` keeps its edge.
* **#2c** The `Call`-role edge count is unchanged by the predicate alone.

**Failure criteria that revert the item.**

* #1 reverts if the default map over any corpus is not byte-identical (a `Type` ref reaching the CSR),
  if determinism breaks, or if a type-role row is emitted at a *definition* site (a self-reference).
* #2 reverts if `ambiguous=` fails to decrease (criterion #2a unmet — the predicate is then a no-op and
  is not worth a behavioral surface), or if any known-good edge is dropped.

**What moves if either lands.** #1 changes extraction ⇒ `kParserVer` 66 → 67 and
`quality.h::kIngestParserVerMirror` 66 → 67 in the same commit, plus the `--uses` legend, the `--help`
text, and every recorded capture in `docs/COMMANDS.md` (arm G is byte-parity). #2 moves `edges=` /
`ambiguous=` on real corpora ⇒ the same re-capture obligation.

**Red-first reference binary.** A `build/ripwire` built from `ba3a716` — the same commit this lane
branches from — kept in a separate worktree. Every gate below is recorded FAILING against it before the
feature code exists.

#### RESULT — #1 ACCEPT, #2 REJECT on its own registered criterion (2026-08-20)

**Red-first, recorded.** Against the `ba3a716` binary, `test/typerefcheck.sh` failed 5 arms / passed 5
and `test/nsfiltercheck.sh` failed 1 / passed 7 — each failing on exactly the arms the feature code is
supposed to turn green, and on no others. Both are `ALL PASS` on the lane binary.

**#1a MET.** `--uses` counts on this tree, pre-fix binary → lane binary, same working tree:

| symbol | before | after | | symbol | before | after |
| --- | --- | --- | --- | --- | --- | --- |
| `IngestResult` | 0 | **416** | | `ScipOverlay` | 0 | **7** |
| `Symbol` | 2 | **308** | | `AffResult` | 0 | **5** |
| `RawRef` | 0 | **37** | | `VarSpan` | 1 | **4** |
| `ComposeEdge` | 0 | **10** | | `UseCtx` | 0 | **3** |
| `ShadowEvidence` | 0 | **2** | | `Narrower` | 0 | **1** |

On the fixture, `--uses=Widget` returns 5 `role="type"` rows at the four pinned mention lines.

`Narrower` reaching 1 rather than its 14 textual mentions is the disclosed limit doing its job, not a
miss: the other 13 are the SCOPE segment of `Narrower::appendUint`, and a qualified name's segment has
never been a use-site here — the same rule that already excludes a qualified VALUE read. The legend now
states that limit rather than leaving it to be discovered.

**#1b MET, in the strongest available form.** Not "`edges=`/`ambiguous=` are unchanged" but the whole
default map is **byte-identical** between the pre-fix binary and the lane binary on the same tree
(`files=1300 symbols=11264 edges=13761 ambiguous=5468 unresolved=3160 precise=3` either way). Two
independent reasons, both load-bearing: `buildGraph` admits only `Call` and `Macro`, and the value-uses
pass is RICH-family only, so the lean blob that backs the default map holds no type row at all.

**#1c MET.** The local variable named `Widget` yields no type row, and the definition site is not a
use-site.

**#2a NOT MET ⇒ REJECT, and the criterion is unmeetable at the registered site.** `ambiguous=` is
unchanged (5468 → 5468). This is not a weak effect, it is a proof: the call-edge resolve loop admits
only `role=Call` — un-narrowed by the hard constraint — and `role=Macro`, whose name is uniquely a macro
by construction (`retagMacroCallReferences` assigns the role only when `scanMacroNames` reports flags==1
over exactly the language set `langCompatible` bridges, so every candidate surviving the language gate
is already `SymKind::Macro`). A namespace filter there can therefore never remove a candidate. The
registered failure criterion says this reverts the item, and it does: `namespaceCompatible` stays as the
single statement of the rule and as the executable form of the Call-un-narrowed constraint, but it
buys **no measured ambiguity reduction** and is not published as one.

Three claims in the recon report that this re-derivation corrected, recorded so the next round does not
re-pay for them:

* *"Every `Extends` reference today sprays across every same-named definition regardless of kind."*
  False — the implementors builder has been kind-filtered all along (`isClassLike`), and `Extends`
  references never reach the call-edge loop at all.
* *"Expected effect on `amb=`: real and unconditional."* False, per the proof above.
* *"`--uses`, `--impact`, `--affected`, `--situ`, `--pr-context`, `--test-gate` all gain the type-only
  dependents."* Only the RICH-family verbs can see the new references, and `--impact` / `--affected` /
  `--situ` / `--pr-context` are LEAN and CSR-driven. What genuinely gains is `--uses` and the MCP
  server's `uses` / `find_referencing_symbols` (the MCP index ingests RICH).

**#2b MET.** No known-good edge lost: 434/437 gates pass, `Handler( 3 )` keeps both its `role="call"`
site and its call edge, and the byte-identical default map is a stronger statement than the fixture set.

**#2c MET, trivially** — byte-identical map ⇒ unchanged Call-role edge count.

**Cost.** The RICH per-file cache blob grows 15.48 MB → 15.86 MB (+2.5%) on this tree; the LEAN blob is
unchanged. Type mentions are dense, so this is the volume the recon report flagged, measured: it is
real and it is small.

**Deliberately out of scope, and disclosed rather than taken silently.** `contextratio` skips
`role=type`: a member declaration already contributes a site through its HAS-A compose reference over
the same bytes, and this lens feeds thresholds calibrated in §9 over the pre-`Type` reference stream.
Admitting type mentions there is a real improvement AND a real re-calibration, so it needs its own
registered round rather than a free ride on a use-site lane.

**A second, narrower input change to the same lens — disclosed 2026-08-20 (V-5), verdicts unchanged.**
The paragraph above covers the `role=type` *skip*; it did not cover the `namespaceCompatible` narrowing
that `c604254` also added to `contextratio.h::resolveCandidates`. That narrowing does move the coupling
lens's ambiguity facts — not for `Type`, which `collectFacts` `continue`s on 28 lines earlier and which
therefore can never reach `resolveCandidates`, but for **`Extends`**: a base clause now binds only to
class-like definitions, where before it also offered a same-named free function. Measured effect on this
tree: **zero** — `--context-ratio` is byte-identical between the `ba3a716` and the merged binary over the
1 304-file corpus (18 976 B), as are `--metrics` and `--quality-panel`, and it is zero on
`test/typereffix` too. It is non-zero only on a corpus that carries a same-name class/function collision
in a base-clause position, which `test/nsfilterfix` is built to be (`Derived`: `ents` 2→1, `amb` 1→0).
The §9 calibration corpus is therefore only affected to the extent it holds such collisions, and this
disclosure exists so a re-derivation of §9 knows to check rather than assume. `test/nsfiltercheck.sh`
arm 5 pins the effect; the two source comments that attributed it to `RefRole::Type` were corrected in
the same commit.

**Battery at `bf67225`.** `gates=437 pass=434 skip=2 fail=1`; the one failure is
`ripwirepubliccheck.sh` arm 3, verified RED at the clean integration baseline `ba3a716` in a detached
worktree — pre-existing, on three wave-3 lines this lane never touched. ASan+LSan clean on the default
map, `--uses`, `--metrics` and both fixtures; determinism byte-identical ×3 cold, warm==cold, and ×3 on
the RICH `--uses` path; `xmllint` clean; golden unchanged; `--quality-delta` exit 0 with
`regressions="0" gating="0"` (the 16 stale acks are identical at the baseline).

### Depth-2 receiver-chain resolution — PRE-REGISTERED 2026-08-21 (before any feature code)

Item #3 of the stack-graphs recon lane, deliberately excluded from the round above and registered here
on its own. `ingest.cpp::receiverOf` classifies a call-site receiver as `ThisObj` (`this`/`self`),
`NamedVar` (a bare identifier) or `None`. Every **chained** receiver — `this->m_pool.acquire()`,
`cfg.opts.enable()`, `m_cfg.opts.enable()` — lands in `None`, so the call reaches neither Rule 1, Rule 2,
Rule 2b, CHA-lite nor `receiverStaticType`, and falls to the bare-name spray. The change widens
`RecvKind` by exactly ONE intermediate hop (`FieldOfThis`, `FieldOfVar`), carries the intermediate field
name through the existing `Reference::fieldName` slot, and adds a Rule 4 that resolves the intermediate
through the `class#field → declared type` table Rule 2b already consumes, then applies Rule 2b's own
member/base-walk at the final hop.

**Two claims of the recon report re-derived before registering, and the design changed by both.**

* *"`composeEdges` is built after the resolve loop; Rule 4 needs it before, so the hoist is the thing to
  prove first."* The hoist is **unnecessary**. `graph.h::buildFieldNarrowTables` (`graph.h:648`) is
  already called at `graph.h:919`, ahead of the resolve loop, and is built from the SAME `isCompose`
  reference stream `composeEdges` is built from at `graph.h:1907` — `fieldTypeByClass` is the
  `(owner, field) → declared type` table under a third name, already tombstoned on conflict and already
  consumed by Rule 2b. Rule 4 reads that table. `buildGraph`'s statement order does not move at all, so
  the reordering risk the report flagged is not taken rather than being proven safe.
* *"`RecvKind` widens ⇒ `kParserVer` bump"* — confirmed, and it is not the only consequence. Five sites
  test `recv == RecvKind::None` (`model.h:848` macro retag, `model.h:969` shadow suppression,
  `graph.h:1195` fn-pointer binding, `resolve.h:1403` Rule 1's `bareCish`, `resolve.h:1655`
  `receiverStaticType`). A chained receiver stops satisfying all five. Rule 1's `bareCish` is the
  load-bearing one: **today `this->m_pool.acquire()` is treated as a bare unqualified call and Rule 1
  will pin it to the enclosing class's own `acquire` when one exists** — a wrong narrow that this change
  removes. That removal can *raise* ambiguity where it fires, which is why criterion **#3b** below is
  registered as a whole-tree measurement and not assumed.

**Baseline, re-derived on this lane's own base build** (`cd30104`, `./build/ripwire` built in
`lane/depth2-chains`, measured against a pristine detached checkout of `cd30104` so no untracked plan doc
or build tree can move it):

```
files=1308 symbols=11367 edges=13933 ambiguous=5519 unresolved=3203 precise=3
```

`ambiguous/edges = 39.6%`. Fixture-level baseline, same binary, `test/fieldnarrowcheck.sh`'s generated
corpus: `ambiguous=7`, with its `(b) expl` arm asserting that `this->m_pool.acquire()` **stays split** —
that arm is a statement of exactly the limit this lane closes and must flip in the same commit.

**Success criteria, registered before the code.**

* **#3a** On a chained-receiver fixture, calls that spray today resolve to the intermediate field type's
  member: `this->m_pool.acquire()` → `Pool::acquire` only, `cfg.opts.enable()` (typed local base) →
  `Opts::enable` only, `m_cfg.opts.enable()` (field base) → `Opts::enable` only, with every same-named
  decoy left unlinked. Each is RED against the `cd30104` binary.
* **#3b** `ambiguous=` on ripwire's own tree **strictly decreases** against the 5519 baseline.
* **#3c** Zero Call edges lost on a pinned fixture, in the auditable form: every positive arm's correct
  edge is present, and every degrade arm keeps its COMPLETE honest split (both decoy edges), so the only
  edges the change removes are the ones the narrow provably excludes. The fixture's `edges=` is pinned to
  an exactly-derived post value, so a silently dropped edge is a gate failure rather than a smaller number.
* **#3d** Determinism byte-identical ×3 cold, and warm == cold across the `kParserVer` bump.
* **#3e** The disclosed limits stay disclosed, each with its own negative-control arm: a depth-3 chain
  (`this->m_cfg.opts.enable()`) refuses; an unindexed intermediate type refuses; a tombstoned
  `class#field` refuses; a scope-less free function refuses; and **Python `self.pool.acquire()` stays
  honestly split** — the receiver SHAPE is captured for Python (it is a fact about syntax), but the
  field-type table is C++ evidence only, so Rule 4 is C-family gated exactly as Rule 2b is.

**Failure criteria that revert the lane.**

* Reverts if **#3b** is unmet — if `ambiguous=` fails to strictly decrease on ripwire's own tree, the
  wrong-narrow removal costs more than the chain resolution buys and the widening is not worth an
  extraction change plus a `kParserVer` bump.
* Reverts if any degrade arm loses part of its honest split (a narrow that guesses), if determinism or
  warm==cold breaks, or if a Rule-4 target is ever a definition the bare ladder could not also reach
  (the "never invent a candidate" contract).

**What moves if it lands.** Extraction changes ⇒ `kParserVer` 67 → 68 and
`quality.h::kIngestParserVerMirror` 67 → 68 in the same commit (`qextractionkeycheck`).
`test/fieldnarrowcheck.sh`'s `(b) expl` and `(h) ambiguous=7` arms are re-derived in the same commit —
they pin the limit being closed. `edges=` / `ambiguous=` move on real corpora ⇒ the `docs/COMMANDS.md`
byte-parity captures (`docscommandscheck` arm G) are re-recorded from this tree.

**Red-first reference binary.** `build/ripwire` built at `cd30104` — the commit this lane branches from —
copied aside before any source edit. `test/chainrecvcheck.sh` is recorded FAILING against it before the
feature code exists.

#### RESULT — REJECT on the registered criterion, and REVERTED (2026-08-21)

The feature was built, gated red-first, measured, and then **reverted at `lane/depth2-chains`** because
criterion **#3b** — the one the registration named as the lane's value test — was not met. The code is
in this branch's history at `c3ebbd8` (implementation) and `71ec7c5` (the gate) for a future round that
registers a different instrument; the tree at the lane head is byte-identical to `cd30104` outside this
section.

**Red-first, recorded.** Against the `cd30104` binary, `test/chainrecvcheck.sh` was **6 FAIL / 16 PASS**,
failing on exactly the four chain shapes Rule 4 resolves plus the two header gauges, and on no others.
The six degrade arms were green before and after. On the lane binary the gate was ALL PASS, including
under ASan.

**#3a MET.** `this->m_pool.acquire()` → `Pool::acquire` alone; `c.opts.enable()` over a typed local →
`Opts::enable` alone; `m_cfg.opts.enable()` over a field base → `Opts::enable` alone; a declared local
`DCfg cfg` shadowing a field `Cfg cfg` → `DOpts::enable`, never `Opts::enable`. Every decoy unlinked.

**#3b NOT MET ⇒ REJECT.** On ripwire's own tree, against a pristine detached `cd30104` checkout:

| binary | edges= | ambiguous= |
| --- | --- | --- |
| `cd30104` baseline | 13933 | **5519** |
| capture widening ONLY (Rule 4 disabled in a scratch worktree) | 13941 | **5522** |
| capture widening + Rule 4 (the lane) | 13941 | **5521** |

`ambiguous=` rose by 2 where the criterion required a strict decrease. The three-way split is the finding,
and it is worse for the feature than the aggregate looks: **Rule 4's own lever on 1308 files, 11367
symbols and 13941 edges is exactly ONE call site** (5522 → 5521). The rule is correct — the fixture proves
each shape — but ripwire's own data-oriented C++ (free functions, public POD fields, subscripted access
like `ing.symbols[i].name`, and chains through `std::` types the index does not define) barely contains
the idiom it resolves. A `kParserVer` bump costs every user a full re-parse; one resolved call site does
not buy it.

**Where the +3 comes from — mechanism, not attribution guesswork.** Widening `RecvKind` changes five
sites that test `recv == RecvKind::None`. Three micro-fixtures, base binary vs lane binary:

* *Rule 1's `bareCish` arm was WRONG-narrowing chained receivers.* `struct App { Pool m_pool; void run();
  void go(){ this->m_pool.run(); } }` — the base binary binds `go` to **`App::run`** (the caller's own
  class) because a chained receiver reads as a bare unqualified call; the lane binary binds it to
  **`Pool::run`**. A silently wrong edge replaced by the right one, invisible in `ambiguous=` because
  both are one edge. Where Rule 4 then cannot resolve the field's type, the same site degrades from a
  wrong pin to an honest split — that is the direction that ADDS to `ambiguous=`.
* *Shadow suppression was deleting real member calls.* `void go(){ int enable = 0;
  this->m_cfg.enable(); }` — the base binary emits **zero** call edges for `go`: the local named `enable`
  suppressed the reference outright. The lane binary emits the correct edge to `Cfg::enable`. This is the
  `edges=` +8: recovered calls, not invented ones. Each recovered call is then honestly ambiguous wherever
  its name is.
* The macro-retag and fn-pointer-binding guards move in the same direction (a receiver-qualified name is
  neither a macro invocation nor a call through a bare variable) and are not separately measurable here.

So the `ambiguous=` rise is **recovered and corrected information, not new noise** — and that is precisely
why this is recorded as a REJECT rather than quietly re-read as a pass: the criterion was registered
before the measurement, it is unmet, and revising an instrument after seeing its answer is the failure
mode pre-registration exists to prevent. The two bugs above are real, are reproducible from the fixtures
in `71ec7c5`, and want their own round with an instrument that can see them (recovered-edge count and
corrected-target count, not `ambiguous=`).

**#3c MET** — the fixture's `edges=` pin (22 → 15) accounts for every removed edge as a decoy the narrow
provably excludes, and all four degrade arms keep their COMPLETE split.
**#3d MET** — determinism byte-identical ×3 cold, warm == cold across the version bump, `xmllint` clean.
**#3e MET** — depth-3, unindexed intermediate type, tombstoned `class#field`, scope-less free function,
Python and TypeScript all refuse. One limit the fixture DISCOVERED and now pins: a **parameter** base
(`void f( DCfg cfg ){ cfg.opts.enable(); }`) cannot narrow, because the binding capture records a
parameter's name but not its type, and the parameter still shadows a same-named field — so the honest
split is the only sound answer. That is the same answer Rule 2 already gives a depth-1 parameter receiver.

**The recon report's `composeEdges` hoist is unnecessary — re-derived, and the design changed by it.**
`graph.h::buildFieldNarrowTables` (`graph.h:648`) already runs at `graph.h:919`, ahead of the resolve
loop, over the SAME `isCompose` reference stream `composeEdges` is built from at `graph.h:1907`; its
`fieldTypeByClass` IS the `(owner, field) → declared type` table, already tombstoned on conflict and
already consumed by Rule 2b. Rule 4 read that table and `buildGraph`'s statement order never moved, so
the reordering the report wanted proven red-first was not taken at all. The compose builder's
`langCompatible` guard is respected transitively: Rule 4's candidates pass the same
`langCompatible && sameRoot` filter at the call site that every other rule's candidates do.

**Cost, measured, for the next round to weigh.** `--quality-delta=cd30104..HEAD` on the feature build:
`regressions="16" gating="6"` — `receiverOf` complexity 16 → 33 and LOC 46 → 88, `buildGraph` complexity
764 → 780, plus one duplication finding pairing the new 53-token `Narrower::finalScopeSegment` with an
unrelated `mcphttp::isJsonContentType`. ASan+LSan clean on the default map and on the gate.

**Battery on the feature build (`c3ebbd8`, before the revert).** Suite green apart from three, all
accounted for: `qschemetripcheck` (expected — `kParserVer` moved; re-pinned with `UPDATE_GOLDEN=1`),
`readmeexamplecheck` (the README's recorded `--callers=rankGraphTeleport` capture carries `src/graph.h`
line numbers, which the 23-line Rule 4 block shifted by exactly 23 — the caller SET was byte-identical
between the two binaries), and `editcheckcheck`'s 100 ms warm budget, which fails **identically on the
`cd30104` binary in a clean short-path worktree under the same concurrent-lane load** (base 201/120 ms,
lane 142/101 ms) — environmental, not a lane effect. `docscommandscheck` arm G was green: no recorded
capture in `docs/COMMANDS.md` moved.

**Battery at the reverted head `5d7ec08`.** Clean rebuild, then `edges=13933 ambiguous=5519` — the
`cd30104` baseline restored exactly. Suite: `gates=440 pass=436 skip=2 fail=2 wall=1007.5s jobs=6`, both
failures cleared: `g1freshcheck` fired correctly because the `asan/` tree still held the `c3ebbd8` binary
that the revert made older than `src/` (the stale-artifact class `CLAUDE.md` documents — cleared by
`cmake --build asan --clean-first`, then ALL PASS), and `editcheckcheck` is ALL PASS on a solo re-run.
The two skips are the standing self-skips (`namingcalibrationcheck` withholds live judgement,
`argvdiffcheck` has no `RIPWIRE_BASE`). ASan+LSan clean, determinism byte-identical ×3, `xmllint` clean,
`--quality-delta=cd30104..HEAD` → `regressions="0" gating="0"`, exit 0.

### Receiver-guard misfires: `bareCish` wrong-narrow + shadow deletion — PRE-REGISTERED 2026-08-21 (before any fix code)

The two resolver-correctness bugs the depth-2 lane's REJECT surfaced and declined to rescue
(`lane/depth2-chains` @ `21f75a9`, its RESULT section in that branch's copy of this file;
`PLAN_HARVEST_REPORTS_2026-08-20/depth2-lane.md` §6). Both share one root cause: `receiverOf`
classifies EVERY chained receiver as `RecvKind::None`, and five guard sites key on
`recv == RecvKind::None` (`model.h` macro retag + shadow suppression, `graph.h` fn-pointer binding,
`resolve.h` Rule 1 `bareCish` + `receiverStaticType`). Two of the five misfire observably:

* **Bug 1 — Rule 1's `bareCish` arm wrong-narrows chained receivers.** `struct App { Pool m_pool;
  void run(); void go(){ this->m_pool.run(); } }` — the chained receiver reads as a bare unqualified
  call, so Rule 1 pins `go → App::run` (the caller's OWN class), a silently wrong PRECISE edge where
  the honest answer is the split that includes `Pool::run`.
* **Bug 2 — shadow suppression deletes real member calls.** `void go(){ int enable = 0;
  this->m_cfg.enable(); }` — the receiver-qualified call cannot resolve to the local, but the
  `recv == None` guard cannot see the receiver, so the reference is deleted outright: `go` emits ZERO
  call edges.

**Why a new instrument.** The two bugs NET against each other in `ambiguous=` — a removed wrong pin
*raises* it, a recovered call raises it only where the name is multi-def — which is exactly how the
depth-2 lane's #3b criterion (strict decrease) rejected a change that fixed both. This round's
instrument counts each bug separately: **recovered-edge count** (calls that exist in source and emit no
edge today) and **corrected-target count** (calls whose lone edge today is a provably wrong pin), per
change, against a pinned corpus.

**The fix under measurement, and its re-justified scope.** The capture widening from the reverted
`c3ebbd8`, ALONE: `RecvKind` gains `FieldOfThis` / `FieldOfVar` (depth-2 chains only; depth ≥3 stays
`None`), the intermediate field name rides the call ref's otherwise-free `fieldName` slot, and the five
guards are NOT edited — a chained receiver simply stops satisfying `recv == None`, which is the whole
fix. Rule 4 (chain RESOLUTION through the field-type table) stays out, per the lane's own finding: its
lever on this tree is one call site and it wants a heavily-OO corpus head-to-head before it is funded.
Carrying the field/var names now is deliberate: the classifier must read those nodes anyway to bound the
shape, and a future Rule 4 round becomes resolve-side only — no second `kParserVer` re-parse for every
user. Extraction VALUES change ⇒ `kParserVer` 67 → 68 + `quality.h` mirror in the fix commit.

**The instrument, built and shown red before the fix.**

* `test/chainguardcheck.sh` — micro-fixture gate (fixtures generated, line-numbers load-bearing,
  `--callees` def-site assertions). Bug-1 arms assert the full honest split WITH the old target
  retained; Bug-2 arms assert the recovered edge (one single-def flavor that lands precise, one
  multi-def flavor that lands honestly split). Controls that must be green before AND after: bare
  Rule-1 narrow (`run()` inside `App`), depth-1 `NamedVar` Rule 2b narrow, Python `self.pool.acquire()`
  and TS `this.cfg.opts.enable()` edge sets unchanged, and the depth-3 residual pinned as DISCLOSED
  (both bugs persist for `this->a.b.m()` — the capture bound is one hop; separately fundable).
  Determinism + warm==cold across the version bump ride in the gate.
* `test/edgediff.py` — the whole-tree audit: parses two full maps (`--top-k` ≥ symbol count) of the SAME
  pinned corpus from two binaries, keys symbols by `(file, id|name, kind)`, and classifies every changed
  caller: **RECOVERED** (a callee name appears that had no edge before), **SPLIT-WIDENED** (same callee
  names, edge count and `amb=` rose — a pin became an honest split), **REMOVED** (an edge vanished —
  this class must be EMPTY), plus header-gauge deltas. Deterministic output, sorted.

**Pinned corpus.** The gate's generated fixtures, plus ripwire's own tree at `cd30104` measured as a
pristine detached checkout. Baseline re-derived on this round's base build of `cd30104`:

```
files=1308 symbols=11367 edges=13933 ambiguous=5519 unresolved=3203 precise=3
```

**Success criteria, registered before the code.**

* **#B1 (corrected targets, fixture)** Every Bug-1 arm flips: base binary emits the lone wrong pin to
  the caller's own class; fixed binary emits the complete honest split, old target retained. RED at
  `cd30104`.
* **#B2 (recovered edges, fixture)** Every Bug-2 arm flips: base binary emits zero call edges for the
  shadowed member call; fixed binary emits the member-call edge(s). RED at `cd30104`.
* **#B3 (whole tree, exact prediction)** On the pristine `cd30104` checkout the fixed binary lands
  `edges=13941`, `ambiguous=5522`, `symbols=11367`, `files=1308` — the depth-2 lane's measured
  capture-widening-only arm IS this prior (`rw-d2-probe`, Rule 4 disabled). Any other landing is an
  unexplained divergence: the round does not accept until `test/edgediff.py` decomposes it.
* **#B4 (whole tree, accounting)** `test/edgediff.py` accounts EVERY changed caller: each RECOVERED
  site and each SPLIT-WIDENED site is hand-verified against source (the call exists; the receiver is
  chained; for splits, the old lone target was the caller's own class or otherwise provably
  wrong-pinned) and listed in the RESULT. The REMOVED class is empty — this fix deletes nothing.
* **#B5 (no collateral)** `test/shadowcheck.sh` (bare-name suppression), `test/fieldnarrowcheck.sh`
  (Rule 2b) and the full suite stay green; Python/TS fixture edge sets byte-stable.
* **#B6 (contract)** Determinism byte-identical ×3 cold on the pristine checkout, warm == cold across
  the `kParserVer` bump, `xmllint` clean.

**Failure criteria that revert the round.** Any REMOVED edge on fixture or tree; any hand-verified site
that turns out not to be a real call / not a wrong pin; #B3 landing off-prediction with a decomposition
that reveals an unintended behavior change; determinism or cache transparency breaking. `ambiguous=` is
NOT a criterion here in either direction — that gauge cannot see these bugs, which is this
registration's reason to exist.

**What moves if it lands.** `kParserVer` 67 → 68 and `quality.h::kIngestParserVerMirror` in the same
commit (`qextractionkeycheck`); `qschemetripcheck` golden re-pinned; gate count 432 → 433
(`manifestcheck` pins). Predicted NOT to move: `test/fieldnarrowcheck.sh` arms and gauges (its fixture
has no same-named member in the enclosing class and no shadowing local over a chained call) — verified,
not assumed, in the fix commit.

#### RESULT — ACCEPT on every registered criterion (2026-08-21)

The fix is the capture widening alone plus ONE discovery the red gate forced (below); `kParserVer`
67 → 68 with the `quality.h` mirror in the same commit. Rule 4 stayed out, as registered.

**Red-first, recorded.** Against the `cd30104` binary, `test/chainguardcheck.sh` was **8 FAIL /
17 PASS** — failing on exactly the five bug arms plus the two fixture gauges (the base binary reads the
bug fixture as `edges=6 ambiguous=0`: six calls pinned or deleted, ZERO disclosed ambiguity, wrong five
times over), and on no others. On the fixed binary: ALL PASS, including under ASan.

**The discovery the gate forced — a SIXTH `recv`-ignorant site.** With the widening in place and Rule 1
correctly refusing, arms (a)(b)(c) stayed RED: the **S6-C locality tie-break** re-minted the identical
wrong pin. The caller's canonical id shares its scope segment with the caller's own class's member and
not with the field type's, so `App::run` won the tie-break and `Pool::run` was dropped as "strictly
less local". The registration's mechanism list (five guard sites) was incomplete — the tie-break is a
sixth consumer of receiver ignorance, invisible to `ambiguous=` for the same netting reason. Fix: a
depth-2 chained-receiver call takes NO locality tie-break (the explicit receiver redirects the call
away from the enclosing scope, so scope-segment credit there is anti-evidence); ThisObj/NamedVar keep
the tie-break unchanged. One added guard in `graph.h`, disclosed here because the registration said
"the five guards are NOT edited" — five were not; the sixth did not exist in the registration's model
of the bug. Finding it is the gate-before-code discipline doing its job.

**#B1 MET (corrected targets, fixture).** `this->m_pool.run()` → the complete split
{`Pool::run`, `App::run`}, old target retained; same for the field-base and typed-local-base FieldOfVar
arms. **#B2 MET (recovered edges, fixture).** `int enable = 0; this->m_cfg.enable();` → recovered as
the complete 2-way split; the single-def flavor (`m_box.opts.ping()` under a local `ping`) recovers
precise.

**#B3 MET — the whole-tree landing hits the registered prediction EXACTLY.** Pristine detached
`cd30104` checkout, `test/edgediff.py` between the base and fixed binaries:

| gauge | base | fixed |
| --- | --- | --- |
| edges= | 13933 | **13941** (+8, predicted +8) |
| ambiguous= | 5519 | **5522** (+3, predicted +3) |
| symbols= / files= | 11367 / 1308 | unchanged |

**#B4 MET — every changed caller accounted and hand-verified.** The audit classifies ALL +8 edges as
RECOVERED (the shadow-deletion class); **SPLIT-WIDENED is EMPTY** — ripwire's own tree contains no
chained-receiver wrong-pin for either mechanism, consistent with the depth-2 lane's "one call site"
ceiling finding — and **REMOVED is EMPTY**: the fix deletes nothing. The five recovered sites, each
read in source:

* `src/lexindex.h::buildDefLexStats` — `std::sort( out.tokenHashes.begin(), out.tokenHashes.end() )`
  under the function's own local `end`. Recovered → `rw::svector::end()` ×2 (`svector.h:270`/`272`, the
  const/non-const overloads — the split is the two real overloads of the CORRECT class: `tokenHashes`
  IS an `rw::svector`). +2 edges, amb 4→5.
* `src/nonlocalstate.h::propagateToCallers` — `const auto* rowOffsets = g.inEdges.rowOffsets();` and
  its `colIndices` twin: the declarator's OWN name shadows the method being called in its initializer
  ([basic.scope.pdecl] — the initializer sits inside the new name's scope), so the base binary emitted
  NO edge for either call. Recovered → `sparseCsr::rowOffsets()` ×2 / `colIndices()` ×2 (the
  mutable/const overload pairs, `sparseCsr.h:248-252` — again the correct class). +4 edges, amb 4→6.
  The same idiom with a DIFFERENT local name (`editcheck.h:414`, `const auto* ro = …`) was never
  deleted — the bug required the name collision, which is why it hid.
* `test/cloneband_harness.cpp` / `test/type3clone_harness.cpp` `addWholeFileFn` — `ing.files.size()`
  under the parameter `size`. Recovered → `rw::svector::size()` (`svector.h:285`), +1 edge each, amb
  unchanged. Caveat recorded: the TRUE callee is `std::vector::size` (unindexed), so the recovered
  edge is the name-ladder's answer — the same answer every unshadowed `.size()` call in the corpus
  already gets. Recovery to parity, not a new claim of precision.

**#B5 MET.** `fieldnarrowcheck` green UNCHANGED (as the registration predicted — verified, not
assumed); `shadowcheck` green (bare-name suppression intact); Python/TS fixture gauges byte-stable
(`edges=4 ambiguous=2`). **#B6 MET.** Determinism byte-identical ×3 cold on the pristine checkout;
warm == cold across the `kParserVer` bump; `xmllint` clean.

**Cost, measured — and the delta findings the instrument round-tripped.**
`--quality-delta=cd30104..HEAD`: `regressions="6" gating="0"`, exit 0. The first cut GATED
(`receiverOf` complexity 16→33, LOC 46→88) and was refactored rather than acked: the depth-2 arm became
a bounded recursion (`classifyReceiver`, the one-hop bound enforced by an `allowChain` flag), and the
first extraction attempt itself round-tripped through TWO further gating findings — a fresh
`recvNodeText` duplicating the existing `pattern::nodeText` (deleted; `ingest.cpp` already includes
`pattern.h`) and a 272-token `chainReceiverShape`/`receiverOf` clone pair (dissolved by the recursion).
The refactor is behavior-neutral: the full pristine-tree map is byte-identical before and after it.
Remaining rows are all origin=new-symbol or sev=minor — `classifyReceiver` cx 21 (the guard ladder IS
the feature), `parseMap` cx 22 (the Python instrument), the 31-token
`memberAccessReceiver`/`memberAccessField` accessor pair (kept: a bool-parameter merge reads worse),
`buildGraph` +8 LOC (the locality-guard comment), `captureTagsFacts` +1 LOC.

**Battery at the fix tree.** Final full suite at the finished tree:
**`gates=441 pass=439 skip=2 fail=0 wall=443.0s jobs=6` — ALL PASS**; the two skips are the standing
self-skips (`namingcalibrationcheck` withholds live judgement; `argvdiffcheck` has no `RIPWIRE_BASE`).
The mid-round run had two failures, both accounted before the final run: `readmeexamplecheck` — the
README's recorded `--callers=rankGraphTeleport` capture carries `src/graph.h` line numbers, which the
9-line locality-guard block shifted by exactly 9 (2168→2176, 2504→2512); the caller SET was
byte-identical, re-recorded, and `docscommandscheck` arm G stayed green throughout. `editcheckcheck` —
the 100 ms warm budget under sustained parallel-lane load (load average ~25 during the mid-round runs);
**control run: the `cd30104` base binary fails it HARDER under the same load (183/169 ms vs the fix
binary's 144-163 ms)** — environmental, not a regression, and ALL PASS in the final suite run.
ASan/LSan (`-DRIPWIRE_ASAN=ON`, committed suppressions, clean-first rebuild): exit 0, zero sanitizer
lines on the whole-tree default map, and `chainguardcheck` is ALL PASS under the ASan binary.
`qschemetripcheck` golden re-pinned (the mirror value keys the snapshot cache, so stale snapshots
self-invalidate — the "just re-pin" path, as the depth-2 lane took).

**Residuals, disclosed.** (1) Depth ≥3 chains still classify `None`: BOTH bugs persist there
(`chainguardcheck` arm (h) pins `deepPin`/`deepShadow` as recorded facts) — the capture bound is
deliberate, and the residual is separately fundable. (2) TS/JS receivers are not captured at all, so a
TS chained call keeps whatever the bare ladder gives it (arm (j-ts) pins the stability). (3) The `size`
caveat above: recovery restores name-ladder parity; it cannot invent `std::` targets the index does not
hold.

### External-corpus retrieval-loss buckets — PRE-REGISTERED 2026-08-22 (before any fix code)

**What this registers.** Four separately-diagnosed retrieval-loss *mechanisms*, each with its own
baseline, its own ACCEPT band and its own revert decision. They are registered together because they
share one instrument, and judged apart because they are four different claims:

| Bucket slug | The mechanism |
| --- | --- |
| `diagnostic-class` | A conceptual query's content words are also the NAME of a diagnostic class (a `*Warning` / `*Error`, or a plugin whose only job is to report one). The diagnostic is named after the failure the real mechanism can produce, so it matches the query's words with a tiny body, and the implementation never surfaces. |
| `thin-registration` | The answer is a small registration/wiring class whose name spells most of the query's content words but which carries near-zero graph centrality. Structurally central symbols sharing *fewer* query terms displace it. |
| `subsystem-directory` | The concept the query names IS a directory name. Path components are not ranking evidence for the code lenses, so the query word matches inside unrelated symbol names elsewhere while the directory literally named for the concept contributes nothing. |
| `vendored-asset` | Vendored front-end assets and numbered database migrations take top slots in task bundles that have nothing to do with either. |

**Why a new instrument was needed.** `bench/recalleval/`'s two frozen corpora are snapshots of *this*
repository, and this tree contains no vendored asset directory, no numbered migrations, no thin
one-hook registration classes and no directory-per-subsystem layout with a diagnostic-class sibling
per mechanism. A gate written here for those shapes passes because the offending population is
**absent**, not because the ranker handles it — green-while-inert, the failure `CONTRIBUTING.md` §2
exists to prevent. So the slice is pinned to two outside trees that do contain the populations, and
the instrument is the same `--for` computation an agent actually consumes.

**The instrument.**

| Piece | File |
| --- | --- |
| Corpus pins + materialize recipe | `bench/recalleval/extcorpus.lock` |
| Labels (30 django rows + 24 webpack rows = 54) | `bench/recalleval/labels_extcorpus_{django,webpack}.tsv` |
| Absolute per-bucket scorer | `bench/recalleval/run_extcorpus.py` |
| Per-query comparative diff | `bench/recalleval/run_r3diff.py` (unmodified — it runs the slice as-is) |

Corpora are **pinned, not committed**: ~1 GB of third-party source under its own licences is not
vendored into a public export. The integrity anchor is the commit pin *plus* the tree hash, verified
before any query runs; a mismatch is a hard refusal (exit 2), never a quiet re-baseline. Both pins
and both tree hashes were verified in this lane before the baseline below was taken.

**Baselines — re-derived at `4692076` in this lane, before any fix code existed.** Plain dev build,
`--top-k=10`, two full runs byte-identical, zero skipped labels. The re-derivation reproduces the
draft registration's numbers exactly on all four buckets and on both per-corpus splits, which is the
provenance check that the instrument and the corpora are the same instrument the bands were drawn
against.

| Bucket | n | gold in top-5 | strict r@1 | strict r@5 | strict r@10 | lenient r@5 | strict MRR | asset slots in top-5 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `diagnostic-class` | 14 | **7 / 14** | 21.4% | 50.0% | 57.1% | 57.1% | 0.332 | 0.0% |
| `thin-registration` | 14 | **7 / 14** | 42.9% | 50.0% | 64.3% | 50.0% | 0.486 | 0.0% |
| `subsystem-directory` | 14 | **4 / 14** | 7.1% | 28.6% | 50.0% | 35.7% | 0.159 | 0.0% |
| `vendored-asset` | 12 | **6 / 12** | 16.7% | 50.0% | 58.3% | 58.3% | 0.326 | **10.0%** (6 of 60) |

Per corpus, because the split matters: `diagnostic-class` 6 rows django at 66.7% strict r@5 against 8
rows webpack at 37.5%; `thin-registration` the same 66.7% / 37.5%; `subsystem-directory` 33.3% /
25.0%; `vendored-asset` is django-only (webpack's analogous noise is a different mechanism and
folding it in would blur two of them).

**Bands — registered before any fix code exists.** The unit is a whole label row, and a band is at
least two units wide: the metric is a count over a fixed deterministic set, so a band narrower than
two rows reads label-set sensitivity rather than a mechanism.

| Bucket | Registered metric | Baseline | ACCEPT band | Width |
| --- | --- | ---: | --- | ---: |
| `diagnostic-class` | net flipped rows, gold-in-top-5, n=14 | 7 | **[+2, +6]** | 5 rows |
| `thin-registration` | net flipped rows, gold-in-top-5, n=14 | 7 | **[+2, +6]** | 5 rows |
| `subsystem-directory` | net flipped rows, gold-in-top-5, n=14 | 4 | **[+3, +8]** | 6 rows |
| `vendored-asset` (primary) | vendored/generated slots in top-5, of 60 | 6 | **[0, 2] remaining** | 3 slots |
| `vendored-asset` (guard) | net flipped rows, gold-in-top-5, n=12 | 6 | **[−1, +4]** | 6 rows |

- *Lower edges are non-zero on the three ranking buckets* because each fix is a deliberate ranking
  change with a real cost surface. A change that moves one row is indistinguishable from a change
  that moved that row by accident. `subsystem-directory` starts at +3 because it starts from the
  lowest base and its fix is the bluntest instrument on the list.
- *Upper edges are leakage guards, not ceilings.* A perfect score is deliberately **outside** every
  band: a change that lifts every gold in a bucket has probably found the label set rather than the
  mechanism, and that result is to be audited, not banked.
- *The asset band is stated in slots*, because slots is the unit the mechanism moves. Reaching 0 is
  in band — unlike the ranking buckets there is no leakage story for a path weight that
  de-prioritizes exactly the paths it names.
- *The asset guard is non-inferiority-shaped* (`−1` allowed): de-prioritizing a path family can cost
  a gold that sat behind one, and one row is an acceptable price for the slot recovery. Two is not.

**The two name-driven buckets overlap by six rows, and any result must decompose it.** Six of the
eight webpack `thin-registration` golds live under `lib/ids/`, which is also a `subsystem-directory`
population. A fix that works purely by lifting directories would move BOTH rates. Every result below
reports the two buckets separately AND states how many `thin-registration` flips were `lib/ids/`
rows; a `thin-registration` gain that is entirely `lib/ids/` is a `subsystem-directory` fix wearing
two hats.

#### Pre-code feasibility audit — registered before the fixes were written

The diagnosis that produced these buckets also proposed a fix *shape* per bucket. Two of those shapes
can be bounded from above on this label set **without running them**, by measuring the trigger
condition directly against the frozen labels. That bound is registered here, before any fix code
exists, so that an out-of-band result reads as a refuted mechanism rather than a badly chosen
constant discovered afterwards.

Measured over the 54 frozen rows (query subtokens minus a closed-class function-word list, against
the gold file's basename subtokens and its directory-component subtokens):

| Proposed shape | Trigger | Rows that can fire | Of those, rows currently missing top-5 | Ceiling |
| --- | --- | ---: | ---: | ---: |
| name-coverage floor at ⅔ | one symbol name covers ≥ ⅔ of the query's content subtokens | 2 of 14 | 1 | **+1** |
| name-coverage floor at ½ | same, at ½ | 4 of 14 | 2 | **+2** |
| directory-component evidence | ≥ 1 query content subtoken equals a directory component of the gold path | 7 of 14 | 5 | **+5** |

The `thin-registration` ceiling is the load-bearing number. At the proposed ⅔ threshold the shape can
flip **at most one row**, which is below the registered band's lower edge — so that instantiation is
refuted before it is built. The loosest threshold that still means "the name spells most of the
query" is ½, whose ceiling is exactly the band's lower edge; that is the instantiation this round
attempts, and it is registered as such. The reason the shape is so weak here is morphological, not
structural: the golds that miss are missed because `deterministically` is not the subtoken
`deterministic` and `chunks` is not `chunk`, and because one gold's concept word (`caps`) is a
synonym of its name's (`limit`) — six of the fourteen golds share only a single content subtoken with
their query, and six django golds share none at all.

The `diagnostic-class` shape is **not** bounded this way, and one part of its stated diagnosis is
corrected here before any code exists. The proposed shape was "require body-term evidence before
name-match alone can top-rank a tiny-body symbol". Read against the pinned tree, the displacing
symbols mostly *do* carry body evidence: a diagnostic's constructor recites the failure in the
reader's own vocabulary, so `lib/errors/UnusedReexportsWarning.js`'s constructor contains `unused`,
`exports` and `modules` in a fifteen-line body. A name-only predicate would therefore be largely
inert on the population it was written for. What the offenders share is not the *absence* of body
evidence but the *tininess* of the document that carries it — the same shape puts a one-line
`types.d.ts` method stub and a single-line constant above real implementations. The mechanism
registered here is accordingly **short-document over-reward in BM25 length normalization**, and the
fix attempted is a document-length floor: a symbol whose weighted subtoken length falls below a named
constant is normalized as if it were that long. The band is unchanged.

#### Simultaneous floors — all must hold; a bucket win bought past a floor is a REJECT

Every value was re-measured at `4692076` in this lane, on the binary that produced the baselines
above.

| Guard | Floor / ceiling | Measured at `4692076` | Headroom |
| --- | ---: | ---: | --- |
| skill routing split=test `bm25-desc` hit@1 | **≥ 60.0%** | **73.1%** | 13.1pp |
| skill routing split=test `bm25-desc` sep-auc | **≥ 0.89** | **0.957** | 0.067 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 | wide |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 64.5% (98/152) / 61.2% (93/152) | wide |
| recall lane lenient recall@5 | ≥ 71% | 88.1% | 17.1pp |
| recall lane lenient MRR | ≥ 0.57 | 0.643 | 0.073 |
| LIVE-corpus pollution@5 | ≤ 16% | 2.4% | 13.6pp |
| **ranking lane lenient recall@5** | **≥ 70%** | **71.9%** | **1.9pp — the tightest floor on the board** |
| ranking lane lenient MRR | ≥ 0.55 | 0.639 | 0.089 |
| ranking lane / adversarial-class pollution@5 | ≤ 5% / ≤ 8% | 0.0% / 0.0% | full |

Frozen corpora at the measurement: docs `commit=7a7f79892034 files=113 sha=cfeb23c71cd2`, source
`commit=7a3194b51ac6 files=1422 sha=eb25c17569d5`.

**The ranking lane's lenient recall@5 is the one to watch.** 71.9% against a 70% floor is under two
labels of margin on a 32-label lane. Three of the four fixes are general ranking changes, so this is
the floor a bucket win is most likely to be bought past — and buying it is a REJECT, not a trade.
**Expected direction on the in-tree lanes: neutral, and no directional claim is registered** — the
frozen corpora carry none of the four populations, which is why the slice exists. An in-tree lane
moving *up* is an unregistered result and is reported, not banked.

Standing requirements, not part of any band: `python3 test/pargates.py . ./build/ripwire -j 6` rc=0 ·
ASan/LSan clean under the committed suppressions · two runs of the slice and of both lanes
byte-identical · `--quality-delta` with zero unacked regressions · `bash test/ripwirepubliccheck.sh`
clean.

**One standing constraint that this round does not discharge.** The full-path BM25 field in
`src/lexical.h` (`pathFieldDefaultW`) carries an earlier held-out REJECT whose pre-registration binds
a nonzero *code-lens* default to a LocBench held-out acceptance run, and whose retry clause requires
"multi-file-primary, amortized first". The `subsystem-directory` fix attempted here is a **narrower,
separately-named** field — directory components only, basename excluded, amortized per file — and its
acceptance instrument is the slice registered above. It does **not** turn the full-path field on, and
it does **not** discharge that earlier obligation; if the narrower field is accepted here, the wider
one stays at 0 and the earlier registration stands untouched.

#### Decision rule

For each bucket independently: **in band with every floor above green → keep that bucket's change.**
Out of band on either edge, or any floor breached → **revert that bucket's change**, keep this
registration and the negative result on record, and keep any gate added for it only if it still
describes shipped behaviour. The four buckets are separable and land in separate commits; a reverted
bucket does not invalidate the others.

**One measurement, one attempt.** Each bucket gets exactly one measurement against these bands. A
retry is a new round with a fresh registration. Re-cutting a band after seeing a result, adding
labels to a bucket after measuring it, or refreshing the corpus pins in the same commit as a
measurement each turn the instrument into a description of the fix, and none is permitted.

#### Limits of this slice, recorded before it decides anything

- **Two repositories, two languages** (Python, JavaScript). Nothing here says a fix generalizes to
  C++, Go, Rust or Swift. A fix that is language-neutral by construction inherits that claim from its
  own shape, not from this measurement.
- **54 labels, per-bucket n of 12–14.** That smallness is why bands are stated in whole rows and why
  a one-row move is registered as indistinguishable from noise.
- **The labels are ours** — authored from the pinned source and frozen, but not an external gold set.
  Five rows carry an outside arm's answer on record; 49 do not.
- **`acceptable` is used narrowly** — only a file that lands the task without another call. A wider
  list would flatter every number above.
- **`vendored-asset` gold rank is not evidence for that bucket.** Several of those queries are hard
  for reasons unrelated to asset noise. The slot share is the metric that sees the mechanism; gold
  rank there is registered as a non-inferiority guard only.
- **Pinned to a moving upstream.** Both trees are active projects; the harness refuses rather than
  drifts if a pin stops being reachable, which is a weaker anchor than the content-hashed packs the
  two in-tree corpora use.

#### Results — measured 2026-08-22, one measurement per bucket, against the bands above

One of the four bands is met and ships. One is met and was reverted anyway. Two are missed. The
registration above is unchanged: nothing here re-cuts a band, adds a label, or re-reads an edge.

| Bucket | Registered metric | Baseline | Measured | Band | Verdict |
| --- | --- | ---: | ---: | --- | --- |
| `vendored-asset` (primary) | vendored/generated slots in top-5, of 60 | 6 | **0** | [0, 2] | **ACCEPT — shipped** |
| `vendored-asset` (guard) | net flipped rows, n=12 | 6 | **7 (+1)** | [−1, +4] | in band |
| `thin-registration` | net flipped rows, n=14 | 7 | **9 (+2)** | [+2, +6] | **in band, REVERTED — see below** |
| `diagnostic-class` | net flipped rows, n=14 | 7 | **7 (+0)** | [+2, +6] | **REJECT — reverted** |
| `subsystem-directory` | net flipped rows, n=14 | 4 | **4 (+0)** | [+3, +8] | **REJECT — reverted** |

Each bucket was measured immediately after its own commit and again at the round's head, so a later
change cannot mask an earlier one. That ordering earned its keep: while the name-coverage floor was
in the tree it cost `vendored-asset` one gold row (7 → 6 in top-5) and cost `subsystem-directory` two
rows at DEPTH 10 (50.0% → 35.7% strict r@10) while leaving that bucket's registered top-5 rate
untouched. Both are displacement, both were visible only because the intermediate measurement was
taken, and both are gone with the revert.

**A band met is not a change shipped.** `thin-registration`'s +2 sat inside its band with every
simultaneous floor green, and the code still came out, because the gate suite found a displacement
the slice's 54 labels could not see. On `test/packtaskcheck.sh`'s fixture the floor lifts SEVEN
symbols — one real hit and six leaf functions named `decoyBudgetOne`…`Six` — because each of their
names covers two of that query's four content words; a genuinely relevant symbol is pushed out of the
anchor set by the six decoys, and the 1-hop caller the gate exists to assert disappears with it. Half
of four words is two words, and two shared subtokens is coincidence-level evidence — the same
strength an earlier round in this project was rejected twice for trusting. It is not a fixture that
happens to collide with a sound rule: **both** of the flipped label rows are themselves 2-of-4
coverage, so the measured win rests on exactly the strength the gate caught misfiring. Tightening the
rule and measuring again is a second measurement against a band that allows one, so the honest move
is the revert and the negative on record. A future round re-registers this mechanism with
displacement as a NAMED guard rather than something the gate suite has to catch.

**The overlap decomposition the registration demands** was computed while the change was in the tree,
and it acquits the mechanism on that axis at least: of the two `thin-registration` flips, exactly
**one** was a `lib/ids/` row and one was not (a django app-config class under `contrib/admin/`). The
gain was therefore not a directory effect wearing two hats — which the `subsystem-directory` result
independently confirms, since the directory mechanism was measured separately and moved that bucket's
registered metric by zero.

**One correction to the registration's own feasibility audit, in the direction that matters.** The
audit bounded the name-coverage shape at +2 by measuring coverage against each gold's FILE BASENAME.
The rule as built reads SYMBOL names, and a file's best-covering symbol is not always named after the
file. The realized ceiling was therefore higher than the registered proxy — the audit was
conservative in the direction that could only have produced a false REJECT, never a false ACCEPT.

**Both outright rejections are mechanism-level, not constant-level**, and each was swept across its
whole knob range before the code came out — a rejected fix that was merely mistuned would be worth
retrying, and neither of these is:

| Rejected mechanism | Knob swept | Best `strict r@5` for its own bucket | Band |
| --- | --- | --- | ---: |
| short-document floor on BM25 length normalization | 0 / 25 / 50 / 75 / 100 percent of average document length | **7/14 at every setting** | [+2, +6] |
| directory-component lexical field | weight 1 / 2 / 3 on the field scale | 4/14 at weight 1, **5/14 at weights 2 and 3** | [+3, +8] |

The short-document floor is the more interesting negative, because it also refutes the mechanism the
registration corrected TO. The displacing diagnostics are not short documents relative to their
corpus: a fifteen-line constructor sits at or above the average symbol's weighted length on a
JavaScript tree full of one-line arrow functions, so a floor expressed as a fraction of that average
cannot reach them at any setting. What they have is term DENSITY at ordinary length — the failure
recited in the query's own words — and neither of the two shapes proposed for this bucket addresses
that. A future round would have to register density, not length and not name-only matching.

The directory field reached +1 at weights 2 and 3 and moved OTHER buckets up at weight 3. Shipping it
on that basis would be choosing the metric after seeing the result, which the decision rule forbids;
the negative stands, and its knob is not retained — a reverted mechanism should not leave scaffolding
that reads like a shipped feature.

**Guard readout at the round's head** — every floor green, and every one of them byte-identical to
its value at the base, because the one shipped change cannot fire on a tree that contains none of the
paths it names:

| Guard | Floor / ceiling | At `4692076` | At the round's head |
| --- | ---: | ---: | ---: |
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 93/152 | 98/152 / 93/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 | 88.1% / 0.643 |
| LIVE-corpus pollution@5 | ≤ 16% | 2.4% | 2.4% |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 | 71.9% / 0.639 |
| ranking lane / adversarial pollution@5 | ≤ 5% / ≤ 8% | 0.0% / 0.0% | 0.0% / 0.0% |

The per-query comparative diff says the same thing without averaging: base binary against the round's
head, on both frozen corpora, **32 of 32 and 42 of 42 rows byte-identical, zero wins and zero
losses**. That is the honest shape of this round — the change that shipped is a path-tier rule for
paths this repository does not contain, so on this repository it does nothing at all, and the only
instrument that can see it is the external slice it was registered against.

**Standing constraint, still not discharged.** The full-path field's default remains 0 and its earlier
held-out registration is untouched. The directory-component field that would have engaged it was
rejected on its own band and removed, so nothing here moves that question either way.

---

### Query-term density weighting — `diagnostic-class` retry, PRE-REGISTERED 2026-08-22 (before any fix code)

**What this registers.** One mechanism, one bucket, one band. The `diagnostic-class` bucket registered
above has now been read two ways and refuted twice: it is **not** name-only matching (the displacing
diagnostics carry real body evidence — a diagnostic's constructor recites the failure in the reader's
vocabulary), and it is **not** short documents (a fifteen-line constructor sits at or above the average
symbol's weighted length on a JavaScript tree full of one-line arrow functions, so a floor expressed as
a fraction of that average could not reach them at any setting in a full knob sweep). The surviving
reading, named in that round's own negative, is **term density at ordinary length**. This registers it
as a testable rule before any code exists.

**The mechanism, stated so it can be wrong.** BM25 already discounts long documents, but it discounts
the *score*, not the *term*. At `k1 = 1.5`, `b = 0.75` and a document of average weighted length, a term
occurring ONCE receives `2.5 × 1 / (1 + 1.5) = 1.00` of the `k1 + 1 = 2.5` asymptote — **40% of what a
fully saturated term ever receives**. A term occurring eight times receives `2.105`, 84% of the
asymptote. So one mention is worth 0.475 of one subject, and **four mentions beat one subject 1.9 : 1**.
A diagnostic class is exactly a document that mentions four or five of a natural-language query's words
once each — in its message string, its doc comment, and often a documentation URL — while the
implementation carries one or two of them at implementation density and nothing else. The claim under
test: *a query term's contribution should be scaled by the share of the document that term actually
occupies, so that a mention is priced below a subject.*

**The rule.** Inside `src/lexical.h`'s conceptual BM25 (`lexicalScoresTiered`), per query-term
contribution, both scoring branches identically:

```
rho   = tf / dl                                        # this term's share of the document's weighted mass
ramp  = min( 1, rho / ( kDensityRefTf / avgdl ) )
dfac  = kDensityFloor + ( 1 - kDensityFloor ) * ramp    # in [kDensityFloor, 1] — shrink-only
sc   += idf * dfac * tf(k1+1) / ( tf + k1(1-b+b*dl/avgdl) )
```

Three properties are structural, not asserted: `dfac ≤ 1` always, so the MaxScore impact bound (derived
at `tf ≤ T`, `dl ≥ 0`) stays a valid upper bound and the pruned and exhaustive branches stay
byte-identical; `tf > 0 ⇒ dl ≥ tf ≥ 1`, so the ratio is always defined; and `tf`/`dl` are the same
integers on the persisted-stats path and the scan path, so postings parity and the cache format are
untouched. The name-exact ranker (`lexicalScoresNameExactTiered`) is a separate entry point and is **not
touched** — the routing floors below therefore cannot move through this rule's own code.

**Both constants are derived from BM25's own algebra, and neither is tuned against the slice.**

| Constant | Value | Derivation |
| --- | ---: | --- |
| `kDensityRefTf` | **8** | The weighted term frequency at which BM25's own saturation curve reaches 84% of its asymptote at `dl = avgdl` — the count past which further occurrences buy almost nothing, i.e. where BM25 already treats the term as the document's subject. Full density weight is granted exactly there. Expressed as `kDensityRefTf / avgdl`, so the reference is corpus-relative, never a magic absolute density. |
| `kDensityFloor` | **50%** | How far a density judgement may go. A mention is already worth only 0.475 of a subject; the floor halves that at worst and no term ever loses more than half its evidence. Evidence is **reduced, never deleted** — the recorded lesson of the filler-strip and IDF-floor negatives in §7, both of which removed query evidence and cut both ways. |

**Baseline, re-derived in this round before any fix code existed.** Plain dev build, `--top-k=10`, two
full runs byte-identical, zero skipped labels, both corpora verified against `bench/recalleval/
extcorpus.lock` on commit **and** tree hash and both `git status`-clean:

| Bucket | n | gold in top-5 | strict r@1 | strict r@5 | strict r@10 | lenient r@5 | strict MRR |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `diagnostic-class` | 14 | **7 / 14** | 21.4% | 50.0% | 57.1% | 57.1% | 0.332 |
| `thin-registration` | 14 | 7 / 14 | 42.9% | 50.0% | 64.3% | 50.0% | 0.486 |
| `subsystem-directory` | 14 | 4 / 14 | 7.1% | 28.6% | 50.0% | 35.7% | 0.159 |
| `vendored-asset` | 12 | 7 / 12 | 16.7% | 58.3% | 58.3% | 66.7% | 0.336 |

Per corpus: `diagnostic-class` 6 django rows at 66.7% strict r@5 against 8 webpack rows at 37.5%. The
bucket's baseline is **identical to the digit** to the one the bands were drawn against; `vendored-asset`
is the only row that moved, and it moved because the path-tier rule registered above shipped. **The
registered band therefore stands unchanged at [+2, +6] net flipped rows**, and no edge is re-cut.

**A pre-code feasibility audit, because this shape can be bounded from above without running it.**
A shrink-only factor that is non-increasing in density can lift a gold past an occupant only if the gold
is strictly *less* dense than that occupant, and only by at most `1 / kDensityFloor = 2.00×`. Both
conditions are measurable on the frozen labels against the base binary, before the rule exists. Measured
over the seven `diagnostic-class` rows whose primary gold is outside the top-5, comparing each gold's
best-scoring symbol against the fifth-ranked occupant it must pass:

| Row | Gold density | 5th-place density | Direction | Score ratio needed | Reachable at floor 50% |
| --- | ---: | ---: | --- | ---: | --- |
| a cache backend storing a value with a timeout | 0.191 | 0.244 | gold sparser | **1.05×** | **yes** |
| an emitted asset checked against a size budget | 0.100 | 0.167 | gold sparser | **1.05×** | **yes** |
| scope hoisting deciding a module cannot be concatenated | 0.096 | 0.216 | gold sparser | **1.68×** | **yes** |
| tree shaking marking exports as unused | 0.110 | 0.113 | gold sparser | 2.14× | no |
| compile-time constants substituted into module source | 0.021 | 0.075 | gold sparser | 2.91× | no |
| email messages assembled before being sent | 0.082 | 0.062 | **gold denser — inverts** | — | no |
| a splitChunks bug producing an empty chunk | 0.330 | 0.133 | **gold denser — inverts** | — | no |

**Ceiling: +3, against a band of [+2, +6].** That is registered here, before the code, so that a result
of +4 or higher would read as a mechanism this audit mismodelled rather than as a well-chosen constant
found afterwards — and so that a result of +0 or +1 reads as the mechanism failing on rows the audit said
it should reach. Two rows invert: on those the gold is the *densest* thing in its own neighbourhood and
this rule can only hurt them, which is stated now rather than discovered later. The audit's proxy is the
gold's best-scoring symbol, which is the same conservative direction the previous round's audit erred in.

**Correction to the rule block above, before any measurement.** The registration as first written was
internally inconsistent: its feasibility audit measured a factor **non-increasing** in density (penalize
the document that is mostly query terms) while its rule block spelled a factor **non-decreasing** in
per-term density (reward the term that is a large share of its document). Those are opposite rules, and
only one of them is the reading the earlier negative named. The two were separated by measuring both
trigger conditions on the frozen labels, against the base binary, before either was built — over the
seven `diagnostic-class` rows whose primary gold is outside the top-5, comparing the gold's
best-scoring symbol against each of the five occupants it must pass:

| Candidate reading | Favours the gold in |
| --- | ---: |
| **document** query-term density, `Σ tf / dl`, factor non-increasing | **24 of 35** occupant-comparisons |
| **peak per-term** density, `max_u tf_u / dl`, factor non-decreasing | 12 of 35 occupant-comparisons |

The per-term reading is the minority direction and is **refuted here, before code**: an offender reaches
a document density comparable to the gold's by summing four or five terms it mentions once each, and its
peak per-term density is therefore *lower* than the gold's, not higher — so rewarding peak per-term
density lifts the offenders this bucket is about. The rule below is the document-level, non-increasing
one, which is what the audit measures and what the earlier negative named. Nothing about the band, the
baseline or the guards moves with this correction, and no result had been taken when it was made.

**The rule, corrected.** Inside `src/lexical.h`'s conceptual BM25 (`lexicalScoresTiered`), applied to the
document's assembled score in both scoring branches identically, exactly where the Section down-weight
and the fixture/generated-path tier multiplier already sit:

```
D     = ( sum over query terms of tf ) / dl      # share of the document that IS query text
dfac  = kDensityFloor + ( 1 - kDensityFloor ) * min( 1, kDensityCap / D )
sc   *= dfac                                     # in [kDensityFloor, 1] — shrink-only
```

Three properties are structural, not asserted: `dfac ≤ 1` always, so the MaxScore impact bound (derived
at `tf ≤ T`, `dl ≥ 0`) stays a valid upper bound and the pruned and exhaustive branches stay
byte-identical; `tf > 0 ⇒ dl ≥ tf ≥ 1` (a scanned token increments both), so `D` is defined and finite
wherever it is applied; and `tf`/`dl` are the same integers on the persisted-stats path and the scan
path, so postings parity and the cache format are untouched. The name-exact ranker
(`lexicalScoresNameExactTiered`) is a separate entry point and is **not** touched.

**Both constants are derived from BM25's own algebra at this file's `k1 = 1.5`, `b = 0.75`, and neither
is tuned against the slice.**

| Constant | Value | Derivation |
| --- | ---: | --- |
| `kDensityCapPercent` | **10%** | A document's weighted mass is name ×3 + callee ×1 + doc ×2 + body ×1. A symbol whose NAME is entirely query terms already contributes 3 × \|name\| ≈ 6–12 weighted units of query mass; for the query to stay under a tenth of the whole document that symbol must carry roughly 60–120 further weighted units — a signature plus a handful of statements, which any real implementation has and a name-plus-one-sentence document does not. Above a tenth, the document is largely a restatement of the query. |
| `kDensityFloorPercent` | **25%** | How much authority a density judgement may have. `1 / 0.25 = 4×` is exactly the factor `b = 0.75` already grants an empty document over an average one (`1 / (1 − b) = 4`), so the rule's maximum authority is the maximum authority BM25's own length normalization already hands a short document — and no more. A document keeps a quarter of its evidence however much of it is query text: evidence is **reduced, never deleted**, the recorded lesson of the two §7 negatives for this bucket family that removed query evidence outright. |

**The corrected ceiling, and it is tight.** For a factor of this shape the best a gold with density `Dg`
can do against an occupant with density `Do > Dg` is `1 / ( f + (1−f)·Dg/Do )`, maximised over any choice
of cap; below, that bound is evaluated per row at `f = 0.25` alongside the score ratio the row actually
needs, and again at the registered cap of 10%:

| Row | Gold `D` | 5th-place `D` | Needs | Bound at any cap | At cap 10% | Reachable |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| a cache backend storing a value with a timeout | 0.191 | 0.244 | **1.05×** | 1.16× | **1.15×** | **yes** |
| an emitted asset checked against a size budget | 0.100 | 0.167 | **1.05×** | 1.35× | **1.43×** | **yes** |
| scope hoisting deciding a module cannot be concatenated | 0.096 | 0.216 | 1.68× | 1.72× | 1.675× | **borderline — 0.3% short at the registered cap** |
| tree shaking marking exports as unused | 0.110 | 0.113 | 2.14× | 1.01× | 1.02× | no |
| compile-time constants substituted into module source | 0.021 | 0.075 | 2.91× | 1.88× | 1.00× | no |
| email messages assembled before being sent | 0.082 | 0.062 | — | gold is DENSER — the rule inverts | | no |
| a splitChunks bug producing an empty chunk | 0.330 | 0.133 | — | gold is DENSER — the rule inverts | | no |

**Ceiling: +2, or +3 if the borderline row lands — against a band whose lower edge is +2.** This
supersedes the +3 stated above, which bounded each row by the floor's reciprocal alone and ignored that
the gold is penalised too whenever its own density clears the cap. The corrected ceiling is
registered here, before the code, and it is the least comfortable thing in this document: an in-band
result requires the ceiling to be reached with **zero net displacement**, and a result of +0 or +1 is
the outcome the arithmetic says is more likely. It is registered anyway rather than abandoned because
the two rows the bound clears comfortably are real and the mechanism is the last of the three readings
this bucket has left; a refutation at +0 or +1 closes the bucket rather than leaving it open on a shape
nobody costed. Two rows invert outright — on those the gold is the densest document in its own
neighbourhood and the rule can only hurt them, which is stated now rather than discovered later.

The bound is conservative in exactly one direction, the same one the previous round's audit was: its
proxy is the gold file's **best-scoring symbol**, and the rule can change WHICH symbol of that file
scores best. So a realized result above the ceiling is possible and would mean the proxy was loose, not
that a constant was chosen after the fact. A realized result at or below +1 is the mechanism failing on
rows the audit says it should reach.

**Displacement is a first-class registered guard this time, not something the gate suite has to find.**
The previous round's band-met revert was caused by a displacement its 54 labels could not see. So:

| Registered guard | Bar |
| --- | ---: |
| **Band metric** — `diagnostic-class` net flipped rows, gold in top-5, n=14 | **[+2, +6]** |
| **Displacement, other three buckets** — combined gold-in-top-5 count, n=40 | may **not fall at all** |
| **Displacement, depth** — each of the four buckets' strict r@10 | may not fall by more than one row |
| `test/packtaskcheck.sh` and its decoy population | rc=0, no arm red |

**Standing floors, all re-derived in this round at `d7061e2` and all of them re-run after the change:**

| Guard | Floor / ceiling | Measured at `d7061e2` | Headroom |
| --- | ---: | ---: | --- |
| skill routing split=test `bm25-desc` hit@1 | ≥ 60.0% | 73.1% | 13.1pp |
| skill routing split=test `bm25-desc` sep-auc | ≥ 0.89 | 0.957 | 0.067 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 | wide |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 | wide |
| recall lane lenient recall@5 | ≥ 71% | 88.1% | 17.1pp |
| recall lane lenient MRR | ≥ 0.57 | 0.643 | 0.073 |
| LIVE-corpus pollution@5 | ≤ 16% | 2.4% | 13.6pp |
| **ranking lane lenient recall@5** | **≥ 70%** | **71.9%** | **1.9pp — the tightest floor on the board** |
| ranking lane lenient MRR | ≥ 0.55 | 0.639 | 0.089 |
| ranking lane / adversarial-class pollution@5 | ≤ 5% / ≤ 8% | 0.0% / 0.0% | full |
| name-exact route recall@1 | unmoved | asserted by `test/routecheck.sh` in the suite | — |

Frozen corpora at the measurement: docs `commit=7a7f79892034 files=113`, source `commit=7a3194b51ac6
files=1422`. Unlike the four buckets above, **this rule is a global change to the conceptual BM25 that
every in-tree lane runs**, so the ranking lane's 1.9pp is not a formality here: it is under two labels of
margin on a 32-label lane and it is the floor this mechanism is most likely to be bought past. Buying it
is a REJECT, not a trade. The per-query comparative diff (`bench/recalleval/run_r3diff.py`, base binary
against the candidate, both frozen sets) is reported whatever the aggregate does, because an aggregate
that holds while rows churn underneath it is the failure the diff exists to expose.

Standing requirements, not part of any band: `python3 test/pargates.py . ./build/ripwire -j 6` rc=0 ·
ASan/LSan clean under the committed suppressions · two runs of the slice and of both lanes
byte-identical · pruned and exhaustive scoring byte-identical · `--quality-delta` with zero unacked
regressions · `bash test/ripwirepubliccheck.sh` clean.

#### Decision rule

In band **and** every guard above green → keep. Out of band on either edge, or any floor breached, or any
displacement guard tripped → **revert the rule**, keep this registration and the negative on record, and
remove the gate written for it since it would no longer describe shipped behaviour. **One measurement,
one attempt**: the constants are frozen above and a knob sweep, if one is run, is a diagnostic that
establishes whether a rejected mechanism is dead or merely mistuned — no verdict may be taken from it.

#### Limits carried into this attempt

- **The same two repositories and two languages** as the slice above, with the same 14-row bucket. A ±1
  row is inside this instrument's noise, which is why the band's lower edge is +2.
- **The audit's ceiling of +3 is an upper bound on flips, not a prediction of the net.** Displacement can
  subtract from it, and the two inverting rows are where it would come from.
- **This rule cannot be measured on this repository's own populations.** The in-tree lanes carry no
  diagnostic-class population; they are here as floors, and any movement on them is a cost, never a win
  to bank.

#### Result — measured 2026-08-22, one measurement, against the band above

**REJECT, reverted.** The band is missed, both displacement guards are tripped, and the change is out
of the tree. The registration above is unchanged: nothing here re-cuts a band, adds a label, or re-reads
an edge.

| Registered metric | Baseline | Measured | Band / bar | Verdict |
| --- | ---: | ---: | --- | --- |
| `diagnostic-class` net flipped rows, gold in top-5, n=14 | 7 | **8 (+1)** | [+2, +6] | **out of band** |
| Displacement — other three buckets, combined gold in top-5, n=40 | 18 | **17 (−1)** | may not fall | **tripped** |
| Displacement — `thin-registration` strict r@10 | 9 | **6 (−3)** | −1 row at most | **tripped** |
| Displacement — `subsystem-directory` / `vendored-asset` / `diagnostic-class` strict r@10 | 7 / 7 / 8 | 6 / 8 / 10 | −1 row at most | in bar |

**The audit predicted the outcome row for row, which is the useful part.** The two rows that flipped IN
are exactly the two the pre-code table cleared comfortably — the cache backend storing a value with a
timeout (rank 9 → 2) and the emitted asset checked against a size budget (unranked → 2). The one row
that flipped OUT is from the inverting class the audit named: a package `sideEffects` flag applied to a
module (5 → 9), whose gold is the densest document in its own neighbourhood, so a rule that prices
density can only cost it. The borderline row the audit put 0.3% short did not land, and neither
unreachable row moved. **+2 where predicted, −1 where predicted, net +1 against a lower edge of +2.**

**The displacement guards are the part that worked, and they are worth naming row by row.** They were
registered as first-class bars in this round precisely because the previous round's band-met revert was
caught by a gate fixture rather than by the slice; here they fired on the slice itself, before any gate
ran. `thin-registration` is where the cost landed:

| Displaced row | Base | With the rule |
| --- | ---: | ---: |
| `where is the staticfiles application config defined` | **1** | unranked |
| `which command prints only the settings that differ from the defaults` | 6 | unranked |
| `which plugin gives chunks readable names as their ids` | 7 | unranked |
| `which command sends a test email to verify the mail configuration` | **1** | 5 |

Three rows off depth 10 and one gold lost from the top 5, from a bucket the change was not aimed at —
and the first of them was a rank-1 answer. `subsystem-directory` and `vendored-asset` each churned two
rows out and two rows in for a net of zero, which the combined-count bar cannot see and which is why the
per-bucket depth bar was registered alongside it. A registration that had measured only its own bucket
would have reported +1 and stopped; these bars are what turn that into a documented cost.

**The mechanism is dead, not mistuned.** Swept across the whole authority range after the verdict was
taken — a diagnostic, and no verdict is drawn from it:

| `RIPWIRE_TERMDENSITY_FLOOR` | 0 | 10 | 25 (shipped default) | 50 | 75 | 100 (rule off) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `diagnostic-class` strict r@5 | 8/14 | 8/14 | **8/14** | 8/14 | 8/14 | 7/14 |

At floor 0 the factor is unbounded — a document may lose all but an arbitrarily small share of its
evidence — and the bucket still reads 8/14. There is no setting of this knob at which the mechanism buys
its band, so a future round should not retry it at a different constant.

**The standing floors held, and that is not the same as the change being harmless:**

| Guard | Floor / ceiling | At `d7061e2` | With the rule in |
| --- | ---: | ---: | ---: |
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 | 98/152 / **91/152** |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 | 88.1% / **0.627** |
| LIVE-corpus pollution@5 | ≤ 16% | 2.4% | 2.4% |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 | 71.9% / **0.586** |
| ranking lane strict recall@1 | not a floor | 53.1% | **43.8%** |
| ranking lane / adversarial pollution@5 | ≤ 5% / ≤ 8% | 0.0% / 0.0% | 0.0% / 0.0% |

Every registered floor is green — the tightest one, the ranking lane's lenient recall@5, did not move
at all. **Read alone that table would have licensed the change.** The per-query diff says otherwise:
against the base binary on the frozen ranking corpus, `scored=32 wins=4 losses=4 net=+0 ties=24` — an
aggregate that holds while a quarter of the rows churn underneath it, including one row lost outright
and three rows displaced off rank 1. That is precisely the failure the diff is registered to expose, and
it is why the ranking lane's strict recall@1 fell nine points while its lenient recall@5 did not move.
The frozen docs corpus reads `scored=42 wins=3 losses=2 net=+1 ties=37`.

**The gate suite is what makes this REJECT unarguable.** With the rule in the tree,
`python3 test/pargates.py . ./build/ripwire -j 6` reported **`gates=455 pass=440 skip=3 fail=12`** —
eleven substantive failures plus the known warm-timing flake. `routecheck.sh` and `anchorcheck.sh` drift
from their golden `--for` outputs; `recallanchorcheck.sh` selects a different body anchor (`1-15` where
the ground truth is `5-8`); `retrievalqualitycheck.sh` reports its explicit-query/denylist policy
regressed; and `adaptivecheck`, `modifierguardcheck`, `fornotesbudgetcheck`, `packtaskmonotoncheck`,
`cochangeboostcheck` and `sibliftcheck` each move. A global multiplier on the conceptual BM25 reaches
every verb that ranks anything, and eleven gates is the honest measure of that reach — a scale of
disturbance the four bucket rates and the eight standing floors together did not show.

**What is now closed for this bucket.** All three readings it has been given are refuted with the
evidence to keep them refuted: it is not name-only matching (the displacing diagnostics carry real body
evidence), it is not short documents (they are not short, and the length floor was swept to zero effect),
and it is not term density in either direction (per-term density points at the offenders and was refuted
before code; document density buys exactly +2 and gives back −1 to its own inverting class, at every
setting of its own knob). What actually separates a diagnostic from its implementation on these rows is
visible in the anatomy and is not a density: the diagnostic's document contains the question's function
words and its documentation URL, so it matches MORE DISTINCT query terms than the implementation does,
and each of those matches is a hapax that BM25 already pays 40% of a saturated term for. Acting on that
observation means pricing hapax coordination or filtering query function words — and the function-word
strip is one of the two negatives recorded in §7 for exactly this family. **A fourth attempt on this
bucket needs a new mechanism, not a new constant, and this round did not find one.**

The gate written for the rule (`test/termdensitycheck.sh`) came out with it, since it no longer describes
shipped behaviour; the gate count returns to 446. The rule's commit and this revert are both kept on
record rather than rebased away: a negative is only reproducible while the code that produced it is still
readable.

### Definition-over-declaration tiebreak on the name-exact route — PRE-REGISTERED 2026-08-24 (before any fix code)

**What this registers.** One mechanism, one route, one band. The E6 demotion-corpus work closed with a
single named, mechanically-understood defect and an armed kill tripwire for it: **name-exact BM25 has no
definition-over-declaration tiebreak**. A bare `class X;` forward declaration and the real `class X { … }`
definition are, to whole-name BM25, the *same document* — one token, equal to the query. They therefore
score bit-for-bit identically, the tie breaks on symbol id (crawl/path order), and a corpus that forward-
declares a type in eighty-five headers spends every ranked row and every body slot on eighty-five copies
of the name the caller already typed. The agent is sent to a signature when the body exists elsewhere in
the same tree. This registers the fix as a testable rule before any code exists.

**The mechanism, stated so it can be wrong.** The claim under test is *not* that declarations are
worthless — a query that asks for forward declarations must still get them, and the kill tripwire below
exists to hold that. The claim is narrower: **when two candidates are exactly as name-exact as each
other, the one that carries a body is the better answer.** If that is false, the change will show up as
displacement on the frozen ranking/recall lanes, or as a routing-floor regression, and is reverted.

**The rule.** On the **name-exact route only**, after `lexicalScoresNameExactTiered` has produced its
score vector and before any anchor / mention / co-change reshaping:

```
for each EXACT-tie group of equal scores v > 0 that contains BOTH a body-carrying symbol
    and a bodyless one (the house predicate, graph.h / arch.h: endByte > sigEndByte):
        vLow = nextafter( v, 0 )
        if vLow is already an occupied score anywhere in the vector:  skip this group   # refuse
        else: every bodyless member of the group takes vLow;  body-carrying members keep v
```

Four properties are structural, not asserted, and each is why this is a **tiebreak and not a score
change**: (i) only members of an *exact* tie are touched, so no two rows that were already ordered by
score can swap; (ii) the demoted value is the immediate float predecessor, so nothing can land *between*
it and the group it left, and the refusal clause means it can never land *on* an occupied value — the
post-state's distinct-value set is the pre-state's plus injectively-new values; (iii) demotion only fires
in **mixed** groups, in which a body-carrying member retains `v`, so `max(rank)` is invariant and the R4
weak-evidence honesty signal (`kWeakLexicalScoreThreshold`) cannot move; (iv) within each side of the
split the id-ascending order is untouched, so the net effect is exactly a stable partition of the tie
group. The subtoken+body ranker (`lexicalScoresTiered`) is a separate entry point and is **not touched**,
so no conceptual query can move through this rule's code at all.

**The registered invariance criterion, which outranks the band.** *Order among non-tied rows must be
byte-identical.* Registered as a first-class bar, not a hope: the controls below are byte-compared, and a
single differing byte on a conceptual route or a no-tie name-exact route is a REVERT regardless of the
primary metric.

**The probe set, and how it was chosen — mechanically, to make cherry-picking impossible.** The E6
corpus's class-2b rows are pinned by SHA, but only some are name-bearing; the conceptual ones (`G18`,
`G20`) route subtoken+body and this rule is deliberately blind to them, so they serve here as *negative*
controls rather than as scored rows. `Q27` (memgraph) is **excluded and disclosed**: its query text is
not recorded verbatim anywhere in the E6 ledger and is therefore not replayable. The scored set is:

* **(P-a)** every name-bearing 2b query recorded verbatim in the E6/growth/D4 ledgers whose corpus is
  re-clonable at its pinned SHA — `ClientContext` (H18), `DatabaseInstance` (H31), `Serializer` (H20),
  `ColumnFamilyData` (H22);
* **(P-b)** a mechanical extension with no human choice in it: for each corpus, the class names with the
  most **bare** forward declarations (lines matching `^\s*class\s+NAME\s*;\s*$` under `*.h *.hpp *.cc
  *.cpp`), taken in count-descending then name-ascending order, top three per corpus, minus any name
  already in (P-a). ugrep offers only two such names and contributes both.

Corpora re-cloned blob-filtered (`git clone` with a `blob:none` filter, the D4 freeze's own recipe) at
the D4-pinned SHAs and **verified by revision count against the D4 freeze**: duckdb `19864453` (48632 revs), rocksdb `0e2801ac` (12938), ugrep `550599a6` (985) — all
three match to the digit. The forward-declaration census reproduces the D4 report exactly (ClientContext
85, DatabaseInstance 38, Serializer 24), and every gold resolves to a unique definition site identical to
the one the ledger names.

| id | corpus | `--for=` | gold definition | in E6 |
| --- | --- | --- | --- | --- |
| N01 | DD | `ClientContext` | `src/include/duckdb/main/client_context.hpp:65` | H18 (CLEAN) |
| N02 | DD | `DatabaseInstance` | `src/include/duckdb/main/database.hpp:40` | H31 (CLEAN) |
| N03 | DD | `Serializer` | `src/include/duckdb/common/serializer/serializer.hpp:35` | H20 (AMBIGUOUS) |
| N04 | DD | `TableCatalogEntry` | `…/catalog/catalog_entry/table_catalog_entry.hpp:50` | new (P-b) |
| N05 | DD | `Deserializer` | `…/common/serializer/deserializer.hpp:22` | new (P-b) |
| N06 | DD | `Catalog` | `src/include/duckdb/catalog/catalog.hpp:75` | new (P-b) |
| N07 | RD | `ColumnFamilyData` | `db/column_family.h:294` | H22 (AMBIGUOUS) |
| N08 | RD | `Slice` | `include/rocksdb/slice.h:32` | new (P-b) |
| N09 | RD | `SystemClock` | `include/rocksdb/system_clock.h:30` | new (P-b) |
| N10 | RD | `Logger` | `include/rocksdb/env.h:1217` | new (P-b) |
| N11 | UG | `dos_streambuf` | `include/reflex/input.h:865` or `:1120` | G18 lineage, name form |
| N12 | UG | `streambuf` | `include/reflex/input.h:822` or `:1087` | G18 lineage, name form |

**Primary metric.** `SERVED` = the number of probes whose **gold definition is actually emitted** by a
plain `ripwire <corpus> --for="<Name>"` — present in a `<d>` row or in a `<bodies>` slot. That is the
thing the defect costs the agent, so it is the thing measured; the candidates-export rank is reported
alongside as a diagnostic and no verdict is drawn from it.

**Baseline, measured in this lane at `da61bac` before any fix code existed.** All twelve probes route
name-exact (verified per row from the `route=` disclosure), so all twelve are in the rule's scope.

| id | route | gold served | gold rank in `--format=candidates --top-k=500` | rows tied at top | gold tied at top |
| --- | --- | :---: | ---: | ---: | :---: |
| N01 | name-exact | no | 40 | 89 | yes |
| N02 | name-exact | no | 11 | 42 | yes |
| N03 | name-exact | no | 10 | 32 | yes |
| N04 | name-exact | no | 5 | 29 | yes |
| N05 | name-exact | no | 9 | 34 | yes |
| N06 | name-exact | **yes** | 2 | 25 | yes |
| N07 | name-exact | **yes** | 3 | 14 | yes |
| N08 | name-exact | no | 29 | 7 | **no** |
| N09 | name-exact | no | 19 | 31 | yes |
| N10 | name-exact | no | 13 | 4 | **no** |
| N11 | name-exact | no | absent from top-500 | 5 | **no** |
| N12 | name-exact | no | absent from top-500 | 2 | **no** |

**`SERVED` baseline = 2 / 12.**

**A pre-code feasibility ceiling, because this shape can be bounded from above before it is built.**
A tiebreak can only move a row that is *in* a tie. Eight of the twelve golds share the top score exactly
(N01–N07, N09); two of those eight are already served (N06, N07). **The rule can therefore flip at most
six rows, and `SERVED` can reach at most 8 / 12.** The four unreachable rows are named now rather than
explained afterwards: `Slice` and `Logger` have golds that score strictly *below* their top group (a
scoped `Slice::Slice` / `Logger::Logger` member matches the query's whole name twice), and ugrep's two
nested `BufferedInput::streambuf` definitions do not rank in the top 500 at all — a separate defect
(qualified out-of-class nested definitions) this rule neither addresses nor is credited for.

**Registered band: `SERVED` ≥ 6 / 12, i.e. `[+4, +6]` against the baseline of 2** — three units wide,
with its upper edge at the audited ceiling. Below `+4` is a REJECT and the code is reverted. A result of
`+5` or `+6` is the mechanism working as modelled; `+4` is the floor at which it is worth its risk. A
result **above** `+6` would mean the audit mismodelled the mechanism and the change must be re-read
before it may ship, not celebrated.

**Registered controls — byte-compared, base vs head, and any difference is a REVERT.**

| control | command | why |
| --- | --- | --- |
| **C13** (the armed kill tripwire) | UG `--for="forward declared nested stream buffer classes"` | growth's class-2b kill control: a query that explicitly asks for forward declarations must keep them in its body slots. The rule is route-scoped precisely so this cannot move. |
| G18 | UG `--for="dos line ending stream buffer for buffered input"` | the CLEAN 2b row on the conceptual route — must not move |
| G20 | UG `--pack-task="implement a new stream buffer over reflex Input" --token-budget=6000` | the body-selector 2b row, conceptual route — must not move |
| H19 | DD `--for="per connection state that holds the active transaction and query"` | H18's conceptual twin over the same gold |
| no-tie name-exact ×2 | this repo, `--for="computeLensRanking"` / `--for="lexicalScoresNameExactTiered"` | name-exact route, no mixed tie — the invariance criterion's own fixture |
| default map | this repo, flagless | the whole-corpus PageRank map takes no lexical score at all |
| conceptual | this repo, `--for="how does the ranker route a query"` | ordinary subtoken+body traffic |

`RD --for="Slice"` is registered as a **mixed control**: its top group is a tie that the rule may legally
reorder while its gold is not in that tie, so it is expected to change *and* to leave `SERVED` untouched.
It is recorded, not byte-pinned.

**Registered guards, re-run after the change; any regression is a REVERT regardless of the band.**
Values are this lane's own measurement at `da61bac`, and every one of them reproduces the last recorded
baseline to the digit — which is the instrument check.

| Guard | Floor / ceiling | At `da61bac` |
| --- | ---: | ---: |
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 |
| LIVE / ranking / adversarial pollution@5 | ≤ 16% / ≤ 5% / ≤ 8% | 2.4% / 0.0% / 0.0% |
| `bench/recalleval/run_r3diff.py` base-vs-head, ranking + recall sets | near-all ties | — |
| determinism (two runs byte-identical) + `xmllint` well-formedness | contract | — |
| full gate battery (`test/regression.sh`) | all green | — |
| G1 — ASan/UBSan/integer/LSan over the new path | no report | — |

The r3diff bar deserves its own sentence, because it is the one that can catch a mis-scoped rule that
every floor above would pass: these frozen sets are natural-language queries that route subtoken+body,
so a **wide** diff is a red flag that the change leaked off the name-exact route, not a win.

**KILL conditions, registered before the result.** Any one of: C13's body slots losing a forward
declaration; any byte-compared control differing; any floor above going red; a non-tied row changing
order on any probe; `SERVED` below `+4`.

#### The result: SHIP, at the audited ceiling

| Registered metric | Baseline | Measured | Band / bar | Verdict |
| --- | ---: | ---: | --- | --- |
| `SERVED` — gold definition emitted, n=12 | 2 / 12 | **8 / 12 (+6)** | [+4, +6] | **in band, at the ceiling** |
| Non-tied order, byte-compared controls (8) | — | **8 / 8 identical** | any difference kills | held |
| `run_r3diff.py`, frozen ranking set | — | **32 ties, 0 wins, 0 losses** | near-all ties | held |
| `run_r3diff.py`, frozen recall set | — | **42 ties, 0 wins, 0 losses** | near-all ties | held |

**The feasibility audit predicted the outcome row for row, which is the useful part.** It named six
reachable rows and four unreachable ones before the code existed. **All six flipped; none of the four
did.** Every flipped row's gold went to `p=1` or `p=2`.

| id | gold rank, base | gold rank, with the rule | served, base → head | audit said |
| --- | ---: | ---: | :---: | --- |
| N01 `ClientContext` | 40 | **1** | no → **yes** | reachable |
| N02 `DatabaseInstance` | 11 | **1** | no → **yes** | reachable |
| N03 `Serializer` | 10 | **1** | no → **yes** | reachable |
| N04 `TableCatalogEntry` | 5 | **2** | no → **yes** | reachable |
| N05 `Deserializer` | 9 | **1** | no → **yes** | reachable |
| N06 `Catalog` | 2 | 2 | yes → yes | already served |
| N07 `ColumnFamilyData` | 3 | 2 | yes → yes | already served |
| N08 `Slice` | 29 | 8 | no → no | **unreachable** — gold below its top group |
| N09 `SystemClock` | 19 | **1** | no → **yes** | reachable |
| N10 `Logger` | 13 | 5 | no → no | **unreachable** — gold below its top group |
| N11 `dos_streambuf` | absent | absent | no → no | **unreachable** — gold unranked at all |
| N12 `streambuf` | absent | absent | no → no | **unreachable** — gold unranked at all |

`Slice` 29 → 8 and `Logger` 13 → 5 are the rule working *around* a gold it cannot lift: bodyless rows
in the tie groups **above** those golds were demoted past them. Neither reaches the emitted bundle, so
neither is counted, and neither is claimed.

**H18, the strongest 2b row in the merged E6 corpus, is closed.** `--for="ClientContext"` on duckdb went
from four ranked rows that were all bare `class ClientContext;` declarations, with the definition absent
from the whole bundle, to the definition at `p=1`. H31 and H22 likewise.

**Where the wins landed, stated exactly, because the metric allowed two places and only one delivered.**
`SERVED` was registered as "in a `<d>` row **or** a `<bodies>` slot". Every one of the six flips landed
in the `<d>` rows; **not one landed in `<bodies>`** — `b=0` on all twelve probes, before and after.

**That is this round's named residual, and it is a second site of the same defect.** The body that rides
on a name-exact `--for` is not chosen from the ranking at all: it comes from the ROUTER's anchor, and
`lexical.h`'s `NameAnchor::fileId` is documented as *"the FIRST definition of this name in NodeId order"* —
path order, so it resolves to a forward declaration for exactly the reason the ranking used to. The D4
report already saw this without naming the mechanism: *"the ANCHOR ripwire chose for the type name is
itself a forward declaration."* **It was not registered this round and is not fixed here.** Extending the
change to reach it after seeing the measurement is precisely what pre-registration exists to prevent, so
it is recorded as the next round's item instead, and `test/defoverdeclcheck.sh` arm (f2) PINS the current
behaviour so that fixing it goes red and is acknowledged rather than absorbed silently.

**Every guard is not merely green but IDENTICAL, to the digit, on both sides.**

| Guard | Floor / ceiling | At `da61bac` | With the rule in |
| --- | ---: | ---: | ---: |
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 | 98/152 / 92/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 | 88.1% / 0.643 |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 | 71.9% / 0.639 |
| LIVE / ranking / adversarial pollution@5 | ≤ 16% / ≤ 5% / ≤ 8% | 2.4% / 0.0% / 0.0% | 2.4% / 0.0% / 0.0% |

Zero displacement is the expected shape here and not a surprise: these lanes' queries are natural
language, they route subtoken+body, and this rule cannot execute on that route. The r3diff readouts say
the same thing per query — 74 of 74 ties across both sets — and the registration flagged in advance that a
WIDE diff would have been the red flag, not a win.

**A measurement error worth recording, because it is the wave's own named failure class.** The first pass
at the byte-compared controls ran the base binary before this lane's commits and the head binary after —
on `.`, this repository, whose tree those commits had changed. Four of nine "differed", including the
flagless map, which consumes no lexical score at all and therefore could not possibly have moved. The
control was backwards: the corpus, not the binary, was the variable. Re-run correctly — the same tree,
two binaries — all nine are byte-identical. The tell was the map: **when a control that the change cannot
reach reports a difference, the control is wrong, not the change.**

`--quality-delta=da61bac..bae00d7` (the ref-pair form, two committed trees): `gating="0"`,
`preexisting-worse="0"`, all twelve rows `origin="new-symbol"` — the new helper and the fixture's own
symbols. Nothing that existed got worse. `applyDefOverDeclTiebreak` measures
`cx=21 ccx=29 loc=91 nest=3`, with `ev=10 ev_why="guard-return:3,loop-escape:4"` — the count is dominated
by early-exit guards and refusals, which is the shape §6's readability work says not to refactor away, and
it sits below both of its immediate neighbours in the same file (`chooseForRanker` 34,
`lexicalScoresNameExactTiered` 61). Left as written, deliberately, rather than split into a single-use
helper to lower a number.

G1: the `asan/` build (ASan + UBSan + integer + LSan with the committed suppressions) runs the new path
clean, exit 0 with empty stderr, on duckdb's `--for="ClientContext"`, the fixture's `--for=Widget` and a
whole-repo map; `test/defoverdeclcheck.sh` passes against `asan/ripwire` as well as `build/ripwire`.

Gate count 451 → **452** (`test/defoverdeclcheck.sh`).

### Definition-over-declaration at the ANCHOR — PRE-REGISTERED 2026-08-25 (before any fix code)

**What this registers.** The named residual of the round immediately above, and nothing else. That round
gave the name-exact ranking a definition-over-declaration tiebreak and moved six golds to `p=1`/`p=2` — but
**every one of those wins landed in a `<d>` row and not one landed in `<bodies>`**, because the body that
rides on a name-exact `--for` is not drawn from the ranking at all. It is drawn from the ROUTER's anchor,
and `lexical.h`'s `NameAnchor::fileId` is *"the FIRST definition of this name in NodeId order"* — path
order, so on a header-heavy C++ tree it resolves to a forward declaration for exactly the reason the
ranking used to. **The same defect at a second site.** This registers the fix for that site before any
code exists.

**The mechanism, stated so it can be wrong.** `buildLowerNameIndex` walks symbols in NodeId order and the
first symbol whose whole lowercased name equals the key claims `fileId`. Every later same-named definition
only increments `extraDefs`. So a bare `class ClientContext;` in `extension/parquet/include/geo_parquet.hpp`
claims the anchor for `ClientContext` on duckdb, and `restrictBodiesToRouteAnchor` — which is *correct*, and
is the T3 substitution round's own fix — then narrows the auto-body candidates to symbols in **that** file.
The definition, ranked first since the round above, is filtered out, and the caller is served the
declaration's own text under the heading of an answer. The claim under test is the same one that round made,
transplanted: **when several definitions share a name, the one that carries a body is the better anchor.**

**The rule.** In `noteWholeNameDef`, using the house bodyless predicate shared with `graph.h`, `arch.h` and
`applyDefOverDeclTiebreak` (`endByte > sigEndByte`):

```
the anchor is claimed by the first BODY-CARRYING definition of the name in NodeId order;
a bodyless definition claims it only while no body-carrying one has been seen;
when a body-carrying definition arrives after a bodyless claim, it TAKES the claim.
If no definition of the name carries a body, the first one keeps it — exactly as today.
```

**Three properties are structural rather than asserted, and they are why this cannot reach the router.**
(i) The rule writes `fileId` and one new private flag and **nothing else**: `wholeName`, `extraDefs` and
`carriers` are untouched, byte for byte. (ii) Every input to the route DECISION is one of those three —
whole-name membership (`wholeName`), the anchor-plausibility bounds (`extraDefs`, `carriers`) and the query
words. **No query can therefore change route, and no plausibility verdict can change,** which is a stronger
statement than "the floors did not move" and is checkable by reading the diff. (iii) Neither lexical scorer
is touched, so the ranked order — every `<d>` row, every `--format=candidates` rank, the prior round's whole
`SERVED` result — is invariant by construction. What may legitimately move is exactly two things: the path
printed in the `anchors:` clause, and which body the T3 allowance serves.

**The probe set is the twelve probes of the round above, frozen and unchanged** (their selection is
recorded there: (P-a) every name-bearing class-2b query recorded verbatim and re-clonable, (P-b) a
mechanical top-three-by-bare-declaration-count extension per corpus). Re-using them rather than choosing
new ones is deliberate — the residual was measured on this set, so the fix is measured on this set.
Corpora re-cloned blob-filtered at the same pinned SHAs and re-verified by revision count: duckdb
`19864453` (48632 revs), rocksdb `0e2801ac` (12938), ugrep `550599a6` (985), all three matching the D4
freeze to the digit, and the duckdb forward-declaration census reproducing it exactly as well
(`ClientContext` 85, `DatabaseInstance` 38, `Serializer` 24).

**Primary metric: `BODY-SERVED`** = of the twelve probes, how many have the **gold definition's own body**
emitted in the `<bodies>` section of a plain `ripwire <corpus> --for="<Name>"`. Not "a body"; not "a body of
something with the right name" — the gold definition's. That is precisely the distinction the T3
substitution round drew and it is the distinction the defect erases.

**Baseline, measured in this lane at `8312d8f` before any fix code existed: `BODY-SERVED` = 0 / 12.** All
twelve route name-exact. Eight of the twelve have the gold in a `<d>` row (the round above's `SERVED` 8/12,
reproduced here to the row) and **none of the eight gets its body**. What the eight get instead is the
finding restated as data:

| id | corpus | `--for=` | anchor at base | body served at base | gold body? |
| --- | --- | --- | --- | --- | :---: |
| N01 | DD | `ClientContext` | `extension/…/geo_parquet.hpp` | `geo_parquet.hpp:77` — a bare declaration | no |
| N02 | DD | `DatabaseInstance` | `…/catalog/catalog.hpp` | `catalog.hpp:57` — a bare declaration | no |
| N03 | DD | `Serializer` | `extension/json/…/json_serializer.hpp` | `json_serializer.hpp:37` — a bare declaration | no |
| N04 | DD | `TableCatalogEntry` | `src/catalog/…/table_catalog_entry.cpp` | `table_catalog_entry.cpp:22` — the out-of-line constructor | no |
| N05 | DD | `Deserializer` | `extension/json/…/json_serialize_sql.cpp` | `json_serialize_sql.cpp:198` | no |
| N06 | DD | `Catalog` | `src/README.md` | none (`bodies="0" reason="no_candidates"`) | no |
| N07 | RD | `ColumnFamilyData` | `db/column_family.cc` | `column_family.cc:526` — the out-of-line constructor | no |
| N08 | RD | `Slice` | `db/blob/blob_fetcher.h` | none (`bodies="0" reason="no_candidates"`) | no |
| N09 | RD | `SystemClock` | `db/blob/blob_file_builder.h` | `blob_file_builder.h:24` — a bare declaration | no |
| N10 | RD | `Logger` | `db/log_reader.h` ‡ | none | no |
| N11 | UG | `dos_streambuf` | `include/reflex/input.h` | five constructor bodies | no |
| N12 | UG | `streambuf` | `include/reflex/input.h` | four constructor bodies | no |

‡ **A correction to this table, made after the fact and marked rather than rewritten.** N10's base-anchor
cell first read `include/rocksdb/env.h`. That was carried over from the reachability reasoning below
instead of read off the run, and it is wrong: the measured base anchor is `db/log_reader.h`, a bare
`class Logger;`. Nothing else moves with it — the row's *served body* (none), its `BODY-SERVED` (no) and
its reachability verdict (reachable, because the claimant is bodyless and the first body-carrying
definition in path order is the gold in `env.h`) are all unchanged, and had the cell been right the first
time the audit would have read the same. It is corrected in place, with this note, because a baseline
table quietly edited after a result is a baseline nobody can trust.

**A pre-code feasibility ceiling, bounded from above before the code exists — the round above's own
discipline, and the part of it that earned its keep.** The rule can only reach a probe when (a) the anchor's
current claimant is bodyless AND a body-carrying same-named definition exists, (b) that first body-carrying
definition in NodeId order IS the gold, and (c) the gold survives the auto-body candidate head, which is the
top `kPackTaskBodyCandidates` = 6 positive-scoring ranks. Audited per probe against the candidates export:

* **Reachable (6): N01, N02, N03, N05, N09, N10.** In each, every same-named symbol sorting before the gold
  by path is a bare declaration, and the gold is at rank 1 (N01, N02, N03, N05, N09) or rank 5 (N10).
* **Unreachable (6), each for a named and different reason.** **N04** and **N07**: the first body-carrying
  definition in NodeId order is the class's own **out-of-line constructor** in the `.cpp`/`.cc`, which sorts
  before the header — the anchor is already body-carrying, so the rule is inert and the bundle must not move.
  **N06**: the claimant is a markdown section (`# Catalog` in `src/README.md`), which carries a body, so it
  keeps the claim and this probe must not move either. **N08**: the anchor does move to `include/rocksdb/slice.h`,
  but the six-candidate head is filled entirely by higher-scoring `Slice.java` rows and the gold sits at rank
  8 — a candidate-head bound, not an anchor bound. **N11**/**N12**: every definition is in one file, so the
  anchor cannot move at all, and the gold (`class Input::dos_streambuf : … {`, a qualified out-of-class
  nested definition) is not extracted as a symbol — the separate extraction gap the round above named and
  disclaimed.

**Registered band: `BODY-SERVED` ≥ 4 / 12, i.e. `[+4, +6]` against the baseline of 0** — three units wide,
upper edge at the audited ceiling. Below `+4` is a REJECT and the code is reverted. **Above `+6` the audit
mismodelled the mechanism and the change must be re-read before it may ship, not celebrated.**

**Registered invariance criterion, which outranks the band, and is (d) of this lane's brief.** *A query
whose name has a UNIQUE definition must produce a byte-identical bundle.* Nothing about such a query can
touch this rule — there is no second claimant — so a single differing byte means the rule is doing something
other than what it says.

**Registered controls — byte-compared, base vs head on the same tree and the same corpus; any difference is
a REVERT.** The first four are the round above's own control set, re-used unchanged; the last three are new
and are the ones this rule could plausibly break.

| control | command | why |
| --- | --- | --- |
| **C13** (the armed kill tripwire) | UG `--for="forward declared nested stream buffer classes"` | a query that explicitly asks for forward declarations must keep them |
| G18 | UG `--for="dos line ending stream buffer for buffered input"` | conceptual route — anchors nothing, so must not move |
| G20 | UG `--pack-task="implement a new stream buffer over reflex Input" --token-budget=6000` | the body-selector row on the conceptual route |
| unique-definition name-exact ×2 | this repo, `--for="computeLensRanking"` / `--for="lexicalScoresNameExactTiered"` | the invariance criterion's own fixture |
| default map + conceptual | this repo, flagless / `--for="how does the ranker route a query"` | surfaces that consume no anchor at all |
| **N04, N07** | DD `--for="TableCatalogEntry"` / RD `--for="ColumnFamilyData"` | **the audit's own prediction, byte-pinned:** a many-definition name whose first claimant already carries a body must not move one byte |
| **N11, N12** | UG `--for="dos_streambuf"` / `--for="streambuf"` | every definition in one file — the anchor is structurally immovable |

`N06` (`Catalog`, the markdown-section claimant) and `N08` (`Slice`, the candidate-head bound) are
**recorded, not byte-pinned**: the audit predicts N06 unchanged and N08 changed in its `anchors:` clause but
not in its zero bodies, and a prediction that names its own uncertainty should not be enforced as a control.

**Registered guards, re-run after the change; any regression is a REVERT regardless of the band.** Every
value below is this lane's own re-measurement at `8312d8f`, and every one reproduces the last recorded
baseline to the digit — that is the instrument check, done before any result was believed.

| Guard | Floor / ceiling | At `8312d8f` |
| --- | ---: | ---: |
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 |
| LIVE / ranking / adversarial pollution@5 | ≤ 16% / ≤ 5% / ≤ 8% | 2.4% / 0.0% / 0.0% |
| `bench/recalleval/run_r3diff.py` base-vs-head, ranking + recall sets | near-all ties | — |
| the round above's `SERVED`, re-measured | **8 / 12, unmoved** | 8 / 12 |
| determinism (two runs byte-identical) + `xmllint` well-formedness | contract | — |
| full gate battery (`test/regression.sh`) | all green | — |
| G1 — ASan/UBSan/integer/LSan over the new path | no report | — |

**The gate arm that is flipped on purpose.** `test/defoverdeclcheck.sh` arm (f2) PINS the pre-fix behaviour —
it asserts the auto-body slot still serves `a_headers.hpp:12`, the declaration, and it fails loudly with
*"the anchor-side defect was fixed; re-register this arm and retire the residual"* the moment it is not.
That is this round, so **arm (f2) is rewritten to pin the new behaviour as part of this registration**,
together with a new fixture name whose declaration and definition are in different files and whose ranked
rows were never the issue. Flipping a tripwire silently is how a green-but-inert gate is born; flipping it
inside the registration that predicted it is the opposite.

**KILL conditions, registered before the result.** Any one of: `BODY-SERVED` below `+4`; any byte-compared
control differing; the round above's `SERVED` moving off 8/12; any floor above going red; a route decision
changing on any probe; a body served that is neither the gold nor what base served.

#### The result: SHIP, at the FLOOR of the band, and the audit missed a bound

| Registered metric | Baseline | Measured | Band / bar | Verdict |
| --- | ---: | ---: | --- | --- |
| `BODY-SERVED` — gold definition's own body emitted, n=12 | 0 / 12 | **4 / 12 (+4)** | [+4, +6] | **in band, at the floor** |
| Byte-compared controls (12: the 8 registered + N04, N07, N11, N12) | — | **12 / 12 identical** | any difference kills | held |
| The round above's `<d>` rows, all twelve probes | — | **12 / 12 byte-identical** | ranked side must not move | held, stronger than registered |
| `run_r3diff.py`, frozen ranking (n=32) + recall (n=42) | — | **74 ties, 0 wins, 0 losses** | near-all ties | held |

**Where the four landed, and where the two that did not went instead.**

| id | corpus | anchor: base → head | body served: base → head | `BODY-SERVED` | audit said |
| --- | --- | --- | --- | :---: | --- |
| N01 | DD | `geo_parquet.hpp` → **`client_context.hpp`** | a declaration's text → **none, `reason="budget"`** | no | reachable — **missed** |
| N02 | DD | `catalog.hpp` → **`database.hpp`** | a declaration's text → **the gold** | **yes** | reachable |
| N03 | DD | `json_serializer.hpp` → **`serializer.hpp`** | a declaration's text → **the gold** | **yes** | reachable |
| N04 | DD | unchanged (`table_catalog_entry.cpp`) | unchanged | no | unreachable — inert branch |
| N05 | DD | `json_serialize_sql.cpp` → **`deserializer.hpp`** | a namesake → **none, `reason="budget"`** | no | reachable — **missed** |
| N06 | DD | unchanged (`src/README.md`) | unchanged (none) | no | unreachable — body-carrying claimant |
| N07 | RD | unchanged (`column_family.cc`) | unchanged | no | unreachable — inert branch |
| N08 | RD | `blob_fetcher.h` → **`slice.h`** | none → none | no | unreachable — candidate-head bound |
| N09 | RD | `blob_file_builder.h` → **`system_clock.h`** | a declaration's text → **the gold** | **yes** | reachable |
| N10 | RD | `log_reader.h` → **`env.h`** | none → **the gold** | **yes** | reachable |
| N11 | UG | unchanged (`input.h`) | unchanged | no | unreachable — one file, extraction gap |
| N12 | UG | unchanged (`input.h`) | unchanged | no | unreachable — one file, extraction gap |

**The anchor moved on all six rows the audit called reachable, and on none of the six it called
unreachable.** The mechanism did exactly what it was registered to do. What the audit got wrong is
narrower and more interesting than a mis-modelled mechanism: **it modelled the anchor and the six-row
candidate head, and forgot the BYTE BUDGET.**

**N01 and N05 are the two misses, and they are the defect's own economics showing up on the other side.**
A bare `class ClientContext;` is one line; `class ClientContext { … }` in duckdb is hundreds. The T3
allowance is whole-body-or-nothing by design (`truncateOversizedFirst=false` — a rank-1 definition larger
than the body budget is DROPPED and disclosed, never cut mid-definition), so the correct answer does not
fit where the wrong one always did. Both rows now emit `bodies="0" reason="budget"` plus the per-item
`<!-- body omitted (over budget): ClientContext -->`. **That is the T3 substitution round's registered
posture reached at last, not a new failure:** its rule was that when the anchor's own body does not fit,
the honest zero is strictly more informative than a smaller namesake's body, "which reads like an answer
and is not one". Before this change those two callers were served a forward declaration's text under the
heading of an answer; now they are told, in the disclosure the header already carries, that the answer
exists and did not fit. It does not count toward the band and it is not claimed as a win — but it is not a
loss either, and pretending the row is unchanged would be the dishonest reading.

**The audit's real lesson, for the next round that bounds itself from above:** a feasibility ceiling on a
BODY metric has three gates, not two — the anchor, the candidate head, and the budget — and this one
audited two. Had it audited three it would have registered a ceiling of `+4` and named N01/N05 in advance,
which is exactly the sharper prediction the discipline is for.

**A registered kill condition that fired on its wording and not on its intent, disclosed rather than
reinterpreted quietly.** The kill list says *"the round above's `SERVED` moving off 8/12"*. Re-measured,
`SERVED` is **9 / 12**: N10 `Logger` gained it. That is a GAIN, and it arrives through `SERVED`'s own
definition — "present in a `<d>` row **or** in a `<bodies>` slot" — whose second clause is precisely this
round's metric, so the two measures overlap and the guard could only ever have been one-sided. The thing
that kill was written to protect is the RANKED side, and it is verified here more strictly than it was
registered: **the `<d>` row sections are byte-identical between the two binaries on all twelve probes**, so
not one ranked row moved and `SERVED`-via-`<d>` stands at exactly 8/12. N10 is counted once, in
`BODY-SERVED`, and not again. **No revert.** The wording was wrong, the mechanism was not, and the fix for
the next registration is to guard the ranked half of a metric when the round's own metric is the other half.

**Every guard is identical to the digit on both sides**, which is what the structural argument predicted:
the rule writes `fileId` and one private flag, and `wholeName` / `extraDefs` / `carriers` — the whole input
to the route decision and the plausibility bounds — are untouched, so no query can change route through
this code. All twelve probes route name-exact on both sides.

| Guard | Floor / ceiling | At `8312d8f` | With the rule in |
| --- | ---: | ---: | ---: |
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 | 98/152 / 92/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 | 88.1% / 0.643 |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 | 71.9% / 0.639 |
| LIVE / ranking / adversarial pollution@5 | ≤ 16% / ≤ 5% / ≤ 8% | 2.4% / 0.0% / 0.0% | 2.4% / 0.0% / 0.0% |

The `+N` ambiguity counts are identical on every probe whose anchor moved — 88, 41, 34, 36, 60, 30, 32 —
which is the disclosure half of the rule holding: the anchor changed its mind about WHICH definition, never
about HOW MANY there are.

`--quality-delta=8312d8f..5c434ff` (the ref-pair form): `gating="0"`, `preexisting-worse="0"`, three
`origin="new-symbol"` minor api-surface rows, all three being the `Cog` FIXTURE's own symbols. Nothing that
existed got worse, and the rule added no production symbol at all — it is nine lines inside an existing
one-pass walk.

G1: the `asan/` build (ASan + UBSan + integer + LSan with the committed suppressions) runs the new path
clean — exit 0, empty stderr — on `--for` over all three corpora and on a whole-repo map, and
`test/defoverdeclcheck.sh` passes against `asan/ripwire` as well as `build/ripwire`.

Gate count 452 → **452** — `test/defoverdeclcheck.sh` grew four arms and flipped one; no new gate file. The
final battery ran on a FROZEN tree after the last commit: `gates=463 pass=461 skip=2 fail=0`, the two skips
being `namingcalibrationcheck` (live judgement withheld by design) and `argvdiffcheck` (no `RIPWIRE_BASE`).

### The anchor-resolved body allowance — T3 body-budget round, PRE-REGISTERED 2026-08-25 (before any fix code)

**Scope guard, first.** This is **not** a KEEP/REJECT on T3, whose registered primary metric is the
transcript-mined map-then-read rate above and whose readout still waits on ≥ 30 post-deploy `--for`
episodes. Nor does it repeal the anchor-only round: **no body other than the anchor's own may ever be
served in the anchor's place, and when the anchor's own body does not fit, the honest zero stands.** This
round changes only *how many bytes the anchor's own body is allowed to cost*, on the one route where the
tool is most certain what the caller asked for. Every "which body" question is settled upstream and stays
settled.

**The named residual this closes, and nothing else.** The round immediately above moved the anchor to the
first body-carrying definition and landed `BODY-SERVED` at 4/12 — at the FLOOR of its band, because two of
the six rows whose anchor it correctly fixed (**N01** `ClientContext`, **N05** `Deserializer`, both duckdb)
then lost the body to the BYTE BUDGET and emit `bodies="0" reason="budget"`. Its own §7 item 1 names the
question: *"whether the default auto-body allowance should scale with the confidence the route has in its
anchor — a name-exact query with a resolved anchor is the most certain the tool ever is about what the
caller wants, and it is currently funded at the same fixed rate as everything else."* That round declined
to widen a constant after a measurement and left it to be registered on its own. This is that registration.

**The mechanism, stated so it can be wrong.** `buildForAutoBodies` computes ONE scalar allowance —
`leftBytes` = the bundle's leftover, plus `kForAutoBodyBudgetBytes` when there is no explicit
`--token-budget` — and hands it to `packBodies` with `truncateOversizedFirst=false`. That allowance is a
POOL sized for up to `kPackTaskBodyCandidates` = 6 bodies. But `restrictBodiesToRouteAnchor` runs first, and
on a name-exact route with a resolved anchor it frequently collapses the candidate set to **exactly one**:
the anchor's own definition. The bundle is then rationing a six-body pool against a one-body answer, and on
a large class it refuses. Default `bundleBudget` is `kForPayloadBudgetBytes` = 7,500 B, so today's allowance
cannot exceed 7,500 + 6,000 = **13,500 B** even with a zero-byte signature side — while duckdb's
`class Deserializer` body is 14,875 B. **The claim under test: when the candidate set IS one
anchor-resolved definition, that one body should be funded at a rate set by what one body is worth, not by
a pool sized for six.**

**The rule.** In `buildForAutoBodies`, after `restrictBodiesToRouteAnchor` and after the existing
`leftBytes` arithmetic, and only when all three hold:

```
  cfg.tokenBudget == 0        an explicit --token-budget stays a HARD ceiling (T3's own registration)
  !anchorDefs.empty()         the route went name-exact AND resolved an anchor to a definition
  autoBodyIds.size() == 1     the candidate set IS one definition — the anchor's own
raise:
  leftBytes = max( leftBytes, kForAnchorBodyBudgetBytes )
```

Nothing downstream changes: `autoBodyBudget = max( 1, min( leftBytes, cfg.packBudgetBytes ) )` as before,
`truncateOversizedFirst=false` as before, the same three disclosure branches as before.

**The constant, derived before the probes were consulted and not from them.**
`kForAnchorBodyBudgetBytes` = **22,800 B** = `kPackTaskDefaultTokens` (6,000) × `kBytesPerTokenBody` (3.80),
i.e. **one anchor-resolved body may cost at most what one whole default `--pack-task` bundle costs.** Both
terms are pre-existing registered constants of this tool; neither is a probe measurement. The identity is
machine-checked by a tolerance-band `static_assert` rather than left as a comment, so the number cannot
drift away from its own rationale. Its cost is disclosed where it is incurred: `est_tokens` already charges
bodies at `kBytesPerTokenBody`.

**Four properties keep this out of the general budget, and three of them are structural rather than
asserted.** (i) `autoBodyIds.size() == 1` makes *"funds at most one body"* a fact about the input, not an
accounting argument — `packBodies` is handed a one-element list and can emit at most one body; there is no
second item for the raised allowance to spend on. (ii) `cfg.tokenBudget == 0` keeps every explicit-ceiling
caller byte-identical, and lives in the same regime as the existing allowance that T3 registered as
*"without an explicit budget, the default bundle gains a fixed body allowance"*. (iii) `kForAutoBodyBudgetBytes`
itself is **not touched**, and neither is `packBodies`, so `--pack-task`, `--expand`, `--detail=N`,
`--exemplar`, `--from-trace`, the MCP verbs and the compact conceptual `<hops>` builder are byte-identical
by construction — the raise exists only inside the one `--for` auto-body branch. (iv) `truncateOversizedFirst`
stays `false`: whole-body-or-nothing survives, so a definition larger than the raised allowance is still
DROPPED and disclosed. **The honest zero does not go away; it moves.**

**What this deliberately does NOT fund.** An anchored bundle whose candidate set is 2 or more — several
same-named definitions inside the anchor's own file — keeps today's fixed pool exactly. At that point the
bundle is serving a SET, not "the answer", and a pool is the right funding for a set. This is the boundary
that stops the raise from becoming a general per-item budget increase, and it is the one an implementation
is most likely to get wrong by relaxing.

**The probe set is the twelve probes of the two rounds above, frozen and unchanged.** Corpora re-verified
in this lane by revision count: duckdb `19864453` (48632 revs), rocksdb `0e2801ac` (12938), ugrep
`550599a6` (985) — all three matching the D4 freeze to the digit.

**Primary metric: `BODY-SERVED`**, the round above's, re-used verbatim — of the twelve probes, how many have
the **gold definition's own body** emitted in `<bodies>` by a plain `ripwire <corpus> --for="<Name>"`.

**Baseline, re-measured in this lane at `518fe0d` before any code: `BODY-SERVED` = 4 / 12** — served on
N02, N03, N09, N10, reproducing the round above's result row for row. **A scoring correction that the round
above's own table implies but never had to state:** the gold must be pinned as a `(name, path, LINE)`
triple, not a path. Scored on path alone the baseline reads **6/12**, because ugrep's `include/reflex/input.h`
— the gold's own file for N11/N12 — also contains the bare in-class declarations `class dos_streambuf;`
(:335, :951) and `class streambuf;` (:333), which the allowance does emit as bodies. Those are same-named
text in the right file and are exactly the *"reads like an answer and is not one"* shape the anchor-only
round refuses; counting them would inflate this metric by two rows on both sides of the A/B. The triple is
what the round above's table already meant (its N11/N12 rows read "five constructor bodies … gold body? no").

**The feasibility ceiling, audited on all THREE gates this time — the round above's own lesson, applied to
the round that IS the third gate.** A body reaches `<bodies>` only through the anchor, the candidate head,
and the budget. This rule moves the budget alone, so a probe can move only if it is *already* through the
first two and stopped by the third: it must currently read `bodies="0" reason="budget"`, its single
candidate must be the gold, and the gold must fit 22,800 B. The candidate-set size is directly observable
as `<bodies total="N">`, so this audit is read off the base run rather than reasoned toward:

| id | `total=` | state at `518fe0d` | can this rule move it? |
| --- | :---: | --- | --- |
| **N01** | 1 | `reason="budget"`, candidate IS the gold, body **12,691 B** | **YES — the rule's whole target** |
| **N05** | 1 | `reason="budget"`, candidate IS the gold, body **14,875 B** | **YES — the rule's whole target** |
| N02, N03, N09 | 1 | already serving the gold | no — one candidate already emitted; a larger pool buys nothing |
| N04, N07 | 1 | already serving (a non-gold out-of-line constructor) | no — same; and the rule cannot change WHICH body |
| N06, N08 | 0 | `reason="no_candidates"` | no — that branch returns **before** the allowance is computed |
| N10 | 2 | serving 2 | no — `size() != 1`, the rule is not applied |
| N11, N12 | 5 / 4 | serving 5 / 4 | no — `size() != 1`, the rule is not applied |

**Registered band: `BODY-SERVED` = 6 / 12, i.e. `[+2, +2]` against the baseline of 4.** The ceiling is +2
because **N01 and N05 are the only two rows this rule can possibly move**, and the table above says so from
an observable rather than from a mechanism story. The floor is also +2 because both golds are measured, both
are single-candidate, and both sit under 22,800 B with ≥ 7.9 KB of headroom — there is no third outcome that
is not a bug. **Below +2 is a REJECT and the code is reverted. Above +2 is impossible under the audit, so it
means the audit is wrong and the change must be re-read before it may ship, not celebrated.**

**The prior round's invariance criterion does NOT carry over, and saying so is the point.** That round
registered *"a query whose name has a UNIQUE definition must produce a byte-identical bundle"* — valid
there, because a unique name has no second claimant for an anchor rule to choose between. It is **not**
valid here: a unique-definition name whose body exceeds the allowance is precisely what this round funds.
Applying it unchanged would be registering a criterion the round is designed to violate. This is the round
above's own finding #3 — *guard the half of a prior metric the current round does not touch* — so the
invariance criterion is restated for what this rule actually cannot reach:

> **A bundle is byte-identical unless it is a name-exact, anchor-resolved, no-explicit-budget bundle whose
> candidate set is exactly one definition that does not currently fit.** Every other bundle — every
> conceptual route, every explicit `--token-budget`, every multi-candidate anchor, every already-serving
> single candidate, and every other verb — must not differ by one byte.

`--for="computeLensRanking"` and `--for="lexicalScoresNameExactTiered"` are still byte-pinned below, but for
a different reason than last round: they already serve their single candidate (`total="1" shown="1"`), so
the raise buys them nothing. Their names being unique is now a coincidence, not the argument.

**Registered controls — byte-compared, base vs head, same tree and same corpus; any difference is a
REVERT.** CTL01–CTL13 are the round above's registered set re-used unchanged; CTL14–CTL20 are new and are
the surfaces this rule could plausibly reach. The repo-root controls run against a FROZEN `518fe0d`
checkout, never the lane worktree, whose own sources change when the rule lands.

| control | command | why it cannot move |
| --- | --- | --- |
| CTL01 (C13) | UG `--for="forward declared nested stream buffer classes"` | compact conceptual route — a different builder |
| CTL02 (G18) | UG `--for="dos line ending stream buffer for buffered input"` | compact conceptual route |
| CTL03 (G20) | UG `--pack-task="implement a new stream buffer over reflex Input" --token-budget=6000` | `--pack-task` does not use this allowance |
| CTL04, CTL05 | frozen repo, `--for="computeLensRanking"` / `--for="lexicalScoresNameExactTiered"` | anchored, `total="1"`, **already serving** |
| CTL06, CTL07 | frozen repo, flagless map / `--for="how does the ranker route a query"` | no anchor at all |
| CTL08, CTL09 (N04, N07) | DD `--for="TableCatalogEntry"` / RD `--for="ColumnFamilyData"` | anchored, `total="1"`, already serving |
| CTL10, CTL11 (N11, N12) | UG `--for="dos_streambuf"` / `--for="streambuf"` | anchored, `total="5"`/`"4"` — `size() != 1` |
| CTL12, CTL13 (N06, N08) | DD `--for="Catalog"` / RD `--for="Slice"` | `total="0"` — returns before the allowance |
| **CTL14, CTL15** | **DD `--for="ClientContext" --token-budget=6000` / `--for="Deserializer" --token-budget=6000`** | **the hard-ceiling tripwire: the two rows the rule DOES move, with an explicit budget. An implementation that forgot `cfg.tokenBudget == 0` serves a body here and this control goes red.** |
| CTL16 | frozen repo, `--for="how does the ranker route a query" --auto-bodies` | the conceptual rank-first body walk — no anchor |
| CTL17 | DD `--pack-task="add a new serializer format" --token-budget=6000` | separate builder |
| CTL18 | DD `--expand=ClientContext` | separate verb, `truncateOversizedFirst=true` |
| CTL19 | DD `--for="ClientContext" --signatures-only` | the registered opt-out |
| CTL20 | DD `--for="ClientContext" --detail=1` | the explicit body knob; `autoBundleMode` requires `cfg.detail == 0` |

**Registered guards, re-run after the change; any regression is a REVERT regardless of the band.** Every
value below is this lane's OWN re-measurement at `518fe0d`, and every one reproduces the last recorded
baseline to the digit — the instrument check, done before any result was believed. All of them are expected
identical **by construction**: this rule changes a byte allowance downstream of ranking and cannot move a
`<d>` row, a candidate order or a route decision.

| Guard | Floor / ceiling | At `518fe0d`, measured in this lane |
| --- | ---: | ---: |
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 |
| LIVE / ranking / adversarial pollution@5 | ≤ 16% / ≤ 5% / ≤ 8% | 2.4% / 0.0% / 0.0% |
| recall / ranking frozen corpus pins | contract | `7a7f7989203479` files=113 · `7a3194b51ac6` files=1422 |
| `run_r3diff.py` ranking (n=32) + recall (n=42) | near-all ties | — |
| the round above's `BODY-SERVED` rows N02/N03/N09/N10 | **must stay served** | 4 / 4 |
| determinism (two runs byte-identical) + `xmllint` | contract | — |
| full gate battery | all green | — |
| G1 — ASan/UBSan/integer/LSan over the new path | no report | — |

**The gate, registered before it is written.** Four new arms on `test/anchorbodycheck.sh`, which already
owns this contract. A new mid-sized fixture symbol is needed because the existing oversized one
(`widgetAnchorProbe`, **36,163 B**) is far above the raised allowance and therefore cannot observe it —
that is deliberate and it is why arms (0)/(1)/(2) stay green and stay meaningful.

* **(7)** RED-FIRST. A MID-SIZED anchor — above today's ≤ 13,500 B allowance, below 22,800 B — is served
  whole. On the base binary this is `bodies="0" reason="budget"`; with the rule it is `bodies="1"`.
* **(7b)** …and served ALONE, from its own file, with no bystander prose. The raise must not re-open
  substitution: a bigger allowance is exactly the condition under which the old defect used to fire.
* **(7c)** The raise does NOT apply under an explicit `--token-budget`: the same query with a stated
  ceiling still refuses and still discloses. Green on both binaries, and the fixture form of CTL14/CTL15.
* **(7d)** The OVERSIZED anchor still refuses at the raised allowance — whole-body-or-nothing survives and
  the raise is BOUNDED. This is arm (1)/(2) restated at the new ceiling.
* **(7e)** A MULTI-candidate anchored bundle does not get the raise: two same-named mid-sized definitions in
  ONE file stay at `bodies="0"`. An implementation that dropped the `size() == 1` guard serves one of them
  and goes red here. This is the leak tripwire, and it is verified by mutation, not by inspection.

**KILL conditions, registered before the result.** Any one of: `BODY-SERVED` not exactly 6/12; any of the
twenty byte-compared controls differing; **any of N02/N03/N09/N10 losing a body it already served**; a
`<d>` row section changing on any of the twelve probes; any guard floor above going red; a route decision
changing on any probe; or a body served that is neither the gold nor what base served.

#### The result: SHIP, in band, and the audit was right this time

| Registered metric | Baseline | Measured | Band / bar | Verdict |
| --- | ---: | ---: | --- | --- |
| `BODY-SERVED` — gold definition's own body emitted, n=12 | 4 / 12 | **6 / 12 (+2)** | [+2, +2] | **in band** |
| Byte-compared controls (20) | — | **20 / 20 identical** | any difference kills | held |
| `<d>` row sections, all twelve probes | — | **12 / 12 byte-identical** | must not move | held |
| Whole bundles, all twelve probes | — | **10 / 12 byte-identical** | only N01/N05 may move | held, stronger than registered |
| N02/N03/N09/N10 still served | 4 / 4 | **4 / 4** | must not lose one | held |
| `run_r3diff.py`, ranking (n=32) + recall (n=42) | — | **74 ties, 0 wins, 0 losses** | near-all ties | held |

**The two rows the audit named, and nothing else.**

| id | corpus | body served: base → head | gold body B | `BODY-SERVED` | audit said |
| --- | --- | --- | ---: | :---: | --- |
| **N01** | DD | none, `reason="budget"` → **the gold**, `client_context.hpp:65` | 12,691 | **yes** | reachable |
| **N05** | DD | none, `reason="budget"` → **the gold**, `deserializer.hpp:22` | 14,875 | **yes** | reachable |
| N02, N03, N09, N10 | DD/RD | unchanged — still the gold | — | **yes** ×4 | already serving |
| N04, N06, N07, N08, N11, N12 | — | **byte-identical bundles** | — | no ×6 | unreachable, each for its named reason |

**The feasibility ceiling was exactly right, which is the first time in this sequence.** The round above
audited two of the three gates a body passes and was row-for-row correct about the mechanism but wrong about
the ceiling by two. This registration audited all three, predicted `+2` and named N01 and N05 in advance,
and got `+2` on N01 and N05. The thing that made it checkable rather than merely careful was reading the
candidate-set size off `<bodies total="N">` in the base run instead of reasoning toward it — **a feasibility
ceiling built from observables is auditable before the result; one built from a mechanism story is only
auditable after.**

**The cost, stated plainly, because this round makes two calls more expensive.** `est_tokens` on the two
moved probes goes 3,798 → **7,144** (N01) and 962 → **4,886** (N05). That is the trade: those two callers
were being told the answer existed and did not fit, and are now handed it. The bodies themselves cost 3,340
and 3,914 tokens against the registered 6,000-token ceiling, i.e. the constant is a real bound and the two
bodies it bought landed at 56% and 65% of it — it is not a number tuned so that the probes just squeeze in.
The other ten probes cost exactly what they cost before, to the byte.

**An honest correction to the intuition the derivation could be mistaken for.** It is tempting to justify a
body allowance as "cheaper than the whole-file read it replaces". On these two probes that is **not** true
in bytes: `class ClientContext` is 12,691 B of a 14,995 B header (85%) and `class Deserializer` is 14,875 B
of 15,956 B (93%) — a large class in a dedicated header essentially IS its file. The win this round buys is
therefore not a byte saving over the read; it is that the answer arrives inside the call the agent already
made, ranked, with the quality lens on it, instead of as a second round trip. The registered derivation is
`kPackTaskDefaultTokens × kBytesPerTokenBody` and rests on nothing else, and the byte-saving story is
recorded here as refuted rather than left available to be repeated.

**Every guard is identical, and the strongest of them is stronger than registered:** the whole
`--eval-skills` report — every arm, every split, the judged-only line — is **byte-identical** between the
two binaries, not merely equal on the four pinned numbers.

| Guard | Floor / ceiling | At `518fe0d` | With the rule in |
| --- | ---: | ---: | ---: |
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 | 98/152 / 92/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 | 88.1% / 0.643 |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 | 71.9% / 0.639 |
| LIVE / ranking / adversarial pollution@5 | ≤ 16% / ≤ 5% / ≤ 8% | 2.4% / 0.0% / 0.0% | 2.4% / 0.0% / 0.0% |

That is what the structural argument predicted: the rule changes a byte allowance strictly downstream of
ranking, so it cannot move a `<d>` row, a candidate order or a route decision. The `anchors:` clause and its
`+N` ambiguity count are identical on both moved probes (88 and 36) — the only thing that changed on either
root is `bodies="0" reason="budget"` becoming `bodies="1"`, which is the disclosure doing its job.

**The gate, and the mutation that proves its most important arm is not inert.** `test/anchorbodycheck.sh`
grew six arms and two fixtures, verified **RED at `518fe0d` on exactly (7) and (7b)** with all twenty other
arms green, and ALL PASS at head under both `build/ripwire` and `asan/ripwire`. Arm **(7e)** — the
`size() == 1` leak tripwire — was additionally proved by MUTATION: with that conjunct removed and the binary
rebuilt, the first of two same-named mid-sized twins fits the raised allowance and the bundle reports
`bodies="1"`, so (7e) fails **and only (7e) fails**. A tripwire that fires on exactly the mistake it names,
and on nothing else, is worth more than one that merely happens to be green.

G1: the `asan/` build (ASan + UBSan + integer + LSan with the committed suppressions) is clean — exit 0,
empty stderr — on both newly-served probes, on the explicit-`--token-budget` shape, the multi-candidate
shape, the `no_candidates` shape, all three corpus maps and the self-map, and `test/anchorbodycheck.sh`
passes against `asan/ripwire`.

`--quality-delta=518fe0d..HEAD` (ref-pair): `gating="0"` `preexisting-worse="0"` after acking exactly two
findings, both on `buildForAutoBodies` and both the change's own shape — complexity `ccx` 16 → 19 (the `if`
and its `&&`) and verbosity 107 → 128. `--ack-only=gating`, so the never-gating `api-surface` row for
`kForAnchorBodyBudgetBytes` stays visible and unacked. The duplicated half of the call-site comment was
removed first, on its own merits: the mechanism and the derivation now live once, beside the constant.

Gate count **463 → 463** — six arms and two fixtures on an existing gate, no new gate file.

Two reds in the first battery were real and both were mine: `g1freshcheck` (the `asan/` tree predated the
comment de-duplication — rebuilt, and the gate is worth believing exactly as `CLAUDE.md` says) and
`readmeexamplecheck` (the rule's lines shifted `churnRankedGraph`/`runDefaultMap` by 28 — re-pinned from the
binary). A third, `editcheckcheck`'s 100 ms warm budget, measured 144/147 ms inside a `-j 6` battery at load
~30 and **75 ms re-run solo**: environmental, the false-positive class this campaign hits constantly, and
nothing was `pkill`-ed to get that measurement.

The final battery ran on a FROZEN tree after the result commit: **`gates=463 pass=461 skip=2 fail=0`**
(wall 387.5s, `-j 6`), the two skips being `namingcalibrationcheck` (live judgement withheld by design) and
`argvdiffcheck` (no `RIPWIRE_BASE`).

---

### `--recall` ranks by where the repo sits on disk — PRE-REGISTERED 2026-08-25 (before any fix code)

**What this registers.** The single disclosed residual of the root-relative lane, and nothing else. That
lane made every EMITTED path relative to the corpus root, so the document a consumer receives no longer
depends on where the repo happens to sit on disk — and it closed by naming what it had deliberately *not*
fixed (its report, §6): `--recall`'s relevance SCORES still move with checkout depth, because curing that
means changing what the RANKER indexes, and a ranking change owes an eval. **This is that eval, registered
before any fix code exists.**

**The mechanism, stated so it can be wrong.** `lexical.h` pass 1.5 scans each symbol's file path through the
same BM25 subtoken state machine as its name, doc-comment and body, at weight `pathFieldDefaultW`. Exactly
one caller passes a nonzero weight: the `--recall` lens passes 1, because documents are ranked partly BY
their filename — a query naming "readme" or "paired table" should reach the doc whose PATH says exactly that
(measured at +0.03 lenient MRR, gate `test/recallevalcheck.sh`). The string it scans is `ing.files[fileId]`,
the STORED spelling, which the root-relative lane proved must stay absolute (`g.canonId`, `Regression::key`,
every `pathQualifiedKey`, and the ingest cache's `reAbsolutize` all key off it). So every directory ABOVE the
corpus root is indexed as corpus vocabulary, with two distinct consequences:

* every symbol gains the SAME root tokens, so each document's BM25 length `dl` and the corpus `avgdl` grow by
  different proportions, length normalization shifts, and **every** score moves; and
* if any directory above the root spells a query word (`…/ripwire/docs/recall/…`), that word now matches
  EVERY document, its idf collapses, and whatever else the documents happen to share decides the order.

The second is the one that reorders answers. The claim under test: **the scorer should index the path the
emitter now prints — the root-relative one — because nothing above the root is corpus text.**

**The oracle is not invented, which is why the target is an equality and not a tolerance.** A RELATIVE root
already stores `./docs/x.md`, whose only path tokens are corpus-internal, so `ripwire . --recall=Q` is
already depth-invariant and already shipping. The correct ranking therefore exists today, and absolute-root
runs simply disagree with it. `rootrelemitcheck.sh` ARM 3 established for emission that *an absolute root is
a SPELLING, not a content change*. This registers the ranking twin of that sentence.

**The rule.** In pass 1.5 — and in its inert basename sibling pass 1.6, so the two path passes cannot drift
apart — scan `rw::sarif::rootRelativeUri( ing.files[f], pathRootPrefix )` instead of `ing.files[f]`. That is
the identical helper `recall.h` already uses to print the separator line's path, so the SCORED string and the
PRINTED string cannot disagree about a file. `pathRootPrefix` is a new defaulted parameter, empty for every
existing caller; only the `--recall` call site passes one, derived from the same single-root expression that
already feeds `buildRecall`. **No stored spelling moves.**

**Three properties are structural rather than asserted, and they are why this cannot reach the other
lenses.** (i) Pass 1.5 does not execute at all unless `pathFieldDefaultW > 0`, and `--recall` is the *only*
caller passing a nonzero weight — so `--for` and its whole family, `--exemplar`, `--handoff` and both eval
harnesses are byte-identical **by control flow, not by measurement**. (ii) The new parameter defaults to
empty, and `rootRelativeUri(p, "")` strips a leading `./` and otherwise returns `p` unchanged — which is
exactly today's behaviour for relative roots. (iii) MCP `memory_recall` calls `lexicalScores` with no weight
argument at all and is therefore already immune; see the finding below.

**The probe set** is the recall lane's frozen corpus — every tracked `*.md` at the commit pinned in
`snapshot.lock` (113 docs @ `7a7f798`) — and its 42 held-out queries from `labels_recall.tsv`. The LABELS are
deliberately unused: this measures INVARIANCE, not correctness, and whether an answer is *right* is
`run_recalleval.py`'s job. Instrument: `bench/recalleval/run_depthinvariance.py`, committed with this
registration.

**Primary metric: `ORDER-MOVED`** = of the 42 queries, how many return a different ranked list of documents
when the identical corpus is addressed at a different checkout depth. Reported beside it: `TOPK-MOVED` (a
different SET of documents — the harm a user actually sees) and `SCORE-MOVED` (the finest signal, first to
move and last to settle).

**Baseline, measured in this lane at `518fe0d` before any fix code existed:**

| comparison | what differs between the two runs | order | top-K | score |
| --- | --- | ---: | ---: | ---: |
| **A vs B** | absolute root, NEUTRAL depth delta (+90 chars, segments sharing no vocabulary) | **5 / 42** | 0 / 42 | **42 / 42** |
| **A vs P** | absolute root, ADVERSARIAL depth delta (+68 chars, every segment corpus vocabulary) | **11 / 42** | **5 / 42** | **42 / 42** |
| **C vs D** | relative root at both depths — the oracle's own flatness control | 0 / 42 | 0 / 42 | 0 / 42 |
| **A vs C** | absolute vs relative spelling of the same corpus at the same depth | 3 / 42 | 1 / 42 | 42 / 42 |

Two rows carry the argument. **A vs P is worse than A vs B at a SHORTER delta** — 11 reorderings and five
changed answer SETS, against 5 and none — so the defect is driven by vocabulary, not length, and any
measurement testing only neutral depth would under-report the thing it exists to catch. **C vs D is flat at
0 / 0 / 0**, which is what makes the fix a convergence onto an already-correct shipped behaviour rather than
a new ranking opinion.

**Registered band: EXACT invariance — A vs B, A vs P and A vs C must all reach 0 / 0 / 0.** Not "a large
reduction toward invariance": the oracle row proves 0 is attainable, and the mechanism predicts the scanned
string becomes byte-identical to the relative-root one, so anything above 0 means the mechanism is not what
this registration says it is. **A nonzero residual on any of the three is a REJECT and the code is
reverted** — a partial cure would mean some other path-derived quantity is *also* depth-dependent, which is
a different finding owing its own round, not a win to bank.

**Registered kill tripwire, which outranks the band.** Invariance is trivially achievable by scoring no path
tokens at all, which would silently delete a measured retrieval feature. `test/recallrankdepthcheck.sh`
ARM 4 therefore retrieves a document whose BODY never contains the query word and whose PATH does, at all
three roots and under the relative spelling. **If ARMs 1-3 go green while ARM 4 goes red, the change
disabled the feature instead of relativizing it, and it is reverted regardless of every other number.**

**Registered controls — byte-compared, base vs head; any difference is a REVERT.**

| control | why |
| --- | --- |
| recall lane lenient recall@5 / MRR on the frozen corpus | `run_recalleval.py` addresses the corpus RELATIVELY (`ripwire .`, cwd = root), so the scored string does not change and these must be **digit-identical**, not merely in-band |
| `--for`, `--format=candidates`, `--pack-task`, `--exemplar` on any corpus | pass 1.5 never runs at these lenses — byte-identical by control flow |
| `run_r3diff.py` on both frozen sets | the wide-diff detector: a change confined to `--recall`'s path field must leave the **ranking** set at all-ties |
| MCP `memory_recall` | passes no path weight, so it must be byte-identical — and it is the control proving the CLI/MCP divergence below is pre-existing rather than introduced here |

**Registered guards, re-run after the change; any regression is a REVERT regardless of the band.** Every
value below is this lane's own re-measurement at `518fe0d`, and every one reproduces the last recorded
baseline to the digit — that is the instrument check, done before any result was believed.

| Guard | Floor / ceiling | At `518fe0d` |
| --- | ---: | ---: |
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 |
| LIVE / ranking / adversarial pollution@5 | ≤ 16% / ≤ 5% / ≤ 8% | 2.4% / 0.0% / 0.0% |
| `run_r3diff.py` ranking (n=32) / recall (n=42) | near-all ties | — |
| determinism (two runs byte-identical) + `xmllint` well-formedness | contract | — |
| full gate battery (`test/pargates.py`) | all green | — |
| G1 — ASan/UBSan/integer/LSan over the changed path | no report | — |

**A pre-existing divergence this registration does not fix, recorded so the next reader need not re-find
it.** `mcpverbs.h::recallText` calls `lexicalScores( ix.ing, …, task )` with no `pathFieldDefaultW`, i.e. 0,
while the CLI `--recall` passes 1 — so MCP `memory_recall` and CLI `--recall` already rank the same query
differently, under a comment claiming they "share `lexicalScores`". That is its own ranking change owing its
own eval; it is out of this round's one-mechanism scope, and it is why MCP `memory_recall` appears above as
an invariance CONTROL rather than as a subject.

**DISCHARGED 2026-08-30 — MCP takes the CLI's ranking, and the argument that let them differ is gone.** The
divergence was worse than a score shift: on a corpus where a document's *directory* names the query word and
its body never does, CLI `--recall=telemetry` returns `telemetry/zeta.md` while MCP `memory_recall` returned
`(no relevant documents — try different terms)`. The CLI is the reference surface, so the CLI's answer is the
one that stands: `recallText` now ranks with the recall lens (`pathFieldDefaultW=1` and the root prefix) and
the two doors are byte-identical, header included. The fix is structural rather than a second copy of one
argument list — the lens decision moved into `recall.h::recallFor`, the single rank-then-build call BOTH doors
make, and the old `writeRecall( out, ing, scores, … )` wrapper, whose caller-supplied `scores` parameter WAS
the divergence, is deleted; no argument remains through which a front door can rank recall its own way.
**CLI `--recall` output is unchanged, byte for byte** (checked against a pre-change binary over this repo,
`docs/`, and the probe corpus): this round moves the MCP door only. `test/recallparitycheck.sh` gates the
class — same corpus and task ⇒ same bundle on both doors, plus the shaping knobs (`--top-k` / `top_k`,
`--max-tokens` / `budget_tokens`) — and carries the same KILL-TRIPWIRE shape as `recallrankdepthcheck.sh`
ARM 4, because byte-parity is trivially reachable by scoring no path tokens at all: the two path-only
documents must still be RETRIEVED on both doors, or the "unification" deleted the measured feature and is
reverted regardless of every other arm. Against a pre-change binary the gate is red on 8 of its 12 arms,
that tripwire among them.

### The result — EXACT invariance, at the registered target (2026-08-25)

**Verdict: SHIP.** The registered band was EXACT invariance, and exact invariance is what the fix reaches —
all three absolute-root comparisons go to `0 / 0 / 0`, with the relative-root oracle unmoved throughout.

| comparison | order | top-K | score |
| --- | ---: | ---: | ---: |
| **A vs B** — absolute root, neutral +90-char depth | 5 → **0** / 42 | 0 → **0** / 42 | 42 → **0** / 42 |
| **A vs P** — absolute root, adversarial +68-char depth | 11 → **0** / 42 | 5 → **0** / 42 | 42 → **0** / 42 |
| **A vs C** — absolute vs relative spelling | 3 → **0** / 42 | 1 → **0** / 42 | 42 → **0** / 42 |
| **C vs D** — the oracle's own flatness control | 0 → 0 / 42 | 0 → 0 / 42 | 0 → 0 / 42 |

`test/recallrankdepthcheck.sh`: **15 of 21 arms FAIL** against a clean build of `518fe0d` (ARMs 1, 2 and 3
red; ARM 0 liveness and all four ARM 4 path-field tripwires green — the exact shape the registration
predicts of a pre-fix binary), **21 of 21 PASS** at this head, and ALL PASS again under `asan/ripwire`.

**Every registered guard is unmoved, and most of them by a stronger statement than "in band".**

| Guard | Floor / ceiling | At `518fe0d` | At head |
| --- | ---: | ---: | ---: |
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 | 98/152 / 92/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 | 88.1% / 0.643 |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 | 71.9% / 0.639 |
| LIVE / ranking / adversarial pollution@5 | ≤ 16% / ≤ 5% / ≤ 8% | 2.4% / 0.0% / 0.0% | 2.4% / 0.0% / 0.0% |
| `run_r3diff.py` ranking (n=32) | near-all ties | — | **32 ties, 0 wins, 0 losses, net +0** |
| `run_r3diff.py` recall (n=42) | near-all ties | — | **42 ties, 0 wins, 0 losses, net +0** |

The whole `--eval-skills` report is **byte-identical** base vs head, which subsumes all four routing numbers
and both judged-only arms — a stronger claim than the digits agreeing. The recall and ranking lanes are
digit-identical for the registered reason: `run_recalleval.py` invokes `ripwire .` with `cwd` = the corpus
root, so the scored string never contained a checkout prefix to remove.

**The registered controls, byte-compared base vs head at an ABSOLUTE root** — the only spelling under which
a leak could show — with the sizes recorded so no row is an empty-vs-empty pass:

| control | bytes | verdict |
| --- | ---: | --- |
| default map | 21998 | identical |
| `--for` conceptual / candidates / name-exact | 8391 / 2922 / 13387 | identical |
| `--pack-task` / `--exemplar` / `--pack-signatures` | 9591 / 1650 / 30668 | identical |
| `--json` / `--metrics` / `--handoff` | 22794 / 45215 / 1445 | identical |
| MCP `memory_recall` / MCP `for` | 685 / 668 | identical |
| `--recall` at an absolute root | 690405 | **DIFFERS — the subject** |

Twelve of thirteen identical and exactly one changed, and the one that changed is the verb under test. MCP
`memory_recall` being byte-identical is also the positive evidence for the divergence recorded above: it
never ran the pass that moved.

**Quality.** `--quality-delta=518fe0d..HEAD`: **7 findings, 4 gating → gating="0", acked="4"**, three
non-gating rows left visible. Acked with `--ack-only=gating`, never bare `--quality-ack`. All four ARE the
change: 2 × api-surface contract-change (the `+1` root parameter on `lexicalScores` /
`lexicalScoresTiered` — the scorer cannot relativize against a root it was never told) and 2 × verbosity
(that parameter's rationale in comments, already tightened once *because* the tool flagged them).

**One finding was NOT acked, because the tool was right and the fix was cheap.** The first run reported
`complexity runTargetedViews 42 → 44`, from a ternary guarding `rootPrefixOf` against an empty root. But
`rootPrefixOf("")` already returns `""` — its trailing-slash loop needs `size() > 1` — so the branch could
not change an outcome. Removed; the finding is gone rather than acked. The three surviving non-gating rows
are two `params` minors (the same `+1`, counted on the other axis) and one `dead-code` on the new
instrument's `Cmp.__init__`, a Python constructor no caller names — a resolver artifact, `origin="new-symbol"`,
never gating, and recorded rather than suppressed.

**Gate battery**, on a FROZEN tree: `gates=464 pass=461 skip=2 fail=1 wall=480.6s`. Gate count 455 → **456**
(`test/recallrankdepthcheck.sh`), all three `docs/EVALS.md` pins moved together. The two skips are the
tree's standing ones (`namingcalibrationcheck`, live judgement withheld by design; `argvdiffcheck`, no
`RIPWIRE_BASE`).

**The one failure is `editcheckcheck`'s 100 ms warm timing budget, and it is environmental.** Two
independent reasons, the structural one first: `--edit-check` never executes the changed code at all — pass
1.5 runs only when `pathFieldDefaultW > 0`, and `--recall` is its only nonzero caller — so no control-flow
path connects this change to that measurement. And the A/B says the same: a clean `518fe0d` build misses the
same budget on this machine (111/110 ms, then 139/209 ms), while this head measured **85 ms and PASSED**
when the machine was quiet and 136/149 ms when it was not. The spread on ONE binary is 85–310 ms, which
swamps any difference between the two. This matches the standing note on this gate across several lanes.

**One re-derivation, kept as its own commit.** The fix added 11 lines to `src/main.cpp` above two rows the
README pins verbatim, so `churnRankedGraph` moved `13388 → 13399` and `runDefaultMap` `13503 → 13514`.
`readmeexamplecheck.sh` caught it; the numbers were re-derived from this tree's own binary rather than
hand-adjusted.

`--test-gate` on the changed files names one test (`test/adaptivecutshapecheck.sh` — ALL PASS) and a
20-symbol untested blast radius. Those 20 are the `lexicalScores` consumers, and every one of them is
covered empirically above rather than by the call graph: they are the byte-identical control rows, the two
frozen `r3diff` sets and the two eval harnesses.

G1: the `asan/` build (ASan + UBSan + integer + LSan with the committed suppressions) is clean — `rc=0`,
empty stderr — on `--recall` at an absolute root, on `--for`, on a whole-repo map, and across the whole of
`test/recallrankdepthcheck.sh`. Determinism ×3 byte-identical (21940 B) and `xmllint --noout` clean.

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

**Root-neutralised on this repository (re-derived 2026-08-23):**

| Result size | Byte reduction | previous (2026-08-01) |
| --- | --- | --- |
| top-10 | 86.5% | 46.7% |
| **top-50** | **81.4%** | 67.0% |
| top-100 | 81.6% | 66.2% |

The three figures moved together on 2026-08-15, and the cause is on the *denominator* side, not this
verb's: `--expand`'s `<b>` bodies now carry `sibs=`/`inc=` file-context attributes, which grows the
full-body side of the ratio. The verb elides no more than it did. `docs/COMMANDS.md`'s own
`--pack-signatures` caption is regenerated from a live capture and carries the same triple, and
`test/showcasecapturecheck.sh` fails if the caption and its own recount drift more than 1.5 points
apart — at the time of writing that recount reads 86.5 / 81.1 / 81.3.

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
recount drift more than 1.5 points apart — plus a separate regression band at top-50, derived as the
caption's own figure ±9 points (72–90% at the caption's current 81.4%). The
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
- **`--grep` re-derived 2026-08-15** (post emission-overhaul; supersedes the 2026-06-20 +19.7% /
  −11.2% row — kept below as the historical record). Same instrument arm as `bench/bench_proof.py`
  (tiktoken `cl100k_base`, `--no-cache`, same two terms), on the same private corpus advanced from
  366 to 405 files. Four disclosed facts, not one number:
  1. **The wave's causal cut, binary-to-binary** (identical corpus, queries, cap state):
     `--grep frantic` 6,568 → 4,552 → **4,415** tok (**−30.7%** at the wave, **−32.8%** after the
     fix-grep lane's conditional-legend fix), `--grep FirePolicy` 6,531 → 4,556 → **4,419**
     (**−30.2%** → **−32.3%**) at the capped view; −22.2% / −21.5% → **−23.1% / −22.3%**
     uncapped (`--limit=1000`). Independent corroboration:
     `test/grepbytescheck.sh` re-derives a **−40.2% median** payload cut on this repository's five
     frozen *capped* queries — and, on twelve frozen *uncapped* small-hit queries, a
     **+61.5% median** payload *increase*, larger than plain grep on **12 of 12**.
     **What "the view" means since 2026-08-19**: span tiers made `--grep`'s DEFAULT a filtered view of the
     same exhaustive scan, and this gate's instrument was deliberately pinned to `--grep-in=any` — the
     un-tiered emitter — in the same wave (`test/grepbytescheck.sh:114`, with the reason in its own header:
     folding a second, independent row-cutting axis into the same median would silently re-band a published
     number, and would empty the capped regime this set exists to measure, since three of its frozen queries
     stop being capped once their comment rows are held back). So every byte figure in facts 1-3 is an
     **`--grep-in=any`** figure, not a default-view figure — including the pre-tier measurements, whose
     "default" was byte-identical to today's `--grep-in=any` (verified across eleven query shapes, both
     dialects and the MCP surface by the wave-3 verifier). The tiered default's own byte effect is reported
     un-banded by the gate and is not a headline in either direction: measured `buffer` **−20.4%** to
     `DEGRADED_PATH_ALERT` **+12.3%**, because suppressing comment rows frees room under the row cap and the
     page refills with code rows — the tiered default buys row QUALITY at a fixed row budget, not bytes.
     Those two medians
     are DEV-MACHINE values: ripwire's grep enrichment carries git-context-dependent bytes
     (churn/amp/hotspot attrs vary with the clone), and the same commit re-derived the capped median
     as −41.4% (dev worktree), −55.8% (fresh single-branch clone), and −31.5%/−31.9% (the two CI
     platforms). What is environment-STABLE, and what the gate asserts on every run everywhere: the
     ≥30% kill-condition bar held in all four environments, and both directions held (capped always a
     cut, uncapped always an increase). The gate also pins this paragraph's form and signs, so the
     claim cannot silently rot; magnitudes here are labelled by machine, not gated. *(Re-measured 2026-08-15 by the fix-grep lane, which corrected three
     instrument defects in that gate: the two arms were reading different corpora (ripwire the whole
     repo, grep only `src/`), `grep` was invoked by bare name, and all five frozen queries were
     row-capped — so the statistic tracked grep's verbosity rather than ripwire's encoding, and the
     regime where ripwire is LARGER was structurally invisible. The same lane made the boolean-terms
     legend clause conditional on `--and`/`--not` actually being passed, which is what moved the capped
     median from −38.6% to −40.2% and the uncapped one from +78.0% to +61.5% (re-derived at the final wave head bc19040 — the expand-estimator and legend-scoping merges moved bytes after the fix-grep measurement). One residual is disclosed
     in the gate's own header rather than acted on: both arms are handed an ABSOLUTE corpus path, so
     grep repeats a ~60-byte prefix on every output line while ripwire prints a root-relative path once
     per file; re-running the capped set with a relative path for both arms reads **≈ −14%**, not
     −40.2%. Re-basing a published headline by ~25 points is an owner call, and it is recorded as the
     open item in `PLAN_HARVEST_REPORTS_2026-08-15/ROUTING_LEDGER.md`.)*
  2. **Un-tiered view (`--grep-in=any`) vs a clean raw-grep dump**: **−1.9% / +4.3%** *(re-measured
     2026-08-15 after the
     fix-grep lane; the wave itself read +1.2% / +7.6%, and 2026-06 read +19.7% / −11.2%. Labelled
     "default view" until 2026-08-19; span tiers moved the default and the label was corrected, not the
     number — the measurement is unchanged and `--grep-in=any` is byte-identical to the pre-tier default)*.
     The
     `frantic` arm crosses zero for the first time — that view is now marginally *smaller* than
     a clean grep dump on that term, and still larger on `FirePolicy`; one term either side of parity
     is not a headline, which is why the row prints both. Not same-answer: ripwire shows 100 of 172/190
     occurrence-hits (capped, disclosed in-band) with enclosing symbols; grep's 90/86-line dump is
     complete. "Clean" = `--exclude-dir=.claude` — the corpus now carries agent-worktree duplicates
     ripwire's crawler skips; without that exclusion the grep arm balloons 4.7× and ripwire reads −80%,
     a litter artifact this row refuses to quote.
  3. **Same-answer uncapped parity — the anti-headline stands**: showing every hit,
     `--grep --grep-in=any` remains
     token-negative vs clean grep, **+150% / +214%** *(re-measured 2026-08-15 after the fix-grep lane;
     +153% / +217% at the wave, down from +225% / +304% pre-wave on the same measurement)*. `--grep`
     buys enclosing-symbol structure and in-band honesty, not fewer tokens, on exhaustive dumps. The
     fixed per-answer legend is why the gap barely moves here: it is amortized over every hit on an
     exhaustive dump, and dominant only on the small-hit answers fact 1's uncapped gate set measures.
  4. **Boolean AND is the flip**: `--grep=frantic --and=state` answers the narrowed question complete
     (uncapped) at **−77.7%** vs the single-term capped view *(re-measured 2026-08-15; −78.4% at the
     wave — the AND answer is byte-identical across the two binaries at 985 tok, so the whole move is
     the single-term baseline getting smaller)*; on this repository's frozen pairs the G3 gate holds
     6/6 gold lines. When the agent knows a second term, `--grep` is now firmly token-positive.
- *(historical, 2026-06-20)* **`--grep` was +19.7% / −11.2%** — published deliberately as the
  anti-headline. `--grep` is not a token reducer, and saying so is cheaper than being caught.

The benchmark states its own scope limit, and it is worth repeating verbatim in spirit: the token
baseline is *a model of a naive agent read* — a documented, auditable proxy, not a live agent trace —
and these numbers prove **cheaper and faster, not better outcomes**.

### The MCP server's standing schema cost (measured 2026-08-10)

The CLI and the MCP server answer the same questions. The MCP path costs more, and **almost all of
the difference is a term nobody counts**: the server advertises 30 verbs, and their names,
descriptions and JSON schemas sit in the model's context *every turn, whether a verb is called or
not*. The CLI costs nothing until it is invoked.

**Instrument.** Drive `ripwire . --mcp` over stdio (`initialize` → `notifications/initialized` →
`tools/list`), serialize the returned `tools` array compact, and convert bytes to tokens with this
repository's own calibration table (`src/serialize.h:478-505`, measured against `o200k_base`).
Raw bytes plus argv are the instrument; tokens are the user-facing unit.

| | bytes | est. tokens |
| --- | --- | --- |
| `tools` array, compact (30 verbs) | 36,717 | **11,844 – 14,687** |
| one `--for` answer on `src/` (CLI) | 7,428 | ~3,020 |

The token figure is a **band, not a point**, because the payload is a mixture: **55.3% of those
bytes are English prose** (the tool descriptions), and the rest is JSON structure. The low end
applies this table's measured `Json` rate (3.10 B/tok, n=108 — but that corpus was
structure-heavy `package.json`/`tsconfig.json`); the high end applies the prose rate (2.56) and the
unknown-language mid-band (2.50). The composition argues for the upper end. **All of it is an
estimate** (`docs/ARCHITECTURE.md` §4) — a crude bytes/4 rule reads 9,179 and is low by ~55%, which
is why it is not used here.

So the standing cost of registering the MCP server is roughly **4–5× a typical answer, paid every
turn.** That is the finding.

**Two things this measurement does *not* say, both of which would be easy to imply:**

- **Per-response framing is nearly free.** The same `for` query costs 8,288 bytes as a complete
  JSON-RPC frame against 7,428 bytes on stdout — **1.12×**. JSON-string escaping and round-trip
  framing are real but negligible next to the standing cost.
- **The two `for` paths are not the same bundle, so that 1.12× is not a content-parity ratio.**
  On an identical corpus and query the MCP verb returned **13 ranked symbols to the CLI's 25**, with
  no `churn=`/`amp=` quality lens and no `est_tokens` self-report. The MCP verb documents itself as a
  signatures-only inventory, so this is by design — but it means the near-1:1 byte ratio is a
  coincidence of two different products, and a per-response ratio is not a like-for-like comparison.
  Only the standing cost above is quoted as a headline, and it needs no such caveat.

**Where the MCP still wins,** and this is not a footnote: agents that cannot shell out at all, and a
warm index held across calls where a cold CLI invocation might not have one. The conclusion is
*prefer the CLI where the agent can shell out, and here is the number* — **not** "remove the MCP".
This is why `ripwire wrap opencode` leads with the CLI recipe and offers MCP as the alternative:
opencode ships a `bash` tool, so it can pay zero.

**Reproduce:**

```
ripwire . --mcp                      # stdio; send initialize, notifications/initialized, tools/list
ripwire src --for="how are call edges resolved"
```

Byte counts are stable across repeat runs and across separate server processes (verified; the
determinism contract covers both paths). Count **bytes, not characters** — ripwire's verb
descriptions use multi-byte punctuation, and the character count of the same payload is 36,564.

### README-grade rows, re-measured on this repository (2026-08-08)

The row above carries a private-corpus caveat. These don't: every byte count below is `wc -c` on
this tree, at this binary, and reproducible by running the command shown. A row qualifies for the
README table only if it clears three bars: it is an everyday agent moment (not a constructed best
case), the same correct answer is verified present on both sides (named below, not asserted), and the
ratio is published as a range — the cheap end and the honest end of "what would an agent actually
read" — never the single most flattering number. Tokens ≈ bytes/4 throughout, per §1's instrument
note. The original four ran after `git merge --ff-only main` picked up density-wave lanes D/D2
(`7558fd9`/`2d8891b` — route-note dedup, terse panel legend, `--expand` cheapest-complete-answer
serving); the six added in lane E2 (below the rule) ran at `ec4b4ba` or later, same binary family, so
all ten measure the current build, not a pre-wave one.

| Moment | Command | ripwire | naive read | savings |
| --- | --- | --- | --- | --- |
| Orient me in this repo | `ripwire .` | **22,571 B** | 80,267–101,738 B (`README.md`, or `README.md`+`docs/ARCHITECTURE.md`) | 3.6×–4.5× |
| Where is X handled? | `ripwire . --for="where is the cache staleness check for the MCP index"` | **7,501 B** | 19,463–80,037 B (`grep -rn stale src/*.h src/*.cpp`, or that grep + reading `src/mcpindex.h` whole) | 2.6×–10.7× |
| What do I already know? | `ripwire . --recall="why is std::map banned in this codebase"` | **61,064 B** | 1,781,685 B (every markdown file this repo carries — 119 files, the same population `--recall`'s own header counts as "of 120 document files") | 29.2× |
| Set me up for this task | `ripwire . --pack-task="add a new lint rule to cachelint.h"` | **8,512 B** | 65,378–320,597 B (the two obviously-relevant files + a locating grep, or every file the bundle itself cites, whole) | 7.7×–37.7× |
| Show me this one function | `ripwire . --expand=mergeCachePack --top-k=0` (body alone; also verified on `buildGraph`) | **1,038–65,908 B** (body alone) / 23,675–88,547 B (default bundle, `mode="bundle"`, ranked neighborhood riding along) | 173,647–695,888 B (the whole file the symbol lives in) | 2.6×–670× (body alone) / 2.0×–29.4× (bundle) |
| Who calls this function? | `ripwire . --callers=langOfPath` | **2,326 B** | 160,989–207,359 B (`grep -rn langOfPath src/` — 2,010 B, mostly false positives — plus the 2–3 files opened to tell a real call from a comment mention) | 69.2×–89.1× |
| Is it safe to change this? | `ripwire . --impact=coversOrEquals` + `ripwire . --uses=coversOrEquals` | **5,125 B** | 73,661 B (the two files `--uses` names, `src/atoms.h` + `src/lintrules.h`, read whole) | 14.4× |
| I changed these files — which tests, what blast radius? | `ripwire . --situ` (diff: `src/graph.h`, `src/clones.h`) | **1,632 B** | 11,926–529,245 B (`git diff` + `grep -rn 'graph\.h\|clones\.h' test/` — 11,926 B before opening anything — up to every one of the 41 grep-hit files opened, 529,245 B) | 7.3×–324.2× |
| Review this PR/diff | `ripwire . --pr-context=HEAD~6` | **7,437 B** | 19,298–204,294 B (`git diff HEAD~6` alone, or that diff + the 6 touched files read whole) | 2.6×–27.5× |
| I have a stack trace | `ripwire . --from-trace=trace.txt` (7-frame trace, real symbols) | **5,718 B** | 497,104–1,192,992 B (grepping the 7 frame names — 5,150 B — plus the innermost file opened, or both files the trace touches) | 86.9×–208.6× |

**Re-measured 2026-08-22, COMPACT conceptual serving (pre-registered above, the T3 route-narrowing
round):** the "Where is X handled?" query is a conceptual phrase, so it routes subtoken+body and the
row's command now serves the COMPACT bundle — **8,563 B** at this binary
(`bundle="compact" bodies="0" reason="compact-route"`), **2.3×–9.3×** against the same naive read. It
still names `mcpStale` in `src/mcpindex.h`, and the `<hops>` section carries that symbol's one-hop
callees, so the map still terminates on the right symbol; what it no longer does is prepay the body.
`--auto-bodies` restores the pre-compact shape at **14,397 B**, and `--signatures-only` the
signatures-only one at **7,470 B** (2.6×–10.7×) — the two flags bracket the compact default, which is
the honest way to read it. PRIOR PINS, kept as the record rather than overwritten: 13,859 B was the
T3 terminal-by-default measurement of 2026-08-12 (`bundle="auto" bodies="3"`, 1.4×–5.8×) with
`--signatures-only` at 7,196 B, and the 7,501 B figure in the row above is the pre-T3 measurement of
2026-08-08.

**Same-answer verification, one line per row:**
- **Orient** — both surface the pipeline's own core files (`ingest.cpp`, `graph.h`, `serialize.h`) as
  central: ripwire ranks them into the first screen (positions 5, 7, 11 of the flagless map); the two
  docs name them explicitly in `docs/ARCHITECTURE.md` §1 ("The pipeline").
- **Where is X handled** — both name `mcpStale` (`src/mcpindex.h:633`) as the staleness check: it is
  the 5th ranked symbol in the `--for` bundle, and the only match in `src/mcpindex.h` whose signature
  is literally `inline bool mcpStale(...)`.
- **Set me up** — both name the same three touch points: `src/cachelint.h::cacheFriendliness` (the
  existing cache-lint rules to imitate), `mergeCachePack` (`src/main.cpp:1787`, the dispatch that
  folds a new rule's findings into `--lint`, called from `runLint`), and the `src/lintrules.h` span
  helpers (`langOfPath`, `collapseEnclosed`, `contains`, `coversOrEquals`) `cacheFriendliness` itself
  reuses.
- **Show me this function** — both hand back `mergeCachePack`'s (or `buildGraph`'s) complete,
  unmodified body: `--expand`'s `<bodies shown="1" total="1" capped="0">` on the first, byte-identical
  source on the second — nothing paraphrased or truncated. The two forms disclosed in the row aren't
  two different answers, they're the same body at two honesty-disclosed radii: `--top-k=0` is the
  function alone, a bare `--expand=SYM` adds the ranked-neighborhood map. That addition costs almost
  exactly the same regardless of which function you ask for — 22,637 B on `mergeCachePack`, 22,639 B
  on `buildGraph` — confirming it's a fixed floor (the default top-200 map), not per-function
  variance, which is why the lean form's ratio swings so much wider (2.6×–670×) than the bundle's
  (2.0×–29.4×): stripping a near-constant floor off a small body inflates the ratio for exactly the
  functions where the floor would otherwise have dominated the number.
- **What do I already know** — both name the same rule: `--recall`'s top-ranked doc (`AGENTS.md`)
  states it verbatim — "No `std::map` / `std::unordered_map`" with its replacements (`HashMap<>`,
  `gtl::btree_map`, `dynamic_map`) — and `CONTRIBUTING.md`'s container rule (not itself top-8 for this
  phrasing) carries the fuller reasoning. Disclosed, not hidden: an agent who already knew to grep
  `std::map` across every `.md` file would find the three genuinely relevant docs
  (`CONTRIBUTING.md`+`AGENTS.md`+`CLAUDE.md`, 28,795 B) cheaper than `--recall`'s 61,064 B — but that
  presupposes knowing the exact term in advance, which is the premise "what do I already know"
  explicitly does not grant. The naive number here prices the agent who doesn't have that shortcut:
  every doc in the repo, the population `--recall`'s own header counts against.
- **Who calls this function** — both name the same 2 real callers (`src/lintrules.h:185`,
  `src/lintrules.h:772`/`:781`, `src/atoms.h`'s own use is a different call chain feeding the same
  span check) that `--callers` returns; `grep -rn langOfPath src/` returns those same lines PLUS five
  more files (`src/gitmine.h`, `src/graph.h`, `src/nonlocalstate.h`, `src/qualitypanel.h`,
  `src/serialize.h`) whose only "hit" is a comment mentioning the name, not a call — a naive agent has
  to open files to find that out, which is what the naive number prices.
- **Is it safe to change this** — both name the same direct call sites (`src/atoms.h:130`,
  `src/lintrules.h:864`) `--uses` returns. Disclosed: `--impact`'s own transitive reach is wider than
  what `--uses`'s file list covers — it also touches `src/ensemble.h`, `src/qualitypanel.h`, and
  `src/main.cpp` two hops out — so a naive read that stops at the direct-use files (the naive number
  here) under-answers "is it safe" exactly the amount `--impact` is for; pricing it wider would only
  widen the ratio further in ripwire's favor.
- **I changed these files** — both surface the same 6 real test harnesses `--situ`'s blast-radius walk
  finds (`test/clonelex_harness.cpp`, `test/type3clone_harness.cpp`, `test/cloneband_harness.cpp`,
  `test/connectcore_harness.cpp`, `test/includeprecise_unit.cpp`, `test/rustimport_unit.cpp`).
  Disclosed, not hidden: `grep -rn 'graph\.h\|clones\.h' test/` — the naive move — surfaces 41
  candidate files (mostly noise) containing only 4 of those 6; the other 2 reach `graph.h`/`clones.h`
  only through the compiled call graph and are invisible to any filename grep, so even the "honest
  end" of the naive number (every one of the 41 candidates opened) doesn't reach full parity with
  `--situ`'s answer — a completeness gap in ripwire's favor that the byte ratio alone doesn't capture.
- **Review this PR/diff** — both name the same co-change signal for the changed files: `--pr-context`'s
  bundle lists `test/regression.sh`, `src/main.cpp`, and `docs/COMMANDS.md` as partners usually edited
  alongside `README.md`/`docs/EVALS.md` that this diff (`HEAD~6`..`HEAD`) did NOT touch — a real
  reviewer question ("did they forget something?") a raw `git diff` read cannot answer at all, since
  it has no memory of what usually changes together.
- **I have a stack trace** — both resolve the same 7-frame call chain to the same real definitions:
  `--from-trace` binds all 7 frames `resolved_by="name"` to their actual signatures
  (`collectChildren`→`ur_walkTree`→`runWalkGroups`→`astQueryGrouped`→`builtInLintCaptures`→`runLint`→
  `main`), rank-1's full body included; `grep` for each of the 7 names returns the same definition
  lines, mixed with call sites and comments in the same two files, which the naive number prices as
  opened whole to tell them apart.

**Reproduce any row:** `cd` to this repository, run the command in that row, `wc -c` the output; the
naive side is the `grep`/`wc -c` invocations named above, run from the same root. The stack-trace row's
`trace.txt` isn't a repo file — it's seven lines of the form
`#N  0xADDRESS in NAME () at PATH:LINE` naming the real chain above; write it yourself to reproduce.

### The `--expand` small-file inversion, resolved (density-M6, `e6f173d`/`7558fd9`)

§7 records the inversion this fixes and keeps it — a negative result stays recorded even after the
fix. What changed: a bare `--expand=SYM` no longer blindly emits the bundle. It measures the default
bundle (ranked map + bodies, rendered exactly as it would be emitted) against the requested symbols'
whole-file bytes and serves the smaller, disclosed on the `<ctx>` root as
`mode="whole-file"`/`mode="bundle"` with `reason="file NB &lt; bundle MB"` (or the reverse). Re-run on
`pageRankDouble` at this head:

| Form | Bytes | Disclosure |
| --- | --- | --- |
| Old unconditional bundle (as measured 2026-08-01, no auto-selection existed) | 27,890 B | none — always the bundle |
| Current `--expand=pageRankDouble` (auto-selected) | **5,911 B** | `mode="whole-file" reason="file 5559B &lt; bundle 27916B"` |
| Raw file (`src/pagerank.cpp`) | 5,559 B | — |

The 5.65×-over-the-file loss is gone: the served form now costs **1.06×** the raw file (envelope +
CDATA overhead only), not 5.65× more than it. The inversion is self-correcting — the tool notices its
own bundle would cost more than the file and stops emitting it — which is why this is filed as a
*resolution*, not a retraction: the original measurement was correct for the binary it measured, and
`test/expandmodecheck.sh` (registered in `test/regression.sh`) now gates both arms so it cannot
regress silently in either direction.

### Density-wave savings, one-line before/afters

Two more density-wave fixes, cited by their merge commits, each re-verified at this head:

- **Route disclosure emitted once** (`dbda0ec`, merged `7558fd9`, lane D): `--for=pageRankDouble` on
  this repo went from 6,934 B to 6,821 B (**−1.6%**, −113 B) by dropping the duplicated `routed: …`
  text that used to appear in both the `route=` attribute and the legend comment. Re-measured at this
  head: still **6,821 B**, unchanged since the fix landed — the `route=` attribute is the sole
  surviving copy.
- **Quality-panel legend terse by contract** (`2e8835f`, merged `7558fd9`, lane D): on this repo,
  `--quality-panel`'s leading legend comment went from 7,179 B to 4,087 B (**−43%**), and the whole
  emission from 24,473 B to 21,381 B (**−12.6%**) — the legend had been re-emitted in full on every
  call and, at audit time, out-sized the panel's own payload. Re-measured at this head: comment is
  still **4,087 B** (fixed text, unchanged in size), against a **17,967 B** total on this repo's
  current (smaller) ranked set — the comment-vs-payload ratio the fix targeted still holds.

### `--callers` / `--impact` / `--uses` shared legend, and `--test-gate`'s, terse by contract (lane/fa-legend, 2026-08-28)

**C1 — the three near-duplicate graph-count essays.** Measured on `rootRelPathsLegend`, a real,
unambiguous, well-connected symbol in `src/graphlegend.h` (**not** `main`, which has 76 in-corpus
definitions in this tree and collapses the payload). Root cause: `kCallHierarchyLegendOpen`,
`kImpactLegendOpen`/`kImpactImportTierLegend` and `kUsesLegendOpen` (`src/graphlegend.h`) each carry
their own hand-written prose, and every one of them pays in full for the shared
`graphCountDisclosure()` essay (`kGraphCountFloorLegend` + `kCallCountUnitLegend`) — the same ~2.3 KB
floor-and-unit clause is reused **verbatim across seven call sites** (`--callers`/`--callees`,
`--uses`, `--impact`, `--edit-check`, `--graph-query`, `--pr-context`), so `CLAUDE.md`'s own
`--impact` + `--uses` blast-radius pairing pays for it twice back to back.

| argv | total B (before → after) | legend B (before → after) | payload B | legend % (before → after) |
| --- | ---: | ---: | ---: | ---: |
| `--callers=rootRelPathsLegend` | 4,474 → 3,643 | 3,179 → 2,348 | 1,295 (unchanged) | 71.1% → 64.5% |
| `--impact=rootRelPathsLegend` | 6,510 → 5,605 | 3,683 → 2,778 | 2,827 (unchanged) | 56.6% → 49.6% |
| `--uses=rootRelPathsLegend` | 6,330 → 5,327 | 4,303 → 3,300 | 2,027 (unchanged) | 68.0% → 61.9% |

Every payload byte (the document minus its leading comment run) is **byte-identical before and
after** — verified by diffing `<callers>…</callers>` / `<impact>…</impact>` / `<uses>…</uses>` (and,
as collateral verification on the same shared constants, `--callees`, `--graph-query` and `--verify`)
captured from the pre-fix and post-fix binaries on this repository; only explanatory prose moved,
never a fact or a row. Two verbs this change also improves as a side effect, not separately audited
here: `--edit-check` and `--pr-context` (the latter's own legend fell from 91.3% to well under that on
a representative `--pr-context=HEAD~1` capture).

**Shape chosen: compact the DEFAULT** (the `--quality-panel` shape), not an opt-in `--legend=compact`
flag — these seven verbs have no compact-legend flag today, and `CLAUDE.md`'s own guidance is to
prefer compacting the default over adding a flag surface across seven verbs for one fix.
`test/graphlegendbudgetcheck.sh` red-first-verified against the 1dc7b01 binary (`--callers` 3,179 B >
2,700 B budget, `--impact` 3,683 B > 3,100 B, `--uses` 4,303 B > 3,600 B — all FAIL) and green at this
head; `test/legendcoveragecheck.sh` and `test/floormarkcheck.sh` (the exact cross-verb anchors —
`is a FLOOR, never a total`, `most-vexing-parse`, `COUNTING UNIT`, `graph-query and pr-context counts
are DISTINCT SYMBOLS`, `pr-context's dependents=`, `map header's edges= is a unit again different —
distinct (caller,callee) PAIRS`, `not call reach`) both ALL PASS unchanged.

**C2 — `--test-gate`'s legend on an empty diff.** Measured with `--test-gate` on a clean working tree
(the honest zero case, where the payload is near-zero *by construction*): **1,689 B legend against a
299 B payload (84.7%)**, root cause `kTestGateLegend` (`src/situ.h:682`). A relative `legend<=payload`
invariant is the WRONG ratchet here (unlike C1's real row content, an empty diff's payload cannot grow
to meet it), so `test/testgatelegendbudgetcheck.sh` ratchets the **absolute legend byte count**
instead, on a fixed `--test-gate=src/model.h` fixture (stable across the caller's own working-tree
dirtiness): pre-fix **1,689 B**, post-fix **1,332 B** (**−21.1%**, −357 B), payload byte-identical
(299 B on the empty-diff case; 3,848 B on the `src/model.h` fixture, both before and after). Red-first
verified against the 1dc7b01 binary (1,689 B > 1,500 B budget — FAIL) and green at this head.
`test/testgatecheck.sh` arm (g) — the exact cross-verb unit-collision phrases (`UNIT: untested=
here counts impacted SYMBOLS`, `call EDGES`, `defs a gate lights`) shared with `--seams` and
`--flip` — ALL PASS unchanged.

**Declined, spec'd as follow-ups (both live in `src/main.cpp`, outside this lane's file scope):**
`--quality-delta` (7,143 B legend / 2,497 B payload / 74.1%, `src/main.cpp:6129`) and `--safe-delete`
(4,885 B / 332 B / 93.6%, `src/main.cpp:7528`). The MCP `tools/list` schema (37,925 B/session,
descriptions 21,172 B, `src/mcp.h`) is larger and riskier and is spec-only, not attempted.

### The done-checkpoint verbs (2026-09-02) — the C1/C2 follow-ups, executed

**Why these three and not the biggest legend in the tree.** Per-session call-mix telemetry
(`~/.ripwire/substitution.jsonl`, schema `docs/SUBSTITUTION_METER.md`) over a two-week window ranks
`--quality-delta` FIRST among ripwire invocations — ahead of `--for`, `--quality-ack` and
`--test-gate`, in that order — with the MCP transport last at zero. That ordering is the whole
selection criterion: `--quality-delta` is the verb `CLAUDE.md` tells every agent to run before calling
work done, so its fixed text is paid at every checkpoint, while the MCP `tools/list` schema
(43,392 B/session) is bigger but is not on any measured path and was deliberately left alone. Only the
RANKING is published here; absolute usage levels stay local by standing policy.

**Measured before/after** (pre-fix = the `8e186bb` binary, post-fix = this head; both run against the
same pinned `8e186bb` checkout so working-tree dirtiness cannot move a number). Legend = the sum of
the LEADING contiguous `<!-- … -->` blocks, `test/panellegendcheck.sh`'s method.

| shape (argv, run against a checkout pinned at `8e186bb`) | legend B before | after | Δ | payload B |
| --- | ---: | ---: | ---: | ---: |
| `--quality-delta` | 8,574 | **3,838** | −55.2% | 572 |
| `--quality-delta --exclude=bench/external --scope='src/*'` | 10,512 | **5,112** | −51.4% | 859 |
| `--quality-delta=HEAD~1..HEAD` (the ref-pair form) | 8,574 | **4,254** | −50.4% | 651 |
| `--quality-delta` on a dirty fixture (6 findings incl. a clone group) | 8,574 | **3,376** | −60.6% | 771 |
| `--quality-delta` after a `--quality-ack` round trip (acked=6) | 8,574 | **3,783** | −55.9% | 273 |
| `--safe-delete=parseArgs` | 4,112 | **3,652** | −11.2% | 343 |
| `--test-gate` on a clean tree (the empty-obligation case) | 1,332 | **1,111** | −16.6% | 299 |
| `--test-gate=src/model.h` (rows present) | 1,332 | 1,332 | 0 | 2,791 |

**Payload byte-identical, diff-proven with a non-zero row count** on every shape above (the empty-diff
trap): the document minus its leading comment blocks is byte-for-byte the same from both binaries, at
6–42 element tags per document. The `--quality-ack` round trip also writes a byte-identical
`.ripwire_quality_acks` ledger and byte-identical stderr.

**The mechanism — emit-on-presence, not deletion.** No disclosed limit was dropped and no fact moved
to `docs/COMMANDS.md`. What changed is that a definition is emitted **when the thing it defines is in
the document**, generalizing the rule `kScopeLegend` already followed alone: one `baseline=` marker
sentence instead of five, the `at=` sentence only in the forms that carry `at=`, the identity and
re-keying paragraphs only when their attribute families are on the root, the row and clone-row
dictionaries only when there are rows, the `foreign-acks=` paragraph only when it is non-zero, and
`--test-gate`'s page-invariance contract only when the document has rows for it to govern.
`--safe-delete` names the one `risk=` value this run reports rather than a glossary of all three, and
its `defs=` union and `ambiguous_callers=` caveats print only when `defs>1` / `ambiguous_callers>0`.

**Coverage went UP, not down.** The definitional predicate `test/legendcoveragecheck.sh` arm (B) uses
(the attribute name immediately followed by `=`) reports **zero** undefined root attributes on all
four `--quality-delta` shapes, against 2–6 before: this lane closed `sa@key`, `sa@why`, `r@was`,
`r@now`, `quality-delta@minor`, `quality-delta@stale` and `quality-delta@churn`, none of which
`legendcoveragecheck`'s roster reaches because it runs only the bare working-tree form.

**The ratchet is absolute bytes, and the arithmetic is why.** `test/donelegendcheck.sh` pins seven
shapes by absolute legend size and reports the fraction as INFO. A `legend<=payload` arm is
unsatisfiable on the case these verbs exist to handle well — a clean tree's payload is near-zero by
construction — so at 40% of a 572 B payload the whole legend would have to fit in 381 B, shorter than
the list of the ten measured kinds. **A ≤40% relative ceiling for `--quality-delta` and ≤50% for
`--safe-delete`/`--test-gate` were considered and are recorded as UNREACHABLE rather than as missed
work**: post-fix fractions are 87.0% / 91.4% / 78.8% on the clean cases and 81.4–86.7% wherever
the payload is real. The same reasoning `test/testgatelegendbudgetcheck.sh` recorded in 2026-08-28.
`test/donelegendcheck.sh` red-first-verified against the `8e186bb` binary: **20 failing assertions**
(7 budgets, 9 emit-on-presence, 4 coverage), ALL PASS at this head. Its seven shapes are all measured
on temp git fixtures the gate builds itself, including the ref-pair one — this repo's own
`HEAD~1..HEAD` names a different diff after every landing, so a budget on it would be a ratchet whose
value depends on whoever committed last.

**The residual, named.** `--safe-delete`'s remaining 3,652 B is **1,679 B of the shared
`rw::graphCountDisclosure()` tail**, left byte-identical on purpose: `test/floormarkcheck.sh` arm (4)
asserts that tail is byte-identical across CLI and MCP on seven other verbs, and a private shorter
copy here would be exactly the dialect divergence that gate exists to catch. Compacting it is a
`src/graphlegend.h` change touching eight verbs at once, and is a separate round.

---

## 6. Correctness and quality instruments

### The gate suite

`test/regression.sh` is the authoritative list. It runs three tiers: inline contract checks
(determinism run four times for byte-identity, cache transparency, the golden snapshot, architecture
tags, wrap, stable-order defaults), seven individually invoked standalone gates (`g1freshcheck`,
`skillscan`, `htmlexport`, `compresscheck`, `handoffcheck`, `releaseinstallcheck`,
`taskroutecheck`), and a single loop
naming **519 gate scripts**, all of which exist on disk.

`python3 test/pargates.py . ./build/ripwire -j 6` runs the same scripts in parallel so a full
verification fits in one sitting. It does not modify `regression.sh`.

`test/manifestcheck.sh` fails if a committed top-level `*check.sh` is missing from `regression.sh`,
so the list cannot rot.

### The TOML config-key tier — shape coverage, and the ceiling that was declined

**Instrument:** `test/tomllangcheck.sh` over `test/tomlfix/pyproject.toml`, plus the shape/size probe
described below. **Corpora:** the 90-repo breadth corpus (`bench-assets/r4/repos`, 321 `.toml` files)
for the design measurements; `test/tomlfix/` for the pinned per-shape assertions. **Binary:** the tier
landed at `kParserVer 59`.

The corpus is what chose the design, so it is recorded rather than summarized away:

| Measurement | Value |
| --- | --- |
| `.toml` files / parse-clean | 321 / 270 — the real failure rate is **~0.3%**, because 50 of the 51 "failures" are cpython's `test_tomllib/data/invalid/` deliberately-malformed fixtures |
| Size p50 / p90 / p99 / **max** | 277 B / 3 578 B / 21 449 B / **57 759 B** |
| Shape counts | plain `key =` 6 594 · `[table]` 2 561 (258 files) · array value 1 270 · `[[aot]]` 300 (75 files) · inline table 213 · dotted key 197 |
| `[table]` header dotted depth | 1:446 · **2:1421** · 3:415 · 4:191 · 5:87 · 6:1 |
| Key depth measured from the document ROOT | d1 6.2% · **d2 38.3%** · d3 72.1% · d4 89.8% · d7 100% |

That last row is the whole argument. JSON's rule — top-level plus second-level object keys — is a
**root-relative** cut, and applied to TOML it would capture **38.3%** of keys and miss every key under
a 2-dotted table, which is the shape 1421 of 2561 real headers have. So the TOML lane cuts at the
**table header** instead: a header is one symbol under its full dotted name, and its keys sit one
level below *it* at any header depth. `tomllangcheck`'s "keys under a depth-3 header" arm is red
against any literal port of JSON's rule, which is why that arm exists.

**Floors pinned by the gate** (each an arm, all non-vacuous behind presence guards): every emitted
symbol is `t="sec"` · `edges=0` · headers carry their full dotted spelling · keys under
`[tool.ruff.lint]` are present · inline tables are not descended *while their owning key is* · a
dotted key is one symbol, never split · two `[[aot]]` headers are two defs · `--grep` reports the
dotted header as the enclosing symbol both cold and through a cache round-trip · determinism.

**Verified at corpus scale:** all 321 files index clean under the G1 sanitizer stack — `files=321
symbols=9641 edges=0`, zero stderr, zero ASan/UBSan reports — and the 90-repo map is byte-identical
across two cold runs and a warm run. On this repository, which contains no `.toml`, the default map is
**byte-identical** before and after the tier.

**No TOML-specific ceiling, and the absence is the finding.** JSON needed `kMaxJsonConfigBytes` (256 KB)
and `kMaxJsonNestDepth` (512) because a large `.json` is usually *data* wearing a config extension, and
because its error recovery goes superlinear — 43 s on 100 KB of unclosed `[`. Neither holds for TOML.
The observed maximum is 57 759 B, so a ceiling could not be placed both above it and below the generic
4 MB skip without being unreachable; and every adversarial probe is **linear**: `[`×100 000 = 17.4 ms,
dotted key ×50 000 = 7.0 ms, 50 000 `[[aot]]` = 58.7 ms, a 2 MB unterminated string = 21.7 ms — TOML is
line-oriented, so a malformed line resynchronizes at the newline instead of nesting. The vendored
external scanner is stateless (`create()` returns `NULL`, `serialize()` returns 0, never allocates), so
it adds no hazard to weigh either. A ceiling here would fire only on a file no corpus contains. The
gate pins the *decision* from outside by indexing a 216 KB `.toml` — 3.7× the corpus max, and past
where the JSON ceiling would sit — so one cannot be added later without the gate saying so out loud.

### The YAML config-key tier — sequence transparency, and the guard that is memory-safety load-bearing

**Instrument:** `test/yamllangcheck.sh` over `test/yamlfix/{workflow.yml, multidoc.yml, tasks.yaml}`,
plus the corpus-scale run described below. **Corpora:** the 90-repo breadth corpus
(`bench-assets/r4/repos`) for the design measurements (the 2026-08-10 probe measured 4 449 YAML files /
34 209 keys; this round's crawl of the same trees collected 4 428 `.yml`/`.yaml` files); `test/yamlfix/`
for the pinned per-shape assertions. **Binary:** the tier landed at `kParserVer 61`.

**The design number: JSON's root-relative depth rule captures 27.1% of real YAML keys, and the 25.3% of
ALL keys that sit directly inside a sequence element — the `steps:` / `containers:` / `tasks:` shape — it
drops 100%.** YAML's rule is mapping-depth ≤ 2 with sequence levels **transparent**, which captures
44.0% on the same corpus. Block and flow mappings count alike (flow is a presentation style of the same
mapping node). The remaining semantics were fixed from measured frequency before implementation (PLAN
2026-08-10) and each is a gate arm: anchors (1.73% of files) are part of the value, never symbols;
aliases (1.55%; alias-as-key measured **0** in the corpus) are dropped, never expanded; the `<<:` merge
key (0.22%) is dropped rather than minting a symbol named `<<`; multi-document streams (0.11%, max 5
docs) re-enter each document at depth 1; block scalars (20.5% of files) are single value tokens and are
never descended — **384 corpus block scalars contain key-like text a line regex would mint symbols
from**, which is the argument for a real parser; duplicate keys are both minted (`overloads=2`);
non-string keys keep their literal source text (GH Actions' `on:` is a YAML-1.1 bool, and `on` is what a
user greps for); quoted keys keep their quotes (the TOML posture, disclosed).

**Verified at corpus scale under the G1 stack:** the breadth corpus's 4 428 YAML files index to
`files=4424 symbols=118153 edges=0` with **zero stderr and zero sanitizer reports**, byte-identical
across two cold runs and a warm run, `xmllint --noout` clean — and the accounting closes exactly:
4 424 indexed + 3 over the 512 KB ceiling (counted in `skipped_oversize=`) + 1 under a crawl-pruned
directory = 4 428.

**The ceiling is 512 KB, deliberately not JSON's 256 KB.** `.yml` has JSON's hazard (a machine-written
data class behind a config extension) so it gets a ceiling, but JSON's line would drop real
hand-maintained config — NeMo's `cicd-main.yml` is 293 KB. The gate pins both sides: a ~300 KB file
(over JSON's line) stays indexed, a ~600 KB file is skipped *and counted*.

**The nesting guard is memory-safety load-bearing, and it was reproduced red-first.**
tree-sitter-yaml v0.7.2's external scanner `serialize()` writes 4 bytes per open block indent level
behind a guard that proves 1 byte of headroom; at the vendored tag, a 253-level deep-indent fixture
parses (`10 + 4×253 = 1022` fits) and one more level aborts —
`Assertion failed: (length <= 1024), function ts_parser__external_scanner_serialize` (SIGABRT) — while
the same file under `NDEBUG` performs the corrupting write silently (observed SIGSEGV downstream). ASan
alone cannot flag it: the write lands 2 bytes past `debug_buffer` *inside* the `TSLexer` struct, an
intra-object overflow. Two independent layers now stand in front of it, plus a family gate behind:
ingest's `yamlNestsTooDeep` prescan (`kMaxYamlNestDepth`, an over-approximation that can only
over-count, so the failure direction is a disclosed skip) refuses such files before any parse; the
vendored scanner carries the one-line bounds fix (`third_party/patches/yaml/001`, reverse-apply
drift-gated); and `vendorpatchcheck` arm H audits the defect *class* — a per-iteration guard narrower
than the widest write in its loop — across every vendored scanner, unclassified scanners failing loudly.

**A second scanner defect surfaced only at corpus scale.** The first full-corpus G1 run aborted on
`cur_col++` — an `int16_t` cursor implicitly truncating on real 228 279-character lines (VCR-cassette
fixtures, legitimately under the ceiling). Patched as `yaml/002` (explicit casts, the `swift/001`
remedy), with the map output verified **byte-identical on all 4 424 files** before vs after the patch.
A probe over three hand-picked fixtures would not have found this; 90 repos did.

**On repositories the tier does not serve, the change is visible but bounded:** this repository's own
`.github/workflows/*.yml` and test fixtures now index (the `grepcheck` repro arm records the
consequence and its resolution), and `.dSYM` debug-symbol bundles — 197 yaml-format relocation files
and zero real config in the private validation corpus — are pruned by name suffix, pinned by a gate arm.

### Swift shape coverage + TS #private — hand-port of stranded commit bb78f97 (2026-08-10)

**Instrument:** `test/swiftshapecheck.sh` over `test/swiftshapefix/{EnumsAndTypes,Members,ProtocolSurface}.swift`
(fixture-driven, 17 arms). **Corpora used for RE-MEASUREMENT (read-only, pinned to the exact SHAs
the original 2026-08-04 round used):** Alamofire@0455bfb (98 .swift / 469 total files) and
swift-nio@72973283 (554 .swift / 716 total files), at `bench-assets/swift/`.

This work originally landed at kParserVer 41 on a branch that was never merged to main — the code
was gone even though a `.ripwire_quality_acks` entry referencing this exact fix had already
reached main via an unrelated integration merge (a real ledger/code drift, corrected as part of
this port; see the commit for the updated ack). It is hand-ported here at kParserVer 60. Swift
gains `enum_entry`, `typealias_declaration`, `associatedtype_declaration`,
`protocol_property_declaration`, and a builtin-operator-token alternation in
`function_declaration`'s `name:` field; TypeScript's `tags.scm` gains the `#private`
method/field-arrow/call-ref coverage JS already had (0 sites on main before this port — a real
sibling-completeness gap, not a new shape); the shared `finalSegment()` helper gains a leading-`'<'`
carve-out so a Swift operator-function name (`<`, `<+>`) is not erased to `""` by the generic
type-argument strip.

**Re-measured, not carried forward.** AST-level ground truth via `--match` (single-capture
queries, `hits_capped="0"`, i.e. exact, parsed from the `<match>` element rather than grepped)
reproduced the original round's five figures EXACTLY on both pinned corpora:

| shape | Alamofire | swift-nio |
| --- | --- | --- |
| enum case (`enum_entry`) | 247 | 1 209 |
| typealias | 39 | 962 |
| associatedtype | 7 | 35 |
| protocol property requirement | 12 | 65 |
| operator function (builtin tokens; `(custom_operator)` alone still measures 0) | 4 | 62 |

Crawl-based before/after (pre-port binary = main@b598266/kParserVer 59, copied aside before any
port edit; post-port = this commit/kParserVer 60): Alamofire 5120→5429 symbols (+309), 26891→26957
edges (+66); swift-nio 16844→19177 symbols (+2 333), 36021→36515 edges (+494) — symbol deltas
match the original round's recorded `+309`/`+2 333` exactly; the Alamofire edge delta matches
exactly (+66); the swift-nio edge delta is +494 here vs +498 originally recorded, a 4-edge
difference not investigated further (nothing in this port touches call-edge resolution; most
likely unrelated resolver drift across the ~19 kParserVer versions between the two measurements).
**Noise, verified by an actual (file,name) symbol-identity set-diff, not eyeballed:** zero rows
removed on either corpus (Alamofire +220 distinct pairs, swift-nio +1 521), matching the original
round's "ZERO removed rows" claim exactly.

**The vendored `third_party/deps/swift/src/scanner.c` UBSan fix that rode the original commit was
deliberately NOT ported** (see `test/swiftshapecheck.sh`'s header) — nothing else under
`third_party/deps` carries a local patch today, and landing one bare would start a vendored-patch
convention with no drift gate behind it. The underlying bug is real: an isolated one-line Swift
fixture containing an emoji inside a raw `#"..."#` string reproduces the exact documented abort
(`scanner.c:820`, implicit conversion of codepoint 127881 to `uint8_t`, SIGABRT). It does **not**,
however, trigger on the actual pinned swift-nio@72973283 snapshot — a full ASan run over all 716
files (`LSAN_OPTIONS=suppressions=lsan_suppressions.txt ./asan/ripwire <dir>`) completed cleanly,
as did Alamofire and this repository's own fixtures/self-scan. The stranded commit's claim that
swift-nio's test files carry emoji in raw strings did not reproduce at this exact pinned SHA;
whether that content exists at a different swift-nio revision was not investigated. Swift fixtures
in this port (`test/swiftshapefix/`) contain no raw string literals at all, so they cannot
exercise the deferred bug either way.

The TypeScript `#private` half was also measured, not assumed: the wider 90-repo breadth corpus
(`bench-assets/r4/repos`, ~2 900 `.ts` files) shows the real signal confined to one vendored
dependency — ccxt's bundled ethers.js/noble-hashes port under
`ccxt__ccxt/ts/src/static_dependencies/ethers/` — with 15 `#private` method definitions and 45
`this.#x(...)` call sites (`--match`, exact, `hits_capped="0"`), 0 arrow-valued `#private` fields
(added for JS parity only, same as the original round). Several `sktime__sktime` files matched a
naive `#`-grep but are misleading: they carry a `.ts` extension while actually being ARFF-style
time-series **data** files (comment lines literally start with `#`), not TypeScript source — a
corpus-contamination trap of the same shape the original round's openclaw blanking-scan warning
describes, caught here by reading the files before trusting the grep.

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

### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`

An independent adversarial pass over `integration/wave2-2026-08-17` (34 commits ahead of `ab59ca8`),
directed *not* to re-run the green suite but to break the wave's claims: gates passing for the wrong
reason, silently changed semantics, degrade paths that lie. Instruments: a from-scratch build of the
base (`ab59ca8`) and of the head (`aa97c9e`) in throwaway worktrees, never sharing objects — the
mixed-binary discipline in `CLAUDE.md`, applied to the verification and not only to the work.

> Update 2026-08-19: every finding below that named a defect — the two pack-task findings (K1, K2) and
> the four path-coverage gaps (E1–E4, plus a fifth the fix surfaced: the pack-task JSON dialect) — was
> remediated in a follow-up lane and re-verified here by re-executing these same probes at the final
> head, from clean `--clean-first` rebuilds of both flavours. The task-named body now survives all 43
> rungs of a step-100 budget sweep (it was dropped on 31 of them), no section's kept-count decreases
> anywhere on that sweep, and all five path surfaces answer relatively with `root=` disclosed once.
> Suite at the final head: `gates=429 pass=427 skip=2 fail=0`, ASan+LSan clean, byte-deterministic,
> `xmllint` clean, `--quality-delta` gating 0 both against HEAD and across the whole wave as a ref-pair.
> The probe text below is left as written, describing the commit it was measured at.

**Mixed-binary cross-check, first.** The wave worktree's incrementally built `build/ripwire` is
byte-for-byte output-identical to a clean `--clean-first`-equivalent scratch build of the same commit
across 13 verbs (default map, `--lint`, `--hotspots`, `--clones`, `--grep`, `--for`, `--pack-task`,
`--tree`, `--communities`, `--seams`, `--quality-panel`, `--skipped`, `--report`). Every number below
is therefore about the wave, not about a stale object file.

**Probe 1 — unequal cache states. CLEAN.** The zero-cache-format-change claim is verified *in source*,
not asserted: `kParserVer` stays 65 and `kCacheVersion` stays 13 across the whole wave (the only
`ingest.cpp` change moves `looksBinary` to `ingest.h`). The four-cell asymmetry matrix, run with
isolated `TMPDIR` cache ladders on a scratch corpus, is byte-identical in every cell: new cold ==
new warm; new-on-a-cache-written-by-the-old-binary == new cold; old-on-a-cache-written-by-the-new-binary
== old cold. Root-relativization survives a stale cache because it happens at render time, not at
ingest time: `test/rootrelcheck.sh` run with the **new** binary against a cache the **old** binary
wrote is ALL PASS, and nine path-heavy verbs (including `--tree`, `--lint`, `--grep`, `--expand`) are
byte-identical cold vs. stale-cache.

**Probe 2 — vacuous-green hunt. Five of six gates proved decisive; one coverage caveat.** Each new or
re-pinned gate was re-executed against the pre-wave binary. `rootrelcheck` 41 FAIL, `churnjoincheck`
532 FAIL, `prconvergecheck` 15 FAIL, `qdrefpaircheck` 13 FAIL, `queryfilescancheck` 7 FAIL,
`packtaskmonotoncheck` 1 FAIL on exactly its load-bearing assertion (`NON-MONOTONIC bodies_kept: 2 ->
1 at budget=3500`). None of these can pass for the wrong reason.
`legenddriftcheck` is the caveat. Arm B (the synthetic known-positive) fires correctly. Arm A (live)
extracts **1 flag reference from 114 legends** on this corpus — the live arm's whole discriminating
power is one token (`--signatures-only`). It is not vacuous: fed the real live legend text against a
help table with that flag removed, the checker returns `DIRTY`. But three of its four extraction
patterns look for a literal `--flag` spelling, which **cannot appear in a well-formed XML comment**,
so only the prose pattern can ever reach real output. Recorded as narrow coverage, not a false green.

**Probe 3 — the pack-task budget lane. Two findings; the fix is real and its price was never
measured.** The
non-monotonicity is genuinely gone on the live corpus: the base binary shows `callers_kept` 20 → 13
going from `--token-budget=6000` to `8000`; the head binary is non-decreasing across the same ladder.
Both findings are about what that cost.

*K1 — monotone in COUNT, non-monotone in RELEVANCE.* On `packtaskmonotoncheck`'s own fixture, with
the task `"cliffprobe target function"`:

| `--token-budget` | base (`ab59ca8`) bodies | head (`aa97c9e`) bodies |
| ---: | --- | --- |
| 900 | *(none)* | **cliffProbeTargetFunction** |
| 1200 | **cliffProbeTargetFunction** | SmallOne, SmallTwo |
| 2000–4000 | **cliffProbeTargetFunction** (+SmallOne at 3000) | SmallOne…SmallFive |
| 4500+ | all six | all six |

Raising the budget from 900 to 1200 **deletes the body of the function the task literally names** and
substitutes one-line helpers, and it stays deleted through 4000. The base binary keeps it at every
budget from 1200 up. "Bigger budget, worse answer" is the exact defect the lane set out to remove; the
`count > rank-score > cost` tie-break relocated it from the counter to the content. The disclosure is
truthful throughout — the drop is named (`<!-- body omitted (over budget): cliffProbeTargetFunction -->`),
`total="6"` is restated from the true candidate set and `capped="1"` is honest — so this is a
retrieval-semantics finding, not a dishonesty finding. `packtaskmonotoncheck` cannot see it: it
asserts on counts only.

*K2 — `monotoneRoll` under-fills the budget, undisclosed.* A section that was itself capped is
charged its *whole* granted share and donates nothing forward. That is conservative and correct for
monotonicity, and the source says so; the cost was never quantified anywhere in the round record. On
this repository, task `"rank the call graph"`:

| `--token-budget` | base bytes (fill) | head bytes (fill) | base `callers_kept` | head `callers_kept` |
| ---: | ---: | ---: | ---: | ---: |
| 4000 | 7,708 (90.7%) | 6,548 (77.1%) | 11/20 | 8/20 |
| 6000 | 9,848 (77.3%) | 7,121 (55.9%) | **20/20** | **13/20** |
| 8000 | 16,113 (94.8%) | 7,812 (**46.0%**) | 13/20 | 18/20 |

(fill = emitted bytes against `budgetTokens × kMinBytesPerToken × kBudgetHeadroom`.) At the default
6,000-token budget the flagship one-call bundle now carries **seven fewer caller signatures** while
leaving ~44% of the budget unspent — and nothing in the output says the truncation was a policy
choice rather than a budget wall. Roughly a third of the byte reduction is the legitimate
root-relative path saving; the caller-count column is the part that is not.

**Probe 4 — the convergence-disclosure lane's residual. Verified, and its CAUSE is now pinned:
corpus, not ranker.** The residual
reproduces exactly, and a three-cell control isolates it:

| binary | tree | ranking-lane lenient recall@5 | MRR |
| --- | --- | ---: | ---: |
| `ab59ca8` | `ab59ca8` | **75.0%** | 0.694 |
| `ab59ca8` | `aa97c9e` | **71.9%** | 0.660 |
| `aa97c9e` | `aa97c9e` | **71.9%** | 0.660 |

The base binary scores 71.9% on the wave tree — identical to the head binary. The −3.1pp is entirely
**corpus composition**: the ranking lane scores the live source tree, so the lane's own new symbols
displace its gold. Confirmed by inspection of `--for="pagerank power iteration"`: on the clean tree
gold `pageRankDouble` sits at rank 2; on the wave tree ranks 2–5 and 9 are `RankDisclosure`,
`renderDisclosure` (`src/prconverge.h`), `RankedGraph`, `rankGraphTeleport` (`src/graph.h`) and
`PageRankRun` (`src/pagerank.h`). The ship rationale named `RankedGraph`/`PageRankRun`; the true
displacer set is broader and includes the two `prconverge.h` disclosure types.
**Recalibration verdict: recommend — but not by moving the floor.** A metric that any wave can erode
merely by adding load-bearing symbols to this repository measures the tool's own source growth, not
the ranker. The honest correction is to give the ranking lane a frozen corpus the way the recall lane
already has one (`snapshot.mdpack`/`snapshot.lock`), or to re-derive the gold at the new head. Both
are deliberate recalibration commits and neither belongs in this wave.

**Probe 5 — silent-semantics sweep. No undisclosed behavior change; four coverage gaps in the
root-relative-paths lane's claim.** Twenty verb forms were captured from both binaries on this
repository, normalized for the absolute-root prefix, and structurally diffed. Every residual
difference traces to a disclosed deliverable: `root="."` plus its shared legend clause
(root-relative-paths lane), `pr_iters=` plus its legend clause (convergence-disclosure lane), the
`<unindexed>` element and `unindexed_files_scanned=` (grep-visibility lane), `est_tokens=` shrinking
because paths got shorter, and one extra `--for` signature admitted for the same reason. Nothing
unexplained.
The gaps are in the *scope* of "root-relative `p=` on ALL verbs + CLI/MCP parity". Four surfaces
still repeat the absolute root once per row and carry no `root=`:

| surface | absolute `p=` rows | `root=` |
| --- | ---: | --- |
| `--tree` (223 KB, the session-start orientation map) | **1,212** | absent |
| `--quality-panel` (output byte-identical to the base binary) | **40** | absent |
| MCP `analyze` (the default map's own twin; the CLI form is relative) | **85** | absent |
| MCP `for` (the CLI form is relative and discloses `root="."`) | 3 | absent |

None is a regression — the base behaves identically — but the claim is broader than the landing, and
`rootrelcheck`'s 47-verb list omits `--tree` and `--quality-panel` while its CLI/MCP parity arm covers
only `grep` and `situ`. The new state is *internally inconsistent*: the same corpus answers a CLI
question with relative paths and the MCP twin of that question with absolute ones.

**Probe 6 — degrade paths. CLEAN.** No `VERIFY( false )` is added anywhere in the wave. Two new
`DEGRADED_PATH_ALERT` call sites (`restatePackTaskBodiesWrapper`'s unexpected `<bodies>` shape,
`loadRefTree`'s empty materialized tree), both with a real fallback behind them. The
convergence-disclosure lane's own signal is explicitly *not* an assert: `pageRankDouble` returns
`PageRankRun{ iterationCount, hasConverged }`
because `DEGRADED_PATH_ALERT` compiles out under `NDEBUG` and a shipped binary would otherwise have no
signal that a ranking stopped short — non-negotiable #4 honored by construction, not by convention.
The three added `VERIFY`s are true invariants with no behavior behind them. The
`RIPWIRE_TEST_PR_MAXITERS` arming hook is honored in every build flavour by design, and its effect is
disclosed in the document it perturbs (`pr_converged="0"`), so it cannot degrade a run silently.

**Reproduce.** Build both commits in separate throwaway worktrees (never reuse objects across a
checkout), then: `RIPWIRE_BIN=<base-binary> bash test/<gate>.sh` for each red arm;
`TMPDIR=<fresh> <binary> <corpus>` for each cache-matrix cell; `bash test/recallevalcheck.sh` run from
each tree for the probe-4 control.

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

**A bare `--expand=SYM` used to be 5.65× larger than the file it was summarizing, on a small file.**
On this repository, `--expand=pageRankDouble` (as measured at audit time, before any auto-selection
existed): the unconditional bundle cost **27,890 B** against the raw `src/pagerank.cpp` at
**4,936 B** — nearly six times the size of the file for the privilege of one function's body, and
still 1.08× the file even at the caller's lean `--top-k=0` escape hatch. **Resolved, not retracted**
(density-M6, `e6f173d`/`7558fd9`): the verb now measures its own default bundle against the
requested symbols' whole-file bytes, before emitting, and serves whichever is smaller — disclosed on
the `<ctx>` root as `mode="whole-file"`/`mode="bundle"`. Re-run today on the same symbol:
`--expand=pageRankDouble` costs **5,911 B** (`mode="whole-file" reason="file 5559B &lt; bundle
27916B"`, `src/pagerank.cpp` now 4,936→5,559 B as the file grew) — **1.06×** the file, not 5.65×. The
inversion is self-correcting: the tool notices when it would cost more than the file and stops
emitting the losing form, so this counterexample's own failure mode is now caught by the tool at
call time rather than by a reader after the fact. See §5 for the full before/after table and the
`test/expandmodecheck.sh` gate that now pins both arms.

**The mention anchor is worth +0.0pp on the wrong corpus.** SFML commit-message queries: no gain,
only wall-clock cost. See §4.

**`--grep` costs more tokens than it saves** (+19.7% / −11.2%). See §5.

**PageRank is a bad co-change ranker** (3.8% at recall@5 against 40.3% lexical), and fusing it into
the lexical ranker made things worse. See §6.

**A budget-monotonicity fix was monotone in the COUNT of bodies and not in their relevance** — kept
here because the failure mode is the interesting part, not the patch. The pack-task budget lane
(2026-08-17) removed a real defect — a bigger `--token-budget` could show strictly fewer bodies — by
replacing `packBodies`' streaming admission with a max-count subset pre-selection, tie-broken
`count > rank-score > cost`. Measured at `aa97c9e` on the gate's own fixture, the counter was
non-decreasing and the answer was not: at `--token-budget=900` the bundle carried the body of the
function the task names, and at 1200 it carried two one-line helpers instead, holding that
substitution through 4000. The pre-selection disclosed itself honestly throughout (the dropped
candidate named, `total=` restated from the true candidate set, `capped="1"`), and
`test/packtaskmonotoncheck.sh` could not see the inversion because it asserted on counts. The related
`monotoneRoll` conservatism — a capped section charged its whole granted share, donating nothing
forward — left up to ~44% of the requested budget unspent on this repository, costing seven caller
signatures at the default 6,000-token budget. Both are measured in §6.

> Update 2026-08-19: both were fixed after this verdict was written, so its "current behavior" is now
> history. The top-ranked candidate is admitted rather than entered into the count contest — its body
> survives every budget increase, truncated by the existing oversized-first floor when the pool cannot
> hold it whole — and the bodies section, the one whose items differ by two orders of magnitude, is
> allocated last, so the share it cannot spend no longer sits in front of the four sections that can.
> Measured on this repository, `--pack-task="rank the call graph"`: caller signatures at the default
> 6,000-token budget 13/20 → 20/20 and fill 52.5% → 59.8%; at 8,000 tokens fill 43.5% → 90.6%. Both
> properties are now asserted by `test/packtaskmonotoncheck.sh` (a relevance ratchet, and capped ⇒ the
> budget was spent), each shown red against the binary this verdict describes.

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

**Lifting symbols whose NAME carries a query noun reaches the right symbols and still ranks them
wrong — rejected at calibration, before a held-out run was spent.** The r5 round (registered
2026-08-03, decided 2026-08-04) built *nameboost*: an env-gated slot-ladder lift that, under the
conceptual subtoken+body route, placed into the visible bundle any symbol whose name contains a
query token of length ≥ `minTokLen` as a camel/snake name-subtoken (`match` → `ResolverMatch`,
`is_valid` → `is_valid`) **and** that already carried positive body/doc evidence — forced placement
below the mention band, never displacing #1, never touching the name-exact route. It was registered
against two measured r3-headroom losses: a query saying "where the match object is produced" left
`ResolverMatch` absent from the entire candidate pool at 5× budget, and "when I call
form.is_valid()" ranked `BaseForm.is_valid` **112th** behind an unrelated same-file class.

The pre-registered accept criterion, per that round's own amendments to the r3/r4 precedents: the
PRIMARY is the **multi-file stratum** strict file@10 on train (aggregate reported, never switched
to), over a frozen 2×2 grid (`minTokLen`, `maxLifted`) ∈ {4,5} × {2,4}, selection = highest train
primary with any cell regressing train single-file strict@10 by more than 1pp disqualified; the
held-out 243 run with repo-clustered bootstrap would be spent only if a cell advanced. It also
carried a hard pre-grid stop: if the trigger's gold fire-rate on the currently-missed set came in
under 20%, archive and stop.

Measured on train (n=254), the primary **never moved off baseline in any cell**:

| cell | strict@10 | single-file (n=205) | multi-file (n=49) — **PRIMARY** |
| --- | ---: | ---: | ---: |
| base | 61.81% | 70.73% | **24.49%** |
| 4,2 | 61.42% | 70.24% | **24.49%** |
| 4,4 | 61.42% | 70.24% | **24.49%** |
| 5,2 | 61.42% | 70.24% | **24.49%** |
| 5,4 | 61.81% | 70.73% | **24.49%** |

The entire @10 movement across all four cells is two instances: every cell *loses* `yt-dlp-11827`
(single-file gold displaced 9 → 10 by lifted non-gold rows), and only 5,4 *gains* `flet-4425`
(10 → 5, a genuine q07-shaped rescue) which exactly cancels its own loss. No cell exceeds baseline
on the primary, so under the frozen selection rule no candidate advanced. **REJECT at calibration;
the default stayed off and nothing landed on this branch.**

**The finding worth the round is that it died one stage LATER than the audit was built to catch.**
The pre-grid targeting audit *passed*, twice — 69.1%/60.8% gold fire-rate on the missed set from an
independent Python mirror, 66.0%/58.8% from the production predicate through its own audit tap, at
`minTokLen` 4 and 5. The trigger reaches gold; detection is not the gap. What fails is the
**choice**: on the 97-instance missed set the trigger fires on a symbol in the gold file in 64/97
instances, but that symbol's median rank *within the fired order* is **33** — top-2 **0/97**, top-4
**1/97**, and that single top-4 case is the `flet-4425` gain above. Ordering the fired set by the
current lens score re-ranks it by exactly the diluted subtoken-BM25 signal whose failure the
mechanism was registered to correct, so the 2–4 ladder slots go to generic high-scoring fired
symbols sitting just below the band. The illustration is stark: on the pinned django checkout, the
q07 query fires **1,588 symbols** — "path", "view", "handler", "chain", "match" are all common code
nouns at `minTokLen`=4 — with `ResolverMatch` at fired rank ~192. Both pre-registered reproducer
probes are null at every cell. **The methodological lesson, recorded for any successor: auditing a
mechanism's TRIGGER fire-rate gates the wrong stage.** The statistic that had to be audited is the
full one — "is gold inside the top-`maxLifted` of the candidate *ordering*" — which is computable on
train for free before a single cell runs, and whose 0/97 would have killed this round before the
grid.

Two shaped directions survived this round's post-mortem: ordering the fired set by name-match
specificity (matched-token IDF or name coverage) — but q07 shows full-coverage favors generic short
names like `View`; and file-level evidence pooling. **CORRECTION (2026-08-11, same day this entry
landed): the original text here called pooling "UNSPENT — open headroom". That was false when it was
written.** Pooling had already been pre-registered, gridded, and **rejected on held-out at +0.00pp**
five days earlier (2026-08-06, `bench/locbench/results/r5_pooling/gate_verdict.txt`), and its
successor r6 (structural expansion) had already closed the stratum to ranking-side mechanisms the
same evening (`r6_expansion/gate_verdict.txt`). Neither verdict had been carried into this document —
this entry was written from the nameboost archive without checking whether its "surviving directions"
had since been spent. Both rejections are now recorded in the two entries that follow.

Evidence is archived, not deleted: branch `claude/loving-fermat-6e9614` (tip `ed952ed`) retains the
pre-registration, the verdict table, the flip ledger, the two targeting-audit dumps, the per-cell
train scores, the candidate header, and its red-first gate under
`bench/locbench/results/r5_nameboost/`. None of it is on `main` and no default was flipped.

**File-level evidence pooling does not lift the multi-file stratum — rejected on held-out at +0.00pp
as a constrained mechanism (2026-08-06), and re-refuted as an unconstrained upper bound before it
could be re-attempted (2026-08-11).** The constrained round (`bench/locbench/results/r5_pooling/`,
registered 2026-08-06) implemented `poolScore(f) = Σ top-K symbol scores`, promote-only on the
mention slot ladder, env-gated as `RIPWIRE_POOL` (scaffolding still on main in `src/filepool.h`,
inert). Its identity control reproduced baseline exactly, two train cells advanced under its frozen
rule, and the single permitted held-out run came back **+0.00pp on every stratum** — the entire train
signal was ONE instance (`UXARRAY__uxarray-1117`). Its verdict also records a methodological defect
adopted by everything after it: a ±2pp bar on a 43-instance stratum is below single-instance
granularity, so **stratum thresholds must be stated in instances, floor ≥ 3**.

The 2026-08-11 re-check (VT-2 round, `bench/locbench/results/vt2_pooling_freestat/`) exists because
this document's stale "UNSPENT" line above nearly caused the idea to be re-attempted from scratch —
the exact failure §5's "publish the negative results" is meant to prevent. Per the §7 rule the
nameboost round earned, it computed the free end-to-end statistic FIRST: the full pooled FILE
ordering (no ladder, no blend — the unconstrained best case any pooling mechanism could emit) from
the complete routed `--for` scored candidate export, for a fixed family of pooling functions, on the
A7 train split (n=254; single 203 / multi 51; baseline re-measured on the current binary at 61.0%
overall, 70.9% single, 21.6% multi — drift from the recorded 61.81/70.73/24.49 explained by the
resolver and noise-gate work since kParserVer 50, two instances migrated strata). The control
(`max`, today's behavior) reproduced the recorded per-instance baseline on all 254 instances — then
no candidate cleared, and most did active harm:

| pooling fn | multi-file strict@10 (n=51) | single-file strict@10 (n=203) | multi net | single net |
| --- | ---: | ---: | ---: | ---: |
| `max` (control = shipped) | 11 (21.6%) | 144 (70.9%) | — | — |
| `sum` (all positive members) | 8 (15.7%) | 81 (39.9%) | **−3** | **−63** |
| `top2sum` | 11 (21.6%) | 140 (69.0%) | 0 | −4 |
| `top3sum` | 11 (21.6%) | 142 (70.0%) | 0 | −2 |
| `count-weighted` (max·(1+log₂(1+n))) | 9 (17.6%) | 128 (63.1%) | −2 | −16 |

The pre-fixed bar (net ≥ +3 multi-file instances, ≤ 2 single-file losses) was never approached; no
function nets even +1. `sum` is the instructive row: unbounded pooling makes file size the ranking
signal and destroys the single-file stratum wholesale. And the only recurring multi-file "gain"
(`sum`/`top3sum`) is `UXARRAY__uxarray-1117` — **the same single instance that laundered the
constrained round's train advance**, now identified as such on a second instrument. Stage
attribution, per the rule above: the failure is in the EVIDENCE, not the trigger and not the choice —
pooling can only aggregate the query-derived per-symbol scores that already buried the sibling
files, so it either moves nothing (`top2sum`/`top3sum`) or imports the file-size confound
(`sum`/`cw`). This is the unconstrained confirmation of the constrained round's own diagnosis, and
of the r6 closure: **the multi-file stratum is closed to ranking-side mechanisms** — five
pre-registered rounds (anchorhop ×2, siblift, pooling, expansion) plus this upper-bound check, three
seeds and three edges between them, all rejected. What remains open is candidate GENERATION (11 of
22 decomposed held-out failures: the sibling never enters the candidate set), query understanding
(4), and non-symbol gold (3) — different subsystems, recorded in `r6_expansion/gate_verdict.txt`.

**Stripping question words out of prose queries does not fix prose-query recall.** The r7 loss-first
round (2026-08-08, question sets committed in `bench/r7/`) measured natural-language queries at
**4/22** on a webpack set where terse keyword rephrasings of the same targets recovered 7 of 12
tested misses, and attributed the gap to interrogative/filler tokens diluting subtoken+body BM25.
The pre-registered fix — a closed filler-token strip on the routed conceptual lane plus an IDF
floor — was built, gated green, measured, and **rejected**: predicted 12/22 (pre-registered band
10–14), measured **5/22**, with only 1 of the 8 predicted flips materializing. The IDF floor died
first, by its own pre-authorized rule: it dropped a truth's *own* name carrier (`module`, for
`DeterministicModuleIdsPlugin`) and flipped a current hit to a miss. Strip-only then cost a baseline
C++ hit (`packtask.h`, rank 3→5) whose doc prose was riding exactly the filler-token mass the strip
removes — the dilution mechanism is real but it cuts both ways. The commit (`1a00a65`, reverted, in
reflog only) was rolled back rather than tuned, because the misses have a different anatomy: the
concept lives in the class/file *name* with no body carrier at all — `SplitChunksPlugin` contains
zero `splits`/`shared` subtokens, `FlagDependencyUsagePlugin` zero `unused` — a stemming/name-field
problem (recorded as LB-3 open headroom), not a dilution problem. The 4/22 prose number stands until
that is built and measured. The router-plausibility fix from the same round (LB-2, `fa4639e`) *did*
ship: terse compound queries like `split chunks` no longer hard-route onto a common stdlib anchor
(`split`) — 5 of 6 pre-registered probes recovered with all 7 controls held, the 42 committed
questions byte-identical, and the name-exact lane's recall@1 measured unchanged (98.0% at both the
pre-round base and the fix, base rebuilt in a throwaway worktree to prove it).

**Un-guarded query stemming recovers prose misses — and displaces existing hits; rejected by its
own rules.** The LB-3 fix round (2026-08-08, same committed `bench/r7/` sets at token-budget tiers
2000/6000 against the r8-pinned corpora) built the name-field levers the previous entry named as
the real anatomy: query-side stem variants ("splits"→"split", "resolved"→"resolve") scoring into
the original token's tf/idf row, and a basename-only BM25 field (the r3_pathtok retry, narrowed to
basenames per that round's own rejection note and amortized per file). Both env-gated, byte-inert
off, parity-gated (`test/lb3namecheck.sh`, red-first). Measured over the pre-registered 8-arm grid:
stemming genuinely recovers the diagnosed misses — webpack@6000 **6/22 → 11/22** alone, **12/22**
with basename w=2, webpack@2000 4→11, zero cells below baseline — but **every stem arm violated the
frozen rules**: cpp@6000 landed 19/20 against a pre-registered 20/20 point band (the predicted
`resolve.h` flip moved rank 24→18, short of the budget cut), and each stem arm flipped a
currently-hit question to a miss (`SplitChunksPlugin` and/or `HotModuleReplacementPlugin`) — the
common-stem variant `split` hands term frequency to corpus-wide competitors, the same
dilution-cuts-both-ways mechanism that killed the LB-1 filler strip, one level down. Verdict:
**REJECT, no defaults flipped** — verified by independent recomputation of all 32 grid cells, the
flip lists, and the five frozen gates. The recorded retry conditions: IDF-guard the variants (a
variant whose corpus document frequency is high may not be added — "resolve" passes, "split"
fails), bands at least 2 wide (a 20/20 point prediction is a coin flip, not a band), and acceptance
primary on instruments never used for tuning. The basename-alone arm (webpack 6→7, no flips, no
band violation) was too weak to select under the frozen selection rule. The 4/22 default-budget
prose number still stands.

**The IDF-guarded stemming retry: a VOIDED round, with a coincident negative that stands on its
own.** The LB-3 retry (2026-08-08, prereg + sealed instruments committed at `bench/lb3retry/`)
implemented the retry conditions above. The guard's form was to be selected by a frozen mechanical
ladder over string-level probes only — and the ladder's own stopping rule fired: name-carrier
bounds (rungs 1–2, the LB-2 `routeCarrierCap` reuse) measure too LOW to catch the recorded
casualties ("split" rides only 23 webpack symbol NAMES against cap 118, but 292 doc/body rows —
the displacing mass is `.split()` call-site BODY frequency, not name mass), and the doc/body-df
rung (R3: admit only df ≤ max(8, S/64), computed branch-identically so the scan==postings parity
gates hold armed) kills both recorded casualty strings but ALSO rejects "resolve" on the cpp
corpus (df=275/8856 symbols ≈ 3.1%) — refuting this section's own worked example ("'resolve'
passes") by the rule's own standard. The orchestrating session amended its freeze to drop the
refuted example-check and proceed; the round's independent adversarial verifier — directed by the
prereg to audit exactly this — ruled the amendment a **material pre-registration violation** (a
hard stopping rule renegotiated the moment it fires is not a hard stopping rule) and VOIDED the
round at guard selection. That ruling is accepted and recorded: the numbers below are evidence
about the configuration broadly, not untainted evidence for the prereg's hypothesis chain.

The coincident negative, verified by full independent recomputation (every grid cell, flip list,
seal hash, gate, and probe; one verifier side-finding — alleged mid-round corpus drift — was
retracted after a floor-division check showed every probe cap derives from constant symbol
counts): the guard DOES eliminate the recorded casualty class — 42-set webpack@6000 **6/22 →
12/22 with zero flips** in the selected S1B2 arm (stem variants + basename w=2; S-alone still
flips `SplitChunksPlugin` via an admitted rare variant "share", and the basename field's
re-anchoring is what buys the zero-flip property), cpp@2000 13→14, no cell below baseline, both
named regression questions held, every ≥2-wide report-only band hit. Then the never-tuned
instruments ran once. A fresh 42-question set authored blind by an independent agent and
SHA-256-sealed before any lever run: webpack 3/22 → 5/22 with zero flips — and ONE cpp question
flipped hit→miss ("…the compressed sparse-row structure used for ranking?", truth `src/graph.h`),
displaced by the variant "compressed"→"compress" at **df=41, well under cap 138**. Held-out
LocBench (arm `for`, paired vs the same binary levers-off, n=306 scored across 88 repos, settings
identical to the r3_pathtok acceptance run): strict file@10 **+0.65pp**, clustered-bootstrap 95%
lower bound **+0.00pp** — positive on never-tuned data but not significant; the harness's two-tier
gate reads REJECT on that bound. Verdict on the configuration: **REJECT by the frozen no-flip
clause, independent of the void — no defaults flipped.**

The finding that matters for any third attempt: the IDF guard eliminates the common-variant
casualty class it was designed for, and a SECOND class survives it — a genuinely corpus-rare
variant can still displace a truth whose rank margin is thin at the budget cut. Dilution cuts both
ways at every level measured so far: filler-strip (LB-1), un-guarded variants (first LB-3 round),
full-weight rare variants (this round). Recorded third-attempt conditions: (1) variants contribute
at REDUCED weight (fractional tf or a per-variant contribution cap) — attack the margin mechanism,
not the frequency mechanism; (2) the r7 42-set AND this round's fresh set are both
tuning-contaminated for this lever family now — a third attempt needs a new blind instrument;
(3) a guard-form ladder must validate its named checks against measured df/carrier tables BEFORE
freezing, so a self-contradictory check is caught before the ladder can fire (this is what voided
the round). Audit note: the stemmer also emits second-order zero-df variants ("generat",
"resolv"), functionally inert on postings and never named in the prereg. The R3 guard machinery is
retained in-tree, env-gated (`RIPWIRE_QSTEM`), byte-inert off — 84/84 levers-off outputs
byte-identical to the pre-round binary's, re-verified independently.

**RTA-lite (the instantiation-filtered CHA cone): rejected by its own prereg — an inert evidence
class on real C++, a cross-namespace wrong filter, and silent devirtualization.** The preregistered
resolver-precision round (2026-08-08; blind acceptance fixtures and per-lever binary snapshots
sealed before implementation) landed the Bacon/Sweeney refinement of the shipped CHA-lite: a
still-ambiguous receiver-typed tier, after the cone prune, intersected with the set of class names
holding constructor evidence in the reference stream, degrading to the plain cone on an empty
intersection. The implementation was faithful to the preregistered design and passed its own
red-first gate; the design's evidence class failed three ways. (1) **Inert where C++ instantiates.**
The only constructor forms that mint a reference are `T()` temporaries (plus `new T(…)` in
JS/TS/Java/C#, whose tags queries capture object creation); C++ `new T`, `T{}`, and plain value
declarations (`Circle c;` — a Rule-2 type *binding*, not a reference) are invisible at extraction —
a gap the lever disclosed at landing, and exactly the form the blind fixture used. The fixture's
virtual call listed all three candidates, identical to base; calibration deltas were **exactly 0 on
all three corpora** (cpp `ambiguous=` 3045→3045 against an accepted-decrease band of [1, 300];
webpack and the private ObjC++ validation tree likewise unmoved). Closing the gap means new extraction machinery, which the
round's rules correctly refuse as post-hoc mechanism invention. (2) **Name-keying filters the wrong
hierarchy.** Adversarial fixture: two namespaces each define an `Impl` (X's derived from X's base,
Y's from Y's), only `Y::Impl` is constructed. On a call through `X::Base*`, the name-keyed set
matched bare "Impl" from Y's evidence and DROPPED `X::Alt::draw` while keeping `X::Impl::draw` — a
wrong filter that falsifies the in-code claim "a same-name collision only ever ENLARGES the set"
(it enlarges the *set*, and thereby wrongly *arms* the filter over an unrelated cone). (3) **Silent
devirtualization.** When the filter narrowed a tier to one candidate the `amb=` marker disappeared,
so an unsound closed-world guess (extern factories can construct what the corpus never mentions)
became indistinguishable from a sound CHA resolution — an honesty violation on its own. Verdict:
**REJECT; the lever is reverted in full** (this entry's commit removes the set builder, the
intersect step, and its gate). Recorded conditions for any future preregistered attempt: a
pointer-vs-value bit on the Rule-2 binding record so value declarations become evidence while
pointer declarations stay out; tags patterns for new-expressions and brace-init so `new T` / `T{}`
mint references (a parser-version bump with its own vocab updates); QUALIFIED-name keying of the
instantiated set so evidence in one namespace can never arm a filter over another's cone; and an
explicit disclosure attribute on every RTA-narrowed call (narrowed-by-evidence is weaker than
proof, and the map must say so) with legend coverage and a red-first gate for each.

### External corroboration — three 2026 papers (citations only, no benchmark numbers of our own)

**"What Context Does a Coding Agent Actually Need to Act?" — arXiv:2607.09691.** With localization
held constant, adding class skeletons/signatures produced no editing-accuracy benefit over the
located source alone; NL summaries scored ~9% on behavioral probes against ~60% for source;
compressed source matched whole-file context at roughly 1/3 the tokens (19.3K vs 93.7K per resolved
issue). Implication for this tool: the signature map earns its tokens at FINDING time, not ACTING
time — corroborates the anchor-body/T3 direction (rank first, then serve full bodies of the few
right symbols) and the `--compress` lever, and is a caution against any future signature-heavier
serving shape.

**"Is Grep All You Need?" — arXiv:2605.15184.** Grep-based retrieval beat vector retrieval across
three agent harnesses (Claude Code, Codex CLI, Gemini CLI), and the harness mattered more to the
outcome than the retrieval method did. Implication: corroborates both the no-embeddings design bet
(`docs/LINEAGE.md` §2, *Keyword search is all you need*) and the harness-conditional posture already
written into the skills (e.g. the grep-still-wins guidance in ripwire-efficient).

**"ARISE" — arXiv:2605.03117.** Statement-level def-use edges and data-flow slicing, exposed as a
queryable agent primitive, beat SWE-agent on SWE-bench Lite by +17pp Function Recall@1 and +15pp
Line Recall@1. Implication: names a real ceiling in this tool's granularity — the call graph is
symbol-level, with no intra-procedural slice verb. Recorded here as a candidate future round, not a
commitment.

---

## 8. Claims this project does *not* publish

Listed because the reason is more useful than the silence.

- **Any claim that ripwire changes whether an agent SOLVES a task.** This is the north-star metric
  and it has never been measured: `--evaluator swebench` has never executed, and every record in the
  one pilot on file carries `resolved: null`. Everything published here scores *retrieval quality*,
  whose correlation with task success is assumed, not demonstrated.

  As of 2026-08-10 there is a second, sharper reason to withhold it: **the eval as designed cannot
  detect a plausible effect.** `bench/agentloop/analyze.py` bootstraps clustered by repository, and
  with equal rows per repo that is algebraically a resample of the **6 repo-level means** — so
  effective N is the cluster count, not the 24 instances. Minimum detectable effect at the planned
  configuration is **18–32pp** on resolution rate, and at 6 clusters a 5pp or 10pp effect is not
  reachable *at any instance count* once between-repo heterogeneity is non-zero (simulated out to
  49,152 instances; `bench/agentloop/power_sim.py`). Adding repos buys roughly 4× the power of adding
  instances inside the existing six.

  The consequence for honesty is specific and worth stating plainly: **a null result from this design
  would not be evidence of no effect**, and must not be reported as one. Until the repo universe is
  widened or a scored pilot measures the intra-cluster correlation, no outcome number — positive,
  negative, or null — is publishable from this instrument.
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
  ~210; `test/argvdiffcheck.sh` says 200+), while the loop in `test/regression.sh` names 519. The
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

---

## Wave-3 round (2026-08-19) — adversarial verdicts, findings included

Verifier probes ran against `35fccbf` (the merged wave head plus its quality-acks ledger) from
clean from-scratch builds of both `adb0831` and the head in throwaway worktrees. Full report:
the round's local record. The pre-push fix round (`lane/w3-verifier-fixes`, ten commits) landed
every must-fix finding below before this verdict commit; SHAs cited inline.

**R-H — span tiers on `--grep`/`--regex`: ACCEPT the mechanism, with the ladder correction
required by the verifier LANDED (`8d935d1`) and the byte claim withheld.** The tier pass is a
query-time filter over already-collected hits (`search.h::grepApplySpanTiers`), owned by one
function that both the CLI and the MCP `grep` verb call, with `--grep-in=any` byte-identical to
the pre-tier verb on every cell of a 4-way cache-provenance matrix across two corpora (default
map identical in 6/6 cells, `kParserVer` 66 unmoved, `reparsed=0` when the new binary reads the
old binary's blob — and additionally across 11 query shapes, `--json`, and the MCP verb). The
disclosed budgets (`kGrepTierFileBudget=128`, 8 MB bytes) are pure functions of the corpus, and
the deterministic-byte substitution for E5's parse-*time* budget is the right call:
budget-tripped answers are byte-identical across three cold runs and warm≡cold, xmllint-clean,
ASan/LSan-clean, with `tier_parsed=`/`tier_budget=`/`tier_unclassified=` disclosed and
`complete=` correctly withheld. **The harvest's −38…−87% byte projection does not reproduce and
must not publish** — measured whole-answer deltas run −20.4% to +12.3%, because suppressing
comment rows frees room under the row cap and the page refills with code rows; the win is row
quality at a fixed row budget. The verifier's structural finding — §F4's ladder ranked `comment`
above `string`, so pasting an error message could serve a test-script comment while suppressing
the emit site (10/138 measured misses), and config languages (whose content parses entirely to
string nodes) vanished from the default view — is closed by collapsing the ladder to
`code → everything-else` when the code tier is empty (`tier="comment+string"`), gate arms
red-first, with the data-language carve-out recorded as a wave-4 item and
`skills/ripwire-security-scan`'s recipe corrected to `--grep-in=any` (`a957607`) in the interim.
`--help` no longer calls the default an "exhaustive literal scan" (`b6428c5`); the published
`--grep` byte numbers are relabelled as `--grep-in=any` measurements (`74160b8`); `greptiercheck`
now pins both budget constants (`6e51beb`), closing the found hole where `128 → 12` left all
arms green while the feature went ~90% inert.

**The six-smalls disclosure round — ACCEPT, with two gate-margin liabilities recorded.** All four new gates
are decisive against the clean `adb0831` binary (verifier reproduction: `lintpayloadcapcheck`
5 FAIL/3 PASS, `bodiesshowncheck` 4/5, `langcensuscheck` 5/12, `forrootlegendcheck` 3/6; all
green on the wave binary), and each carries a reachable-both-ways guard. `--lint`'s default
payload falls 370,721 B → 67,908 B with `findings= shown= capped=` disclosed and the per-rule
tally still truthful. Recorded liability 1: the cap keeps a sorted path prefix, so 14 of 31
firing rules lose every locator row while their `count=` stays truthful — a one-attribute
per-rule `shown=` closes it (wave-4). Recorded liability 2: the `root=` legend clause costs 51
`est_tokens` at `--token-budget=800`, taking `fornotesbudgetcheck` from 747/800 to 798/800 —
2 tokens of margin, now recorded in the gate's own header (`683e34c`) so the next red there
reads as this wave's ratchet. `legenddriftcheck`'s widening is a genuine strengthening (live
flag extraction 1 → 5 over 166 legends) and closes the wave-2 verifier's near-inert finding by
naming the mechanism (`--` is illegal inside an XML comment). `packtaskcheck`'s path-stability
hardening is verified green at both path depths and is the template for the remaining members
of the byte-gate-over-live-tree class (`grepbytescheck`, `showcasecapturecheck`,
`lintbudgetcheck` — wave-4 freezes). `skilltruthcheck`'s JSON-monoculture fixture — the reason
the config-language consequence shipped unnoticed — now has a mixed fixture whose decisive arm
fires (`61bb8b0`), and the MCP `grep` verb refuses unknown `in=` values the way the CLI does
(`36f79e5`).

**The length-aware desc+body mix — REJECT stands, verified on every axis.** Registration
(`2cc9924`) precedes the lever (`deda604`) precedes the revert (`d8862a6`) precedes the result
(`7e2ad2c`), and the registration is result-free: `for-routed` judged hit@1, n=152, ACCEPT iff
[+4, +8], plus guards (split=test ≥ 67.7%, sep-auc ≥ 0.922). Measured 90 → 92 = +2, below band,
split=test guard missed at 66.2%. Verifier re-measurement at the merged head returns 90/152 —
the registered baseline — possible only with the lever fully out; the final diff is
`docs/EVALS.md` only. What outlives the REJECT: the pre-build refutation of the margin-blend
family (bm25-desc misses the same hard row to the same wrong skill, capping the recoverable dip
at +1 against a +4 floor), which makes a third desc-vs-body round unfundable at this corpus
power; the remaining lever class is query-side term weighting.

**Wave-level quality-delta: `gating="0"` is honest, and the headline duplication ack survives
refutation.** `--quality-delta=adb0831..HEAD` returns gating 0 with all preexisting-worse rows
either reasoned-acked or unacked `sev="minor"` wiring deltas; nothing hides behind a minor
classification. The load-bearing `{writeLangRows, writeUnindexedExtRows}` ack was attacked with
the repo's own fold threshold and holds (the same emitter block deliberately leaves a *larger*
clone pair unfolded for exactly the discriminator that applies — differing attribute sets — and
every consolidation sketch is net-longer). The 16 stale rows are proven inherited (identical
key-for-key in a baseline-vs-baseline run). The three ack-text defects the verifier found
(a false "both callers updated" clause, a behaviour-changing cap filed as usage text, a
non-member named in a group) are corrected in the ledger (`0e97e2f`), and the false clause's
substance is fixed rather than reworded: batch grep now carries the same `in` hatch (`6e51beb`).

**Instrument state at close (all floors green, re-confirmed live by the verifier):** skill
routing judged 98/152 bm25-desc / 90/152 for-routed, split=test 73.1%; frozen ranking lane
71.9% ≥ 70 (`snapshot.srcpack`); recall MRR 0.643; kParserVer 66 (unmoved this wave, proven by
cache-provenance matrix). The E6 demotion corpus stands at 16 CLEAN (strict 15) against the
≥25 bar — the three queued ranking lanes remain deliberately unbuilt, and the pre-registered
band remains banked, unregistered, and untuned.

### N11/N12 — the ugrep EXTRACTION gap — PRE-REGISTERED 2026-08-25 (before any fix code)

**What this registers.** Both the anchor-body round and the def-over-decl round named the same residual
and disclaimed it rather than fix it: *"a qualified out-of-class nested definition (`class
BufferedInput::dos_streambuf : …`) is not extracted as a symbol for its own bare name."* This is an
EXTRACTION gap, not a ranking or routing one — neither round's diff touched a tags query or `kParserVer` —
and it is the one item this lane is scoped to fix.

**The mechanism, stated so it can be wrong.** `queries/cpp/tags.scm`'s `class_specifier`/`struct_specifier`
patterns bind `name: (type_identifier)` — a BARE, unqualified class name. A nested type DEFINED OUT OF
LINE with its qualifier written out — `class Outer::Inner : Base { … };`, the Pimpl idiom rocksdb's own
tree uses ~29 times (`BlockBasedTable::IndexReaderCommon`, `AutoHyperClockTable::ChainRewriteLock`,
`VersionBuilder::Rep`, `CompressionContextCache::Rep`, …) — writes its OWN name as a `qualified_identifier`
instead, so neither pattern matches and the class itself is dropped at extraction: no symbol, no
`--skipped` row, no floor. Its MEMBERS still extract fine and still scope correctly to `Outer::Inner` —
`ingest.cpp`'s `enclosingScopeOf` walk is structural (it reads the `class_specifier`'s own `name:` field AS
WRITTEN, whether or not the tags query captured that node as a symbol) — so a constructor inside the class
body was never the problem. Only the class's OWN bare name resolves to nothing.

Measured at base (`518fe0d`), ugrep `include/reflex/input.h`: `--for="dos_streambuf"` ranks the
CONSTRUCTOR (`fn`, a real def — a constructor's own name is the class name too) and the bodyless in-class
forward declaration `class dos_streambuf;` (extracted, but — a second, narrower defect this lane's fix
also happens to expose rather than cause, see the finding below — two DIFFERENT enclosing classes'
forward declarations of the same bare nested name collide into ONE self-scoped id) but never the real
`class BufferedInput::dos_streambuf : public std::streambuf { … }` definition itself: absent from the
candidate list entirely, not merely low-ranked.

**The claim under test.** The out-of-line METHOD pattern two lines above in the same file already handles
this exact grammar shape (`function_declarator declarator: (qualified_identifier name: (identifier))`,
extended to `name: (qualified_identifier)` for 2+ segments — the C1/memgraph round, 2026-08-yy) via two
pieces of machinery that are already GENERIC over every C++ definition capture, not method-specific:
`cppDefNameReseat` (descends a qualified `@name` capture to its innermost identifier for the bare NAME)
and the canonical-scope rule (`qualifierOf` first, `enclosingScopeOf` only when that is empty, for the
SCOPE — "out-of-line `A::b` → `A`"). The claim: adding the class/struct-level twin of the existing
qualified-method pattern needs no new C++ code, only two new query lines plus the `kParserVer` bump every
extraction change carries.

**The fix (stated before it is written).** Two new lines in `queries/cpp/tags.scm`:
```
(class_specifier name: (qualified_identifier) @name body:(_)) @definition.class
(struct_specifier name: (qualified_identifier) @name body:(_)) @definition.class
```
`body:(_)` mirrors the upstream `struct_specifier` pattern's own requirement (only a real out-of-line
DEFINITION carries a body; ISO C++ has no syntax for a qualified out-of-line FORWARD declaration of a
nested class, so the bodyless case is not a live shape this drops on purpose). `kParserVer` 72 → 73.

**Primary metric: `GOLD-EXTRACTED`** = of the two named probes (N11 `dos_streambuf`, N12 `streambuf`,
both on ugrep `include/reflex/input.h`), does `--format=candidates` for a plain `--for="<name>"` include a
`cls` candidate whose id is the QUALIFIED name (`Input::dos_streambuf` / `BufferedInput::dos_streambuf`,
etc.) at the definition's real line — i.e. is the gold class itself extracted and locatable by its bare
name, not merely its constructor. **Baseline, measured at `518fe0d`: 0 / 2** (confirmed above). Both
`dos_streambuf` and `streambuf` name TWO out-of-line definitions each (`Input::X` and `BufferedInput::X`),
so the metric is a strict 0-of-2 rather than a partial credit scale — the mechanism is a grammar-level,
unconditional extraction rule, not a score-dependent tiebreak, so there is no plausible PARTIAL outcome
the way a ranking round has: either the pattern matches the shape and both flip, or it does not and
neither does. **Registered band: `GOLD-EXTRACTED` = 2 / 2, a single point, not a range** — anything less
is a REJECT (the mechanism does not do what it claims) and anything else does not exist for this metric.

**Registered invariance criterion, which outranks the band.** *Every symbol that already extracted
correctly — every already-passing row of the twelve-probe anchor-body set (N01–N10), every member's own
scope (the constructor's id, unchanged) — must be untouched.* This is a structural claim from the fix's
own shape (two new, disjoint query patterns; `cppDefNameReseat`/`qualifierOf` are read-only over the AST,
not rewritten): a query pattern either matches a node or it does not, and nothing is removed or reordered
for the shapes that already matched. Checkable two ways: (i) the fixture-level constructor-id control
(`test/nestedqualfix`, arm (e)); (ii) `<sigs>` byte-compared across the SAME twelve real-corpus probes the
anchor-body round pinned, base vs. this lane's head, on duckdb/rocksdb/ugrep.

**Registered controls.**

| control | why |
| --- | --- |
| `test/nestedqualfix`'s Decoy (arm (d)) | a same-named nested forward declaration in an UNRELATED enclosing class must never be attributed the real definition — proves the fix reads the qualifier at the DEFINITION site, not a name-only merge |
| the constructor's own id, unchanged (arm (e)) | this fix ADDS a symbol; it must not touch a member scope that already worked |
| N01–N10, `<sigs>` byte-compared | ten already-passing rows this extraction change has no business reaching |
| duckdb `third_party/re2` (8 real instances of the shape, e.g. `RE2::Set`, `DFA::Workq`) | vendored/excluded from the crawl already, base and head alike — the predicted EXPLANATION for why duckdb's total symbol count does not move at all, checked rather than assumed |
| rocksdb symbol-count delta, spot-checked | the ~29 new rocksdb symbols this fix is expected to mint (real Pimpl-idiom classes) must be exactly that shape, not a false-positive flood — `IndexReaderCommon`, spot-checked, resolves correctly |

**Registered guards, re-run after the change; any regression is a REVERT regardless of the band.** Same
lattice as the round above: skill routing (split=test/dev), judged routing, recall lane, ranking lane,
pollution, `run_r3diff.py` on the two frozen sets, determinism, `xmllint`, the full gate battery, G1.
**One extraction-specific expectation, stated in advance rather than discovered after:** raw BM25 scores
on UNRELATED queries may shift in the LOW DIGITS of a floating value (adding symbols anywhere changes
corpus-wide document-frequency/length statistics for every query, not just the ones this fix targets) —
this is expected and is not itself a regression; what MUST hold is that `<sigs>`/ranked ROW ORDER and
every disclosed anchor are byte-identical on every probe this fix does not target. A WIDE `r3diff` on
either frozen set, or any `<sigs>` byte movement on N01–N10, is the actual kill condition.

---

**Verdict: SHIP.** `GOLD-EXTRACTED` **0/2 → 2/2**, the single-point band, hit exactly. Both N11
(`dos_streambuf`) and N12 (`streambuf`) now extract their real out-of-line class definitions as their
own `cls` symbols, findable by bare name, on the real ugrep corpus. Every registered guard reproduces
its last recorded value to the digit, the two frozen `r3diff` sets are 74/74 ties, the twelve-probe
`<sigs>` sections are byte-identical on N01–N10, and G1 is clean on the new parser path including the
one real-world instance spot-checked outside the fixture (`rocksdb`'s `BlockBasedTable::IndexReaderCommon`).

**Provenance.** Branch `lane/candhead-ugrep`, worktree `~/AppDevelopLocal/project2/ripwire-wt-candhead`,
off `518fe0d`. Commits: `bcd91a9` (registration, result-free) → `d4947a6` (red gate, verified RED against
`518fe0d`) → `4a2b784` (the fix: two `queries/cpp/tags.scm` patterns, `kParserVer` 72 → 73) → `120d99b`
(a `test/qschemetripcheck.sh` re-pin the first full battery run caught — an EXTRACTION-not-SEMANTICS
change, so `kQSnapCacheScheme` correctly stayed put, matching every prior `kParserVer`-only re-pin logged
in that gate's own history). Corpora: the same pinned duckdb/rocksdb/ugrep checkouts the anchor-body
round re-cloned (`rw-lane-ab2-corpora/`), reused rather than re-cloned since only reads happen here.

**Result — the twelve-probe set, base (`518fe0d`) vs. this lane's head, isolated from item A (a
separately-stashed, separately-committed change — this measurement carries none of it).**

| id | corpus | query | `<sigs>` | anchor | note |
|---|---|---|---|---|---|
| N01–N09 | DD/RD | (all seven not shown below) | byte-identical | unchanged | untouched, as registered |
| N10 | RD | `Logger` | byte-identical | unchanged | untouched, as registered |
| N11 | UG | `dos_streambuf` | **moved** | `input.h+4` → `input.h+6` | anchor now the real CLASS, not its constructor |
| N12 | UG | `streambuf` | **moved** | `input.h+6` → `input.h+8` | same shift, same reason |

N11/N12's anchor byte-offset moving is not a defect — it is the anchor-body round's own "first
BODY-CARRYING definition in NodeId order" rule reaching a BETTER candidate than it had before: with the
class itself now extracted (and, in NodeId/crawl order, the class declaration line always precedes its
own constructor), the anchor shifts from a constructor to the class it constructs. Bodies served for N11
went from `{fn:867, fn:1122, fn:1128, cls:335, cls:951}` (a constructor-heavy set, plus a bodyless
in-class forward declaration that used to fill a leftover slot) to `{cls:865, fn:867, cls:1120, fn:1122,
fn:1128, cls:335}` — the real `Input::dos_streambuf` and `BufferedInput::dos_streambuf` definitions now
present, one bodyless forward-decl slot displaced by them. N12 is the same shape.

**Symbol-count blast radius, measured rather than assumed.**

| corpus | base | head | Δ | explanation |
|---|---:|---:|---:|---|
| duckdb | 61178 | 61178 | 0 | the shape's 8 real duckdb instances (`RE2::Set`, `DFA::Workq`, …) sit entirely in `third_party/re2/`, excluded from the crawl already — confirmed, not assumed: none of the 8 paths appear in `--for="RE2"`'s candidate list on either binary |
| rocksdb | 53590 | 53619 | **+29** | real Pimpl-idiom classes; spot-checked `BlockBasedTable::IndexReaderCommon` (`table/block_based/index_reader_common.h:19`) resolves correctly by bare name, scope `BlockBasedTable` |
| ugrep | 3622 | 3626 | **+4** | exactly the two N11/N12 golds' two out-of-line definitions each |
| ripwire's own `src/` | 11731 | 11731 | 0 | zero instances of the shape in this repo (consistent with the C1/memgraph round's own note) |

**Fixture-level gate, `test/nestedqualcheck.sh`, all nine arms.** (a)/(b) the gold class/struct extract
at their real defining lines; (c) the class's own body rides in `<bodies>`, not just the constructor;
(d) the Decoy control — a same-named nested forward declaration in an unrelated enclosing class is never
attributed the real definition; (e) the constructor's own scope (`Outer::Inner::Inner`) is untouched;
(f) route scope sanity; (g) symbol count is exactly +2; (h) determinism. Verified RED on `518fe0d`
(arms a/b/c/g fail exactly as predicted, d/e/f/h already pass as controls) and GREEN on both `build/`
and `asan/` binaries.

**Guards — green, and identical to the digit.**

| Guard | Floor / ceiling | `518fe0d` | with the fix |
|---|---:|---:|---:|
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 | 98/152 / 92/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 | 88.1% / 0.643 |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 | 71.9% / 0.639 |
| LIVE / ranking / adversarial pollution@5 | ≤ 16% / ≤ 5% / ≤ 8% | 2.4% / 0.0% / 0.0% | 2.4% / 0.0% / 0.0% |
| `run_r3diff.py` ranking (n=32) | near-all ties | — | **32 ties, net +0** |
| `run_r3diff.py` recall (n=42) | near-all ties | — | **42 ties, net +0** |
| determinism (map, `--for`) + `xmllint` | contract | — | byte-identical, well-formed |
| G1 — ASan/UBSan/integer/LSan, all four corpora + the new parser path + the real rocksdb instance | no report | — | **clean, exit 0, empty stderr** |
| `--quality-delta=518fe0d..HEAD` | no gating regression | — | `gating="0"` (9 `sev="minor" origin="new-symbol"` rows, all the fixture's own new classes) |
| full gate battery, frozen tree | all green | — | **`gates=464 pass=462 skip=2 fail=0`** (the two skips are the standing `namingcalibrationcheck`/`argvdiffcheck`) |

**Findings for the next round.** (1) The bodyless-forward-declaration collision this lane's own base
measurement exposed — two DIFFERENT enclosing classes' in-class `class Name;` forward declarations
collapse into one self-scoped id (`outer.hpp::Inner::Inner` for both `Outer::Inner`'s and `Decoy::Inner`'s
forward declarations in the fixture) — is a separate, narrower defect this lane did not fix: it predates
this change, this change does not make it worse (the Decoy control proves the real DEFINITION still
resolves to the right scope regardless), and it was not named by the task. (2) Templated out-of-line
nested definitions (`template <class T> class Foo<T>::Bar { ... }`) are a documented remaining gap: the
new pattern's `name: (qualified_identifier)` does not match a `template_type`/`dependent_type` name node,
and duckdb's `third_party/re2` instances happen not to exercise this because they are vendor-excluded,
not because they are templated — an untested, disclosed edge.

### N08 — the candidate-head bound — PRE-REGISTERED 2026-08-25 (before any fix code, on top of the
### extraction round immediately above)

**What this registers.** Both the anchor-body round and the def-over-decl round named this residual too:
*"`Slice`'s anchor is now correct and its gold sits at rank 8, one past `kPackTaskBodyCandidates` = 6,
behind seven higher-scoring `Slice.java` rows … Whether the head should be taken AFTER the anchor
restriction rather than BEFORE is a small, well-understood question with a clean fixture available."*

**The mechanism, read from the code rather than assumed.** `main.cpp`'s `buildForAutoBodies` takes the
top-`kPackTaskBodyCandidates` (6) positive-score rows of `lensSurfaceIds` (the WHOLE ranked surface, not
scoped to any one file) FIRST, and only THEN calls `restrictBodiesToRouteAnchor` to narrow that already-
capped six down to the anchor's own file. Confirmed directly on rocksdb: `--for="Slice"` resolves the
anchor correctly to `include/rocksdb/slice.h` (the def-over-decl/anchor-body rounds' own fix), but the
pre-restriction top-6 is seven `Slice`-named rows in `java/src/main/java/org/rocksdb/Slice.java` — a
different LANGUAGE, an unrelated file — scoring higher (`8.37869` vs. slice.h's `6.35078`) because of
BM25's length-normalization term: a symbol WITH a written scope (`s.scope` non-empty, e.g. a C++
constructor `Slice::Slice`) counts as a two-token "document" against the whole-name scorer, while an
unscoped Java method scores as one token and wins the length penalty. Restriction runs on a set that
already has zero anchor-file members, so it produces the empty set: `bodies="0" reason="no_candidates"`.

**The claim under test.** Restricting the FULL positive-score surface to the anchor's own file BEFORE
taking the top-6, rather than after, makes the anchor's own definitions the only pool the cap draws from
— so the gold is served whenever anything in its own file is on the positive-score surface at all,
regardless of how many unrelated same-named symbols elsewhere outscore it. This is a REORDERING of an
existing two-step pipeline, not a new rule: no scoring, no anchor selection, and no ranked-row content
changes, by construction — `restrictBodiesToRouteAnchor` and `isRouteAnchorSymbol` are reused verbatim,
only the ORDER of two already-existing calls moves.

**Primary metric: does N08 flip.** On rocksdb `--for="Slice"`, is the gold class definition
(`include/rocksdb/slice.h`'s `class Slice`) present in `<bodies>`. **Baseline, measured at this lane's own
head-with-item-B (item B lands first in this branch; N08 is untouched by it — confirmed, `<sigs>` and
`bodies="0"` both unmoved from `518fe0d`): NO.** **Registered band: YES** — a single boolean, not a range;
the mechanism is an unconditional reordering, so there is no partial outcome for the one probe it directly
targets.

**The open question this lane's own brief poses, registered rather than pre-answered: does the reorder
touch ONLY N08, or does the same crowding pattern reach other probes in the twelve-probe set too?** The
mechanism gives no reason to expect N08 is unique — ANY probe whose anchor file holds more real
definitions than fit under a pre-restriction top-6 crowded by unrelated same-named rows has the identical
shape. This is registered as an OPEN MEASUREMENT, not assumed either way, and is not itself part of the
pass/fail band: whatever the twelve-probe set shows is reported as data. **What DOES gate, regardless of
how many probes move, is the invariance criterion below** — it is what makes "more than N08 moved" a
FINDING rather than a defect.

**Registered invariance criterion, which outranks the band.** Three structural guarantees, checkable by
reading the diff (`restrictBodiesToRouteAnchor`/`isRouteAnchorSymbol` untouched; only the caller's control
flow reorders two existing calls) and confirmed by measurement on ALL twelve probes: (i) `<sigs>` — the
RANKED rows — are byte-identical, base vs. head, on every probe (this touches body SELECTION only, never
ranking); (ii) every probe's disclosed `anchors:` line is byte-identical (the anchor computation is not
in this diff's reach at all); (iii) any body that newly appears on ANY probe belongs to that probe's
ALREADY-resolved anchor file — no cross-file, no wrong-symbol serving is possible by construction, since
restriction still runs, just earlier.

**Registered controls.**

| control | why |
| --- | --- |
| `<sigs>` byte-compared on all twelve probes | the invariance criterion's own primary check |
| every probe's `anchors:` line byte-compared | this diff cannot reach anchor selection |
| N01, N05 (the T3 budget misses) | registered UNREACHABLE by the anchor-body round's own audit — a bare
`class X;` forward declaration crowding out a HUNDREDS-of-lines real definition is a byte-BUDGET question,
not a candidate-HEAD question; this reorder does not change which candidates are large, only which ones
are considered, so these two must stay `reason="budget"` |
| N04, N07 (the inert-branch controls) | the anchor-body round's own byte-pinned rows — a claimant that
already carries a body has nothing for either rule to prefer; must stay byte-identical |
| N11, N12 (ugrep) | item B already lands first in this branch; this reorder's effect on them, if any, is
measured on a corpus where the extraction gap is ALREADY closed, not the pre-item-B state |

**Registered guards, re-run after the change; any regression is a REVERT regardless of the band.** Same
lattice as both rounds above: skill routing (split=test/dev), judged routing, recall lane, ranking lane,
pollution, `run_r3diff.py` on the two frozen sets, determinism, `xmllint`, the full gate battery, G1. This
diff touches `main.cpp` only (no `kParserVer` bump — it is not an extraction change), so the blast radius
is smaller in kind than item B's, but the SAME lattice is re-run rather than assumed clean.

---

**Verdict: SHIP.** N08 flips **NO → YES** — rocksdb's `--for="Slice"` now serves `include/rocksdb/slice.h`'s
own class definition (and five more anchor-file candidates) where it served nothing before. The reorder
is **not N08-specific**, exactly the open question this registration named rather than pre-answered: N02,
N06, N10 and N12 also gain served bodies from the same crowding pattern, at varying severity. Every
registered invariance guarantee holds without exception on the full twelve-probe set: `<sigs>` byte-
identical on all twelve, every disclosed anchor byte-identical on all twelve, and every newly-served body
on every moved probe belongs to that probe's own, already-correctly-resolved anchor file — confirmed by
inspecting content, not assumed from the count. Every registered floor reproduces to the digit, both
frozen `r3diff` sets are 74/74 ties, and G1 is clean including the exact N08 path and three of the other
four probes that moved.

**Provenance.** Branch `lane/candhead-ugrep`, same worktree, stacked on item B's already-landed
`3715ca8`. Commits: `8e21380` (registration, result-free) → `8885183` (red gate, verified RED against a
binary built from `3715ca8` — item B alone, item A absent) → `86d7956` (the fix) → `c3a7d64` (a
complexity-reducing refactor `--quality-delta` itself called for — `computeAutoBodyCandidateIds` extracted
out of `buildForAutoBodies`, no behavior change) → `6f16b83` (a fixture rename: the gate's original
`Widget` symbol collided with this repo's own dozen pre-existing, unrelated `Widget` fixtures on
`--quality-delta`'s documented bare-name api-surface key — traced to `src/quality.h`'s own canonical-id
note on that mechanism, not a real regression, fixed by renaming to `Frobnicator` rather than suppressing
with an ack) → `8a46946` (a
`README.md` `--callers` example re-pin the first full battery run on this diff caught, the same drift
class the anchor-body round hit for the same reason — new lines above `churnRankedGraph`/`runDefaultMap`
shifted both by 40).

**Result — the twelve-probe set, base (a binary built from `3715ca8`, item B landed, item A absent) vs.
this lane's final head.**

| id | corpus | query | `<sigs>` | anchor | bodies served, base → head |
|---|---|---|---|---|---:|
| N01 | DD | `ClientContext` | byte-identical | unchanged | 0 → 0 (unreachable — T3 budget miss, as registered) |
| N02 | DD | `DatabaseInstance` | byte-identical | unchanged | **1 → 3** |
| N03 | DD | `Serializer` | byte-identical | unchanged | 1 → 1 |
| N04 | DD | `TableCatalogEntry` | byte-identical | unchanged | 1 → 1 (inert-branch control, as registered) |
| N05 | DD | `Deserializer` | byte-identical | unchanged | 0 → 0 (unreachable — T3 budget miss, as registered) |
| N06 | DD | `Catalog` | byte-identical | unchanged | **0 → 1** |
| N07 | RD | `ColumnFamilyData` | byte-identical | unchanged | 1 → 1 (inert-branch control, as registered) |
| N08 | RD | `Slice` | byte-identical | unchanged | **0 → 6 — THE TARGET** |
| N09 | RD | `SystemClock` | byte-identical | unchanged | 1 → 1 |
| N10 | RD | `Logger` | byte-identical | unchanged | **2 → 4** |
| N11 | UG | `dos_streambuf` | byte-identical | unchanged | 6 → 6 (already at the cap via item B alone) |
| N12 | UG | `streambuf` | byte-identical | unchanged | **4 → 6** |

**Every moved body traced to its content, not just its count.** N02 (`DatabaseInstance`) gains a second
constructor from `database.hpp`, the SAME anchor file. N06 (`Catalog`) gains a `sec` body from
`src/README.md`, the SAME anchor file (a markdown section is what this anchor always was). N10 (`Logger`)
gains a second `cls` definition (a second, genuinely different `Logger` declaration inside
`include/rocksdb/env.h`) and a third constructor — all `env.h`, the SAME anchor file; one of the four is
itself a bare forward declaration (`class Logger;`), a pre-existing, disclosed characteristic named below,
not a defect this round introduces. N12 gains a `cls` definition from `include/reflex/input.h`, the SAME
anchor file. **No probe, on any corpus, ever serves a body from a file other than its own already-
resolved anchor** — checked by reading every new `<b p=…>` path, not inferred from the shown-count delta.

**Guards — green, and identical to the digit.**

| Guard | Floor / ceiling | base (`3715ca8`) | with item A |
|---|---:|---:|---:|
| skill routing split=test `bm25-desc` hit@1 / sep-auc | ≥ 60.0% / ≥ 0.89 | 73.1% / 0.957 | 73.1% / 0.957 |
| skill routing split=dev hit@1 / sep-auc | ≥ 46.0% / ≥ 0.75 | 69.1% / 0.887 | 69.1% / 0.887 |
| judged-only `bm25-desc` / `for-routed` hit@1 | ≥ 50% / ≥ 50% | 98/152 / 92/152 | 98/152 / 92/152 |
| recall lane lenient recall@5 / MRR | ≥ 71% / ≥ 0.57 | 88.1% / 0.643 | 88.1% / 0.643 |
| ranking lane lenient recall@5 / MRR | ≥ 70% / ≥ 0.55 | 71.9% / 0.639 | 71.9% / 0.639 |
| LIVE / ranking / adversarial pollution@5 | ≤ 16% / ≤ 5% / ≤ 8% | 2.4% / 0.0% / 0.0% | 2.4% / 0.0% / 0.0% |
| `run_r3diff.py` ranking (n=32) | near-all ties | — | **32 ties, net +0** |
| `run_r3diff.py` recall (n=42) | near-all ties | — | **42 ties, net +0** |
| determinism (map, `--for`) + `xmllint` | contract | — | byte-identical, well-formed |
| G1 — ASan/UBSan/integer/LSan, self + the exact N08/N02/N12 paths + the gate | no report | — | **clean, exit 0, empty stderr** |
| `--quality-delta=518fe0d..HEAD` | no gating regression | — | `gating="0"` (12 `sev="minor" origin="new-symbol"` rows, all fixture classes) |
| full gate battery, frozen tree | all green | — | **`gates=465 pass=463 skip=2 fail=0`** |

**Findings for the next round.** (1) N10's newly-served bodies include one bare forward declaration
(`class Logger;` at `env.h:53`) riding alongside three real definitions — the candidate-head-bound fix
correctly restricts to the anchor's own file and correctly orders body-carrying candidates ahead of
bodyless ones (the def-over-decl tiebreak, untouched here), but the cap still has room left over on this
particular probe and fills it with whatever ranks next, bodyless or not. Not a regression this round
introduces — the SAME thing already happens on any probe whose anchor file holds more candidates than fit
under the K=6 cap, with or without this fix — but worth a future round asking whether the auto-body
candidate selection should prefer body-carrying candidates WITHIN a file the way the ranking and anchor
selection already do. (2) The registered open question is answered: the reorder is not N08-specific. Any
future probe set drawn from a header-heavy, cross-language, or multi-definition corpus should expect the
same shape whenever an anchor's own file holds real definitions crowded out by unrelated same-named rows
elsewhere — worth naming as an expected consequence rather than a surprise in future audits of this class
of fix.

---

## Merge recompute (2026-08-25) — the twelve-probe `BODY-SERVED` set at the merged head

**This section is a RECOMPUTE, not a registration.** It records nothing anyone predicted in advance and
grades nobody's band. Three lanes off `518fe0d` — `lane/candhead-ugrep`, `lane/t3-body-budget` and
`lane/recall-rootrel-rank` — each measured this probe set against its own head, and two of them changed
`buildForAutoBodies`. A number measured with one lane's fix in and the other's out is not the number the
merged tree produces, so the set was re-measured at the merge. **Each lane's own recorded in-band result
above stands exactly as that lane recorded it; nothing here overwrites or re-grades it.**

`BODY-SERVED` is unchanged in definition: the gold DEFINITION's own body emitted in `<bodies>` by a plain
`--for="<Name>"`, gold pinned as the `(name, path, LINE)` triple (the T3 round's scoring correction —
a path-only predicate inflates N11/N12 by counting the bare in-class declarations at `input.h:333/:335`).

Corpora are the pinned checkouts, rev-counts re-verified at recompute time: duckdb `19864453` (48,632),
rocksdb `0e2801ac` (12,938), ugrep `550599a6` (985). All four binaries measured with the same script.

**Instrument check first: the `518fe0d` binary reproduces `4 / 12` row for row, and every `total=` matches
the T3 round's recorded table to the digit.** No result below was believed before that agreed.

| id | corpus | query | base `518fe0d` | candhead `522a295` | t3 `6203024` | **MERGED `d7276d6`** |
|---|---|---|:---:|:---:|:---:|:---:|
| N01 | DD | `ClientContext` | no — `budget` | no — `budget` | **YES** | **YES** |
| N02 | DD | `DatabaseInstance` | YES | YES | YES | **YES** |
| N03 | DD | `Serializer` | YES | YES | YES | **YES** |
| N04 | DD | `TableCatalogEntry` | no | no | no | no |
| N05 | DD | `Deserializer` | no — `budget` | no — `budget` | **YES** | **YES** |
| N06 | DD | `Catalog` | no — `no_candidates` | no | no — `no_candidates` | no |
| N07 | RD | `ColumnFamilyData` | no | no | no | no |
| N08 | RD | `Slice` | no — `no_candidates` | **YES** | no — `no_candidates` | **YES** |
| N09 | RD | `SystemClock` | YES | YES | YES | **YES** |
| N10 | RD | `Logger` | YES | YES | YES | **YES** |
| N11 | UG | `dos_streambuf` | no | **YES** | no | **YES** |
| N12 | UG | `streambuf` | no | **YES** | no | **YES** |
| | | **`BODY-SERVED`** | **4 / 12** | **7 / 12** | **6 / 12** | **9 / 12** |

**The merged set is the exact UNION of the two lanes' gains, and nothing more.** candhead gains
`{N08, N11, N12}`, t3 gains `{N01, N05}`, base holds `{N02, N03, N09, N10}`: 4 + 3 + 2 = 9. Checked in
both directions rather than by adding up — **no probe is served at the merged head that neither lane
served alone (no super-additive row), and no probe served at a lane head is lost at the merge.**

### The predicted interaction is REFUTED, and the mechanism runs the other way

The merge was expected to be super-additive: restricting to the anchor BEFORE the top-K cut should make
the one-candidate case fire more often, so T3's `autoBodyIds.size() == 1` allowance should reach probes it
could not reach alone, and the merged number should exceed the union. **It does not, and the candidate-set
sizes say why.** Every probe whose candidate-set size moves under the candhead reorder moves **UP**:

| probe | `<bodies total=>` base → candhead |
|---|---|
| N02 | 1 → 3 |
| N06 | 0 → 1 |
| N08 | 0 → 6 |
| N10 | 2 → 4 |
| N11 | 5 → 6 |
| N12 | 4 → 6 |

That is the fix working as designed, not a surprise: taking the head AFTER the restriction means the
anchor's own rows are no longer displaced out of the K=6 window by unrelated same-named rows elsewhere, so
**more** of the anchor's own definitions survive into the candidate list. Restrict-before-cut therefore
pushes candidate sets **away from** `size() == 1`, not toward it.

The population `size() == 1` can fire on is **7 probes before the reorder and 7 after** — not a growth but
a swap: N02 leaves it (1 → 3) and N06 joins it (0 → 1). N06 gains nothing from the raise, because its one
surviving candidate is the `src/README.md:15` markdown-section claimant and not the gold, so the raise
funds a body that was never the answer and `BODY-SERVED` correctly stays `no`.

**The two rules are therefore orthogonal on this probe set**: T3's allowance fires on N01 and N05, both of
which sit at `total="1"` in all four arms, and the candhead reorder never touches either. The reason the
merged number beats both lanes is simply that each lane's rows are disjoint.

### What did not move

Every served body at the merged head belongs to its own probe's anchor file — checked by reading each
emitted `<b p=…>` path, not inferred from the count. The two shapes prior rounds disclosed are still
present and still disclosed, neither introduced nor worsened here: N10 carries the bare `class Logger;`
forward declaration at `env.h:53` alongside three real definitions (the K=6 cap filling leftover room), and
N11/N12 carry the bare in-class declarations at `input.h:335`/`:333` (which is why the gold is scored as a
line-pinned triple). N04, N06 and N07 remain unserved for the three reasons already recorded — an
already-body-carrying out-of-line constructor, a markdown-section claimant, and an out-of-line constructor
respectively — and none of them is a budget or a candidate-head question.

## The scope-less quality-key fold (2026-08-25) — PRE-REGISTERED, before any fix code

**What this registers.** The 2026-08-24 identity round (`6cd5ba5`) closed the rename/move case and filed
one residual it deliberately did not absorb: *"canonicalId degrades to a BARE NAME for scope-less symbols,
so the canonId key space is not path-qualified for them and folds them across files — the same class of
bug already fixed for churn's key space, still open for the other seven kinds."* This section registers the
fix for that residual, and corrects two things about how it has been described.

**Correction 1 — "seven kinds" is seven QUALITY kinds, not seven symbol kinds.** There is ONE defect:
`resolve.h`'s `canonicalId` returns the bare name when `scope` is empty. Seven of `--quality-delta`'s ten
finding kinds inherit it because seven key spaces derive from it — `ccx` (complexity), `loc` (verbosity),
`nest` (nesting), `params`, `mask` (error-masking), `dead` (dead-code), `api` (api-surface). The other
three are already elsewhere: short-horizon-churn moved to `pathQualifiedKey` in `d593de3`, and the
two clone kinds key on a member-set hash. 7 + 1 + 2 = 10, and `--quality-baseline` emits exactly those
spaces (`defs` is an eighth canonId-keyed space, but it is internal overload cardinality, never a
reported kind).

**Correction 2 — the affected ack count is 270, not "~300".** Measured at this lane's base `7a42a67`
against the merged 476-row ledger, not carried from the pre-merge investigation.

**The mechanism, stated so it can be wrong.** `quality.h`'s `computeSnapshot` and `computeDelta` both key
on `fnv1a64( baselineCanonId( ing, i, root ) )`. For a scope-less symbol `baselineCanonId` is the bare
name, so the key is `fnv1a64(name)` — **path-independent**. Every scope-less `ok()` in the tree is one
identity, and `perSymbolKind` aggregates the fold with `max()`, so the reported magnitude belongs to
whichever file's symbol is largest.

Measured at `7a42a67` (1,368 files, 11,811 symbols), via the default map's `id=` attribute, which
`serialize.h:1771` emits under exactly `if( canon != s.name )` — so absent `id=` is an exact scope-less
discriminator, not a heuristic:

| | rows | distinct canonIds | identities lost to the fold |
| --- | --- | --- | --- |
| scope-less | 6,418 (56.4%) | 3,845 | **2,573** |
| scoped | 4,953 | 4,898 | 55 (legitimate same-file overloads) |
| total | 11,371 | **8,743** | |

Method validation: that 8,743 is derived out-of-band (a parse of the shipped binary's own map) and equals
the binary's own `ccx` key-space cardinality exactly. The path-qualified space (`bodyq`) holds 11,311.

**What the fix is — and what it deliberately is NOT.** It does **not** touch `canonicalId`. Path-qualifying
`canonicalId` itself was measured and rejected: it inflates the default map by **+293,886 bytes (+26.4%,
~73K tokens)** on this repo, because `id=` is currently omitted for all 6,418 scope-less rows — a direct
G4 breach — and `canonicalId` has 67 call sites across 11 files (resolver identity, selector grammar, MCP
handle source, notes key, merge-scout key). It would also SPLIT 21 correct folds: in `src/` there are 23
colliding scope-less names, and 21 are `extern "C" tree_sitter_X` declarations of the *same* C function
declared in both `ingest.cpp` and `main.cpp`. Of the remaining two, `it` is a local variable declaration
mis-extracted as a function via the most-vexing-parse ambiguity, and `main` (main.cpp vs tsprobe.cpp) is
the single true collision in shipping source.

The fix instead moves the seven kinds' key space onto the **`pathQualifiedKey` that already exists**
(`quality.h:381`), finishing the pattern `d593de3` started for churn and `mcpindex::stableHandleId`
started for MCP handles, rather than opening a third scheme. `canonicalId` answers *"which entity is
this?"* — and for the 21 declarations "one entity" is the correct answer, which is why that fold must
survive. The quality key must answer *"which piece of source is this?"*. The bug is that quality borrowed
the entity key to ask a source question.

**The migration, which is the actual risk.** All 270 canonId-keyed acks change key, because
`fnv1a64("p::s::n")` ≠ `pathQualifiedKey("p\0s\0n")` — different bytes. That is more rows than the 79
that would move under a naive path-qualification, and it is nonetheless the cheaper migration, because
the rule is computable exactly: for every symbol in the tree, both the old key and the new key are pure
functions of `(path, scope, name)`. The replay reuses the identity round's existing alias machinery
(`IdentityAliases` / `remapAckIdentity`) rather than adding a parallel mechanism — a scheme migration is
an old-key → new-key map, which is exactly what that machinery already consumes.

The one genuine hazard is disclosed rather than papered over: **the old side is many-to-one.** A folded
scope-less name has one old key and N new keys, so the replay cannot know which file's symbol the ack
meant. Those refuse and are counted, never guessed — the same floors-not-guesses rule the rename route's
ambiguous-ancestor refusal already applies.

**REGISTERED BAND.** Measured at `7a42a67`, on this repo's own 476-row ledger:

| metric | band | why this number |
| --- | --- | --- |
| `ACKS-PRESERVED` (re-filed by replay) | **exactly 257** | 184 scoped (always 1:1) + 73 unambiguous scope-less |
| `ACKS-AMBIGUOUS` (refused, each named) | **exactly 6** | `complexity main`, `verbosity main`, `dead-code it`, `dead-code any10`, `dead-code strict10`, `params run_one` |
| `ACKS-ORPHANED` (already stale, each named) | **exactly 7** | complexity 3 + verbosity 4; dead before this round, resolve rate 97.4% |
| `ACKS-SILENTLY-DROPPED` | **0 — hard gate** | the failure mode this round exists to prevent |
| default-map bytes vs `7a42a67` | **0, byte-identical — hard gate** | proves `canonicalId` was not touched; the G4 protection |
| `FOLD-ELIMINATED` (scope-less quality identities) | **3,845 → 6,418 (+2,573)** | deterministic, not statistical — a different number means the key rule is wrong |
| guard lattice (routing, recall, ranking, pollution, r3diff) | **all unchanged** | the change cannot reach retrieval; the byte-identical map gate proves the confinement mechanically |

257 + 6 + 7 = 270. Any row unaccounted for by those three buckets is a silent drop and fails the gate.

**Out of scope, stated rather than quietly skipped.** The two CLONE kinds keep their member-set hash, and
their member ids keep using `baselineCanonId` — so a clone group over scope-less members still folds. That
is the same floor the identity round recorded for clone acks, unchanged here and not fixed by guessing.
The `it` extraction defect (a local variable indexed as a function) is an extraction question, not a
keying one, and is untouched.

### RESULT — measured at `a26ae61`/`93d7173`, against the band registered above

| metric | registered | measured | verdict |
| --- | --- | --- | --- |
| `ACKS-PRESERVED` | exactly 257 | **260 rows moved** (259 counted + 1 merged) | **band missed by +3, in the honest direction** — see below |
| `ACKS-AMBIGUOUS` (named) | exactly 6 | **6**, each named | **met exactly** |
| `ACKS-SILENTLY-DROPPED` | 0 — hard gate | **0** — 95 distinct hand-written reasons before, 96 after (the one added is this lane's own ack), none lost | **met** |
| default-map bytes | 0, byte-identical — hard gate | **1,128,344 = 1,128,344**, identical file/symbol/edge counts | **met** |
| `FOLD-ELIMINATED` | 3,845 → 6,418 (+2,573) | **8,743 → 11,312 canonId-space identities (+2,569)** | **met, 4 short, fully explained** |
| `ACKS-ORPHANED` (named) | exactly 7 | **8 target-gone pre-existing** (7 + one legacy churn row) | +1, same cause as the +3 |
| guard lattice | unchanged | unchanged — the byte-identical map proves the confinement | **met** |

**Why `ACKS-PRESERVED` missed by 3, recorded rather than rounded away.** Registration predicted 257 =
184 scoped + 73 unambiguous scope-less. The replay moved 260. The extra three are `short-horizon-churn`
rows still keyed in the *canonId* space — acks written BEFORE `d593de3` moved churn to
`pathQualifiedKey`, which nothing has healed since. The pre-registration classified all churn acks as
already-path-qualified, which is true of every row written after `d593de3` and false for those three. They
are a bonus heal of long-dead legacy rows, and the same three explain the orphan count landing at 8
rather than 7.

**Why `FOLD-ELIMINATED` landed 4 short of the registered figure.** The registered +2,573 was counted in
map ROWS; the key space counts IDENTITIES, and `pathQualifiedKey(relPath, scope, name)` does not include
the symbol KIND. Four same-file/same-name pairs carrying two different kinds — `Widget` as both a `cls`
and a `method` in `bench/h4fixtures/java/Main.java`, `csharp/Main.cs` and `test/swiftshapefix/
ProtocolSurface.swift` — therefore share one identity. 8,743 + (6,414 − 3,845) = 11,312, exactly the
measured value. This is a pre-existing property of `pathQualifiedKey` that short-horizon-churn has had
since `d593de3`; it is inherited here, not introduced, and is recorded as a floor rather than fixed by
adding a kind byte to a key space three other subsystems already share.

**The convergence that says the fix landed.** On the identical tree, `ccx`/`loc`/`nest`/`params`/`defs`
now all hold 11,312 identities and `bodyq` (churn, path-qualified since `d593de3`) holds 11,311. The
seven kinds and churn occupy one key space again, which was the entire point.

**The behavioural proof, not just the counting one.** `test/qualitykeycheck.sh` arm (A): a function
going ccx 1 → 18 beside a same-named scope-less neighbour at ccx 23 reported `regressions="0"` before
this change and is reported and located at the right file after it. Arm (F) pins that `canonicalId` did
not move — scope-less symbols still emit no `id=` — which is what keeps the +26.4% map inflation off the
table.

## The paper-shape lane (2026-08-28) — motivation note, result-free

Two changes landed on `lane/paper-shape`, both surfacing, neither measured here (no result is claimed
and no band was registered — this note records only WHY the shapes exist, so a later round can measure
against the right question).

**`--compress` composes with the body-serving bundles.** arXiv 2607.09691 (July 2026) measured that,
once localization is fixed, compressed SOURCE matches whole files for ACTING at roughly a third of the
tokens — and that signatures/summaries add nothing to acting quality. Read through this tool's serving
shapes, that says the tokens that matter are the ones spent on SERVED BODIES — `--for`'s terminal
auto/anchor bundle and `--pack-task`'s bodies section — not on the signature head. So the same
`compressBody` pass `--expand` already had now composes with bare `--for` (the guard previously
admitted only `--detail>0`), and every `<bodies>` element discloses the mode as `compress="1"`.
Flagless output is byte-identical by gate (`test/forcompresscheck.sh`, red-first against `1dc7b01`).

**Ranking-confidence disclosure on `--for`.** arXiv 2607.24882 (Agent Retrieval Bench, July 2026)
names abstention/confidence as the unsolved retrieval axis: retrievers cannot tell the caller when the
ranking is not trustworthy. `--for` already computes the relevance-cliff gap statistic (`adaptiveCut`,
the `--adaptive` lever); the header now states what that statistic already knows — `confidence=` /
`margin_pct=` as facts with a legend sentence — with no behavior change and no new scorer.
## The `--slice` def-use primitive (2026-08-28) — REGISTERED CONTRACT, no numbers yet

**Motivation.** ARISE (arXiv:2605.03117) measured statement-level definition-use edges exposed as a
queryable agent primitive at +17pp Function Recall@1 on SWE-bench Lite. ripwire's graph stops at symbol
granularity; `--slice=SYM[:VAR]` is the bounded v1 of that primitive and this paragraph registers what
it CLAIMS, before any accuracy number is published for it.

**The claimed contract (all of it gate-pinned in `test/slicecheck.sh`, none of it a measured accuracy
claim).** One `<s l= k= t=>` row per source line touching VAR inside the ONE uniquely-resolved
definition SYM, source order; `k=` def/use/both per line, `t=` the strongest role
(param > decl > assign > call-arg > read), `defs=`/`uses=` occurrence counts; bare `--slice=SYM` lists
the sliceable locals. NAME-BASED and intra-procedural by declaration: no alias analysis, no flow
sensitivity, nested-scope shadowing may over-include — all three limits are in the emitted legend, and
the not-served languages (everything outside C/C++/ObjC(+CUDA/Metal), Python, JS/TS, Go, Java, Rust)
refuse at exit 1 rather than empty-succeed. Ambiguous selectors refuse with the qualifying spellings
(the same ambiguity-refusal rule and `editCheckGroups` machinery `--edit-check` uses).

**The eval this registers for a later round — a LINE-RECALL shape, not run yet.** Mine fix commits whose
diff touches exactly one function (the `--affected`/co-change harness already isolates these); for each,
take the variables named on the changed lines and ask whether `--slice=fn:var` surfaces those changed
lines among its rows (hit = every changed line touching `var` appears; report line-recall and the
over-inclusion ratio rows-emitted / lines-relevant, per language family). Baseline arm: the whole
function body via `--expand` (the primitive's value claim is fewer tokens for the same lines, so both
recall AND the token ratio must be reported together, per the §5 discipline). No number from this shape
is published until that round runs to completion under its own pre-registration — this paragraph is the
registration, not the result.
## `--slice-flow` — ARISE rung 2, cross-statement data-flow slicing (2026-08-30) — REGISTERED CONTRACT

**The paper's own mechanism, read before this was designed.** ARISE's ablation credits its data-flow
slicer with the largest single component of the +17pp Function Recall@1 (0.50 → 0.57 of the 0.43 → 0.60
total; Line Recall@1 0.26 → 0.41 overall), and the paper is specific about what that slicer is: def-use
edges by the reaching-definition rule ("for each use of variable v at statement s, the last preceding
definition of v in source order within the same function"), a seed plus a direction (backward, forward
or both), a bounded BFS over those edges that **stops at function boundaries** — inter-procedural
expansion belongs to its call-graph ranking tier, not the slicer. Rung 2 lands that mechanism on the v1
substrate: `--slice=SYM:VAR --slice-flow=back|fwd|both [--slice-depth=N]`.

**The claimed contract (all of it gate-pinned in `test/sliceflowcheck.sh`, red-first against the
pre-lane binary; none of it an accuracy claim).** Bounded BFS from the seed variable over
line-granular reaching-definition edges: `back` = statements whose values feed the seed, `fwd` =
statements the seed's value reaches (a reached line that defines another variable carries the value
onward), `both` = the union, backward first, deduplicated. Flow rows extend the v1 `<s>` row with
`v=` (the variable at that step), `d=` (BFS depth; seed rows are depth 0) and `f=` (the line the step
was reached from), ordered by (d, line, variable) as a stated contract. `depth=` always states the
bound in force (default 8, `--slice-depth=1..32`); a bound that suppresses a novel row is disclosed as
`flow_truncated="1"` — bounded-here, never proven-complete. Without the new flags the v1 output is
byte-identical (verified against the pre-lane binary). Modifier misuse refuses loudly: `--slice-flow`
alone, on the bare inventory (no seed VAR), an unknown direction, `--slice-depth` without
`--slice-flow`, depth outside 1..32.

**Deviations from the paper, deliberate and disclosed in the emitted legend:** (1) statement ≈ source
LINE — rows aggregate per line, so a multi-statement line merges and may over-connect (the paper keys
on AST statement nodes); (2) name-based and scope-insensitive like v1 — no alias analysis, no lexical
scope separation (the paper handles global/nonlocal explicitly), shadowing may over-include; (3) the
seed is the whole variable inside ONE resolved definition (v1's addressing), not the paper's
(file, line, variable) triple — a line seed is recoverable by reading the d=0 rows. The paper's
Python-only substrate widens here to v1's six served families, with the classification tables v1
already grep-verified per vendored grammar.

**The measurement this registers — protocol fixed BEFORE either arm runs.** The v1 paragraph above
registered a line-recall shape; this round executes it and extends it with a paired v2 arm, on a
corpus registered here as: fix-shaped commits mined from THIS repository's own history (family: cpp —
the one family this corpus can speak for, stated rather than averaged away), newest first, a commit
qualifying when `git diff -U0` against its parent confines every added line to ONE function per git's
own C/C++ hunk funcnames, that function resolves uniquely in the index at that commit, and at least
one added line names a sliceable local. Instances are (commit, function, variable) triples: the
variables named on the added lines that appear in the function's `--slice=fn` inventory. Arms, all
measured on the SAME instances at the commit's own tree: (a) **v1** `--slice=fn:var` — per-variable
line-recall (hit = every added line naming var appears among its rows) and rows-emitted /
lines-relevant over-inclusion, the v1 paragraph's own metrics; (b) **v2** `--slice=fn:var
--slice-flow=both` — FUNCTION-level added-line recall (|added lines ∩ slice lines| / |added lines|,
per instance) for the v1 rows vs the v2 rows, the delta being rung 2's whole value claim: flow rows
recover related changed lines the flat single-variable slice cannot see; (c) **`--expand=fn`** — the
whole-body baseline, recall 1.0 by construction, priced in raw output bytes (the §5 discipline: recall
and cost reported together, bytes not estimated tokens). Harness: `bench/slice/run_slicerecall.py`,
deterministic given the commit list; the instance cap (newest 40 qualifying commits) is part of this
registration. Numbers from this protocol land in this section and nowhere public until an owner pass.

**Measured 2026-08-30, first run of the registered protocol** (binary at the rung-2 feature commit;
"fix-shaped" operationalized in the committed harness as subject containing `fix`, case-insensitive;
the miner takes every non-merge commit, not first-parent only, because this repository lands work
through merged lanes). The corpus could speak less than the cap: the ENTIRE history yields **10**
single-function fix-shaped candidates, of which **7 commits** survive unique resolution and produce
**38 (commit, function, variable) instances** — cpp family only, and a thin corpus is reported as
thin rather than padded.

| metric | value |
| --- | --- |
| v1 per-variable line-recall (mean) | **0.726** |
| v1 hit-all rate (every added line naming var among its rows) | **0.632** |
| v1 over-inclusion (rows emitted / lines relevant, mean) | 3.77× |
| function-level added-line recall, v1 rows (mean) | 0.163 |
| function-level added-line recall, v2 `--slice-flow=both` rows (mean) | **0.198** |
| output bytes, mean: v1 / v2 / `--expand` | 2 043 / 4 993 / 20 034 |

Reading, with the caveat that owns most of the headline: the v1 line-recall misses were inspected
per instance and are dominated by the RELEVANCE ORACLE, not the slice — the protocol's "changed line
touching var" is a word-regex over added lines, which matches short identifiers (`s`, `i`, `d`,
`out`, `ok`) inside **comments and string literals** (e.g. cff49a6d2's added refusal-wording lines),
occurrences the classifier correctly refuses to call variable occurrences. The measured 0.726 is
therefore a floor under a noisy oracle; no instance inspected showed a real identifier occurrence
the slice dropped. The rung-2 delta on this corpus is modest and stated plainly: `--slice-flow=both`
lifts function-level added-line recall 0.163 → 0.198 (+3.5pp) at 2.4× the v1 bytes — and at **25%
of the `--expand` bytes** for the whole-body baseline whose recall is 1.0 by construction. On
fix-commits this granular (median single-function diffs here are small), the flat v1 slice already
carries most of what flow can add; the ARISE-shaped payoff is expected where the changed lines
span several variables of one computation, which this thin corpus rarely exhibits. Published to the
README's What's-new (2026-08-30) on an owner pass, caveats carried with the numbers (deck untouched);
a wider-corpus rerun (the SWEX/ARB trees
carry no usable per-commit git history for this shape, so an external corpus with history would need
pinning first) is future-round material, not this registration.

**Contract addendum — the line seed (2026-08-31, lane/tc-sliceat; surface only, no numbers).** ARISE
seeds its slicer at *(file, line[, variable])*; the registration above addressed by *(symbol,
variable)*. `--slice` now takes the line seed through the existing at machinery, both spellings —
`--at=FILE:LINE` beside `--slice` (no longer a dropped competing verb) and the `--slice=@FILE:LINE`
selector: the definition sliced is the innermost indexed one enclosing the seed line; a seed narrows
an otherwise-ambiguous SYM to the enclosing definition; a seed enclosed by none of SYM's definitions
refuses naming both sides; a plain-identifier spec beside `--at` reads as the seed's VARIABLE. A seed
line naming exactly ONE sliceable local pre-picks it, disclosed (`seed=`, `var_from="seed"`); zero or
several serve the inventory with `seed_vars=` and the candidate `<v>` rows marked `seed="1"` — never a
guess. v1/v2 slice semantics, bytes and refusals are unchanged on every unseeded invocation (gate arm
22), and the pre-picked slice's rows are the same scan a `:VAR` spec runs. Gate:
`test/sliceflowcheck.sh` arms 11–24, red-first against the 5c6a6fd binary (18 FAILs recorded). The
same lane lands the MCP `slice` verb (tools/list 30→31) mirroring this CLI contract
refusal-for-refusal — one emitter (`sliceBundleText`) on both surfaces, payloads byte-identical on
the same root/spec — gated by `test/mcpslicecheck.sh` (red-first: 22 FAILs on the pre-verb binary).


**Wider-corpus extension — REGISTERED 2026-08-31, before a single external instance was measured.**
The 2026-08-30 run above closed asking for a corpus with real per-commit history. The pinning that
sentence asked for already exists in this document: the **D4-frozen external repositories**, three
C/C++ trees with full history, re-clonable and revision-count-verified at their pinned SHAs —
**duckdb `19864453`** (48632 revs), **rocksdb `0e2801ac`** (12938 revs), **ugrep `550599a6`**
(985 revs). This paragraph extends the protocol to those three and fixes every choice before the
harness runs against them; no pin is invented here, the D4 SHAs are reused verbatim so the corpus of
this rung and the corpus of the churn lanes are the same frozen trees.

*Unchanged from the 2026-08-30 registration, deliberately:* the instance-qualification rules
(fix-shaped subject, `git diff -U0` against the first parent confining every added line to ONE
function per git's own C/C++ hunk funcnames, that function resolving uniquely in the index at that
commit, at least one added line naming a sliceable local from the function's own `--slice` inventory);
the three arms (**v1** `--slice=fn:var`, **v2** `--slice=fn:var --slice-flow=both`, **`--expand=fn`**
priced in raw output bytes); and every metric definition. The cap is the same **newest 40 qualifying
commits, applied PER REPO** — three independent draws, not one pooled 40. Mining walks each repo's
log from its pinned SHA, so the commit list is a function of the pin alone and the run is
deterministic in the same sense the first one was.

*The decision framing, fixed here so it cannot be chosen after seeing scores:* these numbers
**EXTEND** the 2026-08-30 table, they do not replace it and are **never averaged into it**. Each repo
is reported as its own row set with its own instance count; the ripwire-history run stays a separate,
separately-labelled result. All four corpora are cpp-family, so the family split is trivial here — it
is still stated per corpus rather than collapsed, because the point of the extension is precisely
that a 38-instance in-tree draw and a large-repo draw are different populations. A repo that yields
few or zero qualifying instances is reported as such: a zero is a finding about the qualification
rules (basename selector ambiguity in a large tree, funcname heuristics, deletion-heavy fixes), not
an outcome to be quietly dropped. The v1 line-recall misses are inspected the way the first run
inspected them — sample the misses and say, per repo, whether they are the relevance oracle's
word-regex noise or real drops by the slicer. Numbers land in this section and nowhere public until
an owner pass.

**Measured 2026-08-31, the wider-corpus run of exactly that protocol.** Binary: this lane's plain
`build/ripwire` at the registration commit. Each pinned tree was COPIED to a throwaway location and
left DETACHED at its pin — the D4 originals were not written to — and the harness mined and checked
out inside the copy. Two adaptations were needed for the external path and both are committed
separately with their reasoning: byte-tolerant subprocess decoding (ugrep's own test fixtures are
deliberately non-UTF-8 and aborted the mine) and a bounded retry of the per-commit checkout (a
blob-filtered clone materializes blobs from its promisor remote, and one such fetch failed
transiently 40 commits into duckdb). Neither touches qualification, arms or metrics; per-reason skip
counters were added for the disclosure below. Total wall time for all three repos ≈ 10 min
(duckdb 4:05, rocksdb 5:30, ugrep 0:44), so no repo was dropped and the reduction clause the
registration allowed for was not used. Determinism was re-checked the way the rest of this document
checks it: duckdb and ugrep were re-run end to end, and both the summary and every per-instance row
compared identical.

What each corpus actually yielded — the mine takes 3× the cap in candidates, so "120" means the
over-mine bound was reached, not the history exhausted:

| corpus | pin | revs | single-function fix-shaped candidates | commits used | instances | thinned by: selector unserved / empty inventory / no touched var |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| duckdb | `19864453` | 48632 | 120 (over-mine bound) | 40 (cap) | **90** | 34 / 3 / 6 |
| rocksdb | `0e2801ac` | 12938 | 120 (over-mine bound) | 40 (cap) | **98** | 63 / 1 / 10 |
| ugrep | `550599a6` | 985 | 16 (**entire history**) | 2 | **5** | 12 / 0 / 2 |
| ripwire (2026-08-30) | — | — | 10 (entire history) | 7 | 38 | not counted then |

Per repo, never pooled and never averaged with the 2026-08-30 column, which is reproduced here only
so the two populations can be read side by side:

| metric | duckdb | rocksdb | ugrep | ripwire (2026-08-30) |
| --- | ---: | ---: | ---: | ---: |
| v1 per-variable line-recall (mean) | **0.911** | **0.864** | 0.800 | 0.726 |
| v1 hit-all rate | 0.889 | 0.837 | 0.800 | 0.632 |
| v1 over-inclusion (rows emitted / lines relevant) | 4.96× | 4.49× | 20.47× | 3.77× |
| function-level added-line recall, v1 rows | 0.547 | 0.421 | 0.582 | 0.163 |
| function-level added-line recall, v2 `--slice-flow=both` | **0.597** | **0.469** | 0.582 | 0.198 |
| the rung-2 delta | **+5.0pp** | **+4.7pp** | +0.0pp | +3.5pp |
| instances where v2 > v1 / = v1 / < v1 | 14 / 76 / 0 | 17 / 81 / 0 | 0 / 5 / 0 | not counted then |
| output bytes, mean: v1 / v2 / `--expand` | 2 059 / 4 116 / 4 384 | 2 024 / 3 839 / 7 008 | 7 341 / 22 592 / 28 930 | 2 043 / 4 993 / 20 034 |
| v2 bytes as a share of `--expand` | **94%** | **55%** | 78% | 25% |

**Reading. (1) The rung-2 delta reproduces, in sign and in size.** +5.0pp and +4.7pp on 90 and 98
instances against +3.5pp on the in-tree 38 — the first run's modest number was not an artifact of a
thin corpus, it is what this mechanism is worth on fix-shaped single-function commits. Stronger than
the means: across all 193 external instances, **no instance moved DOWN** (31 up, 162 unchanged). The
flow rows are additive by construction, so this is a consistency check passing rather than a
surprise, but it is the check that would have caught over-connection.

**(2) The cost claim from the first run does NOT generalize, and that is the finding that matters.**
In-tree, v2 bought its recall at 25% of the `--expand` bytes. Here it is 55% (rocksdb), 78% (ugrep)
and **94% (duckdb)** — on duckdb the flow slice costs essentially the whole function body, for 0.597
recall against `--expand`'s 1.0. The mechanism is not doing anything different; the corpus is. These
repositories' fix-touched functions are SHORT (duckdb `--expand` mean 4 384 B against ripwire's
20 034 B), and a bounded flow slice cannot be much cheaper than a body it nearly covers. The honest
statement of the primitive's value claim is therefore conditional: **`--slice-flow` buys its recall
at a real discount only where the enclosing function is large.** On small functions, `--expand`
dominates it — full recall for comparable bytes.

**(3) The misses were CLASSIFIED, not sampled** — every one of the 50 missed relevant lines across
the three repos, by whether the variable's occurrence on that line is a comment, a string, a member
access on another object, outside the resolved function, or a genuine identifier occurrence the
slice dropped. rocksdb: **29 of 29 are oracle noise** (26 comment, 2 member, 1 string) — zero real
drops in 98 instances, and the first run's diagnosis reproduces exactly. duckdb: 10 missed lines →
4 comment, 3 member access (`state[i]->data`, `list_entry.offset` — the slice is *correct* to
exclude these; the word-regex oracle is not), 1 mining artifact (git's funcname heuristic attributing
a newly INSERTED function to its preceding neighbour, the limit the harness's own docstring
predicted), and **2 genuine drops, both on one line**. So the measured v1 line-recall remains a
FLOOR under a noisy oracle in the same way and for the same reasons — but at this scale the residue
is no longer empty, and it named two real defects.

**(4) Two real v1 defects the in-tree corpus could not see. Both are `--slice` inventory/occurrence
defects; neither is in the rung-2 flow machinery.**

- **Direct-initialization constructor arguments are invisible to the slice.** duckdb
  `src/execution/index/art/prefix.cpp` @ `e5281f103`, `Prefix::TransformToDeprecated`:
  `Prefix prefix( art, current_node, true, true );` is absent from `--slice=…:art` and from
  `--slice=…:current_node`, while every `f( art, … )` call-argument line in the same function is
  present. Both occurrences of the pattern in that function are missed (the added line 411 and the
  pre-existing 394), so this is systematic, not a diff artifact: a `T v( a, b );` declaration's
  argument list is not walked for occurrences. This is the ONLY real drop in 188 duckdb+rocksdb
  instances, and it accounts for 2 of duckdb's 10 missed lines. **Fixed at 713a020** (same round:
  the walk recognizes the most-vexing-parse shape and rows those arguments `k="use" t="call-arg"`,
  C-family-only, gated red-first in slicecheck arm (1b)); duckdb re-run in full on the fixed
  binary, same corpus copy and cap: the two drop lines now hit — per-variable line-recall
  0.911 → **0.917**, hit-all 0.889 → **0.911** (exactly the +2/90 the fix predicts), fn-recall
  v1 0.547 → 0.550 / v2 0.597 → 0.602, over-inclusion 4.96× → 4.99× — every other instance's
  rows unchanged.
- **A C++ keyword can be listed as a sliceable local.** ugrep `lib/matcher.cpp` @ `a8af825d3`,
  `Matcher::advance` (a ~1 200-line SIMD/macro-heavy function): the bare inventory offers
  `<v n="if" l="683" t="decl">`, and `--slice=matcher.cpp:advance:if` returns 13 rows, every one an
  `else if ( pat_->ndl_ == N )` clause classified `k="def" t="decl"` — a declaration misparse in a
  region where the C++ grammar's recovery has degraded. This single instance produces **all 11** of
  ugrep's missed lines and drives its 20.47× over-inclusion, which is why ugrep's numbers are read
  as one defect's shadow rather than as a corpus signal.

**(5) ugrep is reported as thin, because it is.** Its ENTIRE 985-revision history yields 16
single-function fix-shaped candidates, of which 12 fail selector resolution and 2 name no sliceable
local, leaving **2 commits and 5 instances** — and one of those five is the `if` defect above. No
row in the ugrep column should be read as a population estimate; it is five observations, published
because suppressing a thin corpus after seeing it is the thing this document does not do. The
selector-unserved counts are the wider finding here: the harness addresses functions by BASENAME
(`file.cpp:fn`), and in a large tree that is ambiguous or unresolvable for 28% (duckdb), 53%
(rocksdb) and 75% (ugrep) of otherwise-qualifying candidates. That is a property of the
qualification rule, not of the slicer — it costs corpus size, and it is disclosed rather than
worked around, because widening the selector mid-round would have changed what "qualifies" after
the numbers were in view.

**(6) ugrep re-measured after the D2 fix (2026-08-31, same round).** Finding D2 above — a degraded
parse offering the reserved word `if` as a sliceable local — was fixed before this round merged
(per-language keyword tables in the slice walk), and numbers measured without that fix are stale for
the mechanism it removes, so the ugrep arm re-ran on the fixed binary, same corpus copy, same cap.
The keyword instance no longer QUALIFIES (an added line naming only `if` names no sliceable local
now), which is the fix behaving: instances 5 → **4**, all four at `v1 line-recall` **1.0** / hit-all
**1.0** (was 0.800/0.800 — the sole miss was the keyword instance), fn-recall v1 = v2 = **0.727**
(was 0.582; the v2 delta stays +0.0pp), per-instance values otherwise identical to the first run
modulo ~+210 B of the fix's own legend disclosure. Two honest movements against the headline: mean
over-inclusion RISES 20.47× → 25.29× because the removed instance had the LOWEST ratio — set
composition, not a regression (the surviving 58.0×/22.5×/17.0×/3.7× rows are unchanged) — and mean
v2 bytes (27,519) now EXCEED the `--expand` baseline (24,966) on this four-instance set, the
short-function cost regime the reading above already names. Four observations; the
population-estimate caveat of (5) applies with more force, not less.

**Reference-implementation fidelity audit (2026-08-31, lane/tc-arisecode).** Both slice rungs were
built from the paper's PROSE alone; the reference implementation has since been published
([FARD-Lab/ARISE](https://github.com/FARD-Lab/ARISE), MIT) and was read line-by-line
(`src/arise/analysis/program_graph.py` — the two-pass AST + data-flow builder — and
`src/arise/tools/dataflow_slice.py` — the traversal) against `src/slice.h`. This paragraph is the
record of that comparison: it amends two readings of the paper the deviations list above credited
too generously, and discloses two divergences between ripwire and the reference CODE that the
prose-only registration could not have named. **No ripwire behavior changed as a result** — the
registered contract stands, every emitted legend sentence describes ripwire's own behavior and
remains true, and both newly-disclosed divergences are kept deliberately.

| point | reference as coded | ripwire | verdict |
| --- | --- | --- | --- |
| reaching-definition rule | single forward textual pass; `definitions[var]` = last def statement; each use links to exactly that def; an augmented assignment's read links to the PREVIOUS def (uses are processed before defs within a statement) | `sliceReachingDef`: the last def row strictly before the line, same last-writer-wins fold; aug-assign rows `k="both"` and chain to the prior def | **faithful** — the core rule matches exactly; both sides are flow-insensitive single passes with no branch joins and no loop back-edges |
| statement granularity | TOP-LEVEL function-body statements only: a compound `if`/`try` block is ONE node spanning all its lines, and a `for`/`with` statement's node carries only its target and iterator — the body's defs and uses are dropped entirely | one row per source LINE; every identifier in the definition's span is classified, nothing dropped | deviation (1) above read the paper as finer-grained than us; the published code is strictly COARSER — line grain over-merges only multi-statement lines, the reference over-merges whole compound blocks and loses loop-body occurrences outright |
| traversal variable scope | the BFS filters EVERY edge to the seed variable (`if variable not in edge_vars: continue`) — the backward slice is the seed's own same-name def-use chain, typically one hop; the variables a reached definition READS are never chained | rung 2 chains through operand variables: a reached def's uses continue to THEIR reaching definitions | **new divergence, disclosed here and KEPT**: ripwire's slice is a strict superset (probe: a four-assignment Python chain — the back-slice reaches the parameter through two intermediate variables; the reference stops at the seed's own definition). The paper's +17pp was measured with the single-variable form |
| bound | UNBOUNDED — `_bfs_slice` has no depth or node cap (harmless there because single-variable chains are short) | default depth 8, band 1..32, `flow_truncated="1"` when the bound suppresses a novel row | **new divergence, disclosed here and KEPT** — the registration's "bounded BFS" reading came from prose; the bound is ours, and it is the disclosed-truncation posture this document requires |
| halt at call edges | trivially true — no data-flow edge ever crosses a function; parameters have NO def site at all, so a use of a never-reassigned parameter has no backward edge | span-scoped walk, same intra-procedural guarantee; the parameter line rows as a `t="param"` def and is reachable | faithful on the boundary; ripwire's param rows are richer, kept |
| direction semantics | backward = USE_DEF edges, forward = DEF_USE, both = union deduplicated by statement; every emitted step is labeled with the SEED variable's name | back/fwd/both, backward first, deduplicated per (variable, line); flow rows carry `v=` (the step's OWN variable), `d=`, `f=` | faithful (modulo the variable-scope row); ripwire's per-step labeling is strictly more informative |
| seed addressing | (file, line, variable): the statement covering the line via binary search, an explanatory string when none covers it | (symbol, variable) + the line-seed addendum (`--at` / `@FILE:LINE`); the seed variable's rows are the d=0 block | deviation (3) as already disclosed; the addendum closes the addressing gap |
| scope handling | `global x` / `nonlocal x` statements are treated as DEFS of x — declaration-as-def, no scope analysis; comprehension scopes are NOT separated (their variables leak as plain loads); attribute and subscript stores (`self.x = v`, `a[i] = v`) produce NO defs and NO uses — invisible | name-based: all such identifiers row as reads; no lexical scope separation either | deviation (2) credited the paper with explicit scope handling; the published code is as scope-insensitive as v1, and blinder on attribute stores (invisible there, visible-as-reads here) |

The audit's operative finding for any future head-to-head: the reference slicer that produced the
paper's +17pp is the WEAKER instrument — top-level-statement grain, single-variable chains, no
transitive closure, loop bodies dropped. Matching the published number does not require matching
the published slicer, and a comparison arm that swaps in ripwire's verbs is comparing a superset
slice against the number the subset earned.

**Corrections from the 2026-09-02 read-only adversarial audit — dated, appended, history above untouched.**
Seven findings against the `--slice` / `--slice-flow` surface at `8e186bb` were re-verified against a
fresh build of that commit before any code moved (every cited probe reproduced), then fixed red-first
in five commits on `lane/n2-h`, one finding-group per commit, gates in `test/sliceflowcheck.sh` arms
27–30 and `test/slicecheck.sh` arms 12–14. Each paragraph below states what the audit found, what
changed, the fixture numbers before/after, and the effect on the pinned 38-instance in-tree corpus
(`python3 bench/slice/run_slicerecall.py --bin <binary> --repo . --cap 40`, the registered argv, run
once per commit against a copy of that commit's binary; `bench/external` is absent in this
checkout, so the duckdb/rocksdb/ugrep rows are NOT re-run — the external numbers above stand as
measured on the older binary and are not compared here).

*F-01, HIGH, fixed at `9dd6ef8` — preprocessor-dead code replaced the live chain.* `#if 0` /
`#ifdef NEVER_*` bodies were lexical to the slicer: `--slice=if0:w --slice-flow=back` returned
`steps="1"` whose only row was `v = 111;` from inside `#if 0` — the real chain `w ← v ← n` ABSENT,
not truncated, undisclosed. The rule now (C-family, stated verbatim in the legend and `--help`):
decided only by the literal — the body of `#if 0` and the `#else` of `#if 1` are dead, their rows
dropped and counted as `preproc_rows=` (absent when zero); every other conditional (`#ifdef`,
`#ifndef`, `#if defined(X)`, `#if EXPR`, `#elif`) is build-dependent and cannot be decided without
the build's macro set — "the file never `#define`s X" is exactly the shape of a `-DNDEBUG`-style
macro, so it is not evidence of dead code — its rows are kept and flagged `pp="1"`, and in a flow a
`pp="1"` def is a reaching def AND so is the unconditional def before it (both emitted; the forward
walk passes through it). Fixture: `if0:w` back `steps` 1 → 2 (v@3, n@1; the `#if 0` row gone,
`preproc_rows="1"`); `ppsupp:t2` both `steps` 1 → 4 (the `#ifdef` def kept with `pp="1"`, the
unconditional `s2` def and `p1`/`n` behind it now reached). Corpus: line-recall 0.739 / hit-all
0.658 / over-inclusion 3.79× / fn-recall v1 0.167, v2 0.206 — all UNCHANGED (this repository's
single-function fix commits hold no `#if 0`); bytes v1 3 187 → 3 936, v2 7 429 → 8 428, all of it
legend (the rule must be stated; F-11 below takes it back).

*F-03, HIGH, fixed at `5bb566f` — `counts_floor="1"` was false in the over-direction.* The root
promised true ≥ reported while the same legend admitted shadowing over-includes (`shadowing:v` →
`defs="3"` for a variable with one def; `guarded:g` → 3 vs 2). The marker is now
`counts="as-classified"` (deliberately NOT the graph verbs' `counts_floor=`; the legend names the
absent marker once to say why): `defs=`, `uses=`, `vars=`, `steps=` are exact counts of what the
name-based classifier rowed, neither floors nor totals — LOW where a write hides behind a call,
HIGH where a rowed occurrence is not this variable's (a `pp="1"` row, a same-spelled member/
attribute). The numbers themselves did not move (the spelling did); corpus identical to F-01's row
except bytes (v1 4 458, v2 8 968 — legend).

*F-02, HIGH, fixed at `1ce7a3a` — the flow walk chained into a sibling block's shadow.*
`--slice=shadowing:r --slice-flow=back` chained `l6 → l5` (the inner block's `v`) and never reached
`int v = n;` or the parameter: a chain through a variable `r` does not read, and the legend disclosed
only over-inclusion. Block scopes are now separated: a name declared more than once inside the
definition is that many variables (`SliceBinding`), scoped to the innermost scope-creating ancestor
per family (kind tables verified against the vendored parsers), every other occurrence bound in a
post-walk pass to the innermost enclosing scope whose declaration precedes it; rows, folds, the
anchor table and the BFS are keyed per binding. Go `v := v + 1` and Rust `let v = v + 1` read the
previous binding in their own initializer (one line, two rows); JS `var` hoists to the function,
`let`/`const` are per block; Python is function-scoped (one binding). Disclosure: `bindings=` on a
shadowed seed's root, `b=` on every row of a shadowed name (its declaration line; `b="0"` = unbound),
the inventory lists one `<v>` per binding; an unshadowed slice is byte-for-byte free of the new
vocabulary. Fixture: `shadowing:r` back → `steps="2"` = `v@3 (b=3)`, `n@1`, no `l5`/`l6` rows;
inventory `vars` 3 → 4. **Also fixed, found by the separation:** tree-sitter-cpp's condition-clause
`declaration` (`if( int k = x )`) carries its initializer in a `value` field with no
`init_declarator`, and the classifier read `x` as a DECL on the `8e186bb` binary too (`defs="5"`
where 3 is right) — a false def that became a false binding; `x` rows as a read now (slicecheck arm
12). Corpus: unchanged (no shadowing inside the 38 instances); bytes v1 5 322, v2 9 904 (legend).

*F-08 (MEDIUM), F-12 and F-15 (LOW), fixed at `a8c08fb`.* JS/TS destructuring binders were
invisible (`const { x, y } = o` minted no local and no def; `destructure:s` back `steps="0"`): the
walk now treats `shorthand_property_identifier_pattern` as an occurrence and climbs the pattern
wrappers to the binding site — `--slice=destructure` inventory 2 → 12 binders, `destructure:x`
`defs` 0 → 2, `destructure:s` back `steps` 0 → 3 (`s ← x,y ← o`), matching what Python tuple-unpack
and Go multi-assign already did. Python `global X` / `nonlocal X` rowed `k="use" t="read"` and
listed a global as a LOCAL: they row `k="scope" t="global|nonlocal"` now (a fourth `k=` value —
neither read nor write, never a flow anchor) and the inventory shows `<v n="COUNTER" l="4"
t="global"/>`. The under-count clause named only receiver mutation; it now names a write through an
ARGUMENT — by-reference/pointer parameter, out-parameter, function-like macro — as the same blind
spot (classified `k="use" t="call-arg"`), in the legend, the header contract and `--help`. Corpus:
unchanged (cpp-only corpus, no Python/JS); bytes v1 6 122, v2 10 704 (legend).

*F-11, MEDIUM, fixed at `1b71618` — legend 84–90% of the output, two LIMITS paragraphs restating each
other, `--legend=compact` refused.* The four fixes above made it worse (v1 legend 2 354 → 5 278 B,
flow 4 381 → 7 648 B). Now three tiers, one owner per rule: the v1 block states every rule once,
numbered (1)–(7), **3 585 B** (gate budget 3 584 B on its fixture, a ratchet; four more rules than
the 2 354 B baseline stated); the seed and flow blocks add only their own vocabulary and point at
v1's numbered limits — flow addendum **2 027 → 1 338 B**; and `--legend=compact`
(`schema="ripwire.slice/v1"`, **987 B**, one block that also carries the seed and flow vocabulary)
for the many-small-calls seed loop, rows byte-identical to the full form (proven against the
previous commit's binary on 5-, 6- and 6-row flows). Legend share on the audit's own fixture
(`--slice=guarded:g`, leading-comment bytes / total): 84.2% → 88.7% full (the rules) / **66.0%**
compact; `--slice-flow=both`: 88.7% → 89.6% full / **61.0%** compact — the ratio is dominated by
that fixture's 455-byte payload, so the bytes are the honest measure: full v1 legend 2 354 → 3 585
(+1 231 for four stated rules), full flow legend 4 381 → 4 923 (+542), compact 987. Corpus (the
registered argv carries no `--legend`, so this is the FULL tier): recall unchanged; bytes v1 3 187 →
**4 429** (+1 242 = the v1 legend growth, to the byte), v2 7 429 → **7 979** (+550 = the flow legend
growth). Arithmetic, not a run, because the registered argv is fixed: under `--legend=compact` the
same instances would carry 4 429 − 3 585 + 987 ≈ 1 831 B (v1) and 7 979 − 4 923 + 987 ≈ 4 043 B (v2),
−43% / −46% against the 8e186bb baseline.

*What this does to the ARISE-faithfulness table above.* Two rows are amended by these fixes and the
table is left as written (it records the 2026-08-31 comparison): "reaching-definition rule —
faithful" now carries one stated deviation, a `pp="1"` (build-dependent) def is a reaching def
together with the unconditional def before it, where the reference's single forward pass would let
it replace that def — deliberate, because the reference's slicer is as lexical to the preprocessor
as v1 was (it never sees C at all); and "scope handling — no lexical scope separation either" is no
longer true of ripwire: block scopes are separated for C-family/JS/TS/Go/Java/Rust, Python remains
function-scoped like the reference, and `global`/`nonlocal` are a scope role rather than the
reference's declaration-as-def. Both make ripwire's slice a still-larger superset of the instrument
that earned the paper's +17pp; the "matching the published number does not require matching the
published slicer" reading stands, with one more reason.

## `--slice-guards` — control dependence for the slice, PRE-REGISTERED 2026-08-31 (before any feature code)

**What this registers.** The survey lane's proposal: control-dependence rows beside the flow
slice's data rows — for each emitted statement, WHICH guard (`if`/loop/early-return conditional)
decides whether it executes. This section fixes the mechanism's honesty tiers, the corpus, the
counting rule, the validity preconditions and the accept/reject bands BEFORE any feature code
exists. Nothing below is a result; this phase changes no binary behaviour, and the one count in it
is instance QUALIFICATION, not an outcome.

**Provenance, and what the tool says today.** Control and data dependence belong in one graph —
Ferrante, Ottenstein & Warren's program dependence graph (TOPLAS 1987). The flow slice models DATA
dependence only, and since `1a12c5a` (merged `f920f45`, 2026-08-31) the emitted legend says so as
its fifth limit: *"DATA dependence only — no control dependence: the guard (if/loop) deciding
whether a def executes is never a row."* `test/sliceflowcheck.sh` arm (10) pins that sentence
(greps for `no control dependence` and `guard`). **The coupling, registered as an obligation:** the
commit that ships `--slice-guards` MUST, in the same commit, (i) reword that legend clause — on a
guards run the sentence becomes false, and on a non-guards run it must point at the flag instead —
and (ii) update arm (10)'s assertion. Ship the rows without touching the clause and the tool lies
in the opposite direction; touch the clause without the arm and the gate pins the lie. Red-first
arms for the new rows, the degrade and the refusals extend `sliceflowcheck.sh` per the house rule,
with the gate-count pins (README/EVALS, `readmedriftcheck.sh`) updated if a new gate file appears.

**Extractability — verified against the vendored grammar, not assumed.** `sliceScanDefinition`
already re-parses the ONE file holding the definition; the AST is in hand at row-emission time and
no new parse infrastructure is needed. Every C-family node kind the mechanism reads exists in
`third_party/deps/cpp/src/parser.c` (grep-verified at this registration): `if_statement` /
`while_statement` / `for_statement` / `do_statement` / `for_range_loop` / `switch_statement` /
`case_statement` / `conditional_expression` for guards; `return_statement` / `break_statement` /
`continue_statement` / `throw_statement` / `goto_statement` / `labeled_statement` for exits;
`lambda_expression` for the scope boundary an exit scan must respect — a `return` inside a nested
lambda exits the LAMBDA, and an exit scan that ignores that boundary manufactures false guards, so
the boundary is part of the contract, not an optimization. No CFG and no post-dominator computation
is planned. The mechanism is therefore two halves of unequal strength, stated now: the
**enclosing-guard chain** is EXACT for goto-free structured code by construction (a syntactic
ancestor walk); the **early-exit half** — a statement after `if( c ) return;` is control-dependent
on `c` — is an APPROXIMATION of post-dominance, exact for the early-exit idiom and wrong in corners
(a `break` deep in a nested loop deciding post-loop statements needs the CFG this slicer does not
build).

**The three honesty tiers, fixed before the code.** *(1) Degraded, detectably —*
`guards_degraded="1"` when the definition's span defeats the mechanism in a way the AST can see:
`goto_statement` or `labeled_statement`; a `switch` whose case body can fall through (conservative
syntactic test — a non-empty case not ending in a jump statement); `co_await` / `co_return` /
`co_yield` (resumption is scheduler-controlled); `seh_try_statement`; a `preproc_if` /
`preproc_ifdef` inside the span (the parse in hand is ONE branch of a carved token stream). *(2)
Invisible, legend-disclosed only —* what no AST read can detect: macro-hidden control flow (a macro
expanding to `if`/`return` parses as a plain call — this repo's own `DEGRADED_PATH_ALERT` shape is
the live example); a potentially-throwing call (exceptional edges need the callee's body — the same
evidence limit the receiver-mutation decision registered); a `noreturn` callee (`exit`/`abort`/
`longjmp` falsify post-dominance silently). Consequence: guard rows are FLOORS — the
`counts_floor="1"` discipline extends to them, and an absent guard row never means "unconditional".
*(3) Family scope —* the measured claim below is C-family ONLY (the corpus is cpp); other served
families may ship rows but earn no measured claim from this round.

**The corpus problem, settled — the reason this registration exists.** The survey lane described "a
pinned 38-instance corpus". **It is not pinned in any file**: `bench/slice/run_slicerecall.py`
MINES at run time — newest-first fix-shaped commits from the `--repo` tree's own history, cap 40 —
so the instance set is a function of the HEAD it runs at. Settled here, from the harness code and a
read-only count: **(a)** the paired design is real — all arms run per instance inside ONE
invocation with one binary, so a v3−v2 delta computed within one invocation is a valid paired
statistic under any drift; but validity-under-drift is not enough, because the newest-first cap
makes the SET a function of when you run — a re-roll channel and a population drift. So **(b)** the
corpus is additionally frozen — by pin, not by JSON: the measurement mine runs against a throwaway
checkout DETACHED at **`b156027`** (this registration's base; the harness docstring's own
external-corpus pattern — the pin alone fixes the commit list, and the mine is deterministic given
it). **(c)** Counted at `b156027` on 2026-08-31, qualification only (no recall or byte was read):
the ENTIRE history still yields **10** single-function fix-shaped candidates → **7** commits →
**38** instances — `86d7956` (9), `317fb19` (4), `4b9386c` (6), `ebdeead` (8), `1c1d513` (3),
`b2cbbda` (7), `cff49a6` (1); skips 1 selector-unserved / 2 no-touched-var — the same 10/7/38 the
2026-08-30 run reported, counted with today's binary (the D1 ctor-arg and D2 keyword fixes
included). The drift the recon brief predicted did NOT materialize: none of today's 14 commits
qualifies — `d106bb4`, the flagged likely entrant, adds lines to `README.md` and `test/` fixtures
beside `src/graph.h`, and the added-lines-confined rule rejects it. The structural reason is the
house discipline itself (a fix lands with its gate and doc pins in the same commit), which is why
this repo's own history is corpus-thin — noted, not relied on. **(d)** Contamination: the pin
forecloses it — an implementation commit post-dates the pin and can never enter; today's
slice-adjacent commits are already excluded by (c). No further exclusion rule is registered,
deliberately: a rule invented later, with an instance list in view, is itself a fitting channel.

**Arms, metric, counting rule.** The harness gains arm (d): **v3** = `--slice=fn:var
--slice-flow=both --slice-guards`, in the SAME per-instance loop — mining and qualification rules
byte-untouched. Primary metric: the per-instance paired delta of function-level added-line recall,
v3 − v2, mean over the 38. Counting rule fixed now: v3 "slice lines" = every line-bearing row the
invocation emits, guard rows included — if guard rows use a new element tag, the harness's row
regex must be extended in the same commit, else the arm silently re-measures v2. Cost: mean v3
bytes beside v2 and `--expand` bytes — recall and cost together, never recall alone (§5). Reported
beside, not banded: the share of instances with `guards_degraded="1"`, and the per-instance
up/unchanged split.

**Validity preconditions — the run is invalid before any number is read if any fails.** (i) The
measurement binary at the pin re-derives exactly 7 commits / 38 instances, identical triples. (ii)
Arm (b)'s per-instance recall values from the measurement binary equal those from a
`b156027`-built binary at the same pin — guards code must not move data rows; bytes may differ
only by the reworded legend's constant delta, identical across instances and disclosed. (iii)
Additivity holds on every instance: v3 rows ⊇ v2 rows, hence per-instance v3 recall ≥ v2 — any
instance moving DOWN is a mechanism or harness bug, never a result.

**Registered bands — fixed before any number.** Additivity means the delta cannot be negative;
magnitude and cost are the whole question.

* **SHIP:** paired mean v3−v2 ≥ **+3.0pp** on the pinned 38, AND ≥ 5 of 38 instances move up, AND
  mean v3 bytes ≤ **1.6×** mean v2 bytes, AND mean v3 bytes < mean `--expand` bytes on the same
  instances. The survey lane proposed this band; it is registered here after verifying its metric
  names match what the harness computes (`fn_added_recall_*`; the byte base, unstated there, is
  fixed as v2), and +3.0pp is defended against precedent rather than inherited from it: rung 2
  itself shipped at +3.5pp on this same corpus, and a control rung that cannot roughly match the
  data rung's contribution is not worth its bytes or its legend complexity.
* **NEGATIVE (published — §7 discipline):** mean delta < **+1.0pp**, or any cost bound broken. The
  record reads "control dependence is not worth its bytes on fix-shaped single-function commits";
  the flag does not ship, and the legend's fifth limit STANDS as the durable disclosure.
* **INCONCLUSIVE (published as such):** delta in **[+1.0, +3.0)pp**, or fewer than 5 instances
  moving up — real but undecided at this corpus's power. The only funded follow-up is the external
  strata below, never a re-roll of the in-tree mine.

**External strata — mandatory report, non-deciding.** The D4-pinned trio (duckdb `19864453`,
rocksdb `0e2801ac`, ugrep `550599a6`) runs under the same protocol, per repo, never pooled,
reported beside the in-tree decider. Additivity makes their deltas ≥ 0 by construction, so no band
attaches; what they decide is the COST REGIME: rung 2's wider run showed v2 already ≈ `--expand`
bytes on short-function corpora, and if v3 mean bytes exceed `--expand` mean bytes on duckdb or
rocksdb, every public value claim for `--slice-guards` must carry the short-function caveat in the
same commit that publishes it — the conditional-cost posture rung 2's reading already adopted.

**The falsifiable claim.** *"On fix-shaped single-function commits, the enclosing-guard chain plus
early-exit conditionals recovers enough of a fix's added guard lines to be worth ≤ 1.6× the data
slice's bytes."* Every band above is publishable, including both failures; a registration that
cannot fail is not a registration.

**Explicitly out of this phase.** No feature code, no flag, no legend change, no gate arm, no
recall or byte number from any arm — the count above is qualification only, and the first outcome
number appears below this section, dated, whichever way it goes.

## `--slice-guards` — the registered NEGATIVE, measured 2026-08-31 against the bands above

**Verdict: NEGATIVE, by the bands the section above fixed before the code existed.** The paired mean
`v3 − v2` on the pinned 38 is **+0.895 pp** (n = 38), under the **+1.0 pp** NEGATIVE threshold. Both
cost bounds were MET, and that matters to the reading: this is not "too expensive", it is "does not
buy enough". **The flag does not ship.** The flow legend's fifth limit stands exactly as `f920f45`
landed it, `test/sliceflowcheck.sh` arm (10) keeps pinning that sentence, and the implementation is
reverted (`2a21a73` built it and gated it red-first; `15a018c` reverts it whole, tree byte-identical
to the registration base). Nothing below is speculative — every number came out of that binary.

**Validity preconditions — checked, not asserted.** All three pass, so the delta is readable at all.

| # | Precondition | Result |
| --- | --- | --- |
| (i) | the pin re-derives 7 commits / 38 instances, identical triples | **PASS** — 10 candidates → 7 commits → 38 instances; `86d7956`·9, `317fb19`·4, `4b9386c`·6, `ebdeead`·8, `1c1d513`·3, `b2cbbda`·7, `cff49a6`·1; skips 1 selector-unserved / 2 no-touched-var. The instance KEY SET is identical to the `b156027`-binary run, not merely the counts |
| (ii) | arm (b) unmoved vs a `b156027`-built binary | **PASS** — 0 of 38 instances moved on `v1_line_recall`, `fn_added_recall_v1` or `fn_added_recall_v2`. v1 bytes delta **0** everywhere; v2 bytes delta **+72 on every one of the 38**, a single constant, exactly the reworded fifth limit's length. The registration allowed a legend-constant delta and required it be identical across instances and disclosed; it is both |
| (iii) | per-instance additivity, v3 rows ⊇ v2 rows | **PASS** — 0 violations and 0 instances moving DOWN, on all 38 (and on all 192 external instances below) |

**The banded result** — recall beside cost, never recall alone (§5).

| Arm | fn added-line recall (mean, n=38) | mean bytes |
| --- | --- | --- |
| v1 `--slice=fn:var` | 16.73% | 3,187 |
| v2 `+ --slice-flow=both` | 20.64% | 7,501 |
| **v3 `+ --slice-guards`** | **21.53%** | **10,228** |
| `--expand=fn` (whole body) | 100% by construction | 20,034 |

| Registered criterion | Band | Measured | |
| --- | --- | --- | --- |
| paired mean `v3 − v2` | ≥ +3.0 pp SHIPs; < +1.0 pp is NEGATIVE | **+0.895 pp** (sd 2.212 pp, sem 0.359 pp) | **fails** |
| instances improved | ≥ 5 of 38 | **7** up / 31 same / **0** down | meets |
| mean v3 bytes ≤ 1.6× v2 | ≤ 1.6× | **1.364×** | meets |
| mean v3 bytes < `--expand` | < 20,034 | **10,228** | meets |

Three of four criteria are met and the one that decides is not. It misses by 0.105 pp; the paired sem
is 0.359 pp, so a 95% interval straddles the threshold and no honest reader should call this a wide
margin. It is still NEGATIVE under the rule fixed before the number existed. Moving a band after
seeing a number is the single move a registration exists to forbid.

**Why it fails, which is a finding and not a defect.** The mechanism is not inert: **7.53 guard rows
per instance** on average, non-zero on **35 of 38**, and **zero** instances degraded (no goto, label,
fallthrough case, coroutine, `__try` or in-span `#if` occurs inside any of the 38 definitions). The
guards are real. They are simply not *the lines a fix adds*. A fix-shaped commit adds data statements
and whole new branches; the conditions those statements sit **under** are, overwhelmingly, lines that
were already there — and added-line recall cannot credit a pre-existing line. The whole +0.895 pp
comes from **7 instances on 2 of the 7 commits** (`buildForAutoBodies` ×6, `passesPredicates` ×1),
i.e. the cases where the fix *was* its own guard. That concentration is the substance of the result.

**External strata — mandatory report, NON-DECIDING by the registration, and they disagree.** Same
protocol, per repo, never pooled, same binary, D4 pins with rev counts re-verified (duckdb 48,632;
rocksdb 12,938; ugrep 985).

| repo (D4 pin) | cand → commits → n | paired mean `v3 − v2` | up / same / down | v2 B | v3 B | v3/v2 | `--expand` B | v3 vs expand |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| duckdb `19864453` | 120 → 40 → **90** | **+3.04 pp** (sem 0.77) | 18 / 72 / 0 | 6,053 | 8,581 | 1.42× | 4,357 | **exceeds** |
| rocksdb `0e2801ac` | 120 → 40 → **98** | **+2.08 pp** (sem 0.48) | 21 / 77 / 0 | 5,878 | 8,444 | 1.44× | 7,008 | **exceeds** |
| ugrep `550599a6` | 16 → 2 → **4** | **+0.00 pp** | 0 / 4 / 0 | 31,384 | 39,462 | 1.26× | 24,966 | **exceeds** |

Two things must be said plainly about that table, and neither changes the verdict.

*First, the cost regime the strata were registered to decide is decided, and it is bad.* On **all
three** external corpora mean v3 bytes **exceed** mean `--expand` bytes — the whole-body baseline is
cheaper than the slice. On duckdb and ugrep v2 already exceeded `--expand`, so guards inherit that
regime; on **rocksdb the crossing is new** (v2 5,878 < 7,008 < v3 8,444), i.e. the guard rows are
what push it over. The registration's clause therefore binds: any future public value claim for
`--slice-guards` must carry the short-function caveat in the commit that publishes it.

*Second, the non-deciding numbers are larger than the deciding one, and pretending otherwise would be
the dishonest move.* 188 instances across two large C++ trees show **+3.04 pp** and **+2.08 pp**, one
of them at the SHIP threshold, against **+0.895 pp** on the 38-instance in-tree draw. The registration
declared the strata non-deciding *before* anyone could see this, precisely so that a bigger number
found later could not be promoted into the decider — so the verdict stands. But the honest reading of
the pair is that the in-tree corpus, thin by the registration's own admission ("this repo's own
history is corpus-thin — noted, not relied on"), probably lacked the power to decide the question it
was given, and the band was calibrated against a population that turns out to be unrepresentative.
That is a finding about the registration's design, not a licence to revise its output. A future round
that wants this flag should register the **external strata as the decider** and re-derive its band
there, with the cost caveat above attached from the start.

**What this negative does NOT establish.** (a) It measures *added-line recall on fix-shaped
single-function commits* — not whether guard rows help an agent. A reader asking "which condition
decides this line?" got a correct answer from the mechanism on 35 of 38 instances; this corpus cannot
see that value. (b) The early-exit half's registered wrong corner (a `break` deep in nested loops
deciding post-loop statements) was never exercised — it needs the CFG that was deliberately not
built, and no instance contained the shape. (c) The C-family-only scope holds: the Python/JS/Go/Java/
Rust node-kind tables were gate-verified on fixtures, never measured. (d) `switch`/`case`, ternary,
`if`/`else` fork and fallthrough-degrade shapes were probe-verified against the built binary but are
not in the committed gate, because the gate went away with the flag. (e) No claim is made about
whether shipping the flag on the external evidence would be right; that is a new registration's
question, not this one's.

## ARISE fault-localization head-to-head — PRE-REGISTERED 2026-08-31 (before any arm runs)

**What this registers.** The head-to-head the fidelity audit above scoped: ripwire's verbs mounted
inside ARISE's own SWE-agent fault-localization harness, scored by ARISE's own evaluator, against
their bundle and against the vanilla baseline. Everything below is fixed BEFORE any arm runs an
instance; at registration time NO model endpoint or API key exists in the environment, so the
key-free prefix (environment, bundle, smoke, dry-runs) is executed and the measured runs are
blocked at the LM boundary — nothing in this section is a result.

**The task and the scorer of record, imported unmodified.** The FL task is a SWE-agent `run_batch`
over SWE-bench Lite with config overlays (a condition overlay + `fl.yaml`); the agent may not edit
files or run tests, and the terminal answer is a ranked `LOCATIONS … END_LOCATIONS` block (file,
function, line triples) parsed from the trajectory by their `evaluation/parse_preds.py`. Scoring is
their `evaluation/run_eval.py` + `src/arise/eval/gold.py`, byte-unmodified (the SWEX/ARB scorer-of-
record precedent): File Recall@k and File MRR, Function Recall@k / F1@k / MRR, Line Recall@k, Line
IoU, Coverage@budget — every metric exactly as they define it, with the gold labels derived from
the SWE-bench patch by their funcname-regex rules, whose quirks are inherited equally by every arm.
Token cost per arm is reported beside recall via their own `--token-usage` trajectory parse (the §5
discipline: recall and cost together, never recall alone).

**Pins, recorded at registration.** ARISE `3abdc361ba2cb627b8c83c2493dafd1d7cc874dd`
([FARD-Lab/ARISE](https://github.com/FARD-Lab/ARISE), MIT); SWE-agent **1.1.0** at
`3ea751c087f32b16e039a2233dd6eefecef325d5` (SWE-ReX 1.4.0); dataset
`princeton-nlp/SWE-bench_Lite`, test split (300 instances, 11 Python repos), HF revision
`6ec7bb89b9342f664a54a6e0a6ea6501d3437cc2`; harness Python 3.14.6; ripwire = the plain
`build/ripwire` at the head this round runs from, pinned into the shims via `RIPWIRE_BIN`. The
**model ID is left explicitly unpinned here and is pinned at run time, before the first instance
runs** — runs are blocked on an API key at registration time, and whichever model is pinned then is
used identically for all three arms in the same window (their published numbers used
Qwen2.5-Coder-32B-Instruct-AWQ on local vLLM; a different backbone here makes our (a)/(b) re-runs
the only in-table baselines, which is why they are required).

**The three arms, all in THEIR scaffold — anything else measures the scaffold.** (a) **vanilla
SWE-agent**: `config/default.yaml` + their `fl_baseline.yaml` (shell-only). (b) **ARISE full
bundle**: `default.yaml` + their `arise.yaml` + their `fl.yaml`. (c) **ripwire bundle**:
`default.yaml` + `bench/arise-h2h/ripwire.yaml` (mounts `bench/arise-h2h/swe_agent_bundle_ripwire/`,
mirroring their bin-shim pattern: one tiny executable + config.yaml docstring per verb) +
`bench/arise-h2h/fl_ripwire.yaml`, which is their `fl.yaml` with ONLY the tool names and per-tool
usage lines substituted verb-for-verb — stages, rules, LOCATIONS format, `single_bash_code_block`
parser and every other line preserved, so the prompt shape is held constant. Same model, same turn
and cost budget, same parser across all three. Verb map (registered in the bundle's config.yaml):
`--for` ↔ arise_search; `--at` ↔ arise_get_enclosing_scopes; `--expand` (with `SYM:A-B` range) ↔
arise_get_code_span; `--callers`/`--callees`/`--impact` ↔ arise_traverse_relations;
`--slice`/`--slice-flow` (line-seeded `--slice=@FILE:LINE` + variable) ↔ arise_get_dataflow_slice;
`--pack-task` ↔ arise_build_context_bundle; `--from-trace` ↔ rank_suspects' trace half. Shim
docstrings state ripwire's own limits (name-based edges, no alias analysis) — never a capability
the binary does not have.

**The rung this registration funds: the 60-instance stable-order slice.** Instance selection rule,
deterministic given the dataset pin alone: the test split in its dataset order at revision
`6ec7bb89…`, indices 0, 5, 10, …, 295 (stride 5 from index 0; SWE-agent spelling
`instances.slice: "::5"`) — 60 instances, proportional across the split's repo blocks, chosen by
arithmetic and not by eye. The full-300 run is a later rung under this same protocol, owner-funded
separately.

**Their numbers stay theirs.** The published baseline→ARISE-Full Function Recall@1 43.0→60.0 (Line
Recall@1 26.0→41.0, Pass@1 17.3%→22.0%) is quoted as THEIR run on their backbone; any table this
protocol produces reports OUR re-runs of arms (a) and (b) beside those quotes, never substituted
for them, with the backbone difference stated on the same row.

**Which comparison is primary (the tier-mirroring rule).** Their scaffold's Stage-2 prompt tells
the agent to slice "suspicious variables" — the +17pp is partly prompt-shaped tool routing, not
tool quality alone, and their tier bundles (tier1/tier2/coarse/explain) exist to isolate that. The
ripwire bundle mounts the full-tier verb map above, so the PRIMARY comparison is **arm (c) vs arm
(b), ARISE-Full, tool-for-tool under the constant prompt shape**; per-tier comparisons (a ripwire
bundle cut down to mirror tier1 or tier2) are secondary rungs that reuse this registration's rules
and mirror whichever tier bundle they are compared against, tool-for-tool — a ripwire arm is never
scored against a tier it carries more tools than.

**Precondition, registered as blocking: the Python slice smoke pass.** `--slice`/`--slice-flow`'s
measured runs so far are cpp-only; SWE-bench Lite is Python, so this is the slicer's first measured
Python outing. Before any arm runs, slicecheck-style probes on real Python from the pinned-SHA
SWE-bench repos (inventory sanity, def/use classification on the shapes the reference handles,
flow chains) must pass against ripwire's own registered contract. A probe failure against the
contract is a red-first gate + fix BEFORE the head-to-head; a probe landing on an already-disclosed
limit (name-based, scope-insensitive, attribute stores as reads) is recorded here as inherited by
the ripwire arm, not fixed mid-round. The smoke pass runs AFTER this registration commits and its
outcome is recorded below it, dated, whichever way it goes.

**Smoke pass EXECUTED 2026-08-31, same round — one real defect found and fixed red-first.** Probes
on django @ `e7fd69d05` (instance django__django-10914's base commit) and sympy @ `8dcb12a6c`
(sympy__sympy-11400), real functions read by hand first: inventory (`indent_code`'s 12 locals incl.
comprehension/loop variables — exact), def/use roles (aug-assign `k="both"`, correct chain to the
prior def), transitive back-flow (loop-body and comprehension occurrences chained, d=1..3 — the
strict-superset behavior the fidelity audit registered), line seed (`@ccode.py:277` resolves the
enclosing def, 3 candidates served with `seed_vars=`, never a guess), forward flow (value carried
def-to-def), and the disclosed limits verified HOLDING as registered: `self.object_list =
object_list` rows the attribute store as a read (inherited by the ripwire arm), and a method-call
mutation (`pretty.append(tab*level…)`) is not a def. **The defect:** back-flow from
`_generate_cache_key`'s `cache_key` returned `steps="0"` — the def statement spans two lines via
implicit continuation and every operand (`url`, `ctx`, `key_prefix`, `method`) sits on the
continuation line, which line-keyed chaining never saw. The registered contract's own words ("back
= statements whose values feed the seed") cover those operands, the disclosed line-grain deviation
names only the MERGE direction, and black-formatted Python wraps statements everywhere — the
round-poisoning class. Fixed before any arm runs: occurrences now carry their statement's first
line as a chaining ANCHOR (`sliceStmtAnchorLine`, per-family statement-container tables) and both
walk directions chain per statement while rows stay line-granular; the legend now discloses both
grain directions. Gated red-first in `test/sliceflowcheck.sh` arm 25 (Python + C-family
continuation fixtures; 5 FAILs recorded against the pre-fix binary), and the deviations table's
"statement ≈ LINE" row is amended in place in the rung-2 header comment. Post-fix, the probe
chains fully (`steps="5"`: all four operands at d=1, `request` at d=2); slicecheck /
mcpslicecheck / atcheck / determinism / xmllint green, ASan+LSan clean on both new gates and the
django probe. The 2026-08-30/31 measured slice numbers above were taken on the pre-fix binary;
flow rows are additive, so those figures are floors under this fix, and they are not restated.

**Improve-first (the house rule, binding).** The first completed run is loss-first: every instance
where arm (c) loses to arm (b) is bucketed by failure mechanism to a LOCAL report, fixed or
disclosed, and only THEN does any comparative number leave this section. No number from this
protocol is published in the README or deck until that pass completes.

**Owed, registered 2026-09-03, not yet measured: a follow-up-call-count column.** An external study
of context compression found that task-completion metrics can hold flat while the interaction cost
behind them does not — in one of six measured model/regime comparisons, completion moved 80%→85%
(p = 1.0, i.e. unchanged) while retrieval calls rose 21.0→63.9 (p = .002), and five of six
comparisons showed a significant retrieval-call surge ([arXiv:2608.16370](https://arxiv.org/abs/2608.16370)).
Every arm above scores File/Function/Line recall and token cost per instance; none of it currently
counts how many *extra* tool calls (a second `--for`, an `--expand`, a `--callers`) an agent needed
to reach the same answer after a given `--token-budget` trimmed the first one. That count is owed as
a column on this head-to-head and on the ARB lanes below before either is read as settled — a tighter
budget that only defers tokens into more calls is not the same result as a tighter budget that needs
none, and right now nothing here can tell the two apart. Not gating anything yet; recorded so the gap
cannot be quietly forgotten.

**Inventory, taken 2026-09-03 (lane n4-e), before any counting was written.** Where transcripts
carrying per-call evidence actually live on disk, arm by arm:

- **ARISE head-to-head (all three arms).** Zero local transcripts. The round's own text above is why:
  every arm is blocked at the LM boundary (no model endpoint/API key at registration time), so no
  instance has ever run and no SWE-agent `.traj` trajectory exists anywhere in this worktree.
  `bench/arise-h2h/swe_agent_bundle_ripwire/bin/rw_*` are the nine shims a run *would* invoke; they
  emit no call log of their own (each `exec`s the pinned binary and exits), so the call evidence for
  a future real run lives in SWE-agent's own trajectory file, one per instance, exactly like every
  other tool call in that harness — not in anything ripwire-side to build.
- **agentloop (claude / codex / opencode).** `bench/agentloop/results/pilot-6run.json` is the only
  results file committed to this worktree (schema `ripwire-agentloop-results-v2`, `codex-exec`
  harness, 3 instances × 2 arms, 2026-08-04). It **already carries per-instance call evidence**:
  `run_agentloop.py`'s own JSONL parsers (`parse_codex_jsonl_metrics` / `parse_opencode_ndjson_metrics`
  / `parse_claude_session_metrics`) populate `ripwire_calls` (an int) and `ripwire_commands` (the
  literal command list) on every record at run time — this is the same field `analyze.py`'s
  `substitution_rate()` already reads, from a different angle. The raw per-line transcripts
  (`events_path`, e.g. `/private/tmp/ripwire-codex-cli-agentloop-v2/events/*.jsonl`) do **not** exist
  locally — that directory was ephemeral and is gone — so the counted fields on the results record are
  the only surviving evidence; nothing here needs the raw file, since the count was extracted at run
  time, not deferred to post-hoc parsing. The Stage-1 48-run design (§3b above, `claude -p`, schema
  `ripwire-agentloop-results-v3`) is **not present in this worktree** — not under
  `bench/agentloop/results/`, not found anywhere else searched (`find` across the tree, git history of
  that directory) — so its per-instance call counts, if they still exist at all, are absent from this
  round's reach. Note also that `analyze.py` hard-refuses any file whose `schema` isn't exactly `v3`
  (`load_results()`), so it cannot be pointed at `pilot-6run.json` — the new counting script below
  reads any `ripwire-agentloop-results-*` schema instead, deliberately.
- **ARB lanes (`bench/arb/`).** `bench/external/arb/` (dataset bundles, repo snapshots, run outputs)
  does not exist in this worktree — untracked and never fetched, per its own registration ("pinned,
  not committed") — so there is no run output of any kind to count calls from. Separately, and worth
  recording rather than silently working around: **ARB's adapter is not an agent loop**, so the
  follow-up-call definition below does not apply to it as written. `run_arb.py`'s `compose_ranking()`
  calls a **fixed, task-determined sequence of tiers unconditionally** for every instance (e.g.
  trace2code always calls `--from-trace` then `--for` then `--query`, appending only what the earlier
  tier didn't already rank) — there is no `--token-budget` retry loop, no agent deciding whether one
  answer sufficed, and therefore no "extra call after a trimmed first answer" for this column to
  count; the tier count is a fixed adapter-design constant, not a per-instance behavioral signal. The
  column is therefore **out of scope for the ARB lanes by design**, not merely unmeasured — recorded
  here as a correction to the sentence above that named ARB as a joining table.

**Registered (this round, lane n4-e).** Definitions, held identical across both applicable surfaces:

- **calls** — the total number of ripwire invocations attributed to one (instance, arm[, seed]) run,
  read from whatever field the transcript already carries the count in (agentloop:
  `record["ripwire_calls"]`; ARISE, once a real `.traj` exists: the number of trajectory steps whose
  `action` string's leading word is one of the nine registered `rw_*` shim names).
- **follow-up calls** — `max(calls - 1, 0)`. The first call is the initial retrieval attempt; every
  call after it is the "extra call" the owed paragraph above is asking about — direct evidence of an
  agent needing a second (or third, ...) call to reach the same answer.
- **the statistic** — per-arm mean and median of `calls` and of `follow-ups`, over every record whose
  count is not absent (below), plus `n` = the record count that mean/median rests on. Reported as one
  markdown table row per arm; never pooled across arms or across harnesses (a codex call count and a
  claude call count are not the same measurement — same posture as `analyze.py`'s substitution rate).
- **floor rule** — a record/trajectory whose completion state is not clean (agentloop: `status != "ok"`;
  ARISE: `info.exit_status != "submitted"`) has its call count marked a **floor**: an aborted, errored,
  or timed-out run cannot prove its shim log or transcript parse captured every invocation before it
  stopped, so the true count may be higher. Marked per-record (`n_floor` in the table) and disclosed in
  the printed report — never silently averaged in as if it were exact (CLAUDE.md non-negotiable 3).
- **absent rule** — a record whose call count was never measured (agentloop: `ripwire_calls is None`,
  e.g. `claude -p` runs recorded before 2026-08-22; ARISE: no `.traj` file exists for that arm at all)
  is counted separately (`n_absent`) and **excluded** from every mean/median — never coerced to 0,
  which would misread as "the agent never needed a follow-up" when the truth is "nobody measured it".
  An arm with zero measured records shows the column as **absent for the whole arm**, not a zero row.
- **gates** — `test/agentloopfollowupcheck.sh` (`bench/agentloop/followup_calls.py`) and
  `test/arisefollowupcheck.sh` (`bench/arise-h2h/followup_calls.py`), both listed in
  `test/regression.sh`. Each gate's own `--self-test` fixture exercises a clean multi-call record, a
  floor (non-clean completion), and an absent (unmeasured) record before any real number is trusted;
  the agentloop gate additionally cross-checks the real committed `pilot-6run.json` end to end against
  hand-derived expected numbers, so a schema-shape regression the synthetic fixture wouldn't catch
  still fails there.

**RUN, 2026-09-03 (lane n4-e) — what was actually measured, and what remains owed.** The only surface
with local transcripts carrying the count is agentloop's `pilot-6run.json`. Reproduce with:

```
python3 bench/agentloop/followup_calls.py --results bench/agentloop/results/pilot-6run.json
```

| arm | n | measured | absent | floor | mean calls | median calls | mean follow-ups | median follow-ups |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline | 3 | 3 | 0 | 0 | 0.00 | 0.00 | 0.00 | 0.00 |
| ripwire_cli | 3 | 3 | 0 | 0 | 4.33 | 5.00 | 3.33 | 4.00 |

Read narrowly: this is the 2026-08-04 six-run codex pilot (§3b above already retires that pilot's
*outcome* numbers as non-comparable to the later, better-isolated design — this table only adds the
call count the pilot happened to already log, it does not rehabilitate the pilot as an outcome
source). n=3 pairs is nowhere near enough to say anything about the population; it is here because it
is the only committed file the count could be pulled from without a new run, and every number above is
computed by the script, never hand-typed.

**Still owed, unchanged by this round:** the Stage-1 48-run claude-harness table (§3b) — absent
locally, per the inventory above; the ARISE head-to-head, all three arms — absent, blocked at the LM
boundary, the counting script exists and is gated on a synthetic fixture but has nothing real to run
against yet. ARB is removed from the "owed" list per the scope correction above, not fulfilled. This
paragraph replaces, rather than resolves, the original owed sentence's claim that ARB was a joining
table.

## Agent Retrieval Bench — external loss-first lane, PRE-REGISTERED 2026-08-28 (before any measurement)

**The benchmark.** *Agent Retrieval Bench: Evaluating Repository Context Retrieval for Coding Agents*
(arXiv 2607.24882, July 2026). 427 samples across 25 repositories (13 Python, 3 Go, 3 Rust,
3 TypeScript, 2 Java, 1 JavaScript), four retrieval tasks plus an abstention set. Artifacts verified
public before this registration was written: evaluator and metadata MIT-licensed
(github.com/eyuansu62/agent-retrieval-bench), dataset ungated on HuggingFace
(datasets/eyuansu71/agent_retrieval_bench) with the repository snapshots included — corpus source
files retain their upstream licences, which is why the data lives **pinned, not committed**, in the
untracked `bench/external/arb/` (same posture as the extcorpus slice above and `bench/multiswe/`'s
raw cache).

**Why this benchmark.** Its four tasks are the four questions ripwire's verb catalog claims to
answer, so it scores the *mapped verb*, not a generic ranker shim. The paper's own finding — a
vectorless RepoMap family winning trace2code (MRR 0.274 vs 0.083 for the best embedding) — is the
family ripwire belongs to; this lane measures whether ripwire is that family's strongest instance,
loss-first.

**Task → verb mapping, registered before any adapter run:**

| Benchmark task | n | The signal | ripwire verb |
| --- | ---: | --- | --- |
| `code2test` | 106 | PR intent → related tests | `--affected` (changed files → reaching tests), `--test-gate` posture |
| `comment2context` | 80 | review comment + file → additional context files | `--for` (anchored: the reviewed file is pasted verbatim into the query) |
| `trace2code` | 101 | reproduced failure output → root-cause files | `--from-trace` (the trace is pasted, never hand-translated) |
| `edit2ripple` | 58 | anchored code change → additionally affected files | `--impact` (transitive) seeded from the changed symbols |

Symbol→file projection: ripwire ranks symbols with `p="file:line"`; the benchmark ranks files. The
adapter (`bench/arb/run_arb.py`) dedupes to file rank by **best symbol rank per file** — registered
here so the projection cannot be tuned after seeing scores.

**Metrics, exactly as the paper defines them:** MRR (first ranked gold file), Recall@20 (fraction of
gold files in the top 20 unique files), and BCY@8k (Budgeted Context Yield at an 8k-token budget,
τ=1 canonical). Scored with the benchmark's own scorer where it runs; any local reimplementation is
diffed against the shipped scorer on at least one task before being trusted.

**The abstention arm.** The 50 natural no-gold samples (maintainer evidence attributes the fix to an
upstream dependency) and the 32 counterfactual wrong-repository controls are scored as
*refusal-quality*, not skipped: honesty in output is this tool's stated feature (§ Non-negotiables),
so "returns confident garbage on an unanswerable query" is a first-class loss bucket, and the
abstention rate is reported next to the retrieval metrics, never instead of them.

**Decision rule — this is a LOSS-FIRST round (the improve-first house rule).** The deliverable is a
loss-bucket list: every sample where ripwire under-performs the difficulty implied by the paper's
published RepoMap/Qwen3 numbers, classified by failure mechanism (missing edge type, tokenizer miss,
doc-vs-code confusion, multi-root layout, abstention miss, …), written to a LOCAL `PLAN_*` report.
**No comparative number from this lane is published in EVALS or README until a fix round completes
and re-measures.** Fix rounds register their own bands per bucket, per the extcorpus template above.

**Determinism gate before any sweep is trusted:** one sample per task run twice, rankings
byte-identical, or the sweep does not run. Subsetting, if the full 25-repo corpus is not swept, is
**disclosed in the report** (stratified: all four tasks, ≥3 languages) — never silent.

**Instrument v2 (2026-08-29, registered before the fix-round re-measure).** The adapter now consumes
three output surfaces that did not exist at the original registration: `--from-trace`'s disclosed
test→source hop rows are spliced into the composition after the innermost frame (the emitted legend
states that served order); `--for --json` file order follows the per-symbol rank fact `r=` (best
symbol per file) where present; and the file-grain `tail` extends the composed depth after the head.
Each is a faithful reading of what the binary now serves and discloses — no metric-side re-ranking,
no change to the scorer or to any metric definition. The re-measure runs this adapter version, and
its determinism gate re-ran clean after these edits.

**RE-MEASURED 2026-08-29 — the fix round completed, so per this registration's own rule these
numbers are now published.** Same 9-repo stratified subset as the loss-first sweep (disclosed
above; trace2code is the FULL task, no subsetting), same scorer definitions, determinism gate OK
on all tasks before the sweep, binary = the merged fix-round head. Pre-fix values are the
loss-first sweep's, on the identical subset and adapter task composition (instrument v2 splices
surfaces the pre-fix binary never emitted, so its pre-fix numbers are unchanged by it):

| task | ripwire pre-fix MRR / R@20 | ripwire post-fix MRR / R@20 | paper RepoMap (full task) | best-in-paper |
| --- | --- | --- | --- | --- |
| trace2code (full, n=101) | 0.158 / 0.627 | **0.283 / 0.797** | 0.274 / 0.837 | RepoMap 0.274 / 0.837 |
| code2test (n=71 of 106) | 0.388 / 0.617 | 0.388 / 0.624 | 0.236 / 0.604 | Qwen3-4B 0.323 / 0.660 |
| comment2context (n=35 of 80) | 0.253 / 0.510 | 0.255 / 0.495 | 0.215 / 0.588 | Jina 0.304 MRR / Qwen3-8B 0.688 R@20 |
| edit2ripple (n=46 of 58) | 0.341 / 0.496 | 0.341 / 0.496 | 0.207 / 0.655 | Qwen3-4B 0.288 / 0.711 |

The registration's stated question — is ripwire the RepoMap family's strongest instance on the
family's own task — flips from NO to YES on MRR: trace2code 0.283 vs the paper's RepoMap 0.274,
carried by the `--from-trace` test→source hop (87/101 traces frame only test files) plus the
trace-shaped document-tier demotion (docs in the top-5 fell 53→27 of 101; a doc at rank 1 fell
15→10). Recall@20 closes most of its gap (0.627→0.797 vs 0.837) but stays below — the file-grain
tail extends composed depth (median 30→35 files) without reaching RepoMap's 20-deep coverage.
Gold-at-rank-1 is 0/101 BY DESIGN: the innermost test frame keeps rank 1 (the hop discloses, never
rewrites the frame partition), so gold rides rank 2–4 — MRR reflects exactly that. The three other
tasks were already wins and moved little: their pre-fix numbers stand re-confirmed post-fix.
Subset caveat applies to every row but trace2code; the same-46-sample edit2ripple comparison
against shipped repomap_details stands at MRR 0.341 vs 0.235. The paper's BCY@8k column remains
NOT reproduced here (≠ shipped `gold_coverage@8k`, ~9× apart) and is never approximated. The
abstention arm's calibration outcome is the recorded NEGATIVE in the next section.

## Agent Retrieval Bench — abstention calibration round, PRE-REGISTERED 2026-08-29 (before any
selective-split measurement)

**Why this round.** The loss-first lane above found LB-E: the abstention task's 47/47 unanswerable
subset all got a confident-looking ranking, because the ranking-confidence disclosure landed for
`--for` (`confidence="high|low"`, `margin_pct=`) but nothing in the ARB adapter scored it. That
disclosure ships the exact two facts this round calibrates against. This registration is written
against the selective-split bundles' **schema and row counts only** — no per-sample content or label
distribution was read before this text was committed, per the house discipline that a registration
must precede the measurement it governs.

**The two shipped facts (source: `deriveForConfidence`, the `--for --json` root).** `confidence` is
binary (`"high"`/`"low"`). `margin_pct` is an integer 0–100, but it is **not independent of
confidence**: `confidence="low"` always ships `margin_pct="0"` (the derivation's `hitCeiling`-and-not-
`servedComplete` branch forces it), so margin only varies *within* `confidence="high"` rows. A third
fact the adaptive-cut statistic computes internally — `kept` / `positiveHits` (the window size and how
many symbols actually scored, i.e. "N") — is **not surfaced** on any `--for` output, JSON or XML. This
round therefore evaluates confidence/margin only; it does not attempt a kept/N sweep, and if the bands
below are not met, surfacing kept/positiveHits as new facts is the natural next-round fix, out of
scope here.

**The verdict rule under test.** `predicted_abstain = (confidence == "low")` is the **default
operating point (DOP)** — threshold-free, exactly what a caller reading the header would do. Because
margin only varies inside `confidence="high"`, the only meaningful sweep is a combined ordinal score
that lets a weak-margin "high" sample be pulled into "abstain":

```
score(sample) = 0.0                          if confidence == "low"
              = 1.0 + margin_pct / 100.0      if confidence == "high"
```

`score` is monotone in the tool's own stated confidence ordering (every "low" ranks below every
"high", and within "high" a smaller margin ranks lower). The threshold sweep tries `abstain if score <
θ` at every distinct value of `score` present in the data, plus the DOP (`θ` such that only
`score == 0` abstains). No per-sample value is read before this rule and sweep are committed.

**Datasets and n (from bundle manifests / row counts, not per-row content):**

| dataset | rows (9-repo mirror subset) | no_gold | positive | usable metrics |
| --- | ---: | ---: | ---: | --- |
| `v2_abstention` (the original LB-E subset) | 47 | 47 | 0 | recall only — single-class, no AUROC/precision/false-abstain-rate |
| `v2_selective_retrieval_balanced` | 108 | 47 | 61 | full confusion matrix + AUROC + threshold sweep (primary — near-balanced) |
| `v2_selective_retrieval_natural` | 300 | 47 | 253 | full confusion matrix + AUROC + threshold sweep (secondary — realistic no-gold prior) |

The subset filter is the same 9-repo mirror set already disclosed above (`SUBSET_REPOS` in
`bench/arb/run_arb.py`); rows outside those repos are excluded because no bare mirror is held for
them, exactly as the parent lane does — never silently, the adapter prints the kept-of-total count.
`positive` rows use whichever verb the sample's own `task_type` maps to (the table in the parent
section); the `confidence`/`margin_pct` used for the abstention verdict is read from that same
`--for` call already made as one of the tiers in `compose_ranking` — no extra invocation, no
cherry-picked query.

**Metrics.** Per dataset (where the class mix allows it): abstention recall (sensitivity,
TP/(TP+FN)), false-abstain rate (FP/(FP+TN), i.e. positive samples wrongly abstained on), precision
and F1 of the DOP; AUROC of `score` against the no_gold/positive label via the rank-based
Mann-Whitney identity (ties averaged) — a single ROC point from a mostly-binary feature is not
informative on its own, which is why AUROC is computed over `score`, not over raw `confidence`; and
the F1-maximizing threshold from the sweep above, reported with its own confusion matrix. Every
metric is computed per dataset — no pooling across datasets with different class balance.

**Bands — set now, before any row is scored:**

- **AUROC** (balanced and natural splits): ≥ 0.65 → *meets* (confidence carries real separating
  signal beyond chance); 0.55–0.65 → *weak* (marginal, not worth shipping as a gate); < 0.55 → *does
  not meet* (no meaningful separability from this signal).
- **DOP safety** (both selective splits): false-abstain rate ≤ 0.10 **and** abstention recall ≥ 0.20
  → *DOP meets floor* (safe to treat `confidence="low"` as an abstain signal as-is). Recall on the
  single-class `v2_abstention` subset is reported the same way (≥ 0.20 against the same floor) but
  cannot confirm false-abstain rate by itself.
- **Best-F1 threshold** (both selective splits): F1 ≥ 0.35 → *meets* (the signal is calibratable to a
  usable gate even if the DOP alone is not); F1 < 0.35 → *does not meet* (confidence/margin_pct alone
  cannot support a usable abstention gate; the fix is a new emitted fact, not a threshold).

**Decision rule.** This is a calibration round, not a fix round: it reports whether the shipped
disclosure is *already* usable as an abstention signal and, if so, at what operating point — it does
not change `--for`'s behavior. Per the improve-first house rule, the measured numbers stay local (the
lane's own `LANE_REPORT.md`, never committed); this section may record only whether the pre-registered
bands were met, not the numbers themselves, mirroring how the parent lane's numbers stay out of this
file until a fix round re-measures.

**Determinism gate before any sweep is trusted:** the same one-sample-run-twice gate as the parent
lane, extended to the selective-split composition.

**SWE-Explore side-by-side (registered here, scored separately below).** SWE-Explore's own bench file
ships no natural no-gold/abstention split — every instance derives from a real accepted fix, so there
is no unanswerable-query class to calibrate against. A pseudo-split manufactured from zero-recall
instances (an instance where the explorer's arm found none of the core lines) would conflate "hard but
answerable" with "should abstain" — a different failure mode — so no abstention calibration is run on
SWE-Explore; this is recorded as a coverage boundary of that benchmark, not a gap in this round.

**MEASURED OUTCOME (2026-08-29, base binary of this round): the registered bands were NOT met — this
is a recorded negative.** `confidence="low"` fires at ~85–87% on the natural split *regardless of
answerability* (no-gold 85.1% vs answerable 87.0%), so the declared-operating-point false-abstain rate
lands at 80–87% against the registered 0.10 ceiling, and rank-based AUROC over the combined
confidence/margin score is indistinguishable from chance (0.48 balanced, 0.51 natural). One F1 cell on
the balanced split crossed its band numerically but is a degenerate always-abstain artifact of that
split's class balance — it is not reported as a pass. **No operating point is recommended.** The
conclusion the numbers force: the shipped disclosure is honest about *ranking shape*, but ranking
shape and *query answerability* are close to independent on this benchmark's query mix — so threshold
tuning over `confidence=`/`margin_pct=` alone is CLOSED as a fix shape for the abstention loss bucket.
A future round needs a new fact surfaced from the ranker (the adaptive cut's kept-vs-scored and
positive-hit counts are not emitted on any surface today) rather than a recalibration of these two.

## Agent Retrieval Bench — abstention round 2: the adaptive cut's corpus-support facts,
PRE-REGISTERED 2026-08-30 (before any measurement)

**Why a second round on the same axis.** The round above is a recorded NEGATIVE: `confidence=` /
`margin_pct=` separate answerable from unanswerable at chance, and threshold tuning over those two is
CLOSED. Its own closing sentence names the next candidate: the adaptive cut computes two counts that
reach no output surface — `kept` (the cliff-clamped head size) and `positiveHits` (how many indexed
symbols scored above zero for this query). This round surfaces those, plus the denominator they are
meaningless without, and calibrates ONE pre-designated statistic over them. Written against the same
selective bundles' schema and row counts as the round above; no per-sample value of any NEW field
existed when this paragraph was committed, because the binary did not emit one yet.

**The three facts this round adds (`--for --json` root, that dialect only).** `scored` =
`AdaptiveCut::positiveHits`, the count of indexed symbols whose routed lexical score is > 0 for this
query, from the SAME `adaptiveCut` call the confidence disclosure already derives from — no second
scorer, no second pass. `kept` = `AdaptiveCut::kept`, the cliff-clamped head size in [5, 40].
`corpus` = the length of the lens rank vector, i.e. how many symbols were scored at all — the
denominator without which `scored` is a repo-size measurement rather than a query measurement. The
three are HARNESS-FACING and land on nothing but the JSON root. The XML bundle stays byte-identical
on purpose: its header rides a measured byte ceiling (`fornotesbudgetcheck.sh` fits at exactly
`est_tokens=800`), and a disclosure this round may well close as a second negative has not earned
bytes off every ranked answer. Promoting them to root attributes with a legend clause and the
surface-audit checklist is part of the behavior change a POSITIVE would license, not part of this
instrumentation.

**Why this is a different signal, not a reparameterization of the last one.** `confidence=` is a
statement about the ranking's SHAPE — whether a cliff falls inside the served head. `scored/corpus`
is a statement about the query's GRIP on the corpus — what fraction of the indexed symbols the
query's terms reach at all. The round above's conclusion was exactly that shape and answerability are
near-independent on this query mix; grip is the other axis the same statistic already carries and has
never emitted.

**The statistic under test — designated PRIMARY before any row is read.**

```
support(sample)       = scored / corpus        # in [0, 1]
abstain_score(sample) = 1.0 - support          # higher = more likely unanswerable
```

AUROC of `abstain_score` against the positive class "should abstain" (`selective_label == "no_gold"`),
by the same rank-based Mann-Whitney identity with averaged ties the round above used, computed per
dataset with no pooling across datasets. The DIRECTION is part of the registration: the hypothesis is
that an unanswerable query has THINNER corpus support. Rows where the binary emitted no
`scored`/`corpus` are `signal_missing`, excluded from the statistic, counted and reported — exactly
how the round above treats a missing `confidence`.

**Secondary statistics — reported for the record, never deciding the verdict.** (a) raw `scored`,
unnormalized, to show how much of any separation is repo size rather than query grip; (b)
`kept / scored`, the served head's share of everything that matched; (c) the joint rule
`abstain iff confidence == "low" AND support < θ`, best-F1 over the same threshold sweep, to test
whether grip rescues the shape signal that failed alone. Naming these SECONDARY now is the guard
against reading the best of four out of the table afterwards and calling it the hypothesis.

**Bands — set now, at the same thresholds as the round above so the two are comparable.**

- **PRIMARY AUROC**, on `v2_selective_retrieval_balanced` AND `v2_selective_retrieval_natural`:
  ≥ 0.65 → *meets*; 0.55–0.65 → *weak* (marginal, not shipped); < 0.55 → *does not meet*.
- **Directional refutation, stated now so it cannot be spun into a pass afterwards:** AUROC ≤ 0.35
  means the signal separates in the OPPOSITE direction to the registered hypothesis. That is recorded
  as a refutation of the direction, NOT as a pass; acting on it would need its own registration in a
  later round.
- **Operating point — reachable only if PRIMARY meets on BOTH splits:** a threshold θ must exist with
  false-abstain rate ≤ 0.10 AND abstention recall ≥ 0.20 on both splits simultaneously. Only then is
  an abstention BEHAVIOR licensed.

**What ships on each outcome.** PRIMARY meets and an operating point exists → the facts are promoted
to `--for`'s XML root with a legend clause under the full surface-audit checklist (legend coverage,
`--help`, skills), and the abstention behavior is wired with disclosure and gated. Anything else →
this is a second registered NEGATIVE on the abstention axis: the three JSON keys stay as
harness-facing instrumentation (they are honest facts and cost the XML bundle nothing), `--for`'s
behavior is unchanged, and the axis stays **"disclosed, not acted on."** Per the improve-first rule
the measured numbers stay in the lane's own local report; this section records only which band was
met.

**Determinism gate before the sweep is trusted:** the same one-sample-run-twice gate as the parent
lane, extended so the new facts are part of the compared payload (the harness already compares the
confidence dict between the two runs; the new keys ride in it).

**MEASURED OUTCOME (2026-08-30, the instrumented binary of this round): the registered band was NOT
met — this is a second recorded negative on the abstention axis.** Determinism gate OK on both
selective splits before the sweep. `signal_missing` is 0 on all three datasets: the instrumentation
reached every scored row, so nothing here is an artifact of a missing fact. The PRIMARY
`support = scored/corpus` AUROC is **0.434** (balanced, 47 no-gold / 61 positive) and **0.409**
(natural, 47 / 253) — *does not meet* against the ≥ 0.65 band on both, and short of the 0.55 *weak*
rung too. Neither reaches the ≤ 0.35 directional-refutation rung either, but both sit BELOW 0.50,
which is worth stating plainly: to the small extent corpus support separates at all, it separates the
OPPOSITE way to the registered hypothesis — an unanswerable query on this benchmark's mix grips
slightly MORE of the corpus, not less. **No operating point exists**, on the primary or on any
secondary, on either split: no threshold anywhere in either sweep reaches false-abstain ≤ 0.10 at
recall ≥ 0.20, so the registration's licensing condition is not merely unmet on the AUROC gate, it is
unreachable behind it.

The secondaries, reported because they were registered as reported and not because any of them is
being promoted: raw un-normalized `scored` gives 0.428 / 0.404, i.e. the denominator this round
insisted on is worth about 0.006 of AUROC — repo size was not what was hiding the signal, because
there was no signal to hide. `kept / scored` gives 0.525 / 0.591; the natural split's 0.591 lands in
the *weak* rung, and it is named here precisely so that it is on the record as a SECONDARY that the
registration declared unshippable in advance, rather than reappearing later as this round's finding.
The joint `confidence == "low" AND support < θ` rule gives 0.491 / 0.435 — grip does not rescue
shape. As a control, round one's own statistic re-measured on these same rows reproduces its recorded
result (0.472 balanced / 0.509 natural against the recorded 0.48 / 0.51), so the new negative is a
property of the signal and not of a changed harness.

**What this closes.** Round one showed the ranking's SHAPE is near-independent of answerability here.
This round shows the query's GRIP on the corpus is too — and both are functions of the same routed
lexical score distribution, which is now the thing that has been tested, not any particular
summary of it. `--for`'s behavior is unchanged, the three counts stay harness-facing on `--for --json`
(never promoted to the XML root — `test/forcalibfactscheck.sh` fails if they ever are without a
calibration that earned it), and the axis stays **"disclosed, not acted on."** A future round on this
axis needs a fact that is NOT derived from the lexical score distribution at all; recalibrating over
what that distribution already knows is now closed twice.

*Disclosure about this record.* The registration above said this section would report only which band
was met, with the numbers staying in the lane's local report. It carries the numbers instead, matching
what round one's own negative published — publishing MORE than registered on a NEGATIVE cannot
manufacture a favorable result, and EVALS is the measurement record. The numbers stay out of README
and every other public-facing surface, which is the constraint that actually binds.


## SWE-Explore exploration lane (2026-08-28) — PRE-REGISTERED, loss-first, before any measurement

**What this registers.** An external-benchmark evaluation lane on *SWE-Explore: Benchmarking How Coding
Agents Explore Repositories* (arXiv 2606.07297). SWE-Explore scores repository EXPLORATION in isolation:
given an issue and a repository snapshot, an explorer returns a RANKED list of code regions
`(path, start_line, end_line)` under a fixed line budget; ground truth is line-level, distilled from
independent successful repair trajectories (848 instances, 10 languages, 203 repos). This section is
written and committed BEFORE the harness has scored a single instance. No number appears here.

**Artifacts and licenses.** Code: `github.com/Qiushao-E/SWE-Explore-Bench` (MIT), whose `eval.py`
`ExploreEvaluator` is the scorer of record for this lane — imported and used unmodified, never
reimplemented. Dataset: Hugging Face `SWE-Explore-Bench/SWE-Explore-Bench`, single file
`bench.final.public.jsonl` (848 rows), license **CC-BY-NC-ND-4.0** — therefore the data, the benchmark
clone, and every repository snapshot live in the untracked, gitignored `bench/external/swex/` and are
never committed or redistributed from this repository. Issue text and base commits are NOT in the bench
rows; they are joined from the upstream datasets the bench derives from, keyed by `instance_id`:
`princeton-nlp/SWE-bench_Verified` (rows tagged `dataset="verified"`) and
`SWE-bench/SWE-bench_Multilingual` (rows tagged `dataset="multilingual"`).

**The two arms.** Both are one-invocation uses of the shipped binary on the repository snapshot checked
out at the instance's `base_commit`, given the verbatim issue text (title + problem statement, pasted
unparaphrased — the anchoring contract says paths/symbols in the issue must reach the query literally):

- **Arm FOR** — `ripwire <snapshot> --for="<issue>"`: the ranked signature rows, in emitted order.
- **Arm PACK** — `ripwire <snapshot> --pack-task="<issue>"`: the task bundle's ranking-section rows, in
  emitted order (the bundle's own body/caller sections are not extra predictions; the ranking order is
  the arm's ranking).

**Symbol → region mapping.** A ranked row gives `p=` (path, root-relative) and `l=` (1-based start
line). The end line comes from the symbol's own body extent: per instance, ONE follow-up
`--expand=sel1,sel2,…` call per arm (selectors are the rows' canonical `id=` when present, else
`FILE:NAME`), and `end = l + (CDATA newline count of the <b> body)`. A row whose expand returns no body
(declaration-only, macro, expand miss) becomes the single-line region `(p, l, l)` — counted and
disclosed in the run report, never silently dropped. Regions are deduplicated (first, i.e. highest,
rank wins) and emitted in rank order.

**Line budget.** The ranked region list is cut at the paper's main budget **B = 500 cumulative lines**
(a region straddling the cut is kept whole, matching the scorer's own budget semantics). The scorer's
`recall_at_{100,300,500}` and `ndcg_at_{100,300,500}` truncate further internally, giving the paper's
B ∈ {100, 300, 500} ladder from the same prediction file.

**Metrics (theirs, verbatim).** Coverage = line-level `precision` / `recall` / `f1_score` against core
regions, plus `hit_file_rate`; Ranking = `ndcg_at_{100,300,500}` (main-file lines ×1.5, density-ideal
normalization) and `first_useful_hit`; Context-efficiency = `context_efficiency`
(pred ∩ (core ∪ optional) / pred) plus `noise_file_rate` as a diagnostic. `file_line_counts` (needed to
resolve `end=-1` ground-truth regions) are computed from the snapshot at `base_commit`.

**Subset (tonight's run is a subset, disclosed as such).** The full 848×203 corpus is out of scope for
one session. The run uses a stratified subset with the deterministic rule: an instance's language is the
majority file extension of its ground-truth `modified_core_files`; within each language, instances sort
by `instance_id` and the first N are taken. Floors: ≥ 5 languages ripwire parses, ≥ 60 instances,
drawing Python from `verified` and the rest from `multilingual`. Exclusions, registered up front:
`dataset="pro"` rows (215) — third upstream join, out of tonight's scope; PHP rows — ripwire has no PHP
grammar, so the arm cannot rank PHP symbols (a known coverage boundary of the tool, not of the
benchmark); instances whose snapshot cannot be fetched at `base_commit` — counted in the report. Subset
composition is recorded in the run report before scoring.

**Determinism gate.** One instance, both arms, run twice end-to-end: prediction files byte-identical, or
the lane stops.

**Decision rule — LOSS-FIRST (the improve-first house rule).** The deliverable of this lane is a
loss-bucket analysis (an operator-local report, never committed): where core-line coverage
misses concentrate (language, dispatch-heavy edges, docs-vs-code, issue-vocabulary vs
identifier-vocabulary), whether PACK beats FOR at equal budget, and the largest fixable shapes. **No
comparative number from this lane is published — in this file, the README, or anywhere public — until a
fix round has re-measured.** Local numbers exist only to rank the loss buckets.

**Instrument v2 (2026-08-29, registered before the fix-round re-measure).** The harness's
`flatten_ranked` now sorts served rows by the per-symbol rank fact `r=` where the binary emits it
(stable; unranked rows keep document order after the ranked ones) — the document-order approximation
the original registration disclosed is thereby retired on binaries that serve `r=`. The file-grain
`tail` surface is NOT consumed here (regions are symbol-grained under the 500-line budget); that is
an unconsumed surface of this harness, recorded rather than silently absorbed.

**RE-MEASURED 2026-08-29 — the fix round completed; per this registration's rule the numbers
publish, and the result is MIXED, reported with its decomposition rather than rounded to a win.**
Same 68-instance subset, same scorer of record, determinism byte-identical. Three-way A/B on the
FOR arm separates the binary's effect from the serving-order instrument's (the v1 harness reads
document order; v2 reads the rank fact `r=`):

| FOR arm, B=500 | line recall | hit_file_rate | nDCG@500 | noise_file_rate |
| --- | --- | --- | --- | --- |
| pre-fix binary × v1 harness | 0.135 | 0.260 | 0.357 | 0.728 |
| post-fix binary × v1 harness | 0.123 | 0.281 | 0.378 | 0.716 |
| post-fix binary × v2 harness | 0.109 | 0.311 | 0.361 | 0.742 |

The BINARY improved file-level retrieval — hit_file_rate +2.1pp, nDCG +2.1pp, noise −1.2pp,
zero-recall instances 32→30 of 68 (the meta-doc demotion and vendored-bundle tier working as
registered) — at a −1.2pp line-recall cost: demoting prose changed which regions fill the 500-line
budget, and the replacing code regions are not always gold lines. The INSTRUMENT's rank-order
serving then trades a further −1.4pp line recall for +3.0pp hit_file_rate: this benchmark's
line-grain scoring rewards depth-per-file, and true-rank-order serving spreads the budget across
files. That trade-off is now a measured fact of serving shape, not a ranking defect — the natural
follow-up (rank-ordered file SELECTION with file-grouped bodies) is a candidate for a future
round, not retrofitted here. PACK arm moved the same directions (nDCG 0.348→0.368, hit_file
0.263→0.285). All numbers remain subset-local (n=68, python stratum all-astropy, disclosed above);
the CC-BY-NC-ND data itself stays untracked.

## Shape-conditional documentation-tier demotion (2026-08-29) — PRE-REGISTERED, before any measurement

**What changes.** `--for` and `--pack-task` — and their MCP twins — classify the QUERY's SHAPE before
they rank, and demote the documentation tier when that shape says the answer cannot be prose. Two
shapes are recognised, from the query text alone:

- **trace-shaped** — the text parses as stack frames, sanitizer output, or a compiler diagnostic. The
  classifier reuses `--from-trace`'s own frame extractor (`src/tracein.h`); there is no second parser,
  and its known blind spots are its blind spots here too.
- **bug-report-form-shaped** — the text is a pasted issue-template form: two or more distinct template
  field labels (`Describe the bug`, `Steps to reproduce`, `Expected behavior`, …) or markdown task-list
  checkboxes, each counted only where it is used as a LABEL — at a line start, or behind markdown
  heading / bullet / emphasis punctuation — never inside a sentence.

When either fires, the document tier is DEMOTED in the ranking lenses: the same shrink-only,
path-keyed multiplier the fixture-and-generated tier already applies, applied to files that carry a
document extension, and applied TWICE to repository meta-prose (issue and pull-request templates,
`CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY`, `SUPPORT`, `GOVERNANCE`, changelogs, anything under
`.github/`). Demotion, never exclusion — those files stay indexed, still score, still win when nothing
else matches, and the query-mention anchor still lifts a document the task literally names. The
demotion is disclosed verbatim in the bundle's `route=` attribute and its JSON twin, so a reader can
always see that it happened, which shape fired, and on what evidence.

**Why.** Both external retrieval lanes registered above lose head slots to prose that matches a pasted
failure or a pasted issue form rather than the code the task is about. When the query IS a failure
artefact the answer is code by construction; when the query IS the repository's own bug form, the
strongest lexical match in the repository is often that form.

**What is deliberately NOT changed** — each already recorded as a negative or closed by an earlier
round: no short-document floor, no query-term density weighting, no stemming, no pooling or
hierarchical retrieval, no edit to the routing decision itself, and no change to any scoring formula.
This is one tier multiplier conditioned on query shape, and nothing else.

**Invariance contract, gated by `test/docdemotecheck.sh`:**

- `--recall` — the documents-only verb — is byte-identical, on a fixture corpus and on this repository.
  It does not take the ranking tier and must not start taking it.
- a conceptual `--for` query (no shape match) is byte-identical to the pre-change binary, on the same
  fixture and on this repository.
- `--no-route` is byte-identical: with no `route=` attribute there is nowhere to disclose the
  demotion, so it does not happen.

**Decision rule at re-measure.** Judged on the two external lanes registered above, on their own
harnesses, the same disclosed subsets, the same binary discipline, determinism gate first:

- on the trace-to-code task, MRR and Recall@20 must both move UP, and no other task in that lane may
  lose more than 0.01 MRR;
- on the exploration lane, mean line recall for the `--for` arm must move UP with `hit_file_rate` not
  falling, at the same line budget;
- the share of rank-1..3 slots held by documents must FALL on shape-matched queries and must not move
  at all on unshaped conceptual queries — the latter is structural, since those runs are byte-identical.

If any of the three fails, the change is reverted rather than re-tuned and the negative is recorded in
§7. No number from this lane is published anywhere until that re-measure has completed.
## Deep-tail serving (2026-08-29) — REGISTERED CONTRACT, judged by the standing external lanes

**Motivation.** The two pre-registered external retrieval lanes above (Agent Retrieval Bench; the
SWE-Explore exploration lane) both measured the same serving-shape pair of losses, independent of
ranking quality: (1) the ranked bundle groups symbols by file and sorts by line inside the group, so a
budget-truncating consumer reads document order and the ranker's true per-symbol order is
unrecoverable; (2) the lens serves ranked symbol heads concentrated in few files while file-grain
consumers score recall 20+ deep, so the composed ranking runs out of files long before that depth even
on task families where its head already wins.

**The claimed contract (gate-pinned in `test/deeptailcheck.sh`, none of it an accuracy claim).** Every
lens-ranked signature row (`--for` and `--pack-task`, XML and JSON, CLI and MCP `for`) carries its
1-based global rank in that bundle's lens ranking (` r="N"` / `"r":N`), rank-consistent with the flat
`--format=candidates` export; ranks are assigned before the byte-trim ladder, so a trimmed row leaves a
visible gap rather than a renumbered fake-contiguous head. After the signature-shaped sections, `--for`
serves a FILE-GRAIN TAIL — the remaining candidate files with a positive lens score, paths only, in the
best-symbol projection of the same ranking — disclosed as `total=`/`shown=`/`capped=` and labelled in
the legend as weaker evidence than the head; the JSON dialect carries the same object always
(`"tail"`), and 0 means genuinely none remain. The tail is a projection of the existing ranking, never
a re-rank; serving it makes the lens a full-distribution consumer, so the bundle path scores
exhaustively (the `--adaptive` rule) and `total=` is a real count, not a pruning artifact. Byte cost is
measured and disclosed through `est_tokens`; under an explicit `--token-budget` the tail is funded last
and trims to its empty shell rather than breaching the ceiling.

**What judges it.** No new eval: the already-registered ARB and SWE-Explore re-measures are the
judges — the adapters consume the rank facts and the file tail instead of their document-order and
head-only approximations, and the pre-registered metrics (file MRR / Recall@20 there; nDCG@500 /
recall@100 there) move or they do not. Publication stays gated on those re-measures per the
improve-first rule.

## The locality-pinned population — S6-C silent-pin precision census, PRE-REGISTERED 2026-08-31 (before any census run)

**What this registers.** A measurement-only census of the one resolver population no instrument has
ever isolated: call sites the S6-C locality tie-break pins to a single target and therefore —
deliberately, by documented design — never counts in `amb=` / the header `ambiguous=`. This section
fixes the population definition, the oracle, the instrumentation verdict, the corpora, and the
accept/reject bands BEFORE any number exists. Nothing below is a result; the census itself is a later
phase, and no resolver or output behaviour changes in this one.

**The mechanism under audit, restated from the source (`src/graph.h`, S6-C block;
`resolve.h::sharedLocality`).** After qualified/canonical resolution, the receiver-narrowing rules,
the CHA cone and the arity filter have all run, a call whose candidate tier still holds >1 in-repo
definition prefers the candidate(s) whose canonical id (`path/to/file.ext::scope::name`) shares the
longest whole-SEGMENT prefix with the caller's canonical id — same file > same class/scope > same
directory. `sharedLocality` counts only prefixes ending exactly on a `/` or `::` boundary, so partial
overlap inside one segment (`Xenon` vs `Xtra`) scores zero and cannot manufacture a win. The
tie-break only re-weights among tier survivors: it never adds a candidate the fallback ladder didn't
reach, and it never empties the tier (a full locality tie leaves the tier intact and the call stays
split). It is skipped entirely when the caller is scope-less (bare canonical id — no locality to
compare; so every S6-C pin has a SCOPED caller), when the receiver is a depth-2 chained field
(`RecvKind::FieldOfThis` / `FieldOfVar` — the chainguardcheck history), and on SCIP- or
binding-pinned sites. When it leaves exactly ONE non-self survivor, the call emits as a single
confident edge and `ambOut` is NOT incremented — `src/graph.h`'s `ambOut` declaration and the
amb-clue comment both say so explicitly. That pin is invisible in every disclosed gauge. The
invisible population is the subject.

**The population, defined for the census.** A *locality-pinned site* is a resolved call reference
where (a) the site is not SCIP- or binding-pinned, (b) the tier entering S6-C held ≥2 candidates, and
(c) after S6-C exactly one non-self survivor remains. Strata reported beside it, same run, same
oracle: (i) *other silent pins* — qualified `A::b`, `this->`, Rule-3 file narrowing, cone/arity
collapse to one — also uncounted in `amb=` but each carrying receiver or qualifier evidence the
locality prior lacks (the expected upper reference); (ii) *residual splits* — today's `amb=`
population, the 2026-07-11 census's "amb-flagged" group (the expected lower reference,
≈ 1/mean-split-width). Scale scoping from recon, explicitly UNPINNED and re-derived by the census
before use: on duckdb roughly ~48k name-collision call sites collapse to ~8.9k residual `ambiguous=`
— the gap is mostly this population plus the other silent pins, in unknown proportion.

**Units, registered so the known error cannot recur.** `ambiguous=` counts call SITES (`ambOut` is
incremented at most once per reference). `edges=` counts unique deduplicated `(from,to)` PAIRS
(`outTargets`). One ambiguous site can emit several 1/k-split edges; k repeated calls to one callee
are k sites but one edge. They are never divided into a "share of edges": `src/lanes.h:737` made
exactly that error ("X of Y call edges are name-ambiguous") and is fixed at `73b057f`
(`fix/codex-punchlist`; not yet an ancestor of this worktree's head). The two historical
"`ambiguous/edges = 39.x%`" convenience lines earlier in this file mix the same units and stand as
history — read them as a gauge, never a proportion. The census reports each population as a count in
its own unit, full stop.

**What the existing oracle can and cannot see — the instrumentation verdict, established by reading
`bench/scip_amb_precision.py`.** The prior census (pre-cutover history-of-record: ctxpack
`bench/ANSWERQUALITY.md`, appended 2026-07-11) measured amb-flagged precision **0.378** (loguru,
300 buckets / 794 edges) and **0.841** (rq, 520 / 622) against a non-ambiguous control of **1.000**
over 2,077 edges. Its grouping key is whether the callee NAME has >1 in-corpus definition — and a
locality-pinned site lands in that "amb" group with emitted=1, where the harness scores it **1.0 BY
CONSTRUCTION**: the serialized edge is `<c n="X"/>` with no target identity, the `--scip` overlay's
replacement edge carries the same name, so `min(pinned=1, emitted=1)/1 = 1` whether the pin chose
SCIP's target or a wrong same-name definition. So the answer to the registered question is the
stronger one: the harness does not merely lump tie-break pins in with confidently-resolved edges in a
way a regrouping could fix — it is structurally BLIND to a wrong pin, because edge serialization is
name-keyed. **Phase 2 therefore needs new instrumentation, not a new grouping.** Minimal registered
form: an eval-only, flag-gated census emission at the resolver — per call site: caller id, callee
name, surviving target canonical id(s), and decision mechanism ∈ {qualified, receiver-rule, cone,
arity, locality, split} — joined against SCIP's per-site target by symbol identity, not by name. The
overlay join point (`src/scipoverlay.h`'s `(fromSymbol, calleeName)` → pinned-target side table)
already holds both sides in memory during a `--scip` run, so agreement is computable exactly where
replacement happens today. The census surface must be output-invariant for every existing argv (G5
additive; `argvdiffcheck`-clean) and pass determinism ×3 before its first number is read.

**Arms and corpora.** *Python arm — runnable today*: `scip-python` 0.6.6 is installed
(`/opt/homebrew/bin/scip-python`). Corpora: loguru and rq exactly as in the 2026-07-11 census, for
comparability; at most one larger Python repo may be added ONLY if its SHA is pinned in the census
commit before any run. *C++ arm — CONDITIONAL on `scip-clang`, which is NOT installed at
registration* (`scip-clang` and `scip` both absent from PATH, checked 2026-08-31). The untracked
`compile_commands.json` at the main checkout root (48 entries) was re-checked at registration: it
carries compile commands for all five own translation units — `main.cpp` and `tsprobe.cpp` once,
`ingest.cpp` / `pagerank.cpp` / `infra/diagnostics.cpp` twice across the `ripwire` and
`ripwire_probe` targets — with only the optional `RIPWIRE_ALLOC_COUNT` TU (`alloccount.cpp`) absent,
which is correct (it is deliberately out of the shipped target). (The recon brief said 4 of 5; the
re-check says all five are present, and the re-check wins.) **If `scip-clang` is never installed, the
round completes as a PYTHON-ONLY census and is published as exactly that**: a narrower result whose
C++ generalization is UNKNOWN and says so in the same table — the duckdb scoping figures then stay
scoping context, never results. That degradation is registered here, up front, not discovered in the
writeup.

**Baseline, re-derived on this worktree's own head** (`3ce9944`, plain build,
`./build/ripwire src --no-cache`):

```
files=144 symbols=4610 edges=12515 ambiguous=5410 unresolved=1445
```

**Registered bands — fixed before any number.** Primary metric: precision of S6-C locality-pinned
edges where SCIP speaks, per corpus — a pinned edge is *confirmed* iff SCIP's resolved target IS the
pinned definition, by symbol identity.

* **Silence justified (current behaviour stands):** precision ≥ **0.90** on every measured corpus
  with ≥ 100 SCIP-covered pinned sites. The pin's exclusion from `amb=` is then earned, and this
  becomes the citable justification for it.
* **Silence unjustified (funds the disclosure fix):** precision < **0.80** on any corpus with ≥ 100
  covered pinned sites — the tie-break is manufacturing silent wrong edges at a rate the honesty
  contract cannot carry.
* **Inconclusive:** 0.80–0.90, or < 100 covered pinned sites on every corpus. Published as
  inconclusive; the only funded follow-up is corpus growth, never a fix reached for through the band.

Reference strata are published beside the primary in the same table: other-silent-pin precision and
residual-split per-target precision (the continuation of 0.378 / 0.841).

**The trap, encoded: "reduce `ambiguous=`" is NOT a criterion, and any later fix is judged
non-inferior instead.** That criterion is twice-rejected in this file — #2a (type-mention lane,
2026-08-20: NOT MET and "unmeetable at the registered site") and #3b (depth-2 lane, 2026-08-21:
REJECT, with the postmortem showing the `ambiguous=` rise was recovered and corrected information).
Replacing a wrongly-pinned edge with an honest split RAISES `ambiguous=`; a round judged on lowering
it is judged backwards. So for whatever fix this census funds (phase 3, separately registered):
header `ambiguous=` MAY RISE, ceiling **+2.0%** against the same-commit baseline, with the primary
being the precision statement above — never the direction of `ambiguous=`.

**What a negative looks like — and every one of them is publishable in §7.** (a) Precision ≥ 0.90:
the lane's premise ("the silent pin hides wrong edges") is REFUTED; no fix is funded; the result is
recorded as a registered negative for the lane and a positive for current behaviour. (b) Coverage
failure: SCIP speaks on too few pinned sites to decide; recorded as inconclusive, with the coverage
number, not quietly widened until it decides. (c) The Python-only degradation above. The falsifiable
claim is: *"S6-C's silent commitments are at least as trustworthy (≥ 0.90 where SCIP speaks) as the
census's confident control."* Either verdict is a result; a registration that cannot fail is not a
registration.

**Design latitude, registered but deliberately NOT chosen here.** The owner has pre-authorized
changing the data structure: *"if need/want a different data structure, or if a different data
structure is more optimal for these use cases it is totally fine to do that."* G2 still binds —
DOD/POD/SoA, 32-bit handles, cache locality, no generic graph library. The two candidate shapes for
the eventual honest-disclosure fix, ordered by size: (i) a third parallel per-symbol counter beside
`ambOut` / `unresolvedOut` (one more `std::vector<std::uint32_t>`, no `Symbol` change) — gives the
population size and a header gauge, but cannot feed the oracle join by itself; (ii) retained
candidate SETS for decided call sites — a sparse CSR-style side table keyed by CALL SITE, not by
edge, holding the pre-pin tier for pinned sites — the larger option, enabling both the census join
and a future "show the pin's alternatives" surface. Choosing between them is phase 2's measurement
call. Any change that moves `sizeof(Symbol)` obliges `cmake --build build --clean-first -j` on every
live build tree before any number is trusted (the CLAUDE.md mixed-binary trap).

**Explicitly out of this phase.** No census run, no precision number, no resolver change, no output
change, no counter, no side table. This section is the registration and the read-only recon behind
it; the first number appears below it, dated, whichever way it goes.

### The census, RUN — S6-C silent-pin precision, 2026-08-31 (the number the section above registered)

**Verdict against the frozen bands: INCONCLUSIVE by coverage.** Locality-pinned precision is
**0.729 (n = 85)** on astropy-14365 and **0.738 (n = 84)** on astropy-12907. Both point estimates sit
inside the registered "silence unjustified" region (< 0.80); neither corpus reaches the registered
**n ≥ 100** floor. The registration says exactly what happens then — *"Published as inconclusive; the
only funded follow-up is corpus growth, never a fix reached for through the band"* — so **no fix is
funded by this result**, and no band was widened, narrowed or restated to reach a decision. What the
census does establish is the instrument, the population's true size, and a mechanically demonstrated
root cause, all of which make a follow-on census cheap.

**The two corpora are NOT independent, and pooling them is refused.** They are the same project 1,458
issue-numbers apart, and **154 of the 157 distinct locality-pinned (caller, callee) pairs — 98% — are
literally the same code in both**. Pooling would give n = 169 at 0.733 and would clear the registered
floor, which is precisely why it is not done: that number would be one measurement counted twice
wearing the costume of replication. astropy-12907 is reported as a STABILITY CHECK on the point
estimate (0.729 → 0.738, every stratum within 0.01), not as a second corpus.

**Deviation from the registered corpora, stated up front because it constrains everything below.** The
registration named loguru and rq, for comparability with the 2026-07-11 census. Neither is in this
tree and the round ran under a no-clone constraint, so neither could be indexed. The corpora are
instead checkouts already present at `bench/external/swex/snapshots/`: **`astropy__astropy-14365`**
(942 `.py`; ripwire indexes 1149 files / 26,405 symbols) and **`astropy__astropy-12907`** (910 `.py`).
astropy was chosen because it is the only genuine, large Python *library* in that directory — the six
`astral-sh__ruff-*` snapshots are larger but their Python is a Rust project's lint FIXTURES
(deliberately pathological code), and `scip-python` in fact **crashed fatally** on
`astral-sh__ruff-15626` (`Debug Failure. False expression.` on
`resources/test/fixtures/flake8_simplify/SIM117.py`, exit 1 after a partial 29 MB index), so that arm
is recorded UNRUNNABLE rather than quietly dropped. Comparability with 0.378 (loguru) / 0.841 (rq) is
therefore **lost**, and nothing below should be read against those two.

**C++ arm: UNKNOWN, exactly as the registration provided for.** `scip-clang` is still not installed
and was not installed for this round. This is a PYTHON-ONLY census; its C++ generalization is unknown
and the duckdb scoping figures in the registration remain scoping context, never results.

**The instrument (`--pin-census=FILE`, `src/pincensus.h`, gate `test/pincensuscheck.sh`).** Building it
confirmed the registration's diagnosis rather than merely inheriting it: a call edge serializes as
`<c n="NAME"/>`, so the identity a precision join needs is simply absent from the output and no
regrouping of `bench/scip_amb_precision.py` could recover it. The census is an eval-only side file
emitting, per DECIDED call site, the caller's canonical id, the callee name, the mechanism that
resolved it (`unique|qualified|receiver-rule|cone|arity|locality|split|scip|binding`), a flag string
naming *every* narrowing stage that fired (so a tie-break that narrowed 3→2 and still split stays
visible), and the canonical id of every surviving target. Under `--scip` it also transcribes the
overlay's own covered sites, so both sides of the join live in one file and no protobuf reader is
needed downstream. Shape: SoA parallel vectors, 32-bit handles, one flat name pool, CSR-style target
ranges, `Symbol` untouched (G2; the registration's option (ii) in its smaller, census-only form).
`stdout` is byte-identical with and without the flag — verified on the fixture by gate arm (E) and
again on the 1149-file corpus — and three armed runs are byte-identical. The join harness is
`bench/scip_pin_precision.py`.

**One instrument defect, found and fixed before any number was read, because it would have reproduced
the very blindness being measured.** `canonicalIdForEmit` degrades an UNSCOPED symbol to its BARE
NAME, so the census's first draft printed two sibling free functions named `handler` identically —
name-keyed again. Gate arm (G), run against `test/scipfix`, caught it. The census identity is
therefore `path::scope::name#NODEID` (`path::name#NODEID` when unscoped) — never a bare name — and arm
(I) asserts the load-bearing assumption that the handle is stable between the plain and `--scip` runs
rather than assuming it.

**The population is far smaller than the recon implied — the first substantive finding.** On
astropy-14365 the resolver decided **46,785** call sites. Of those, **224 (0.48%)** are
locality-pinned in the registered sense (tier ≥ 2 entering S6-C, exactly one non-self survivor after,
not SCIP- or binding-pinned); a further 20 had S6-C fire and still split, so the tie-break touches 244
sites in all. The recon's duckdb framing — ~48k name-collision sites collapsing to ~8.9k residual
`ambiguous=`, "the gap is mostly this population plus the other silent pins" — is **not** what this
corpus shows: the gap is dominated by the receiver rules (5,409 sites) and by names that were never
ambiguous at all (37,984), with locality a half-percent sliver. Whatever the pin's precision proves to
be, its blast radius here is 0.5% of decided edges.

**Results. Every figure carries its own n; SCIP silence is not disconfirmation, so precision is
reported only where SCIP speaks.**

| mechanism | astropy-14365 sites | covered | precision | astropy-12907 sites | covered | precision |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **locality (S6-C — the registered primary)** | **224** | **85** | **0.729** | **224** | **84** | **0.738** |
| receiver-rule (Rule 1/2/2b/3) | 5,409 | 4,580 | 0.984 | 5,328 | 4,466 | 0.983 |
| cone (CHA-lite) | 254 | 253 | 1.000 | 248 | 248 | 1.000 |
| arity | 183 | 42 | 0.238 | 197 | 41 | 0.244 |
| split (today's `amb=` population, per-TARGET) | 2,731 | 677 | 0.146 | 3,092 | 681 | 0.147 |
| unique (control) | 37,984 | 19,983 | 0.969 | 46,607 | 19,606 | 0.969 |

The control matters: `unique` is 0.969, not 1.000, so roughly 3pp of every figure here is
ripwire/SCIP disagreement rather than ripwire error. Locality at 0.729 sits 24pp below that floor.

**Secondary decomposition — reported beside the primary, never in place of it, and it moves no band.**
A `mech` label names the stage that chose *inside the tier*; if SCIP's answer was never in the tier at
all (it lives in another file, and tiers 1/2 are same-file / same-dir) the miss belongs to the tier
ladder, not to that stage. Restricting to covered sites where SCIP's target is in the caller's OWN
file (astropy-14365):

| mechanism | covered | of those, in-file | precision (all) | precision (in-file) |
| --- | ---: | ---: | ---: | ---: |
| locality | 85 | 76 | 0.729 | **0.763** |
| receiver-rule | 4,580 | 2,399 | 0.984 | 0.992 |
| cone | 253 | 232 | 1.000 | 1.000 |
| arity | 42 | 9 | 0.238 | 1.000 |
| unique | 19,983 | 4,423 | 0.969 | 1.000 |

This reads cleanly, and it reverses one alarming-looking number: `arity`'s 0.238 is **not** the arity
filter — all 32 of its disconfirmations are cross-file, i.e. the true target was never in the tier at
all, and in-file it is 1.000 (n=9). Every other mechanism is 1.000 or 0.992 in-file. Locality alone is
**0.763 in-file**: even when the correct definition was sitting in the caller's own file, available to
the tie-break, S6-C picked a different one about a quarter of the time.

**Root cause, demonstrated rather than inferred.** The 23 disconfirmed locality pins split into three
shapes: **10** where SCIP resolves to a MODULE-LEVEL function and ripwire pinned a same-file CLASS
METHOD, **10** where both are methods of sibling classes in one file, **3** cross-file. The first shape
has a mechanical explanation. `resolve.h::canonicalId` returns the BARE NAME for a symbol with no
enclosing scope, so a module-level function's canonical id carries no path segment at all — and
`sharedLocality`, which counts only whole-segment prefixes, therefore scores it **zero against every
caller in the repo**. A module-level function can never win the locality tie-break, and any same-file
class method beats it by default. Five lines reproduce it with no oracle involved:

```python
def compute( x ): return x + 1                       # mod.py::compute  ->  canonId is just "compute"
class Helper:
    def compute( self, x ): return x - 1             # mod.py::Helper::compute
class Caller:
    def go( self, x ): return compute( x )           # a module-level call
```

```
C  locality  2  1  l  mod.py::Caller::go#4  compute  mod.py::Helper::compute#2
... and the map for that corpus reports ambiguous=0.
```

The call is pinned to an unrelated class's method, one confident edge is emitted, and the disclosed
ambiguity gauge says nothing. Real instances in astropy include
`io/fits/column.py::_ColumnFormat::from_recformat` → `Column::_convert_format` (SCIP: module-level
`_convert_format`) and three fitters in `modeling/fitting.py` pinned to
`JointFitter::model_to_fit_params` where SCIP says the module-level function. Note this is the SAME
degrade that bit the census writer above, in a second place; if a phase 3 is ever funded, the first
question is whether the fix belongs in `canonicalId`'s unscoped spelling rather than in S6-C.

**Coverage is the binding constraint, and it is OUR ceiling, not SCIP's.** Only 85 of 224 pinned sites
(38%) are covered. The `--scip` run's own honesty note explains why: `SCIP matched 47% of occurrences
(85889/183188), 47235 defs unmatched`. The index was generated from this exact checkout, so "older
commit" is not the explanation — the loss is in ripwire's own SCIP ingestion. Raising that match rate
is the cheapest route to n ≥ 100 on a corpus already in the tree, and it is an instrument-side change
that must land BEFORE, not during, the next census.

**What could not be established.** (a) The registered primary at its registered floor — n = 85 of a
required 100. (b) Any C++ statement: `scip-clang` absent. (c) Comparability with the 0.378 / 0.841
census: its corpora are not in this tree. (d) A second INDEPENDENT corpus: only one Python project in
the tree proved measurable. (e) Whether the 10 sibling-class disconfirmations are wrong edges or SCIP
mis-resolutions — they were read, not adjudicated.

**Standing rules this result does NOT touch.** No fix is funded. If a later phase is funded on a
larger census, it is judged by the precision statement, never by the direction of `ambiguous=`, which
MAY RISE to a ceiling of +2.0% against the same-commit baseline — the twice-rejected criterion stays
rejected. Baseline for this worktree's head, re-derived: `ripwire src --no-cache` gives
`files=145 symbols=4624 edges=12550 ambiguous=5434 unresolved=1445`; the +1 file / +14 symbols / +24
`ambiguous` against the registration's `3ce9944` figure is this round's own `src/pincensus.h` and its
call sites, and excluding that one header reproduces the registered
`files=144 symbols=4610 edges=12515 unresolved=1445` exactly.

### Phase 3 — the SCIP join diagnosed, and the census re-registered on the full oracle, PRE-REGISTERED 2026-09-03 (before any post-fix number)

**What this registers.** The phase-2 result above stopped at n = 85 because SCIP "spoke" on only 85 of
224 locality-pinned sites, and named the `--scip` join's `SCIP matched 47% of occurrences
(85889/183188)` line as the binding constraint. This section is the diagnosis of that line — measured
per failure class, not guessed — and the registration of what phase 3 changes, with every band fixed
before the post-fix number is read. Instrument: `bench/scip_match_diag.py` (stdlib-only; reproduces
both joins `src/scip.h::buildScipOverlay` performs from the census side files and classifies every
rejection), over `--pin-census` **format v2**, which now carries the call-site line on every `C` row and
one `S` row per symbol (`test/pincensuscheck.sh` arms (J)/(K), red first). Corpora: the same two
astropy snapshots, copied to the session scratchpad and re-indexed there with `scip-python` 0.6.6
(`scip-python index --project-name astropy --project-version 14365 --quiet --output astropy-14365.scip .`,
same for 12907; 47.5 MB / 45.6 MB). Re-running `bench/scip_pin_precision.py` on the fresh indexes
reproduces phase 2 exactly — **0.729 (n = 85)** and **0.738 (n = 84)** — so the instrument is stable
across an index rebuild and the diagnosis below is of the same population.

**Diagnosis, astropy-14365 (`python3 bench/scip_match_diag.py --bin ./build/ripwire --repo
<astropy-14365> --scip astropy-14365.scip`; 12907 in parentheses where it differs).**

*The 47% is a ratio of two polluted counts, not a match rate.* Of the 183,043 occurrences the overlay
counts as INTERNAL (their SCIP symbol bound to a ripwire definition), **119,154 — 65.1% — are
references that cannot be calls by construction**: 63,989 parameter uses, 48,705 `local N` uses,
6,460 attribute/term reads. They enter the denominator through two defects in the def-side join,
which binds a SCIP definition occurrence to whatever ripwire symbol is FIRST on that exact line:

* **`local N` symbols are keyed globally.** SCIP scopes `local N` to its document; `scipDef` is one
  `HashMap<string,NodeId>` over the whole index, so the 39 `local N` definitions that happen to share a
  line with a real symbol (a module-level assignment) bind that symbol for every same-numbered local in
  every other file — 48,705 references, 27% of the "internal" denominator, and every one of them that
  lands on a line with any ripwire reference is a **phantom precise edge** to an unrelated file's
  symbol (from ≠ to, so it also inflates the numerator).
* **Parameter definitions bind to the enclosing function.** A parameter's definition occurrence sits on
  the `def` line, which holds the function's own symbol, so `f().(x)` binds to `f` (25,248 of 28,104
  parameter defs, 89.8%; 95.5% on 12907). Every use of `x` inside `f` is then an "internal" occurrence
  whose target is `f` itself — dropped as a self-loop AFTER entering the denominator. The same
  first-on-the-line rule mis-binds same-line terms (`major, minor = …` → `bugfix`).

*The method and class definitions all bind.* `method` 16,077 / 16,077 (100%), `type` 2,139 / 2,139
(100%), zero near-misses within ±5 lines on either corpus: decorators and multi-line signatures — the
phase-1 guess in `bench/ANSWERQUALITY.md` — are **not** a failure class at all. `term` (class and
module attributes) binds 32%; the 4,710 unbound are attributes ripwire indexes no symbol for
(`Conf#unicode_output`, `Table#read`), an extraction fact, not a join fact.

*The honest match rate.* Restricting to what the census can possibly cover — a method/type reference,
call-shaped (`name(` on the line), inside a body, target bound — **27,189 of 33,523 call occurrences
match a decided call site: 81.1% (81.3% on 12907).** The 6,258 that do not are `iers_conf.reset(…)`,
`item.reload()`, `super().__enter__()` — receiver calls whose name has many in-repo definitions and no
same-file/same-dir candidate, which the tier ladder DROPS (no row: the census's documented floor).
That is the resolver's recall, not the join's; 67 sites (0.2%) are genuine line skew (a multi-line
call whose name token and call node sit on different lines). The remaining rejections are outside any
call site: 25,179 mentions (imports, annotations, `isinstance` arguments, inheritance lists) and 5,187
module-level calls with no enclosing symbol (absent from the census by definition).

*Where the locality coverage actually goes — the finding that changes the census.* Of the 139 uncovered
locality-pinned sites on 14365 (140 on 12907): **57 (58) SCIP silent** — no occurrence names the callee
inside the caller; **2 (3) line skew**; and **80 (79) where SCIP DID resolve the occurrence, to
something that is not any ripwire definition**: 50 (49) to an external package (`sum` → `builtins/sum()`,
`append` → `builtins/list#append()`, `array` → `numpy._core.multiarray/array()`), 18 (18) to an
in-package attribute ripwire has no symbol for (`self.model(3, 5)` → `TestInputUnits#model.`), 12 (12) to
a parameter (`m = model(*params)` → `test_input1D().(model)`). Each was read at source: the tie-break
pinned a bare `sum(` in `BaseRepresentation.norm` to `BaseRepresentation.sum`, `values.append(vc)` in
`Card._split` to `Header.append` in another file, a parameter call to `TestJointFitter.model`. Under the
registration's own rule — *"a pinned edge is confirmed iff SCIP's resolved target IS the pinned
definition, by symbol identity"* — these are disconfirmations. The phase-2 instrument could not
transcribe them because the overlay's job is edge REPLACEMENT and it only records targets it can point
an edge at; a resolution to a non-definition was indistinguishable from silence. That is an instrument
gap, not a band question, and it is closed below.

**Registered before the fix, in this order.**

1. **The matcher defects are fixed and the shipped overlay changes with them** — a bug fix, disclosed:
   `local N` symbols never bind and are never internal; a definition occurrence binds only when its
   descriptor is a method (`().`), type (`#`) or term (`.`) AND a ripwire symbol of the SAME NAME sits on
   that line (parameters, locals and `__init__:` meta never bind; a same-line different-named symbol
   never binds). Baseline to compare against, same binary, `ripwire <corpus> --no-cache --scip=<index>`:
   14365 `edges=35939 ambiguous=2054 precise=20355`, stderr `47% (85889/183188), 47235 defs unmatched`;
   12907 `edges=40193 ambiguous=2411 precise=19808`, `48% (90106/188992), 44362 defs unmatched`. The
   post-fix figures are published beside these whichever way they move. `test/scipcheck.sh` stays green
   unchanged (its fixture has neither locals nor parameters in the index).
2. **Target for the honesty line.** With the two polluting classes gone, the line's ratio is expected to
   report the CALL-occurrence rate the diagnosis measured. Registered band: the diag's
   `CALL-OCCURRENCE MATCH RATE` is **non-inferior** after the fix (≥ 81.0% on both corpora — the fixes
   remove pollution and must lose no genuine match), and the stderr `matched N%` figure lands within
   **±5 points of that rate** on both corpora. A widening of the gap means the line still counts
   something the census cannot cover, and is reported as such.
3. **The oracle is transcribed in full — `--pin-census` O rows for every SCIP-resolved call site.** Under
   `--scip`, a reference occurrence that ripwire holds a same-named Call reference for on that line, but
   whose SCIP target is not a ripwire definition, is written as an `O` row whose target is a sentinel:
   `@external` (the symbol has no definition occurrence in the index — another package) or `@nondef`
   (it is defined in the index but bound no symbol: a parameter, a `local`, an attribute ripwire does not
   extract). The harness counts a sentinel-covered site as COVERED and its in-repo pin as DISCONFIRMED,
   in a column of its own. **The primary is re-read on this full definition — it is the registered
   definition — and the phase-2 in-repo-only figure is reported beside it for continuity**, never in
   its place. Coverage expectation registered as a floor, not a result: locality covered ≥ **160 / 224**
   on 14365 (85 + 80 sentinel − skew), which reaches the registered **n ≥ 100 on ONE corpus without
   pooling**. If it does not, the section says so and stops.
4. **The funded-fix decision is then taken mechanically from the bands already on record**: precision
   < 0.80 at n ≥ 100 on a corpus funds the `canonicalId` fix; 0.80–0.90 or n < 100 does not; ≥ 0.90
   refutes the premise. No band moves. If funded, the non-inferiority ceiling (`ambiguous=` +2.0%) and
   a locality-precision floor are registered in a further section BEFORE that fix's first number.

**Gate.** `test/scipjoincheck.sh` on the new fixture `test/scipjoinfix/` (two files, a hand-rolled
index from `make_index.py` — the `scipfix` generator's protobuf helpers): the `local 0` cross-file
collision (no phantom O row), the parameter-on-`def`-line collision (no self-bound target; an `@nondef`
O row instead), an external resolution (`@external` O row), the unchanged in-repo O row, the harness's
two-definition readout, and stdout byte-identity / determinism / xmllint under `--scip`. Written and run
RED against the pre-fix binary before `src/scip.h` changed.

### Phase 3, RUN — the join fixed, the oracle transcribed in full, and the number (2026-09-03)

**Verdict against the bands registered above: the fix is FUNDED.** On the full oracle — the registered
definition — locality-pinned precision is **0.368 (n = 163)** on astropy-14365 and **0.373 (n = 161)**
on astropy-12907. Both clear the **n ≥ 100** floor on a single corpus with no pooling, and both sit
far inside the "silence unjustified" region (< 0.80). Under the phase-2 in-repo-only definition,
reported for continuity, the figures are **0.723 (n = 83)** and **0.732 (n = 82)**: within two sites of
phase 2's 0.729 / 0.738 (the two sites that moved are parameter calls the old binding had self-bound
into "in-repo" coverage; they are now `@nondef`). Argv, both corpora, same binary:

```
python3 bench/scip_pin_precision.py --bin ./build/ripwire --repo <astropy-14365> --scip astropy-14365.scip --label astropy-14365-fix
python3 bench/scip_pin_precision.py --bin ./build/ripwire --repo <astropy-12907> --scip astropy-12907.scip --label astropy-12907-fix
```

| mechanism | 14365 sites | covered (full) | precision (full) | n in-repo | p in-repo | @external | @nondef | 12907 covered | precision | n in-repo | p in-repo |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **locality (S6-C, the primary)** | **224** | **163** | **0.368** | 83 | 0.723 | 50 | 30 | **161** | **0.373** | 82 | 0.732 |
| receiver-rule | 5,409 | 4,847 | 0.930 | 4,580 | 0.984 | 257 | 10 | 4,766 | 0.921 | 4,466 | 0.983 |
| cone | 254 | 253 | 1.000 | 253 | 1.000 | 0 | 0 | 248 | 1.000 | 248 | 1.000 |
| arity | 183 | 112 | 0.089 | 42 | 0.238 | 33 | 37 | 109 | 0.092 | 41 | 0.244 |
| split (per-target) | 2,731 | 1,128 | 0.105 | 677 | 0.146 | 225 | 226 | 1,168 | 0.101 | 681 | 0.147 |
| unique (control) | 37,984 | 24,216 | 0.799 | 19,955 | 0.969 | 3,765 | 496 | 23,392 | 0.811 | 19,574 | 0.969 |

Read the control first: `unique` drops from 0.969 to **0.799** on the full oracle. That 17-point gap is
the name-based resolver's plausibly-internal false-positive rate on this corpus — calls to `sum`,
`append`, `set`, `dict`, `array` that Pyright resolves to a builtin or numpy while ripwire finds a
same-named in-repo definition and, the name being unique in the tree, emits one confident edge. It
was invisible to every prior census because the oracle could not say "not here". Locality at 0.368 sits
43 points below that control; its 103 disconfirmations decompose as **50 external + 30 non-def + 23
in-repo** (the 23 are phase 2's 10 module-level / 10 sibling-class / 3 cross-file, unchanged).

**Band 1 — the matcher defects, disclosed.** After the fix the shipped overlay on 14365 reports
`edges=35905 ambiguous=2054 precise=20302` (was 35939 / 2054 / 20355): **53 phantom precise edges gone**,
every one a cross-file `local N` collision; on 12907 `edges=40169 ambiguous=2411 precise=19763` (was
40193 / 2411 / 19808), 45 gone. `ambiguous=` is byte-identical on both. `test/scipcheck.sh` green
unchanged; `test/scipjoincheck.sh` (red-first on the pre-fix binary: arms C/D/E/F/G) green.

**Band 2 — the honesty line: half met, half MISSED, reported as such.** The diag's CALL-occurrence match
rate is exactly non-inferior — **81.1% → 81.1%** (27,189 / 33,523) and **81.3% → 81.3%** (27,201 /
33,457): the fixes removed pollution and lost no genuine match. The stderr line now reads
`SCIP matched 71% of occurrences (48511/68646)` on 14365 and `72% (47687/66314)` on 12907 — up from
47% / 48%, but **10 points below the diag rate, outside the registered ±5**. The gap is real and named:
the line's denominator still includes bound-term references (attribute reads, 6,460 on 14365) and its
numerator counts a mention line as matched whenever ripwire holds any-role reference there, so it
measures "occurrence lands on a ripwire reference", not "call lands on a decided call site". Tightening
it to the call definition would need the line to know a reference's role, which the overlay's
`(file,line)` table deliberately does not carry. Left as a registered miss; the stderr text is unchanged
in shape so no gate or doc moved.

**Band 3 — coverage.** Locality covered **163 / 224** on 14365 (floor 160: met) and 161 / 224 on 12907.
The 61 (63) still uncovered are 59 (60) genuine SCIP silence and 2 (3) line skew.

**What the funded fix can and cannot move — stated before it is registered.** The `canonicalId` fix
(bare-name spelling for an unscoped symbol ⇒ zero shared locality) reaches exactly the module-level
shape: 10 of the 23 in-repo disconfirmations on each corpus. It cannot touch the 80 sentinel
disconfirmations — a tie-break chooses among in-repo candidates, and for those sites every candidate is
wrong — so the full-oracle primary will remain < 0.80 after it, and **the disclosure question the
registration funds ("the pin's exclusion from `amb=` is unearned") stands regardless of the
`canonicalId` outcome**. Its floor is therefore registered on the stratum it addresses, with the full
figure held non-inferior, in the next section.

### Phase 3b — the `canonicalId` locality fix, PRE-REGISTERED 2026-09-03 (before its first number)

**What changes.** `resolve.h::canonicalId` spells an unscoped symbol as its BARE NAME, and
`sharedLocality` counts whole matching segments, so a module-level function scores zero locality
against every caller and can never survive the S6-C tie-break against a same-file class method. The
fix gives the tie-break its own spelling: a per-symbol `Graph::localityKey` — `path::scope::name`, and
`path::name` when unscoped — read ONLY by the S6-C block. `g.canonId`, `canonicalId`, `canonicalIdForEmit`
and therefore the emitted `id=` (absent for an unscoped symbol), the note keys, the quality baseline
keys and every selector are untouched **by construction**: no legend moves, no `id=` appears that did
not before. The population the tie-break fires on is unchanged (a SCOPED caller, tier > 1, not a
depth-2 chained receiver, not SCIP/binding-pinned); only how candidates are scored changes. Expected
mechanics on the registered repro (`mod.py::Caller::go` → `compute` with candidates `Helper::compute`
and module-level `compute`): both now share exactly `mod.py::` → a full tie → the tier stays intact →
the call is an honest split and `ambiguous=` counts it, where today `Helper::compute` is silently pinned.
Cross-file: `dir/a.py::X::f` vs `dir/b.py::f` for a caller in `dir/c.py` both share `dir/` → tie →
split, where today `X::f` wins by `dir/` against zero. So the change converts silent pins to splits; it
can also let a same-file module-level function WIN when the class candidate is in another file.

**Cache.** `src/ingest_cache.h` persists raw facts (symbols, references); resolution runs in
`buildGraph` on every invocation, so the change reaches a warm run without a `kParserVer` bump. The
cold == warm determinism check below is the proof, not the reasoning.

**Registered bands, fixed before the build.** Same-commit baselines, `ripwire <root> --no-cache`, plain
build at `be3e1e6` (this lane's phase-3 commit; the D4 trees at `rw-lane-ab2-corpora/`, each verified
at its pin with a clean status):

| corpus | pin | files | symbols | edges | `ambiguous=` | unresolved | +2.0% ceiling |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ripwire `src/` | be3e1e6 | 146 | 4,729 | 12,835 | **5,553** | 1,480 | 5,664 |
| ugrep | `550599a6` | 156 | 3,626 | 5,381 | **1,721** | 5 | 1,755 |
| rocksdb | `0e2801ac` | 1,873 | 53,619 | 210,332 | **44,967** | 1,800 | 45,866 |
| duckdb | `19864453` | 5,123 | 61,178 | 84,701 | **8,934** | 2,650 | 9,112 |

1. **Non-inferiority on the whole-graph `ambiguous=`: ceiling +2.0%** against the figure above on each
   of the four corpora. It MAY RISE — a silent wrong pin becoming a disclosed split is the intended
   direction — and "reduce `ambiguous=`" remains the twice-rejected non-criterion. A rise above +2.0% on
   any corpus is a REJECT of this shape (the fix is reverted; the number ships as a registered negative,
   the `--slice-guards` precedent).
2. **Locality precision floor on the stratum the fix addresses: in-repo-only locality precision ≥ 0.85
   on astropy-14365** (0.723, n = 83 today; the 10 module-level disconfirmations are the reachable
   set). 12907 reported as the stability check. Sites that leave the `locality` population must
   reappear under `split` — the harness's mechanism counts are printed before and after and the leavers
   are reconciled by count (locality lost == split gained, ± sites whose tier also changed width).
3. **Full-oracle locality precision must not drop** below 0.368 / 0.373 (non-inferior), and every
   sentinel disconfirmation is expected to persist: this fix does not claim them, and the disclosure
   question stands after it whatever band 2 says.
4. **The golden** (`test/golden.xml`, the default map on `test/fixture`) is re-derived in its OWN commit
   with the reasoning, if and only if the fixture holds a tie the change moves; determinism ×2, cold ==
   warm, `xmllint --noout` on the fixture and on astropy-14365; ASan clean on the census path.

### Phase 3b, RUN — the `canonicalId` locality fix is a registered NEGATIVE, measured 2026-09-03 against the bands above

**Verdict: NEGATIVE, by the bands the section above fixed before the build.** Band 2 — in-repo-only
locality precision ≥ 0.85 on astropy-14365 — measured **0.831 (n = 71)**, 1.9 points under the floor
(0.831 on 12907 as well). Bands 1 and 3 were both MET, and that matters to the reading: this is not "it
raised `ambiguous=`" or "it made the pin worse", it is "it did not buy enough of the stratum it was
registered to buy". **The change does not ship.** It was a 14-line diff (a `Graph::localityKey`
vector beside `canonId`, populated in the same loop, read at the two S6-C `sharedLocality` sites);
it is reverted whole in the same commit that carries this section, `src/graph.h` byte-identical to
`be3e1e6`, and the patch is kept verbatim in the lane report. Every number below came out of that binary.

| Registered criterion | Band | 14365 | 12907 | |
| --- | --- | --- | --- | --- |
| 1. whole-graph `ambiguous=` vs same-commit baseline | ≤ +2.0% on each of 4 corpora | src 5,553 → **5,555** (+0.04%) · ugrep 1,721 → **1,722** (+0.06%) · rocksdb 44,967 → **45,146** (+0.40%) · duckdb 8,934 → **8,934** (0) | — | **meets** |
| 2. in-repo-only locality precision | ≥ 0.85 on 14365 | **0.831** (59 / 71) — was 0.723 (60 / 83) | 0.831 (59 / 71) — was 0.732 | **fails** |
| 2. leavers reappear as `split` | locality lost == split gained | locality 224 → **115** (−109), split 2,731 → **2,840** (+109) | 224 → 115, 3,092 → 3,201 (+109) | meets |
| 3. full-oracle locality precision | ≥ 0.368 / 0.373 (non-inferior) | **0.670** (59 / 88; 17 `@external`, 0 `@nondef`) | **0.678** (59 / 87; 16 `@external`) | meets |
| 4. golden / determinism / cold==warm / xmllint / ASan | all clean | `test/golden.xml` byte-identical; ×2 identical; cold == warm == warm on 14365; xmllint clean; ASan census path clean (rc 0, 0 reports) | — | meets |

Argv: `ripwire <root> --no-cache` for band 1 (the D4 trees at `rw-lane-ab2-corpora/{ugrep,rocksdb,duckdb}`,
each verified at its pin with a clean status); `python3 bench/scip_pin_precision.py --bin ./build/ripwire
--repo <astropy-N> --scip astropy-N.scip --label astropy-N-lk` for bands 2–3.

**Why it fails, which is a finding and not a defect.** The mechanism did exactly what the registration
said it would: 109 sites on each corpus that S6-C used to pin silently became full ties and honest
splits, `ambiguous=` rose by the size of that population and no more, and the 30 `@nondef`
disconfirmations (parameter and attribute calls the pin had sent to some in-repo `model`) all left the
population. What remains in the locality stratum after the fix is the population a LOCALITY prior
cannot decide: of the 29 disconfirmed pins on 14365, **17 are external** (`sum(`, `dtype(`,
`append(` — every in-repo candidate is wrong, and a tie-break chooses among candidates), **10 are
same-file sibling-class methods** (`UnitSphericalDifferential.to_cartesian` bare-calls
`represent_as`, SCIP names `SphericalRepresentation.represent_as` — a receiver-TYPE fact the
tie-break has no access to), 1 non-def, 1 cross-file. The module-level shape the fix targeted is gone
from the disconfirmations entirely; it was 10 of 23, and 0.723 → 0.831 is that shape leaving. The floor
was set at the task's suggested ≥ 0.85 without a model of the residue, and the residue is 2 points
wide. Moving a band after seeing a number is the single move a registration exists to forbid, so
0.831 is a NEGATIVE under the rule as written, and the lane says so instead of arguing with it.

**What is established, and stands.** (a) The primary census verdict from phase 3 — full-oracle
locality precision 0.368 / 0.373 at n ≥ 100 without pooling — is unchanged by this section: the
disclosure fix (the S6-C pin's exclusion from `amb=` is unearned) is **funded and still owed**; its
shape is a per-row marker or counter, since counting the 224 pins into `amb=` on astropy would be a
+8% rise against a +2% ceiling. (b) The tie-break fix's effect is now measured, not modelled:
−109 silent pins, +0.04..0.40% `ambiguous=`, 0.723 → 0.831 in-repo, 0.368 → 0.670 full. (c) Its post-fix
population, n = 88, falls under the n ≥ 100 floor — a fix that removes wrong pins shrinks the very
population the census measures, which any re-registration must budget for.

**The exact next step.** Re-register the tie-break change with a floor derived from the residue
model above (the reachable set is the module-level shape; the sibling-method and external residues
belong to the receiver rules and to disclosure respectively) — or better, register it TOGETHER with
the disclosure marker, judged on one band: full-oracle precision of the remaining silent pins plus
`ambiguous=` non-inferiority. Then the receiver-type route for the 10 sibling-method sites
(`RecvKind::NamedVar` with a recorded declared type reaches Rule 2 today; a bare same-file call to a
method of a sibling class does not). The census, the join, the sentinel oracle and the diag stay in
the tree for that round to run against.

### Phase 4 — the S6-C pin DISCLOSED (`lpin=` / `locality_pinned=`) together with the `localityKey` tie-break, PRE-REGISTERED 2026-09-03 (before its first number)

**What phase 3b left owed, and what this section registers.** Phase 3 funded a disclosure fix: the
S6-C locality pin emits a confident edge and contributes nothing to `amb=`, and the full-oracle census
put that pin's precision at 0.368 (n = 163). Phase 3b measured the `localityKey` tie-break (module-level
functions spelled `path::name` for the locality comparison) and registered it NEGATIVE on a floor set
without a residue model: it removed 109 silent pins per corpus, lifted the in-repo figure 0.723 → 0.831
and the full-oracle one 0.368 → 0.670, and missed ≥ 0.85 by 1.9 points. Its RUN section's "exact next
step" is this registration: the tie-break re-registered TOGETHER with the disclosure marker, judged on
ONE band, with the n-floor budgeted. Both changes ship or both revert.

**The marker's spelling — chosen so it discloses WITHOUT inflating `amb=`.** Counting the 224 pins on
astropy into `amb=` would be a +8% rise against the +2.0% non-inferiority ceiling every resolver change
carries, and it would also conflate two different facts (a k-way split nothing decided, and a one-way
pin a prior decided). The marker is therefore its own counter, parallel to `ambOut`:

- `Graph::locPinOut` — per symbol, the number of its outgoing calls whose single confident target was
  chosen by the S6-C locality tie-break ALONE: the tier still held > 1 candidate when it reached S6-C,
  the compaction left exactly ONE non-self survivor, and the site is neither SCIP- nor binding-pinned.
  This is exactly the predicate under which `pincensus.h::classifyPin` labels a C row `locality`, so the
  marker and the census name the SAME population by construction (a gate arm asserts it rather than
  assuming it). A site S6-C narrowed 3 → 2 is a `split`, `amb=` already counts it, and it is NOT an
  `lpin`.
- Row attribute **`lpin="K"`** beside `amb="K"`, XML and `--json` (`"lpin":K`), **absent when K = 0** —
  zero bytes on every row without a pin, the `dropped_positive=` precedent.
- Header counter **`locality_pinned=N`** after `unresolved=`, the sum over all symbols (the whole
  corpus, like `ambiguous=`), XML and JSON, **absent when N = 0**. So a corpus with no locality pin
  emits a byte-identical map: `test/golden.xml` cannot move from the marker (verified before the build:
  `test/fixture` has 5 census rows, all `unique`).
- Legend: two entries in the map's leading comment, `lpin=…` and `hdr:locality_pinned=…`, spelled
  `name=` so `test/legendcoveragecheck.sh`'s definitional predicate credits them.
- `amb=`, `ambiguous=`, `unresolved=`, `id=`, notes and baseline keys: untouched by construction.

**The tie-break change**, re-applied verbatim from phase 3b: `Graph::localityKey` = `path::scope::name`,
`path::name` when unscoped, populated in the `canonId` loop and read at the two S6-C `sharedLocality`
sites only. `canonId`, `canonicalId`, `canonicalIdForEmit` and the emitted `id=` do not change.

**Cache.** Resolution runs in `buildGraph` on every invocation; no `kParserVer` bump. Cold == warm below
is the proof.

**Same-commit baselines**, plain build at `1c6fdf4` (= origin/main, this lane's base), `ripwire <root>
--no-cache`; the D4 trees at `rw-lane-ab2-corpora/{ugrep,rocksdb,duckdb}` each verified at its pin with
a clean `git status`. The tree moved since phase 3b (`src/` 146 → 147 files, `ambiguous=`
5,553 → 5,598), so the ceilings are recomputed here and the phase-3b table is not reused:

| corpus | pin | files | symbols | edges | `ambiguous=` | unresolved | +2.0% ceiling |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ripwire `src/` | 1c6fdf4 | 147 | 4,773 | 13,002 | **5,598** | 1,488 | 5,709 |
| ugrep | `550599a6` | 156 | 3,626 | 5,381 | **1,721** | 5 | 1,755 |
| rocksdb | `0e2801ac` | 1,873 | 53,619 | 210,332 | **44,967** | 1,800 | 45,866 |
| duckdb | `19864453` | 5,123 | 61,178 | 84,701 | **8,934** | 2,650 | 9,112 |

The census at the same commit reproduces phase 3 exactly (`--label astropy-N-r4base`): locality 224
sites, 163 / 161 covered, **0.368 / 0.373** full-oracle, 0.723 / 0.732 in-repo, 50 / 49 `@external`,
30 / 30 `@nondef`; `split` 2,731 / 3,092 sites.

**The ONE band — three conjuncts, all-or-nothing.** A miss on any conjunct is a REGISTERED NEGATIVE:
both changes are reverted in the commit that carries the RUN section and the patch is kept verbatim in
the lane report. No conjunct moves after a number.

1. **`ambiguous=` non-inferiority: ≤ the +2.0% ceiling above on each of the four corpora** (it MAY rise
   — a silent pin becoming an honest split is the intended direction; "reduce `ambiguous=`" stays the
   twice-rejected non-criterion). The marker itself contributes ZERO to this gauge by construction; any
   movement is the tie-break's.
2. **Full-oracle precision of the REMAINING pins ≥ 0.60 on astropy-14365** — the `locality` row of
   `bench/scip_pin_precision.py`, `covered` / `precision` (sentinel rows included, the registered
   definition since phase 3), measured on the post-change binary. Derivation, stated before the number:
   phase 3b's residue model is 17 `@external` + 10 same-file sibling-class + 1 `@nondef` + 1 cross-file
   = 29 disconfirmed of 88, i.e. 0.670 on the previous tree; the floor sits 7 points under that so a
   moved tree cannot decide the verdict by itself, and any figure under 0.60 falsifies the residue model
   — which is the finding this floor exists to catch, not a defect to argue with. The reading behind
   0.60: with `lpin=` on the row, the remaining pin is a DISCLOSED guess; a disclosed guess that is
   right ≥ 3 times in 5 is worth one confident edge more than a 1/k spray over candidates that are ALL
   wrong (the external residue), and below that it is not.
   **n-floor budget, registered before looking:** the primary is 14365 alone if its post-change
   `covered` ≥ 100. Phase 3b measured n = 88 after the fix, so this is expected NOT to hold; in that case
   the primary is the POOLED figure over 14365 + 12907 (Σ confirmed / Σ covered across both `locality`
   rows), which must reach pooled n ≥ 100, with each corpus reported beside it. Dependence disclosed
   with the number: the two snapshots are the same repository ~1,000 commits apart and share most
   sites, so the pooled n is a floor on evidence, not two independent samples — the pooling buys
   stability against per-snapshot drift, not a second population. Pooled n < 100 ⇒ INCONCLUSIVE, which
   is a miss of this conjunct.
3. **The marker is exact and costs nothing where it does not fire:** on the plain astropy-14365 run the
   header `locality_pinned=` equals the number of `C<TAB>locality` rows in that run's `--pin-census`;
   on `test/fixture` the map contains no `lpin=` and no `locality_pinned=` and `test/golden.xml` is
   byte-identical (no golden re-derivation: the fixture holds no locality pin and no tie the change
   moves). Asserted by the gate below on its fixture and repeated on astropy in the RUN section.

**Contract checks, not bands** (each must be clean, none is a criterion of the band): determinism ×2
on the fixture and on astropy-14365; cold == warm == warm on astropy-14365; `xmllint --noout` on the
fixture map and the astropy-14365 map; ASan (`LSAN_OPTIONS=suppressions=lsan_suppressions.txt`) on the
new gate, on `pincensuscheck`, `scipjoincheck`, and on the full `--scip --pin-census` census path over
astropy-14365 (census rows == dev rows); `pincensuscheck`, `scipjoincheck`, `localitycheck`,
`resolverhonestycheck`, `chainguardcheck`, `legendcoveragecheck`, `jsonparitycheck`, `manifestcheck`
green; `docs/COMMANDS.md` NOT regenerated in-lane (the legend string is captured there; the orchestrator
recomputes from the merged tree, and the in-lane `docscommandscheck` result is reported as-is).

**Gate — written and run RED before the code.** `test/lpincheck.sh` on the new fixture `test/lpinfix/`
(three files, ~40 lines): `pinned.py` (the pin: `Alpha.run` bare-calls `helper()`, `Alpha.helper` and
`Beta.helper` in the same file — `lpin="1"` on `Alpha::run`, no `amb=`), `tied.py` (the control:
`Eps.go` → sibling `Gamma.other` / `Delta.other`, `amb="1"`, no `lpin=`), and `modlevel.py` (the
phase-3b repro: `Caller.go` bare-calls `compute()` with `Helper.compute` and a module-level `compute`
in the same file — today a silent pin on `Helper::compute`; after the tie-break a full `modlevel.py::`
tie ⇒ `amb="1"`, no `lpin=`). Arms: (A) the pin row carries `lpin="1"` and no `amb=`; (B) the tied
control carries `amb="1"` and no `lpin=`; (C) the module-level site is a split, `amb="1"`, no `lpin=`;
(D) header `locality_pinned=1` and `ambiguous=2`, and `locality_pinned=` == the census's `C<TAB>locality`
row count; (E) zero bytes when nothing fires — `test/fixture` emits no `lpin=` and no `locality_pinned=`;
(F) the legend defines both names with `name=`; (G) `--json` carries `"lpin":1` on the pin row and
`"locality_pinned":1` in the header; (H) determinism ×2 and `xmllint`. Red on the pre-change binary at
(A), (C), (D), (F), (G) — nothing emits the attribute yet and `Caller::go` is still pinned.

### Phase 4, RUN — the pin disclosed and the tie-break shipped: ACCEPT on the one band, with one registration defect stated (measured 2026-09-03)

**Verdict: ACCEPT.** All three conjuncts of the registered band hold on the post-change binary; the
disclosure marker and the `localityKey` tie-break ship together (commits `e46638a` feature + gate,
`292d5de` golden, this section). One clause of conjunct 3 was written wrong in the registration and is
reported below as a defect of the registration, not re-read to fit the result.

| Conjunct | Registered | Measured | |
| --- | --- | --- | --- |
| 1. `ambiguous=` vs the 1c6fdf4 baselines | ≤ +2.0% on each of 4 corpora | src 5,598 → **5,598** (0; measured on `git archive 1c6fdf4 src`, see below) · ugrep 1,721 → **1,722** (+0.06%) · rocksdb 44,967 → **45,146** (+0.40%) · duckdb 8,934 → **8,934** (0) | **meets** |
| 2. full-oracle precision of the remaining pins | ≥ 0.60; 14365 alone if n ≥ 100, else pooled 14365+12907 at pooled n ≥ 100 | 14365 **0.670** (59 / 88; 17 `@external`, 0 `@nondef`) — n = 88 < 100 as budgeted ⇒ pooled **0.674 (118 / 175)**, n = 175; 12907 0.678 (59 / 87) | **meets** |
| 3. marker exact, zero bytes when silent | `locality_pinned=` == census `locality` rows on 14365; no marker on `test/fixture`; golden byte-identical | 14365 header **`locality_pinned=115`** == **115** `C<TAB>locality` rows (also `src/`: absent == 0 rows); `test/fixture`: no `lpin=`, no `locality_pinned=`, every `<s>`/`<c>` row byte-identical — **but the golden moved by its legend line** (below) | **meets on substance; the golden clause was mis-registered** |

Argv: `ripwire <root> --no-cache` (band 1; the D4 trees each at their pin, clean `git status`);
`python3 bench/scip_pin_precision.py --bin ./build/ripwire --repo <astropy-N> --scip astropy-N.scip
--label astropy-N-r4` (band 2; the r4base labels are the same-commit baselines); `ripwire <astropy-14365>
--no-cache --pin-census=FILE` and `grep -cE '^C<TAB>locality<TAB>'` against the header (band 3).

**The registration defect, stated plainly.** Conjunct 3 demanded BOTH "two entries in the map's leading
legend comment" AND "`test/golden.xml` byte-identical". The legend IS the first line of the golden, so
the two clauses cannot both hold; the parenthetical reason given for the byte-identity clause — "the
fixture holds no locality pin and no tie the change moves" — is the substance, and that substance
holds exactly: the golden diff is the legend line and the two `est_tokens` copies that follow the
legend's own bytes (769 → 822), zero `<s>`/`<c>`/count changes. The golden was re-derived in its own
commit (`292d5de`) with that diff reviewed by eye. Whether "met on substance" is enough is the
orchestrator's call, recorded here rather than argued away; the lane's reading is that reverting a
disclosure because its own required legend entry appears in a legend-bearing golden would be the rule
eating its purpose.

**What the numbers say.** The marker makes 115 pins on astropy-14365 visible per row (`lpin="K"` on 4
of the 200 shown rows, 36 bytes) and per corpus (`locality_pinned=115`); ugrep 66, rocksdb 141, duckdb
171, ripwire `src/` 0 — the last is a real zero (the census holds 0 `locality` rows on this C++ tree:
qualifiers, receivers and cones decide before the prior ever has to). `ambiguous=` moved by the
tie-break alone and by no more than 0.40%; the marker contributed nothing to it by construction. The
tie-break's effect reproduces phase 3b exactly on the moved tree: locality 224 → 115 sites, the
leavers reappearing as `split` (2,731 → 2,840 on 14365; 3,092 → 3,201 on 12907), `@nondef` 30 → 0,
full-oracle 0.368 → 0.670 / 0.373 → 0.678.

**A measurement trap, recorded.** `ripwire src/` on the WORKING tree read `ambiguous=5601` (then
5600) during the lane: the corpus was moving under the measurement — this lane's own new symbols
(`localityKeyOf`, `isLocalityPin`, `counterTotal`, `counterAt`) — not the resolver. Band 1's `src/`
row is therefore measured on `git archive 1c6fdf4 src` extracted to scratch, where the new binary
reads 5,598 / 13,002 edges: identical to the baseline. Any future band on the tool's own tree must pin
the corpus the same way.

**Contract checks, all clean:** determinism ×2 (fixture, astropy-14365), cold == warm == warm on
astropy-14365, `xmllint --noout` on both maps; ASan (`LSAN_OPTIONS=suppressions=lsan_suppressions.txt`)
on `lpincheck`, `pincensuscheck`, `scipjoincheck`, `localitycheck` and the full `--scip --pin-census`
over astropy-14365 (rc 0, 0 reports, census byte-identical to the dev binary's); `pincensuscheck`,
`scipjoincheck`, `localitycheck`, `resolverhonestycheck`, `chainguardcheck`, `legendcoveragecheck`,
`jsonparitycheck`, `fixedbufsweep` (re-pinned +3 bounded numeric snprintfs), `mcpclidiffcheck`,
`estchargecheck`, `compactlegendcheck`, `attrvocabcheck`, `deckcheck`, `docscommandscheck`,
`docdriftcheck`, `flagtablecheck` green. `manifestcheck` red ONLY on the three gate-count pins (EVALS:24,
:4912 and §8 — the loop now names one more script than they say) — the orchestrator's recompute. The astropy map and both census files are
byte-identical before and after the in-lane refactor that folded six duplicated counter loops into
`counterTotal`/`counterAt`. `--quality-delta --scope='src/*'` gating 0 after four exact-name acks (the
two deliberate `serialize`/`serializeJson` contract changes, the one-line `classifyPin` reroute through
`isLocalityPin`, the one-argument `runAround` call-site extension).

**What stands after this section.** (a) The S6-C pin is no longer silent: every remaining pin carries
`lpin=` and the header sums them, so the "unearned exclusion from `amb=`" phase 3 funded is discharged
without touching `amb=`. (b) The residue is now enumerated per site (lane report): of 28 disconfirmed
remaining pins on 14365 by the (caller, callee) join, 13 external, 13 same-file sibling-class, 1
`@nondef`, 1 cross-file. Reading the 13 sibling-class sites at source splits them into shapes a
receiver rule can and cannot reach — the next section registers the reachable one.

### Phase 4b — Rule 2c, the CLASS-NAME receiver route for the sibling-class residue, PRE-REGISTERED 2026-09-03 (before any fixture, gate or code)

**The residue, read at source before anything was designed.** Phase 4 left 13 same-file sibling-class
disconfirmations among the remaining pins on astropy-14365 (28 disconfirmed of 68 by the (caller,
callee) join; 13 external, 1 `@nondef`, 1 cross-file beside them). They are NOT bare calls, and they
split into two populations by what the receiver token IS:

- **Five sites whose receiver is the NAME OF A CLASS** — a static / classmethod call through the class:
  `astropy/modeling/bounding_box.py:711` `_Interval.validate(value)` (pinned `ModelBoundingBox::validate`,
  SCIP `_Interval::validate`); `:1350` and `:1398` `_SelectorArguments.validate(…)` (pinned
  `CompoundBoundingBox::validate`, SCIP `_SelectorArguments::validate`); `:1427`
  `ModelBoundingBox.validate(…)` (pinned `CompoundBoundingBox::validate`, SCIP `ModelBoundingBox::validate`);
  `astropy/utils/iers/iers.py:924` `IERS_B.open()` (pinned `IERS_Auto::open`, SCIP `IERS::open` — the
  method is INHERITED: `IERS_B` defines no `open`, its base `IERS` does). On 12907 the same five sit at
  `bounding_box.py:684/1300/1344/1370` and `iers.py:801`. Today ingest classifies the receiver
  `RecvKind::NamedVar` with `recvVar` = the class name, Rule 2 finds no local binding for it, and S6-C
  hands the win to the CALLER's own class by the scope segment — the wrong pin every time.
- **Eight sites no type fact reaches**: untyped locals and parameters (`base.represent_as(…)` ×2,
  `diff.represent_as(…)`, `value.field(…)`, `masked_cls.from_unmasked(…)`), `super().__new__(…)`, a
  chained expression `(u / t).decompose()`, and two same-canonical-id overload pairs (`atol.to_value`,
  `UnitBase::decompose` — a duplicate definition, not a sibling). These stay disclosed by `lpin=` and are
  declared OUT OF REACH of this section; a path-only S6-C for untyped `NamedVar` receivers was considered
  and NOT attempted here, because on the C++ corpora the untyped receiver is the common case and the
  `ambiguous=` ceiling would almost certainly decide it before the census could.

**The route — P2-D Rule 2c, class-name receiver.** In the resolve ladder, immediately after Rule 2
misses and before Rule 2b: a named-receiver call (`recv == NamedVar`, no qualifier, caller a known def)
whose `recvVar` (i) has NO local binding of any kind in the caller's scope (a parameter or local named
like a class shadows it — Rule 2b's `localNames` veto, reused), and (ii) is the name of at least one
in-repo `Class`/`Struct`/`Interface` definition, resolves the callee against `recvVar::callee` in
`canonByName` — and, when the class defines no such method, walks its DIRECT bases level by level
(`chaUp`, the exact discipline Rule 2b already uses), first level with a hit wins. A hit narrows the
tier to those definitions (`receiver-rule` in the census, the same mechanism label as Rules 1/2/2b/3);
a miss changes nothing. Two same-named classes both defining the callee keep BOTH candidates: an honest
split `amb=` counts, never a guess between them. Same-root and language-compatibility filters as Rule 2.

**Same-commit baselines:** the Phase 4 table's four `ambiguous=` figures and ceilings are reused
unchanged (they were measured on the shipped Phase-4 binary: src 5,598 on `git archive 1c6fdf4 src`;
ugrep 1,722; rocksdb 45,146; duckdb 8,934 — the ceilings stay the Phase 4 ones, 5,709 / 1,755 / 45,866 /
9,112, so the two rounds are bounded TOGETHER against the 1c6fdf4 tree, not each against the last).
Census baseline: the `astropy-N-r4` labels (locality 0.670 / 0.678 at 88 / 87; receiver-rule 0.930 /
0.921 at 4,847 / 4,766).

**The band — four conjuncts, all-or-nothing; a miss reverts the route in the commit that carries the
RUN section and keeps the patch verbatim in the lane report.**

1. `ambiguous=` ≤ the Phase 4 ceilings on each of the four corpora.
2. **The five listed 14365 sites leave the `locality` population and are CONFIRMED** — each appears as a
   `receiver-rule` C row whose target SCIP names (the `IERS_B.open()` site through the base walk). The
   12907 five are the stability check, reported beside. A site that leaves `locality` but lands
   DISCONFIRMED is a miss of this conjunct — the route is only worth shipping if it is right where it
   fires.
3. **`receiver-rule` full-oracle precision on 14365 non-inferior: ≥ 0.925** (0.930 today). The route adds
   rows to this stratum across the whole corpus, not just the five sites; if the rows it adds are
   wrong elsewhere the stratum dilutes, and −0.5 points is the slack a five-site win must not spend.
   The new rows' own confirmation count is printed beside it.
4. **`locality` full-oracle precision non-inferior to 0.670 / 0.678** — removing wrong pins can only
   raise it; a drop means the route removed RIGHT pins.

**Contract checks, not bands:** determinism ×2, cold == warm on astropy-14365, `xmllint` on fixture and
astropy maps, ASan on the new gate + `pincensuscheck` + `scipjoincheck` + the astropy census path;
`golden` byte-identical (the fixture holds no class-name receiver call); `narrowcheck`,
`fieldnarrowcheck`, `chacheck`, `chainguardcheck`, `resolverhonestycheck`, `localitycheck`,
`lpincheck`, `pincensuscheck` green; `--quality-delta --scope='src/*'` clean.

**Gate — written and run RED before the code.** `test/clsrecvcheck.sh` on `test/clsrecvfix/` (Python,
one file): `Box.__setitem__` calls `Interval.validate(v)`; both `Box` and `Interval` define `validate`,
so today S6-C pins `Box::validate` by scope (`lpin="1"` on `Box::__setitem__`) — after: one edge to
`Interval::validate`, census mech `receiver-rule`, no `lpin=`. Controls: (a) `Box.other()` calls
`item.validate(v)` on an UNTYPED local — unchanged, still the S6-C pin with `lpin="1"` (the route keys
on the class NAME only); (b) `Box.shadowed(Interval)` — a PARAMETER named `Interval` — is vetoed:
unchanged pin, `lpin="1"`; (c) `Box.inherited()` calls `Leaf.validate(v)` where `Leaf(Interval)`
defines no `validate` — the base walk lands `Interval::validate`; (d) `Box.miss()` calls
`Point.validate(v)` where `Point` defines no `validate` and has no bases — nothing fires, the ladder is
unchanged. Plus determinism ×2 and `xmllint`. Red on the Phase-4 binary at the main arm and (c).

### Phase 4b, RUN — Rule 2c ships: ACCEPT on all four conjuncts (measured 2026-09-03)

**Verdict: ACCEPT.** The class-name receiver route ships (commit named in the lane report), with a
kParserVer bump (75 → 76) for the one ingest fact it needed: a Python function definition's parameter
NAMES, recorded as EMPTY-SPAN `VarDecl` bindings so they feed the shadow veto Rules 2b/2c share and
nothing else (the r9 shadow suppression tests span containment and stays C++/ObjC-only — the fixture
control (c) went RED without it: a parameter named `Interval` did not veto the route because Python
parameters were never bound).

| Conjunct | Registered | Measured (14365 · 12907) | |
| --- | --- | --- | --- |
| 1. `ambiguous=` vs the Phase 4 ceilings | ≤ 5,709 / 1,755 / 45,866 / 9,112 | src **5,598** (0, on `git archive 1c6fdf4 src`) · ugrep **1,722** (0) · rocksdb **45,142** (−4) · duckdb **8,929** (−5) | **meets** |
| 2. the five listed sites leave `locality` CONFIRMED | 5 / 5 as `receiver-rule`, SCIP-confirmed | 14365 **5 / 5** (`_Interval::validate`, `_SelectorArguments::validate` ×2, `ModelBoundingBox::validate`, `IERS::open` through the base walk) · 12907 **5 / 5** at 684 / 1300 / 1344 / 1370 / 801 | **meets** |
| 3. `receiver-rule` full-oracle precision | ≥ 0.925 on 14365 | **0.931** (5,141 / 5,522; was 0.930 at 4,847) · 12907 0.923 (was 0.921) | **meets** |
| 4. `locality` full-oracle precision non-inferior | ≥ 0.670 / 0.678 | **0.696** (55 / 79) · **0.705** (55 / 78) | **meets** |

Argv as in Phase 4 with `--label astropy-N-r4b`; the site table from a (caller, callee, line) join of the
`r4` and `r4b` census files (script in the lane report).

**What the route did across the corpus, not just at the five sites.** On 14365 it moved 675 decided
sites into `receiver-rule`: 207 from `unique` (one candidate all along; the label changes, the edge does
not), 34 from `split` (an honest k-way spray now one typed edge), 9 from `locality` (the 5 wrong pins
plus 4 that happened to be right), and **425 sites that had NO row before** — `Cls.m()` calls to a
name with many in-repo definitions and no same-file candidate, which the tier ladder used to DROP
entirely (phase 3's "call-shaped, no decided site" floor). SCIP speaks on 675 of them: **617 confirmed,
40 `@external`, 18 in-repo disagreements** — and every one of the 18 read at source is the census's own
documented (caller, callee) key collision (two `BaseRepresentation.represent_as(…)` sites in one test
sharing one oracle answer, `FloatingPoint.__init__` beside `Array.__init__` in one `Complex.__init__`),
not a wrong target. `edges=` moved +4 on rocksdb and −3 on duckdb; `ambiguous=` fell on both — the
route is a recall gain at receiver-rule precision, and the `locality` population shrank by exactly the
nine sites it explained (`locality_pinned=` 115 → 106 on 14365; ugrep/rocksdb/duckdb unchanged at 66 /
141 / 171: no class-name receiver reaches S6-C on those C++ trees, where `Cls::m()` is a qualifier).

**Contract checks, all clean:** `clsrecvcheck` (RED first at arms A, D, F on the Phase-4 binary; arm C
RED once more before the parameter capture), determinism ×2 and cold == warm on astropy-14365 (the
kParserVer bump re-parses once; warm == cold thereafter), `xmllint` on both maps, `test/golden.xml`
byte-identical; ASan on `clsrecvcheck`, `lpincheck`, `pincensuscheck`, `scipjoincheck` and the astropy
census path (census byte-identical to the dev binary's); `narrowcheck`, `fieldnarrowcheck`, `chacheck`,
`chainguardcheck`, `resolverhonestycheck`, `localitycheck`, `shadowcheck`, `qextractionkeycheck`,
`qschemetripcheck` (re-pinned with its log entry), `cachehashcheck`, `pyshapecheck`, `usescheck`,
`fieldusescheck`, `pyimportprecisecheck`, `legendcoveragecheck`, `fixedbufsweep` green; `manifestcheck`
red only on the gate-count pins (507 now) — the orchestrator's recompute; `--quality-delta
--scope='src/*'` gating 0.

**What is left, stated.** The eight unreachable sibling-class sites stay disclosed by `lpin=`; the 17
external pins are the disclosure's remaining job (a tie-break cannot decline to pin, and no in-repo
oracle says "builtin" — that is `--scip`'s). The remaining `locality` population is n = 79 on 14365, 78
on 12907: below the n ≥ 100 floor on either alone, pooled 157 — a future band on this stratum inherits
Phase 4's pooling rule and its stated dependence.

### Phase 5 — the census residue: the EXTERNAL-NAME VETO (`@external`) and the receiver MRO walk, PRE-REGISTERED 2026-09-03 (before any fixture, gate or code)

**The residue, re-read at source on the d8fa59c binary before anything was designed.** The Phase 4b RUN
left the `locality` stratum at 55 / 79 on astropy-14365 (0.696) and 55 / 78 on 12907 (0.705): 17 (16)
`@external` disconfirmations and 7 (7) in-repo ones. The census join reproduced byte-for-byte on the
d8fa59c binary before this phase (`--label astropy-N-r5base`, same argv as Phase 4). Every one of the 24
disconfirmed 14365 sites was read at source; they fall into FIVE shapes, and the two mechanisms below are
designed from those shapes, not from the numbers:

- **(a) a BARE call whose name is a Python builtin**, pinned to a same-file METHOD of that name — a shape
  Python's name lookup can never produce (a bare `sum(…)` reaches the local, enclosing, module and
  builtin scopes; never a method): `representation.py:1186` `sum(` → `BaseRepresentation::sum`;
  `table/index.py:207` `range(` → `Index::range`. 2 sites (12907: `index.py:200`; the `sum` site is not
  covered there).
- **(b) a named-receiver call whose receiver is bound by an IMPORT of a module the indexed tree does not
  contain**: `np.dtype(…)` ×5 at `io/fits/column.py:1391/1394/1397/1402/1432` (`import numpy as np`) →
  `Column::dtype`; `OrderedDict.__getitem__(…)` at `table/table.py:2235` (`from collections import
  OrderedDict`) → `Table::__getitem__`. 6 sites (12907: `column.py:1305/1308/1311/1316/1341`,
  `table.py:2043`).
- **(c) `super().m(…)`** — ingest classifies the `super()` call-node receiver `RecvKind::None`, so the site
  reaches the ladder as a BARE call and S6-C hands it to the caller's OWN class, the one class `super()`
  by definition skips: `fitsrec.py:1254` `super().field(-1)` (FITS_rec's only base is `np.recarray`),
  `modeling/core.py:151` `super().__init__` and `:485` `super().__repr__` (`_ModelMeta(abc.ABCMeta)`),
  `modeling/utils.py:436` `super().__setitem__` (`_SpecialOperatorsDict(UserDict)`) — 4 sites whose MRO
  leaves the repo, SCIP `@external` on all four (12907: `:1229`, `:132`, `:461`, `:431`); and
  `utils/masked/core.py:476` `super().__new__(cls, …)` in `MaskedNDArray(Masked, np.ndarray)`, whose MRO
  reaches the in-repo `Masked::__new__` — SCIP names exactly that (12907: `:460`).
- **(d) a method call on an UNTYPED local or parameter whose method name is a builtin-TYPE method**:
  `header.py:1795` `self._keyword_indices[keyword].index(idx)` and `:438` `data.index(sep, idx)`
  (`list.index` / `str.index`), `bounding_box.py:1616` `fixed_inputs.copy()` (`dict.copy`). 3 sites. No
  type fact reaches them and the enclosing class defines a method of that name: deciding "external" here
  would be a guess against the class's own method, not a table lookup. **Declared OUT OF REACH.**
- **(e) a receiver bound by MODULE-LEVEL ASSIGNMENT to a C-extension attribute**: `wcs.py:621/636`
  `WCSBase.__init__(self, …)` where `WCSBase = _wcs._Wcs` (`= object` in the fallback arm). 2 sites.
  Not an import, not a class definition; **OUT OF REACH** of this phase.

**The eight "unreachable sibling-class" sites Phase 4b declared, by file:line, and what the r5base join
says about each today** (the diag `bench/scip_match_diag.py --label astropy-14365-r5base` puts all 106
`locality` sites at 79 covered / 25 SCIP-silent / 2 line-skew; the per-site verdicts come from the same
(caller_id, callee, line) join of `astropy-14365-r5base.plain.tsv` × `.scip.tsv` the harness measures):

| # | site (14365 · 12907) | call | pinned | SCIP | r5base verdict | this phase |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `coordinates/representation.py:864` · `:827` | `diff.represent_as(…)` (untyped loop var) | `BaseRepresentation::represent_as` | `BaseDifferential::represent_as` | disconfirmed | out of reach (untyped receiver, no `super`) |
| 2 | `representation.py:3349` · `:3210` | `base.represent_as(…)` (untyped local) | `UnitSphericalCosLatDifferential::represent_as` | `SphericalRepresentation::represent_as` | disconfirmed | out of reach |
| 3 | `representation.py:3088` · `:2956` | `base.represent_as(…)` (untyped local) | `UnitSphericalDifferential::represent_as` | `SphericalRepresentation::represent_as` | disconfirmed | out of reach |
| 4 | `io/fits/fitsrec.py:567` | `value.field(…)` (untyped parameter) | `FITS_rec::field` | `FITS_record::field` | **counted CONFIRMED** — the same line also holds `self.field(…)`, and the census keys the oracle by (caller, callee): one truth set `{FITS_rec::field, FITS_record::field}` covers both sites | unchanged (the join's documented key collision, not a right pin) |
| 5 | `utils/masked/core.py:125` · `:124` | `masked_cls.from_unmasked(…)` (untyped local) | `Masked::from_unmasked` | `MaskedNDArray::from_unmasked` | disconfirmed | out of reach |
| 6 | `utils/masked/core.py:476` · `:460` | `super().__new__(cls, …)` | `MaskedNDArray::__new__` | `Masked::__new__` | disconfirmed | **the MRO walk**: `receiver-rule`, confirmed |
| 7 | `units/core.py:1284` | `(u / tunit_decomposed).decompose()` | `UnitBase::decompose` | `UnitBase::decompose` ∪ `Unit::decompose` | counted CONFIRMED (key collision with `u.decompose()` in the same caller) | unchanged |
| 8 | `time/core.py:3154` | `atol.to_value(u.day)` | `TimeDelta::to_value` | `TimeDelta::to_value` ∪ `Quantity::to_value` | counted CONFIRMED (key collision with `self.to_value(u.day)` on the same line) | unchanged |

So of the eight, ONE is reachable by the walk (#6), THREE are already scored confirmed by the join's key
collision and cannot move (#4, #7, #8), and FOUR are untyped-receiver sites no mechanism in this phase
reaches (#1, #2, #3, #5) — they stay disclosed by `lpin=`. The orchestrator's premise that the walk
covers all eight is corrected here, before measurement, rather than argued after it. Beside the eight,
`modeling/core.py:1085` (`bbox.evaluate(…)`, SCIP `@nondef` ∪ `_BoundingDomain::evaluate`) and
`wcsaxes/core.py:503` (`self.coords.frame.draw(…)`, a depth-3 chain, cross-file) are the other two in-repo
disconfirmations; both out of reach too.

**Mechanism 1 — the external-name veto (`@external`).** A call the name ladder would otherwise SPRAY (no
qualifier, not SCIP-pinned, no receiver rule fired) is refused — no edge, counted once into the header
`external=N` (absent when 0, legend-defined in both dialects, JSON twin `"external":N`) and, under
`--pin-census`, recorded as a `C external` row with an EMPTY target list — when its name or receiver is
provably bound OUTSIDE the indexed tree. Three evidence sources, none heuristic:

1. **Import bindings** (a NEW ingest fact, kParserVer 76 → 77, mirror in `src/quality.h` in the same
   commit): Python `import a.b as c` / `import a.b` / `from m import x as y` / `from . import x` record a
   file-scope `LocalBindKind::Import` binding `bound-name → module target` (`np → numpy`, `OrderedDict →
   collections`, `x → .`; `from m import *` records nothing). Today the Include record keeps only the
   module and drops the imported-names clause, so the bound NAME is not recoverable resolve-side. A
   binding is EXTERNAL iff its target is absolute (no leading dot), `resolvePreciseInclude` maps it to
   no indexed file, AND its head segment names no `.py` stem and no directory anywhere in the indexed
   tree (so a package the crawl did not root at — `src/mypkg/` imported as `mypkg` — reads UNKNOWN,
   never external: the veto is conservative on the side of keeping an edge). A relative import is always
   in-repo evidence. Only Python records these this phase (TS/JS/Rust/Go imports are a follow-up).
2. **The builtin table** — `src/externalnames.h`, a committed sorted table with provenance per group:
   Python = the 152 names of CPython 3.14.7's `builtins` module (`python3 -c 'import builtins;
   print(sorted(dir(builtins)))'`, the six `site`-injected names `copyright credits exit help license
   quit` and the five non-callable constants `True False None Ellipsis NotImplemented` excluded; the
   exception and warning classes kept — they are callable); C-family = the ISO C11 §7 library function
   names listed by header (`<stdio.h> <stdlib.h> <string.h> <math.h> <ctype.h> <time.h> <wchar.h>
   <stdint.h>/<inttypes.h> <signal.h> <assert.h>`) plus the `std::` function templates a bare spelling
   reaches through ADL or a using-directive, taken from the C++23 synopses of `<algorithm> <utility>
   <memory> <numeric> <iterator> <functional> <cmath> <cstring> <cstdlib> <cstdio> <string> <ranges>`
   (`begin end size data empty swap move forward exchange min max clamp sort find copy fill transform
   accumulate …` — the full list is the table). The Python stdlib MODULE surface (`sys.stdlib_module_names`,
   297 names) is deliberately NOT a table: a stdlib member only becomes a bare name through an import,
   and source 1 decides that by resolution, not by list.
3. **Definition evidence, per language.** Python: a same-file module-level `def`/`class` of the name, a
   nested `def` of the name inside the caller, an in-repo import binding, or any local/parameter binding
   of the name (`localNameSet`) is evidence — the ladder runs unchanged. C/C++/ObjC: a symbol of that
   name (declaration OR definition — the header-decl/.cpp-def split is the common case) in the caller's
   file or in any file the caller's file transitively includes (the same path-precise `fileIncludes`
   Rule 3 reads), an enclosing-class or base-class member (mechanism 2, which fires first), or a local
   binding is evidence — and only a FREE (scope-less) symbol or a macro counts as file/include evidence:
   a same-name METHOD of an unrelated class in the same file is exactly the target a bare call cannot
   reach, so it is not evidence (the enclosing class and its bases are mechanism 2's job).

   The veto then fires, in the ladder after Rules 1/2/2c/2b/3 have all missed and BEFORE the tier
   spray — i.e. it removes `unique`- and `split`-tier pins as well as S6-C ones, because the fact it
   states ("this name is bound outside the tree") is a name-resolution fact, not a tie-break: (i) a bare
   Python call whose name has an EXTERNAL import binding, or is in the Python table with no evidence;
   (ii) a bare C-family `Call` (never `Macro`) whose name is in the C-family table with no evidence;
   (iii) a Python named-receiver call whose receiver has an EXTERNAL import binding and no local binding.
   `unresolved=` is untouched (it counts lang-filtered in-repo names; these are not that).

**Mechanism 2 — the receiver MRO walk (Rule 1 generalised).** (i) Rule 1's `this->m()` / `self.m()` /
bare C-family `m()` shapes, when the enclosing class does NOT define `m`, now continue into the
class's bases level by level through `Narrower::methodOnTypeOrBases` (the walk Rules 2b/2c already use;
first level with exactly one hitting base decides, two at one level refuse) — the `IERS_B.open()` base
walk applied to the caller's own class. A miss leaves the ladder unchanged (a `self.m()` may dispatch
DOWNWARD to a subclass; the cone filter owns that). (ii) A NEW receiver kind `RecvKind::SuperObj`
(appended, value 5; Python `super().m()` and `super(C, self).m()`, the `call` node whose function is the
identifier `super`) resolves through the bases ONLY (the class itself is skipped — `super()` never names
it); a miss is a VETO counted into `external=`: the MRO left the indexed tree (`object`, a stdlib or
third-party base), and pinning any in-repo `m` — least of all the caller's own — is wrong by the
language's definition of `super`. No language other than Python classifies a `super` receiver this
phase (`isMemberAccessNode` is C++/Python only).

**Same-commit baselines, measured on the d8fa59c binary before the change.** `ambiguous=`: src **5,632**
on `git archive d8fa59c src` (NOT the 5,598 of the Phase 4b table, which was the 1c6fdf4 tree — the
r4/r4b lanes' own source is in the corpus now; this phase re-bases on the tree the task names), ugrep
1,722, rocksdb 45,142, duckdb 8,929 (`--no-cache`, D4 trees at 550599a / 0e2801ac3 / 19864453f7,
a clean `git status` on each). `edges=` beside them: 13,119 / 5,388 / 210,904 / 84,698. Census
(`astropy-N-r5base`): locality 0.696 (55 / 79) · 0.705 (55 / 78); receiver-rule 0.931 (5,141 / 5,522);
unique 0.798 (19,153 / 24,009) with 3,764 `@external` covered sites — the `isinstance` → `TableColumns::
isinstance` shape, the same defect one tier up, reported below but NOT banded.

**The arithmetic, stated before the run.** From the 14365 population of 79 covered `locality` sites:
mechanism 1 removes shapes (a) + (b) = 8 sites and mechanism 2's veto removes the 4 `super()`-miss sites
of shape (c) → 12 of the 17 `@external` leave; site #6 flips to `receiver-rule` → 1 in-repo
disconfirmation leaves. Expected: **55 / (79 − 13) = 55 / 66 = 0.833** (had all 17 externals left,
55 / 62 = 0.887; had all eight sibling sites flipped as well, 63 / 66 = 0.955 — neither is reachable,
and the band is set on what is). 12907: 55 / (78 − 12) = 55 / 66 = 0.833. n = 66 on either corpus is
under the n ≥ 100 floor; Phase 4's pooling rule applies: **pooled n = 132 ≥ 100**, expected pooled
110 / 132 = 0.833. If the pooled n falls under 100 the section is INCONCLUSIVE, and no band is widened.

**The band — six conjuncts; conjuncts 1–4 gate BOTH mechanisms together (they share the ladder), 5
gates mechanism 1 alone and 6 mechanism 2 alone. A miss on 5 reverts mechanism 1 and keeps 2 if 1–4 and
6 hold; a miss on 6 reverts mechanism 2 (the `SuperObj` kind stays as an ingest fact, its veto arm and
the Rule-1 base walk go) and keeps 1 if 1–5 hold; a miss on any of 1–4 reverts both. A revert keeps the
patch verbatim in the lane report. The band is not moved after a number.**

1. `ambiguous=` within **+2.0 %** of the baselines above on all four corpora: src ≤ 5,744, ugrep ≤ 1,756,
   rocksdb ≤ 46,044, duckdb ≤ 9,107. (A DROP is expected on the C++ trees — a bare std-name spray that
   used to split now vetoes, and a `this->m()` that used to split across unrelated classes now walks the
   base — and is fine.)
2. **The thirteen 14365 sites named above leave the `locality` population**: the 8 of shapes (a)+(b) and
   the 4 `super()`-miss sites as `C external` rows SCIP scores `@external` (the veto right where it
   fires), site #6 as a `receiver-rule` row SCIP CONFIRMS. All thirteen, or the conjunct misses. The
   twelve 12907 sites are the stability check, reported beside.
3. **`locality` full-oracle precision, pooled over 14365 + 12907, ≥ 0.80** (expected 0.833; the slack
   is for sites the harness reclassifies when the population shifts, not for wrong pins), each corpus
   reported with its n, and non-inferior to 0.696 / 0.705 on each corpus alone.
4. **`receiver-rule` full-oracle precision on 14365 ≥ 0.925** (0.931 today) — the walk adds rows to
   this stratum corpus-wide; its own new-row confirmation count is printed beside it.
5. **Veto precision** (mechanism 1): over every `C external` row on 14365 that SCIP covers, the share
   SCIP scores `@external` (a `@nondef` is neither confirmation nor disconfirmation of "outside the
   tree" and is reported separately) **≥ 0.95**, n printed. Below that the table or the evidence rule is
   wrong somewhere, and a veto that drops right edges is worse than the pin it replaces.
6. **Walk precision** (mechanism 2): over the `receiver-rule` rows the walk ADDED on 14365 (a
   (caller, callee, line) join of the r5base and r5 census files — rows labelled `receiver-rule` in r5
   and anything else, or absent, in r5base — restricted to `ThisObj`/bare/`SuperObj` shapes by the
   fixture-proven mechanism), SCIP-covered confirmation **≥ 0.90**, n printed.

**Reported, not banded:** the `unique` stratum's `@external` count and precision on 14365 before/after
(expected to fall from 3,764 and rise from 0.798 — the veto reaches that tier by design); `edges=` on all
four C++ trees; `external=` on all six corpora; the `split` stratum's covered n.

**Contract checks, not bands:** determinism ×2 and cold == warm on astropy-14365 (the kParserVer bump
re-parses once); `xmllint --noout` on the fixture and astropy maps; ASan on the new gates, `lpincheck`,
`clsrecvcheck`, `pincensuscheck`, `scipjoincheck` and the astropy census path; `test/golden.xml` (the
fixture holds no bare builtin call to an in-repo name and no `super()` — re-derived in its own commit if
that reading is wrong, with the diff stated); the resolver/locality family green (`lpincheck clsrecvcheck
localitycheck chainguardcheck resolverhonestycheck shadowcheck qextractionkeycheck qschemetripcheck
cachehashcheck pyshapecheck usescheck fieldusescheck pyimportprecisecheck legendcoveragecheck
compactlegendcheck fixedbufsweep deckcheck docscommandscheck manifestcheck loopconservationcheck`);
`--quality-delta --scope='src/*'` gating 0.

**Gates — written and run RED before the code.** `test/externalvetocheck.sh` on `test/extvetofix/`
(Python `ext.py` + `own.py`, C++ `ext.cpp` + `ext.h` + `decl.cpp`): (A) `Rep.norm` calls bare `sum(…)`
with `Rep::sum` and `Other::sum` both defined in the file — today an S6-C pin on `Rep::sum` with
`lpin="1"`; after: NO `sum` edge from `Rep::norm`, no `lpin=`, a `C external` row; (B) `Rep.conv` calls
`np.dtype(…)` under `import numpy as np` with `Rep::dtype` defined — today pinned; after: vetoed; (C)
`Rep.get` calls `OrderedDict.__getitem__(…)` under `from collections import OrderedDict` — vetoed; (D)
control: `Rep.use` calls `helper(1)` under `from .own import helper` — the edge to `own.py::helper`
stays; (E) control: `own.py` defines a module-level `def sum(xs)` and `K.go` calls `sum([1])` — same-file
definition evidence, the edge stays; (F) C++: `free_fn` calls bare `find( 3 )` with `Buf::find` and
`Other2::find` defined — today a split, after: vetoed; (G) control: `uses_decl` calls `clamp( 1 )`,
declared in the included `ext.h` and defined in `decl.cpp` — include evidence, the edge stays; (H) the
header reads exactly `external=N` for the fixture's N vetoed sites, and the legend defines it (both
dialects); (I) `--json` carries `"external":N`; (J) determinism ×2 and `xmllint`. `test/mrowalkcheck.sh`
on the same fixture: (K) `Leaf.run` calls `super().run()` where `Leaf(Mid)`, `Mid(Base)`, `Base.run`
defined — today NO edge at all (the S6-C pin lands the caller's own `Leaf::run`, a self-loop, dropped);
after: one edge to `Base::run`, mech `receiver-rule`; (L) `Ext(dict).reset` calls `super().__init__()`
with `Other.__init__` defined in the file — today a `unique` edge to `Other::__init__`; after: vetoed,
`C external`; (M) C++: `Grid::go` calls bare `size()` where `Grid : Buf`, `Buf::size` and `Other2::size`
defined — today a split (`amb="1"`), after: `Buf::size`, `receiver-rule`; (N) control: `Ext.reset` also
calls `self.keys()` — no in-repo `keys` anywhere, no row before or after (the walk never invents a
target); (O) determinism ×2. Both gates enter `test/regression.sh` in their feature commits; red on the
d8fa59c binary at A, B, C, F, H, I, K, L, M.

### Phase 5, RUN — ACCEPT on conjuncts 1, 3, 4, 5, 6; conjunct 2 at 12 / 13, a MISS BY THE LETTER the registration itself predicts (measured 2026-09-03)

**Verdict.** Both mechanisms ship on the lane branch (commit named in the lane report; kParserVer 76 → 77
with the mirror). Five of six conjuncts meet with room; conjunct 2 counts twelve of its thirteen named
sites leaving — the thirteenth, `table/table.py:2235` `OrderedDict.__getitem__(…)`, stays a `locality`
pin because the mechanism as REGISTERED says it must: `from collections import OrderedDict` resolves to no
indexed file, and its head segment `collections` names `astropy/utils/collections.py`, so the binding reads
UNKNOWN — the conservative clause written into source 1 above, applied to a site the same registration
listed as leaving. The registration contradicts itself on that one site; the arithmetic was written
without applying its own head-segment rule. By its letter a miss on 1–4 reverts both mechanisms; by its
substance the mechanism did exactly what was registered and every measured number is above its floor.
As the Phase 4 RUN did with its golden clause, this section states the defect and leaves the letter to
the orchestrator: the code is NOT reverted, the branch is the patch, and the revert recipe is the lane
report's. Depth-≤2 head-segment probing (a package importable from the crawl root sits at depth 1 or 2;
`astropy/utils/collections.py` is depth 3) is the obvious refinement and is deliberately NOT applied
after the number — it is the first candidate for a Phase 5b registration.

| Conjunct | Registered | Measured (14365 · 12907) | |
| --- | --- | --- | --- |
| 1. `ambiguous=` ≤ +2.0 % | src ≤ 5,744 · ugrep ≤ 1,756 · rocksdb ≤ 46,044 · duckdb ≤ 9,107 | src **5,634** (+2, +0.04 %) · ugrep **1,703** (−19) · rocksdb **44,969** (−173) · duckdb **9,021** (+92, +1.03 %) | **meets** |
| 2. the thirteen named sites leave `locality` | 13 / 13 | **12 / 13** — `sum`:1186, `range`:207, `np.dtype` ×5, the four `super()`-miss sites all `C external` and SCIP `@external`; `super().__new__`:476 `receiver-rule` → `Masked::__new__`, SCIP-confirmed; `OrderedDict.__getitem__`:2235 stays (above) · 12907 **11 / 12**, the same site | **miss by the letter** |
| 3. `locality` full-oracle precision, pooled ≥ 0.80; each ≥ 0.696 / 0.705 | pooled n ≥ 100 | **0.836** (51 / 61) · **0.836** (51 / 61); pooled **0.836** (102 / 122), n = 122 ≥ 100 | **meets** |
| 4. `receiver-rule` precision on 14365 ≥ 0.925 | | **0.948** (6,961 / 7,339; was 0.931 at 5,522) · 12907 0.942 (was 0.923) | **meets** |
| 5. veto precision ≥ 0.95 | confirmed / (covered − @nondef) | **0.996** (11,180 / 11,223; 43 in-repo, 4 `@nondef`, n = 11,227 covered of 17,941 refused) · 12907 **0.993** (10,491 / 10,565) | **meets** |
| 6. walk precision ≥ 0.90 | walk-added `receiver-rule` rows, SCIP-covered | **0.995** (1,832 / 1,841 of 1,851 added; 6 sentinel, 3 in-repo) · 12907 **0.995** (1,683 / 1,692) | **meets** |

Argv as in Phase 4 with `--label astropy-N-r5base` (d8fa59c binary) and `astropy-N-r5`; the site
tables from the (caller_id, callee, line) join of `.plain.tsv` × `.scip.tsv` (`join.py`, `walkprec.py`
in the lane report). The conjunct-3 population moved 79 → 61 covered on 14365 (105 → 82 sites): 23 left
— 13 to `external`, 8 to `split` (rich-receiver sites the S6-C prior no longer credits — see D2 below —
e.g. `header.py:1795` `self._keyword_indices[keyword].index(idx)` and the depth-3 `wcsaxes/core.py:503`),
2 to `receiver-rule` (`:476` and its twin `:492`) — and 0 entered. The remaining residue is exactly the
registration's out-of-reach list: `.index`:438, `.copy`:1616, `WCSBase.__init__` ×2 and the `OrderedDict`
site (`@external`), sites #1/#2/#3/#5 and `bbox.evaluate`:1085 (in-repo).

**Two defects the instruments found in the first cut, fixed BEFORE these numbers, each with its
before/after — neither moves a band, both are the registered mechanism failing to be itself:**

- **D1 — a `super()` over two direct bases that both define `m` was VETOED.** `methodOnTypeOrBases`
  refuses a multi-hit level (nullptr, Rule 2b/2c's honest-ambiguity discipline) and the walk read that
  nullptr as "the MRO left the tree" — `FlatLambdaCDM(FlatFLRWMixin, LambdaCDM).__init__` and the
  cosmology `TestFlat*` mixin tests, ~25 sites, refused. Fix: the walk takes the UNION of a multi-base
  level (an honest split) — and, one step further, the DIRECT-base level honours declaration order
  (`chaUpDeclared`, the first declared base that defines `m` wins: Python's C3 puts the first base's
  chain first) because the union alone let the tier ladder's same-file prior pick `LambdaCDM::__init__`
  over the first-declared `FlatFLRWMixin::__init__` SCIP names (19 sites). S6-C is excluded for a
  `super()` receiver. Veto-row in-repo disagreements 73 → 43; walk precision first cut 0.995 → 0.995
  with 19 fewer wrong pins. C3 beyond the direct level is not modelled — disclosed.
- **D2 — a member access whose receiver is undecidable classified `RecvKind::None`, and every bare-name
  guard read it as a BARE call.** The veto refused `self.to_cartesian().sum()` as the builtin `sum`,
  `abs(t1 - t2).max()` as `max`, `"…".format(` as `format`; on ripwire's own src/ ALL 213 first-cut
  vetoes were this shape (`x.foo().find(…)` read as std `find`), and the same misread is what Rule 1's
  bare arm and shadow suppression did on the depth-3 chains `test/chainguardcheck.sh` arm (h) had pinned
  as a disclosed residual. Fix (kParserVer 77, same bump): a call ref whose receiver is a member access
  with an undecidable receiver stamps `FieldOfVar` with an EMPTY recvVar — the convention Read/Write refs
  already used — so `None` means bare. src/ `external=` 213 → 0 (absent); chainguardcheck arm (h) re-pinned
  to the closed shape (its fixture: edges 12 → 15, ambiguous 4 → 6 — the two depth-3 chains take the
  honest split instead of the enclosing-class pin / the deletion). `ambiguous=` moved +2 on src and +92 on
  duckdb from this (rich-receiver calls that Rule 1 used to wrong-pin now split), inside the band.

**Two amendments stated before their code, both conservative:** (A1) C-family definition evidence is a
FREE symbol or macro of the name ANYWHERE in the corpus, not only in the caller's file/includes — an angle
include is not path-resolvable in a single root, so "declared in an included file" is undecidable, while
"the name's in-repo definitions are all members" is the fact the veto actually needs; (A2) the `super()`
direct-base order above.

**Reported, not banded.** `unique` on 14365: 0.798 → **0.876** (19,153 / 24,009 → 18,037 / 20,587),
`@external` 3,764 → **1,479** — the `isinstance` → `TableColumns::isinstance` shape one tier up, the same
defect, mostly gone; 12907 0.810 → 0.879, 3,336 → 1,393. `split` `@external` 258 → 201 · 271 → 214.
`external=` 17,941 on 14365 (17,944 before D1's order fix), 16,970 on 12907; src **absent** (0), ugrep 7,
rocksdb 369, duckdb 2,055. `edges=`: src 13,119 (0), ugrep 5,371 (−17), rocksdb 210,834 (−70), duckdb
84,461 (−237). `unresolved=` fell on rocksdb 1,800 → 1,503 and duckdb 2,650 → 1,492: a C++ call to a
std name whose only in-repo definition is in another language used to count as "lang-filtered
unresolved"; it is external, and the veto now says so first. The walk's 1,851 added rows on 14365: 1,115
re-labelled from `unique`, 180 from `cone`, 24 from `split`, and **522 that had NO row** — `super().m()`
sites the old ladder pinned to the caller's own class and dropped as self-loops; new edges at 0.995.
The 43 veto rows SCIP scores in-repo: 39 are the census's (caller, callee) key collision (the same
caller also calls an in-repo `dtype`/`convolve`/`slice`/… beside the vetoed `np.dtype`/`np.convolve`/
builtin `slice`, one oracle answer for both); the 4 pure ones are `plt.hist` beside an in-repo `hist(…)`
(SCIP silent on matplotlib, so the key carries only the in-repo half), a same-name re-export shim
`class BoxLeastSquaresResults(BoxLeastSquaresResults)`, and a nested CLASS `format` inside a test method
that the nested-def probe (keyed on the enclosing FUNCTION's name) does not see — two sites. Disclosed.

**Contract checks, all clean:** `externalvetocheck` (RED first at A, B, C, F, H, I on the d8fa59c binary)
and `mrowalkcheck` (RED at K, L, M) green; determinism ×2 and cold == warm on astropy-14365 — measured
with a PRIVATE `TMPDIR` cache dir, because the lane's own intermediate kParserVer-77 binaries had written
a blob the final binary would have served (a bump is one-shot; facts that move twice inside one lane
under one bump leave a stale blob behind — the lane report records the trap); `xmllint` on the fixture and
the astropy map; `test/golden.xml` re-derived in its own commit — the legend line (`hdr:external=`) and
`est_tokens` 822 → 884 only, zero row/edge/count changes; ASan on `externalvetocheck`, `mrowalkcheck`,
`clsrecvcheck`, `pincensuscheck`, `scipjoincheck`, `chainguardcheck` and the astropy census path (both
census files byte-identical to the dev binary's, 0 reports); the resolver/locality family green
(`lpincheck clsrecvcheck localitycheck chainguardcheck resolverhonestycheck shadowcheck
qextractionkeycheck qschemetripcheck cachehashcheck pyshapecheck usescheck fieldusescheck
pyimportprecisecheck legendcoveragecheck compactlegendcheck fixedbufsweep pincensuscheck scipjoincheck
narrowcheck fieldnarrowcheck chacheck deckcheck docscommandscheck loopconservationcheck`);
`manifestcheck` red ONLY on the gate-count pins (515 now) — the orchestrator's recompute;
`--quality-delta --scope='src/*'` gating 0 after 26 acks under one stated reason (the four deliberate
contract changes, the ladder's new steps, the census's tenth mechanism, kParserVer, and two lexical clone
false positives), all by the `gating` pseudo-token.

**What is left, stated.** The `locality` residue on 14365 is 10 covered disconfirmations: 5 `@external`
(the two builtin-type methods on untyped receivers, the `WCSBase` module-level alias ×2, the `OrderedDict`
head-segment case) and 5 in-repo (four untyped receivers, one `@nondef`-mixed). n = 61 alone on either
corpus, 122 pooled — the pooling rule still carries the stratum. Phase 5b candidates, in order: the
depth-≤2 head-segment probe (1 site here, but it is the rule's precision); TS/JS/Rust/Go import bindings
(the veto is Python + C-family only); nested-class shadow evidence (2 sites); the C3 order beyond direct
bases (0 sites measured).

### Phase 5b — the depth-≤2 head-segment probe, PRE-REGISTERED 2026-09-03 (owner ACCEPTED Phase 5's conjunct-2 letter; this is the refinement that discharges it)

**The decision this discharges.** Phase 5's conjunct 2 counted twelve of thirteen named sites leaving the
`locality` population. The thirteenth stayed because the registration's own conservative clause said it
must, and the arithmetic that named it had not applied that clause. The owner accepted the letter rather
than reverting two mechanisms over one site, on the record, and registered this in the same breath: the
refinement is written down BEFORE it is built, and it is the reason the acceptance is not a precedent for
moving a band.

**The mechanism.** Source 1 of Phase 5 reads an absolute Python import binding as EXTERNAL only when
`resolvePreciseInclude` maps it to no indexed file AND its head segment names no `.py` stem and no
directory anywhere in the indexed tree. That last clause is a whole-tree name test, which is why
`from collections import OrderedDict` reads UNKNOWN inside astropy: `astropy/utils/collections.py` exists
somewhere. But a package importable as a bare head segment from the crawl root sits at DEPTH 1 or 2 of
that root (`collections.py`, or `collections/__init__.py`); `astropy/utils/collections.py` is depth 3 and
is importable only as `astropy.utils.collections`. The probe therefore restricts the existing clause to
candidates at depth ≤ 2 from each crawl root, leaving every other part of the rule untouched. A root
whose import path is genuinely deeper (a `src/` layout rooted one level down) is the case this could get
wrong, so the probe additionally accepts a candidate at any depth whose PARENT chain is unbroken by
`__init__.py`-less directories — stated here because it is the clause that decides whether this is
precision or a new false-external.

**Bands, fixed before any code and never moved after a number.** Measured with
`bench/scip_pin_precision.py` + `bench/scip_match_diag.py` against the same SCIP oracles Phase 4b and
Phase 5 used, on astropy-14365 with 12907 as the stability check.
1. `table/table.py:2235` `OrderedDict.__getitem__(…)` leaves the `locality` population, counted
   `@external`; Phase 5's other twelve sites are unchanged.
2. **No new false external.** Veto precision stays ≥ 0.99 on both corpora (Phase 5 measured 0.996 and
   0.993); every disconfirmation the probe adds is read at source and named in the RUN.
3. `ambiguous=` within +0.5% on all four corpora at their pins (a tighter band than Phase 5's +2.0%,
   because this refinement removes edges rather than adding a mechanism): ripwire `src/` on
   `git archive <base> src`, ugrep / rocksdb / duckdb in `rw-lane-ab2-corpora`.
4. Full-oracle `locality` precision does not fall on either corpus (Phase 5 measured 0.836 pooled,
   n = 122, and Phase 4's pooling rule still carries this stratum).
5. A new gate arm in `test/externalvetocheck.sh`, RED first, fixing the shape directly: a fixture with a
   top-level `collections.py` (depth 1, in-repo evidence, MUST NOT be vetoed) beside a nested
   `pkg/utils/collections.py` (depth 3, no in-repo evidence for a bare `collections` import, MUST be
   vetoed), plus the `src/`-layout case of the paragraph above.
6. Determinism ×2, ASan on the fixture, xmllint, `--quality-delta --scope='src/*'` gating 0.

**NEGATIVE consequence, stated now.** If band 2 or 4 misses, the depth restriction does not ship and the
whole-tree clause stands as Phase 5 wrote it — the conservative reading keeps an edge, which is the side
of the trade this project already chose. A miss is recorded here as a negative result, not retried with a
different depth until it passes.

## Member variables as symbols + `--uses=Owner.field` — the member-variable round (card A3), PRE-REGISTERED 2026-09-02 (before any corpus number)

**What this registers.** ARISE-bibliography RANK-A card A3 — CodexGraph's FIELD schema element: a class's
member variables as first-class symbols, with their read and write use-sites resolved per site, so
`--uses=Owner.field` answers "who writes this member". Before this round `./build/ripwire . --uses=Symbol.name`
refused (SymKind had no Field) and the only route to a member's writers was the name-wide union of every
`name` in the tree. This section fixes the contract, the fixture gate, the corpus floor and the disclosed
limits BEFORE the floor is measured; the floor's result is appended below it, whatever it is.

**The contract (all of it gate-pinned in `test/fieldusescheck.sh` on `test/fieldusesfix`, none of it an
accuracy claim).** (1) A new kind `t="field"` (SymKind::Field, appended after Macro) for a per-object data
member: C/C++ non-static `field_declaration` inside a class/struct/union body; Python the first `self.x = …`
assignment in a method (one symbol per class and name; later assignments are `role="write"` sites) and an
annotated class-body attribute `x: T [= v]` (re-kinded from `var` — same sites, honest kind). Canonical id
`path::Owner::field`; selector spellings `Owner.field`, `Owner::field`, the id. Static data members are NOT
fields (a class-static constant keeps its `var` row; a mutable static member is not extracted); owner-less
fields (anonymous struct/union) are dropped. (2) Use-sites: the SAME `<u role= p= [in_id=]/>` row `--uses`
prints, plus `amb="K"` on a row the resolver could not pin to one owner. `write` = assignment target,
compound assignment, increment/decrement; **pass-by-non-const-reference and address-of are NOT claimed as
writes.** Resolution is name-based like the rest of the graph, per site: `this->f` / `self.f` / bare `f`
inside the owner's own methods pin to the owner; `v.f` / `v->f` pins through v's recorded declared type (a
typed local, a parameter, a range-for variable, a reference local, or a member of the enclosing class via
the S5-E field-type table — the parameter/range-for/reference-local types are a NEW binding kind,
`LocalBindKind::ParamType`, consumed by this index ALONE so no call edge moves); otherwise every owner
declaring `f` is a candidate and the row carries `amb=K`. **There is deliberately no S6-C locality
tie-break on a field site** — the locality-pinned population is the one resolver decision no instrument
has measured (the census section above), and a field answer is read row by row where a wrong pin is a
wrong line. (3) `--uses=Owner.field` answers; a bare `--uses=field` whose every definition is a field of
two or more owners REFUSES listing the `Owner.field` spellings (the `--edit-check` ambiguity pattern; MCP
`uses` speaks the same message); a bare name with exactly one field owner answers with the member form; a
bare name mixing field and non-field definitions keeps the historic name-wide union. (4) `--nonlocal-state`
keeps EXCLUDING instance fields — by definition, disclosed on its legend — and gains precision from the
same facts: a member access (`recv != None` on a Read/Write ref) and a bare name the enclosing method's own
class declares as a field are no longer charged to a same-named global (the fixture's `int count` global
vs `Counter.count` / `Gauge.count`). No toggle shipped; see the deviation note in the lane report. (5) The
member-form legend discloses, per run: no alias analysis (a field reached through a copied pointer or
reference is missed — `int* alias = &c.count; *alias = 5;` is the fixture's pinned known miss, arm C), a C
macro expanding to a member access, an inherited field named bare in a derived class's method, a field
named inside a lambda tree-sitter scopes outside the method, `.c` bodies (the value-use pass is
C++/ObjC/Python: C struct fields are symbols, their `.c` use-sites are not indexed), static data members;
languages not served refuse with the language name (`--uses=Box.width` on a Go struct: "'Box' is a
lang=go type"). (6) `--help` carries the form under `--uses`.

**The fixture gate, red first.** `test/fieldusescheck.sh` was written and run RED against the pre-round
binary (21 PASS / 43 FAIL at 8e186bb: no `t="field"` rows, every member selector refused) before any
extraction code. The C++ fixture holds 7 fields across 2 classes with two SAME-NAMED members (`count`,
`label`), reads and writes inside and outside the owners' methods, a parameter shadowing a field, a
same-named file-scope global, a typed-parameter receiver, a member-of-the-enclosing-class receiver, an
untyped template receiver (the registered `amb="2"` row), and the alias miss; the Python fixture holds
`self.x` fields in two classes sharing a name plus an annotated attribute; a Go file carries the refusal
case. Every expected row is hand-derived in the gate's header. The gate also pins: determinism, warm ==
cold, xmllint, no `<c>` edge on a field row, the nonlocal-state precision, and that every attribute the
member form emits is defined in the legend it prints.

**Corpus floor — PRE-REGISTERED, on the D4-pinned duckdb `19864453` (checkout
`rw-lane-ab2-corpora/duckdb`, verified `git rev-parse --short=8 HEAD` == `19864453`).** Twelve member
variables chosen by READING the headers (grep for data-member declarations in `vector.hpp`,
`data_chunk.hpp`, `physical_operator.hpp`, `expression.hpp`; no tool run before this paragraph was
written): `Vector.data`, `Vector.validity`, `Vector.type`, `Vector.vector_type`, `Vector.buffer`,
`Vector.auxiliary`, `DataChunk.count`, `DataChunk.capacity`, `DataChunk.data`,
`PhysicalOperator.sink_state`, `PhysicalOperator.op_state`, `Expression.return_type`. `Vector.data` and
`Vector.validity` are declared by more than one duckdb class (`UnifiedVectorFormat` declares both), so
they are the registered same-name cases. THE FLOOR: each selector must resolve to exactly one field
(`defs="1"`, `member=` echoing the owner) and report **at least one `role="write"` site**, pinned or
`amb=`; the accept band is **≥ 10 of 12** meeting both. Reported beside it, per field, never folded into the
verdict: `count=`, `pinned=`, `amb_sites=`, `owners_of_name=`, and for the whole corpus the flagless-map
`symbols=` delta and the wall time of one warm `--uses=Owner.field`. A field that misses is a disclosed
number; the definition of "field" or "write" is not widened to make it pass.

**Token cost, pre-registered shape.** Reported on ripwire's own tree: the flagless map's byte count and
`symbols=` on `.` and on `src/` before/after, the count of top-200 rows that changed, and `--uses=name`
(the union, unchanged contract) before/after. If the flagless map grew by more than 5% the field rows would
move behind `--uses`/`--nonlocal-state`; the measured delta decides, and the result is recorded below.

**RESULT — the corpus floor, measured 2026-09-02 after the registration above (dev build of this lane's
head, `ripwire <duckdb> --uses=Owner.field --limit=100000`, warm cache after one cold run; the checkout is
`19864453`).** **12 of 12** registered fields resolve to exactly one field (`defs="1"`, `member=` echoing the
owner) and report at least one `role="write"` site — the floor (≥ 10 of 12) is met. Per field
(count / pinned / amb_sites / owners_of_name / write rows): `Vector.data` 475 / 62 / 413 / 49 / 49;
`Vector.validity` 116 / 29 / 87 / 6 / 2; `Vector.type` 1141 / 13 / 1128 / 116 / 67; `Vector.vector_type`
13 / 13 / 0 / 1 / 8; `Vector.buffer` 71 / 31 / 40 / 18 / 13; `Vector.auxiliary` 103 / 87 / 16 / 2 / 24;
`DataChunk.count` 609 / 4 / 605 / 82 / 144; `DataChunk.capacity` 51 / 10 / 41 / 24 / 15; `DataChunk.data`
1477 / 1064 / 413 / 49 / 36; `PhysicalOperator.sink_state` 67 / 67 / 0 / 1 / 4; `PhysicalOperator.op_state`
7 / 7 / 0 / 1 / 1; `Expression.return_type` 844 / 22 / 822 / 18 / 168. Read honestly: on a name declared by
many owners (`type` × 116, `count` × 82) the answer is MOSTLY `amb=` rows — duckdb reaches its members
through `unique_ptr<DataChunk>`, `auto &`, `reference<T>` and template-wrapped receivers whose written type
the ParamType/Type capture does not decode (`writtenTypeOf` records only a plain or qualified type
identifier), so the split is the disclosed truth of what the resolver can see, not a pin. Where the receiver
is a plain typed local, parameter, range-for variable or reference local, or the field is uniquely named
(`sink_state`, `op_state`, `vector_type`), the answer pins. The flagless map on duckdb: `symbols=` 61178 →
71173 (+9995 fields), `edges=` 84701 → 85071 was the FIRST measurement and is the reason fields are now
excluded from the call resolver's name tables (a field was a candidate of every same-named call — `v.data()`
minted edges into 49 `data` members); with that fix the call graph is byte-identical to the pre-round binary
on the same tree (verified per-symbol on ripwire `src/`: 4414 non-field symbols, 0 callee-name differences,
identical `edges=`/`ambiguous=`/`unresolved=`). One warm `--uses=Vector.data`: 0.42 s wall.

**RESULT — token cost, measured on ripwire's own tree, SAME tree under both binaries (the pre-round
8e186bb build vs this lane's head).** Flagless map `.`: 21 862 B → 21 906 B (**+44 B, +0.20%**),
`symbols=` 12 663 → 16 447, `edges=`/`ambiguous=`/`unresolved=` identical (15 308 / 5 611 / 3 742), **0 of
the 200 rows changed** and 0 field rows reached the top 200. `src/`: 23 320 B → 23 364 B (+44 B, +0.19%),
`symbols=` 4 647 → 8 139, 0 rows changed. Well under the registered 5% line, so fields stay ordinary
symbols (isolates in the graph, like `var` constants) rather than moving behind a flag. `--uses=name` (the
name-wide union, contract unchanged): 11 048 B / count=183 → 12 273 B / count=811 — the member sites the
old index never captured. `--uses=Symbol.name` on `.` (cold): count=386, pinned=236, amb_sites=150,
owners_of_name=58, 0.09 s warm. The rich-cache blob of a tree indexed by an EARLIER binary of the same
parserVer is stale but "valid" — a development-only trap this lane hit (pinned counts read 109 warm vs 236
cold until the blob was purged); parserVer 75 vs the shipped 74 means no released cache can hit it.

**Deviation, disclosed.** Contract item (4) offered "stop excluding instance fields, or a disclosed toggle"
for `--nonlocal-state`; this lane shipped neither a widening nor a flag. Fields stay excluded BY DEFINITION
(the lens's own header: a cell is linkage-scoped state), the legend now says so and points at the member
selector, and the lens gained the precision the fixture pins (arm G). A `--nonlocal-state` toggle would be
a new flag with its own help/legend/flag-surface footprint; it is left for a round that wants it.

**THE SIDE-TABLE RULE — orchestrator decision 2026-09-02, registered here as the contract (supersedes the
"fields stay ordinary symbols" conclusion of the token-cost result above).** The merged-tree battery went red
on ten gates (moduleconstcheck, atomscheck, contextratiocheck, docdemotecheck, exemplarconfcheck,
nestedqualcheck, treecheck, adaptivecheck, compactroutecheck, perfharnesscheck), every one because field
symbols had entered the GENERAL symbol universe: a field owned an atom finding, became a context-ratio unit,
displaced an exemplar choice, moved a fixture's symbol count, drifted the --for/--recall/--no-route goldens.
The rule now: **field symbols are indexed for use-site resolution and addressable ONLY through the
member-selector surfaces** — `--uses=Owner.field` (also `Owner::field` and the canonical id), the bare-name
refusal that lists the `Owner.field` spellings, `--nonlocal-state`'s disclosure and exclusion, and
`test/fieldusescheck.sh`. They do NOT enter the flagless map rows or its `symbols=` count, PageRank /
`--for` / `--recall` / `--no-route` / `--exemplar` ranking, adaptive-cut candidates, lint/atom finding
attribution (the enclosing NON-field symbol owns the finding), context-ratio units, `--tree` counts,
`--outline`, the quality-delta symbol universe, or any fixture symbol count. **Implementation:** a field is
never a member of `IngestResult::symbols`; it lives in `IngestResult::fields`, a side table with its own
index space (`FieldId`), partitioned out of the raw defs before symbol ids are assigned
(`ingest_model.h::partitionFieldDefs` / `assignFields`), so every array aligned 1:1 with symbols (the lex
CSR, the def-span index, the atom/lint attribution, every count) is blind to fields by construction rather
than by a per-verb filter. `graph.h::resolveFieldSelector` is the ONLY reader of the table besides
`--nonlocal-state`'s exclusion set. Two consequences applied in the same commit: (a) the Python annotated
class attribute (`x: T = v`) STAYS a `t="var"` map symbol — the pre-round contract pyshapecheck pins in the
map — and is not re-kinded (the `self.x` instance attribute is the one Python field shape); (b)
`--context-ratio` skips a member-access Read/Write ref (`recv != None`), which resolving by NAME would have
bound `s.name` to every function called `name` — its calibrated input stream is the pre-round one. The map
legend's `t=` list no longer names `field` (fields never appear in the map); the token stays in the `--uses`
member-form legend only. **The proof of the rule, measured**: on the same tree, the 8e186bb binary and this
lane's head are BYTE-IDENTICAL for the flagless map (`.` 21 906 B / 185 rows; `src/` 23 320 B / 186 rows;
`test/fixture` 1 923 B; `test/fieldusesfix` 2 691 B / 27 rows), `--for` (routed and `--no-route`),
`--recall`, `--exemplar=fn`, `--tree`, `--lint`, `--context-ratio`, `--adaptive`, `--hotspots`, `--metrics`,
`--dead-code`, `--clones`, `--callers`. Three verbs differ ON PURPOSE and only where the lane registered a
change: `--uses` (the one-sentence member-form pointer in the shared legend; the name-wide union now carries
the member sites), `--nonlocal-state` (the instance-field disclosure sentence and the precision exclusion).
The 44ac095 golden re-pins this rule made unnecessary (test/golden.xml, fillordercheck's est_tokens) are
reverted to their 8e186bb bytes; the qschemetrip re-pin stays (it is driven by the kParserVer declaration
line, which legitimately moved to 75) and so does the README/EVALS gate count (fieldusescheck exists).

## Freshness disclosure on a cached answer (card A3) — PRE-REGISTERED 2026-09-03 (before any measurement)

**What this registers.** ARISE-bibliography RANK-A card A3, the shape Graft spends ~3 ms per query on: an
answer served from a warm index should say, on its own root, whether it still describes the tree the agent
is editing — so the agent never has to ask, and never has to run a second command to find out. The
capability is a disclosure, not a new index: `fresh="ok"` when the file set behind the answer was
re-validated during this query, `reindexed`/`stale_files`/`changed_files` when it was not clean. This
section fixes the surface inventory, the bands and the rejection rule BEFORE any number, and the results
are appended under it whatever they are.

**The surface inventory this lane must produce first, with argv.** "Which surfaces can actually serve a
stale answer today" is a measurement, not a premise, and the design depends on the answer:

| surface | what it re-validates per query | can it serve stale? |
| --- | --- | --- |
| CLI cold (`--no-cache`) | reads and hashes every crawled file | to be measured |
| CLI warm (default TMPDIR cache, or `--cache=PATH`) | crawl + per-file `(mtimeNs, sizeBytes)` stat gate + the racy rule; read+hash on any mismatch | to be measured |
| `--mcp` warm reuse | `mcpStale()` — the watched-dir mtime sweep plus the per-file mtime+size loop — then a rebuild when either moves | to be measured |

**Band 1 — cost.** The re-validation must cost **under 5% of warm wall-clock** on a ~1500-file tree. A
LEDGER row in `bench/PROFILE.md` with the argv, never a red gate (the no-perf-budget-gates rule). If the
honest check turns out to be one the surface already runs, the row says so and reports the delta it
actually added, which may be zero — a zero is a result, not a pass by default.

**Band 2 — induced staleness, four fixtures, 100%.** Against a long-lived server holding a warm index:
(a) EDIT a file, (b) DELETE a file, (c) ADD a file, (d) `touch` a file **without changing its content**.
Each must report the right attribute. (d) is the discriminating one: a `touch` moves mtime, so a
stat-keyed check is entitled to re-validate — but it must **not** claim anything was stale, because no
byte changed. The contract is therefore: (d) may disclose that a re-validation ran, and must disclose
`changed_files="0"` alongside it, so "the index was refreshed" and "the tree changed" are never conflated.
An implementation that reports (d) the same way it reports (a) fails this band.

**Band 3 — byte-identity, and the rejection rule.** Two halves, and the second is registered as
rejectable in advance:

- A **timing** value (`revalidated_ms`) MUST NOT enter the output unless an explicit gate excludes it from
  the determinism comparison. The default is to ship the boolean alone and record the timing half here as
  REJECTED with its reason.
- The CLI map's warm output is asserted **byte-identical to its cold output** (`docs/ARCHITECTURE.md` §2,
  and the determinism gate in `CONTRIBUTING.md`). Any attribute whose value depends on the CLI's own cache
  state therefore cannot be emitted on the CLI at all. If the inventory shows the CLI re-validates on every
  invocation, the only CLI-legal value of the attribute is a CONSTANT, and a constant attribute on the map
  root buys no information for its bytes (G4) while re-pinning `test/golden.xml`, 24 recorded captures in
  `docs/COMMANDS.md` and `docs/captures/`, and 15 gates. That half is then recorded here as REJECTED with
  the measurement that justifies it — not shipped quietly and not silently dropped.

**Gate.** `test/freshnesscheck.sh`, written and run RED before any implementation code: the four band-2
fixtures plus a mutation control (a build that never re-stats between queries must go red) plus the
clean-warm control (a query over an untouched tree must NOT claim a re-index).

**What this section will NOT claim.** No accuracy number, no ranking effect, and no closure of the
same-`(mtimeNs, sizeBytes)` residual that `mcpStale()`'s comment already documents as irreducible without
a whole-tree re-read. If the inventory reproduces that residual on a surface whose own gate header claims
immunity to it, the finding is recorded here and the claim is corrected — a stale honesty claim is the
same defect class as a stale answer.

### The card A3 result, measured 2026-09-03 against the bands registered above

**The surface inventory, with argv — and it changed the design.** Every row was reproduced, not reasoned
about. The reproduction that matters uses a mtime pinned OLD on both sides, so the cache blob's own write
time is strictly newer than the file's recorded mtime and the racy rule does not fire:

```
mkdir tree && printf 'int alphaaa( int x ) { return x + 1; }\nint caller( void ) { return alphaaa( 2 ); }\n' > tree/a.c
touch -t 202601011200.00 tree/a.c
ripwire tree --cache=C --top-k=20          # -> n="alphaaa" n="caller"
printf 'int betaaaa( int x ) { return x + 1; }\nint caller( void ) { return betaaaa( 2 ); }\n' > tree/a.c
touch -t 202601011200.00 tree/a.c          # same byte length, mtime restored
ripwire tree --cache=C --top-k=20          # -> n="alphaaa" n="caller"   <-- STALE
ripwire tree --top-k=20                    # -> n="alphaaa" n="caller"   <-- STALE (default TMPDIR cache too)
ripwire tree --top-k=20 --no-cache         # -> n="betaaaa" n="caller"   <-- correct
```

| surface | what it re-validates per query | can it serve stale? |
| --- | --- | --- |
| CLI cold (`--no-cache`) | reads and hashes every crawled file | **no** |
| CLI warm (default TMPDIR cache, or `--cache=PATH`) | crawl + per-file `(mtimeNs, sizeBytes)` stat gate + racy rule | **yes** — the same-`(mtime, size)` edit above, on BOTH warm paths |
| `--mcp` warm reuse | `mcpStale()`: watched-dir mtime sweep + per-file mtime+size loop, rebuild on any move | **yes** — the same residual, and nothing else |

Two findings fell out of that table, and both changed what this lane shipped.

**Finding 1 — the residual is shared, and a gate header said otherwise.** `test/cachehashcheck.sh`'s header
generalised its own passing arm into immunity: *"the CLI path re-crawls and re-hashes bytes every
invocation, so an equal mtime never masks a content change."* The re-crawl half is still true; the re-hash
half stopped being true when the A4-P7 stat-gate landed, and the run above is the counterexample. What that
gate actually proves is the case it stages — its edit changes the byte LENGTH, and the SIZE discriminator
catches it. The header is corrected to say that, and the residual is now executable rather than prose:
`test/freshnesscheck.sh` arm 6 reproduces it, pins `--no-cache` as the escape hatch and pins that a
length-changing edit under a restored mtime IS caught. This is the honesty-claim half of the same defect
class as a stale answer, which the registration said would be recorded if it turned up. It turned up.

**Finding 2 — the re-validation already existed everywhere; only the disclosure was missing.** No surface
lacks a per-query check. The CLI re-crawls every invocation; the MCP server sweeps every request and
rebuilds before answering. So the design registered above ("a per-query re-stat … when stale, either
transparently re-index or serve with `stale=1`") resolves to: the re-index policy, already in force on both
surfaces, finally said out loud. `_fresh` never takes the value `"stale"` on either surface, because
neither surface serves-and-flags.

**Band 2 — induced staleness: 4/4, plus both controls.** `test/freshnesscheck.sh`, written and run RED
first (16 FAIL at `2898e51`, every one because the fields did not exist).

| fixture | `_fresh` | `_stale_files` | `_changed_files` |
| --- | --- | --- | --- |
| first build | `ok` | absent | absent |
| clean re-query (CONTROL) | `ok` | absent | absent |
| EDIT one file | `reindexed` | 1 | 1 |
| DELETE one file | `reindexed` | 1 | 1 |
| ADD one file | `reindexed` | **0** | 1 |
| `touch`, content identical | `reindexed` | 1 | **0** |

The two bold cells are the band's discriminating clause and they point opposite ways, which is why the
disclosure is two counts and not one. An ADD moves no INDEXED file's stat — its directory's mtime is what
moved — so `_stale_files:0` is the true answer, and a fused counter would have to lie in one direction or
the other. A `touch` moves a recorded stat and not one byte, so `_stale_files:1, _changed_files:0` says
exactly what happened: the check fired, correctly, and nothing was stale. The gate corroborates that zero
independently by asserting the verb's answer is byte-identical across the pass.

**Band 1 — cost: met, and the band's premise was wrong.** Full ledger, argv and instrument in
`bench/PROFILE.md` ("card A3 freshness disclosure"). On a **2377-file** tree, HEAD vs base `3eec040`, five
alternating trials: warm requests **10.52 ms vs 11.17 ms** and rebuilds **479.4 ms vs 499.2 ms** — both
deltas NEGATIVE, i.e. the added cost does not resolve against a base arm whose own trials spread 9.9–17.3
ms warm. Band 1 asked what fraction of the warm request a NEW check would be; the inventory says the check
was already there, so the number worth recording is the inverse: **≈4.4 µs per indexed file**, derived from
0.51 ms at 120 files against 10.52 ms at 2377, which puts **~95% of a warm MCP request in the freshness
sweep**. A warm request on a tree this size is very nearly nothing but the re-validation that was already
running silently.

**Band 3 — byte-identity: shipped as the boolean, with BOTH registered halves REJECTED as registered.**

- *`revalidated_ms` — REJECTED.* Not emitted. A per-request wall time is exactly the kind of value the
  determinism contract has no tolerance band for, and the registration named shipping the boolean alone as
  the default rather than as a retreat. The timing lives where timings live: `RIPWIRE_MCP_TIMINGS`'s
  env-gated stderr line, and the ledger above.
- *A CLI attribute on the map root — REJECTED, and the measurement is the reason.* The CLI re-crawls every
  invocation, so its only truthful value is a CONSTANT `fresh="ok"`. Warm output is asserted byte-identical
  to cold, so nothing that varies with the CLI's own cache state may be emitted there at all — the one
  genuinely informative variant (how many files were trusted on stat alone this run) is cold/warm-varying by
  construction and therefore illegal. A constant attribute on the map root buys no information for its
  bytes (G4) while re-pinning `test/golden.xml`, 24 recorded captures across `docs/COMMANDS.md` and
  `docs/captures/`, and 15 gates. The CLI's freshness story is instead told where it is true and free: the
  reproduction above, `--no-cache` as the escape hatch, and `test/freshnesscheck.sh` arm 6.

**What this section does not claim.** No accuracy number and no ranking effect: `_fresh` is process
history, never tree state, and like `_reingest` it is deliberately excluded from every warm-equals-cold
comparison. The same-`(mtime, size)` residual is NOT closed on either surface, and the ledger above prices
why: the whole-tree re-read that would close it lands on a warm request that is already ~95% stat sweep.

## Closing the same-`(mtime, size)` warm-path residual (card A3 follow-up) — PRE-REGISTERED 2026-09-03 (before any measurement)

**What this registers.** The card A3 section above reproduced, on argv, a warm-path answer that is STALE:
a content edit that preserves the byte LENGTH and restores the mtime to a value strictly older than the
cache blob's own write time is trusted by the A4-P7 stat gate and never read. `test/freshnesscheck.sh` arm 6
reproduces it with an OBSERVED branch that passes on either outcome, and `test/statgatecheck.sh` case (b2)
records it as an informational `note`. Two claims in the tree say it cannot be closed cheaply:
`src/mcpindex.h`'s `mcpStale()` comment — *"Catching it is provably impossible without READING the file's
bytes"* — and the A3 ledger that prices that read at ~13x the warm sweep. This section registers the
mechanism, the bands and the rejection rule for closing it, BEFORE any number, and the result is appended
under it whatever it is.

**The mechanism under test: `st_ctime`, not a content hash.** `::stat` already returns three timestamps and
the warm path already calls it once per file, so the candidate discriminator costs **zero additional
syscalls and zero file reads**. `st_ctime` (inode *change* time, not creation time on POSIX) moves on any
write to the file AND on the `utimes()` that a `touch -r` / editor "preserve mtime" / `cp -p` restore
performs, and POSIX exposes no interface for setting it — an unprivileged process cannot restore it the way
it restores mtime. The design is therefore: record `ctimeNs` beside `(sizeBytes, mtimeNs)` at the moment a
file is read+hashed, and require it to match EXACTLY for the stat gate to trust the cached parse. Two
surfaces carry the same residual and both are in scope: the CLI incremental cache (`src/ingest_cache.h`
`FileFacts` + the gate in `src/ingest_prewarm.h`; a per-file record change ⇒ `kCacheVersion` bump ⇒ old
blobs self-heal via full reparse) and the warm `--mcp` index (`mcpStale()` / `mcpStaleFileCount()`, a new
`McpIndex::fileCtime` parallel to `fileMtime`/`fileSize`).

**Band 1 — correctness, HARD, no OBSERVED branch left.** The arms that must flip, and the arms that must
not move:

- `test/freshnesscheck.sh` arm 6: the OBSERVED branch becomes **HARD** in the direction shipped. Shipping
  the discriminator makes it *"the same-`(mtime, size)` edit IS caught on the warm CLI path"*; refusing
  keeps the residual reproducible and adds a HARD assertion on the disclosure instead. Both existing HARD
  halves (`--no-cache` correct, a LENGTH-changing edit under a restored mtime caught) stay HARD.
- `test/statgatecheck.sh` case (b2): the informational `note` pair becomes a **HARD** assertion. The header's
  "HONEST DISPOSITION … NOT asserted as detected" paragraph is rewritten to what the code then does.
- A NEW arm on the `--mcp` surface staging the same attack against a long-lived warm server: same byte
  length, mtime restored, no sibling add/delete to bump a watched directory's mtime. It must answer with
  the POST-edit symbol and disclose `_fresh:"reindexed"` with `_changed_files:1`.
- Non-regression, all must stay green with no edit to their assertions: `statgatecheck` (a)/(b1)/(b3)/(c)/(d),
  `racymtimecheck` (both arms — the racy rule is NOT replaced, it still covers the coarse-granularity case
  the recorded ctime cannot, on a filesystem whose ctime granularity is also coarse), `cachehashcheck`,
  `tornreadcheck`, `savecachecheck`, `cacheisolationcheck`, `cachefuzzcheck`, `portablecachecheck`,
  `mcpstalecheck`, `mcpincrementalcheck`, `postingscheck`, `qextractionkeycheck`, `qschemetripcheck`.

**Band 2 — cost, a LEDGER row in `bench/PROFILE.md`, never a red gate** (the no-perf-budget rule). The
ceiling this lane is willing to state, and the rejection rule attached to it:

- On a settled tree (nothing edited between two runs) the discriminator must add **zero file reads** — it is
  one integer comparison on a `struct stat` already in hand. Measured as warm wall-clock on **two** trees:
  ripwire's own (`files=1505` as this binary indexes it, `--exclude=bench/external`) and a large one
  (`rw-lane-ab2-corpora/duckdb`, ~5.1k files, read-only, never modified by this lane). Arms alternated
  HEAD / base `1c6fdf4`, five trials each, medians reported with the base arm's own trial spread beside
  them so a delta inside the noise floor is reported as such and not as a win.
- **REJECTION RULE, registered in advance:** if the warm delta on either tree lands OUTSIDE the base arm's
  own trial spread in the slower direction, or if a settled warm run re-reads any file it did not re-read
  before, the fix is REJECTED and this lane ships option (b) — the refusal — instead: the stat gate is kept
  and its blind spot becomes a disclosed one.
- The alternative the task named, **content-hashing every stat-equal file on the warm path (option (a)
  proper)**, is measured as its own arm on the same two trees, produced by a throwaway build that forces
  `statMatches=false` (i.e. every stat-equal file is read+hashed and its cached FACTS are still reused, so
  the arm prices the read+hash and not the reparse). That arm is the control that says whether hashing
  defeats the stat gate's purpose. It is a measurement, not a candidate: it is not committed.

**Band 3 — determinism, format and portability.** All HARD:

- `cold == warm == warm` byte-identical on both trees, and `xmllint --noout` clean on both.
- ASan (`-DRIPWIRE_ASAN=ON`, `LSAN_OPTIONS=suppressions=lsan_suppressions.txt`) over a cold run AND a warm
  run that engages the new comparison — the warm path is the one that changed.
- A `kCacheVersion`-1 blob (i.e. a blob written before this change) must self-heal to a full reparse and a
  byte-identical answer, never a crash and never a wrong answer — `portablecachecheck` case (c) already
  stages exactly this by doctoring the version field, and it must stay green with the version it now
  doctors down FROM.
- The cache-key portability contract is **unchanged**: keys stay root-relative (`relForHash`), so a
  committed `--cache=FILE` artifact consumed under a different checkout path still warm-hits at the
  CONTENT-HASH level (`portablecachecheck` (a): byte-identical to a cold run at B). What such a transported
  cache may lose is stat-gate ELIGIBILITY — `ctime` is not preserved by `cp`, `tar` or `rsync` on any
  platform, so a transported tree falls through to read+hash and then hits on the hash. That is a cost, not
  a correctness change, and it is the honest posture: a tree whose inodes we did not observe being written
  is exactly the tree whose stat identity we must not trust. `qextractionkeycheck` gates the
  `kIngestCacheVersionMirror` half in the same commit.

**What this section will NOT claim.** Not "the residual is closed", unconditionally. `st_ctime` closes it
against every unprivileged same-`(mtime, size)` edit on a filesystem that maintains ctime (APFS, ext4,
btrfs, xfs, HFS+). It does NOT close it against a caller who can move the system clock backward, against
raw block-device manipulation, or on a filesystem that does not maintain a distinct ctime (FAT/exFAT, some
SMB/network mounts) — there the gate degrades to exactly today's behaviour, which is why the racy rule is
kept rather than replaced. The new boundary is stated in the gate headers as the boundary it is, and
`--no-cache` remains the unconditional escape hatch. No accuracy number and no ranking effect is claimed:
this changes WHEN bytes are read, never what is extracted from them.

### The result, measured 2026-09-03 against the bands registered above — SHIPPED (option (a)'s cheap discriminator, not its content hash)

**The mechanism that shipped.** `st_ctime`, recorded beside `(sizeBytes, mtimeNs)` at the moment a file is
read+hashed and required to match EXACTLY. `::stat` already returns it and every one of these paths already
called `::stat` once per file, so the fix costs **no syscall and no file read**. It landed on all three warm
surfaces that shared the residual, because a fix to one is not a fix to the others: the CLI incremental
cache (`FileFacts` + the A4-P7 gate; `kCacheVersion` 13 → 14, so v13 blobs self-heal), the `--grep`
span-tier memo (`kSpanTierMemoVersion` 1 → 2), and the warm `--mcp` index (`McpIndex::fileCtime`,
`mcpStale()`, `mcpStaleFileCount()`). The `--mcp` half needed the CLI half: an `--mcp` rebuild re-ingests
through the same on-disk cache, so a build that fixed only `mcpStale()` would have decided "stale", rebuilt,
and then been handed the pre-edit facts by `ingest()`'s stat gate. `freshnesscheck` arm 7 is the arm that
proves both halves at once.

**Band 1 — correctness: every registered arm flipped, and one arm was added that the registration did not
foresee.**

| arm | before | after |
| --- | --- | --- |
| `freshnesscheck` arm 6 (warm CLI) | OBSERVED, passed either way | **HARD** — the same-`(mtime, size)` edit IS caught |
| `freshnesscheck` arm 7 (warm `--mcp`) | did not exist | **HARD** — `_fresh:"reindexed"`, `_stale_files:1`, `_changed_files:1`, post-edit symbol served |
| `statgatecheck` (b2) | informational `note` pair | **HARD** — the backdated same-size edit is detected |
| `statgatecheck` (e) | did not exist | **HARD** — a `chmod`-to-unreadable keeps the cached parse |

6 FAIL red-first at `e8af28f`, all green at `ea9a064`. The registered non-regression set is green with no
edit to its assertions: `racymtimecheck` (both arms — the racy rule is kept, not replaced), `cachehashcheck`,
`tornreadcheck`, `savecachecheck`, `cacheisolationcheck`, `cachefuzzcheck`, `portablecachecheck`,
`mcpstalecheck`, `mcpincrementalcheck`, `postingscheck`, `qextractionkeycheck`, `qschemetripcheck` (re-pinned
— `kCacheVersion` is one of the two declaration lines its hash feeds on), plus `cachesplitcheck`,
`clonecachecheck`, `headsnapcachecheck`, `qsnapcachecheck`, `qsnapprefetchcheck`, `docmdcachecheck`,
`evictioncheck`, `greptiercheck`, `grepfastcheck`.

**The arm the registration did not foresee, and the gate that caught it.** `st_ctime` moves on
`chmod`/`chown`/xattr/rename as well as on a write. Those all fall out of the stat gate into the read+hash
path — correct, and cheap, since the re-hash then agrees with the record. Except when the metadata change is
what made the file UNREADABLE: the read fails, and the first implementation dropped every symbol the file
had, turning a `chmod 000` into a silently partial index. `postingscheck` (d) went red — it makes every
source unreadable on purpose, to prove the warm scorer does not re-read per query, and that instrument
collides with this discriminator. The rule that shipped: **an unreadable file whose `(size, mtime)` still
match a non-racy record KEEPS its cached parse** and absorbs the metadata move, because a ctime that moved
alone is not evidence of a content change and serving the last-known parse of a file we could not look at
beats deleting it from the answer. An unreadable file whose size or mtime DID move is still dropped, as
before. Disclosed exposure, stated at the code and in `statgatecheck` (e)'s header: a same-`(mtime, size)`
edit hidden behind a chmod-to-unreadable is served stale — and no cache-free run does better, since
`--no-cache` cannot read it either.

**Band 2 — cost: the fix does not resolve against the noise floor; the alternative costs ~23% of every warm
run.** Full ledger, argv and instrument in `bench/PROFILE.md` ("card A3 follow-up"). Three binaries — `base`
= `1c6fdf4`, `head` = this lane, `hashall` = **option (a) proper**, `head` with `statMatches` forced `false`
so every stat-equal file is read + content-hashed and its cached facts still reused (a throwaway measurement
arm, not committed). Nine trials per tree with the **arm order rotating by trial**.

| tree | `base` | `head` (ctime) | `hashall` (option (a)) |
| --- | --- | --- | --- |
| ripwire, `files=1505` | 62.4 ms (spread 59.8–75.1) | **61.3 ms** (−1.1) | 75.2 ms (**+22.7%** vs head) |
| duckdb, `files=5123` | 219.4 ms (spread 198.5–342.9) | **212.8 ms** (−6.6) | 261.4 ms (**+22.8%** vs head) |

Both `head` deltas are NEGATIVE and both sit inside the base arm's own trial spread: one integer comparison
per file, on a `struct stat` the loop had already filled, does not resolve. The registered rejection rule is
not triggered. `RIPWIRE_CACHE_STATS=1` reports `reparsed=0 reused=1505` and `reparsed=0 reused=5123` for all
three arms on a settled tree — the arms differ only in whether they READ, which is what makes the wall-clock
gap readable as the read cost.

**The rotation is part of the result.** A first pass with a FIXED arm order (base always first, head always
second) reported `head` +19.9 ms on duckdb — outside base's spread, and therefore a REJECT under the rule
registered above. It was position, not code: the within-trial ramp penalises whichever arm runs second. The
fixed-order numbers are discarded and the rotated ones are what is reported. Worth recording because the
registered rejection rule would have fired on a measurement artifact and killed a free fix.

**The verdict on option (a), stated as the task's own question asks it.** Content-hashing every stat-equal
file is *not* more expensive than the parse it saves — `hashall` never reparses, so its penalty is ~23% of a
warm run rather than the 1.1–2.3 s cold parse. It is **dominated**: it costs ~23% of every warm invocation,
and it still closes the residual only for files it can READ, while the recorded ctime closes it for free and
keeps the cached parse of a file that has become unreadable. So the answer to "does hashing every stat-equal
file defeat the stat gate's purpose" is yes, measured: on the common no-change path every file is
stat-equal, so option (a) degenerates to a whole-tree re-read on every invocation, which is the one thing
the gate exists to avoid.

**Band 3 — determinism, format and portability: all green.** `cold == warm == warm` byte-identical and
`xmllint --noout` clean on BOTH trees (ripwire root with `--exclude=bench/external`, and duckdb; the corpus
is left untouched). ASan (`-DRIPWIRE_ASAN=ON`, `LSAN_OPTIONS=suppressions=lsan_suppressions.txt`) cold and
warm over the repo root: `rc=0`, empty stderr, no LSan report — and both changed gates green under
`asan/ripwire`. `portablecachecheck` (c) still self-heals a doctored old-version blob, and (a) still proves
a cache built under root A is byte-identical to a cold run when consumed under root B: the cache-key
portability contract (root-relative `relForHash` keys) is untouched. What a transported cache may lose is
stat-gate ELIGIBILITY, since `ctime` is not preserved by `cp`, `tar` or `rsync` anywhere — it then falls
through to read+hash and hits on the content hash, which is a cost and not a correctness change, and is the
honest posture: a tree whose inodes we did not observe being written is exactly the tree whose stat identity
we must not trust.

**The honesty-claim corrections this lane owed.** Three comments generalised a passing arm into an immunity
the code did not have, which is the same defect class as a stale answer:

* `src/mcpindex.h` — *"Catching it is provably impossible without READING the file's bytes."* Sound about the
  two fields it considered, wrong about the third the same `::stat` returns. Rewritten to say what the check
  now does, what it used to miss, and what is still outside it.
* `test/mcpstalecheck.sh` — the same-`(mtime,size)` corner described as "the documented irreducible
  residual". Corrected: it was wrong about the cost, not about the read.
* `src/ingest_astquery.h` — "THE ONE RESIDUAL" on the span-tier memo. Corrected, and the memo fixed rather
  than only re-described.
* `test/cachehashcheck.sh`'s header (corrected once already this round) now also says why its arm stays
  length-CHANGING: so it keeps fencing the size discriminator specifically instead of becoming a duplicate
  of the arms that stage the length-preserving attack.
* `docs/ARCHITECTURE.md` §2 and `skills/ripwire-mcp/mcp-reference.md` name the triple and the new boundary.

**What this section does not claim.** The residual is narrowed, not abolished. `st_ctime` closes it against
every unprivileged same-`(mtime, size)` edit on a filesystem that maintains ctime (APFS, ext4, btrfs, xfs,
HFS+). It does NOT close it against a caller who can move the system clock backward, against raw
block-device manipulation, or on a filesystem with no distinct ctime (FAT/exFAT, some SMB mounts) — there
the gate degrades to exactly its pre-ctime behaviour, which is why the racy rule is kept rather than
replaced, and both gates print the mounted filesystem when their assertion fails so that case is
diagnosable. `--no-cache` remains the unconditional escape hatch. No accuracy number and no ranking effect:
this changes WHEN bytes are read, never what is extracted from them.

## `--impact`/`--callers`/`--callees` tested/untested row partition (card A6, agent-lsp), PRE-REGISTERED 2026-09-03 (before any measurement)

**What this registers.** ARISE-bibliography RANK-A card A6 — agent-lsp's "who breaks, and which of those
a test reaches" in ONE call: each `<s>` row `--impact`/`--callers`/`--callees` already print gains
`tested="1"` (the house omitted-not-zero spelling — absent means untested, never a literal `tested="0"`,
matching every other `tested=` site in this tree), reusing the identical isTestSymbol-seeded
`forwardReach` `computeQMetrics`'s own `tested=` column runs (`graph.h::testSymbolForwardReach`, now also
`--safe-delete`'s lens, factored so the three callers share ONE traversal rather than three near-identical
copies). The root gains the partition's two counts: `--impact` (a TRANSITIVE reach) carries
`radius_tested=`/`radius_untested=`, reusing the exact vocabulary `--safe-delete` already prints for the
identical measurement over the identical `transitiveCallers` walk (README:1025); `--callers`/`--callees`
(1-hop, never transitive) carry `hop_tested=`/`hop_untested=` — a deliberately DIFFERENT name, because
reusing "radius_" on a 1-hop count would be a false claim of transitivity. The row COUNT is unchanged on
every dialect (XML/columnar/JSON) — a partition, never a filter.

**The band.** On a ≥50-symbol sample of ripwire's own `src/`, the partition must agree, symbol for symbol,
100% with `--test-gate`'s own untested= determination for the identical reach set. Disagreement is a
correctness BUG on whichever verb is wrong, to be reported, not papered over. Gate:
`test/impactpartitioncheck.sh`.

**Why the comparison is apples-to-apples, not two unrelated measurements agreeing by luck.**
`situ.h::computeTestGateFor` calls the SAME `rw::transitiveCallers` `--impact` calls, over its whole
changed-SYMBOL set. BFS reachability is seed-set-monotone-additive: `reach(union of seeds) ==
union(reach(each seed))`, so unioning N separate `--impact=SEED` calls over a symbol set S is
architecturally IDENTICAL to `--test-gate`'s blast radius when its "changed" set is EXACTLY S.
`--test-gate`'s CLI only accepts FILES (not a bare symbol list), so S is chosen as EVERY symbol
`src/graph.h` defines (134 distinct names measured at this lane's head, comfortably over the 50-symbol
floor, and deterministic — `--graph-query='file(all,"src/graph\.h")'` is a fixed query against a file
whose defined-symbol population does not depend on run order) and `--test-gate=src/graph.h` then marks
EXACTLY that same symbol set as changed — one file, no broader superset of "changed" to reconcile. `<u>`
rows carry no line number, so the join key is `(name, root-relative-file)`, normalized on both sides
(`--impact`'s `p="path:line"` vs `--test-gate`'s `p="./path"`); two DIFFERENT same-named symbols in one
file collapse to the same key on BOTH sides alike (measured: 2 such collisions on this sample,
`cochangePartners`/gitmine.h and `want`/crossref.h — a disclosed limit of `--test-gate`'s own row
identity, not a comparison artifact), which is why the gate compares distinct-key SETS rather than raw row
counts. Rows in the changed file itself, and rows in any file `--test-gate`'s own `<t>` listing names, are
excluded from the `--impact` side the same way `--test-gate` excludes them from `<u>` (the changed set is
never its own radius; a test-path row is folded into `<t>`, never listed as untested).

**RESULT — measured 2026-09-03 against the band registered above (dev build of this lane's head,
`test/impactpartitioncheck.sh`, warm cache).** **100% agreement, exact.** `--test-gate=src/graph.h
--limit=5000`: `untested="646"`, 646 raw `<u>` rows / 644 distinct `(name,file)` keys. Unioning
`--impact=src/graph.h:SYM --limit=5000` over all 134 symbols `src/graph.h` defines: every one of those 134
calls reports `capped="0"` (5000 was enough headroom) and satisfies `radius_tested= + radius_untested= ==
reaches=` (the partition's own internal arithmetic) and printed-row-count `== reaches=` (row-count
invariance — the new attribute changed what a row discloses, never how many rows exist). The union of
every row NOT carrying `tested="1"` (644 keys, after the changed-file and test-file exclusions above)
equals `--test-gate`'s 644-key untested set EXACTLY — zero rows on either side without a match on the
other. The complementary claim holds too: no row `--impact` marks `tested="1"` appears in
`--test-gate`'s untested list. MUTATION CONTROL: dropping one arbitrary row from a copy of the
`--test-gate` set before re-running the equality check makes it fail, as expected — proof the assertion
above can discriminate a real regression and is not comparing two accidentally-always-equal sets. No
disagreement found; nothing needed fixing on either verb.

**Byte cost.** Zero on the untested-dominant case: `tested=` is omitted, never spelled `tested="0"`, so an
untested row costs 0 bytes over the pre-A6 shape. `radius_tested=`/`radius_untested=` (impact) and
`hop_tested=`/`hop_untested=` (callers/callees) are two root attributes, present unconditionally (a count
pair, like `importers=`, never a filter a reader must ask for) — `test/graphlegendbudgetcheck.sh`'s
per-verb legend-byte ratchets (`--callers` ≤2700 B, `--impact` ≤3100 B) stayed green with this lane's
legend additions (2551 B / 3004 B measured), so the new vocabulary's OWN definition did not blow either
budget.

## Pre-apply `--edit-check` — the contract preview on an unwritten payload (card A1), PRE-REGISTERED 2026-09-03 (before any fixture or feature code)

**What this registers.** ARISE-bibliography RANK-A card A1 — the capability gortex calls `preview_edit` and
agent-lsp calls `simulate_edit`. ripwire's three edit verbs (`--replace-symbol-body`,
`--insert-before-symbol`, `--insert-after-symbol`, and their MCP twins) write first and are verified after;
`--edit-check=SYM` answers "did I change a contract someone depends on" only once the bytes are on disk.
This round closes that loop from the other side: `--edit-check=SYM --edit-payload=FILE --dry-run` answers the
SAME question about bytes that have not been written. Nothing about the post-hoc verb changes.

**The contract.** The payload is treated as the exact bytes `--replace-symbol-body=SYM
--edit-payload=FILE` would splice over SYM's full definition span `[sigStartByte, endByte)` — the same
`mcpedit::applyEdit` call, the same CRLF harmonisation against the target file's own dominant line ending, so
"what the preview measured" and "what an apply would write" are one function and cannot drift. The spliced
bytes are parsed through the ordinary ingest path; the working tree is re-derived in memory with ONLY that
one file's symbols, references, bindings and routes replaced (symbol ids are contiguous per file, so the
splice is a range swap, not a renumbering heuristic); the call graph is rebuilt over that merged tree; and
the answer is emitted by the SAME `editCheckBundleText()` assembler the post-hoc verb calls. The root
element carries `preview="1"` and the legend carries one sentence stating that the document describes an
UNWRITTEN payload and that no byte was written. The HEAD baseline, the root spelling, the `at=` commit
anchor and the note children are the real tree's throughout — no temporary root reaches the output.

**Refusals — exit 1, a reason on stderr, nothing on stdout.** (1) The payload is unreadable, EMPTY, over
`--max-file-size`, or NUL-bearing — the CLI edit bridge's own four refusals, reused verbatim from one
extracted reader so the preview and the write path cannot word them differently. (2) The payload is
SYNTACTICALLY INVALID: the spliced file's parse holds MORE ERROR/MISSING nodes than the target file's parse
holds today. Stated as a DELTA rather than an absolute, because a file that already parses degraded (a
macro-heavy C++ header) would otherwise make every payload refuse — a refusal that is right about the file
and wrong about the payload. (3) The payload does not define SYM: no definition of that name survives with a
span intersecting the spliced region. (4) SYM is a document heading/section — the edit engine's own kind
guard, because a Section's stored span does not delimit an editable definition. (5) The target is STALE: the
span does not fit the file's current bytes, or the definition's own name no longer occurs inside its
recorded span. (6) SYM is ambiguous — the existing ambiguity refusal, unchanged, listing the spellings that pick
one contract. Two combination refusals: `--edit-check --edit-payload` without `--dry-run` (the preview never
writes; the write verb is named in the message), and `--edit-check --dry-run` with no payload.

**Scope note, recorded rather than papered over.** `--edit-check`'s target grammar is UNCHANGED — bare name,
`file:name`, `Scope::name`, the canonical id, `@FILE:LINE`. It does not accept a `sym#…@…` edit handle
today and does not gain one here, so there is no handle-staleness arm; refusal (5) is the file-side
equivalent and is strictly wider, because it holds for every spelling rather than only for a handle. A
handle tier on this verb is a target-grammar change with its own help, refusal and gate footprint, and it
belongs to the round that wants it.

**The band.** A fixture set of **at least 30 payloads** — at least 10 contract-CHANGING, at least 10
contract-PRESERVING, at least 10 INVALID — across C++ and Python. For every valid payload the gate runs the
preview on a pristine corpus, then applies the SAME payload to a fresh copy of that corpus through
`--replace-symbol-body` and runs the ordinary `--edit-check` on the result, and the two documents must
AGREE. Agreement is byte-equality of the `<edit-check>` element after three normalisations and no others:
the leading `<!-- … -->` legend is dropped, ` at="…"` is dropped (the applied tree is dirty and the pristine
one is not), and ` preview="1"` is dropped. Everything else is compared — `status=`, `change=`,
`params_was/now=`, `public_was/now=`, `defs_was/now=`, `defs=`, `callers=`, `incompatible=`, `p=`, every
`<def>` row and every `<c>` row in order. **ACCEPT: agreement on ≥ 29 of 30, with ZERO false "unchanged"** —
a preview reporting `status="unchanged"` where the applied tree reports `contract-change` or `new-symbol` is
a single-instance FAILURE of the whole band regardless of the ratio, because reassurance is the one answer
this verb exists to be trusted on. Every INVALID payload must refuse (exit 1, empty stdout); an invalid
payload that ANSWERS fails the band. The gate carries a MUTATION CONTROL proving it can see a false clean:
the same comparison is run with a contract-changing preview against a contract-preserving apply, and the
gate fails if that pair is reported as agreeing. ASan/UBSan clean on every fixture; the preview's output is
deterministic across repeated runs and pipes clean through `xmllint`.

**NEGATIVE consequence, pre-committed.** Below 29/30, or on any single false "unchanged", the flag does NOT
ship: the feature code is reverted, the fixture corpus and this section stay, and the result is written up
here as a registered negative.

**MCP mirror.** The MCP `edit_check` verb gains the same preview only if its input schema can carry the
payload without breaking `test/mcpcontractcheck.sh`. If it cannot, the CLI-only scope is stated in the
emitted legend and reported in the lane report rather than left for a reader to discover.

### RESULT — measured 2026-09-03 against the band registered immediately above

**The realized fixture set: 37 payloads — 12 contract-changing, 13 contract-preserving, 12 invalid** — over a
five-file corpus (`test/editpreviewfix/corpus`: a public C++ header with a free function and two methods, a
non-public translation unit with three free functions, a C++ caller, a Python module with two free functions
and a two-method class, a Python caller). The changing class covers a parameter added, a parameter removed,
a method's arity moving, a zero-parameter method gaining one, Python's implicit `self` on both sides, and an
added WIDER OVERLOAD (`defs` 1 → 2 with the params MAX 2 → 4, which is the shape the MAX fold exists to
disclose). The preserving class covers bodies rewritten, locals introduced, a docstring added, and
parameters RENAMED at unchanged arity.

**Agreement: 25 of 25 valid payloads — ZERO disagreements. Zero false "unchanged". All 12 invalid payloads
refused (exit 1, empty stdout).** The registered floor is the rate 29/30, i.e. one allowed disagreement;
`test/editpreviewcheck.sh` applies it to the realized valid set as "at most one disagreement", which on 25
payloads is a stricter rate than 29/30 rather than a looser one. Agreement is byte-equality of the whole
`<edit-check>` element after exactly the three normalisations the band named, so `params_was/now=`,
`public_was/now=`, `defs_was/now=`, `change=`, `callers=`, `incompatible=`, `p=` and every `<c>` row in
order are all inside the claim. Arm M (a contract-changing preview compared against a contract-preserving
apply) reports that pair as disagreeing, so the 25/25 is not a comparison of two constants.

**ONE RECLASSIFICATION, and it is a limit rather than a pass.** The set as first drafted classed a
DE-INDENTED Python body (`def widen(a, b):` followed by an unindented `return`) as invalid. It is not
detectably invalid: tree-sitter-python RECOVERS that text with **zero** ERROR/MISSING nodes — the `def`
keeps its parameters and the statement becomes top-level — so the parse-error delta the refusal is built on
does not move, and the preview answers `unchanged`, which the applied tree also answers. Widening the
refusal to catch it would mean inventing a syntax verdict the parser did not give, on a surface whose whole
value is that it does not guess. So the payload was moved to the preserving class as fixture `pre13`, is
pinned there by gate arm R, is named in the emitted legend, and the invalid class was refilled with a
Python `def` line missing its colon (which does raise the error count, and does refuse). The class floor of
10 each is still met on both sides of the move.

**Why the caller SET is allowed to move, and why that is what makes the numbers hold.** The preview does not
recompute the answer from the payload; it re-derives the TREE and calls the same `editCheckBundleText()`.
The edited file's symbols, references, bindings and routes are RANGE-SPLICED out of the working-tree ingest
and replaced by a single-file parse of the spliced bytes (symbol ids are assigned in `(fileId, line, name,
startByte)` order, so one file's records are a contiguous run and the id remap is one linear shift), then
`buildGraph()` runs over the merged result. That matters because call resolution carries an ARITY FILTER: a
payload that changes a parameter count changes which call sites bind, so the caller list and the
`incompatible="1"` flags are outputs of the rebuilt graph rather than of the old one. The file TABLE is
never touched, so `ing.files` identities — and every path, root-relative spelling, HEAD-baseline key and
`at=` anchor derived from them — stay the real tree's; no temporary root reaches the output.

**MCP mirror: SHIPPED.** `edit_check` gained an OPTIONAL `new_body` and stays `readOnlyHint:true` — passing
it previews, it never writes. `test/mcpcontractcheck.sh` is green (it parses its expected sets out of
`src/mcprefusal.h`, so the schema, the unknown-field guard and what the code consumes moved together), as
are `mcpeditcheck`, `mcpeditpresencecheck`, `mcpclidiffcheck`, `mcpverbscheck`, `mcpflagshipcheck`,
`mcptoolprunecheck` and `mcptranchecheck`. Gate arm N pins the mirror document-for-document against the CLI
preview; both surfaces route through one `editpreview::run`.

**Cost, reported as a ledger and never as a gate.** On `src/` (130 files), warm: the post-hoc
`--edit-check` is ~92 ms and the preview ~280 ms (three runs each, same machine, same warm caches). The
delta is two single-file ingests — the spliced file and, for the honest error-node baseline, the original —
plus one `buildGraph()` over the merged tree. Deliberate: reading the "before" error count off
`ing.fileHealth` instead would cost nothing, but `fileBytes == 0` there means NOT MEASURED, which on a
cache-served parse becomes a silent zero baseline that refuses every payload.

**Clean:** ASan/UBSan (`-fno-sanitize-recover=all`, committed LSan suppressions) over the whole 37-payload
sweep and over the whole-repo map; three byte-identical preview runs; `xmllint --noout` on the preview
document. Gate arm W asserts the corpus is still byte-clean after all 37 previews — the dry run writes
nothing, which is the only claim that must never be taken on trust.

**Two disclosures the legend carries, because they are limits and not footnotes.** (1) A payload the grammar
RECOVERS is answered on its recovered parse, per the reclassification above. (2) The preview previews a body
REPLACEMENT only; the two insert verbs have no preview in this round. And the scope note stands unchanged:
`--edit-check`'s target grammar did not gain a `sym#…@…` handle tier, so the staleness refusal is file-side
(the span must fit the file's current bytes and still contain the definition's own name), which holds for
every spelling rather than only for a handle.

### `dropped_positive=` — A2 round, PRE-REGISTERED 2026-09-03 (survey card A²Agent: budget cuts silently
drop true positives)

**The mechanism under test.** `dropped_positive="N"` on the `--for` and `--pack-task` roots (both dialects,
CLI XML/JSON and their MCP twins `for`/`pack_task`): how many symbols scored ABOVE the relevance floor
(positives by LB-A's own admission rule — `relevanceFloorCut`/`relevanceFlooredKeep`, the same cut that
already narrows `--for`'s quota to non-zero-score rows) and were then removed by the PAYLOAD ceiling — the
H1 sig-ladder's step F (`trimSigLadder`, `src/serialize.h`) or the collection-phase byte gate — rather than
a content reason (an unreadable file, an out-of-range signature span, an empty cleaned signature; those are
NOT the payload ceiling's doing and must not be blamed on it). Shared arithmetic, one function
(`droppedPositiveCount`, `src/serialize.h`), consumed by both `packSignatures` (XML) and `packSignaturesJson`
(JSON) via a `droppedPositiveOut` out-param, so the two dialects and the two verbs cannot report two
different counts for the same query. Emitted ONLY when nonzero — absent on the (overwhelming) no-drop path,
the `pr_converged="0"` precedent (`src/prconverge.h`) — spliced in the same "insert before the header's
trailing `-->`" mechanism `weak=`/`est_tokens=` already use for --for (their value is likewise known only
after the sigs render), and folded into --pack-task's existing per-section `report` clause (whose bytes are
already inside `kPackTaskHeaderReserve`'s generous fixed allowance, so no separate budget accounting is
needed there).

**Band (registered before measuring, per the round's own rule).** The attribute must be EXACTLY correct —
never an estimate, never a floor label (`_floor`/`_capped` mean "this count admits it might be short"; this
one carries no such hedge, so a wrong count is strictly worse than shipping nothing). Verification method:
for a shape wide enough to serve its whole kept head without any ladder trim (the reference run) versus the
same query at a tight budget (the capped run), `reference_rows - capped_rows` — matched by `r=`, the 1-based
GLOBAL rank assigned once before any trim and therefore invariant across budgets for the same query — is
ground truth; the reported attribute must equal it exactly. Byte cost on the no-drop path must be zero: the
XML splice and the JSON `dropped_positive` key are both entirely absent (never a fabricated
`dropped_positive="0"`), and neither the XML sig-side budget computation (`sigsBudget`) nor
--pack-task's section-quota arithmetic reads anything related to this attribute, so the no-drop path's
bytes are unaffected by construction — verified additionally by direct md5 comparison against the pre-change
binary (`origin/main @ 3eec040`) on 4 no-drop shapes (`--for=pageRankDouble` XML and MCP, `--for=pageRankDouble
--json`, `--pack-task=pageRankDouble`), all byte-identical.

**Trap found and fixed during verification, recorded so it is not re-discovered.** `--for`'s AUTO-bundle
sig-side ceiling (`forSigSideCeiling`, `src/verbs_for.h`) freezes the `<sigs>` budget at
`kForPayloadBudgetBytes` regardless of how large an explicit `--token-budget` is (a deliberate,
pre-existing rule: a wider ceiling must not re-inflate the sig tail at the auto-bodies' expense —
`forbudgetmonotoncheck`). A naive verification that used a huge `--token-budget` alone as the "unbounded
reference" therefore produced a reference that was ITSELF still capped, which read as the attribute
OVER-counting by the reference's own hidden shortfall (measured once: reported 30, naive reference implied
25). The fix is procedural, not code: pair the reference and the capped run under the SAME serving shape —
both `--signatures-only`, or both carrying an explicit `--pack-top-n` (which takes the "explicit sig
posture" branch and honors the full `--token-budget`) — so the sig-side clamp is either present or absent
on BOTH sides identically. `test/droppedpositivecheck.sh` builds every reference run this way and also
refuses to trust a reference that itself carries `dropped_positive=` (arm-internal ground-truth guard).

**A second trap, found by the round's own gate list.** The first cut spelled the splice with an inline
English bracket note (`dropped_positive="N" [dropped_positive: N symbol(s) scored above the relevance floor
but were then cut by the payload ceiling]`, ~120 B) and reserved its exact width in every downstream section
(bodies, enrichment, tail, the explicit-ceiling ladder) so the CONSERVATIVE byte ceiling
(`ceilingAllowanceBytes`, `kMinBytesPerToken`) could never be blown — `w3fixbudgetcheck` passed. But
`fornotesbudgetcheck`'s three-budget fixture (950/1500/3000) checks a DIFFERENT, stricter number:
`est_tokens` computed at the denser `kBytesPerTokenDefault` rate, which that fixture pins with as little as
~28 tokens of headroom at its middle budget (by design — its own header text: "any addition to --for's
legend or header, of any size, turns this arm red... the correct response is a DELIBERATE re-anchor"). A
~120 B addition is ~50 tokens at that rate — genuinely wider than the fixture's margin, and NOT something a
byte-ceiling reserve can paper over (the reserve controls whether the document overflows the conservative
allowance, not whether the honest `est_tokens` count stays under the caller's stated number). Re-anchoring
the fixture was the file's own prescribed fix, but the budget domain here is coarse (`1500`→`1540` jumps a
whole extra row into the bundle, `est_tokens` 1524→1648 in one step — no clean nearby value exists). The
actual fix: shrink the spelling to the bare attribute (`dropped_positive="N"`, ~24 B, matching `weak="1"`'s
own economy) — legendcoveragecheck's `ATTR` regex matches literal `<tag attr="v">` shapes and never sees
either spelling (both live inside a comment, not a real tag's attribute list; proven green both ways), so
the bracket note bought no legend coverage, only bytes it could not afford. Both `fornotesbudgetcheck` and
`w3fixbudgetcheck` pass with the bare spelling and no fixture re-anchor.

**Result: KEEP.** Verified exact on: `--for` XML (`--signatures-only` route and the auto/bodies route, both
via the paired-shape method above), `--for --json`, `--pack-task` XML, MCP `for`, MCP `pack_task` — a
conceptual query (`"tree-sitter parse of a source file"`) against `src/` at several token-budgets, plus 5
additional no-drop queries confirmed silent on all three surfaces (`--for`, `--for --json`, `--pack-task`).
Mutation control: `droppedPositiveCount` patched to add a constant off-by-three, rebuilt `--clean-first`,
`test/droppedpositivecheck.sh` went from 14/14 PASS to 12 FAIL (every exact-match and every no-drop-silence
arm); reverted, rebuilt `--clean-first` again, back to 14/14 PASS — the gate is sensitive to the exact
arithmetic, not just to presence/absence. Legend: no defining clause needed — the bare attribute rides
inside the same trailing comment `weak=`/`est_tokens=` already splice into, and `legendcoveragecheck`'s
`ATTR` regex (which enumerates real TAG attributes, not comment text) never sees it as a first-screen
attribute needing a registry entry in the first place — the same structural reason `weak=`/`est_tokens=`
need none of their own; the full explanation lives here, in this registration. Gate:
`test/droppedpositivecheck.sh` (14 assertions across both dialects, both verbs, both CLI and MCP, plus
well-formedness and determinism on a drop-case shape); registered in `test/regression.sh`'s absorb loop.

## `--slice=SYM:VAR --since=REV` — the def-use slice as a DEPENDENCE diff (card A4, COMMITGUARD), PRE-REGISTERED 2026-09-03 (before the feature existed and before any number)

The survey card (P10 COMMITGUARD, `arXiv:2608.17401`) reads: *"the def-use slice as it was vs as it is,
so a regression review reads the dependence change and not just the textual diff"*. ripwire already owns
both endpoints and no operator between them — `--slice=SYM:VAR` slices the working tree, `--since=REV|DATE`
already scopes `--hotspots`/`--cochange`/`--rank-by=churn`, and `--quality-delta`/`--dmm` already
re-materialize a committed tree. This registration fixes the band and the output contract BEFORE the code,
per the house rule; the labelled set it is judged on was written before the feature ran even once.

### The band, fixed here, verbatim

- on **≥20 hand-labelled commits where a dependence edge actually changed** for the sliced `SYM:VAR`, the
  slice diff must be **NON-EMPTY on ≥18**;
- on **≥20 commits that only reformatted the sliced symbol** (whitespace, comments, renames of unrelated
  locals) it must be **EMPTY on ≥19**;
- the diff's own legend restates **every limit the slice legend states** — the diff cannot be more
  confident than the slice it diffs;
- **0 bytes of new output** on any run without `--since`; determinism ×2; cold == warm; `xmllint`; ASan on
  the new path.
- **NEGATIVE consequence:** below either floor the diff does **not ship** (registered negative; no slice
  diff whose false-positive rate makes it review noise).

### The labelled set — written first, `test/slicediffix/labels.tsv`

57 rows over 57 distinct commits of ripwire's own history: **35 `dependence`**, **22 `reformat`**. Both
buckets clear the ≥20 floor with margin, so the band is MEASURED, not unmeasured. The mining and labelling
protocol, the VAR-selection rule, and the five candidate shapes that were read and then DROPPED as not
honestly labellable from the diff alone, are all stated in that file's own header — including the one
sub-shape the band names that history did not contain (`renames of an unrelated local`: zero commits over
436 `src/`-touching commits rename a local and change nothing else inside the function; the reformat bucket
is comments ×19 and whitespace/re-wrap ×3, said rather than manufactured).

### The output contract, fixed here

Emitted ONLY under `--since`; the flag is purely additive and a run without it is byte-identical to today.

- One `<since>` child of `<slice>`, carrying `rev=` (the spec verbatim), `resolved=` (the short sha it
  resolved to), `p=` (the path read at REV) and `status=`.
- `<sd op="+|-" i=" ordinal" k= t= l= [pp=] [b=]>CDATA</sd>` — one row per **statement** of VAR that the
  commit added (`+`, present now) or removed (`-`, present at REV). `l=` is the line on the side the row
  exists on; the CDATA is that side's text.
- `<se op="+|-" d= u= dl= ul=/>` — one row per **def-use edge** added or removed, endpoints named by
  statement ordinal plus the line on the side the edge exists on. Edges are `sliceReachingDefs` at
  statement grain: the same rule the `--slice-flow` walk already chains on.
- Counts `added=`/`removed=`/`edges_added=`/`edges_removed=` on `<since>`; `counts="as-classified"` on the
  root already governs them (a diff of two as-classified sets is as-classified, in both directions).

**The key, and why it is the whole feature.** The diff's unit is the **STATEMENT** — the slicer's own
`sliceStmtAnchorLine` chaining anchor — never the LINE, and the two sides are aligned by a canonical LCS
over the tuple `(k, t, pp)` in source order, **never** over line numbers and **never** over statement TEXT.
Line keying would make every re-wrap and every inserted line above the symbol a false positive; text keying
would make a renamed unrelated local one. Both are exactly the negative bucket the band scores. The
consequence, stated in the legend rather than discovered: `v = 111;` → `v = 222;` is an EMPTY slice diff.
That is correct — no def-use edge moved — and it is why the element is named for dependence and not for
change.

**Absence is disclosed, never silently empty.** `status=` is one of: `ok` (both sides sliced);
`sym_absent_at_rev` (the file exists at REV, no definition of SYM in it — the symbol is new, so every row
reads `+`); `var_absent_at_rev` (SYM exists, VAR has no occurrence — every row reads `+`);
`file_absent_at_rev` (the path is not in the REV tree and no rename resolves it — `comparable="0"`, NO rows,
and the legend says outright that an empty diff under `comparable="0"` is not evidence of no change);
`unparsed_at_rev`. A rename is followed once (`git diff --name-status -M`) and disclosed as
`renamed_from=`. A `--since` spec that resolves to no commit, and a root that is not a git repository,
REFUSE at exit 1 — a comparison verb that cannot compare must not exit 0 with an empty answer.

### Instrument and argv

New gate `test/slicediffcheck.sh` (listed in `test/regression.sh` in the same commit). It replays the
labelled set in a private `git clone --local --no-checkout` of the repo under test — never a worktree of
it, so the gate is safe under `pargates -j6` — checking out each labelled commit and running

```
ripwire <clone> --slice=<file>:<sym>:<var> --since=<sha>^
```

scoring `added+removed+edges_added+edges_removed > 0` as NON-EMPTY. Rows whose commit is not present in
the repo under test are SKIPPED and counted; if fewer than 20 of either bucket survive, the gate FAILS
rather than scoring a short set. The remaining arms cover the 0-byte no-`--since` path, determinism ×2,
cold == warm, `xmllint`, every `status=` value on purpose-built fixtures, the two refusals, and the legend
restatement.

### The falsifiable claim

*"A def-use slice diffed at statement grain separates a dependence change from a reformat well enough to
be read INSTEAD of the textual diff during a regression review."* The 18/20 and 19/20 floors are the two
ways that sentence can be false, and both are scored on the same 57 rows.

## `--slice=SYM:VAR --since=REV` — MEASURED 2026-09-03 against the bands above: **POSITIVE, both floors cleared with margin**

**Verdict: the diff SHIPS.** Scored on the 57 rows registered above, replayed by
`bash test/slicediffcheck.sh build/ripwire` arm (17), which checks each labelled commit out in a private
clone and runs `ripwire <clone> --slice=<file>:<sym>:<var> --since=<sha>^ --no-cache`:

| bucket | registered floor | scaled floor on the set that survived | measured |
| --- | --- | --- | --- |
| `dependence` — must be NON-EMPTY | 18 of 20 | 32 of 35 | **35 / 35** |
| `reformat` — must be EMPTY | 19 of 20 | 21 of 22 | **22 / 22** |
| skipped (commit absent from the checkout) | — | — | **0** |

No miss in either direction, so there is no loss bucket to report and nothing was tuned after the fact:
the labelled set was committed at `95e902d`, the gate went red at `0ba42ab`, and the feature first ran
against them at `e497a0f`. The floors are scaled from the registered 18-of-20 / 19-of-20 ratios to the
number of labelled commits actually present in the checkout under test, which is STRICTER here than the
literal registration (32/35 and 21/22 rather than 18 and 19). One refinement was made to the registration's
gate description after it was written and is disclosed rather than folded in: a checkout carrying NONE of
the labelled commits (a shallow CI clone) is an environment SKIP, not a failure; fewer than 20 in a bucket
while some are present still FAILS. On this checkout 0 were skipped, so the distinction did not bear on
the number.

**Why 35/35 and 22/22 rather than something near the floor.** Both keys are the reason, and each is a
falsifier the reformat bucket actually exercised: 3 of the 22 reformat rows are whitespace/re-wrap commits
(`cls=wsonly` in the mining pass) that a LINE-keyed diff would have reported as changes, and all 22 sit in
commits whose other hunks move the symbol's line numbers. The gate's own fixtures pin the four shapes
independently of the corpus — a comment-only edit, a statement re-wrapped across two lines, a function
inserted ABOVE the symbol so every line number moves, and a value-only edit of the def — plus the two that
must NOT be empty, an added statement and a def inserted between a def and its use (arms 2–7).

**The rest of the band.**

| requirement | result |
| --- | --- |
| the diff's legend restates every limit the slice legend states | **MET** — gate arm 13 asserts `no alias analysis`, `no flow sensitivity`, `STATEMENT` and `comparable="0"` in the block; the block also names intra-procedural, name-based, write-behind-a-call, block-scope separation and the `#if 0` rule |
| 0 bytes of new output without `--since` | **MET** — arm 1; a run without the flag leaves both `SliceEmitOpts` pointers null and is byte-identical to the pre-feature form |
| determinism ×2, cold == warm | **MET** — arms 14a/14b, and the repo map ×2 byte-identical (21 870 B class run) |
| `xmllint` | **MET** — arm 15 on a diff-bearing document |
| ASan on the new path | **MET** — the WHOLE gate re-run against `asan/ripwire` under `LSAN_OPTIONS=suppressions=lsan_suppressions.txt`: ALL PASS, zero reports, including all 57 replays |

**Byte cost, measured** (`ripwire . --slice=src/slice.h:sliceReachingDefs:v --since=HEAD~1 --no-cache`,
`wc -c`): 4 174 B without the flag, 7 103 B with it — of which the `<since>` ELEMENT is **141 B** and the
legend block is **2 796 B**. A legend 20× its payload is the shape the slice family already hit and already
answered, so the since block joined `--legend=compact` in the same lane: 1 016 B there, total 2 751 B, with
the `<since>` element byte-IDENTICAL between the two tiers (gate arm 18b). Warm wall-clock for a
`--since=HEAD~40` run is 0.21 s total, because the REV side materializes ONE FILE rather than a tree.

**What it costs to be wrong, restated as a limit rather than a caveat.** The empty answer is the load-bearing
one, and it is empty for two different reasons that the legend keeps apart: `added="0" removed="0"
edges_added="0" edges_removed="0"` means *this variable's def-use edges did not move*, while `comparable="0"`
means *no comparison was made at all*. Reading the second as the first is the one way this verb can mislead,
which is why the element never carries both and the legend says so in its own sentence.

### Flow-sensitive slice in the small — reaching definitions with kills and joins, PRE-REGISTERED 2026-09-03 (before the code and before any number)

**What is claimed.** `--slice=SYM:VAR` (and the MCP `slice` verb, the same function) computes the REACHING
DEFINITIONS of every use of VAR inside ONE definition **flow-sensitively**: a def of VAR is killed by the next
unconditional def of the same binding on every path, and the defs live on merging paths JOIN — at an
`if`/`elif`/`else` without a covering branch, a `switch` without `default` (and across a case fall-through),
a loop's back-edge (a def at the bottom of a loop reaches a use at its top, and a use after the loop sees
both the pre-loop def and the loop-body def), a `try` body's handlers (every statement of the body may
raise, BEFORE its own defs apply) and `finally` (walked once on the normal path, once on the exceptional
one), a Python `for`/`while ... else`, a `match` (the no-case path is always kept), and a build-dependent
C-family `#ifdef`/`#if EXPR` region (an undecided branch — the existing pp rule, now by structure). A
`return`/`break`/`continue`/`throw`/`raise` ends its path. The walk is over tree-sitter STATEMENT order
inside the one definition — no alias analysis (a reference/pointer alias is still invisible, and still
disclosed), no inter-procedural flow. Today the reaching definition is name-based and source-ordered: the
last def before the use in the file kills everything above it whatever branch it sits on, and no join
ever happens; the slice legend says "no flow sensitivity".

**The surface, fixed here.** Every USE row (`k="use"|"both"`) of VAR carries `rd=` — the lines of the defs
that reach it, ascending, comma-separated, `"-"` when no def inside the definition reaches it — placed LAST
on the row (after `b=`/`pp=`, the same placement rule `pp=` follows). The root carries `reach="cfg"` where
the flow-sensitive walk is served (C/C++/ObjC (+CUDA/Metal), Python) and `reach="linear"` where it is
not yet (JS/TS, Go, Java, Rust keep the linear source-order rule — a later def kills, nothing joins — and
say so). `--slice-flow` and `--since` consume the SAME per-occurrence reach table the rows print, so the
flow walk, the dependence diff and `rd=` can never disagree about what an edge is. `counts="as-classified"`
semantics are unchanged: `defs=`/`uses=` still count occurrences the classifier rowed.

**The unit rule, and the per-construct disclosures (each stated in the legend, never guessed).** The unit
is the STATEMENT: every use in a statement reads the state ENTERING it, and the statement's defs apply
after — so `x += 1` / `x++` read the previous def then kill it (exact, `k="both"`), a walrus or an
assignment inside a condition defs after the condition's reads, and a C++17 `if( init; cond )` walks its
initializer as its own unit. Consequences, disclosed per construct rather than modelled: (i) control flow
NESTED INSIDE AN EXPRESSION never branches — `?:`, short-circuit `&&`/`||`, a Python conditional
expression or comprehension, a lambda / closure / nested `def` / nested class body — the whole enclosing
statement is one unit and a def inside it applies there, once, unconditionally; (ii) `goto` falls through
(a label is walked as the statement it labels; the jump is not tracked); (iii) a Python `global`/`nonlocal`
name is tracked like a local inside the function — a write from outside is invisible; (iv) no alias
analysis — a write through a reference/pointer alias, or hidden behind a call (limit 2), never defs the
original; (v) a `try` body's handler sees the state before EVERY statement of the body, at any depth
(over-includes when only one statement can raise); (vi) a loop iterates to a fixpoint (monotone, always
terminates), which is exact for reaching definitions.

**Instruments.** (a) A NEW sentinel fixture `test/sliceflowsensfix/` — hand-written functions in C++ and
Python plus one JS control for the `linear` arm — with the exact expected reaching-def lines of EVERY use
row in `test/sliceflowsensfix/expect.tsv`, committed with this registration and BEFORE the code, in the
same commit as the RED gate. Composition as committed: 53 functions — **16 with a kill, 17 with a
branch/loop join, 10 straight-line controls, 9 disclosed-construct sentinels, 1 linear** (the band asked
≥10/≥10/≥10 and ≥30 in all); 85 use rows over 56 (file, function, variable) groups; every row's `rd=` is
an expectation. Where the source-order edge of a use DISAPPEARS under the flow-sensitive rule, `expect.tsv`
carries a `reason` — `exit=K` (the def's path leaves through the jump at line K), `branch=K` (the branch
head at K puts the def on a sibling path), `unit=K` (the statement at K folds the def and the use into
one unit — disclosure (i)) or `try=K` (the try at K: its handler sees the state BEFORE each body statement,
disclosure (v), so the body's last def never reaches the handler) — and the gate CHECKS it: it re-derives
the source-order edge from the tool's own rows, requires K to sit where the reason says (exit/branch
strictly between the vanished def and the use; unit/try at or before the def) and to read as that kind of
statement in the fixture source. Nine such disappearances are in the committed set (four exits, two
sibling branches, one nested-body fold, two try-handler entries — and none spurious). (b) The 57 labelled commits of `test/slicediffix/labels.tsv`: `slicediffcheck` arm
(17) must stay **35/35 and 22/22** with the new edge rule underneath it. (c) Gate
`test/sliceflowsenscheck.sh`, in `test/regression.sh` in the same commit, RED against the current binary
(no `rd=`, no `reach=`, joins missing).

**The band, fixed here, verbatim — a miss on ANY conjunct is a registered NEGATIVE with the numbers, and the
band is never moved after a number.**

| conjunct | requirement |
| --- | --- |
| sentinel | **0** use rows whose `rd=` differs from `expect.tsv` (both directions: every use row has an expectation, every expectation is met), across all 53 functions |
| disappearances | **every** source-order edge that disappears is explained by a `reason` the gate verifies as above — none unexplained, none spurious |
| composition | ≥10 kill, ≥10 join, ≥10 straight-line functions in the committed fixture (counted by the gate) |
| labelled set | `slicediffcheck` arm (17): dependence ≥ 32/35 as registered, measured **35/35**; reformat ≥ 21/22, measured **22/22** — must not move |
| legend | the full legend no longer says "no flow sensitivity"; it defines `rd=` and `reach=`, states the unit rule and each disclosure (i)–(vi) by construct; the `--since` block and the compact tier follow |
| counts | `counts="as-classified"` unchanged in meaning and placement |
| inheritance | `--slice-flow=back` on a join reaches BOTH defs at depth 1 (gate arm); `--since` reports the join's added edge (gate arm) |
| MCP parity | the MCP `slice` payload is byte-identical to the CLI on the fixture (same function — gated) |
| determinism / well-formedness | ×2 byte-identical; `xmllint --noout` on every emitted shape |
| ASan | the whole gate green against `asan/ripwire` under `LSAN_OPTIONS=suppressions=lsan_suppressions.txt` |
| slice family | `slicecheck`, `sliceflowcheck`, `mcpslicecheck`, `slicediffcheck`, `compactlegendcheck`, `legendcoveragecheck` green (their pinned rows updated in the SAME commit where `rd=` lands on a use row — the contract moves with the gate, never after it) |

**The falsifiable claim.** *"Inside one function, a def-use edge the slice prints is one the program can
actually take: a killed def is gone, a joined def is present, and where the walk cannot know (an alias, a
goto, a nested body) the legend names the construct instead of guessing."* The sentinel's 0-wrong floor and
the verified reasons are the two ways that sentence can be false.

### Flow-sensitive slice in the small — MEASURED 2026-09-03 against the band above: **POSITIVE, every conjunct met**

**Verdict: rung 3 SHIPS** (`0f68ece`, registration + fixture + RED gate at `7ba5587`). Scored by
`bash test/sliceflowsenscheck.sh build/ripwire` and the slice family, then the whole set again against
`asan/ripwire` under `LSAN_OPTIONS=suppressions=lsan_suppressions.txt`.

| conjunct | registered | measured |
| --- | --- | --- |
| sentinel | 0 use rows wrong, both directions | **0 wrong of 85 use rows** over 56 (file, fn, var) groups, **125 edges** checked; every expectation met, no unexpected use row |
| disappearances | every vanished source-order edge explained by a verified reason, none spurious | **9 explained, 0 unexplained, 0 spurious** — 4 `exit=` (ck02, ck08, pk02, pk05), 2 `branch=` (ck03, pk03), 1 `unit=` (pd02), 2 `try=` (cj07, pj04) |
| composition | ≥10 kill, ≥10 join, ≥10 straight, ≥30 in all | **16 kill, 17 join, 10 straight, 9 disclosed, 1 linear = 53** |
| labelled set | slicediffcheck (17) ≥ 32/35 and ≥ 21/22, must not move from 35/35 · 22/22 | **35/35 and 22/22**, 0 skipped — on `build/ripwire` AND `asan/ripwire` |
| legend | "no flow sensitivity" gone; `rd=`/`reach=` defined; unit rule + each disclosure by construct; since block and compact tier follow | **MET** — gate arms (3), (4), (6); the full block names ?:, short-circuit, conditional expression/comprehension, lambda/closure/nested def/class body, goto, global/nonlocal, try, alias, linear; the since legend says "reaching definitions by the same reach= rule" |
| counts | `counts="as-classified"` unchanged | **MET** — same marker, same LAST placement; `defs=`/`uses=` still count occurrences (slicecheck green) |
| inheritance | `--slice-flow=back` reaches both joined defs; `--since` reports the join's added edge | **MET** — arm (5): cj11 back from `y` rows `x` at l=137 and l=140, both d=1 f=142; arm (6): wrapping `x = 2` in an `if` yields `edges_added="1"` `<se op="+" d="0" u="2" dl="3" ul="8"/>` |
| MCP parity | byte-identical to the CLI on the fixture | **MET** — arm (7), the flow-back payload of cj11:y, rd= and reach= included (one function, `sliceBundleText`) |
| determinism / xmllint | ×2; every shape | **MET** — arm (8)/(9) on the fixture; ×2 + `xmllint --noout` on `ripwire . --slice=sliceComputeReach:state --slice-flow=both` in this repo |
| ASan | the gate green under the sanitizer | **MET** — sliceflowsenscheck, slicecheck, sliceflowcheck, mcpslicecheck, slicediffcheck (all 57 replays) ALL PASS on `asan/ripwire`, zero reports |
| slice family | six gates green with their pins moved in the same commit | **MET** — slicecheck, sliceflowcheck, mcpslicecheck, slicediffcheck, compactlegendcheck, legendcoveragecheck rc=0; plus deckcheck, docscommandscheck (COMMANDS.md regenerated for the `--slice` help text), skilltruthcheck, loopconservationcheck rc=0 |

**What was fixed in the expectations before the code existed, and where.** Three corrections were made
to `expect.tsv` between writing it and running the implementation, all inside the registration commit
(`7ba5587`, amended before any number): (a) `cj07` l=91 and `pj04` l=35 — the first draft listed the try
body's LAST def as reaching the handler, which contradicts the registered rule "every statement may raise
BEFORE its own defs apply"; the rule stood, the two rows moved to `83,86` / `30,32`; (b) the
`unit=K` reason kind for `pd02` l=17 (a nested-def fold is neither an exit nor a branch) and (c) the `try=K`
reason kind for the two rows in (a), both added to the gate's verifier with their own placement and
keyword checks. The band itself did not move.

**The contract that moved with the gate, disclosed.** `rd=` now lands on every use row, so three pinned
rows in `sliceflowcheck` (27c, 28b, 28d) carry it, and arm (7)'s "no flow attribute" regex learned that
`rd=` is a v1 attribute. The v1 legend grew by the per-construct disclosures the band requires: 4523 B
against a budget that was 3584 B and now is 4608 B (the pre-existing block sat within 14 B of the old
budget); the flow addendum is 1287 B under its unchanged 1400 B; the compact tier is 1216 B against
1024 → 1280 B (it is the attribute-vocabulary tier, and `rd=`/`reach=` are first-screen attributes).
Both moves are in `0f68ece` with the code, with their reasons in the gate. Byte cost on a fixture row:
`rd="9,12"` + `reach="cfg"` = **22 B** on a 4 836 B document (legend 4 500 B).

**Per-construct disclosures as shipped** (the legend's limit 1, verbatim in spirit): control flow nested
inside an expression — `?:`, short-circuit, a conditional expression or comprehension, a lambda / closure /
nested def / class body — folds into its statement and its defs apply there once (sentinels cd01, cd02,
cd05, pd02, pd03, pd04); `goto` falls through and the jump is untracked (cd03); a Python
`global`/`nonlocal` name is tracked like a local, an outside write invisible (pd01); a try handler sees
the state before every statement of its innermost try body (cj07, pj04 — over-includes when only one
statement can raise; a nested try's statements feed the inner handler only); no alias analysis (cd04, and
the by-reference call-arg limit 2 unchanged); `x += 1` reads then kills — exact, not a disclosure (cs03,
ps03); JS/TS, Go, Java, Rust are `reach="linear"` (lj01: the `if` never joins, `rd="6"`) until their
control tables are fixture-verified the same way.

**Quality-delta.** `ripwire . --quality-delta --scope='src/*'` clean (gating="0") after acking 17 gating
rows with one reason (`--ack-only=gating`): the `edgesOf` contract change (the point — one edge oracle),
sliceEmitBody +4 complexity (the rd= emission, its formatting factored into `sliceAppendReachAttr`), three
duplication rows that are the idiomatic tree-sitter named-child loop / a two-way ternary, eleven
short-horizon-churn rows on the two files this lane owns, and sliceLegendText +11 lines of registered
disclosure text. `sliceFlowExpandBack`'s +5 complexity was removed instead (factored into
`sliceFlowChainUse`).

**What it does not claim.** The linear families are not "flow-insensitive by design" — they are untabled,
and the root says `reach="linear"` so no reader mistakes source order for a proof. The nested-body fold
is the one disclosure that can put an edge the program cannot take on a row (cd02: the lambda's def
"applies" at the lambda line); it is named rather than modelled because a closure's execution point is
not knowable here.
