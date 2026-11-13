### Changed — `--quality-delta`: a new function at the ceiling (4x the bar) now gates; constructors and moved bodies stop reading as new debt

Until now a new function never made `--quality-delta` exit 2, however large it was. A NEW complexity or verbosity row in non-test code now gates once it reaches 4 times the bar (ccx 60, or 240 code lines; `kNewSymbolCeilingMul`), and the row carries `ceiling="60"` or `ceiling="240"` (`"ceiling":N` in `--json` and over MCP). Test drivers (any path `isTestPath` reads as test code) still only report. New-symbol rows otherwise still never gate: "new-symbol rows never gate, except defect-shape format-arity and a new function at the ceiling".

Two fixes come first. Without them, rows at that size were noise:

- A C++ constructor no longer carries its class's extent. `class TextPool` and `TextPool::TextPool` share one canonical id, and the per-id maximum gave the constructor's verbosity row the whole class (129 and 149 lines on two recent merges). Where a function or method shares the id, the container measures 0 there. `--metrics` is unchanged.
- A new function whose body (scrubbed of whitespace and its own name) matches a baseline body whose symbol is gone is a move. It prints `origin="moved"`, still counts in `new-symbol=`, and never gates. A body that was copied while the original stayed is not a move. The dead-code row of a moved symbol still reads `origin="new-symbol"`.

`test/qdentryceilingcheck.sh` pins a 250-line function and a ccx-61 function that gate; ccx-59 and 239-line functions, a moved body, a constructor and a test driver that do not; the copy that still gates; `--json`; and all three legends. Each negative arm counts its premise and fails on zero.

Versions: `kQSnapCacheScheme` 26 -> 28 (a cached snapshot is recomputed once). The session legend dictionary moves to `dictv=861ee5ed76b15f66 entries=1066`, and docs/COMMANDS.md and the showcase capture are re-recorded.
