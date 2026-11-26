# Skill shortening round — 2026-11-26

Goal: shorter skills, with routing at least as good. Routing was measured before any skill was edited, on the frozen
corpus `test/skillevalfix/prompts.tsv` (sha256 `74953fd1a5e494f2805cb9c51cc828d59a4bf1f2c24912a069e1acdd2fa2a8ba`,
the 2026-09-10 seal, unchanged in this round): 282 rows, 214 positive and 68 negative. Every skill has at least 9
positive rows. The `judged` rows are hand-written paraphrases that sit on the boundary with a neighbouring skill.

## Method

**Lexical arm (deterministic, gated).** `ripwire skills --eval-skills=test/skillevalfix/prompts.tsv --no-cache`: BM25
over the frontmatter descriptions (`bm25-desc`, the headline arm and the one `test/skillevalcheck.sh` floors). It
ranks 16 candidate skills; the router is excluded, as the harness always does. Full output is in `lexical/`, with
per-row miss lines removed.

**Model arm (blind raters).** The brief asked for `claude -p` with a fixed model. That route was not available:
`claude auth status` on this machine reports `loggedIn: false`, and `claude -p` answered "Not logged in", both inside
and outside the sandbox. The desktop app's own sign-in does not reach the CLI. So the model arm ran as Claude Code
subagents pinned to a model alias (`haiku`, `sonnet`). Each rater got one file: the packet written by
`bench/skillrater/prepare.py` (the 16 names and descriptions exactly as a client renders them, then all 282 prompts
under opaque, seeded ids, seed 20260907) and returned `id, top1, top2`. It was told to read nothing else and to
ignore any skill list in its own context. `bench/skillrater/score.py keys/key.tsv answers/<file>` scores the
answers. The packets for both arms share one id→prompt mapping (`keys/key.tsv`), so the scores are paired row for row.

Caveat on the model arm: a subagent's system context lists the skills installed in the session that spawned it, and
those were the BEFORE descriptions. If anything leaked, it favoured the before arm. The raters ran with no tools apart
from the single Read and Write. A model rater is not deterministic, so the before packet was rated twice per model to
measure the spread between runs.

## Results

| arm | n | before | after (final text) |
|---|---|---|---|
| lexical `bm25-desc` hit@1, all positives | 214 | 147 | 147 |
| lexical `bm25-desc` hit@1, split=test (frozen) | 130 | 84 | 83 |
| lexical `bm25-desc` hit@1, split=dev | 84 | 63 | 64 |
| lexical `bm25-desc` hit@1, `judged` rows only | 160 | 100 | 100 |
| lexical `bm25-desc` sep-auc | 282 | 0.906 | 0.902 |
| lexical `for-routed` hit@1 | 214 | 141 | 141 |
| lexical `bm25-full` hit@1 (descriptions + bodies) | 214 | 138 | 133 |
| Haiku rater hit@1 (two before runs) | 214 | 208, 207 | 208 |
| Haiku negatives fired | 68 | 0, 0 | 0 |
| Sonnet rater hit@1 (two before runs) | 214 | 204, 208 | 207 |
| Sonnet negatives fired | 68 | 0, 1 | 0 |

The two runs of the unchanged before text differ by 1 row for Haiku and by 4 rows for Sonnet. Every after score sits
inside that spread. Per skill, rows won by Haiku and Sonnet together on the final text, against the mean of the two
before runs: quality-bar +2, navigate +1, orient +1, change-check −1, perf-target −1, and every other skill within
±0.5 rows. `answers_after_*` rate
an intermediate text: the same as the final apart from navigate's first five words ("You can NAME the symbol"). They
scored Haiku 207 and Sonnet 207 (1 negative fired).

In the lexical arm, one frozen test row moved from write-tests to quality-bar, and one dev row moved the other way.
`bm25-full` is the only arm that reads body text. It dropped 5 rows because the bodies have fewer words in them, and
no client routes on body text. Description edits that saved more bytes cost real lexical rows in drafts: a first draft
at −505 characters lost 16 of 214. Only the edits that cost nothing were kept.

## Consistency over k = 2 runs, and balance (added after the audit's item 10)

The corpus is not balanced: 214 positives against 68 negatives. A plain hit rate would reward a rater that fires on
everything, so `bench/skillrater/passk.py` also reports balanced accuracy, (hit rate on positives + quiet rate on
negatives) / 2. pass^2 counts the rows a rater gets right in BOTH runs.

| arm | model | hit@1 per run | negatives quiet per run | balanced per run | pass^2 positives | pass^2 negatives |
|---|---|---|---|---|---|---|
| before | Haiku | 208, 207 | 68, 68 | 0.986, 0.984 | 207/214 | 68/68 |
| final (shipped) | Haiku | 208, 208 | 68, 68 | 0.986, 0.986 | 207/214 | 68/68 |
| C2 (rejected) | Haiku | 206, 207 | 68, 68 | 0.981, 0.984 | 205/214 | 68/68 |
| before | Sonnet | 204, 208 | 68, 67 | 0.977, 0.979 | 204/214 | 67/68 |
| final (shipped) | Sonnet | 207, 206 | 68, 67 | 0.984, 0.974 | 204/214 | 67/68 |
| C2 (rejected) | Sonnet | 207, 207 | 66, 66 | 0.969, 0.969 | 206/214 | 66/68 |

The shipped text holds pass^2 exactly for both models.

**C2, the audit's description rules taken literally, was measured and rejected.** It removed every "you/your" (audit
d.1) and the nine cross-routing clauses such as "Code QUALITY → quality-bar" (d.2), for 4,970 characters against
5,277. Its rule was written down before any rating (`PREREG_C2.txt`), and it fails twice: Haiku's pass^2 drops 207 →
205, and Sonnet fires on 2 negatives in each run where the rule allows 1. Lexically it scores 142/214 against 147, and
removing the cross-routing clauses alone accounts for 5 of those rows. Its text is in `desc_c2_rejected.tsv`.

All of Sonnet's negative fires, in every arm, land on the same two prompts: "slow, nothing measured yet" questions,
routed to perf-target. C2 did not change perf-target's description, so the evidence against C2 is weak in either
direction. The rule still decided. The soft spot is perf-target's boundary for slowness nobody has measured. Both rows
are in the dev split, so they are fair to tune on. That belongs in its own round with its own rater runs, not in this
one.

The audit's "~6 KB" for the cross-routing clauses is overstated: the nine clauses come to about 300 B in all.

## Sizes (`bench/skillsize.py`; tokens = bytes/4, an estimate, not a tokenizer count)

| tier | when an agent pays it | before | after |
|---|---|---|---|
| descriptions (17) | every session | 5,461 B (~1,365 tok) | 5,339 B (~1,335 tok) |
| SKILL.md bodies (17) | when the skill triggers | 47,243 B (~11,811 tok) | 40,466 B (~10,117 tok) |
| reference files (47) | only when the body sends the agent there | 319,868 B | 323,655 B |

The reference files grew 3,787 B. That is the `Contents:` line now at the top of the 13 references over 100 lines,
which the guidance asks for, plus one corrected paragraph in `ripwire-navigate/blast-radius.md`. Nothing else in a
reference file changed.

`--legend=compact` is redundant on this binary: the CLI default is compact, and 10 verbs were measured byte-identical
with and without the flag. Dropping it from every command would save 729 B more in the bodies and 2,924 B in the
references. It stays, because `test/skilltruthcheck.sh` arm A1-2 enforces owner decision A1-2 (2026-09-12): every
skill command carries the flag wherever the binary accepts it. That is a question for the owner, not for this round.

Per skill: `size_before.txt`, `size_final.txt`.
