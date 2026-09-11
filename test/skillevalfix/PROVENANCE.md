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
