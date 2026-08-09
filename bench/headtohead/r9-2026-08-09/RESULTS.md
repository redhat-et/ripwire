# r9 — oracle-scored reference-precision round (2026-08-09)

The receipt for the README's silent-miss claim, and the round that produced the r9 fix list.

Both tools were scored against a **third-party oracle**, never against each other: a `scip-clang`
v0.4.0 compiler-grade index of this repository. The comparison arm is
[Serena](https://github.com/oraios/serena) 1.6.2.dev0 (its own bundled clangd 19.1.2) — an
LSP-backed tool, included to put a number on the standing objection *"but a compiler-grade index is
correct."* C++ only: the TypeScript corpus of the original sweep was lost to scratchpad garbage
collection and is not reproducible, so no TS claim is made here.

Queries were authored **blind** — written against the source before either tool ran — and the query
file, oracle and scoring definitions were frozen for the whole round and every subsequent replay.
Full manifests, per-query scores and the four re-score rounds live in session scratchpad `a4ba88d1…`.

## Honesty calibration — the number the README cites

An imperfect answer that *says* it is imperfect costs a source read. An imperfect answer that stays
silent costs a bug. This measures which kind this tool produces, across 68 answers (34 queries ×
`--uses` and `--callers`).

| | pre-fix binary | shipping binary (post-fix) |
|---|---|---|
| imperfect answers | 9 | **6** |
| …carrying a discriminating self-flag (`amb=`, `defs>1`, `external="1"`) | 7 | **4** |
| …unflagged | 2 | **2** |
| **true silent misses** | **0** | **0** |
| over-hedging (correct answers carrying a flag anyway) | 11/59 = 18.6% | **14/62 = 22.6%** |

**The two unflagged answers are not misses.** Both are oracle-scope artifacts: a Python file under
`bench/` and an uncompiled file under `test/`, neither visible to a C++ compilation database. The
oracle could not see them; ripwire's answer was the correct one. They are recorded here so nobody
re-litigates them, and they are counted against us in the table above rather than quietly excluded.

**Over-hedging rose across the fix round** (18.6% → 22.6%). Closing loss buckets added self-flags
faster than it removed imperfect answers. That direction is deliberate: the machinery is calibrated
to warn too often rather than too rarely.

## Head-to-head, for context

| Measure | ripwire (pre-fix → shipping) | Serena |
|---|---|---|
| site-level P/R (`--uses` vs `find_referencing_symbols`) | 0.905/0.929 → **0.914/0.941** | 0.929/0.941 |
| symbol-level P/R (`--callers` vs derived callers) | 0.961/0.971 | 0.870/0.882 \* |
| find-symbol rank-1 / top-5 | 15/16, 16/16 | 15/16, 16/16 |
| warm latency, median | **49.8 ms** | 3,760 ms (~3 s floor, even repeated) |
| cold start | **208 ms** | 8.7 s |
| index build | none | ~8 min (compiler-grade) |
| bytes per call, sweep mean | ~4.8 KB | ~0.65 KB |
| errors | 0/101 | 7/61 |

\* Protocol asymmetry, not weaker logic: Serena was scoped to one definition file on overload rows.
Both asymmetry views are in the scratchpad `SCORES.md`; this row should not be read as a clean win.

Reading it honestly in both directions: **the LSP is more precise, and the gap is ~1.5 points after
the fix round, with recall now equal.** It costs ~70× the warm latency, 40× the cold start, an
eight-minute index, and it cannot answer macro queries at all (clangd's `documentSymbol` has no
macro entries — 3 of its 7 errors). ripwire pays ~7× the bytes per call, because its output carries
self-describing legends. Serena also writes `.serena/` into the target repository by default and
requires `compile_commands.json` at the repository root with no override.

## What the fix round changed

The round produced a ranked loss list, and the fixes were preregistered and measured separately;
the full record is [`bench/fixround/RESULTS.md`](../../fixround/RESULTS.md). Two levers were
accepted — `using`-declaration re-exports now emit `role="import"` rows, and a local variable that
shadows a function name no longer steals that function's use-sites — moving site-level precision
0.9046 → 0.9136 and recall 0.9285 → 0.9412.

Per the improve-first rule these numbers were held back until the fix list was worked. They are
published now because it has been.

## Limits that travel with this table

- **One corpus, and it is this repository.** Self-referential: the levers edited files the queries
  score against, which is why three `--for` queries carry stale expected line numbers (documented in
  `bench/fixround/RESULTS.md`). A single-corpus number is not a general claim.
- **34 scorable queries** is a small N. Differences of a point or two are not separable.
- **The oracle is not ground truth**, it is a compiler-grade approximation with its own blind spots —
  two of which this round found and reported above.
- **Latency figures are frozen** from the original sweep and were not re-run against later binaries.
