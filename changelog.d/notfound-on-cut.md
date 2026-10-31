### Fixed — a "not found" from an index the memory guard cut no longer reads as proof of absence

When the memory guard stops a crawl or a parse, the MCP server keeps answering from the partial index. A result from that
index has always carried `_memory_stop`. A refusal did not: `find_symbol` on a name outside the kept files, and every other
not-found or error built after the first request, said only "symbol not found", which an agent reads as "the tree does not
define it". Every error from a cut index now ends with the same disclosure, prefixed with the one thing a not-found reader
needs: the index is partial, so an absence is unproven. It names the stop, the number of files the answer covers (and how many
of them were parsed) and the override (`--max-memory`, `RIPWIRE_MAX_MEMORY`, or a smaller root). The sentence is the same on every path: the first request that built the cut index (which is often an agent's
first call), a `batch` sub-query's `err=`, and the `edit_check` / `quality_delta` refusals. A `grep` payload from a cut index
no longer says `"complete":true`, since a hit may sit in the files that were never read. An error from a whole index,
including another root served by the same process, is unchanged. The CLI needed no change: every verb except the map already
refuses a cut index with exit 5.

The crawl also walks in a fixed order now (pre-order, each directory's entries by file name). It used to take the filesystem's
directory order, and the memory guard stops after N entries, so which files survived a cut depended on the filesystem: the same
tree under the same limit answered from different corpora on macOS and Linux (CI `memguardcheck` B6b). A walk that finishes
sees the same files in the same final order as before; only a cut walk changes, and it is now the same cut everywhere.

One visible side effect on trees past the report cap: where a repository holds more than 500 files of types ripwire does not
index, the off-index scan of `--grep` and the `--skipped` listing keep the first 500 of them, and "first" now means file-name
order instead of the filesystem's directory order. The indexed hits are unchanged; the off-index hits and the listed rows can
differ (measured on `textual`: `--grep=Widget` off-index hits 20 to 25), and the scanned count can now show
`unindexed_files_skipped=` for files in the new set that could not be read. The cap is still disclosed
(`unindexed_candidates_capped=1`).
