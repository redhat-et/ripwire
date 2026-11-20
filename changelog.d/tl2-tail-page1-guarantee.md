### Changed — a tail that fits page 1 no longer blocks a body from reaching it

`promoteGuarded` (`src/foranswerfirst.h`) asked two questions before promoting anything: has the `<tail>` more than
`kGuardTailRows` rows, and does `</tail>` itself end past the page stop. The second is a precondition on the tail's own
SIZE rather than a guard, and it made a tail that FITS page 1 untouchable: the `<fold>` behind such a tail was never
promoted, so page 1 ended on file-grain pointer rows while the body the question asked about began after the cut. The
tail's page-1 presence is now read as a GUARANTEE of its first `kGuardTailRows` rows and only those — the rows past it
carry no rank at all (MEASURED: 0 of 88 page-1 tails on an 89-task orientation set carries a single `r=` row) — so the
size precondition scopes PASS 1 ALONE and the body class may be funded from the unguaranteed rows either way.

Nothing is removed: the tail keeps every row, in order, so this is the same permutation `foranswerfirstcheck` (R1)/(R4)
pin and not a tail cut. When `</tail>` ends past the stop the answer is the previous behaviour byte for byte. On the new
branch the RES class never moves — pass 1 does not run there, and the body's fit test is floored by `postResReach`, the
furthest byte a `kPromotable` section behind `</tail>` already reaches inside the stop, so a RES section page 1 delivers
keeps its place. MEASURED on an 89-task orientation gold set, 11 repos, 11 languages, scored by the baseline lane's own
grader: gold-file naming on page 1 unchanged in every cell and every repo (84 of 89), edit-function naming unchanged
(62 of 89), edit-function bodies delivered on page 1 18 to 19 cells, median page 1 unchanged at 16,354 B with no cell
growing by more than 961 B; the answer is byte-identical in 85 of 89 cells, and `RES_ahead`/`deferred=` are identical to
the parent for every RES section the previous page 1 delivered.

`foranswerfirstcheck`'s new G8/G9/G10 arms pin it: (G8) a body section ahead of `<tail>` on a tail that fits, red on the
previous binary; (G9) the delivered page still carries a body and its first 24 tail rows; (G10) no `kPromotable` section
the previous page 1 delivered is deferred by the promotion. (G8n) asserts the fixture's population in both directions,
and the fixture is a subtree because on the repo itself every tail overflows the stop — 0 of 15 task strings qualify.
