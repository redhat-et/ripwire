# r9 fix round — RESULTS (2026-08-09)

One preregistered round, two levers plus one disclosure, each judged SEPARATELY (the LB-3 lesson:
no blended verdicts). The prereg, the acceptance fixtures and the scored query set were authored
BEFORE implementation; implementers never read them and wrote their own gate fixtures. Bands were
set from the measured r9 baseline and never moved. Prereg, fixture corpora, per-binary snapshots,
verifier fixtures and the four re-score rounds live in the session scratchpad `a4ba88d1…` (kept out
of the public tree by design — fixture code would sit in the indexed corpus and trip public-tree
gates).

The round's input was the r9 head-to-head loss list: the ranked buckets where a compiler-grade LSP
answered a `--uses` question this name-based index did not.

## Verdicts

| Lever | Commits | Primary (blind fixtures) | Secondary (r9 re-score band) | Verdict |
|---|---|---|---|---|
| U — `using ns::name;` re-exports emit `role="import"` | `c082a5f` | PASS ×4 (U-P1…U-P4) | PASS — A03/A05/A06 recall → 1.0000 | **ACCEPT** |
| S — local-shadow suppression | `9677e01` + `79df919` + `79ed3c4` + `65c3ee3` | PASS ×4 (S-P1…S-P4) | PASS — A01 0.6579 → 0.9615 | **ACCEPT** |
| item 3 — bare type-references invisible to `--uses` | (legend sentence) | n/a | n/a | **DISCLOSE** |

## Score table — `--uses` site-level, mean P/R by stratum, 34 scorable queries

| stratum | n | pre | post-U+S | +S-fix | +S-fix2 | +S-fix3 |
|---|---|---|---|---|---|---|
| macro | 2 | 1.0000/1.0000 | 1.0000/1.0000 | 1.0000/1.0000 | 1.0000/1.0000 | 1.0000/1.0000 |
| overloads | 8 | 0.8322/0.8212 | 0.8322/0.8750 | 0.8702/0.8750 | 0.8702/0.8750 | 0.8702/0.8750 |
| plain | 17 | 0.9471/1.0000 | 0.9471/1.0000 | 0.9471/1.0000 | 0.9471/1.0000 | 0.9471/1.0000 |
| templates | 7 | 0.8571/0.8571 | 0.8571/0.8571 | 0.8571/0.8571 | 0.8571/0.8571 | 0.8571/0.8571 |
| **ALL** | 34 | **0.9046/0.9285** | 0.9046/0.9412 | 0.9136/0.9412 | 0.9136/0.9412 | **0.9136/0.9412** |

`--callers` symbol-level is flat at 0.9608/0.9706 across every column: no lever touched the edge
model. All three preregistered bands MET — sweep precision +0.0090 and recall +0.0127 with no
stratum dropping, A01 ≥ 0.90, and A03/A05/A06 all improved to 1.0000.

## The bands were insensitive to the last two commits — stated because it changes what they prove

`+S-fix2` and `+S-fix3` scored **identically** to `+S-fix` on every stratum, every arm and every one
of the 84 scored queries. That is not evidence the two commits did nothing: both are demonstrably
live on hand-derived attack fixtures, and the whole-repo map moves `symbols=9109→9111`,
`edges=10739→10742` between them. The scored set simply contains none of the shapes they fix — the
symbols that move (`line`, `name`, `run`) are not in the query file, and it contains no
control-statement-scoped shadow and no pre-declaration call.

Both nulls were checked against genuinely differing bytes rather than inferred from unchanged
scores: 12 of 101 replayed raw files differ at each step, and six independent drop-detectors over
all scored queries returned empty.

**The lesson, recorded for the next round: a query set frozen by a PREVIOUS round cannot measure the
fixes that round motivated.** Here the blind fixture corpus was the instrument with power, and the
sweep was the collateral-damage guard. A head-to-head that produces a fix list should expect to
author new scored queries for the shapes on it, or say plainly that the sweep is only guarding
against regression.

## Arm C reads 12/16 rank-1 against 15/16 pre-fix — a self-referential-corpus artifact

The scored corpus is this repository, and every lever edited `src/ingest.cpp`, so three queries'
frozen `oracle_line` values went stale: `namesNode` +23, `complexityOf` +23, `firstPathStringArg`
+281 lines, with further churn at each subsequent commit. `--for` still ranks all three **#1**, at
lines independently confirmed by `grep` at HEAD — the scorer's exact-line match is what is stale,
not the ranking. A fourth query (C13) gained a line shift in a non-rank-1 candidate; its rank-1
answer is unaffected. Recorded rather than corrected: re-pinning the frozen file mid-round would
have made the instrument unfalsifiable.

