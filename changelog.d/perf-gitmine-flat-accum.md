### Changed — flat table accumulator in `gitFileAuthors`

`gitFileAuthors` (`src/gitmine.h`) mines whole-repository git history to compute recency-weighted ownership (`--owners`, `--pr-context`, and MCP `owners`). It accumulated per-file commits into an outer `HashMap<std::uint32_t, ...>` keyed by `fileId`, then sorted the results by `fileId` to restore a deterministic order.

`fileId` is a dense `0..fileCount - 1` index from the ingested file table, so the whole-repo accumulator is now a flat vector indexed by it, with each file's author map built on first touch (files without mined history allocate nothing). A single-file query uses one map. Reducing in ascending `fileId` order leaves the result sorted, so the final `std::sort` is gone. Output is byte-identical.
