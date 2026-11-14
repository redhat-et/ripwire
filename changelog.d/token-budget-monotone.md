### Fixed — a `--for` budget only trims the answer; it no longer switches it to a different answer

`--for --token-budget=N` used to choose a different answer as soon as any budget was given, even one far larger than the answer. In the 0.7.0 comparison rehearsal, all 21 questions whose unbudgeted answer was under 16,000 tokens came back smaller and different at `--token-budget=16000`. On koa-02 the answer went from 24,446 B to 10,834 B, although the full answer cost only 5,494 tokens. In the other direction, `--detail=3 --max-tokens=16000` returned 1.14× the unbudgeted size.

The answer is now chosen as if no budget were given, and the budget is applied afterwards as a ceiling:

- When the answer fits, it is returned byte for byte, with no budget attribute added.
- When something is removed, the root names `budget_tokens=N` (or `max_tokens=N` for `--detail=N`) and the legend says what each removal means.
- The blocks printed outside `est_tokens` (`<syms>`, `<doc_body>`, `<decl_rows>` and the like) count toward the budget too. When the answer and those blocks do not fit, the blocks are held first: each prints its `held="budget"` stub with a `next=`, and `<doc_body>` gets only the room the answer leaves.
- After that, parts are removed in a fixed order until the answer fits: the optional attributes on `<sigs>` rows, the last `<tail>` rows, the last `<hops>` rows, the `<fold>` bodies, the last `<bodies>` bodies, the `<doc>` of the lowest-ranked `<sigs>` rows (`docs:N`), and finally the lowest-ranked `<sigs>` rows. Ranks 1 to 4 are always kept, and each ranked row removed is counted in `dropped_positive=`. `shed=` on the root lists what was removed, and the `next=` on a cut block is the same call without the budget.
- `--max-tokens` never removes a ranked `<sigs>` row. When the rest is gone and the answer is still over the ceiling, the root says `over_ceiling="1"`.
- A larger budget never returns less. Every row kept is a row of the full answer, in the same order.
- When the rows are already at their floor and the answer is still too big, `est_tokens` is higher than the budget on the root.

`--signatures-only`, the `--json` dialect and the `--limit`/`--offset` page keep their row target. `test/budgetmonotonecheck.sh` holds the contract on two fixtures and this repository's `src/`.
