### Changed — `--pack-task` is sized by question class

`--pack-task` (and the MCP `explore`/`pack_task` bundle, the same assembler) used to fill its 6,000-token budget on every question: 12.2-12.5 KB, the cap binding in 8 of 8 cells of VERB-AUDIT-2. Three changes, all in `src/packtask.h`:

- **Every class: the ranking folds past rank 12.** `<sigs>` keeps its first 12 rows; the rows past them print as one `<t p= sym= r=/>` row per file the first 12 do not name (`sym=` that file's ranked names, `r=` its first rank). The tag says how many rows folded (`fold=N`) and `next=` is the `--for` call that prints every row. A plain cut of those rows looked free on the audit's 8 cells but lost 1 of 93 items on 18 more DEV cells (a caller file named only by a row past 12); the fold keeps every file named.
- **The name class** — a question that names one symbol the key body resolves and asks where it is, what it does or who calls it (one backtick span, at most 12 words, no path or wider route) — serves its ranking as path rows (`<d l= n= p= r=/>`, the fold without `sym=`) and its tail without `sym=`/`tsym=` (`p_only=` counts the rows). Bodies, callers and tests are served as before. The ledger says `class=name`, and the same call with any other `--token-budget` (12000, say) is the full bundle.
- **The conceptual class** — a question that names no symbol — spends the bytes the fold frees on more rows of its tail (the next files in the same order), so it keeps its size and names more files (vscode cell: 11 -> 19 tail rows). The ranking itself is `--for`'s lens ranking already; `--for` named more of the audit's gold files on these questions because its tail lists more files, which is where these items sit. On DEV the extra rows did not yet reach a gold file: before the `<partners>` block and the tail clause landed on main, the same change reached 24 rows and 13 of 20 items; now the gold files sit just past row 19.

Every other bundle (several names, a longer or path question, `--json`, a `--partition` slice) is the full bundle with the fold. The classes and the fold are the default budget's shape: an explicit `--token-budget=6000` is the default, byte for byte, and any other explicit budget is the previous release's bundle, unfolded. `RIPWIRE_PACK_CLASS=0` turns all three off; the answer is then byte-identical to the previous release's (checked on all 26 DEV cells).

Measured on DEV only (jq from the GA set; vscode, zed, cockroach, nushell, terraform and cpython from the large-dev set; gold from `rg`, never a ripwire run; the 8 VERB-AUDIT-2 cells plus 18 name cells frozen by sha256 before the first run). These are DEV numbers, not a sealed result, and DEV deltas have run 4-18x larger than the sealed ones:

| class | cells | bytes before -> after (mean) | items before -> after |
|---|---:|---:|---:|
| name (one named symbol) | 22 | 12,469 -> 9,030 | 93 -> 93 of 109 |
| conceptual (no named symbol) | 4 | 12,566 -> 12,580 | 11 -> 11 of 20 |

`test/packclasscheck.sh` holds it: the fold's disclosure and that no file is lost; an equivalence twin against `RIPWIRE_PACK_CLASS=0` (the 12 rows are the full head's first 12; a conceptual tail is the full bundle's rows and then more; a several-names bundle is byte-identical outside `<sigs>`); the name class's sections and path rows; a size bound, the `--token-budget=12000` escape and an explicit 6000 equal to the default; the classes that keep the full bundle; the off switch; and well-formed XML on every answer.
