# `--adaptive` on short and low-content queries — an investigation, not a fix

Status: **research only**. No `src/` change on this branch. Everything below is measured against the
binary as it ships today (`0.6.1`, commit at the head of `lane/research-adaptive-shortquery`).

**Outcome (added 2026-09-21).** The defect this investigation found — a name-exact cut firing on a
large pool of identically-named symbols, where the gap is tie-break order rather than a relevance
cliff — was fixed in a separate lane and **released in v0.6.2** (2026-09-21). `--adaptive` now
declines to narrow when a name-exact route's positive pool clears `kAdaptiveHomonymPoolFloor` (50)
and the proposed cut is at most twice the floor: the default top-N is served, an in-band note gives
the pool size and says the gap is tie-break order, and `confidence=` no longer claims `high` on a cut
it declined to trust. `margin_pct=` keeps the true measured drop. See the `## [0.6.2]` section of
`CHANGELOG.md`. This branch still carries no `src/` change, and every measurement below is the
pre-fix behaviour, left exactly as recorded.

## The question

Adaptive-k — [arXiv:2506.08479](https://arxiv.org/abs/2506.08479) — cuts a ranked list at its largest
relative score gap instead of a fixed k, because the knee moves by orders of magnitude between
queries. It ships here as `--adaptive` (`docs/LINEAGE.md`, `src/lexical.h::adaptiveCut`). The case we
expected a largest-gap cut to fail on is a short or low-content query: a thin score distribution
has no reliable knee to find.

Two adjacent, already-closed measurement rounds sit right next to this question in `docs/EVALS.md`
(search `abstention calibration`): both tried to calibrate an *abstention* decision — should the tool
refuse to answer at all — off `confidence=`/`margin_pct=` (round 1) and off the adaptive cut's own
`scored`/`corpus` support ratio (round 2), against the Agent Retrieval Bench's no-gold/positive split.
Both are recorded negatives: confidence separates answerable from unanswerable queries at
approximately chance (AUROC 0.48/0.51), and so does corpus support (0.43/0.41, and in the *wrong*
direction). The closing sentence of round 2 names the next candidate explicitly: *"a future round on
this axis needs a fact that is NOT derived from the lexical score distribution at all."*

This investigation does **not** repeat that round. It asks a narrower and different question: not
"can the tool tell whether a query is answerable", but "when `--adaptive` DOES cut, is the cut
trustworthy for a short or generic query, specifically". The answer turns out to be a mixed one, and
not the one the paper's framing alone would predict.

## Method

Built `./build/ripwire` from this branch's HEAD (dev config, no `Release`). Two corpora:

- **ripwire itself** — 20,217 symbols, its own C++23 source plus docs/bench/tests.
- **a private corpus** — a large private C++/Objective-C++/Metal application, 46,913 symbols
  including a vendored physics tree — a real polyglot corpus with none of ripwire's own vocabulary,
  so a finding that reproduces on both is not an artifact of self-reference. It is not part of this
  repository and is not redistributable, so every file path, type name and corpus-specific query
  below is redacted to a placeholder; only the counts it produced are reproduced verbatim.

Two instruments, both under `bench/adaptive_shortquery/`, both reproducible against the shipped
binary (pure function of scores → deterministic; verified byte-identical on a repeated `--for=update
--json` call against private-corpus, see below):

- **`run_adaptive_shortquery.py`** — five queries per corpus spanning the brief's axis: one common
  word, two words, a contentless instruction, a specific multi-word technical task, and a query naming
  a real symbol from that corpus. Each runs `--for=Q --json` with and without `--adaptive`, recording
  `confidence`, `margin_pct`, the disclosed `kept`/`scored`/`corpus` facts, and the actually-served row
  count.
- **`word_sweep.py`** — because the five-query set's own "common word" case ("value") turned out to
  behave safely, a wider sweep of 13 ordinary English verbs/nouns that also read as plausible C++
  identifiers (`get`, `set`, `init`, `update`, `run`, `load`, `name`, `data`, `test`, `add`, `remove`,
  `find`, `check`), same two corpora, `--for=W --json` only (the disclosed facts already show whether
  `--adaptive` would act).

Raw output: `bench/adaptive_shortquery/results_2026-09-20.json` (five-query set) and
`word_sweep_2026-09-20.txt` (word sweep). Both are re-run outputs, not hand-edited.

## Measured: the five-query set

| corpus | query kind | query | route | conf/margin | served (default) | served (`--adaptive`) |
| --- | --- | --- | --- | ---: | ---: | ---: |
| ripwire | common word | `value` | name-exact | high/45 | 6 | 5 |
| ripwire | two words | `data flow` | subtoken+body:broad | low/0 | 29 | 29 |
| ripwire | contentless | `summarize this` | subtoken+body:broad | low/0 | 35 | 35 |
| ripwire | technical multiword | `cut a ranked list at the largest relative score gap` | subtoken+body | high/23 | 26 | 5 |
| ripwire | named symbol | `adaptiveCut` | name-exact | high/45 | 4 | 4 |
| private-corpus | common word | `value` | name-exact | high/45 | 17 | 13 |
| private-corpus | two words | `«two-word domain phrase»` | subtoken+body:broad | low/0 | 35 | 35 |
| private-corpus | contentless | `summarize this` | subtoken+body:broad | low/0 | 29 | 29 |
| private-corpus | technical multiword | `«technical multiword task»` | subtoken+body | low/0 | 28 | 27 |
| private-corpus | named symbol | `«named symbol»` | name-exact | high/27 | 8 | 5 |

**First reading.** The cases we expected to be hardest for a largest-gap cut — a contentless instruction,
a broad two-word phrase — are already handled. `summarize this` and `«two-word domain phrase»` route to `subtoken+body:broad`, the adaptive
scan finds no material cliff (drop never reaches the 20% `kMinCliffDrop` floor), `confidence="low"` is
reported honestly, and **`--adaptive` is a byte-identical no-op**: served count is the same with or
without the flag on all four broad/contentless rows above. That is the correct, and already-shipped,
protection: the tool does not manufacture a cliff where the score distribution is flat.

The specific multi-word *technical* task query is the opposite case working as designed: it is
long and specific, routes to a sharper score distribution, `--adaptive` narrows 26→5 (ripwire) with
`confidence="high"`, and (eyeballed) the top of that narrowed set is `AdaptiveCut`,
`kForConfidenceNote`, `buildMaskedRank`, `adaptiveCut`, `RecallSelection` — a genuinely tight,
relevant cluster for a query about score-gap cutting. This is the tool doing exactly what
Adaptive-k proposes.

The one row that does not fit either story cleanly is the single common word. `value` on private-corpus
keeps 13 of 17 — mild, plausible. But this is not representative of "single common word" as a class,
which the wider sweep below shows.

## Measured: the word sweep — the real failure mode

The single-word queries above route to **name-exact**, not `subtoken+body`. That routing choice
matters: a literal identifier match produces a candidate set of every symbol in the corpus with that
*exact* name, and nothing else. For an English word that also happens to be a common short method
name, that candidate set can be large and made of entirely unrelated symbols that merely share a
name.

| corpus | word | route | conf/margin | kept | scored (positiveHits) | discarded |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| private-corpus | `update` | name-exact | **high**/25 | 6 | **231** | **97%** |
| ripwire | `run` | name-exact | **high**/27 | 10 | **148** | **93%** |
| private-corpus | `init` | name-exact | **high**/25 | 7 | 56 | 88% |
| ripwire | `find` | name-exact | high/45 | 5 | 19 | 74% |
| private-corpus | `get` | name-exact | low/0 | 40 | 108 | 63% (no cut — protected) |
| private-corpus | `name` | name-exact | low/0 | 40 | 131 | 69% (no cut — protected) |
| private-corpus | `add` | name-exact | high/36 | 35 | 36 | 3% (cut, but harmless) |
| private-corpus | `remove` | name-exact | high/27 | 23 | 24 | 4% (cut, but harmless) |
| private-corpus | `find` | name-exact | high/27 | 25 | 27 | 7% (cut, but harmless) |
| private-corpus | `set` | name-exact | high/45 | 31 | 37 | 16% (cut, but harmless) |
| private-corpus | `check` | name-exact | high/45 | 11 | 13 | 15% (cut, but harmless) |
| private-corpus | `run` | name-exact | high/36 | 14 | 17 | 18% (cut, but harmless) |

Full 13-word × 2-corpus table: `bench/adaptive_shortquery/word_sweep_2026-09-20.txt`.

**`update` on private-corpus is the clean example.** 231 symbols are literally named `update` (every
class in a large application has one). `--adaptive` reports `confidence="high"`, `margin_pct="25"`, and
serves 6. The served six:

```
1 update  ‹file A›
2 update  ‹file B›
3 update  ‹file C›
4 update  ‹file D›
5 update  ‹file D›
6 update  ‹file E›
```

Ranks 7–12, discarded, are just as plausible a reading of the bare word "update" as ranks 1–6:

```
7  update  ‹file F›  ‹class 1›
8  update  ‹file F›  ‹class 2›
9  update  ‹file F›  ‹class 3›
10 update  ‹file G›  ‹class 4›
11 update  ‹file H›  ‹class 5›
12 update  ‹file H›  ‹class 6›
```

Nothing in the query ("update") picks between these. The 25% drop the cut fired on is real — it is
not float noise, `kMinCliffDrop` is 20% and this cleared it — but it is a drop in whatever secondary
key breaks the tie among 231 identically-scored-on-lexical-grounds symbols (PageRank centrality is
the leading candidate; `sc=` — the containing class — is absent on the top six, present from rank 7
on, which is itself suggestive of a centrality/file-layer split rather than a relevance split). The
shape statistic cannot tell a *semantic* cliff from a *tie-break* cliff, because it never looks at
what produced the gap, only that one exists. `ripwire`'s own `run` (148 hits, 10 kept, 93% discarded,
ranks 9–14 of which are prose mentions of "run" in `CHANGELOG.md`/`bench/fixround/RESULTS.md` rather
than code at all) reproduces the same shape on a different codebase and a different word.

