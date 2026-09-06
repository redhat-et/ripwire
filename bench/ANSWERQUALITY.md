# ripwire — answer quality (does the context actually help?)

The published gaps so far were **cheaper** (96% fewer tokens) and **faster** (9–42× vs aider). Both are
*efficiency*. The honest open question is **quality**: does ripwire's context make an agent's answer
*better*? This closes it as far as is measurable without a live agent fleet — with a real **retrieval
proxy** now, and a **runnable end-to-end harness** for the task-success number.

## 1. Retrieval recall — the proxy (real, reproducible: `ripwire <repo> --eval`)
The established proxy (RepoGraph, aider): for real historical multi-file commits, does the tool surface
the *other* files a change touched, given one seed file? Gold = git's co-changed set per commit; seed =
the most-symbol file; measure **recall@k** of the rest, averaged over the last 80 qualifying commits.
LLM-free, deterministic, leave-the-seed-out.

**Historical, private corpus (not reproducible publicly)** — whole private C++ corpus (1574 files),
recall@5 / @10 / @20:

| ranker | @5 | @10 | @20 | what it is |
|---|---|---|---|---|
| **ripwire lexical** (`--for`/`--query`, BM25body) | **40.3%** | 46.2% | 53.2% | subtoken names+callees + file body |
| BM25 (whole-name) | 34.4% | **52.3%** | **59.1%** | lexical baseline |
| ripwire structural (PageRank) | 3.8% | 6.4% | 6.4% | **importance, not relatedness** |
| same-directory | 1.8% | 5.8% | 8.6% | cheapest real prior |
| random | 0.3% | 0.6% | 1.3% | floor |

**→ ripwire's lexical retrieval recovers ~40% of a real change's files at top-5 (≈53% at top-20) —
a 30–130× lift over random, and far above the same-directory prior.**

