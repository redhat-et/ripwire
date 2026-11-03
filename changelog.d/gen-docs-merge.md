### Changed — open pull requests stop conflicting on generated totals

Every landing used to rewrite the totals in `README.md`, `docs/EVALS.md`, `docs/LIMITS.md`, `docs/TUNING.md`
and the showcase deck (the gate count, the cap inventory, the class counts, the TUNING census), so every other
open pull request that had added a gate or a cap went CONFLICTING and needed a main merge plus a full CI run.
Those totals are now a dated snapshot, `docs/counts.tsv`: the generators publish them from it and rewrite only
per-item lines (the absorb list, the per-file cap tables, the per-cap sensitivity tables), which two pull
requests touch on different lines. `python3 docs/counts_snapshot.py show` prints the live numbers beside the
snapshot, `check` compares them, and `refresh` re-takes the snapshot (a maintainer step at a release or in a
standalone change). Replayed with `git merge-tree` on the real refs: #512 against main conflicted on
`README.md`, `docs/LIMITS.md` and `docs/TUNING.md` and merges clean both ways; #505 keeps only its one-time
absorb-list reshape, and #509 only its `test/printf_parity.manifest` hash, which needs the merged build.

`scripts/merge_main.sh` marks main's newer showcase capture for re-recording even when it did not conflict, and
the new `scripts/merge_main.sh --regen-after-build BIN` re-records the marked files (the parity manifest, the
capture's legend-dictionary `dictv=` line, `docs/COMMANDS.md`) from a build of the merged tree and commits them.
A marked line where one side only re-ran a generator now takes the other side's rewording. New gate
`test/gendocsmergecheck.sh`; `test/mergemaincheck.sh` gains the rewording and re-record arms.