**This is not the same failure the two closed EVALS rounds tested, and does not reopen them.** Those
rounds asked whether `confidence=`/`margin_pct=`/`scored÷corpus` predict *answerability* — whether a
gold answer exists at all — across ARB's realistic query mix, and found near-chance separation twice.
This investigation asks a narrower question: given a query that is unambiguously *answerable* in the
trivial sense (the literal name exists, sometimes hundreds of times), is the adaptive cut's *choice of
which few instances to keep* trustworthy. It is not, for large homonym clusters, and the two questions
are genuinely different — a query can be perfectly "answerable" (`update` obviously names something
real) while the specific six the cut picked are an arbitrary sixth of an undifferentiated 231.

**The failure is not simply "the query is short."** `adaptiveCut` and `«named symbol»` are also
one-token queries and work exactly as intended (4→4, 8→5, both tight and correct on inspection — see
the five-query table). `init`, `set`, `data`, `test` on ripwire have small homonym pools (4–8 hits) and
a floor-clamped or near-total keep, which is honest. The discriminator in this data is not query
length or word count, it is **homonym-cluster size under name-exact routing**: a handful of harmless
cuts (`add`, `remove`, `find`, `set`, `check`, `run` on private-corpus — pools of 13–37, cuts that keep
70–96% of them) sit right next to the two dramatic ones (`update` 231→6, ripwire `run` 148→10) with no
clean separation by query surface features alone — only by the pool size the router already computes
and currently uses for nothing but the "sharp query, short tail" wording in the adaptive note.

