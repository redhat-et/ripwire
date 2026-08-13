# taskroutefix corpus provenance

Charter: the PLAN.md taskroute ledger's Orchestrator review addendum (2026-08-13, first row).
The original 50-row corpus scored held-out 1.000 by self-quotation — its fixtures templated the
intent cards' own vocabulary — so those floors were declared NOT discharged until the corpus was
rebuilt from real agent phrasing under a contamination screen and a content-hash split seal.

## Provenance rules

- `provenance=templated` — the original 50 rows, written against the intent cards. They are the
  contaminated artifact: all pinned `split=dev`, permanently excluded from held-out floors.
- `provenance=handwritten-digD[-N]` — 47 new rows hand-written 2026-08-13 in real-agent voice,
  seeded (never copied) from the 2026-08-12 history-mine dig-D phrasing classes
  (`scratchpad/history-mine/digD_phrasings.md`, 31 classes + top-40 unmatched intent openings)
  with texture from `digB_scenarios.md` and `history-mine2/veinB_failures.md`. `-N` names the
  dig-D phrasing class where one applies (e.g. `-1` verify-a-claim, `-22` review-my-diff);
  bare `handwritten-digD` = no single class fit (e.g. off-topic negatives).
- Negative rows (`permitted=abstain`): 10 handwritten, drawn from the dig-D no-clean-home
  classes — build/run-the-suite (2), data wrangling, git-history, A-vs-B comparison,
  doc-section navigation, cross-branch archaeology, off-topic prose (2) — plus one
  review-phrased row on a CLEAN tree (line 71): applicability is rejection, so the router must
  not recommend `--situ` when there is no diff.
- Structured shapes inside prose are evidence, not contamination: closed claim expressions
  (`calls(...)` etc.), the eval fixture's symbol names (`make_repo` in `bench/taskroute_eval.py`),
  and machine-emitted trace lines may appear verbatim; every surrounding word is the author's.
- TSV discipline: literal `\n` escape for multi-line trace prompts (the evaluator un-escapes);
  no tabs inside prompts.

## Contamination screen (2b-round method)

`contamination_screen.py` (this directory) extracts lowercased word-trigrams from every
handwritten prompt (structured-shape tokens stripped first) and flags any trigram also present in
(a) the intent-card string literals of `src/taskroute.h` or (b) the `--help` blocks of the 8
recommended verbs (`--verify --connect --expand --from-trace --situ --pack-task --exemplar
--for`) read from the live binary. Exit 0 clean / 1 dirty. It also verifies the split seal below
and that templated rows stay pinned to dev.

Power check (2026-08-13): known-contaminated probes flag as expected —
"I am about to write one helper function" → `about to write`, `to write one`;
"is my diff safe to merge before i push" → `safe to merge`, `before i push`;
"map a stack trace onto the indexed symbols" → 4 help-text trigrams. The zero-flag result on the
real rows is therefore a measurement, not a dead instrument.

Result: **SCREEN CLEAN** — 0 flagged trigrams across all 47 handwritten rows
(reference corpus = 1040 trigrams). No row needed rewording after the first authored pass;
rows were written avoiding card vocabulary from the start.

## Split seal (assigned before the scoring run)

Rule: `sha256(prompt cell utf-8, exactly as stored in the TSV, escapes included)`; first digest
byte `< 0x4D` → `dev`, else `test` (~30/70 expected). Applied mechanically by
`contamination_screen.py` — no hand assignment. Outcome: 47 handwritten rows → 28 test / 19 dev.
Every intent kept at least one test row (plan-feature drew only 1 — the hash rule is the rule).
Test-split negatives: 6.

**Seal: sha256(prompts.tsv) = `a1e35088949689e6431b982b1d22a86042d1a01ef9067246f524e95d7689ba0d`**

Row counts by provenance × split: templated 50 (all dev) · handwritten 47 (28 test, 19 dev).
Handwritten by intent: verify-claim 5, connect-symbols 4, understand-symbol 5, review-diff 5
(all dirty), plan-feature 5, reuse-one-symbol 4, trace-debug 4, locate-task 5, abstain 10
(one dirty off-topic, one clean review-phrased).

## Scoring run (single run, after the seal; no tuning before or after)

2026-08-13, `python3 bench/taskroute_eval.py --bin build/ripwire --corpus
test/taskroutefix/prompts.tsv --split test`, verbatim, exit 0:

```
taskroute-eval split=test rows=28 accuracy=0.750 precision=1.000 harmful=0.000 negative_specificity=1.000 coverage=0.667
  confusion want=locate-task got=abstain n=1
  confusion want=plan-feature got=abstain n=1
  confusion want=reuse-one-symbol got=abstain n=1
  confusion want=review-diff got=abstain n=1
  confusion want=understand-symbol got=abstain n=1
  confusion want=verify-claim got=abstain n=2
```

Test-split composition (28 rows, all handwritten): verify-claim 3, connect-symbols 2,
understand-symbol 3, review-diff 3, plan-feature 1, reuse-one-symbol 3, trace-debug 2,
locate-task 4, abstain 7.

Reading, honestly: the pre-registered floors HOLD on real phrasing — precision 1.000 (≥0.90),
harmful 0.000 (≤0.02), negative specificity 1.000 (≥0.90) — because the router never made a
wrong recommendation and never recommended on a negative. What the contaminated corpus hid is
COVERAGE: 1.000 → 0.667. Every miss is an abstention on an actionable row, and every one is a
lexical-card vocabulary gap, not a structured-shape failure: prose-embedded closed claims
("now i'm checking whether calls(A, B) still holds …") do not match the whole-string claim
detector (2 of 7); "let me look at X more closely" / "read through X line by line" carry no
understand-trigger word; "is this diff actually ok to merge" misses every review phrase;
"writing a small utility" misses the helper/function cards; "find the bit of code … the bug is
somewhere in there" under-scores the locate floor. Coverage has no round-1 floor by
pre-registration; these six confusion lines are the v1.1 improvement backlog, to be addressed
only under a new sealed corpus per the same rules.

`test/taskroutecheck.sh` runs this same floor line as its final arm and is ALL PASS end-to-end
against the sealed corpus (2026-08-13, including the byte-compat --verify grammar arms).

## Post-seal classifier fix and re-score (2026-08-12, orchestrator)

After the sealed run above, the byte-compat gate arms surfaced a contract violation: the router
recommended `--verify='reaches(A, B)'` for symbol-to-symbol reaches phrasing — a form the shipped
`--verify` parser refuses. Fix: `looksLikeClosedClaim` now delegates to the real parser
(`rw::verify::parseClaim`) plus the verb's own layer validation (`query::isKnownLayerWord`), so a
parser-refused claim can never route to `--verify`. The corpus was NOT touched (same seal,
sha256 a1e35088949689e6431b982b1d22a86042d1a01ef9067246f524e95d7689ba0d); the re-score is a
new-binary run, not a re-roll: test split byte-identical to the sealed run (rows=28
accuracy=0.750 precision=1.000 harmful=0.000 negative_specificity=1.000 coverage=0.667, same six
confusion lines) — no fixture row exercised the fixed sub-shape, so the fix is covered by a new
deliberate gate arm (reaches(SYM,SYM) must abstain) rather than by corpus rows. Dev-split
reference on the same binary: rows=69 accuracy=0.913 coverage=0.893 — the dev–test gap is the
measured size of the self-quotation artifact.
