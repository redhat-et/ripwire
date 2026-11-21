### Changed — the body class gets its own, lower page-1 tail guarantee, and the floor that protects everything behind the tail

`promoteGuarded` (`src/foranswerfirst.h`) tested both of its promotion passes against one guarantee,
`kGuardTailRows` (24 tail rows). The guarantee — not the preceding change's cap — is what funds a body on page 1,
because it sets the headroom every promotion is measured against. It is now **two** constants: `kGuardTailRows` stays
at 24 for the `kPromotable` RES class, which keeps AF2's frozen pass 1 and its eligibility test unchanged on every
input, and the new `kGuardTailRowsBody` is 12 for the body class. A `<tail>` of 13 to 24 rows, which the previous
guard refused outright, is a body candidate from here on.

**Lowering the single constant instead was measured and rejected, and the reason is the bar rather than taste.** At one
constant of 12 the extra headroom reaches pass 1 as well: MEASURED on an 89-task orientation gold set, a `kPromotable`
section is promoted ahead of `<tail>` in four cells where the frozen rule promoted none, and in a fifth the newly
promoted RES section takes the headroom the `<fold>` had won, so a `<fold>` the previous page 1 delivered is deferred.
Seven of 89 cells fail the crowd-out prohibition that way, five of them on its pre-existing conjuncts. Splitting the
guarantee by class keeps pass 1 byte-identical to the parent by construction, and 0 of 89 cells fail.

`postResReach` is therefore generalised to `postPageOneFloors`, which returns the floor **per candidate** — only the
sections ahead of a candidate move when it is promoted — and owes two different things at two granularities: a RES
section keeps **every byte** page 1 delivered (the priority rule, unchanged), and **any** section keeps its page-1
**presence**, which is exactly what the answer's own `deferred=` reports. Reading presence as a section's START and RES
completeness as its END is what keeps the gain: where the previous page 1 already cut a `<fold>` mid-section, an
end-based floor over all sections would refuse the very promotion that delivers its body.

MEASURED on the same 89-task set, 11 repos, 11 languages, scored by the baseline lane's own grader on page 1 of the
shipped default call: gold-file naming unchanged in every cell and every repo (84 of 89), edit-function naming
unchanged (62 of 89), edit-function **bodies delivered on page 1 rising 18 to 21 cells**, **no cell falling on any
rung**, median page 1 unchanged at +0 per question with **1,593 B less page 1 in total across the 89**, and the
crowd-out prohibition passing **89 of 89 in its widest reading** — where the previous change failed it in two cells and
a single lowered constant fails it in seven. The enrichment section that the previous change pushed off page 1 in two
cells stays on it. The floor is CONSERVATIVE in one cell: at a single constant of 12 a 22nd body cell is delivered
whose promotion the floor refuses although the measured geometry admits it, so the bar is bought for one in-sample
cell.

The body guarantee's row offset is also read out of the tail **as it will be emitted** rather than out of the assembled
answer, where the tail still carries the comments rule A hoists into the document legend. The previous expression
corrected for those by subtracting every hoisted byte, which is exact only while they all precede the guaranteed row;
where they do not, it is a negative `std::size_t` and the floor wraps to an astronomical value, refusing every
promotion in silence. MEASURED, the wrap does not fire anywhere on the 89-task set — the arm with and without this
correction is byte-identical in all 89 cells — so this removes an arithmetic hazard and no observed defect, and
`-fsanitize=integer` has nothing left to find on that path. The RES class keeps the previous expression's value for
value, so its promotion set is unchanged by construction; only the wrap is replaced by an explicit refusal, which
decides the same thing.

`foranswerfirstcheck` pins it: (G10) widens the floor arm from the RES class to **every** section the previous page 1
delivered, which is also what stopped it being vacuous on its fixture, and reports the RES subset beside it; (G10n)
states the fixture's population for it in both directions, including that the arm has no contrast there; (G11) pins
both guarantees by value out of the source, so moving either default reddens a gate instead of being followed silently.
