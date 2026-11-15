### Changed — lexical scans read every file, and a reached limit is printed to stderr

`--whereis`, `--stray-content` and `--grep` no longer skip large files. `--whereis` and `--stray-content` used to drop any blob
over 2 MiB unread. `--grep` used to leave the crawl's oversize files (`corpus_oversize=`) unsearched while it still claimed
`complete="1"`. These scans now read a file of any size in line-aligned 2 MiB pieces, so memory stays bounded. `--grep` claims
`complete="1"` only when every such file was read whole.

The branch sweeps past 512 local branches got cheaper. Merge bases now come from one history walk, and the diffs come from
batched `git diff-tree --stdin` runs instead of one git process per branch. On a one-file repository with 602 branches,
`--stray-content` went from 86 s to 2 s, `--abi` from 125 s to 2 s, and `--plan` from 10-15 min to 8 s; at 4,096 branches of that
repository each verb finishes in about 11 s or less. `--whereis` now sizes its branch window by work, about 2 million tree entries in total
(at least 16 refs), so a 602-branch clone of a tree of about 20,000 entries reads 101 refs. `--plan` scouts at most 8,192 indexed
files across its arms. `--detail=1` lifts every window.

Whenever a window or budget cuts an answer, ripwire prints one line to stderr. The line names what was cut, the limit and the
flag that raises it. At most five such lines print per run, then a single line says that further warnings are collapsed. The
answer itself still carries `refs_omitted=` for agents and never contains the warning text.

`--for` "unused functions in A/ and B/" now prints `<unused_cut>` when the table shows fewer files than the named directories
hold together.

The changed compact readings (`corpus_oversize`, `unindexed_files_skipped`, `refs_omitted`) move the session legend dictionary to `dictv=6991d798e7147363 entries=1116` (docs/COMMANDS.md and the showcase capture carry the pair).