**Also notable: the same mechanism is inconsistently protected.** `get` (108 hits) and `name` (131
hits) on private-corpus land on the SAME large-pool-common-word pattern as `update` (231) and `init`
(56), but happen to get `confidence="low"` and a full no-cut serve, purely because their particular
score distribution didn't clear `kMinCliffDrop` within the first 40 ranks. Whether a large homonym
pool is protected or not is presently a coin flip of where the tie-break scores happen to dip, not a
property the tool checks for.

## Answering the brief's three questions

**1. What does `--adaptive` do today, measured.** See the two tables above. On broad/contentless
queries it is a correct, disclosed no-op. On long, specific technical queries it cuts sharply and
well. On short queries specifically, behavior splits on a factor the paper's own framing does not
name: whether the query is a name-exact hit against a large, semantically flat homonym cluster.

**2. Is the failure real, or already covered?** Both, on different axes:

- **Covered:** the low-content-instruction / broad-phrase case we expected to be hardest. `subtoken+body:
  broad` + no material cliff + `confidence="low"` + `--adaptive` no-op, reproduced on both corpora, four
  for four. Nothing to fix here — a genuinely negative result on the axis the task description leads
  with.
- **Real and uncovered:** the homonym-cluster case. `confidence="high"` fires on the same shape
  statistic whether the cliff is semantic or a tie-break artifact inside hundreds of identically-named,
  unrelated symbols, and `--adaptive` then discards the majority of an undifferentiated pool while
  reporting the served remainder as high-confidence. Measured on two corpora with two different common
  words (`update` 231→6, `run` 148→10), both ≥90% discarded.

