### Changed — `--impact` puts production callers and evidence-bearing importers in its first window

Two orders decided what `--impact`'s first 40-row window held, and both let a row that answers nothing push out one that
does. Symbol rows ran depth first, then PageRank: a test helper that many tests call out-ranked a production caller at the
same depth, so django `--impact=salted_hmac` listed depth-3 tests ahead of the two depth-3 production files a blast-radius
question needs, which sat past row 40. Within a depth, rows without `test="1"` now come first, then PageRank, as before. The
import tier (`<f>` rows) ranked an importer by path tier, then how many files import it. An importer the same answer also
has evidence for now goes first within its tier. Evidence means the file holds a reached symbol, a declined call that
`declined_calls=` counts, or a value binding of SYM. Example: envoy `--impact=chargeResponseStat` listed 40 of 141
importers, and `router.cc` and `ratelimit.cc` were past the cut.

Both changes only reorder rows. No row is dropped or added. Every count stays the same, including `reaches=`, `by_depth=`,
`importers=`, `shown_importers=`, `importers_capped=` and `importers_next=`. The `has_more=` / `next_offset=` windows are still
slices of one order. CLI XML, `--json`, `--format=columnar` and the MCP `impact` twin all print the same order. The full
legend and `--help` state the new order. `test/impactfirstwindowcheck.sh` is the gate.

Measured on the spent dev sets (T5d, T5e, held-out, T5c), with the shared grader:
- **Routed** `--for` → `--impact`, 20 cells: complete on window 1 stays 18 of 20, with 0 flips either way.
- **`--impact` asked directly** on the 62 blast-radius and change-risk cells: complete on window 1 stays 50 of 62, with 0 flips.
- **Gold groups that only the symbol and importer rows satisfy:** 60 → 62 routed and 181 → 189 direct, and no cell lost any.
- **Delivered bytes** are unchanged to within 0.2%.

What it does NOT mean: it does not raise the dev completion rate. Every dev answer still incomplete misses files that the
reach set does not hold at all: shell functions, macro expansions, header includers behind an umbrella header, and a few
unindexed definitions. No ordering can surface those.
