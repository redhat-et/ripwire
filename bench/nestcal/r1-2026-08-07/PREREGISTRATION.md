# nestcal r1 pre-registration: the else/elif phantom-depth fix

**Frozen 2026-08-07, BEFORE any code change.** Hypothesis, fix design, labeled predictions,
invariants and the decision rule below are fixed; the implementation may not alter them. Committed
separately from results on purpose (the r1–r6 discipline).

`nest=` feeds the quality panel's structural bar and `humps=`/`deep=` are its profile, so this is a
**ranking-affecting** change: it cannot land as a drive-by. This round is the calibrated round that
`test/nestprofilecheck.sh` arm 5 and `.claude/HANDOFF-quality-panel.md` §3.5 said the fix must have.

## Pins

| thing | pin |
| --- | --- |
| base commit | `88476919e2b358c6e9012621d8e85868cc906cca` (feat/nest-profile tip), dev build (no build type) |
| bar | `quality::kNestBar = 4` |
| C++ corpus (dev) | this repo's `src/` at the base commit |
| Python corpus (validation) | django checkout `3071660acfbdf4b5c59457c8e9dc345d5e8894c5` (`bench-assets/r4/repos/django__django/django`), local |
| C-family corpus (validation) | a private local C-family (ObjC++/C++) tree, `0534e79`, validation-only per its standing rule; its name and per-symbol artifacts stay OUT of the public tree (ripwirepubliccheck arm 1), so round docs call it `cfam-private` and only aggregates appear here |
| harness | `bench/nestcal/measure.py` (`--metrics --no-cache --max-tokens=100000000` so truncation cannot move the row set) + `bench/nestcal/compare.py`, both committed with this doc |
| fixtures | `bench/nestcal/fixtures/chain.c`, `bench/nestcal/fixtures/ladder.py` |
| baselines | `r1-2026-08-07/pre-{ripwire-src,django,cfam-private}.{tsv,summary.json}`, captured at the base commit |

The 2026-08-07 cross-codebase session that motivated this round measured a *different* django
checkout (its `get_field_type` read loc=24; this one reads loc=20, same humps=16), and two of its six
labeled functions (`test/utils.py::enable`, `mail/message.py::_add_attachments`) do not exist in this
older checkout. The fixture `ladder.py` replicates the reported shape exactly, and three real
functions from THIS checkout are labeled below instead. The mechanism reproduces identically.

## Diagnosis (measured before this doc was written; no code changed)

One defect family, two compounding defects, both in cc_walk's `elif_clause`/`else_clause`/`elsif`
branch (`src/ingest.cpp`):