**The honest finding (ripwire's own `--eval` has said this all along):** *relatedness is lexical,
importance is structural.* PageRank — ripwire's headline ranker — is the wrong tool for "what else does
this change touch" (3.8% @5, barely above same-dir); the win comes from ripwire's **lexical** modes, and
**fusing** structure into lexical *hurts* (fused 7.7% @5 < lexical 40%). We ship the signal that wins and
say so — facts, not verdicts.

## 2. End-to-end task success — the harness (`bench/swebench_eval.py`)
Retrieval recall is the *leading indicator*; the real number is **resolve rate on SWE-bench** with vs
without ripwire context. That needs a live LLM + the dataset + the official sandboxed scorer, so it is
**not run here** — but the harness is real and runnable:

```sh
pip install datasets anthropic swebench         # + ANTHROPIC_API_KEY, + Docker for the scorer
python bench/swebench_eval.py --dataset princeton-nlp/SWE-bench_Lite --n 50
# → preds_baseline.jsonl (problem statement only)  and  preds_ripwire.jsonl (+ ripwire --for context)
python -m swebench.harness.run_evaluation --predictions_path preds_baseline.jsonl --run_id base ...
python -m swebench.harness.run_evaluation --predictions_path preds_ripwire.jsonl --run_id ctx  ...
# compare the two resolve rates — the delta IS ripwire's task-success contribution
```
The harness only owns the ripwire-specific part (generate predictions for two arms); **scoring is the
official `swebench` harness** — no reinvented, gameable scorer. The hypothesis to test, grounded in the
proxy above and RepoGraph's **+32.8% SWE-bench from structural retrieval [arXiv 2410.14684]**: the
ripwire arm resolves more, because it walks in already knowing the files the fix spans.

## 3. End-to-end pilot — run here (N=2, the real fix-the-failing-test loop)
The §2 harness needs a key + Docker. To get a *real* end-to-end signal now, I ran a small agent A/B
directly: inject a realistic localized bug into a **big** private C++ tree (1574 files; historical,
private corpus, not reproducible publicly), then have an
identical coding agent fix it **with vs without ripwire**, scored by whether the subsystem doctest passes
(`infrastucture/build_tests.sh release`, exit 0). Same task, same oracle, isolated git worktrees; the only
difference is whether the agent may use `ripwire` to navigate. I scored by re-running the oracle myself.

| bug (symptom the agent saw) | arm | resolved? | tokens | localization |
|---|---|---|---|---|
| kdtree `size()` off-by-one (`tree.size()==400` fails) | baseline | ✅ | 66k | ~4 grep/read steps |
| | **+ripwire** | ✅ | **43k** | 2 steps (`--grep "class KdTree"` → exact line) |
| arena `used()` off-by-one (`arena.used()==0` fails) | baseline | ✅ | 51k | ~4 grep/read steps |
| | **+ripwire** | ✅ | **45k** | 1 step (`--grep "used()"` → exact line) |

**→ Both arms resolved both bugs (2/2). ripwire didn't change *whether* the fix happened — it changed
*how cheaply*: ~25% fewer tokens (88k vs 118k) and 1-command localization vs ~4 grep/read steps.**

Honest reading: these bugs were *solvable either way* (a capable agent + a symptom that named the failing
test). ripwire's value here is **efficiency** (cost, directness) — consistent with the retrieval proxy.
The **resolve-rate** lift RepoGraph reports (+32.8%) needs bugs hard enough that the baseline runs out of
budget localizing, which a 2-bug pilot on named-symptom defects doesn't reach — that is exactly what the
full-scale harness (§2) measures (many tasks, harder localization, resolve-rate per arm). **N=2 is
directional, not significant** — but it is a real end-to-end loop with tests-pass scoring, run here.

## Honest status
- **Proven:** cheaper (tokens), faster (wall-clock), and now **retrieval recall** — ripwire surfaces the
  right files far above random/same-dir. Reproduce: `ripwire <repo> --eval`.
- **Pilot, run here (§3):** a real 2-bug end-to-end loop — both arms resolve; +ripwire is ~25% cheaper
  (tokens) and localizes in 1 command vs ~4 grep/read steps. Measured, but **N=2 = directional**.
- **Not yet run at scale:** the SWE-bench resolve-rate (needs a key + dataset + Docker); the harness is
  here. So we claim **cheaper + more direct** end-to-end (small N) and **better retrieval** — not yet a
  statistically-significant **resolve-rate** lift. We also name which signal does the work (lexical, not PageRank).
- Numbers move with the repo's git history; re-run to reproduce. cf. `BENCHMARK.md` (tokens + speed).

## Appended 2026-07-05 — `--for --anchor` (LARGER-style lexically-anchored PPR): honest result

The steal #1 idea (LARGER, arXiv 2605.16352) shipped behind the opt-in `--anchor` flag: the top-20
lexical hits of `--for=TASK` seed the PPR **personalization vector** (weighted by each anchor's
normalized BM25 score — per-anchor confidence), the existing PPR core expands the walk, and the final
rank is a **score-space** blend `final = 0.7·lex̂ + 0.3·pprˆ` (max-normalized — deliberately NOT the
RRF rank-space fusion that collapsed recall to 7.7%: rank-space hands PPR's near-zero tail large
reciprocal-rank weight; score-space lets the graph term matter only where walk mass actually lands).
Wired as the `anchored` column of `--eval` (file-granularity mirror: anchors lifted from the BM25body
base, file scored by its best symbol). **Result on the 80-commit private-C++-corpus co-change benchmark
(historical, private corpus, not reproducible publicly; 2026-07-05 re-run — history has moved since
the table above; all columns re-based):** anchored
30.6% / 38.0% / 43.7% @5/@10/@20 vs its lexical base BM25body 30.6% / 37.7% / 43.7% and BM25
whole-name 36.9% / 45.1% / 48.1%. A sensitivity scan (N∈{8,20,40}, λ∈{0.15,0.30,0.50}) moves every
number ≤0.3pt — the conclusion is parameter-robust, not a tuning artifact. **Honest verdict: anchoring
never hurts (unlike the RRF fusion) and demonstrably surfaces lexically-invisible direct callees (the
`test/anchorcheck.sh` fixture case — a caller's helper that shares no query token), but it produces NO
measured co-change recall lift and does not close the BM25-wholename gap (A3-F11a stays open). It
ships as an explicit EXPERIMENTAL mode — the output header self-declares this — not as a default.**
One caveat the instrument can't see: co-change gold is file-level and the seed's own vocabulary
already covers most of its lexical neighbourhood, so a symbol-level "surface the un-named helper" win
(what the fixture proves) may be invisible here; a symbol-level localization eval (LocBench, plan
item 18) is the right instrument for a second opinion before deleting or defaulting the mode.

## Appended 2026-07-05 — `--for --route` (deterministic query-shape ranker selector): honest status

`--for=TASK --route` is a second EXPERIMENTAL opt-in modifier on the task lens (same posture as
`--anchor`). A pure, deterministic classifier (`lexical.h chooseForRanker` — no wall-clock, no RNG)
inspects the QUERY SHAPE and picks the base lens ranker for THIS query, then prints which/why in the
`<ctx><!-- lens … [routed: …] -->` header so `--for` vs `--for --route` is a one-glance comparison.

**Two rankers it chooses between:**
- **subtoken+body BM25** (`lexicalScores`) — `--for`'s existing default. Query AND each symbol's doc
  (name subtokens + callees + doc-comment + body) are subtokenized, so "buildGraph" matches every
  *build* and every *graph*. Right for CONCEPTUAL asks.
- **name-exact / whole-name BM25** (`lexicalScoresNameExact`, added here) — the query is split on
  WHITESPACE only (not subtokenized) and scored against each symbol's WHOLE lowercased name (plus
  `scope::name` as a second whole token). Same BM25 constants (k1=1.5, b=0.75) and the same Section
  prose down-weight. This is the ranker the co-change table above shows winning at deeper k when the
  query LITERALLY NAMES a symbol.

**The rules (transparent, not ML — kept in lock-step with the printed `reason`):**
1. Drop tiny stopwords (`the a an is are to of in for how does do where what which on with`); count the
   rest = `nWords`.
2. `hasIdentifier` = any query token is camelCase/snake_case OR (case-insensitively) equals an existing
   symbol name in the ingest.
3. `hasIdentifier` → **name-exact** ("query names a symbol X").
4. else `nWords >= 3` → **subtoken+body** ("multi-word conceptual query").
5. else (1–2 generic words) → **subtoken+body**, flagged LOW CONFIDENCE ("broad query; plain rg may
   also win" — the honest caveat CLAUDE.md already makes for broad common-word asks).

**HONEST CAVEAT — the `--eval` co-change table does NOT by itself validate query-time routing.** That
benchmark is **SEED-based**: it feeds one file's whole symbol bag as the "query" and measures co-change
file recall. `--route` operates on a **free-text task query**, a different distribution — so the
seed-based finding ("whole-name wins at deeper k") is *motivating evidence*, not proof that the router
improves real `--for` answers. The right validation is **side-by-side**: run `--for` vs `--for --route`
on real tasks and compare the top results (the header makes the choice legible).

**UPDATE (post confidence-gate):** the query-time evidence landed via the known-item eval below, and the
router was re-designed to be default-SAFE (a confidence gate, not query-shape rules — see that section).
Routing is now the **DEFAULT** for `--for`/`--query`; `--no-route` restores plain subtoken+body. A conceptual
query's ranking is unchanged (the router falls back — only a header note is added), verified byte-for-byte by
`test/routecheck.sh`. `--route` is still accepted as a back-compat no-op (routing is already on).

---

## Known-item retrieval eval — query-TIME ranker validation (`--eval-retrieval`, 2026-07-05)

> **The 2026-07-05 tables in this section were produced by a DEFECTIVE INSTRUMENT and are kept as the
> historical record, not as current numbers.** That sampler took the first 150 doc-commented symbols in
> symbol-id order — i.e. in PATH order — so a documented file added under an early-sorting directory
> silently moved every figure below with the ranker byte-identical. Measured at `db6a416d`, one identical
> 60-symbol probe file in an otherwise byte-identical corpus scored subtoken/name MRR **0.834** at
> `aaa_probe/` against **0.729** at `zzz_probe/`, and subtoken/doc-phrase **0.620** against **0.976** —
> up to a third of an MRR from path spelling alone.
>
> The bias is ARBITRARY, not consistently flattering: it reports whichever corner of the tree sorts first,
> and on this repo that went OPPOSITE ways on the two published roots — at the root the slice UNDERSTATED
> (subtoken/name 0.598 against a true 0.724), in `src/` it OVERSTATED slightly (name-exact/name 0.977
> against 0.974). Current numbers: **§ Re-measured 2026-09-05** below.

The `--eval` co-change table above and the HONEST CAVEAT flag the exact gap this closes: the co-change
eval is **seed-based** and cannot validate a *query-time* ranker choice. `--eval-retrieval` is the
standard **known-item IR eval**: over EVERY doc-commented symbol in the corpus (the eval prints its own
`population=`/`scored=`/`rule=`), it builds two synthetic queries per symbol — (a) the whole NAME, (b) a stopworded phrase from
the doc-comment's first line — and measures the rank of the gold symbol (in the corpus by construction,
so leave-nothing-out is correct) for four rankers: **subtoken+body** (`lexicalScores`, `--for` default),
**name-exact** (`lexicalScoresNameExact`), **anchored** (`anchoredLexicalRank` over subtoken+body), and
**routed** (`chooseForRanker`'s pick). Deterministic (the gold rank is a pure function of the score
vector). Reproduce: `ripwire <dir> --eval-retrieval`.

### `ripwire src/` (150 doc-commented symbols) — 2026-07-05, defective sampler
```
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.859     76.7%     97.3%     98.7%
  subtoken  doc-phrase   0.993     98.7%    100.0%    100.0%
  name-exact name         0.993     98.7%    100.0%    100.0%
  name-exact doc-phrase   0.060      4.0%      6.0%      8.0%
  anchored  name         0.849     76.7%     95.3%     98.7%
  anchored  doc-phrase   0.991     98.7%     99.3%    100.0%
  routed    name         0.993     98.7%    100.0%    100.0%
  routed    doc-phrase   0.993     98.7%    100.0%    100.0%
```
(routed/doc-phrase 0.993 is the CONFIDENCE-GATED router — before the gate it was 0.427; see the note below.)

### `ripwire .` (repo root; 150 doc-commented symbols) — 2026-07-05, defective sampler
```
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.725     63.3%     83.3%     84.7%
  subtoken  doc-phrase   0.807     76.7%     84.7%     86.7%
  name-exact name         0.929     87.3%    100.0%    100.0%
  name-exact doc-phrase   0.023      1.3%      3.3%      3.3%
  anchored  name         0.712     62.0%     83.3%     84.0%
  anchored  doc-phrase   0.810     77.3%     85.3%     86.7%
  routed    name         0.929     87.3%    100.0%    100.0%
  routed    doc-phrase   0.789     76.7%     81.3%     82.0%
```
(routed/doc-phrase 0.789 is the CONFIDENCE-GATED router — before the gate it was 0.146; see the note below.)

### Re-measured 2026-09-05 — census sampler, midrank ties (THE CURRENT NUMBERS)

Two instrument defects were fixed together; the ranker was not touched, and the movement below is entirely
the instrument telling the truth where it previously did not.

1. **The sample was taken in path order.** Fixed: the population is now every qualifying symbol, and the
   eval is exhaustive over it (`rule=exhaustive`, `population=`/`scored=` printed on every run).
2. **Ties were broken by symbol id — i.e. by path.** A gold symbol under an early-sorting directory won
   every tie it was in. Fixed: rank is now the MIDRANK, `1 + #better + #tied/2`, which no ordering can move.

Decomposed on the repository root, one change at a time:

*(all three rows measured at `db6a416d`, so the third is the fix as measured THEN — the shipped
figure moves as the corpus grows, and the tables above are the current ones)*

| | subtoken/name MRR | name-exact/name MRR | name-exact/name recall@1 |
| --- | --- | --- | --- |
| 150-symbol path-ordered slice, id ties (old) | 0.598 | 0.829 | 75.3% |
| census population, id ties | 0.724 | 0.939 | 90.8% |
| census population, midrank ties (**the fix**) | 0.724 | 0.922 | 85.4% |

On THIS root the sampler fix does nearly all the movement and moves numbers UP, because the head of the
root's path order is `bench/` and `docs/` — harder than the corpus as a whole. That direction is not a
property of head-slicing; in `src/`, whose path order starts inside the source tree, the same fix moves
name-exact/name MRR the other way and barely at all (0.977 → 0.974). Read the slice as *arbitrary*, not
as easy or hard.

The midrank fix then moves name-exact recall@1 down 5.4 points. Most of that is tie-luck removed — gold
symbols had been winning ties they had not earned because their file sorted early — but part is the
convention itself: midrank is deliberately pessimistic, scoring a two-way tie at the top as 1.5, which
takes no recall@1 credit where id-tiebreak handed it rank 1 whenever gold's id was lowest.

### `ripwire src/` (population 3,010, scored 3,010, rule=exhaustive)
```
  subtoken  name         0.745     61.1%     91.8%     96.0%
  subtoken  doc-phrase   0.967     95.2%     98.3%     98.8%
  name-exact name         0.960     91.3%     99.3%     99.4%
  name-exact doc-phrase   0.016      0.8%      2.4%      2.6%
  anchored  name         0.748     62.3%     91.1%     94.6%
  anchored  doc-phrase   0.963     94.5%     98.2%     98.7%
  routed    name         0.960     91.3%     99.3%     99.4%
  routed    doc-phrase   0.967     95.2%     98.3%     98.6%
```
(routing chose name-exact on 3,008/3,010 NAME queries.)

### `ripwire .` (repo root; population 3,521, scored 3,521, rule=exhaustive)
```
  subtoken  name         0.723     59.2%     88.9%     93.4%
  subtoken  doc-phrase   0.930     90.9%     95.2%     95.9%
  name-exact name         0.922     85.5%     97.5%     98.4%
  name-exact doc-phrase   0.017      0.6%      2.7%      3.5%
  anchored  name         0.726     60.6%     87.6%     92.1%
  anchored  doc-phrase   0.925     89.9%     94.9%     95.8%
  routed    name         0.922     85.5%     97.5%     98.5%
  routed    doc-phrase   0.929     90.9%     95.1%     95.7%
```
(routing chose name-exact on 3,519/3,521 NAME queries.)

**The verdict below is unchanged by the re-measurement** — every ordering it rests on still holds:
name-exact wins the NAME mode, collapses on doc-phrase, subtoken+body is the mirror image, and routed
tracks the better lane on both. Only the magnitudes moved. Its prose still quotes the 2026-07-05 figures,
which is deliberate: it is the record of what was concluded then, from what was measured then.

### Verdict (honest — the data drives it, not the other way round)

- **On a NAME query, name-exact WINS decisively** and it is the RIGHT default *for that query shape*.
  On src it lifts MRR 0.859 → 0.993 (recall@1 76.7% → 98.7%); on root 0.725 → 0.929 (63.3% → 87.3%).
  This is the first *query-time* confirmation of the seed-based finding — routing to name-exact when the
  query literally names a symbol is validated. `--route` already does exactly this (150/150 name queries
  routed to name-exact), and **routed == name-exact on the name mode** (identical rows), so on the shape
  routing targets, **routing is a strict win with no downside**. The evidence now justifies routing on
  identifier-shaped queries.

- **On a DOC-PHRASE (conceptual, no-identifier) query, name-exact COLLAPSES** (MRR 0.06 / 0.02;
  recall@1 4% / 1.3%) — whole-name BM25 has nothing to match a prose phrase against — while
  **subtoken+body is near-perfect** (0.993 / 0.807). This is the mirror image and confirms the router's
  *other* branch (multi-word conceptual → subtoken+body) is also correct in principle.

- **The over-eager router was the doc-phrase crater — now FIXED by a confidence gate (this is what made
  routing safe to default).** The first router fired name-exact whenever ANY phrase word case-insensitively
  equalled SOME symbol name (a phrase containing "map"/"score"/"node"/"file"), sending genuinely conceptual
  queries down the name-exact path where whole-name BM25 has nothing to match and COLLAPSES — routed/doc-phrase
  MRR 0.427 src / 0.146 root, far below subtoken+body's 0.993 / 0.807. The fix inverts the trigger from ANY to
  ALL: route to name-exact only when identifier signal DOMINATES the whole query — an explicit camelCase/snake
  token (decisive identifier syntax), OR **every** content word is a whole-name symbol hit. A conceptual phrase
  has prose words that name no symbol, so it fails the "all words name symbols" test and falls back to
  subtoken+body BY CONSTRUCTION (no tuned magic number — the threshold IS the query structure). **After the
  gate: routed/doc-phrase 0.993 src / 0.789 root (was 0.427 / 0.146), routed/name unchanged at 0.993 / 0.929
  (== name-exact). routed now tracks the BETTER ranker on BOTH modes** — the strict identifier-query win and
  the near-perfect conceptual fallback, exactly `routed ≈ max(name-exact, subtoken+body)`. This is what
  cleared the bar to make routing the DEFAULT (see the standing guard `test/knownitemcheck.sh`: routed/doc-phrase
  within 0.03 MRR of subtoken/doc-phrase AND routed/name within 0.03 of name-exact/name).

- **Anchoring is a WASH-to-slightly-NEGATIVE on both query modes** — it never beats its subtoken+body
  base and dips a hair on src/name (MRR 0.859 → 0.849) and root/name (0.725 → 0.712). Consistent with the
  co-change table's "anchored matches lexical-alone, never clearly ahead". **The data does NOT justify
  making `--anchor` default** on either query type; it stays EXPERIMENTAL. (Known-item is admittedly the
  scenario where graph expansion has least to add — the gold IS the queried symbol, so pulling in its
  neighbours can only dilute — so this is a *floor* on anchoring's value, not a full verdict; but it does
  rule out anchoring as a free default.)

**Bottom line for defaulting (UPDATED — routing is now DEFAULT-ON, safely):** the confidence gate closed the
doc-phrase crater, so routing now tracks the better ranker on BOTH query shapes (`routed ≈ max(name-exact,
subtoken+body)`): 0.993/0.993 src and 0.929/0.789 root for name/doc-phrase. That met the defaulting bar, so
**`--for`/`--query` now ROUTE BY DEFAULT**; `--no-route` forces the old plain subtoken+body. The DEFAULT MAP
(no query) is unaffected, and a conceptual `--for` query's RANKING is byte-identical to the pre-routing output
(the router falls back; only a `[routed: subtoken+body …]` header note is added — verified by `test/routecheck.sh`).
`--anchor` remains EXPERIMENTAL/opt-in (still no measured win). All findings are deterministic and reproducible
via `--eval-retrieval`; the standing regression guard is `test/knownitemcheck.sh` (routed within 0.03 MRR of the
better ranker on each mode).

---

## Appended 2026-07-10 — LocBench public scoreboard (`bench/locbench/`, A4-R1)

The retrieval proxy (§1) is on *our own* co-change gold; this puts a number on an **external, published**
benchmark: **Loc-Bench** (LocAgent, [arXiv 2503.09089](https://arxiv.org/abs/2503.09089), ACL'25) — 560
instances of (GitHub issue → repo@commit → gold edit files/functions). `bench/locbench/run_locbench.py`
checks out each repo, runs ripwire as the localizer in three arms (`--for` task lens / `--query` pure
lexical / `--for --anchor` graph expansion), parses the ranked symbols, and scores the paper's **strict
Acc@k** (all gold within top-k) + first-hit MRR. Deterministic, LLM-free, no auth (public HF datasets-server
API). SWE-bench-Lite is the built-in fallback. See `bench/locbench/README.md` for metric defs + the
honest-comparison framing.

**Full run (n=560 — the complete test set, zero skips; ~28 min wall, per-instance rows in
`bench/locbench/full560.json`):**

| arm | file@1 | file@3 | file@5 | file@10 | func@5 | func@10 | fn-MRR | file(any)@10 | func(any)@10 | wall |
|---|---|---|---|---|---|---|---|---|---|---|
| `for` | 7.3% | 14.3% | 19.5% | 28.8% | **4.8%** | 6.2% | 0.049 | 39.8% | 11.1% | 0.48s |
| `query` | 0.5% | 1.1% | 1.8% | 4.6% | 0.0% | 0.0% | 0.006 | 8.9% | 0.7% | 0.33s |
| **`anchor`** | **8.4%** | **16.6%** | **21.2%** | **29.6%** | 4.5% | **6.8%** | **0.055** | **41.6%** | **12.5%** | 0.19s |

Parse coverage **1148/1149 = 99.9%** (301 `added_functions` structurally absent, excluded).

> Footnote — the earlier n=60 validation slice, for comparison: `for` 0.0/5.0/8.3% file@1/5/10, MRR 0.050,
> lenient 31.7%; `query` 0.0/3.3/10.0%, MRR 0.035, lenient 15.0%; `anchor` 1.7/5.0/11.7%, MRR 0.079,
> lenient 38.3%; coverage 189/189. Full-run strict numbers are higher because the full set is **76%
> single-file gold** (median 1 file) vs 25% in the first-60 slice (median 3) — strict ALL-within-top-k is
> far easier with one gold file. Same harness, same metric.

**Honest reading (the losses with the wins):**
- **The floor is modest and we publish it.** Strict Acc by a $0 deterministic *symbol* ranker on raw,
  noisy issue prose tops out at ~30% file@10 / ~7% func@10 — this is precisely the gap LocAgent motivates
  LLM agents to fill (their LocAgent hits 77.7% file Acc@1, BM25-over-*files* 38.7%; **not comparable to
  our symbol-granularity numbers, and we don't claim parity** — the frame is cost-vs-accuracy). The
  multi-file subset stays single-digit (see the n=60 footnote).
- **Parse coverage is 99.9%** — the map *sees* the gold functions; the ceiling is ranking, not parsing.
  This reframes ripwire honestly as the fast, free **candidate feed** into a reranker (A4-R6), not its rival.
- **The lens beats raw lexical at file localization, decisively at full N**: `--for`/`--anchor` surface a
  correct file in the top-10 **~4.5×** as often as `--query` (lenient 39.8/41.6% vs 8.9%; strict file@10
  28.8/29.6% vs 4.6%) — the focused bundle concentrates the right file; the flat BM25 list buries it.
- **The `--anchor` second opinion, now at full N: the n=60 edge HOLDS.** The 2026-07-05 note above closed
  with: a symbol-level LocBench eval "is the right instrument for a second opinion before deleting or
  defaulting the mode." At n=560 `--anchor` beats `--for` on strict file@1/@3/@5/@10, func@10, first-hit
  MRR, and both lenient metrics, losing only func@5 by 0.3pp — a **mild but consistent** win (~1pp strict
  margins), and it is the fastest arm (0.19s/inst). Where the file-level co-change eval was a wash, graph
  expansion earns its keep on symbol-granularity localization. Verdict: **keep `--anchor`**; the margins
  do not yet justify defaulting it.

Reproduce: `RIPWIRE=./build/ripwire python3 bench/locbench/run_locbench.py --n 560 --work-dir /tmp/locbench`.

---

## Appended 2026-07-11 — Is the `amb=` flag honest? Call-edge precision vs SCIP ground truth (B2)

CLAUDE.md tells an agent to *trust the honesty gauges*: a symbol's `amb="K"` means K of its calls hit a
name with multiple defs (the resolver kept them all as a split), so *read the source if which-target
matters* — and, implicitly, that **un**-flagged call edges are safe to trust. This puts a **number** on
that guidance by checking ripwire's name-based call edges against an **independent, type-aware oracle**:
Sourcegraph **SCIP** indexes produced by `scip-python` (Pyright under the hood), consumed through
ripwire's own `--scip` precision overlay (`src/scip.h`) — where SCIP resolves a call site, its target
**replaces** ripwire's name-based guess and the surviving edge is tagged `prov="scip"`. This is
measurement only: no resolver change — the number *informs* a future decision (whether to collapse a
split to a single best guess), it does not make one.

**Method (deterministic full census; `bench/scip_amb_precision.py`).** For each repo we diff two runs at
`--top-k=100000` (defeats the 200-symbol map truncation so *every* edge renders): the baseline name-based
map and the `--scip` overlay. ripwire renders a call edge as `<c n="X"/>` (callee **name**, no target id);
a name X with **>1 in-corpus definition** is ambiguous **by ripwire's own criterion** (the resolver keeps
every same-name def → a split → the owning symbol carries `amb=`). For each `(symbol, X)` bucket where
ripwire emitted ≥1 edge **and** the overlay pinned ≥1 `prov="scip"` edge (i.e. **SCIP speaks** about that
edge), precision = `min(scip_pinned, ripwire_emitted) / ripwire_emitted`, grouped by whether X is
ambiguous. SCIP-only edges (ripwire emitted nothing — a *recall* gap, not a precision datum) are excluded
from precision and reported separately.

**Two indexed repos** (small, self-contained, real `.py` source; from the LocBench cache):

| repo | non-test .py | baseline `ambiguous=` | overlay `precise=` | SCIP occ. coverage |
|---|---|---|---|---|
| **Delgan/loguru** | 21 | 292 | 769 | 26% (1259/4841 internal) |
| **rq/rq** | 35 | 57 | 2554 | 47% (6168/13158 internal) |

**Result — precision where SCIP provides ground truth:**

| repo | group | buckets (n) | ripwire edges | SCIP-confirmed | **precision** | SCIP-only (ripwire missed) |
|---|---|---|---|---|---|---|
| loguru | **amb-flagged** | 300 | 794 | 300 | **0.378** | 5 |
| loguru | non-amb (control) | 460 | 460 | 460 | **1.000** | 4 |
| rq | **amb-flagged** | 520 | 622 | 523 | **0.841** | 384 |
| rq | non-amb (control) | 1617 | 1617 | 1617 | **1.000** | 15 |

**Honest reading:**
- **The `amb=` flag is well-calibrated — it fires on exactly the imprecise edges.** Non-ambiguous
  (unique-name) edges are **100% SCIP-confirmed** in both repos at large n (460 + 1617 = 2077 edges, zero
  disconfirmed). Ambiguous edges drop to **0.38 / 0.84**. The flag cleanly separates the trustworthy edges
  from the guesses — which is precisely what CLAUDE.md's trust-calibration advice asks a reader to assume.
- **But be honest about *why* each side lands where it does.** The non-amb 1.000 is **largely by
  construction**: a unique-name edge has only *one* possible target, so an independent oracle *cannot*
  pick differently — it is a consistency check, not an independent win. And the amb precision is
  essentially **1 / (mean split width)**: ripwire emits *all* candidates for an ambiguous call, so of the
  N edges it renders, only SCIP's one true target is "correct" → precision ≈ 1/N. loguru's ambiguous
  names (many identically-named test fixtures — `patch`, `sink`, `writer`…) give wide splits (2.6
  edges/bucket → 0.38); rq's ambiguous method names give narrow splits (1.2 edges/bucket → 0.84). So the
  amb number is **repo-dependent and dominated by split width**, not by a resolver "guess" being right or
  wrong (ripwire does not commit to one guess — it keeps the split).
- **The decision this informs:** if ripwire were to collapse each split to a *single* best-ranked guess,
  how often would that guess be SCIP's target? This census cannot answer that (the XML exposes no
  per-candidate rank), but it bounds the ceiling: SCIP's target is among ripwire's emitted candidates for
  **98.4% (loguru) / 57.5% (rq)** of the ambiguous calls SCIP resolved — the rest (`SCIP-only`: 5 / 384)
  are calls ripwire's name-based parse emitted **no** candidate for at all (typed-receiver method calls
  Pyright resolves but a name matcher can't). rq's large SCIP-only count is a **ripwire recall** limit,
  orthogonal to the precision question but a real ceiling on what disambiguating the splits could recover.

**Caveats (this is a directional n=2 probe, not a verdict):**
- **SCIP is imperfect ground truth.** Pyright's static resolution is itself wrong for genuine dynamic
  dispatch, monkey-patching, and `**kwargs` forwarding — so "confirmed" means "agrees with a good static
  type-resolver," not "provably correct."
- **Partial coverage (26% / 47% of internal occurrences).** The overlay matched only a subset of SCIP's
  ref occurrences to a current call site, and left 2222 / 2838 SCIP *defs* unmatched — not because the
  index is stale (it was generated from the exact indexed tree) but because `scip-python`/Pyright and
  ripwire's tree-sitter attribute a definition's **line** differently (decorators, the `def` line vs the
  name token). Precision is measured only over the covered subset; the overlay's own "may be from an
  older commit" stderr hint is a **false positive** here and is itself a finding about that diagnostic.
- **The precise-edge set is deduped to unique `(symbol,target)` edges**, so repeated identical calls
  collapse in the numerator while the denominator counts ripwire's raw emitted edges → the amb precision
  is a mild **lower bound** on true per-target precision.
- **n=2 repos, both small and both heavy in tests** — the split-width distribution (and thus the amb
  number) will differ on larger application code. The **direction** is robust (amb < non-amb, flag is
  honest); the **magnitude** (0.38 vs 0.84) is not a single portable constant.

Reproduce (needs Node + `scip-python`; the two indexes are regenerable from the LocBench repo cache):
```sh
npm install -g @sourcegraph/scip-python
( cd <loguru-checkout> && scip-python index --output /tmp/loguru.scip --project-name loguru . )
( cd <rq-checkout>     && scip-python index --output /tmp/rq.scip     --project-name rq     . )
RIPWIRE=./build/ripwire python3 bench/scip_amb_precision.py \
    loguru <loguru-checkout> /tmp/loguru.scip \
    rq     <rq-checkout>     /tmp/rq.scip
```

---

## Appended 2026-07-14 — the first C++ localization number (`bench/cppbench/`, task #13)

**Historical, private corpus (not reproducible publicly).** Superseded by the public-corpus rerun in
`bench/cppbench/`'s own README — `dataset.lock` was later regenerated against a public C++ corpus
(SFML) so the harness is independently reproducible; see that README for the current numbers. The
paragraph below is kept for history only.

Every localization number above is Python (LocBench / SWE-bench-Lite); C++ is the language this
project's user actually cares about. `bench/cppbench/run_cppbench.py` builds a LocBench-style eval from
**a large private C++ corpus's own commit history** (query = commit message, gold = the 1..5 `.cpp/.h/.mm` files that
commit touched, indexed **at the parent commit** via read-only `git archive` — no time-travel leakage,
no writes to the shared tree). 120 instances frozen in `dataset.lock` (content-hash, fail-closed);
117 scored, 3 unindexable-gold exclusions printed with reasons, zero silent skips, determinism ×2 per
arm run. Smoke gate: `test/cppbenchcheck.sh` (in the regression absorb loop; runs on ripwire's own repo,
never the shared tree).

**Scoreboard (strict = ALL gold files within top-k of one flat rank):**

| arm | file@1 | file@3 | file@5 | file@10 | any@10 | MRR | wall/inst |
|---|---|---|---|---|---|---|---|
| `for` (shipping) | 10.3% | 19.7% | 27.4% | 38.5% | **88.9%** | **0.621** | 0.68s |
| `for --no-mention-boost` | 10.3% | **22.2%** | **28.2%** | 38.5% | 87.2% | 0.620 | 0.39s |
| `query` (BM25) | 10.3% | **22.2%** | **28.2%** | 38.5% | 87.2% | 0.620 | 0.44s |

Single-file gold (n=38) strict@10 78.9%; multi-file (n=79) 19.0% — the same cliff as Python.

**Honest findings:** (i) commit messages are POST-HOC queries written by the fixer — easier than issue
reports, so these numbers are optimistic and NOT comparable to the LocBench table; (ii) the **B8 mention
anchor is a wash on this distribution** (+0.0pp strict@10, −2.5pp strict@3, +1.7pp lenient) — symbol-
dense commit messages mention many non-gold files, diluting the anchor that won +4.9pp on issue prose;
(iii) `--for` ≈ `--query` at file granularity on identifier-dense post-hoc queries — the Python
lens-vs-BM25 gap does not transfer to this query shape. Full caveats + methodology:
`bench/cppbench/README.md`.

*2026-07-22 update:* the private-corpus dataset behind the table above was removed for public release
(its lock + per-instance rows embedded verbatim private commit messages); `bench/cppbench/` was
regenerated on a **public** C++ corpus (SFML, pinned commit — see `bench/cppbench/README.md` for the
corpus-selection comparison and the current scoreboard, with per-instance rows in
`bench/cppbench/results/sfml.json`). The table above is retained as the historical record of the
original run; its numbers are no longer reproducible from this tree.