**3. The smallest honest fix, and why.**

Proposed: **decline to cut, and disclose why**, gated on a compound, already-computed pair of facts —
`route == name-exact` **and** `positiveHits` (the homonym pool `AdaptiveCut` already counts, presently
harness-only) large enough that the pool is not a small, disambiguated set, **and** the would-be cut
lands near the floor (a large discard ratio) rather than trimming lightly. Concretely: something in
the shape of `positiveHits > kAdaptiveHomonymTrustCeiling && kept <= 2 * floorK` — a threshold to be
set from an expanded version of this sweep, not guessed here. On decline, fall back to the fixed
top-N and add a fifth disclosed-note branch next to the four `--adaptive` already prints: *"N symbols
share this exact name; the score gap here reflects tie-break order, not relevance — showing the
default top-K; add a second term to narrow it."*

Why this shape over the brief's other two candidates:

- *Not* "decline to adapt below a query-content threshold" measured by word count or a stopword ratio.
  The data above shows content length does not separate the failing cases from the working ones:
  `adaptiveCut` and `update` are both one token; one works perfectly, the other discards 97% of an
  undifferentiated pool. A length/stopword gate would either miss `update`/`run` (false negative on
  exactly the case that motivated this investigation) or block `adaptiveCut`/`«named symbol»`
  (false positive on cases already measured to work well). It optimizes the wrong axis.
- *Not* "widen the gap requirement as content falls" (a continuous version of the same idea). Same
  objection — there is no content-derived dial that separates `update` from `adaptiveCut`; widening
  `kMinCliffDrop` uniformly would either still let `update` (25% drop, comfortably above today's 20%
  floor) through, or would have to widen so far it starts declining genuinely sharp technical-multiword
  cuts too, which the five-query table shows working correctly today.
- The compound homonym-pool gate uses a fact the code already computes for a different purpose
  (`AdaptiveCut::positiveHits`) — no new scorer, matching the discipline every EVALS round on this axis
  has held to ("the SAME `adaptiveCut` call... no second scorer"). It is also mechanically distinct
  from `confidence=`/`margin_pct=`/`scored÷corpus`, so it does not re-run either closed round; it asks
  whether the CUT is trustworthy given the shape of the pool it cut from, not whether the QUERY has a
  gold answer.

What would make me reject it, stated now: if an expanded sweep (below) cannot find a single
`(positiveHits threshold, discard-ratio threshold)` pair that separates the harmless cuts observed here
(`add` 36→35, `remove` 24→23, `find` 27→25, `set` 37→31, `check` 13→11, `run`-on-private-corpus 17→14 —
all name-exact, all cut, none harmful) from the two dramatic ones (`update` 231→6, `run`-on-ripwire
148→10) without misclassifying a meaningful share of either group; or if the fallback's fixed top-N
turns out, on inspection, to be no more useful than the cut it replaces (i.e., a homonym cluster this
large is uninterpretable either way, and the honest answer is a *disclosed low-confidence*, not a
different-shaped serve) — that would argue for reusing the existing `confidence="low"` path with a
clearer note instead of a new decline branch, which is a smaller change and worth measuring first.

**4. What we would NOT do on this branch.** No `src/` change ships here. (The fix itself landed through a
separate lane and shipped in v0.6.2 — see Outcome at the top of this document.) This is the investigation the
brief asked for; a fix round would need its own registration, gates, and red/green pair against a
gate that currently does not exist.

## Pre-registered measurement for the fix (not run — this section is the registration, to be executed
## in a future fix-round lane, BEFORE any threshold is tuned against real rows)

