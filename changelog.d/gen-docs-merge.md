### Changed — open pull requests stop conflicting on generated totals

Every landing used to rewrite the totals in `README.md`, `docs/EVALS.md`, `docs/LIMITS.md`, `docs/TUNING.md`
and the showcase deck (the gate count, the cap inventory, the class counts, the TUNING census), so every other
open pull request that had added a gate or a cap went CONFLICTING and needed a main merge plus a full CI run.
Those totals are now a dated snapshot, `docs/counts.tsv`: the generators publish them from it, every site that
prints one carries its date ("counts snapshot YYYY-MM-DD"), and they rewrite only per-item lines (the absorb
list, the per-file cap tables, the per-cap sensitivity tables), which two pull requests touch on different
lines. `python3 docs/counts_snapshot.py show` prints the live numbers beside the snapshot, `check` compares them
and `refresh` re-takes the snapshot, all or nothing. How stale it can get is bounded: a refresh rides every train
pull request, `test/gendocsmergecheck.sh` goes red once the tree is more than 10 gates or 20 caps away from the
snapshot (`check --max-drift`), and the release workflow refuses a tag unless `check` is exact. A snapshot whose
totals do not add up is refused by every generator. Replayed with `git merge-tree` against the open pull requests
of 2026-11-03, each side cut after this change: #512 and #513 against each other conflicted on `docs/LIMITS.md`
and now merge clean; #505 against main keeps only its one-time absorb-list reshape; #506 keeps only the files a
build pins (`changelog.d/versions.md`, `docs/COMMANDS.md`, two showcase captures). Pull requests opened before
this change need one more main merge, which `scripts/merge_main.sh` settles on the total lines.

`scripts/merge_main.sh` marks main's newer showcase capture for re-recording even when it did not conflict, and
the new `scripts/merge_main.sh --regen-after-build BIN` settles the marks of every merge since its last run from
a build of the merged tree: it re-pins only the parity labels the two merged sides pinned differently (and refuses,
naming it, a label both sides agreed on that moved), re-records the newest capture's legend-dictionary `dictv=`
pair, regenerates `docs/COMMANDS.md`, and commits. A marked line where one side only re-ran a generator now takes
the other side's rewording, unless the rewording changed a hand-written figure, its sign or qualifier included
(`~210` to `210` stays a conflict). New gate `test/gendocsmergecheck.sh`; `test/mergemaincheck.sh` gains the
rewording, qualifier and re-pin arms.
