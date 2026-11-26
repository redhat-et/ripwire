### Changed — `--for` page 1 lists up to 8 act ranges (`RIPWIRE_ACT_EDGES=0` turns it off)

The act line (`<act read=>`) used to list the top 3 ranked ranges. It now keeps those 3 first and adds the next ranged signature rows, up to 8 ranges in all, so an agent can Read them in one parallel turn. A range that an earlier one already covers is not listed again. The edit form's body ranges still follow the act ranges, and none is listed twice.

Paging counts the added ranges. They come off the bottom of page 1, not from the top rows. An answer that fits on one page without them stays on one page with them. MCP `for` carries the same line. The wide clause is not in the legend dictionary, so `dictv=` is unchanged.

`RIPWIRE_ACT_EDGES=0` serves the answer from before this change byte for byte.

New gate: `test/actedgescheck.sh`. `test/actlinecheck.sh` now pins the 3-range line with the lane off.
