### Added — a windowed answer says how to continue it cheaply

A cut listing that pages now says, in its own legend, that the continuation may be taken with
`--legend=dict`: the prose legend is ~26 % of the next page, and it is prose the reader already read
(measured at 3,255 B of a 12,281 B `--impact` page).

Taking a continuation prose-free is a median **13.2 %** smaller (57 windowed cells over `--impact`,
`--grep`, `--uses`, `--callers`; `--impact` 19.3 %, `--callers` 12.9 %, `--grep` 9.5 %, `--uses` 5.1 %)
and **drops no row** — `test/pagenextlegendcheck.sh` pins the continuation's row set byte-identical, so
completeness cannot regress through this path.

It is a statement rather than an automatic cut, deliberately. Dropping the prose whenever `offset>0`
would assume the reader holds page 0, and it may not: a reader can call `--offset=40` first, and a CLI
run is one process with no session. The entitlement here is in hand instead — the prose named as
droppable is prose that same answer just sent that same reader.

Cost disclosed rather than netted out: a constant **+130 B** on a windowed answer against a median
2,074 B saved per continuation followed, so it pays above a **6.3 %** follow rate. Whether readers follow
at that rate is not measured here.

Known gap, stated rather than hidden: the default (compact) posture carries it on every paging verb, but
`--legend=full` has no shared window clause, so there it reaches only verbs composing
`kPageRaiseCapClause`. An attribute would have covered both and was withdrawn — it would have needed
defining in 19 verb dialects, and `test/legendcoverage_baseline.txt` may only be edited downward.
Band: `docs/EVALS.md` amendment 14.
