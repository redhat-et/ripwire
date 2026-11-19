### Changed — `--for` puts the callers block first when the question asks who calls the subject

When a `--for` question asks who calls a named symbol ("Which functions call `X` directly?", "Who calls `X`?"), the answer's `<callers by="subject">` block is now the first row block of the answer-first document. Before, it came after `<sigs>`. Only the order changes: the answer has the same bytes and the same rows, and `test/foranswerfirstcheck.sh` (CL4) pins it as a permutation. A change, blast-radius or transitive question ("What breaks if I change `X`?", "… transitively") keeps the old order, because a one-hop callers block does not answer it first.

Measured once, on a held-out set of 43 questions this mechanism had never seen (a different population from the published compare table):
- Bytes until the whole answer had appeared: median 6,147 → 2,618, p90 14,764 → 12,809.
- Answers complete within the first 12 KB: 32 → 34.
- On the 16 who-calls questions alone: median 6,616 → 1,305.
- Completeness (39 of 43) and the cross-gold count are unchanged, and no answer flipped from complete to incomplete.

That run fired on 2 blast-radius questions it should have left alone ("What breaks if I change `X`? … defines or calls it"). The block's `of=` is qualified while the sentence spells only the leaf, so the change cue was read only on the whole name, and a pronoun "calls it" let the block lead. The change cue is now read on both spellings and vetoes on either (CL5, red before the fix). The fix can only stop the block from leading, never start it. On that set it reverts exactly those 2 questions and leaves the other 15 unchanged, a result read after the set was already used.