**Instrument.** Extend `word_sweep.py`'s query list from 13 to a larger set (target: ≥40) of common
English verbs/nouns that are plausible short identifiers, drawn from a source not chosen by this
investigation after seeing failing cases (e.g. the 50 most frequent English verbs, filtered to those
that parse as valid C-family identifiers) — to avoid the failure mode where a threshold is fit to the
two examples that motivated it. Run against ≥3 corpora (ripwire, private-corpus, and one more not yet
touched by this investigation) with the shipped binary, `--for=W --json`, both with and without the
proposed fix's decline gate compiled in (an A/B binary pair, not a flag — the decline behavior would
not be optional per the "no new operating point without a licensed one" discipline this codebase
already holds to for the abstention axis).

**Band.** For each `(positiveHits, discard-ratio)` threshold pair under test:

- **False-negative check** (fix misses a real homonym-noise case): among rows with `positiveHits ≥ 50`
  observed on this branch's data (`update` 231, `run` 148, `init` 56), the gate must fire on **100%**
  of them at the chosen threshold — this is a small, known set, zero tolerance is achievable and the
  bar is deliberately strict because these are the exact motivating cases.
  Note: this repeats a caution the ARB rounds already learned the hard way — a threshold fit only to
  the cases that motivated it will pass its own check trivially; the real test is the next two rows.
- **False-positive check** (fix wrongly declines a good cut): on the expanded ≥40-word sweep, the
  share of rows where the gate fires AND a human reviewer (blind to which arm produced which set,
  reading only symbol name + path + containing class) judges the pre-fix `--adaptive` top-5 as
  *equal or better* than the fallback top-40's first five by relevance must be **≤ 10%** — i.e. the
  gate should almost never override a cut a human would have kept.
- **Harmless-cut preservation**: the six harmless cases already measured here (`add`, `remove`,
  `find`, `set`, `check`, private-corpus `run`) must NOT trip the gate at the chosen threshold — this is
  the compound condition's whole reason to exist over a bare pool-size cutoff.

**Self-reject rule.** If no single threshold pair clears all three bands simultaneously on the
expanded sweep, this is a third recorded negative on the same axis the two EVALS rounds already closed
twice, and the section 3 fallback (reuse `confidence="low"` with a clearer note, no new branch) is the
next candidate — not a smaller threshold search on the same statistic, which the EVALS closing note
already ruled out as a shape of fix.

**Determinism gate before any row is trusted**: the same one-sample-run-twice gate the EVALS
abstention rounds used, extended to the A/B binary pair (both binaries must reproduce byte-identical
output on a repeated call before any comparison between them is trusted).

## What we would like help with

We would welcome the paper's authors' view on two things this investigation could not settle from the
paper text alone:

1. **Homonym-cluster cuts specifically.** The paper's motivating examples are about *sharp vs. broad*
   query score distributions; we have not found in the published text a treatment of the case where
   the distribution is sharp (a real, material gap) but the thing being cut is a tie-break ordering
   over many identically-scored, unrelated items rather than a relevance ordering over a coherent
   candidate set. Is this a known failure mode of largest-gap cutting in the retrieval settings the
   paper evaluates, or is it specific to a symbol-retrieval setting where exact-name collisions are
   common in a way they might not be in the paper's corpora?
2. **A principled pool-size threshold.** Our proposed fix (section 3) picks a compound threshold
   empirically from twelve data points on two codebases — we know this is thin evidence for a general
   default. If the paper's own evaluation, or follow-on work we are not aware of, has a
   distribution-shape statistic that distinguishes "sharp because relevant" from "sharp because tied",
   we would rather adopt a known-good statistic than tune our own cutoff on a handful of examples.

## Reproducing this

```bash
cmake -S . -B build && cmake --build build -j8
python3 bench/adaptive_shortquery/run_adaptive_shortquery.py \
  --bin ./build/ripwire --out /tmp/results.json \
  --corpus ripwire=. --corpus private-corpus=/path/to/your/second/corpus
python3 bench/adaptive_shortquery/word_sweep.py \
  --bin ./build/ripwire \
  --corpus ripwire=. --corpus private-corpus=/path/to/your/second/corpus
```

Determinism spot-check performed for this document: `ripwire <private-corpus> --for=update --json` run
twice, byte-identical stdout both times.
