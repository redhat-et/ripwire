# Placebo-controlled localization pre-registration — does ripwire's ranking help an agent, or only its answer's size?

**Registered 2026-11-26, BEFORE any arm of this design ran on any benchmark instance, and before any model
call.** It freezes the arms, models, task set and seal, n, metrics, bars, stopping rule, and what counts against
ripwire. Anything not written here is post-hoc. Additions go in the ADDENDUM at the bottom, append-only; no line
above it changes after freeze.

The harness support (the control arms, their byte/format gate, payload sealing) landed with this file. The
agent driver that puts a model in the loop does **not** exist yet; its contract is frozen below. No live
agent, no model, and no API token was spent in writing this.

## Why this round exists

[`docs/METHODOLOGY.md`](../../docs/METHODOLOGY.md) §8 is the standing rule: a retrieval head-to-head without a
placebo at matched cost has shown a context-size win, not a ranking win. The strongest outside evidence on
ripwire's thesis cuts against it:

- **Bellam, arXiv 2610.33958** (pre-registered; nine open models, Qwen3 0.6B–32B and Gemma 4 E2B–12B; 500
  held-out SWE-bench tasks; 170,500 episodes; five seeds). Arms: grep only, + embedding search, + code-graph
  tools, both, and a **placebo whose structural tools return random entities**. Function Acc@10 rose
  +0.06 to +0.10 up to 14B and about +0.03 at 32B (a near miss after correction). The placebo showed the gain
  comes from what the tools return; random output **harmed** two small models. The secondary analysis
  attributes the gain to the **embedding index, not the code graph**, and to exposure: the tools surface the
  gold code more often.
- **Xue et al., arXiv 2611.20455.** Much of the dense-over-BM25 advantage is evaluation artefact: BM25 run
  on chunks rather than whole files, and edited tests counted as relevant. Expanding queries with identifiers
  lets BM25 match dense retrieval on every Python pool. Their guideline: measure against a **fair lexical
  baseline**.
- **Lasbordes et al., arXiv 2610.05099.** Sub-2B agents with a late-interaction semantic search tool
  (ColGREP) beat grep-based agents on SWE-bench Lite and Multi-SWE-bench Flash localization, with 44.1% less
  CPU latency and 29.1% fewer tokens.

ripwire has no embedding index; its `--for` lens is lexical subtoken+body ranking plus graph structure. If
Bellam's attribution holds, ripwire's gain over grep is exposure — which a same-size random answer or a fair
BM25 might buy just as well. This round tests that directly, with ripwire as the structural arm.

## Arms (frozen)

Every model episode gets the issue text (the query) and a read-only grep/read tool set — Bellam's grep-only
baseline is the floor every arm shares. Arms differ ONLY in one frozen payload placed in the first user
message. ripwire is not on the agent's PATH in any arm, so the payload is the only ripwire exposure.

| arm | payload | role |
|---|---|---|
| **A0 `query`** | none | grep-only floor |
| **A1 `for-matched`** | ripwire's own `--for --format=candidates` rows, in ripwire's order, cut to the budget **B** | the treatment |
| **A2 `placebo`** | ripwire-rendered rows drawn uniformly (seeded) from files the A1 answer does **not** name, at exactly **B** bytes | **primary control** — Bellam's random-entity placebo |
| **A3 `lexical`** | file-level BM25 over whole files (identifier-split tokens), each file's rows in universe order, at exactly **B** bytes | fair lexical baseline (Xue) |
| A2s `placebo-shuffle` | A1's rows permuted, r=/s= re-dealt in position order — the same bytes and content, no order | secondary control: order only |
| A1p `for-production` | the shipped `--for` bundle as-is (its own size, its own format) | secondary: the product as shipped |

