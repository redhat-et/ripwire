### Fixed — three full-suite reds the pass-3 merges carried, and the format pin on the new posture struct (lane INT1)

The pass-3 candidate's first full-suite run found three reds that the lanes' own targeted runs never executed.

- `test/hashsetcheck.sh` (S): BX2's per-macro ceiling (`6f023ca5d`) declared `macroCeiling`'s `seen` as
  `HashMap<std::uint64_t, char>` and only ever asked `contains`. A membership table is a `HashSet<K>`, so it is one
  now (`seen.insert( key )`), which is also one fewer byte of value per entry on the hot row loop.
- `test/gateexitcheck.sh` (G2): AR1's new `test/subagentprimercheck.sh` reported 34 verdicts through the one-line
  `… && ok … || no …` spelling, where a failed write of the PASS line prints FAIL for an arm that passed. All 34 are
  now the suite's wrapped spelling, which G2 permits by design.
- `scripts/formatcheck.sh` gate mode: `src/graphlegend.h` is in the gated set — the files that match `.clang-format`
  byte for byte — and this lane's own `DefTableLegendParts` was written with aligned declarations and comments, which
  `.clang-format` does not produce. Reformatted with clang-format 22 (the pin); only that block moved.
