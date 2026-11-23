### Changed — `--pack-task` is one bundle again: the `--for` head, the file tail, and ONE key body

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
one), and every other candidate rides as a `<bn … next="--expand=…"/>` pointer counted in `total=`.
`<callers>` is that body's own callers.

**The file tail takes its declared share as a FLOOR, not as the leftover.** The first build of this shape
gave the tail whatever the sections above it happened to leave, and on a corpus with a long task and long
signatures that was nothing: measured over LocBench's 303 tasks, the tail declared a 20% share of the
shaping budget and received 0.6% — a median `shown="0"` of `total="512"` files — and on 82 of the 84 tasks
whose bundle did not name every file the question needed, the file it needed was in that cut tail.
Completion is counted in files and the tail is the section that names files. Its share is now reserved
before the cascade spends and handed back on top of whatever the sections above leave, so the tail still
grows into their slack but can no longer be starved by it. Over 596 tasks on four sets, that moves the
bundles that name every file the question needs from 329 to 420; LocBench alone goes from 219 to 224 of
303. The budget did not change: the finding above was that this is a shape problem, and raising the budget
would have been the wrong fix.

**`<bodies capped=>` now admits a body it cut.** The attribute read only "fewer bodies served than handed
in" and ignored `truncated="1"` on the one body it serves, so a bundle whose body was cut at the byte
budget published `capped="0"` over it: 194 of 596 measured answers said nothing was cut while a `<b
truncated="1">` row sat inside them. `capped="1"` now also rides a served body that was truncated, which is
the reading `<tail>`, `<calls>` and every other truncating element already spell.

**`--pack-task --token-budget=6000` now serves what the default serves.** The default budget IS 6,000
tokens, but the explicit form passed its own number into the head's lens rules while the default passed
none, and one of those rules is off at 6,000 — so the two answers to the same question differed by a whole
section's reading (`files_first=`). The head now takes the lens's own verdicts in both paths.

`est_tokens=` and `budget_tokens=` now use ONE conversion. The budget was converted to bytes at 2.36 B
per token while the result was priced at 2.50 and 3.80, so a bundle that had spent 91% of its bytes read
`est_tokens="3975"` against `budget_tokens="6000"` and looked a third unspent. Every delivered byte is
now priced at the rate the budget is converted at, and the legend says so and says which direction the
bound runs.

Gates: `test/packtailsharecheck.sh` (the tail's share is a floor: a 1,200-char task at the default budget still serves it, its bytes reach the floor the share implies, the share is read out of `src/packtask.h` so the gate and the cascade cannot drift apart, the row count is monotone in the budget, and a `--partition` slice reserves nothing — with an arm that asserts a pre-fix binary IS red on the same fixture), `test/packlocatecheck.sh` (the head's r=13..40 rows and the tail's files are named; the first 40
rows equal `--for`'s; the tail cut carries `capped="1"` and `next=`; the answer stays under the declared
ceiling) and `test/packkeybodycheck.sh` (exactly one body, the key-body choice, every dropped candidate a
pointer, the ledger's counts agree).
