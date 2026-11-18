### Changed — flat table accumulator and zero-allocation commit parsing in `gitFileAuthors`

`gitFileAuthors` (`src/gitmine.h`) parses whole-repository git history to compute recency-weighted ownership (`--owners`, `--pr-context`, and MCP `owners`). Previously, it accumulated per-file commits into an outer `HashMap<std::uint32_t, ...>` and parsed commit header timestamps via heap-allocated `std::string tsStr` and `std::strtoll`, before sorting results by `fileId` at the end to restore determinism.

Since `fileId` is a dense `0..fileCount - 1` integer produced by the ingested file table, `perFile` and `newestTsByFile` now use flat vectors indexed directly by `fileId`. Header parsing replaces per-commit heap allocations with zero-allocation `std::from_chars` and buffer assignment `curEmail.assign(...)`. Because vector reduction visits files in strictly ascending `fileId` order, the final `std::sort` by `fileId` is eliminated entirely. Output remains 100% byte-identical.
