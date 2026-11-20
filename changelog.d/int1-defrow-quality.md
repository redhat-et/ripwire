### Changed — the def-row legend takes one posture struct, and the untied-match pass is its own function (lane INT1)

Two quality-delta findings the 0.6.11 batch carried into the 0.7.0 candidate, fixed rather than acked (owner ruling
2026-11-19). Both are shape changes: no output byte moves, and no caller outside this repo exists.

- `graphlegend.h defTableLegend` grew from 2 parameters to 4 in two steps — `sole` with the def-row landing
  (VERB-DEF-ROWS) and `rows`/`DefLegendFor` with `--uses`' own reading — so it gated api-surface 2 -> 4 over the
  branch range while being clean on either commit alone. It now takes one `DefTableLegendParts`, the
  `QualityDeltaLegendParts` shape: every field is a property of the answer whose `<def>` rows are introduced, three
  of the four are booleans, and an argument order a caller has to remember is the seam where a legend starts
  describing a table it is not attached to. The seven call sites spell the fields they mean.
- `defattrib.h defGroupsDropSilent` went complexity 14 -> 16 when BX1 FIX 7 turned its `ofMatch` range-`for` into an
  index loop and added the `UINT32_MAX` test that collects a dropped group's member. That one pass is now
  `defGroupsRenumberMatches`, because the function around it only needs the result.

Gates: unchanged and green — `attribmultidefcheck`, `verbdefrowscheck`, `verbfixcheck` ([F7] is the behaviour both
symbols implement), `mcpclidiffcheck` (the CLI/MCP dialects still agree byte for byte), `legendcoveragecheck` and
`capdisclosemapcheck`. A refactor that moves no output byte owes no new gate; the proof it moved none is those six.
