### Fixed — a `--for` budget only trims the answer; it no longer switches it to a different answer

`--for --token-budget=N` used to choose a different answer as soon as any budget was given, even one far larger than the answer. In the 0.7.0 comparison rehearsal, all 21 questions whose unbudgeted answer was under 16,000 tokens came back smaller and different at `--token-budget=16000`. On koa-02 the answer went from 24,446 B to 10,834 B, although the full answer cost only 5,494 tokens. In the other direction, `--detail=3 --max-tokens=16000` returned 1.14× the unbudgeted size.

The answer is now chosen as if no budget were given, and the budget is applied afterwards as a ceiling:

- When the answer fits, it is returned byte for byte, with no budget attribute added.
- When something is removed, the root names `budget_tokens=N` (or `max_tokens=N` for `--detail=N`) and the legend says what each removal means.
- When the answer does not fit, parts are removed in a fixed order until it fits: the optional attributes on `<sigs>` rows, the last `<tail>` rows, the `<fold>` bodies, the last `--detail` bodies, and finally the last `<sigs>` rows. The first four rows are always kept, and each ranked row removed is counted in `dropped_positive=`. `shed=` on the root lists what was removed, and the `next=` on a cut block is the same call without the budget.
- A larger budget never returns less. Every row kept is a row of the full answer, in the same order.
- When the rows are already at their floor and the answer is still too big, `est_tokens` is higher than the budget on the root. A `--max-tokens` ceiling also adds `over_ceiling="1"`.

The `--json` dialect and the `--limit`/`--offset` page keep their row target. `test/budgetmonotonecheck.sh` holds the contract on two fixtures and this repository's `src/`.
