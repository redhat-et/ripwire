### Changed — an over-budget `--for` page sheds optional row attributes instead of missing the budget (#520)

When a `--for --token-budget=N --limit=…` page still exceeds `N` at its one-row floor, the row drops `cx=`, `ccx=`, `layer=` and its own `next=`, then `sc=` if needed, and the root says `attrs_shed="1"` (defined in the page's legend). The row and what names the answer (`n=`, `p=`, `l=`, `r=`, the signature) always ship; a page that already fits is byte-identical.
