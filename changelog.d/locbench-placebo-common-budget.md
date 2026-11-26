### Fixed — LocBench control arms build on real rows: one common budget B* for every arm

The matched-budget control arms closed to the exact byte budget with one trim try. On real LocBench rows (long attribute heads, 16–95-char signatures) that failed often: for-matched on 9 of 24 pilot train instances and lexical on 17. Every derived arm is now built at B*, the largest size at or below the requested budget where all four close exactly. All four are always built, and each instance discloses `requested_bytes` and `budget_shortfall`. The rule is in `bench/locbench/PREREG_PLACEBO.md`'s ADDENDUM (2026-11-26, before any model episode). `test/locbenchplacebocheck.sh` gains a short-signature fixture that is red on the old builder.

Rule A2 (owner ruling): an instance whose control arms cannot be built at all is excluded from every arm, before the gold-based scoring, and listed by id in the run JSON (`excluded_unbuildable_a2`). The run no longer aborts on such an instance.
