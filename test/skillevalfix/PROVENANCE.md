# test/skillevalfix — provenance and seal

`prompts.tsv` is the labelled skill-routing corpus scored by `ripwire skills --eval-skills=…`
(`src/skilleval.h`); its header documents the row format, the provenance classes, the frozen
`split=test` half and the RELABEL log. The header's opening prose still quotes the n=128 / 43-judged
sizes of the 2026-07-25 freeze; the pinned sizes today are 266 rows, split=test 183 (85 of them
judged), split=dev 83 — `test/skillevalsplitcheck.sh` enforces them.

## Seal

Recorded 2026-09-07 for the "Skill descriptions under a client budget" registration in
`docs/EVALS.md`; the held-out set of that round is split=test ∩ (judged | neg), n = 85 + 53.

    Seal: sha256(prompts.tsv) = 16b1c84724a15d41717c588663db36c8569bd7b753701732cf5566560e798b7d

A row added, edited or relabeled after this line changes the digest; a round that measures against
the sealed set states the digest it measured against.

## Seal after the 2026-09-07 relabel (efficient → orient, 12 rows, mechanical map; RELABEL log in the header)

    Seal: sha256(prompts.tsv) = 9262a1b6d87a0ea8c39d5a165217a8f72ac46ff728923aa9a9f38241b8c5ee35

Rows 266, split=test 183 (85 judged), split=dev 83 — unchanged; only the 12 labels moved. The
description-budget round's held-out measurement was taken against the previous seal (16b1c847…); the
folded arm (C2) was scored against a derived copy carrying exactly this map.

## Seal after the 2026-09-10 stop-rule round (lane/helptask-precision; +16 rows, all split=dev)

    Seal: sha256(prompts.tsv) = 74953fd1a5e494f2805cb9c51cc828d59a4bf1f2c24912a069e1acdd2fa2a8ba

Rows 266 → 282; split=test 183 (85 judged) **unchanged — the freeze holds**, split=dev 83 → 99.
The 16 new rows sit between the `STOP-RULE ROWS (2026-09-10)` markers and exist to measure the four
frontmatter STOP RULES #112 restored, which no row in this corpus could previously see (2026-09-10
audit F-R1-03: deleting all four left split=test bm25-desc hit@1 byte-identical and split=dev 1.4pp
BETTER, with `skillevalcheck` 15/15 green either way).

- **8 rows, `provenance=desc`** — the audit's own stop-rule prompts, ASCII-transliterated (em dash →
  hyphen) per this file's ASCII rule and otherwise verbatim. They are `desc`, not `judged`: they echo
  the rules' wording, which is exactly what `desc` means here, and the honesty matters because that
  echo is where all of the discrimination lives.
- **8 rows, `provenance=judged`** — written for this round to AVOID the rules' wording. **Measured at
  exactly zero discrimination: bm25-desc 50.0% with the four rules and 50.0% without** (n=8, same
  binary, same rows). A BM25 arm scores description TEXT, so it can only detect a sentence's removal
  through rows that share that sentence's words; "phrase it without quoting the rule" is not available
  to this instrument. The rows are kept as ordinary hard judged rows and as the record of that null.
- `split=dev` for all 16, by the corpus header's own rule: the test split is FROZEN and new rows
  belong in dev. `test/skillevalsplitcheck.sh` confirms split=test bm25-desc hit@1 is unchanged at
  63.8%.

**Measured (bm25-desc hit@1, same binary):** the 16 rows alone 75.0% with the rules vs 50.0% without;
the whole corpus split=dev 76.2% vs 72.6% (3.6pp — the corpus can now see them at all); split=test
63.8% vs 63.8% (unchanged, as the freeze requires). `test/skillevalcheck.sh`'s new stop-rule arm
scores both trees itself and is RED on six arms against a stripped copy.

**Floors were NOT moved this round** (a floor move is a deliberate recalibration commit, not a
side-effect). Slack as measured now: test hit@1 63.8% vs floor 52.0 (**+11.8pp**), test sep-auc 0.901
vs 0.83 (+0.071), dev hit@1 76.2% vs floor 59.0 (**+17.2pp**), dev sep-auc 0.926 vs 0.75 (**+0.176**).
The dev pair remains outside the file's own stated policy (~10pp / ~0.06–0.07) and is left as a named
decision for the owner.
