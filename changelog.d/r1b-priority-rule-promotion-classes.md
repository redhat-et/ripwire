### Changed — the answer-first page budget has an explicit priority order, so a body cannot displace a RES section

`promoteGuarded` (`src/foranswerfirst.h`) used to walk the sections after `</tail>` once, in emitter order, inside a
finite guard headroom, so a section won a promotion slot by its POSITION rather than its value. AF2's frozen
`kPromotable` is now the first of two classes and the body-bearing sections are the second (`kPromotableBody`:
`fold`, `bodies`): pass 1 promotes RES exactly as before, pass 2 gives the body sections only the headroom pass 1
left, and the promoted bodies are emitted behind the promoted RES sections so their byte offsets do not move.
Crowding-out is therefore removed by construction rather than by a threshold — there is no input for which a body
takes a RES section's slot — and when pass 1 exhausts the headroom nothing moves and the answer is unchanged.

Same guard, same stop (`kAnswerPageBytesDefault`), same emitter order within a class; tail rows 1..`kGuardTailRows`
never move. MEASURED on a fresh 89-task orientation gold set, 11 repos, 11 languages: gold-file naming on page 1
unchanged in every cell and every repo; edit-function naming +2 to +4 cells with none falling; edit-function bodies
delivered on page 1 rising 9 to 20 cells of 89; page 1 never grows by more than 679 B and the population sheds
481 B on page 1 and 2,145 B overall; byte-identical to the previous behaviour in 56 of 89 cells. `RES_ahead` and
`deferred=` are identical to the parent in 89 of 89 cells, against 3 cells where widening `kPromotable` itself
displaced `<lit>` and left `legendseencheck` red.

`foranswerfirstcheck` arms G3/G4/G5 pin that a body is promoted and that the guard still holds; its new G6/G6n/G7
arms pin that the RES section is still promoted and delivered, and that no RES section was displaced by a promotion
— G7 is red on a build that widens `kPromotable` instead. `forkeybodycheck` (K3) stays red: a promoted
`<bodies pick="name">` makes KB1 skip a body already served on the page, so its key group carries one named
definition instead of two. No body is lost from any answer; the key group's contract is a separate change.
