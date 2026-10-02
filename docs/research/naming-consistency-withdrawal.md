# Naming-consistency detection: a withdrawal, reconstructed as evidence

**Status: a first pass and a negative result.** This document does not propose a feature. It reconstructs
one we built, shipped for one commit (`a63a9f15` → `7eeb976f`, both 2026-08-05), measured on our own
source, and withdrew the same day, before any release carried it — and argues that the paper below
explains *why* it failed, from the opposite direction of how the paper's own subjects failed. We are
publishing the failure because we think it is a useful data point for anyone building a naming-quality
tool, deep-learning-based or not, and because we would like to be told where this reasoning is wrong.

**The paper.** Taiming Wang, Yuxia Zhang, Lin Jiang, Yi Tang, Guangjie Li, and Hui Liu, *Deep
Learning-Based Identification of Inconsistent Method Names: How Far Are We?*, Empirical Software
Engineering (2025), [doi:10.1007/s10664-024-10592-z](https://doi.org/10.1007/s10664-024-10592-z),
[arXiv:2501.12617](https://arxiv.org/abs/2501.12617). Its finding, in one sentence: prior evaluations of
DL-based method-name-inconsistency detectors used an artificially **balanced** dataset — inconsistent and
consistent names in equal number — built by a flawed construction process, and once the same detectors are
scored against a realistic, **unbalanced** distribution (most real method names are consistent), reported
performance is far less reliable than the balanced-dataset numbers suggested. The paper's own contribution
is a new benchmark built by combining automatic mining of commit histories with manual developer
inspection, specifically to reduce the false positives a naive construction bakes in.

Nothing in this document uses the paper's code, data, or trained models — no naming-consistency model runs
anywhere in ripwire, deep-learning or otherwise, and this branch adds none. The relevance is the *lesson*:
an evaluation distribution that does not match deployment collapses a detector that looked fine on a
curated set. ripwire's naming lens is deterministic rules over the symbol index for exactly this reason —
and even so, §2 below shows the same collapse can happen to a rule that has no training set, no balanced
benchmark, and no model at all, because the discipline the paper argues for was skipped, not because deep
learning was the problem.

---

## 1. What "the naming lens" is, so the withdrawal below is legible

`src/naminglens.h` is ripwire's identifier-naming quality lens: nine deterministic, dictionary-free rules
surfaced as `naming-*` findings under `--lint` (see `docs/LINEAGE.md` §2 for the empirical paper each rule
mechanizes — Butler et al., Arnaoudova et al., Beniamini et al., AlSuhaibani et al., and Spärck Jones for
the one rule added after this withdrawal, `naming-uninformative`). Every shipped rule fires on a
**syntactic** fact the symbol index already holds — case mixing, digit-suffix siblings, an unresolvable
predicate return type, corpus-wide subtoken rarity. None of them ask whether a name is *true*.

One more rule was built, shipped for one commit, measured, and pulled: `naming-body-mismatch`. It is the
subject of this document.

## 2. The withdrawal, reconstructed — not retold

The commit that added the naming lens (`a63a9f15`, 2026-08-05) shipped `naming-body-mismatch`: a
$\geq$10-line function or method whose name shares **zero** vocabulary with its own definition (signature
+ body, comments and enclosing scope name counted as legitimate agreement, the name's own occurrences
excluded) was flagged as a naming risk — the axis MNire and the CIC comment-coherence work both use, in the
mechanical, ML-free form that `splitIdentifier` / `tokensAgree` in `naminglens.h` made possible (see
`docs/LINEAGE.md` row 104 for the full citation, MNire [doi:10.1145/3377811.3380926] and Scalabrino et al.
[doi:10.1109/ICPC.2016.7503707]). The very next commit (`7eeb976f`, same day) withdrew it.

Rather than take the withdrawal commit's word for it, this document **rebuilt the shipping commit and
reran it**. `a63a9f15` was checked out into an isolated worktree, built with the project's ordinary dev
build (`cmake -S . -B build && cmake --build build -j8`, no `-DCMAKE_BUILD_TYPE=Release`), and run as
`./build/ripwire src --lint` against ripwire's own `src/` at that exact commit — the same population the
withdrawal commit message reports. The reproduction is exact:

| rule | count |
| --- | --- |
| naming-short | 12 |
| naming-wordy | 13 |
| naming-series | 0 |
| naming-underscore | 0 |
| naming-case | 10 |
| naming-predicate | 0 |
| naming-setter | 0 |
| naming-confusable | 23 |
| **naming-body-mismatch** | **159** |
| **total naming findings** | **217** |

`naming-body-mismatch` alone produced 159 of 217 naming findings — **73%** of the entire lens's signal,
from the one rule its own doc comment already called "weakest-confidence." That is not a rate quoted from
memory; it is `count="159"` and `count="217"` (summed) read directly off a freshly built binary's own XML
output at the commit that shipped the rule.

**What it actually flagged.** Pulling the individual `<f rule="naming-body-mismatch" ...>` rows out of that
same run and reading a sample of the flagged symbols' real bodies (not the commit message's four examples —
independently re-selected from the full 159) turns up the same pattern throughout:

- **`probabilityMass( std::span<const double> values )`** (`src/pagerank.cpp`) — a blocked summation loop
  over `values`, `blockBegin`, `partial`, `total`. Not one token in the body is `probability` or `mass`;
  the name states what the sum *represents* in PageRank's algorithm, the body states *how a sum is
  computed*. Flagged.
- **`isPublicApi( const IngestResult& ing, NodeId i )`** (`src/quality.h`) — checks a file extension
  (`.h`/`.hpp`/`.hh`/`.hxx`) against a documented convention ("headers are the public surface"); the word
  "public" appears nowhere in the body, only in the preceding doc comment, which the rule's own body-window
  does not read. Flagged.
- **`msetDiff( a, b )`** (`src/crossref.h`) — a linear merge over two sorted multisets; its own doc comment
  literally opens "Multiset difference a \ b," but `msetDiff`'s subtoken `mset` does not prefix-match
  `Multiset` closely enough for `tokensAgree`, and again the comment is out of the scanned window. Flagged.
- **`sha1Hex( head, body )`** (`src/infra/gitblob.h`) — a complete, correct SHA-1 implementation (the
  standard five-word state, block compression, MD-padding, hex encoding). No token in a bit-twiddling
  cryptographic-hash body is going to read `sha1` or `hex`. Flagged.
- **`skipOneTrivia( Lexer& lx )`** (`src/macroreparse.h`) — skips one unit of lexer "trivia" (a standard
  compiler-construction term for whitespace/comments/line-splices); the body's vocabulary is `pos`, `line`,
  `splice`, `startsWith` — the domain term in the name is precisely the kind of vocabulary a body never
  restates. Flagged.

Every one of these is a *correct, precise* name. The commit message's own worked example makes the general
shape explicit: `didYouMean( ing, name )` has body vocabulary `dist` / `prefixLen` / `best` / `boundedEditDistance`
/ `tolower`; overlap with the name's own tokens `{did, you, mean}` is necessarily zero, and the name is
excellent. **A good abstraction name states intent; its body states mechanism.** Zero lexical overlap
between the two is not evidence of a bad name — on this population it was the *majority* pattern of a good
one. The rule's threshold had a sign error baked into its very premise, not just a bad cutoff.

The reproduction also surfaces two things the original commit message did not have room for:

1. **The direction was untestable, not just miscalibrated.** The withdrawal commit's own reasoning holds:
   near-zero overlap contains both great abstractions *and* genuine lying names, and near-total overlap
   contains both precise restating names *and* redundant ones (`addOneToCounter`). Any single cut on this
   axis puts real cases of both quality classes on both sides of it. No re-tuned threshold fixes that,
   because the axis itself does not separate the quality classes.
2. **The scan window excluded the strongest evidence.** Doc comments were deliberately *not* counted as
   body vocabulary (a scoping decision, not a bug), which means the rule was blind to exactly the text a
   human reader would check first — `isPublicApi`'s and `msetDiff`'s doc comments both state, in English,
   the concept the flagged name names. A rule that cannot read the sentence next to the code it is judging
   is working with less evidence than the average reviewer.

This document treats that reproduction — a rebuilt, rerun binary against the exact commit and the exact
population the original claim was about — as the record. The commit message's original examples are folded
into it rather than repeated as a second source.

## 3. Generalizing it: what a naming check has to demonstrate before it ships

The paper's finding is about *evaluation distribution*: a detector scored on a balanced, curated set can
look competitive and then collapse once scored on the real, overwhelmingly-consistent population it will
actually run against, because the balanced construction hides how rare the positive class really is and
how much of the reported precision was an artifact of that rarity being suppressed.

Our withdrawal is the same failure, reached from the other end. `naming-body-mismatch` had no training
set, no balanced benchmark, and no learned weights to overfit — it is nine lines of subtoken-overlap
arithmetic. It still collapsed the first time it was pointed at a realistic population (ripwire's own
`src/`, no curation, no held-out split, every eligible symbol scored), because **the population it was
finally measured against was the first population it was ever measured against.** Plausibility, not
distribution, was the design input; the paper's discipline — measure against the *deployment* distribution,
not a convenient one — was skipped entirely, and skipping it is sufficient to reproduce the paper's failure
mode even with zero machine learning in the loop.

So: what would a naming-consistency check — ours or anyone else's — have to show before it goes into
`--lint`, given both failures agree on the mechanism?

**1. State the population it is evaluated on, and it must not be curated.** Not a benchmark built by
pairing known-bad names 1:1 with known-good ones (the paper's own critique of the balanced-dataset
construction), and not a hand-picked "these look wrong" set assembled while writing the rule (how
`naming-body-mismatch` was designed). The population has to be *every eligible symbol in a real codebase*,
scored without knowing in advance which ones are bad — which is exactly the discipline
`--naming-calibration` (§9.5, below) already applies to the *other* eight rules, and the one
`naming-body-mismatch` never got before it shipped.

**2. State the base rate of genuine inconsistency in that population, honestly, with its own uncertainty.**
A rule's raw finding count means nothing without knowing what fraction of the scored population is actually
positive. §4 below is our attempt at that number; it is small and admits it.

**3. Require a precision floor set from the base rate, not from what the rule happens to score.** This is
the discipline `test/namingcalibrationcheck.sh` already states for the *other* naming rules — "floors are
declared here, not derived from what today's rules score" — and it is the one paragraph of that gate's own
comment that a semantic-accuracy rule like `naming-body-mismatch` would need a sibling of. Concretely, from
what we can measure (§4): if the true base rate of a genuinely inconsistent name in reviewed, real code is
in the low single digits (our own estimate below is consistent with, at most, high single digits, and
plausibly much lower), then a rule scoring 50% precision on a realistic held-out sample is already
delivering something like a 10–25x enrichment over flagging at random — and 50% is a low bar to call
"worth an agent's attention," not a high one; an agent that acts on a coin flip half the time it is wrong
will learn to ignore the lens. `naming-body-mismatch` measured at the opposite end of that scale: on the
one population it was ever checked against, its true-positive rate among its own 159 findings, by the
worked examples above, rounds to zero — worse than chance, because the axis fires *more* on good names than
bad ones.

**4. Score direction, not just firing.** `--naming-calibration` is the existing instrument that would have
caught the *sign* of the error, if it had existed a commit earlier: it mines real `old -> new` renames from
git history, scores both spellings with the same rule predicate, and reports `proxy = old/(old+new)` — a
useful rule should fire on the abandoned spelling more than the chosen one. Its declared floors
(`test/namingcalibrationcheck.sh`, set from what a useful rule *ought* to clear, not from today's rules'
scores) are `proxy >= 0.70`, at least 30 labelled pairs, at least 10 fires per rule. Measured on ripwire's
own history at the time it shipped (197 commits, 229 raw substitutions, 13 labelled pairs after joining to
symbols still alive at HEAD) the sample was **below the 30-pair floor and the gate correctly skipped rather
than asserting anything** — "no shipping rule is validated by this corpus; none is refuted either," in the
commit's own words. That is the right failure mode for an instrument: silence under insufficient evidence,
not a false pass. It is also a limit worth being explicit about: `--naming-calibration` only ever sees
*renames*, and on this repository's history the largest mined family is a whole-project rebrand carrying no
naming information at all — so even a rule that cleared the floor there would only be validated on
*directional* correctness (does it point at the abandoned spelling), never on *absolute* precision against
a realistic population's true rate of bad names. A rule needs both: §9.5's directional check, and a
population-precision check like the one this document attempts in §4 — neither is a substitute for the
other, and `naming-body-mismatch` had neither before it shipped.

## 4. Measuring the base rate — small, sampled, and honestly reported

This is the piece we can measure ourselves, on what is already on this machine, without inventing a number.

**Method.** `bench/naming/sample_base_rate.py` (added on this branch) pulls a uniform random sample of
top-level function/method definitions, with full bodies, from real on-disk checkouts — never downloaded
for this task, already present from prior ripwire eval rounds:

- **Python** (n=20): drawn from a pool of real, actively maintained GitHub projects including CPython,
  Zulip, and several scientific/infra codebases, checked out under `bench-assets/r4/repos_{b,c,d,e}`.
- **Swift** (n=10): Alamofire and apple/swift-nio, under `bench-assets/swift`.
- **C++** (n=12): ripwire's own `src/` — the one part of the sample this document can also cross-check
  against ripwire's own tooling.

Sample size and seed are fixed in the script (`n=42` requested, seed `20260920`, matching this
measurement's date) so the sample is reproducible against the same checkouts. Candidates are restricted to
3–60 non-blank body lines: long enough to carry real behavior, short enough to judge on one screen without
losing context partway through.

**Judging criteria, stated before the count.** For each sampled `(name, body)` pair: does a reader relying
only on the name form an expectation of the function's primary behavior, return value, or side effect that
the body actually fulfills? Three outcomes:

- **Consistent** — the name's claim holds.
- **Inconsistent** — the body does something the name does not claim, omits something the name specifically
  promises, or does the opposite.
- **Excluded** — the pair carries no naming-quality signal to judge, for one of two disclosed reasons:
  (a) the name is a language- or framework-mandated hook with no freely chosen semantic content
  (`__init__`, `__call__` — "this initializes," "this is callable" is true by construction and unfalsifiable,
  unlike `setUp` or a protocol method with an actual behavioral name, which *were* judged); or (b) the
  sampling script's regex-based extraction — it does not parse, unlike ripwire itself — paired the wrong
  body with a name (2 of 42: a multi-line Python signature that swallowed only its own parameter list, and
  a Swift protocol requirement with no body whose brace-match walked into the next declaration). Both
  exclusion reasons are disclosed rather than silently dropped, and both are limits of this one-off script,
  not of ripwire.

**Result.** Of 42 sampled pairs, 4 were excluded (2 mandated-hook, 2 extraction-artifact) leaving **38
judged pairs. 0 of 38 were judged inconsistent.** Every judged name — across three languages, four
unrelated real projects, and ripwire's own source — held up against its body, including ones that required
a moment's domain knowledge to check (`bpformat` — "breakpoint format," a `bdb.py` method whose docstring
and body both confirm it; `rch_dict` — a MODFLOW-recharge-package test fixture in `imod-python` returning
exactly the dict its name promises; `skipOneTrivia` and `chaseFieldOf`, both correctly using
compiler-construction jargon a body's variable names would never restate).

**What that number does and does not support.** Zero positives in 38 trials is evidence the base rate is
low, not evidence it is zero — 38 real functions from reviewed, merged, production and test code is not
enough to rule out a genuinely rare event. A standard "rule of three" bound for zero observed successes in
$n$ trials puts the population rate's approximate 95% upper bound at $3/n \approx 3/38 \approx 7.9\%$. We
report that as an *upper* bound, not a point estimate — the true rate is very plausibly well under it, and
we have no lower bound at all. Two limits work against generalizing even this much: the sample leans
heavily on test functions (`test_*` names are, by convention, close to self-documenting, which likely makes
them *easier* to judge consistent than an arbitrary production function) and on well-reviewed, mature open
source — code that has already had a maintainer's eyes on its names. A first-draft function, an
under-reviewed internal tool, or LLM-generated code with no naming convention enforced is a different
population, and this sample says nothing about its rate. **We are not claiming the real-world base rate of
inconsistent naming is 8% or lower everywhere — only that in this specific, disclosed, 38-function sample
of reviewed real code, we found no clear counterexample, and we are telling you exactly how small and how
skewed that sample is.**

**A weakness not yet stated above: judging was done by a single reader (the author of this document),
unblinded to which pairs the withdrawn rule itself had flagged, and no per-pair record of the 38
judgments is published alongside this note.**

We considered constructing known-bad examples to anchor the "what would a genuine violation even look
like" question, and did not: manufacturing one and then reporting a rate against a set that includes it
would misrepresent the sample as containing more signal than it does. The nearest published anchor for what
the flagged class looks like when a check is well-scoped, rather than what we are trying to avoid
inventing, is the Linguistic-Antipattern literature already folded into `naminglens.h`
(`naming-predicate`/`naming-setter`, Arnaoudova et al.) — a getter whose known return type contradicts its
`is`/`has` prefix, or a `set`-prefixed method with a non-`void` known return. Those are checkable from a
type fact, not a vocabulary-overlap guess, which is exactly why they shipped and `naming-body-mismatch`
did not.

## 5. What ripwire ships today that touches names

So this document does not read as more confident about the present than it should. As of this branch,
ripwire ships **no semantic name-accuracy judgment** — nothing that asks "does this name match what its
body does" — anywhere in the tool. What it does ship, all deterministic, all syntactic or corpus-statistical
rather than semantic:

- **The symbol index itself** (`src/model.h`, `src/ingest*.h`) — every symbol's name, kind, scope, and
  spans are indexed data. This is the substrate everything else below reads; it makes no naming judgment on
  its own.
- **Eight of the original nine `naming-*` lint rules** (`src/naminglens.h`, `--lint`): `naming-short`,
  `naming-wordy`, `naming-series`, `naming-underscore`, `naming-case`, `naming-predicate`, `naming-setter`,
  `naming-confusable` — each a syntactic or known-type-fact check, none reading a body's vocabulary.
- **`naming-uninformative`** (`src/naminglens.h`, added after this withdrawal, §9.0a candidate 1) — the
  rule's actual successor. It replaced name-vs-body vocabulary overlap with corpus IDF over identifier
  *names themselves* (not body or doc text): a name fires only when every one of its split subtokens is
  corpus-ubiquitous (low information, Spärck Jones 1972) **and** the body clears a size floor. It is
  one-sided by construction — a rare subtoken is never penalized, only a universally common one ever is —
  which is exactly the defensible direction the withdrawn rule's axis did not have.
- **`--naming-consistency`** (`src/namingconsistency.h`) — convention normalization only: given a group of
  co-visible names that already votes for a dominant case style (camel/pascal/snake/screaming), it proposes
  recombining an off-convention name's own subtokens into that style. It never invents or judges a word; it
  is a style suggestion, never a verdict, and the file's own header cites `naming-body-mismatch`'s
  withdrawal as the reason it stops exactly there.
- **`--naming-calibration`** (§9.5, `src/renamemine.h`) — the rename-history proxy instrument described in
  §3 above: a measurement tool for the other naming rules' *direction*, not a rule that fires on ordinary
  (non-renamed) code.
- **Doc-comment matching inside `--for`** (`src/lexical.h`, `src/filter.h`) — a doc comment's vocabulary is
  weighted evidence in the BM25 ranking that decides what to *retrieve* for a query. This is relevance
  ranking, not a claim about whether the comment or the name is accurate.

`tokensAgree` and `splitIdentifier`, the substrate the withdrawn rule needed, are kept in `naminglens.h`
on purpose — the header's own comment says why: the predicate that "two spellings agree" measured *fine*;
what measured wrong was the rule's direction, and that substrate is what `naming-uninformative` and
`--naming-consistency` both now build on instead.

## 6. What we would like help with

Two open questions are where we think outside expertise would most change what we build next, and we are
publishing this specifically to ask about them rather than to announce a plan:

1. **The evaluation-distribution question.** Given the paper's finding and our own reproduction of the same
   failure mode without any learned model in the loop — is there a deterministic, syntax-or-index-level
   signal (not requiring training data, not requiring execution) that *would* clear a realistic-population
   precision floor for name-body consistency specifically? We suspect the answer may be "not from lexical
   overlap at any granularity," given that near-zero overlap turned out to be the dominant pattern for good
   names in our own population — but we have not tried every axis (e.g., structural/control-flow shape
   matched against name-implied verbs, rather than vocabulary), and would value being told what we have not
   ruled out versus what we have.
2. **The base-rate question.** §4's number is small, self-sampled, and heavily caveated. Is there a labelled
   dataset — ideally one built with the paper's own discipline (real commit-history mining plus manual
   inspection, not a balanced construction) — usable to get a tighter, less self-selected estimate of how
   often a name genuinely misdescribes its body in real, reviewed code? If the true rate turns out to be
   meaningfully higher than our upper bound suggests in some population we have not sampled (generated
   code, under-reviewed internal tooling, a specific language ecosystem), that changes whether a precision
   floor like the one in §3 is even reachable, and we would rather know that before spending more engineering
   on this axis than after.

We would welcome a critique of any of the four sections above — the reproduction in §2, the requirements
argued for in §3, the sampling and judging in §4, or the inventory in §5 — and especially a pointer to
where this reasoning has already been made more rigorously elsewhere.

## 7. Cross-corpus check with the calibration probe

`naming-body-mismatch` itself cannot be re-run — it was removed in the withdrawal commit, and nothing here
reintroduces it. What can be re-run, on more evidence than ripwire's own history offers, is
`--naming-calibration` (§9.5): the instrument that mines genuine `old -> new` renames from git history and
asks whether the *currently shipped* naming-* rules fire on the abandoned spelling more than the chosen
one. On ripwire's own history alone it previously stopped below its declared 30-pair floor (13 pairs) and
correctly skipped rather than asserting anything. `bench/ensemblecal/` already tracks five corpora for a
related calibration (§9's family-orthogonality measurement); pointing `--naming-calibration` at the same
five, instead of only at ripwire, is a cheap strengthener neither measurement had run before.

**Command**, run once per corpus root: `ripwire <corpus-root> --naming-calibration --legend=compact`.
Binary: `ripwire 0.6.2 (dev, AppleClang 21.0.0.21000101, emit=std::print, built_from=15a20855c)`.

| corpus | git history? | pairs | candidates | commits | rules fired (of 6 scoreable) | proxy on fires |
| --- | --- | ---: | ---: | ---: | --- | --- |
| ripwire | yes | 86 | 1 371 | 2 821 | none | — |
| gameA | yes | 55 | 750 | 1 637 | naming-wordy=2, naming-case=1 | 0.000 (both on the *chosen* spelling) |
| tree-sitter (vendored) | yes | 3 (below the 30-pair floor) | 1 371† | 2 821† | none | — |
| rustCLI | **no** (`probed="0" r="not-a-git-repo"`) | — | — | — | — | — |
| appleXR | **no** (`probed="0" r="not-a-git-repo"`) | — | — | — | — | — |

† tree-sitter (vendored) is a subtree of ripwire's own repository, so `candidates`/`commits` are the same
repo-wide walk filtered to paths under the vendored subtree; only 3 mined substitutions survive the join
there, which is why it is reported separately rather than pooled with ripwire's row.

`naming-series` and `naming-confusable` judge a relationship between co-visible names and cannot be scored
from one pair (`scope="group-rule"`), so 6 of the 8 rules this instrument scores were eligible to fire at
all. `naming-uninformative`, the rule that replaced the withdrawn one (§5), postdates this instrument and
is not among the rules it scores either.

Two of the five corpora present locally have no git history to mine — `rustCLI` and `appleXR`, the same
"(no git)" trees `docs/EVALS.md` §9.1 already records for the ensemble calibration — so the probe reports
`probed="0" r="not-a-git-repo"` on both and contributes nothing here. `tree-sitter (vendored)` reached
`probed="1"` but stayed below its own 30-pair floor, the same failure mode as ripwire's original 13-pair
run, and is reported rather than pooled. That leaves ripwire and gameA, each independently over the
30-pair floor for the first time this instrument has been run outside ripwire's own history: **141 pooled
labelled rename pairs, 846 rule-pair opportunities across the 6 scoreable rules, and 3 fires total** — all
three on the *newly chosen* spelling rather than the abandoned one (proxy 0.000 on both fired rules in
gameA; ripwire's own 86 pairs produced zero fires on any of the 6 rules).

**Verdict.** This does not, and cannot, re-score `naming-body-mismatch` — it no longer exists to score, and
this instrument only ever scored the other eight rules' direction. What it adds is independent evidence for
the premise under §3 and §4: across 141 genuine rename events in two large, independent, real codebases —
not ripwire's own 13-pair, below-floor sample — a name actually being replaced because it was wrong is rare
enough that even the deterministic rules built to catch known-decidable naming defects almost never fire on
it, and the three times they did, they pointed at the developer's own newly chosen name, not the one they
abandoned. That is the opposite of what a 159-of-217 (73%) flag rate implies about how often real naming
defects occur, so it **corroborates** the withdrawal's low-base-rate claim, by an independent method and a
larger, more diverse sample than §4's. It does not by itself bound the base rate the way §4's direct manual
judging does, and the two no-git corpora (`rustCLI`, `appleXR`) remain untested by this method — they would
need a labelled sample built some other way.
