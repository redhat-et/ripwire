### Changed — `--quality-delta`: a short clone row over different data stops gating; a repeated decision is named on its complexity row

**Clone rows over different data (QD-IDIOM-ELEMTYPE).** Some clone groups are under 80 tokens, sit in distinct
contexts and were not already demoted as a recognized idiom. Such a group is now reported `sev="minor"`, and no
longer gates, when every pair of members operates on different data. "Different data" means one of two things.
The members share no literal: 0 and 1 are left out, and `true`, `nullptr`, `None` and the like count. Or the members
take the same number of concrete parameters, with a different type at some position. The row says which with
`why="different literals"`, `why="different parameter types"` or `why="different literals or parameter types"`.
A template or generic member, an untyped parameter, or a shared literal keeps the group gating, as before. So does a
recognized idiom whose members share a domain value, such as a ladder over the same `Grade::Poor` … with tuned
thresholds, a pair sharing a named constant, or a pair calling the same helper. A function passed by value, like
`svLess`, does not count. Two bodies that both pass their literal straight to a call keep gating too, because that
is one function with the literal as a parameter (`rfind( '/' )` beside `rfind( "::" )`, the `afterLast` family).
`--clones` does not read this verdict and is byte-identical.

Measured on ripwire's own history, gating rows fell from 13 to 3 on the 13 acknowledged VA-FORMS rows. The 3 that
still gate do so by design: one is past the 80-token ceiling, and two members share the literal `0x80`. Other ranges:
- 41 to 36 on 40 tmux commits;
- no change on the qd-tangle range, the last 20 merges, the slip commits, textual or 20 other tmux commits;
- 1,863 to 1,327 on a synthetic envoy range that adds two whole subtrees.

The real duplicates still gate (`writeTangleLines`/`writeHexPairLines`, `steer_find`/`JsonNode::get`). Hand-reading
24 envoy demotions found 21 idiom collisions over different data and 3 borderline rows, among them the identical
"all matchers match" loop over two element types. None was a verbatim copy. `test/cloneoperandcheck.sh` pins the
path: three positives, six counted negatives and a guard-off proof.

**A repeated decision (QD-REPEATED-DECISION).** A function may test the same condition twice: the same 6 or more
tokens, verbatim, in an `if`/`while`/`elif` or a `( … ) ?` ternary. Or it may repeat a loop body: 12 or more tokens
identical. Its complexity or tangle row now carries `fix="name the decision once: <condition> is tested at lines A and
B"` or `fix="name the loop once: the loop body at line A repeats at line B"`. This is a facet. It never makes a row,
and it never changes a severity or gating. In Python a keyword counts only when it starts its line, so comprehensions
and conditional expressions are not read as statements. Ruby, Lua, Elixir and shell are not read.

On ripwire's last 20 merges 14 rows gained the fix, among them `chooseInWindow`'s copied pass loop. Three of the 42
distinct fix= rows across the ripwire, tmux and textual ranges re-test a fact that changes in between:
`memguard::overHardLimit()`, `!qsnapGet(…)` and tmux `event_initialized`. For those, deciding once is the wrong advice.
`test/repeateddecisioncheck.sh` pins it with two positives and five counted negatives.

The legend defines `why=` on a clone row and the new fix= text only when a row carries them. The compact dictionary's
`why` entry now also covers the clone row, so its `dictv` moves.