**The matched budget.** `B = min(production --for payload bytes, --for candidates export bytes)` for that
instance — what the shipped answer costs, never more than ripwire can fill. On LocBench train runs already in
this directory the production `--for` payload averages **5,056 B per instance** (n=254, `results/r3_pathtok/train_w0.json`
aggregate `output_bytes / n`; read from the run's aggregate block only).

**Why one format for A1/A2/A3.** The comparison isolates ranking content. A1, A2 and A3 are all rendered in
the identical `--format=candidates` document: the same legend bytes, the same `<candidates>` root attribute
names, and rows ripwire itself rendered (taken from the coverage-universe export). Only `r=`, `s=`, `count=`,
and at most two tail rows' `<sig>` text (closed with an ellipsis, as ripwire's own truncations are) differ.
The placebo's `s=` column is the real answer's score strings in order, so the score column carries no signal.
A1p is reported beside them so the shipped format is not silently swapped for the test format.

**Gold-blindness.** No arm builder takes gold as an argument. The placebo excludes the files the A1 answer
names — so it cannot be the real answer reordered — and **not** the gold files, so its chance hit rate is
the honest chance rate (reported as such).

**Why BM25 and not ripgrep top-k.** `rg` emits matches in file-walk order, not relevance, so its top-k is not
a ranking. Every arm already has grep as a tool. The fair lexical arm is therefore whole-file BM25
(k1=1.2, b=0.75; camelCase and snake_case split; files over 2,000,000 bytes scored empty and **counted** as
`bm25_oversize_files`), the baseline Xue et al. say prior work handicapped. It is implemented in the harness,
independent of ripwire's code.

**Gate.** `test/locbenchplacebocheck.sh` (registered in `test/regression.sh`) runs
`bench/locbench/test_placebo_arms.py`: exact byte size at 65 targets, format identity, XML well-formedness
at 1,100 consecutive targets, exclusion of the real answer's files on a fixture whose universe does contain
them, determinism, fail-closed on an undersized pool, file-level BM25, one arm on real ripwire output, and an
offline end-to-end `main()` run. Red on the base commit (the builders did not exist), green on the tip.

## Models (frozen)

LocBench itself is LLM-free: `run_locbench.py` scores ranked lists and drives no model. The model loop is the
agent driver below. Models are chosen to replicate Bellam's scale finding at its two informative points and
to add one API tier:

| id | model | serving | why |
|---|---|---|---|
| **M1** | Qwen3-4B | local (vLLM or Ollama through the opencode harness), FP16/BF16 | **small open model**; Bellam's family, the size where his gains were largest and placebo harm appeared |
| **M2** | Qwen3-14B | local, same | the largest size where Bellam still found a significant gain |
| **M3** | `claude-haiku-5-5` | Anthropic API | the cheapest current API model; checks the result is not an open-model artefact |
| M4 (optional) | `claude-sonnet-5-5` | Anthropic API | scale contrast at K=1 only; runs only if the owner approves its line in the cost table |

