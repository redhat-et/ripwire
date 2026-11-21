### Fixed — the MCP `for` budget gate reads the next rank past a cut, not the next printed row

`mcpforparitycheck` arm (5) checks that a soft `budget_tokens` cut is maximal: the next unit past the cut must not fit. Under a
soft target the demote rules run after the ladder has cut the rows, so a rank past answer row 10 can ship as a `<t r=>` pointer,
and the reference the arm priced the next row from printed those ranks as pointers too. The arm skipped them and compared a later,
smaller row: on this repository's own `src/` at `budget_tokens=1600` it compared rank 15 (120 B) where the ladder's next unit is
rank 13, a 367 B row that first fits at `budget_tokens=1621`. It failed on every binary on the merged tree and passed on each
lane's own tree. The arm now takes the lowest rank served neither as a row nor as a pointer and prices it as a row without its
doc, from a reference read with the demote rules off. No product output changes. A mutant that under-fills the MCP refill by 200 B
turns the arm red at `budget_tokens=2000`.