1. **Double-deepening.** The clause node was already pushed at `nesting+1` by its parent
   `if_statement` (which pushes ALL children at `childNest`). The clause branch then pushes every
   non-`if` child at `nesting+1` *again*, so clause bodies — and the anonymous `else`/`elif` keyword
   tokens, the condition, the `:` token — land one level deeper than the construct's primary body.
   This is the known C-family anonymous-`else`-token quirk (arm 5's pinned `elseIfChain nest=2`) and
   the Python elif over-count: **the same mechanism**, not a separate defect.
2. **Per-child hump minting.** `cc_noteHump( c, nesting, nesting+1 )` is called once per non-`if`
   child of the clause. When `nesting+1` equals the bar, *each* child mints a hump — the anonymous
   keyword, the condition, the `:` token, the block, even comment extras attached to the clause. One
   Python elif arm at the right depth mints 4–6 humps. This violates the "one first-crossing per
   region" contract the humps comment claims.

Confirmed against the live base binary: a mini replica of the reported
`DatabaseIntrospection.get_field_type` (fixture `ladder.py::ladder`) reproduces `humps=16` from
hand-derivable arithmetic — 1 genuine ternary crossing + 3 elif arms × 4 children + 1 else × 3
children. The real `get_field_type` in the pinned checkout reports the identical `nest=4 humps=16
deep=5`. The user-reported hypothesis "conditional_expression counting as a nesting level" is **not**
a defect: ternaries deepening nesting is the deliberate Sonar-style convention (`cc_isNestingControl`)
and supplies the one *genuine* hump; the other 15 are per-child minting.

Cross-language note: Java, Go and C# grammars attach the else alternative as a direct `if_statement`
field child (no clause node), so they already behave per the target convention. The fix removes a
C/C++/ObjC/Python/JS/TS/Rust/Ruby-vs-Java/Go/C# inconsistency rather than introducing a new
convention.

## Fix design (declared before implementation)

In the clause branch of `cc_walk`:

- push non-`if` children at `nesting` (the clause's inherited frame nesting, which already carries
  the parent construct's `+1`) instead of `nesting+1`;
- delete the per-child `maxNest` bump and the per-child `cc_noteHump` call — the parent construct
  already recorded that depth when it crossed, and clause bodies open no new depth;
- the flat `cog += 1` for the clause and the C-family else-if grandchild descent (flattening, and
  its `++cyclo`) stay exactly as they are.

Resulting invariant, stated for the record: **an `else`/`elif` body sits at the same nesting level as
the construct's primary body** — matching if/else-if flattening, Ruby's (already-correct) bare `else`
node, and Java/Go/C#. Consequence disclosed: Python `try/for/while ... else:` bodies read at the
construct's own body level too (for try, that is the try-body level, one less than today's value).

`kParserVer` bumps 42→43 (`src/ingest.cpp`) with its `quality.h` mirror — extraction output changes,
caches must invalidate.

## Labeled cases — exact post-fix predictions

Pre values measured at the base commit; post values derived by hand from the fix design BEFORE
implementing. Any miss rejects the round.

| case | lang | pre | predicted post |
| --- | --- | --- | --- |
| `fixtures/chain.c::chain` (5-arm else-if) | C | nest=2 cx=5 ccx=5 | **nest=1**, cx/ccx unchanged |
| `fixtures/chain.c::elsefor` (for inside plain else) | C | nest=3 cx=3 ccx=5 | **nest=2 ccx=4**, cx unchanged |
| `fixtures/ladder.py::flat_ladder` | Py | nest=2 cx=2 ccx=4 | **nest=1**, cx/ccx unchanged |
| `fixtures/ladder.py::ladder` (get_field_type replica) | Py | nest=4 humps=16 deep=5 cx=7 ccx=18 | **humps=1 deep=1**, nest/cx/ccx unchanged |
| django `oracle/introspection.py::get_field_type` | Py | nest=4 humps=16 deep=5 cx=7 ccx=18 | **humps=1 deep=1**, nest/cx/ccx unchanged |
| django `mail/message.py::_create_attachments` | Py | nest=4 humps=3 deep=1 cx=7 ccx=11 | **nest=3, humps/deep ABSENT** (leaves the profile — crosses the omission boundary), cx/ccx unchanged |
| django `mail/message.py::_create_mime_attachment` | Py | nest=4 humps=6 deep=1 cx=5 ccx=9 | **nest=2, humps/deep ABSENT, ccx=8** (one control loses exactly one phantom level), cx unchanged |
| `test/nestprofilecheck.sh::elseIfChain` | C++ | nest=2 (arm-5 pin) | **nest=1** — the arm-5 re-pin, with its comment rewritten to cite this round |

Manual ground truth for the three django functions (read, not assumed): `get_field_type` has exactly
one bar-depth region (the ternary at depth 4); `_create_attachments` never exceeds depth 3
(if → if/for → if/else bodies); `_create_mime_attachment` never exceeds depth 2.

## Corpus-wide invariants (checked by `compare.py`, all three corpora)

- **I1** per shared symbol: `nest_post <= nest_pre` — the fix only removes phantom depth.
- **I2** per shared symbol: `cx_post == cx_pre` — cyclomatic is untouched.
- **I3** per shared symbol: `ccx_post <= ccx_pre` — inflated nesting could only over-charge.
- **I4** on every post row: `humps > 0` iff `nest >= 4` — the arm-5 equivalence survives.

Deliberately **not** claimed: per-symbol monotonicity of `humps=`/`deep=`. A pre-fix phantom crossing
at a clause can mark real inner controls "already deep" (so they went uncounted) and a phantom hump's
span can clamp a later genuine hump's `deep` span; removing phantoms can therefore legitimately
*raise* either value on individual symbols. Only the labeled cases pin exact hump values.

## Directional predictions (falsifiable, per corpus)

On all three corpora: `total_humps` strictly decreases, `rows_with_humps` strictly decreases, and no
`nest_hist` bin below the bar loses mass to a higher bin (mass only moves down). Frozen pre values:

| corpus | symbols | total_humps | rows_with_humps | total_deep | max_nest |
| --- | --- | --- | --- | --- | --- |
| ripwire src/ | 2246 | 842 | 188 | 4182 | 9 |
| django | 8260 | 1379 | 351 | 3140 | 12 |
| cfam-private | 21092 | 1983 | 570 | 9454 | 13 |

## Decision rule

**ACCEPT** iff all of: (1) every labeled prediction above matches exactly, attribute for attribute;
(2) `compare.py` passes I1–I4 on all three corpora; (3) the directional predictions hold on all
three; (4) the full gate suite is green after the declared re-pins; (5) determinism
(`diff` of two runs) and `xmllint --noout` gates pass.

**REJECT** (revert the code, keep the report) if any labeled prediction misses — a miss means the
mechanism is not what this doc says it is, and a fix built on a wrong mechanism does not get to land
because its aggregate numbers drifted in a pleasing direction.

Re-pin policy, declared now: `nestprofilecheck.sh` arm 5 (elseIfChain 2→1, comment rewritten) is the
one *expected* re-pin. Any other gate that fails may be re-pinned **only** if its assertion pins a
quirk value this round corrects (each re-pin individually justified in the results doc); a failure
that is not a pinned-quirk value is a genuine regression and rejects the round.
