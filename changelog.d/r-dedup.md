### Changed — a `--for` tail row no longer repeats the names its file's ranked rows or the `<syms>` block already show

A `<tail>` page row for a file whose symbols the answer already prints as ranked `<d>` rows used to list those same names again in `sym=`, so the row named nothing new. Its `sym=` now skips the names a shown row of that file carries and fills its three slots from the file's next positive-score symbols in the same lens order, each name once (the repeated-name rule the other tail rows already follow). The row count stays the same, and `sym=` never holds more names than before. A file whose positive-score names are all shown prints `p=` only.

The `<syms>` lead block keeps priority over those rows: it reads the answer as if their `sym=` names were not printed, and a name it prints is then cut from them, so the block's leads (with their `file:line` and qualified name) are the ones that survive and no name is printed twice. Both tail legend clauses say so: `sym=` is the file's top symbols minus names a sigs row or the syms block shows.

On the 321 in-sample `--for` calls this names the missing in-file symbol on mf2-pydantic-08 and nfpm-11 without losing a graded item. `test/deeptailcheck.sh` arms (1d) and (1s) pin the refill and the `<syms>` cut, each with a positive twin.

The tail legend clause change moves the session legend dictionary to `dictv=720b939e8b412eb8 entries=1050` (docs/COMMANDS.md and the showcase capture are re-recorded).
