### Fixed — `--situ` says how many commits its co-change section left out as bulk

`--situ`'s section [3] mines co-change from the last 18 months of commits, and a commit that touched more than 30 indexed files is left out so that a mass rename or a vendored-tree drop does not couple every file to every other. Nothing said so. `commits=` counted only the commits that were kept, and a window whose every commit was over the cut printed "no git history reached it", which is false: the history was there, and the cut took all of it.

The [3] header now carries `bulk_skipped="N"` when the cut removed N commits, and the MCP `situational_awareness` twin carries `"cochange_bulk_skipped":N`. Both are absent when nothing was cut, so a report without a bulk commit is byte-identical. When the cut removed every commit, the empty line names the cut instead of missing history. `--pack-task`'s `<partners>` block uses the same spelling for the same cut (#786). `gitCommitFileSets` takes an optional `CommitWindowCensus`, which the commit-count miner already took.

`--handoff` reads the same facts and does not show the count yet. Its `<heuristic>` element would need a new legend-registered attribute.

Gate: `test/situbulkcheck.sh`, on three generated repositories: a 31-file commit beside a 30-file one (only the 31-file one is cut), a window that is all bulk, and a window with no bulk commit.
