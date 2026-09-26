# Readability construct validity: what the lens claims, and how we would check it

Status: **investigation, not a conclusion.** This document states what `--readability` actually computes
and actually claims (read from the code, not assumed), designs a validation of its *ordering* against human
judgment that we have not yet run, and runs the two validations that need no human labels at all — reporting
their numbers whether or not they are flattering. It ends with what we would like help with from readability
researchers who study exactly this gap.

Two published results shaped where ripwire's readability lens sits, and both are **design influences, not
implementations** — nothing in `src/readability.h` runs a model or a judge:

- LLM judges of code readability lean on surface features rather than the construct itself — part of why
  ripwire's readability lens is a deterministic, closed-form formula (Halstead volume, token entropy, the
  Posnett sigmoid fit) instead of a model call, and why the underlying evidence is disclosed (`vol=`, `ent=`,
  `posnett=`) rather than a single opaque number.
- A study of prompt design's association with LLM-generated code readability found the overall role of
  prompt design bounded (Ye, Ran, Xu & Zhou, arXiv:2605.13280) — part of why ripwire's readability-adjacent
  gate (`--quality-delta`'s `verbosity` kind) runs **after** each edit, against the actual diff, rather than
  living inside a generation prompt as one more instruction competing with the rest of the prompt for
  effect.

Both are cited in the readability design note — an internal working document, not part of this
repository — at its §7, as the prompt-design-bounded finding (Ye et al., arXiv:2605.13280) and as "LLM
self-judges … fixate on surface features (CoReEval)" — see the reference list at the end of this document
for both arXiv identifiers. That design log already states
the honesty bound this document expands on: *"Everything here is a lens, never a verdict."* This document is
the follow-through on that bound — checking it empirically rather than repeating it.

## 1. What we actually compute, and what we actually claim (from the code)

`--readability` (`src/readability.h`) is a single closed-form pass per function or method:

- **V — Halstead volume**: `V = N · log2(η)`, `N` = operator+operand token count, `η` = distinct tokens.
- **E — token entropy**: Shannon entropy (bits) of the definition's own token-frequency distribution.
- **L — lines**: the physical line span of the definition (`Symbol::loc`), signature included.
- **P — Posnett score**: `P = sigmoid(8.87 − 0.033·V + 0.40·L − 1.5·E)` — the coefficients published in
  Posnett, Hindle & Devanbu, *A Simpler Model of Software Readability*, MSR 2011.

Three facts about how this is used, verified against the source rather than assumed:

**It is emitted, and used elsewhere in the tool, as an ORDERING, never as a grade.** The verb sorts rows
*least readable first* and says so in its own legend (`src/readability.h`, `kReadabilityLegend`):

> "P was fitted on snippets of 20 lines or fewer: read the ORDER, not the number, and never as a grade."

The header comment states the reason in more detail, and names the literature that forced this framing
rather than a house preference: *"Scalabrino ASE'17 and Trockman MSR'18 both find no readability metric
correlates strongly with measured understandability; Fakhoury ICPC'19 finds the classic models miss real
readability-improving commits. So P is never a grade, never a gate, and never a verdict — it orders a
worklist."* The published `README.md` repeats the same claim as an external-facing promise, in a table of
lenses deliberately kept *outside* the tool's evidence-weighted panel join. Its row for `--readability`
reads, across that row's "why beside the join" and "on this repo" cells: *"the fitted score saturates past 20
lines — only the ordering is meaningful, and an ordering cannot vote in a count"* / *"ordering only, never a
grade."*

**It is not one of `--quality-delta`'s ten gating kinds.** The per-edit gate's kinds are `complexity`,
`verbosity`, `nesting`, `params`, `duplication`, `dead-code`, `api-surface`, `error-masking`,
`short-horizon-churn` and `new-clone-of-reused-helper` (`src/quality.h:4565` and the kind dispatch around
it). None of them is Halstead volume, token entropy or the Posnett score. The one readability-*adjacent*
kind is `verbosity`, and reading its implementation shows exactly what it measures and what it does not:
`verbosity` is **CODE line count only** (`src/quality.h`, `locBySym`, `codeLocByNode` — "Q-DIAL-3: blank and
comment-only lines are not debt"). It shares one input (`L`) with the Posnett formula and none of the other
two (`V`, `E`). So the per-edit gate that actually blocks a merge never sees the entropy or Halstead-volume
half of the readability lens at all — it sees a plain, un-weighted line count.

**The only place the Posnett rank feeds a joined judgment is `--ensemble`, and even there it is kept
ordinal, not additive.** `src/ensemble.h` folds `--readability`'s rank into its "structural" evidence family
alongside complexity/LOC/nesting/params, and its own header comment states why the five are one family and
not five independent votes: *"ccx, loc, nest, params and the Posnett score all track SIZE — Posnett's own fit
is literally linear in L. Counting them as five agreeing witnesses is the Maintainability-Index failure
(§3.10): re-weighting one signal and calling it five."* — and separately, on why the Posnett rank and churn
are handled differently from the other four: *"The other two signals (Posnett readability, churn) are
RANKINGS whose own authors publish no defensible absolute cut: --readability's header says in so many words
to read the ORDER, not the number. The only honest predicate on an ordinal signal is an ordinal cut, so each
fires for the WORST DECILE of its own ranking."* `--ensemble` records only a symbol's position in that
worst-decile prefix (`rrank=`), never `posnett=` itself — there is, by the same comment's own words a few
lines later, "no composite number anywhere in this verb, by contract."

**So: does the tool present readability as an absolute grade anywhere?** No surface we found does. The one
place a reader could plausibly *read* it that way — a raw `posnett=` value on an individual row of
`--readability`'s own output — carries the legend's own correction directly above it every time it is
printed ("read the ORDER, not the number, and never as a grade"), and the value visibly saturates to
`0.000` for a large share of real functions (see §3), which is itself a standing, unavoidable reminder that
the number is not meant to be read on its own. We consider the code's claim to already be the *honest* one:
ordering-only, disclosed as ordering-only, at every point of contact. The rest of this document is about
whether that ordering claim itself survives contact with a human judgment — which is a strictly harder bar
than "is the code's rhetoric honest," and one the code freely admits it has not cleared (Scalabrino/Trockman/
Fakhoury are cited as open problems, not as solved ones).

## 2. A validation of the ORDERING, not the score

Reproducibility (the same input always yields the same rank) is not construct validity (the rank means what
we say it means). The formula could be perfectly deterministic and still rank functions in an order no human
reader would recognize. Here is the validation we think would settle that, specified concretely enough to run:

**Unit of comparison: pairs, not scores.** Ask a rater "which of these two is more readable," never "rate
this snippet 1–5" — the literature's own ground-truth datasets are pairwise-derived or scale-based and Vitale
(2025, cited in the readability design note §7) found up to a third of classic scale labels
self-contradictory on reread. A forced pairwise choice is cheaper to collect, cheaper to get consistent, and
is exactly the shape `--readability`'s own claim needs checking against: it emits an order, so validate the
order.

**Where pairs come from (three tiers, cheapest first):**

1. **This repo's own git history** — a commit whose message says refactor/simplify/cleanup gives a free
   (before, after) pair of the same function, no synthetic construction needed. This is what §3's proxy (a)
   already mines, at zero marginal data-collection cost.
2. **`bench/external/arb` and `bench/external/swex`** — this repo already vendors multiple external-repo
   snapshots and commit histories for other evaluation harnesses (agentic-benchmark corpora, not readability
   ones). The same commit-message mining in §3's script generalizes to any of them by pointing `--root` at a
   different checkout — more languages, more authors, no ripwire-specific style bias. We did not run this for
   the current round (time-boxed to this repo, see §3) but the script takes a `--bin`/corpus-root pair for
   exactly this reason.
3. **Synthetic pairs from `--readability`'s own ranking** — take two functions already far apart in the
   lens's own order (one from the worst decile, one from the best) and ask a rater to confirm or reject the
   implied direction. Cheapest to collect, weakest signal (it can only confirm the lens agrees with itself at
   the extremes, which §3 proxy (b) already establishes for free without a human).

**How a human judgment would be collected.** Blinded, randomized left/right presentation (no file path, no
`posnett=`, no commit message); each pair rated independently by at least three raters, majority vote as the
pair's label, inter-rater agreement reported alongside the correlation (a low agreement number is itself a
finding, per Vitale). Raters should not be told which side the lens preferred — Piantadosi et al.'s "readable
state flip" framing (cited in the readability design note §6) is a reasonable model for how to phrase the
question without anchoring the rater on a metric.

**The statistic.** Percentage pairwise agreement between the lens's implied direction and the majority human
label, plus a rank correlation (Kendall's τ or Spearman's ρ) over any batch of pairs drawn from one shared
ranked list, since τ is exactly a transform of pairwise agreement and gives readers a standard number to
compare against the published literature's own correlations for competing metrics.

**What would count as success, and what would make us withdraw or demote the lens.** We propose three bands,
calibrated against the literature already cited in this repo (Scalabrino ASE'17 and Trockman MSR'18 found
*no* classic metric correlates strongly with measured understandability — so we are not calibrating against
"strong correlation is achievable," we are calibrating against "is this metric earning the narrow claim it
actually makes"):

- **τ (or equivalent pairwise agreement) comfortably above chance and stable across a second, disjoint
  sample** → keep exactly as-is: an ordering signal, disclosed as such, feeding `--ensemble`'s rank-only
  join and nothing stronger.
- **Weak but directionally consistent, or consistent on some function shapes and not others (e.g., holds for
  size-dominated differences, fails when two functions are close in size but differ in naming/structure)** →
  narrow the claim further and say so in the legend — e.g. disclose that the lens is known to track length
  more than it tracks anything len-independent, which §3's proxy (b) already shows structurally (see the
  "what this cannot catch" paragraph there).
- **No better than chance, or a sign flip on a held-out language/corpus** → withdraw the ranking claim from
  any joined surface (`--ensemble`'s `rrank=`) and keep `--readability` only as a standalone, clearly-labeled
  "how does this formula see the codebase" report — the same demotion path `naminglens.h` already used once
  (§5).

We have not run the human-rated arm. It needs raters we do not have in this pass; §6 names it as the thing we
would like the most external help with.

## 3. What we ran WITHOUT human labels

Two proxies need no rater at all. Both are implemented as re-runnable scripts against the real
`./build/ripwire --readability` binary — not a reimplementation of the formula — so what they measure is
the shipped lens, not a paper description of it.

### 3a. Refactor-commit direction (`bench/readability_refactor_pairs.py`)

For every commit in this repo's history whose subject reads as refactor/simplify/cleanup (case-insensitive,
`refactor|simplify|clean(\s|-)?up`) and whose total changed-line count is ≤400 (so a per-function delta stays
attributable to the named refactor rather than to an unrelated bulk edit riding along in the same commit),
the script extracts every touched `.h`/`.cpp` file at the commit and at its parent, scores each version with
the real lens in a single-file scratch directory, and keeps the functions present in both versions with a
**different** token shape (same shape ⇒ this diff did not touch that function's body ⇒ no evidence either
way). Comparison uses the pre-sigmoid `z` score recomputed at full precision from the CLI's own
integer `toks=`/`vocab=` and its `ent=`/`lines=` — not the CLI's own 3-decimal `posnett=` attribute, which
saturates to a repeated `"0.000"` for most real functions (see the tie count below) and would make most pairs
falsely indistinguishable. `z` is monotonic in `posnett` (same sigmoid), so ranking by `z` ranks identically
to ranking by `posnett` without the display truncation.

**Run** (`--max-commits 80 --max-changed-lines 400`, history pinned to the `v0.6.2` tag — never `git log
--all`, the numbers below):

| | |
|---|---|
| candidate refactor/simplify/cleanup commits | 80 (77 contributed ≥1 usable pair) |
| function pairs (changed shape, matched by name) | 412 |
| lens ranks AFTER more readable (`z` increased) | 154 (37.4% of the 412 directional pairs) |
| lens ranks AFTER less readable (`z` decreased) | 258 (62.6%) |
| exact tie | 0 |
| mean Δz (after − before, + = more readable) | **+3.79** |
| median Δz | **−0.56** |
| pairs with \|Δz\| > 20 (large swings) | 32 / 412 (7.8%) |

First recorded as 484 pairs / 146 right-direction / 30.2% from an unpinned `git log --all` walk, which does
not reproduce; see §3c for the instrument defect, the fix, and the full decomposition.

**Read this plainly, including that it is not flattering.** On a majority (63%) of the function pairs a human
called a refactor, the lens's own ranking moved the *wrong* direction — it scored the after-version as *less*
readable. The mean is positive only because a small number of large swings (7.8% of pairs, all from commits
that genuinely shrank a function by splitting work into named helpers) pull it there; the median, which a
skewed distribution like this one should be read against, is negative. This lines up with exactly the
literature the lens's own code already cites as a reason for caution — Fakhoury ICPC'19's finding that
classic readability models "miss real-world readability-improvement commits" is not a hypothetical risk here,
it is what this run measured on ripwire's own history.

**Two worked examples, to show what is and is not driving the number.** The eight largest positive swings on
the pinned population are all commits whose stated purpose was extraction — moving a block of logic out into
named helper functions, which mechanically shortens (or hollows out) the function the lens is scoring:
`buildScipOverlay` (227→124 lines), `ingest` (1138→1029), `writePinCensus` (88→38), `buildFieldNarrowTables`
(114→50), `computeSnapshot` (116→61), `buildScopedRecvDecls` (61→15), `hasNetExfilShape` (59→17) and
`buildExternalVetoTables` (147→86) — a 41%–75% line-count cut in all but one case. The exception is `ingest`
(`refactor(ingest): the doc post-pass becomes ingest_docpass.h`): only a 9.6% line cut, but the swing is
still large because a token-dense block moved out into the new header — the Halstead-volume term collapsed
even though the line count barely moved. That is the same volume-not-lines mechanism §3c's decomposition
finds behind 91%+ of the wrong-direction pairs too (see below), not a second, unrelated effect. The single
largest *negative* swing is the opposite shape of edit: commit `15af398e`
(`refactor(L1-fix): keep existing contracts; readings spell no element markup`) inlined a one-line forwarding
wrapper (`classify()`, 5 lines) into what had been a same-named sibling implementation, producing one 126-line
function where there had been a 5-line indirection plus a separate body. The commit message is about
preserving an API contract, not about readability, and a human reader might reasonably call the *pre*-commit
two-function shape less readable (an unexplained one-line forwarder) than the *post*-commit single function —
the opposite of what the lens's length term rewards. We are not correcting for this by hand; it is exactly
the kind of case a pairwise human study (§2) would need to arbitrate, and we would be misrepresenting the
proxy if we quietly excluded it.

Re-run: `bench/readability_refactor_pairs.py --max-commits 80 --out pairs.tsv` (defaults to this repo,
`build/ripwire`, and the `v0.6.2` ref — override with `--ref`, never `--all`; deterministic given a fixed
git history and a fixed binary).

### 3b. Self-consistency under meaning-preserving rewrites (`bench/readability_self_consistency.py`)

Two mechanical rewrites that should not change how readable a function is: renaming one local identifier to a
fresh name that collides with nothing else in the function, and swapping two adjacent, mutually-independent
simple statements (`lhs = rhs;`, including one-line typed declarations, in this repo's one-statement-per-line
house style). 80 functions were sampled at even percentile positions across `--readability`'s own
least-readable-first ranking of this repo's `src/` (4,373 functions measured), so the sample spans the whole
distribution rather than only the worst decile the verb shows by default. Each sampled function's own whole
file is re-scored unmutated as the baseline (same single-file measurement path the mutant takes, so there is
no cross-file ingest difference to explain away), then rescored after one mutation.

| mutation | attempted | exact tie (`vol=`, `ent=`, `posnett=` all unchanged) | diverged |
|---|---|---|---|
| rename (fresh, non-colliding identifier) | 75 / 80 | 75 | 0 |
| reorder (two adjacent independent statements) | 20 / 80 | 20 | 0 |

**State plainly what this does and does not show.** Halstead volume and Shannon entropy are functions of the
*multiset* of (token, frequency) pairs — not of token identity or statement order (`readability.h`'s own
determinism note: the entropy sum runs over a token-text-**sorted** vector specifically so iteration order
cannot reach the output). So exact invariance under a non-colliding rename or an independent-statement
reorder is what the formula predicts *mathematically*, not a discovery — a 100% tie rate here mostly certifies
that the shipped implementation has no stray non-determinism or order leak, which is a real and worth-having
guarantee, but it is an implementation-correctness result, not a readability-construct-validity result. The
informative failure mode this proxy could have caught — and did not — is any pair that does NOT tie exactly,
which would point at either a bug in this harness's mutation or a genuine order/identity sensitivity in the
lens worth filing as a defect.

**The same invariance is also a disclosed limitation, not only a safety net.** Because the formula is
mathematically blind to identifier length and to statement order, it is *structurally incapable* of
rewarding `numberOfActiveConnections` over `n`, or a well-ordered proof sketch over a scrambled one — both
of which most human readers would call a real readability difference. That is a construct-validity gap this
proxy makes visible without needing a single human label: whatever the lens is measuring, it provably is not
measuring those two things, by the formula's own definition.

**Coverage caveat, reported rather than hidden.** Only 20 of 80 sampled functions (25%) contained an eligible
adjacent, independent, simple-statement pair by our conservative heuristic (excludes calls, subscripts,
member targets, and any pair whose right-hand sides cross-reference the other's left-hand side). This is a
coverage limit of the *harness*, not a claim about the lens — most real functions in this codebase either
have fewer than two adjacent simple statements or have dependencies between them, and a looser heuristic
risks constructing a swap that is not actually independent.

Re-run: `bench/readability_self_consistency.py --samples 80 --seed 20260918 --out consistency.tsv`
(deterministic for a fixed seed, corpus and binary — the sampler's own RNG is seeded, and the rename target
is chosen by frequency-then-lexical order rather than randomly, so re-running with the same seed reproduces
the same mutations).

### 3c. A second, independent proxy: commits that DECLARE a readability improvement

§3a leaves two explanations standing, and they predict different things:

- **Lens defect** — the formula genuinely disagrees with readability. Predicts the inversion reappears on
  *any* readability ground truth, including commits whose author says in so many words that the change is
  for readability.
- **Proxy defect** — a "refactor" commit is not a readability improvement (refactors add guards, split
  responsibilities, keep contracts), which is also the published result this lens already cites (Fakhoury
  ICPC'19: classic models miss developer-declared readability improvements). Predicts that the §3a inversion
  is explained by a mechanical component of the formula responding to non-readability edits, and says nothing
  in advance about declared-readability commits.

The stop rule this section runs under: **if a second, independent proxy also comes out inverted, we withdraw
the ordering claim rather than re-fit the formula to rescue it.**

#### Protocol (fixed in this commit, before any number below was computed)

This protocol was committed to this document before the harness that computes it was run; the commit that
adds this subsection predates the commit that adds its results, and nothing here was edited afterwards.

**Corpus and binary.** Exactly §3a's: this repository's own git history, walked with the same pinned `v0.6.2`
ref over `src/` C/C++ sources (originally `git log --all` — see the instrument-fix note in Results below),
the same ≤400 total-changed-lines cap, the same single-file scratch scoring through the shipped
`--readability` verb, the same (basename, name) matching, the same "changed token shape" filter and the same
full-precision pre-sigmoid `z` comparison. The binary is a v0.6.2 build; `src/readability.h` is byte-identical
between that build's source and this document's base.

**Selection rule — proxy (c), primary arm.** A commit is selected when its **subject line**, after the lens's
own name is masked, matches the case-insensitive regex

```
readab|legib|clarity|clarif|clearer|easier to (read|follow|understand)|self-documenting
```

The mask replaces these substrings with a blank before matching, so a commit *about the lens* is not read as
a commit *declaring readability*: `--readability`, `readability.h`, `readability_`, and a conventional-commit
scope `(readability)` / `(readability,` / `readability)`. A subject that **also** matches §3a's refactor regex
(`refactor|simplify|clean(\s|-)?up`) is excluded, so the primary arm's commit set is disjoint from §3a's by
construction. No `--max-commits` cap: every qualifying commit in the history is used.

**Secondary arm (descriptive only, no verdict).** The same rule applied to the full message (subject and
body), still masked and still disjoint from §3a. Bodies in this repository are long and mention readability in
passing, so this arm is noisier; it is reported because it was named here, and it carries no decision.

**n target.** **100 directional function pairs** in the primary arm (at p = 0.5, 100 pairs gives a 95%
interval of about ±10 points, which is the width of the bands below). If the primary arm reaches fewer than
100, the result is reported as "n not reached", with the n that was reached and its rate shown for the record,
and **no verdict is drawn**. The regex is not loosened after looking.

**Decision bands** (on the primary arm's fraction of directional pairs the lens ranks AFTER more readable):

- **≥ 60%** → the lens's ordering holds on this proxy; §3a's inversion is read as a proxy defect.
- **≤ 40%** → inverted on a second, independent proxy; the stop rule triggers and this document recommends
  withdrawing the ordering claim.
- **between** → inconclusive, reported as such; neither explanation is favoured by proxy (c).

Because pairs cluster inside commits, the per-commit rate (a commit counts as "right" when most of its
directional pairs moved up) is also reported. It is secondary and does not move the band.

**§3a decomposition (deterministic, fixed here too).** For each §3a pair, Δz splits exactly into three terms:
`ΔV·(−0.033)` (Halstead volume), `ΔE·(−1.5)` (entropy), `ΔL·(+0.40)` (lines). For every wrong-direction pair
(Δz < 0), the **driver** is the term with the most negative contribution. Reported: the driver split, the
mean contribution of each term over the wrong-direction pairs, and how many wrong-direction pairs got *longer*
(ΔL > 0). The same split over §3a's right-direction pairs is reported beside it for contrast. The pairs are
regenerated by re-running §3a's exact command (`--max-commits 80 --max-changed-lines 400`), now pinned to the
`v0.6.2` ref by default — walking `git log --all` instead would see every ref in this clone's shared `.git`
(~291 worktree branches at the time this defect was found), so a later ref set could silently shift which 80
commits are "newest" and move the published fraction with it. That is exactly what happened to §3a's first
recorded number; see the instrument-fix note below.

No LLM judgment is used anywhere in this section — not for labels, not for spot-checks. The reference list
cites CoReEval for why: an LLM readability judge fixates on surface features, which is the very construct
question under test.

#### Instrument fix (this revision) — read this before the numbers below

The first recorded run of this section (484 pairs / 146 right-direction / 30.2% in §3a; the proxy (c) and
decomposition numbers this subsection used to report) walked `git log --all` in both
`bench/readability_refactor_pairs.py` and `bench/readability_declared_pairs.py`. This clone's `.git` is
shared across every worktree in the orchestration tree that produced this document — at the time the defect
was found, that was on the order of 291 branches — so `--all` pulled in whatever those branches happened to
contain that day. A rerun of the *identical, unmodified* script gave 413 pairs (38.3%) with the commit window
pinned to the original run's date and 409 pairs (38.4%) without even that pin; neither matched the published
484/146/30.2%, and neither run had touched `src/readability.h` or the lens in any way. A number that moves
when an unrelated lane is pushed is not measuring the lens — it is measuring which branches exist in the
shared `.git` right now. That is an instrument defect, not a finding.

Both scripts now default to walking exactly one immutable ref — the `v0.6.2` tag, which is also the ref the
scoring binary (`build/ripwire`, `built_from=15a20855c`) was built from — instead of `--all`. `--ref`
overrides it for a deliberately different population; `--until` (added when the defect was first worked
around) still narrows further within whatever ref is walked. §3a's headline table above is this pinned run.
Every number for the rest of this section is the same pinned run too, so — unlike the first version of this
document — the "published" and "regenerated" numbers here are one run, not two.

#### Results (recomputed on the `v0.6.2`-pinned instrument)

**Proxy (c), primary arm: n not reached — no verdict.** The pre-registered subject-line rule selected **3
commits yielding 3 directional pairs** against a target of 100 (2 ranked more readable after, 1 less; 2/1 per
commit). Under the protocol that is reported as "n not reached" and draws no band. It is also worse than
small: **none of the three is a readability declaration.** Two match `readab` inside *unreadable* (commits
about files the tool could not read), and one matches the lens's own name in a form the mask did not
anticipate (`readability-wave1`, a lane name). The mask gap is a defect of the pre-registered rule, disclosed
here and not patched after the fact. The honest summary: **this repository's `src/` history, at `v0.6.2`,
holds no commit whose subject declares a readability improvement**, so proxy (c) cannot be run on this corpus
at all.

**Secondary arm: descriptive only, and not a second proxy.** Subject and body together selected 46 commits
and 134 directional pairs, of which the lens ranked AFTER more readable on 38 (28.4%; 13/24/2 per commit
right/wrong/split). This arm carries no verdict by the protocol, and reading its commit list shows why it
should not: its subjects are overwhelmingly error-handling fixes (a file that "could not be read", a
directory walk that was "unreadable"), matched through words like *unreadable* in the body. It is a set of
bug-fix commits, not a readability ground truth, and a 28% figure on it says nothing about the lens-defect
explanation.

**§3a decomposition.** Re-running §3a's command against the pinned `v0.6.2` ref reproduces §3a's own headline
exactly: 412 pairs (154 up, 258 down, 37.4% right-direction). The table below is that same population.

| over the 412 pinned pairs | wrong-direction (258) | right-direction (154) |
|---|---|---|
| driver = Halstead volume term `ΔV·(−0.033)` | **235 (91.1%)** | 148 (96.1%) |
| driver = lines term `ΔL·(+0.40)` | 23 (8.9%) | 6 (3.9%) |
| driver = entropy term `ΔE·(−1.5)` | 0 | 0 |
| mean contribution: volume / entropy / lines | −3.07 / −0.06 / +0.18 | +19.79 / +0.20 / −4.91 |
| function gained tokens | 239 | 3 |
| function got longer in lines / shorter / same | 47 / 51 / 160 | 8 / 127 / 19 |

Three things follow, all mechanical:

1. **The inversion is a token-count signal, not a length signal.** In the Posnett fit the lines coefficient
   is *positive* (+0.40): holding volume fixed, a longer function scores *more* readable. So line count cannot
   be what pushed a pair the wrong way unless the function got shorter, and on average it pushed the other
   way (+0.18). The Halstead-volume term drove 91% of the wrong-direction pairs; entropy drove none.
2. **Direction is almost entirely the sign of the token-count change.** On 388 of the 404 pairs whose token
   count actually changed (96.0%), the lens's direction is predicted by whether the function lost tokens
   (ranked more readable) or gained them (ranked less readable); 8 of the 412 pairs kept the same token count.
3. **The typical wrong-direction pair is a small addition.** Median over the 258: +5 tokens, 0 lines, Δz
   −1.26 — a guard, a check, or an extra argument inside an unchanged line span, in a commit whose subject
   said "refactor", "simplify" or "clean up".

**Which explanation the data favours.** The lens-defect explanation is **untested**, not refuted: its
distinguishing prediction needs a declared-readability ground truth, and this corpus does not contain one.
What the data does settle is the mechanism behind §3a's number, and that mechanism is the shape the
proxy-defect explanation predicts: the lens did exactly what its formula says — it ranked a function that
grew by a few tokens as less readable — on commits that mostly grew functions by a few tokens. Whether those
small additions made the code more readable is precisely what a commit subject containing "refactor" does
not tell us. §3a is therefore better read as *"on this history, `--readability`'s direction is the sign of
the token-count change"* than as *"the lens is wrong 63% of the time"* — and the first statement is a
narrower, checkable fact about the lens that does not depend on the label at all.

**The stop rule did not trigger.** It needs a second independent proxy to come out inverted, and proxy (c)
produced no verdict. The shipped `--readability` flag and its help text are unchanged by this section. One
narrowing is supported by the decomposition regardless of how the construct question resolves, and falls in
§2's middle band ("disclose that the lens is known to track length more than it tracks anything
len-independent"), refined by what was measured — it tracks *token count*, not lines. As a **proposal for
owner sign-off, not a change made here**, the legend could add: *"On ripwire's own history the ORDER between
two versions of a function followed the sign of its token-count change in 96% of pairs; read a move as 'more
or fewer tokens', not as more or less readable."*

**Next step.** Proxy (c) needs a corpus that actually contains declared-readability commits — Fakhoury et
al.'s 548-commit set is the natural one — scored with this same script by pointing it at that checkout, under
this same protocol (bands, n target, and the stop rule unchanged; the mask gap above fixed *before* that run
and disclosed as a change).

Re-run: `bench/readability_declared_pairs.py --bin build/ripwire` (proxy (c), both arms, `v0.6.2`-pinned by
default) and `bench/readability_declared_pairs.py --bin build/ripwire --decompose` (the §3a decomposition, on
the same pinned population as §3a itself). `--ref` points either command at a different immutable ref;
`--until` still narrows within whichever ref is walked.

## 4. Does the ordering predict anything worth acting on? A later-fix-rate validation

§2 and §3 both validate the ORDER: does it move the direction a refactor implies, is it stable under a
meaning-preserving rewrite. Neither asks the question an agent actually relies on when it reaches for
`--readability` to pick a target: **does a low score predict that a function will need fixing later?** That
is the implicit claim behind "use the worst-ranked functions as a worklist," and it has never been tested.
This section tests it, with no human label and no LLM judge, against a complexity control this repo's own
`--quality-delta` "complexity" gate kind already trusts, on the same population, with and without controlling
for function size.

### Protocol (fixed in this commit, before the harness that computes it was run)

This subsection was committed before `bench/readability_fixrate_validity.py` was run for the record — the
same discipline §3c used for proxy (c), and for the same reason: a band decided after seeing the number is
not a band.

**Population.** Every `fn`/`method` in `src/**/*.{h,hpp,cpp,cc}` at a single pinned CUTOFF commit on
`v0.6.2`'s history — never `--all` (§3c's instrument-fix note explains why a shared `.git` makes that
non-reproducible). The cutoff is chosen to leave a multi-week, thousand-plus-commit follow-up window to the
pinned UNTIL ref (`v0.6.2` itself), long enough that a fix-shaped commit has real room to happen, short
enough that the population is still recognizably today's codebase. Functions are matched between a real
`--readability` crawl and a real `--metrics` crawl of the identical extracted tree (`git archive`, not
per-file scratch, so `--metrics`'s in/out/ccx see real cross-file structure) by (path, name), requiring
`loc`(metrics) `==` `lines`(readability); an ambiguous match (same path+name, disagreeing loc — almost always
an overload) is dropped and counted, never guessed at.

**Exposure**, per function, read at the cutoff: `z`, the exact pre-sigmoid Posnett score recomputed from
integer `toks=`/`vocab=` exactly as `bench/readability_refactor_pairs.py` does (lower z = less readable —
`--readability`'s own least-readable-first sort order), and `ccx`, cognitive complexity from `--metrics` —
the same metric `src/quality.h`'s `"complexity"` gate kind reads, used here as the already-trusted baseline
on the identical population, not as a bar the lens must clear.

**Outcome**, defined before looking, over the window `(CUTOFF, UNTIL]`:

- **fix-shaped commit**: subject line (not body — §3c already found body-matching noisy) matches, case
  insensitively: `\bfix(e[sd])?\b|\bbug(s|fix(e[sd])?)?\b|\bcrash(e[sd])?\b|\bregression(s)?\b`.
- a function is **FIXED** if any fix-shaped commit in the window has a diff hunk — in that commit's OWN
  parent's line numbers, not the cutoff's — overlapping the function's span AS MEASURED AT THAT PARENT
  revision (re-scored per commit specifically so line drift from earlier window commits cannot misattribute
  a hunk to the wrong function), matched back to the population by (basename, function name). A pure-insertion
  hunk (old count 0) is treated as touching whichever function(s) contain old-line `start` or `start+1`.
- a function is **MODIFIED** (the broader arm) under the identical rule over every commit that touches a src
  file in the window, fix-shaped or not — a superset computed in the same pass, since every fix-shaped commit
  is also a modifying commit.

**Statistic.** Fix-rate (and modified-rate) in the least-readable quartile (bottom 25% by z) vs the rest,
Wilson interval per proportion, risk ratio with a Katz log-CI — reported beside the identical statistic for
the highest-ccx quartile vs the rest, on the same population, as the trusted-signal comparison point.
Repeated within three size (lines-at-cutoff) terciles, with the least-readable/highest-ccx quartile
recomputed WITHIN each tercile, to test whether either signal survives controlling for size.

**Decision bands**, restated from this document's own §2 framing, applied to the raw (unstratified) arm:
the least-readable quartile's fix-rate CI excludes a risk ratio of 1, and the effect does not vanish once
stratified by size → keep the ordering claim as an actionable, if weak-to-moderate, signal; effect present
raw but gone in every size tercile → the size confound explains it, narrow the claim accordingly; CI includes
1 raw → withdraw the "predicts later fixes" claim outright. The complexity arm is reported for comparison,
never as a bar the lens must clear — Scalabrino/Trockman's own consensus (§2) is that no classic metric
correlates strongly with anything, so "about as good as complexity" is itself the "keep as a weak signal"
outcome, not a pass/fail line of its own.

**A pre-registered caveat about the size control itself.** §3c already found that `z`'s direction on this
repository's own history is almost entirely the sign of the TOKEN-count change (96.0% of pairs), not the
line-count change — the Posnett lines coefficient is positive, so more lines alone would push z the other
way. Stratifying by LINES (the natural, legible size band) therefore does not fully neutralize the mechanism
§3c already implicated: two functions in the same line-count tercile can still differ sharply in token
volume, and z tracks that. A result that survives a lines-based stratification is not automatically a result
that survives a tokens-based one — that is disclosed here, before either number exists, as a limitation of
this design, not folded quietly into the verdict after the fact.

Re-run: `bench/readability_fixrate_validity.py --bin build/ripwire` (population + both outcome arms, raw and
size-stratified, `v0.6.2`-pinned CUTOFF/UNTIL by default; `--out` writes the per-function TSV this section's
numbers were computed from).

### Results

**Population and window.** 2,868 of 3,004 functions crawled at the cutoff (`4f5c310c`, 2026-09-03) matched
between the `--readability` and `--metrics` passes (95.5%; 67 ambiguous matches dropped). The follow-up
window to `v0.6.2` (2026-09-21) held 1,138 commits touching a `src/` file, 556 of them fix-shaped by the
pre-registered regex (48.9%).

**Raw (unstratified).**

| outcome | arm | worst-quartile rate | rest rate | risk ratio (95% CI) |
|---|---|---|---|---|
| FIXED | readability (least-readable quartile, n=717) | 386/717 = 0.538 [0.502, 0.575] | 403/2151 = 0.187 [0.171, 0.204] | **2.87 [2.57, 3.21]** |
| FIXED | complexity (highest-ccx quartile, n=717) | 339/717 = 0.473 [0.437, 0.509] | 450/2151 = 0.209 [0.193, 0.227] | **2.26 [2.02, 2.53]** |
| MODIFIED | readability | 495/717 = 0.690 [0.656, 0.723] | 659/2151 = 0.306 [0.287, 0.326] | **2.25 [2.08, 2.44]** |
| MODIFIED | complexity | 452/717 = 0.630 [0.594, 0.665] | 702/2151 = 0.326 [0.307, 0.346] | **1.93 [1.78, 2.10]** |

Both signals separate from 1 by a wide margin on this population, on both outcome definitions — and, raw, the
readability quartile's risk ratio is *larger* than the complexity quartile's on every row, not smaller.

**Size-stratified** (terciles by lines-at-cutoff; n=956 each; quartile recomputed within each tercile):

| tercile (lines) | outcome | readability RR (95% CI) | complexity RR (95% CI) |
|---|---|---|---|
| T1 (1–10) | FIXED | 3.30 [2.32, 4.70] | 0.80 [0.51, 1.24] |
| T2 (10–26) | FIXED | 1.27 [0.995, 1.63] | **0.55 [0.40, 0.77]** |
| T3 (27–1494) | FIXED | 1.90 [1.69, 2.14] | 1.39 [1.22, 1.58] |
| T1 (1–10) | MODIFIED | 2.39 [1.88, 3.05] | 1.08 [0.82, 1.44] |
| T2 (10–26) | MODIFIED | 1.23 [1.03, 1.47] | **0.79 [0.64, 0.98]** |
| T3 (27–1494) | MODIFIED | 1.56 [1.44, 1.69] | 1.24 [1.13, 1.37] |

**Read this plainly.** The pre-registered "most likely outcome" — the signal vanishing once size is held
constant — did **not** happen. The readability risk ratio stays above 1, with a CI excluding 1, in five of
six stratified rows; it only touches 1 in the FIXED/T2 row (lower bound 0.995), and even there the MODIFIED/T2
row for the same tercile clears 1 (1.03). It attenuates from the T1 (smallest-function) band — where it is
strongest, 3.30 and 2.39 — through T2, then rises again in T3. Complexity's within-band behavior is the more
surprising result here: it is flat-to-inverted in T1 and *significantly below 1* in T2 (0.55 and 0.79, both
CIs excluding 1) — meaning, within these two size bands, the highest-cognitive-complexity quartile was
fixed/modified *less* often than the rest, the opposite of the trusted baseline's raw-population direction.
Complexity only behaves as expected (RR > 1) in T3, the largest-function band.

**What this does and does not show.** On the raw population, `--readability`'s ordering separates a fixed
population by later-fix rate at least as well as the complexity control does, and the effect survives a
lines-based size stratification better than complexity's own effect does. That is a real, actionable-looking
signal on this corpus, under this outcome definition — the decision band above calls this a "keep," not a
"withdraw." But the pre-registered caveat means this is not the full size-confound test: `z` is dominated by
token volume, not lines (§3c), so a function can sit in the smallest LINE tercile while carrying a large
TOKEN volume relative to its tercile-mates, and the lines-based stratification cannot separate "z predicts
fixes independent of size" from "z still partly tracks a size axis lines does not capture." A token-count
stratification (bucketing by `toks=` instead of `lines=`) is the natural next test and was not run in this
round. Separately: complexity's inversion in T2 is itself worth a second look before this repository leans on
"highest complexity" as a worklist filter for medium-sized functions — that result was not anticipated by
this protocol and is reported exactly as measured, not smoothed over because it complicates the expected
story.

### Correction: the line-based stratification did not hold the confound constant

The paragraph above named the gap and deferred the fix; this section runs it. The lines-based stratification
just reported does not hold the actual confound constant: §3c already established that `z`'s direction
tracks the SIGN of the token-count change on 96.0% of this repository's own refactor pairs, not the
line-count change — the median wrong-direction pair there was +5 tokens, 0 lines. A function can gain a
meaningful share of a size band's token volume with no line-count change at all, so two functions in the
same LINE tercile can differ sharply in the unit `z` actually consumes. "Keep the ordering claim" was
therefore not yet earned by the line-stratified result alone. This re-runs the identical stratified analysis
by `toks=` — the Halstead N (operator+operand count) `--readability` itself emits, the exact integer the
lens's own volume term is computed from, not a re-derived proxy — on the same population, same outcome
definitions, same CIs, using the updated `bench/readability_fixrate_validity.py` (now captures `toks=` per
function and stratifies by either measure).

**Token-count stratification** (terciles by `toks`-at-cutoff; n=956 each; quartile recomputed within each
tercile), reported beside the line-stratified table rather than replacing it:

| tercile (toks) | outcome | readability RR (95% CI) | complexity RR (95% CI) |
|---|---|---|---|
| T1 (10–72) | FIXED | 2.28 [1.56, 3.33] | 1.01 [0.65, 1.57] |
| T2 (73–191) | FIXED | 1.06 [0.82, 1.36] | **0.62 [0.46, 0.84]** |
| T3 (191–8023) | FIXED | 1.89 [1.68, 2.13] | 1.38 [1.21, 1.58] |
| T1 (10–72) | MODIFIED | 1.74 [1.33, 2.28] | 1.02 [0.75, 1.39] |
| T2 (73–191) | MODIFIED | 1.05 [0.88, 1.26] | 0.85 [0.70, 1.04] |
| T3 (191–8023) | MODIFIED | 1.59 [1.46, 1.72] | 1.27 [1.15, 1.39] |

**Do the two stratifications agree?** No, and the disagreement is itself the finding. Line-stratified,
readability's RR excluded 1 in five of six rows (only FIXED/T2 touched 1, at a lower bound of 0.995).
Token-stratified — the measure the lens actually consumes — readability's RR excludes 1 in only **four** of
six rows: it holds in T1 and T3 on both outcomes, but **both** T2 rows now include 1 (FIXED 1.06 [0.82,
1.36]; MODIFIED 1.05 [0.88, 1.26]) — indistinguishable from no effect in the middle third of the token
distribution, where the line-based version had reported a real (if borderline) signal. The line-based
analysis was, exactly as suspected, partly reading a token-volume effect that a line-count band does not
hold constant.

**Restated verdict against the pre-registered bands, using the token-stratified result as decisive.** The raw
(unstratified) separation stands unchanged (RR 2.87 [2.57, 3.21] fixed, 2.25 [2.08, 2.44] modified — both
exceed the complexity control's 2.26 / 1.93 on the same population) and by itself would satisfy the "keep"
band. But the token-stratified arm shows that separation is not uniform across the size range the lens
itself measures: it is real and CI-excludes-1 at both ends (small-token and large-token thirds) and
statistically silent in the middle third. That is neither this document's "keep exactly as-is" band (which
requires the effect not to vanish under stratification, full stop) nor its "withdraw" band (which requires
it to vanish in *every* tercile — it does not: T1 and T3 both hold). It matches the **middle band this
document's own §2 already defined for exactly this shape of result**: "consistent on some function shapes
and not others… disclose that the lens is known to track [size] more than it tracks anything
[size]-independent, refined by what was measured." The verdict is therefore: **keep the ordering claim, but
narrowed** — `--readability`'s later-fix signal on this corpus is not a uniform property of the ranking, it
is concentrated at the size extremes (very small and very large functions, measured in tokens) and
disappears for functions of middling token volume, where the raw quartile RR reported earlier is optimistic.
An agent reading "least readable" as a worklist filter should expect the signal to be weakest for
run-of-the-mill mid-sized functions — which is most of the codebase (T2 by construction) — and strongest at
the tails. This is a materially weaker claim than "keep exactly as-is," and this document says so plainly
rather than defaulting to the friendlier reading.

**T2 diagnosis: is the complexity inversion explained by a file or symbol-kind concentration?** Complexity's
below-1 risk ratio in the middle tercile is the more surprising result in both stratifications (line-based:
0.55 fixed / 0.79 modified; token-based: 0.62 fixed / 0.85 modified, the modified arm no longer excluding 1
under the token version). Checked cheaply, on both the line-T2 and token-T2 highest-ccx quartiles (n=239
each): no file supplies more than 5% of either group (top file `src/docdrift.h` at 12–15 of 239), and no
name-pattern keyword (`test`, `match`, `find`, `build`, `table`, `gen`, `classify`, `parse`, `check`, …)
covers more than 3.3% — nothing resembling generated code, a table literal, or a test-fixture cluster
dominates either quartile. The sampled names instead look like a broad mix of short, branch-dense helpers
(classifiers, matchers, small validators: `walkAggregateBody`, `classifySkipHealth`,
`sliceBuildAnchorOccs`) spread across ~40 different files with no concentration. **This is reported as
unexplained.** A plausible but unverified guess — that dense, short decision functions get written once,
exhaustively branch-tested, and rarely revisited — is not checked here and is not asserted as a finding; per
this document's own rule, an anomaly without a cheap explanation is left as measured, not smoothed into a
story.

**External validity.** Every number in this section, both stratifications and the raw arm, comes from one
repository's own history: `ripwire`'s own `src/` under this project's ~662 CI gates, quality-delta review and
adversarial CI, much of it AI-authored under those gates. A later-fix rate measured here is a claim about
*this corpus under this development process*, not a general claim about code, or even about AI-authored code
generally — a codebase without this repository's gate density, review discipline, or authorship mix could see
a different relationship (or none) between `z` and later-fix rate. Nothing in this section should be read as
"readability predicts fixes" as a general software-engineering claim; it is "readability predicted fixes on
this codebase, in this window, measured this way" — exactly the same scope limit §3's proxies already carry.

Re-run (updated to also emit the token-stratified table and the per-function `toks=` column in `--out`):
`bench/readability_fixrate_validity.py --bin build/ripwire`.

### Second correction (POST-HOC, not pre-registered): the tercile itself does not hold size constant

**This subsection was prompted by looking at the token-stratified table above**, not written before it —
labelled as such, per this document's own rule about what counts as pre-registration. The tercile result
has a simpler reading than "keep, narrowed": T1 (10–72 tokens) spans a 7.2× internal range, T2 (73–191) spans
2.6×, T3 (191–8023) spans 42×. The two terciles that show a readability signal are the two with the widest
internal spread; the one that is silent is by far the narrowest. A tercile — even a token tercile — does not
hold size constant, so "the effect survives at both extremes" is exactly what a *residual* size effect
predicts too, not only what an independent readability effect would predict. The two hypotheses make
different, testable predictions on narrower bands: a genuine readability effect should not shrink as the
band narrows; a residual-size effect should shrink toward RR=1, at a rate that tracks how much internal
range is left in the band.

**Deciles by `toks`-at-cutoff** (same population, same outcome definitions, same CIs; quartile recomputed
within each decile; `bench/readability_fixrate_validity.py --load-tsv pop_outcomes.tsv` re-derives this table
from the already-computed per-function data in under a second — no re-crawl needed):

| decile | toks range | internal range | n | FIXED RR (95% CI) | MODIFIED RR (95% CI) |
|---|---|---|---|---|---|
| D01 | 10–29 | 2.90× | 287 | 1.12 [0.31, 4.11] | 0.66 [0.23, 1.90] |
| D02 | 29–47 | 1.62× | 287 | 1.49 [0.70, 3.18] | 1.27 [0.77, 2.09] |
| D03 | 47–66 | 1.40× | 286 | 1.86 [1.03, 3.34] | 1.15 [0.73, 1.82] |
| D04 | 66–89 | 1.35× | 287 | 1.00 [0.58, 1.71] | 1.00 [0.67, 1.47] |
| D05 | 89–118 | 1.33× | 287 | 1.36 [0.88, 2.12] | 1.19 [0.84, 1.69] |
| D06 | 118–157 | 1.33× | 287 | 0.81 [0.51, 1.28] | 0.78 [0.55, 1.09] |
| D07 | 157–211 | 1.34× | 287 | 1.38 [0.92, 2.06] | 1.16 [0.88, 1.53] |
| D08 | 212–300 | 1.42× | 286 | 0.92 [0.63, 1.33] | 0.96 [0.73, 1.26] |
| D09 | 301–491 | 1.63× | 287 | **1.72 [1.37, 2.16]** | **1.36 [1.16, 1.60]** |
| D10 | 492–8023 | **16.31×** | 287 | **1.47 [1.29, 1.68]** | **1.25 [1.15, 1.36]** |

**Does RR track the internal range?** Yes, as the dominant pattern. Eight of the ten deciles (D01–D08, each a
genuinely narrow 1.3×–2.9× band) show a CI that includes 1 on both outcomes, with point estimates scattered
on both sides of 1 (0.81 to 1.86) — the shape of noise around no effect, not a consistent direction. The only
two deciles whose CI excludes 1 on both outcomes are D09 and D10. D10 is not a narrow band at all: at 16.31×
internal range it is wider than every tercile ever examined in this document, so a significant RR there is
exactly what "the tercile does not hold size constant" predicts, one level down. D09 (1.63×) is narrower and
its significance does not fit the range story as cleanly — at n=287 per decile with ten bands tested on two
outcomes (20 tests), roughly one false positive at α=0.05 is expected by chance alone even under a true null,
so D09 is reported without a confident causal reading in either direction, not folded into the "it's just
size" story to make the pattern look cleaner than it is.

**A second, independent check: nearest-token-neighbour matching.** For each of the 717 least-readable-quartile
functions, its closest-toks match from the remaining 2,151 was found (§4's protocol, `nearest_token_match`).
**This check came back unusable, and is reported as such rather than as evidence either way.** Only 46
distinct functions serve as matches for all 717 quartile members: one function (`parseDeclarator`, 327 toks,
itself FIXED) supplies 403 of the 717 matches (56.2%); a second (`printUsage`, 1,417 toks, also FIXED)
supplies another 126 (17.6%) — together 73.8% of the "matched control" group is two always-fixed functions
repeated hundreds of times, and the mean token gap between a quartile function and its nearest match is +136
tokens (median 37, max 6,606) — not a close match at all for most of the quartile. The raw number this
produces (matched-control fixed-rate 0.868 vs the quartile's own 0.538, RR 0.62) is **not reported as a
finding**: it is an artifact of how sparse the "rest" population is near the token counts the least-readable
quartile actually occupies, not a size-controlled comparison. That sparsity is itself informative in a
different way — it confirms the quartile sits in a part of the token distribution the "rest" of the
population barely reaches, which is what "the quartile is largely a size cut" predicts — but the RR number
itself is discarded, not used.

**Restated verdict, using the finest stratification with usable n as decisive.** The pre-registered bands
(§4's Protocol) ask whether the effect vanishes once stratified by size. On deciles narrow enough to
plausibly hold `toks` roughly constant (D01–D08), it does: eight independent CIs on each outcome, none
excluding 1, point estimates with no consistent direction. The two bands that still show a significant
effect are exactly the ones that still carry a wide internal size range (D10 unambiguously; D09 arguably, and
flagged as not cleanly resolved). That is not "keep, narrowed" — this document's second-tier band required
the effect to hold "for size-dominated differences" specifically and to be understood as tracking length; it
is closer to, and is called, this document's **withdraw** band: **the raw and tercile-level separation this
section reported earlier is better explained as a residual size effect, measured in the lens's own units,
than as an independent later-fix signal.** The "keep, narrowed" verdict in the prior revision of this section
is superseded by this one. `--readability`'s ordering does not appear to predict later fixes beyond what its
own dominant token-count component already predicts on its own — which is the same mechanism §3c already
found driving the lens's direction on refactor pairs. Per this document's own precedent (§5, `naminglens.h`),
the correct response to a validation that comes back this way is to say so plainly rather than re-fit the
analysis until it reads more favourably, which is what this subsection does: it withdraws its own prior
verdict in the same document that made it, three commits later, rather than quietly.

**What would change this again.** A genuine readability-independent signal, if one exists, would need to
show up as a CI excluding 1 on a majority of narrow, size-matched bands — not on the single widest band, and
not on a matching check that turned out to be degenerate. A larger population (a bigger corpus, or a longer
follow-up window) would shrink the decile CIs enough to tell D09 apart from noise, and a working size-matched
control (this repo's own "rest" population is too sparse near the quartile's own token range for 1-NN
matching; a synthetic or cross-repo control pool would not have that gap) would settle the discarded check
above properly instead of leaving it unresolved.

Re-run: `bench/readability_fixrate_validity.py --bin build/ripwire` (full run, includes deciles and the
matched-control check) or, on an already-written `--out` TSV, `bench/readability_fixrate_validity.py
--load-tsv pop_outcomes.tsv` (re-stratifies in under a second, no re-crawl).

## 5. Precedent: we have already withdrawn a lens that failed exactly this kind of check

This is not the first deterministic proxy ripwire has shipped, measured, and had to reckon with. §9.0 of
`docs/LINEAGE.md`, and the top of `src/naminglens.h` itself, record `naming-body-mismatch` — a rule that
flagged a name whose tokens shared zero vocabulary with its own body. Measured on this repository's own
`src/` at the commit that shipped it, the rule produced 159 of the lens's 217 naming findings (73% of the
whole signal), and the flagged set was **dominated by the best-named functions in the tree**
(`didYouMean`, `transitiveCallers`, `symbolAdjacency`) — because a good abstraction name states *intent*
while its body states *mechanism*, so near-zero overlap is the signature of a successful abstraction at least
as often as of a lying name. The axis was non-monotonic with quality: no threshold on it has a defensible
direction. It was **withdrawn before it shipped**, and `naminglens.h` carries a do-not-re-add note plus the
measured numbers at the top of the file rather than a silent deletion.

We take that as the template for what "failing this validation" would require of us, not just for naming: if
§2's human-rated pairwise study comes back at or below chance, or flips sign across a second corpus, the
correct response is the same one `naming-body-mismatch` got — record the numbers and the reasoning where the
next reader will actually see them (this document and `--readability`'s own header comment, the way
`naminglens.h`'s header comment carries its own withdrawal), demote or remove the claim from any joined
surface (`--ensemble`'s `rrank=` first), and do **not** quietly re-add a close cousin of it later without
citing why this round's finding no longer applies. §3's numbers are not at that bar yet — proxy (a)'s
63%-wrong-direction result on refactor commits is concerning enough that we think the human-rated study in
§2 is now the right next step, not an optional nice-to-have.

## 6. What we would like help with

We are not readability researchers; we are reporting what a deterministic, disclosed, ordering-only lens
measures against a construct it was never claimed to solve, and we would like informed pushback on the
following, specifically:

1. **Is §2's proposed pairwise + rank-correlation protocol the right design**, or is there a better-controlled
   study shape for validating an *ordering* claim (as opposed to the score-based designs most classic
   readability datasets — Buse & Weimer, Scalabrino, Dorn — were built for)? We deliberately avoided asking
   for a 1–5 scale per snippet, on Vitale's (2025) finding that a meaningful fraction of such labels are
   self-contradictory on reread; is a forced pairwise choice actually more reliable, or does it just move the
   inconsistency somewhere this document has not thought to look?
2. **What is a defensible pass/fail bar for an ordering-only metric**, given that the field's own consensus
   (Scalabrino ASE'17, Trockman MSR'18) is that no classic metric correlates *strongly* with measured
   understandability? §2 proposes three bands calibrated against "does the lens earn the narrow claim it
   makes," not against "strong correlation is achievable" — is that the right frame, or does it let a weak
   metric off too easily?
3. **Proxy (a)'s 63%-wrong-direction number** (§3a) is the most actionable finding in this document, and we
   would like a sanity check on the method before we act on it: is commit-message mining (refactor/simplify/
   cleanup) too noisy a readability label on its own — conflating "the author changed something for reasons
   unrelated to readability" with "the author made it more readable" — and if so, what filter (a stricter
   subject regex, a manual pass over a sample, restricting to commits that touch exactly one function) would
   make the label trustworthy enough to report a headline number from?
4. **Is Halstead volume, entropy and length the right feature set to be checking at all** in 2026, or is this
   entire investigation validating a formula the field has already moved past? The readability design note
   §5 surveys later models (Buse & Weimer 2010, Scalabrino 2018) that add lexical/visual/textual
   features on top of the same structural core — if there is a more recent, still-deterministic (no model
   call) formula with better-established construct validity, we would rather adopt it than keep defending
   Posnett 2011 out of inertia.

## Reference list

- Posnett, D., Hindle, A. & Devanbu, P. *A Simpler Model of Software Readability.* MSR 2011.
  [doi:10.1145/1985441.1985454](https://doi.org/10.1145/1985441.1985454)
- Halstead, M. H. *Elements of Software Science.* Elsevier, 1977.
- Scalabrino, S., Linares-Vásquez, M., Poshyvanyk, D. & Oliveto, R. *Improving Code Readability Models with
  Textual Features.* ICPC 2016 / *A Comprehensive Model for Code Readability.* JSEP 2018.
  [doi:10.1109/ICPC.2016.7503707](https://doi.org/10.1109/ICPC.2016.7503707)
- Trockman, A. et al. — the MSR 2018 result cited throughout this repo's readability code as finding no
  readability metric or combination correlates strongly with measured understandability (see
  `src/readability.h`, the readability design note §0).
- Fakhoury, S. et al. *Improving Source Code Readability: Theory and Practice.* ICPC 2019 — 548
  developer-declared readability-improving commits across 63 projects; classic models "fail to capture
  readability improvements."
- Peitek, N., Apel, S., Parnin, C., Brechmann, A. & Siegmund, J. *Program Comprehension and Code Complexity
  Metrics: An fMRI Study.* ICSE 2021. [doi:10.1109/ICSE43902.2021.00056](https://doi.org/10.1109/ICSE43902.2021.00056) —
  Halstead volume specifically tracks measured cognitive load.
- Vitale, T. et al. (2025) — cited in the readability design note §0 as finding up to a third of classic
  readability ground-truth labels self-contradictory.
- Ye, H., Ran, F., Xu, W. & Zhou, M. *Characterizing Readability Issue Patterns and the Role of Prompt
  Design in LLM-Generated Code.* arXiv:2605.13280 — prompt design's role in generated-code readability is
  bounded; cited in the readability design note §7.
- CoReEval, arXiv:2510.16579 — LLM self-judges of code readability fixate on surface features; cited
  alongside the prompt-constraint study in the readability design note §7 as the joint reason
  `--quality-delta`'s gate is deterministic and external to the model, applied to the diff.
- `docs/LINEAGE.md` §9.0 and `src/naminglens.h` (top-of-file comment) — the withdrawn `naming-body-mismatch`
  rule, this repo's only other instance of "measured, then withdrawn," and the template §5 of this document
  follows.
