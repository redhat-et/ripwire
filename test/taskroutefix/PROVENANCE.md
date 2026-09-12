# taskroutefix corpus provenance

Charter: the taskroute round's orchestrator review addendum (2026-08-13, first row).
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

## data-flow / at-line / who-writes coverage round (2026-09-02, lane/n2-d)

**Corpus state note.** The corpus has grown since the 2026-08-13 sections above without a matching
PROVENANCE.md update: it now also carries a third provenance family, `provenance=instrumented-cli`
(36 rows, split by the same hash rule), used for paraphrase rows of `exact-grep`/`edit-contract` —
intents whose routing vocabulary is itself a small closed phrase list, so a paraphrase that still
triggers the intent necessarily reuses a cue phrase from the card. `contamination_screen.py` only
screens `provenance=handwritten*` rows by construction (`row["provenance"].startswith("handwritten")`),
so `instrumented-cli` rows are exempt from the trigram screen the same structural way `templated`
rows are pinned to dev — this section documents that reasoning since the original file never did.
Row counts as of this round (before the 25 rows below): 158 total, 86 templated + 36 instrumented-cli
+ 47 handwritten-digD* (unchanged from the sealed round); split dev=81/test=52 (unchanged).

**New intents, new rows.** Three router intents shipped this round (`src/taskroute.h`): `data-flow`
(`--slice=SYM:VAR --slice-flow=back`, or bare `--slice=SYM` when no variable-slot cue names a
variable), `at-line` (`--slice=@FILE:LINE` from a literal or prose-stated file:line), and
`who-writes` (`--uses=SYM`; the `Owner.field` dotted form is deliberately NOT specially parsed —
today it resolves the owner symbol only, per the round's own scope). Because these three intents'
routing vocabulary is likewise a small closed phrase list (`"who writes"`, `"data flow"`, `"flows
into"`, …), the SAME reasoning as `instrumented-cli` above governs the 25 new rows: they are
handwritten in genuinely original sentences (none copied from the round's own briefing prompt) but
necessarily use one of the closed-vocabulary trigger phrases somewhere, the same way the existing
`exact-grep`/`edit-contract` paraphrase rows do. Provenance is recorded as `handwritten-digE` to
keep them distinct and auditable, and the split is the same content-hash rule
(`sha256(prompt)[0] < 0x4D → dev`), computed and verified per row before insertion (every row's
actual hash-rule split matches its recorded `split` column — checked mechanically, not by hand).

**Contamination screen result.** `python3 test/taskroutefix/contamination_screen.py --bin
build/ripwire` (now scanning 12 recommended-verb `--help` blocks, `--slice --slice-flow --at --uses`
added to the reference set alongside the original 8) reports exactly ONE flagged line, and it is
NOT one of this round's rows: `line 61, trigram 'i change its'` on a pre-existing
`handwritten-digD-10` row from before this round, colliding with the illustrative example `"did I
change its contract?"` quoted in a `src/taskroute.h` comment. Confirmed pre-existing by running the
same screen against `origin/main`'s prompts.tsv before any row in this round was added — identical
single flag, same line, same trigram. Out of scope for this round (not introduced by it, not one of
this round's own intents); flagged separately for follow-up. All 25 new rows individually screen
clean — diffing the screen's flagged-line output before and after this round's rows land shows zero
new flags.

**Row counts added:** 25 (14 test, 11 dev; every new row's actual placement verified against a
live binary before insertion — see the before/after routing table in `docs/EVALS.md` §4). By
intent: `data-flow` 8 (4 test, 4 dev), `at-line` 7 (4 test, 3 dev), `who-writes` 5 (3 test, 2 dev),
`abstain` (negative) 5 (3 test, 2 dev) — covering both the "wording scores but no symbol/file
resolves" shape and the "wording never scores" shape per intent.

**Seal: sha256(prompts.tsv) = `b113a217a19237a1616f81fe412b06475df848e5974214f1efc496db2519dcc0`**
(post-round; rows=158, dev=92, test=66).

## Weak-tier precision round (2026-09-10, lane/helptask-precision)

**Why the corpus grew.** The 2026-09-10 audit (F-R1-01/02) showed the weak symbol tier recommending
`--expand=<English word>` on 13 of 25 adversarial prose prompts, and the committed corpus scoring
`harmful=0.000` throughout — because **the evaluator's fixture repo had no lowercase English-word
symbols at all**. Every name in `make_repo` was camelCase or Pascal, so no row could reach the weak
tier, and the class was invisible by construction. Two things changed together, and neither is
useful without the other:

- `bench/taskroute_eval.py::make_repo` gained nine lowercase code definitions (`classify`, `report`,
  `patch`, `header`, `prefix`, `audit`, `release`, `target`, `binary`) and a `package.json` whose keys
  index as `t="sec"` symbols (`version`, `summary`, `license`, `agent`, `author`, `notes`) — the two
  halves of the collision class: an English word that IS code, and an English word that is only a
  config key. `test/taskroutecheck.sh`'s own fixture repo gained the same two halves (`patch`, plus a
  `package.json` carrying `version`/`license`/`notes`).
- **Measured control:** on the 158 pre-existing rows the extended fixture repo changed nothing —
  `split=test/dev/all` accuracy, precision, harm, specificity, coverage and every confusion line are
  byte-identical before and after the repo grew (same pre-change binary). The new symbols are reachable
  only from the new rows.

**Rows added: 31 (23 test, 8 dev).** Split by the same content-hash rule
(`sha256(prompt)[0] < 0x4D → dev`), computed mechanically per row.

- **25 negatives, `provenance=handwritten-auditR1`** — the audit's own adversarial set
  (`$S/r1/s2b_adversarial.tsv`), quoted verbatim as evidence: non-code questions whose subject word is
  also an indexed name, placed directly after a symbol-slot cue. 13 of them recommended before this
  round. They are recorded under a `handwritten*` provenance deliberately, so the trigram screen and
  the split rule both apply to them.
- **3 negatives, `provenance=instrumented-cli`** — the `t="sec"` half stated in the understand card's
  own closed vocabulary (`the implementation of version|license|author`). These are caught ONLY by the
  kind filter: their intent word is disjoint from the cue that mints the name, so the
  self-confirmation rule never sees them. Same `instrumented-cli` rationale as the 2026-09-02 section
  above (a paraphrase that still triggers a closed-phrase intent necessarily reuses a card phrase).
- **3 positives (`understand-symbol`), `provenance=instrumented-cli`** — the recall the fix must NOT
  buy its precision with: a lowercase weak name still routing to `--expand` through a cue the gate does
  not itself consume (`the implementation of prefix`, `the implementation of audit`), and the sharpest
  statement of the invariant — a how-does question that later asks for the body OF the same name, which
  routes on that second, independent cue occurrence.

**Screen result: 2 flagged lines, one pre-existing and one new, both stated rather than reworded.**
`python3 test/taskroutefix/contamination_screen.py --bin build/ripwire`:

- `line 61, 'i change its'` — the pre-existing `handwritten-digD-10` flag documented in the 2026-09-02
  section above. Unchanged, still out of scope.
- `line 176, 'the value of'` — new, on the negative row *what is the value of module thinking in org
  design?*. The trigram collides with the `kVariableSlotCues` literal `"the value of"`. It is not
  reworded, for two reasons: the row is audit evidence quoted verbatim, and card vocabulary inside a
  NEGATIVE row is adversarial pressure (a live cue phrase that must still not route), the opposite of
  the self-quotation the screen exists to catch. The screen makes no positive/negative distinction and
  was deliberately not taught one to pass this round.

`FIXTURE_SYMBOLS` in the screen was deliberately NOT extended with the new lowercase names: they are
ordinary English words, so exempting them would blank real prose out of every screened row and hide
flags the screen is there to raise.

**Scoring run, same binary, three splits** (`python3 bench/taskroute_eval.py --bin build/ripwire
--corpus test/taskroutefix/prompts.tsv --split …`), pre-change binary → post-change binary:

| split | rows | accuracy | precision | harmful | neg-specificity | coverage |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| test | 89 | 0.787 → **0.921** | 0.797 → **1.000** | 0.135 → **0.000** | 0.657 → **1.000** | 0.870 → 0.870 |
| dev | 100 | — → **0.940** | — → **1.000** | — → **0.000** | — → **1.000** | — → 0.920 |
| all | 189 | 0.847 → **0.931** | 0.879 → **1.000** | 0.085 → **0.000** | 0.733 → **1.000** | 0.899 → 0.899 |

The pre-change `split=test` run **exits 1** (precision below the 0.90 floor, harm above 0.02,
specificity below 0.90): the corpus can now fail on this class, which is the whole point of the round.
Coverage is unmoved and every confusion line is identical to the pre-round run — no actionable row lost
its route.

**Seal: sha256(prompts.tsv) = `25283f2eba85aad889fe3746308df76ed8b1244529f44986c936eb6ef60b0b53`**
(post-round; rows=189, dev=100, test=89).

## Catalog-tier round (2026-09-10, lane/helptask-precision) — the verbs and skills with no route

**The gap.** The audit measured `--help-task` at **3 recommends over 39 phrasings** of the 13 surfaces
added since 2026-08-28 (F-R1-08), and found the router able to name **8 of the 16** shipped skills
(F-R1-09) — `--help-task` and the skill catalog were two routers with two vocabularies. Three of the
unrouted surfaces are VERBS, not shaping flags: `--handoff` (which has its own shipped skill),
`--plan-lint`, and the PROSE form of `--from-trace` (`looksLikeTrace` matches a PASTED artifact, and a
sanitizer report described in words contains none of its literals).

**Ten new intents** in a `catalogTaskChoice` tier that sits LAST in `directTaskChoice`, so every older
and more specific route keeps its rows: `handoff-brief` (`--handoff`), `plan-lint` (`--plan-lint=FILE`),
`trace-prose` (`--from-trace=-`), `scan-skills`/`scan-skill` (`--scan-skills`, `--scan-skill=FILE`),
`opt-remark` (`--for=TASK`), `architecture-health` (`--deps`), `quality-check` (`--quality-delta`),
`perf-symbol` (`--around=SYM`), `graph-query` (`--graph-query=EXPR`), `maintenance-risk`
(`--hotspots`). Skills nameable: **8 → 16**, and `test/taskroutecheck.sh` now reads BOTH sides from disk
so a new skill shipping without a route fails as loudly as a route naming a skill that does not exist.

**Rows added: 36 (30 positives, 3 per intent, + 6 negatives), `provenance=instrumented-cli`**, split by
the same content-hash rule. `instrumented-cli` for the same reason the 2026-09-02 section gives: each new
intent's trigger is a small closed phrase list, so a sentence that routes necessarily reuses one of its
phrases. Every row's routing outcome was verified against a live binary before insertion (30/30 after one
correction — see below); the 6 negatives are the near misses that must NOT route (an account handed off
to support, a landing-page design that needs a check, vetting a candidate's onboarding plan, a team that
inherited a support queue, a profiler vendor selling licences, a quarterly summary handed to leadership).

**Two corrections the pre-insertion verification caught, recorded rather than smoothed over:**

- *"lint the shape of docs/design-notes.md before I circulate it"* abstained: the surface test wanted the
  words "plan"/"design doc" in the PROSE. A file that names ITSELF a plan (`PLAN_*.md`, `DESIGN_*.md`) is
  surface evidence the prose need not repeat, so the check now reads the named file's own name too.
- *"lint the plan file layout before I commit it"* routed to `quality-check`. `"before i commit"` is a
  TIMING word, not a quality word — it fits linting a plan or running a gate equally well. Re-weighted
  below the floor so it can only ever CONFIRM a quality word, never carry the route alone. The prompt
  now abstains, which is correct: it names no file, and `--plan-lint` refuses a file that is not there.

**Held-out floors, before → after** (`bench/taskroute_eval.py`, same corpus, only the binary changed —
the pre-change binary is this lane's own commit 2, built and kept for the comparison):

| split | rows | accuracy | precision | harmful | neg-specificity | coverage |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| test | 114 | 0.754 → **0.939** | 1.000 → 1.000 | 0.000 → 0.000 | 1.000 → 1.000 | 0.627 → **0.907** |
| dev | 111 | — → **0.946** | — → 1.000 | — → 0.000 | — → 1.000 | — → **0.929** |
| all | 225 | 0.809 → **0.942** | 1.000 → 1.000 | 0.000 → 0.000 | 1.000 → 1.000 | 0.730 → **0.918** |

This round's red-first proof is the GATE, not the eval: coverage has no floor by the round-1 rule, so
the eval exits 0 either way. Eleven `taskroutecheck` arms fail against the pre-change binary (every one
abstained with `score="0"`), plus the two execution arms; the skill-vocabulary arm fails against the
pre-change SOURCE, naming all eight skills no `--help-task` answer could reach.

**Regression discipline.** All 189 rows that predate this tier are BYTE-IDENTICAL on
(status, intent, resolved_symbols) between this lane's commit 2 and commit 3. Surface coverage on the
audit's own 39 phrasings: **3/39 → 9/39** — the remaining 30 are the shaping flags (`--scope`,
`--slice-depth`, `--slice-flow`, `--allow-dirty`, `--no-ignore`, `--no-post-check`), the eval-only
`--pin-census`, `--edit-check` paging, and value-carrying abstentions, all of which a one-command router
declines by design.

**Screen: unchanged at 2 flagged lines** (line 61 pre-existing, line 176 from the previous section) even
though this round added a large amount of new card vocabulary to `src/taskroute.h` — no `handwritten*`
row collides with any of it.

**Seal: sha256(prompts.tsv) = `1719aea95449e222718ec38151d2bd6998a95e1dd070038baa0b6e28fd0c9cf5`**
(post-round; rows=225, dev=111, test=114).
