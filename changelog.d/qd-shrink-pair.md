### Changed — `--quality-delta`: a clone pair that crossed the bar only because one member shrank stops gating

**Shrink-only clone pairs (QD-SHRINK-PAIR).** A Type-3 pair's similarity is 2·LCS/(|a|+|b|), so it rises when either
member loses tokens the other does not share. Handing a body's sort and `erase( unique )` lines to a helper therefore
made it look more like its neighbour: on one development branch, `cFamilyMacroNames` fell from 135 to 99 tokens, its shared
LCS with `jsExportsOf` fell from 84 to 81, and the pair crossed 0.8. It printed as a gating duplication row and a gating
new-clone-of-reused-helper row about an edit that removed code and copied none.

Such a row is now reported `sev="minor"`, and no longer gates, when all of these hold:
- every member existed at the base;
- some member's body has fewer tokens now, and no member's body was cut to under half its base tokens;
- no pair's shared LCS grew.

The row says why: `why="pair crossed the bar because cFamilyMacroNames shrank 135->99 tok; shared code did not grow
(LCS 84->81)"`. A pair whose LCS grew still gates, even while a member shrank, because code was copied in. A member
cut to under half its body is a rewrite the rule cannot judge (a long base body holds most short ones as a subsequence,
so its base LCS says nothing), and it still gates. A group with
a member the base did not hold still gates, and so does one with an overload under a member's key, more than four
members, or a body the base commit could not be read for. The base bodies are read from git at the base commit for
the files of those rows only: the range form's base, or HEAD for the working-tree form, MCP `quality_delta` and the
`--quality-baseline` dirty-pin check. They are read with the same extraction and tokenizer the clone pass uses.
No snapshot or cache format changes. `--clones` does not read this verdict and is byte-identical.

The legend defines the new `why=` only when a row carries it, and the compact dictionary's `why` entry now covers it,
so its `dictv` moves. `test/shrinkpaircheck.sh` pins the rule with three positives (range, working tree, MCP), a
both-shrank positive, four counted negatives and a guard-off proof.
