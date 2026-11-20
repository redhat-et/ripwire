### Changed — a definition body is capped at 120 lines, and the key block carries five

A candidate's definition body now rides whole up to 120 lines of its indexed span and as its first 120 lines
beyond that — `min(span, 120)`, monotone, with no discontinuity. The cut states its cause: `cap_lines=` rides
beside the existing `truncated=`/`lines=`/`next=`, because `truncated=` is registered as "cut at the byte
budget" and a line cap is a different fact. The three surfaces whose unit is a candidate's definition body
take the cap — `<bodies of="key">`, `<bodies pick="name|member">` and `--pack-task`'s. The route, hops and
launch groups do not: their unit is a path through several definitions, and they move no byte.

The monotone shape was chosen over the cheaper "whole under 120, else a 15-line head". That form saves more
— measured, −42.3% of candidate body lines against −21.7% — but an answer whose size jumps eightfold on a
property the caller cannot see is the wrong trade, and it is worst where several agents each budget alone.

The key-body block now carries five bodies rather than two. Five is the p90 of gold functions per task over
an 89-task orientation set whose median is one; a cap of two could satisfy 71.9% of those tasks and five
satisfies 94.4%. The byte budget, not the count, is what bounds the block.

**This is a blow-up guard, not a token saving, and the measurements say so.** On the only stratum where the
cap can act — 25 tasks whose largest gold body exceeds 120 lines, 49 gold functions — it fired on 4 of 25
`--pack-task` answers, left edit-covering completions unchanged at 5, and moved median answer bytes by zero.
Whole bodies cover every gold body by construction, so a cap can only subtract at that rung; what it buys is
a bound on the one place a whole large function could ride unbounded.