Thinking: Qwen3 non-thinking mode (Bellam's main condition); Haiku 5.5 at its default adaptive thinking, effort
`low`. Sampling temperature: the provider default, identical across arms; seeds vary only the sampling seed.
Gemma is out: Bellam's Gemma 4 12B rarely submitted an answer, which tests submission, not localization.

## Agent driver contract (owed; frozen here so the driver cannot be fitted to the result)

- New file `bench/locbench/agent_loc.py`, its own gate, no ripwire binary on the child PATH.
- Reads only the sealed payload files from `--emit-payloads` and verifies each sha256 against the manifest;
  a mismatch refuses the episode.
- Tools: `grep(pattern, path_glob)` and `read(path, start, end)` over the checkout at `base_commit`, each result
  capped at 8,000 bytes with the cut disclosed; `submit(ranked list of up to 10 "path:function")`.
- Limits: 15 tool turns; a hard stop at 250,000 cumulative input tokens (the blow-up guard). An episode that
  ends without `submit` scores as a miss and is counted, never excluded.
- Records per episode: input tokens, output tokens, tool calls by kind, turns, submitted list, wall clock,
  `resolved_model` read back from the transcript (the opencode free-model fallback trap in
  `bench/agentloop/README.md`).
- The history-leakage guard `run_locbench.checkout()` already applies: only `base_commit` is fetched, so no
  future commit is reachable.

## Task set and seal (frozen)

- **LocBench V1 held-out split**: `frozen_partition()` salt `ripwire-a7-v2`, the 243 instances over 78 repos
  the A7 contract defines, from the frozen 560-row file whose SHA-256 the harness already enforces
  (`5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97`). Zero exclusions: an instance that
  fails anywhere stops the run (zero-silent-skip), it is never dropped.
- **Pilot instances** come from the **train** split (24, repo round-robin by `instance_id` order), so the
  held-out set is untouched until the primary run.
- **Payload seal.** Stage 0 writes every arm's payload with `--emit-payloads`. The SHA-256 of the sorted
  concatenation of all per-instance `manifest.json` files is recorded in the ADDENDUM **before any model
  call**. The binary is pinned by commit; its `--version` line goes in the ADDENDUM too.
- **Contamination, stated plainly.**
  - ripwire was tuned on the train split, and the held-out split has been read for acceptance before (A7,
    r1, r3, r5 single held-out runs). That biases the held-out set **toward ripwire**. A ripwire loss here is
    robust to it; a ripwire win carries this caveat in every place it is quoted.
  - LocBench issues are public GitHub history, so models may have seen the fixes. A0 measures that
    memorisation floor. The paired design raises every arm by the same memorised amount to first order.
  - If the rows carry an issue date, the harness reports the post-release stratum per model (Bellam's
    replication check); otherwise that stratum is declared unmeasurable, not zero.
- Gold, answer and held-out row contents were not opened in writing this file.

## n, and the power reasoning

Primary contrast: A1 vs A2, paired by instance, per model. 243 instances × 4 primary arms × K=3 seeds = **2,916
episodes per model**. The secondary arms A2s and A1p run at K=1: 486 more. Total **3,402 per model**, plus a
96-episode pilot (24 × 4 × 1).

The arithmetic, with every assumption named:

- per-instance paired difference of a binary hit, one seed: variance ≈ d − δ², with **d = 0.30 assumed**
  discordance between two different payloads (Bellam's small-model regime; to be measured in the pilot);
- seed averaging, K=3, **assumed half the variance is seed noise**: 0.296 × (0.5 + 0.5/3) = 0.197, SD 0.444;
- repository clustering: 243 / 78 = 3.1 instances per repo, **assumed ICC 0.05**, design effect
  1 + 2.1 × 0.05 = 1.105, √ = 1.051;
- SE = 0.444 × 1.051 / √243 = **0.0299**;
- one-sided α = 0.05, power 0.80: MDE = (1.645 + 0.842) × 0.0299 = **7.4 pp**; Holm over three models (worst
  step α = 0.0167, z = 2.128): MDE = (2.128 + 0.842) × 0.0299 = **8.9 pp**.

So at the held-out set's fixed size this design can detect the **upper half** of Bellam's range (+6 to +10 pp)
and cannot reliably detect +3 pp. That is reported as a limit, not tuned away. The train split is not pooled
in to buy power: ripwire was tuned on it, which would inflate A1.

**Pre-registered power check.** The pilot measures d and the seed share. If the measured values put the
primary model's Holm MDE above 10.0 pp, K rises from 3 to 5 for the held-out run (Bellam's seed count),
decided from pilot **variance only**, never from a pilot effect, and recorded in the ADDENDUM before the
held-out run. If K=5 still leaves the MDE above 10.0 pp, the round runs and is labelled underpowered up
front; a null is then "not detected", never "no effect".

## Metrics (frozen, in decision order)

1. **Primary: function-level hit@10** — any covered gold function (`run_locbench.covered()`, the exact
   path + scope + name identity) in the agent's submitted top 10, averaged over seeds per instance. Function
   level matches Bellam's Acc@10; the any-hit form is used because strict all-gold at function level sits
   near the floor for a deterministic ranker (6.2% strict vs 11.1% any on the full set, README).
2. Secondary localization: file-level hit@5, strict file@10, strict func@10 — same scorer.
3. Secondary cost: **tokens to a correct localization** (an episode's input + output tokens, counted only on
   episodes that hit), **bytes of payload** (equal by construction for A1/A2/A3/A2s — reported to prove it),
   **tool calls** by kind, and turns.
4. Stage 0 (no model): the payload-only hit@10 of each arm, scored by `run_locbench.py` itself. This is
   Bellam's "exposure" quantity: how often the payload alone surfaces the gold.

## Bars (frozen; absolute or net completion, never a relative byte bar)

Per model, paired over the 243 held-out instances, repo-clustered bootstrap (10,000 resamples, fixed seed
`ripwire-placebo-v1`), one-sided 95% lower bounds, Holm across the models run:

- **B1, ranking-signal claim (the ship bar).** A1 − A2 on primary hit@10: mean ≥ **+3.0 pp** absolute AND
  lower bound > **0**. Loss bar: on the single-file and the multi-file stratum separately, A1 − A2 lower
  bound > **−2.0 pp**. No stratum may pay for the other.
- **B2, fair-lexical claim.** A1 − A3: *superiority* if lower bound > 0; *non-inferiority* if lower bound >
  **−3.0 pp**; otherwise ripwire **loses** to whole-file BM25 at the same bytes and format.
- **B3, completion bar against the floor.** A1 must not lose completions to A0: instances that A0 hits in a
  seed-majority and A1 misses ≤ instances the other way, and A1 − A0 lower bound > **−2.0 pp**.
- **Tokens.** No relative token or byte bar. Tokens to a correct localization are reported in absolute
  tokens per arm. The only token limit is the blow-up guard: 250,000 input tokens per episode. If a net price
  is quoted, it is ΔSE ≈ −Δcomplete·F·R + Δtokens·R with F, R and the B/token band (o200k 2.44–4.66) stated,
  and only beside B1 and B3 — net-SE never stands alone as a bar.
- A2 − A0 is reported with its interval. Bellam found placebo **harm** for small models; that is a finding
  about answer-shaped noise, not a ripwire bar.

## Stopping rule (frozen)

0. **Stage 0, $0, no model.** One `run_locbench.py --split=heldout --arms=for,for-matched,placebo,placebo-shuffle,lexical,query --emit-payloads=DIR`
   on the pinned binary. It needs network for the public clones only. Then the payload seal goes in the
   ADDENDUM. Any `PLACEBO UNBUILDABLE` instance stops the round, and this file gets an ADDENDUM rule before
   any model call. No instance is dropped quietly.
1. **Pilot (train split, 96 episodes per model).** Checks isolation (no ripwire on PATH, no network beyond
   the provider), `resolved_model`, the token rate, submission rate, d and seed variance. Stop and ask again
   if the realised mean cost per episode exceeds **2×** the central estimate below. A model whose submission
   rate is below **50%** is dropped from the primary family before any held-out episode, and that is disclosed.
2. **Primary run.** Fixed n. No interim look at any arm contrast. Analysis runs once, after every episode
   has completed. Provider errors retry up to 3 times; a persistent failure scores as a miss and is counted.
3. **Spend cap.** The approved budget is a hard stop. A run cut short by it reports as incomplete, with no
   verdict on B1–B3.

## What counts against ripwire (frozen, published either way)

- **B1 fails** on a model: for that model, ripwire's ranking shows no measurable localization gain over a
  same-size, same-format random answer. The README's localization claims get scoped to "an answer of this
  size helps", and the result is a §5 negative in `docs/EVALS.md`.
- **B2 fails non-inferiority**: whole-file BM25 at the same bytes localizes better. Then neither the lens nor
  the graph carries a localization claim over lexical retrieval. That is Bellam's and Xue's finding,
  replicated against ripwire.
- **A1 ≈ A2 but both > A0**: the gain is exposure and answer size, not ranking.
- **A1 ≈ A2s** (order-only placebo): the content set matters and the order does not, a weaker claim than "the
  ranking helps".
- **A1 < A0** on a small model: ripwire's answer harms that model. This is published with a small-model
  guidance note.
- The direction of the contamination caveat is fixed above: it can only make a ripwire **win** suspect.

## Live-round cost estimate (from first principles; no model has run in this harness)

No LocBench results metadata carries model tokens: every run here is LLM-free. The payload size is the only
measured input (5,056 B mean production `--for`, train n=254). Everything else is an assumption the pilot
replaces.

Per-episode tokens, central:
- fixed prompt (system + tool schemas) **1,500**, query ≤1,200 chars ≈ **300**, payload 5,056 B / 2.36 B/tok
  (the harness's conservative ceiling) ≈ **2,142** → turn-0 context **3,942** (A0: 1,800);
- 8 tool turns, each adding a ≈1,500-token result + 150 output tokens = 1,650 per turn;
- input summed over the turns (the context is re-sent each turn, no caching assumed):
  Σ_{t=0..7} (3,942 + 1,650 t) = 8 × 3,942 + 1,650 × 28 = **77,736 ≈ 80K input**;
- output 8 × 400 (thinking included) = **3,200**.
- Upper bound, 15 turns and 6,000 output: 15 × 3,942 + 1,650 × 105 = **232,380 input**. The largest single
  request is 3,942 + 1,650 × 14 = 27,042 tokens, under Haiku 5.5's 100K-prompt price step.

Prices: the Anthropic first-party table cached 2026-11-03 — Haiku 5.5 $0.10 / $0.50 per MTok in/out,
Sonnet 5.5 $2 / $10. Re-check live prices before approval.

| model | episodes | $/episode central | central | upper |
|---|---|---|---|---|
| M3 Haiku 5.5 | 3,402 + 96 pilot = 3,498 | 80K × 0.10 + 3.2K × 0.50 = $0.0096 | **$34** | 232K × 0.10 + 6K × 0.50 = $0.0262 → **$92** |
| M4 Sonnet 5.5 (optional, K=1, 4 arms) | 972 + 96 = 1,068 | 80K × 2 + 3.2K × 10 = $0.192 | **$205** | 232K × 2 + 6K × 10 = $0.524 → **$560** |
| M1 Qwen3-4B / M2 Qwen3-14B | 3,498 each | $0 API | compute only | — |

Local compute is the binding constraint for M1/M2. Assume ≈2 min per episode for 4B and ≈6 min for 14B on
this machine (prefill ≈80K tokens + ≈3.2K generated; an assumption, n=0). That is ≈117 h for M1 and ≈350 h
for M2 for the full matrix. The pilot measures the real rate, and M2's held-out run needs its own go-ahead.

**Totals:** API **$34 central / $92 upper** without M4; **$239 / $652** with M4. M1/M2 add no API spend. The
pilot's realised rate replaces these figures before the primary run (the 2× stop above). Earlier estimates
in this repo, all extrapolated from one measurement, came in optimistic.

## What the owner must approve (nothing runs without each)

1. **Stage 0**: one deterministic held-out run with public `git fetch` clones, no model, $0.
2. **The agent driver lane** (`agent_loc.py` + gate) against the contract above.
3. **Models**: M1 and M2 served locally (≈117 h and ≈350 h of machine time), and M3 Haiku 5.5 on the API
   (≈$34, cap $92).
4. **Optional M4** Sonnet 5.5 (≈$205, cap $560).
5. **The pilot** (96 episodes per model) before the held-out run, and the billed credential for M3/M4 named
   per run, per `bench/agentloop/README.md`'s safety note.

## What would make this round worthless

Reading any held-out arm contrast before the full run; choosing K, the budget B, the BM25 parameters, or the
primary k after seeing a model's held-out numbers; dropping an instance that failed; or quoting A1 − A0 (the
having-a-tool effect) as if it were A1 − A2 (the ranking effect). METHODOLOGY §8 calls the last one a
different and weaker claim. This file is written first so none of them can happen quietly.

## ADDENDUM (append-only, after freeze)

- **2026-11-26, A1: one common budget B\* for every arm (builder closure fix). No model episode had run.**
  Stage 0 stopped at its first held-out instance with `PLACEBO UNBUILDABLE`: the lexical arm found no exact
  18,048-byte closure. A $0 count on the 24 pilot TRAIN instances (no gold read, no model) then found
  for-matched unbuildable on 9, placebo on 10, and lexical on 17. All four arms built on 7 of the 24.
  - *Cause.* The ordered arms (for-matched, lexical) close with one try. Real rows have long attribute heads
    and short signatures (16–95 chars). So the gap left after the greedy prefix (134 B in the measured case)
    is often smaller than the next row's minimum size (331 B), and trimming at most two signatures cannot
    close it. The original gate's fixture used long signatures and so never exercised this.
  - *Rule.* The matched budget B (above) becomes the **requested** budget. Every derived arm (for-matched,
    placebo, placebo-shuffle, lexical) is built at **B\* = the largest size ≤ B at which all four close
    exactly**. All four are always built, so no payload depends on which arms a run requests. Each instance
    records `requested_bytes` and `budget_shortfall = B − B*`, and the run reports their distribution. If no
    common size exists at all, that is still `PLACEBO UNBUILDABLE` and still stops the round.
  - *Why it cannot favour an arm.*
    - B\* is one number applied to all arms, so every arm pays the same shortfall and the byte-equality
      contract holds exactly.
    - B\* is computed only from row byte lengths in ripwire's own exports and the BM25 file order. It takes
      no gold argument, no score and no model output, so it is as gold-blind as the builders.
    - It is the maximum of an intersection, so the order the arms are tried in cannot change it.
    - A1 is still ripwire's own prefix in ripwire's order with at most two trimmed tail rows. The placebo
      still excludes the answer's files. A1p (the shipped payload) is unchanged.
    - Format identity, the legend bytes and the root attribute names are untouched. No pad, filler row or
      non-ripwire element is added.
  - *What it costs.* A1, A2, A3 and A2s are up to `budget_shortfall` bytes smaller than the shipped answer's
    size. The shortfall is reported beside every byte figure, never folded into B.
  - *Gate.* `test_placebo_arms.py` `test_short_signature_closure` uses a fixture with 16–95-char signatures
    and checks 276 budgets. It is red on the original builder (194 of 276 budgets raised `PLACEBO UNBUILDABLE`;
    6 checks fail) and green after the fix, with a largest shortfall of 510 B on that fixture.
  - *Re-count on the 24 pilot TRAIN ids, fixed builder, /bin/zsh.* All four arms build on 24 of 24. The shortfall
    B − B\* per instance: 0 B on 7, median 62.5 B, mean 373.0 B, above 500 B on 3. The largest are 4,586 B
    (Happy-Algorithms-League__hal-cgp-180) and 2,422 B (alexa-pi__AlexaPi-188), both small repositories whose
    unrelated-file pool cannot fill the full budget.
- **2026-11-26, Stage 0 re-run under A1: stopped again. No seal is recorded and no model episode has run.**
  - The re-run stopped at its fifth held-out instance, `avantifellows__quiz-backend-84`. The A1 rule does not
    cover this case: the `--for` answer names every file in the indexed universe, so the unrelated-file
    placebo pool is empty and no common size exists.
  - A $0 count followed, with no model and no gold field read. It covered all 306 rows of the held-out
    partition (88 repos) and ignored the harness's gold-based unindexable filter, so it is a superset of the
    243 instances. Result: 302 build under A1, and 4 do not.
    - Empty placebo pool: `avantifellows__quiz-backend-84`, `duncanscanga__VDRS-Solutions-73`,
      `rapidsai__dask-cuda-98`.
    - No common exact size at or below 13,726 B: `SYSTRAN__faster-whisper-1198`.
  - Shortfall B − B\* over the 302 that build: 0 B on 89, median 66 B, mean 137.8 B, 90th percentile 234 B,
    above 1,000 B on 3, maximum 5,938 B.
  - The payload-only metrics were not computed or read.
  - Per the stopping rule, these 4 need a rule here before any model call. Choosing that rule is an owner
    call.
  - The pilot's TRAIN payloads are sealed and are not the held-out seal: 24 manifests,
    SHA-256 `69b32fc028aef30b4906ba086776b9bfb5dbe3bfeef3548643c6692f269949f1`, binary
    `ripwire 0.7.0-dev.20+gfe40f1d71`, every arm built on 24 of 24.
- **2026-11-26, A2: an unbuildable instance is excluded from every arm (owner ruling). No held-out model
  episode has run.** The 24-instance TRAIN pilot (Haiku 5.5) was running when this was written. It touches no
  held-out instance.
  - *Rule.* An instance is excluded from **every** arm and counted when its derived arms cannot be built
    under A1: the unrelated-file placebo pool is empty, or no common exact size exists at or below B. Every
    arm includes A0, the shipped `for` and A1p. The run's JSON lists each excluded instance by id
    (`excluded_unbuildable_a2`) and reports the count beside the other exclusions. No payload is sealed for
    it.
  - *The test runs before the gold-based scoring.* It reads only ripwire's own exports, the issue text and
    row lengths. The set is therefore computed by the rule, never by name: on the 243 it need not be exactly
    the 4 the 306-row count found.
  - *Why it cannot favour an arm.*
    - The criterion is gold-blind and model-blind. It is fixed by repository shape: an answer that already
      names every file, or row lengths with no common exact size.
    - Every arm loses the same instances, so each paired contrast (A1−A2, A1−A3, A1−A0) runs over the
      identical task set.
    - It does not depend on any arm's outcome. It is decided before any episode and before any score.
    - It narrows the population, and every published number states it as n = 243 − excluded.
  - *What it costs.* The held-out n falls by the excluded count, and the power arithmetic above uses n = 243.
    The MDE is reported at the realised n, never at 243.
  - *Gate.* `test_placebo_arms.py`'s offline `main()` run on a fixture whose answer names every file now
    requires exclusion by id, n = 0 in every arm, and no sealed payload. Two checks are red on the A1 tip
    `315b057f1`, which aborts; all three are green after.
- **2026-11-26, Stage 0 sealed under A1 + A2. No held-out model episode has run.**
  - Run: `run_locbench.py --n 560 --split=heldout --arms=for,for-matched,placebo,placebo-shuffle,lexical,query --emit-payloads`
    at commit `464a902b7`, binary `ripwire 0.7.0-dev.20+gfe40f1d71 (dev, AppleClang 21.0.0.21000101,
    emit=std::print, act=on, rows=lines, built_from=fe40f1d71)`.
  - The 560-row hash check passed. Exit 0.
  - **Excluded by rule A2:** 4 instances, computed by the rule, not by name.
    - 3 with an empty unrelated-file pool: `avantifellows__quiz-backend-84`, `duncanscanga__VDRS-Solutions-73`,
      `rapidsai__dask-cuda-98`.
    - 1 with no common exact size at or below 13,726 B: `SYSTRAN__faster-whisper-1198`.
    - The other exclusion counters are all 0: nonpy, checkout, ctx and unindexable.
  - **Payload seal:** 302 instance manifests. SHA-256 of their sorted concatenation:
    **`4bc5f5114d4c8518a684eaaa62a61d3af60d3262a66833290414fe866eaf5a17`**.
  - The payload-only metrics were written to a file nobody has read. Only the header's `n_scored` and
    exclusion counts were read.
  - **Discrepancy with the text above (owner call).**
    - The held-out partition this harness selects is **306 rows over 88 repos**, so the scored n is
      **302**. The "243 instances over 78 repos" written above does not match this harness at this seal.
    - The 306 count was made with no gold read. It is also consistent with the train side: 560 − 254 = 306.
    - The power arithmetic is reported at the realised n = 302 beside the frozen 243, and n is not changed
      silently.
- **2026-11-26, the 243 is a different split (a fact for the owner; no rule here). No held-out model episode
  has run, and none will until the owner rules.**
  - The "243 over 78 repos" (README, `docs/EVALS.md` §3: train 317/87, held-out 243/78) is the split
    produced by salt **`ctxpack-a7-v2`**.
  - Commit `3315fb19d` (2026-07-31, "rename: ctxpack -> ripwire … mechanical sweep") rewrote
    `frozen_partition()`'s salt to `ripwire-a7-v2`. That gives a different split, **held-out 306/88 and train
    254**, and it is the split this harness, `dataset.lock`, the Stage 0 seal above and the TRAIN pilot all
    used.
  - Measured on repository names only, with no gold read:
    - 138 instances (39 repos) are held-out under both salts.
    - **10 of the 24 pilot instances, which a model has already seen, are held-out under `ctxpack-a7-v2`.**
    - 3 of A2's 4 excluded instances fall inside that 243.
  - The 302-manifest seal above covers the `ripwire-a7-v2` held-out set, not the 243.
  - The owner needs to rule on which split is the held-out one, and on what the 10 pilot-touched instances
    mean, before any held-out episode.
- **2026-11-26, owner ruling: the held-out set is `ripwire-a7-v2`, n = 302. No held-out model episode had
  run when this was written.**
  - **n.** The held-out set is the current `ripwire-a7-v2` split: 306 tasks over 88 repos, **302 after rule
    A2**. It is exactly the Stage 0 seal above (`4bc5f511…5a17`, 302 manifests).
  - **The 243 is superseded.** The text above saying "243 instances over 78 repos", and every 243 in the
    power section, describes the pre-rename split.
  - **Why.** Commit `3315fb19d` (2026-07-31) renamed the salt from `ctxpack-a7-v2` to `ripwire-a7-v2`, which
    changed the split. Every tuning run since then used the new train side. That makes the old 243 the
    contaminated set: 105 of its instances sat on that train side during tuning, and 10 of them were seen by
    the TRAIN pilot. The new held-out side was touched by neither post-07-31 tuning nor the pilot.
  - **Power restated at n = 302.** The pilot measured d = 0.208 for A1–A2. The seed share stays at the
    assumed 0.5. The design effect √ stays 1.051.
    - K = 3: Holm MDE **6.69 pp** (one model). K = 5 would give 6.35 pp.
    - Both are below 10.0 pp, so K stays **3**, decided from variance only.
  - **Provider errors (owner ruling, replaces stopping rule 2's "persistent failure scores as a miss").** An
    episode that ends on a provider error (a 429 or any CLI error) is re-run once. A provider error is never
    counted as a miss. If the re-run also fails, the run stops and resumes later; the episode is never dropped
    silently.
  - **Rolling token stop.** The run stops and reports if the mean input tokens of the last 50 episodes exceed
    2 × 33,525. That figure is the pilot's mean input per episode.
  - **Unchanged.** Models: Haiku 5.5 only, effort low, claude.ai subscription through the CLI. K = 3 on
    A0–A3 and K = 1 on A2s and A1p, giving 302 × 4 × 3 + 302 × 2 = 4,228 episodes. The bars B1–B3 are as
    frozen, and Holm runs over the one model.
- **2026-11-26, correction to the n = 302 entry, before the first held-out episode.** That entry gave 6.69 pp
  as the "Holm MDE (one model)", but 6.69 pp uses the three-model worst-step z = 2.128. Holm over one model
  is the unadjusted one-sided α = 0.05 (z = 1.645). The corrected one-model MDE at n = 302, K = 3, d = 0.208
  and assumed seed share 0.5 is **(1.645 + 0.842) × √(0.208 × (0.5 + 0.5/3)) × 1.051 / √302 = 5.61 pp**.
  At the three-model z it is 6.69 pp. Both are below 10.0 pp, so K stays 3.
