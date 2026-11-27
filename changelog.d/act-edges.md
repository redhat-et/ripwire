### Changed — `--for` page 1 lists up to 8 act ranges and names the act symbols' callers, callees, tests and docs (`RIPWIRE_ACT_EDGES=0` turns it off)

The act line (`<act read=>`) used to list the top 3 ranked ranges. It now keeps those 3 first and adds the next ranged signature rows, up to 8 ranges in all, so an agent can Read them in one parallel turn. A range that an earlier one already covers is not listed again. The edit form's body ranges still follow the act ranges, and none is listed twice.

Right after the act line, page 1 carries two new lines:

- `<edges>` gives, for each of the first 3 act symbols, up to 2 callers (`called by P:L N`) and up to 2 callees (`calls P:L N`). They come from non-test files, callees from other files only and one per name. Exact-resolved edges come first, then distinct files, and callees with the fewest callers come first. `(+K)` counts the rest. A caller or callee whose line an act range already covers is left out.
- `<where>` names the files that go with the act files:
  - `tests=` lists the test files that call an act symbol, then the ones named after an act file.
  - `docs=` lists the docs that name an act symbol in backticks.
  - `changelog=` is the nearest changelog.
  - `build=` is the make, CMake, meson or Bazel file that lists the first test or an act file.
  - `tests_total=` and `docs_total=` give the full counts when a list is capped.
  - Each attribute appears only when something was found.

Both lines are defined on page 1 next to the act line's definition.

Paging counts the added bytes. They come off the bottom of page 1, not from the top rows. An answer that fits on one page without them stays on one page with them. MCP `for` carries the same lines. They are not in the legend dictionary, so `dictv=` is unchanged.

`RIPWIRE_ACT_EDGES=0` serves the answer from before this change byte for byte. `=1`, `=2` and `=4` turn on only the wide act line, `<edges>` or `<where>`, for A/B runs.

New gate: `test/actedgescheck.sh`, with fixture `test/actedgesfix`. `test/actlinecheck.sh` now pins the 3-range line with the lane off, and `test/corelegendcheck.sh` bounds the two new clauses separately.