## Adversarial verification — refute-by-default skeptics, one per lever

Across this round and the P0 round before it, verifiers drew blood on **six of six** levers. They
are not optional.

- **U** — CONFIRMED-SOUND, 6/6 attack fixtures, 43/43 genuine corpus rows.
- **S** — REFUTED **three times**, each refutation fixed under the prereg's bug-fix allowance and
  added as a RED-first gate arm. `test/shadowcheck.sh` grew 13 → 23 → 31 → 50 arms.
  1. **Reference declarators, structured bindings, whole-function spans, lambdas** (`79df919`).
     `const T& key` — the most idiomatic C++ parameter shape — never suppressed, because
     `reference_declarator` holds its inner declarator as an unnamed child. Structured bindings
     declared nothing. Whole-function suppression ate genuine calls after an inner shadowing block.
     Lambdas are expressions, not definitions, so their parameters and captures were invisible.
  2. **Control-statement header scope leak** (`79ed3c4`). A declaration in a `for`/`if` init is a
     SIBLING of the body, so the plain block walk recorded the enclosing *function* body as the
     shadow span and ate every genuine call after the loop.
  3. **Declaration-point recall loss** (`65c3ee3`). The span started at the block's opening brace,
     so a genuine call ABOVE the shadowing local vanished entirely. Cross-binary attribution showed
     this was a regression the lever itself introduced: pre-lever the map reported the call plus one
     false read, post-lever it reported nothing. A false positive had been traded for a silent false
     negative — the failure class the honesty contract exists to prevent. The fix moves the span
     start to the end of the complete declarator, C++ [basic.scope.pdecl] exactly, and incidentally
     closed a second defect: `isNonValueContext` did not list `declaration` as a declarator-carrying
     parent, so `int key;` leaked its own name as a `role="read"` and `int a, key;` leaked the second
     name (a `declaration` carries one `declarator` FIELD PER NAME; the field accessor returns only
     the first). Seven false sites left this repo's own `src/`.
  The final skeptic reproduced every claim independently — a full byte-level map diff over all three
  legacy fixture trees showed only the refuting fixture moved (0→1), and `shadowcheck.sh` is 50/50
  on the fixed binary against 46/50 on the previous one.

### One honest limit on the gate arms

The guard arms proving the whole-scope shapes (parameters, captures, catch params, range-for
variables) did NOT narrow **cannot** be red on the previous binary, because the bug they guard does
not exist there. They were proven against hand-built mutants instead. This is recorded as a
substitute for a red-first proof, not as one.

## Process finding

`79ed3c4` reported a fixture as "holds". That was true as *unchanged from the previous binary* and
false as *correct* — the fixture was already wrong and stayed wrong. Fixture verdicts require a
hand-derived expectation; comparing a binary to its predecessor cannot detect an error both share.

## Recorded future levers — diagnosed, not attempted

1. **Bare type-references invisible to `--uses`** (r9 loss bucket 3). A type mention in a signature
   contributes no row. Disclosed in the `--uses` legend this round; a `role="type"` reference class
   remains the fix.
2. **Most-vexing-parse direct-init.** `std::string key( tok );` is ingested as a function
   declaration, so the local never shadows. Live at `src/docdrift.h:1563`. Flat across every binary
   in this round.
3. **Lambda-typed local called inside its own control-statement header.** Flat across every binary.
4. **Parameter-default declaration-site leak.** `void p1( int key = 0 )` reports its own parameter
   name as a read; parent node `optional_parameter_declaration` is absent from `isNonValueContext`.
5. **Untyped `FnAssign` binding vetoes shadow suppression.** `captureFnBindAssign` mints a
   function-pointer binding for any `x = y;` where `y` is a bare identifier, with no type gate,
   unlike the sibling declaration arm; that binding then vetoes suppression for `x`'s whole scope.
   Repro: `int line();` plus a function containing `std::string line; line = zzz;` reports
   `count=2`, both sites falsely unsuppressed. Present since the original lever-S landing.

## Non-regression

Full gate suite green at final HEAD (`377 gates, 375 pass, 2 skip, 0 fail`, no flakes). Determinism
double-run byte-identical at every snapshot; `xmllint` clean; `--quality-delta` clean;
ASan/UBSan/LSan exit 0 over the repository and the shadow gate. `kParserVer` 50 → 55 across the
round, each bump with its `quality.h` mirror and a re-pinned `qschemetrip` golden. Gate-script count
unchanged: every arm extended an existing script.
