### Fixed — `--deps` stops calling every deep graph `tangled`

`<health shape=>` was read off `nccd` alone, and `nccd` passes 2 on any graph whose average file reaches a few hundred
others, cycle or not: with true include edges injected, Envoy's verdict went from `horizontal` (`nccd="0.09"`) to `tangled`
(`nccd="16.37"`) while it had three cycles of 2, 3 and 6 files among 7,786 measured files. `tangled` now means what it
says: at least 1 in 20 of `dep_files=` sits inside an include cycle, and the number behind it rides beside it as
`cyclic_files=` (absent at 0). Otherwise `nccd` says how deep: `horizontal` below 1, `vertical` from 1. That Envoy graph now
reads `vertical cyclic_files="11"`; cpython (314 of 3,544 files in cycles) and vscode (1,277 of 15,574) stay `tangled`. A
cycle list longer than its 20 rows now says so: `<cycles total= shown= capped="1">`. The 1-in-20 line is a heuristic, like
the `nccd` one it replaces.
