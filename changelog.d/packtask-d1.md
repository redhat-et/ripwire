### `--pack-task` is one bundle again: the `--for` head, the `--for` file tail, and ONE key body

`--pack-task` called the same ranker as `--for` and then threw most of its locating power away: a fixed
12-row window in raw score order, every row more than one hop from its six bodies demoted to a name-only
`<far>` row, and no file-grain tail at all. Measured on 52 tasks over this repo's own history, `--for`
page 1 named 148 of the 165 files those commits changed and `--pack-task` named 89 — and the budget had
cut no ranking row in any of the 52. It was a shape problem, not a budget problem.

The bundle now takes its locating surface from `--for`: the same 40-row head, in `--for`'s order, under
`--for`'s own lens rules (the relevance floor, `e=`, docs after code, the round robin by file), with rows
past the first ten re-spelled as pointer rows — name, place and the `--expand` selector's parts; and
`--for`'s file tail, filled last with everything the other sections leave and cut at a row boundary. The
six full bodies become ONE, the key body (the symbol the task names in backticks, else the top-ranked
one), and every other candidate rides as a `<b next="--expand=…"/>` pointer counted in `total=`.
`<callers>` is that body's own callers.

`est_tokens=` and `budget_tokens=` now use ONE conversion. The budget was converted to bytes at 2.36 B
per token while the result was priced at 2.50 and 3.80, so a bundle that had spent 91% of its bytes read
`est_tokens="3975"` against `budget_tokens="6000"` and looked a third unspent. Every delivered byte is
now priced at the rate the budget is converted at, and the legend says so and says which direction the
bound runs.

Gates: `test/packlocatecheck.sh` (the head's r=13..40 rows and the tail's files are named; the first 40
rows equal `--for`'s; the tail cut carries `capped="1"` and `next=`; the answer stays under the declared
ceiling) and `test/packkeybodycheck.sh` (exactly one body, KB1's choice, every dropped candidate a
pointer, the ledger's counts agree).
