# P0 resolver-precision round — RESULTS (2026-08-08/09)

One preregistered round, three levers, each accepted or rejected SEPARATELY (the LB-3 lesson:
no blended verdicts). Prereg + blind fixtures were authored BEFORE implementation by a separate
agent; implementers never read the acceptance fixtures (they authored their own gate fixtures).
Bands were set from measured baselines, amended only pre-implementation (amendments A1–A5 in the
prereg), and never moved after. Full prereg, fixture corpora, per-binary measurement matrix and
verifier fixtures live in the session scratchpad `a4ba88d1…/resolverround/` (kept out of the
public tree by design — fixture code would sit in the indexed corpus and trip public-tree gates).

## Verdicts

| Lever | Commits | Primary (blind fixtures) | Secondary (pinned cpp corpus, band) | Verdict |
|---|---|---|---|---|
| L1 RTA-lite (instantiation-filtered CHA cone) | 29d75d2, reverted b04c5ce | FAIL — call site unfiltered (3 candidates, identical to base) | FAIL — ambiguous Δ=0 vs band [−300,−1] | **REJECT** — EVALS §7 entry |
| L2 macro edges + macro-body symbols | 7f37c23 + fix 165610b | PASS ×4 (role="macro" edge, defs≥1, macro-arg call survives, macro-only header populated) | PASS — ambiguous +74 vs band ≤ +100 | **ACCEPT** |
| L3 fn-pointer/callback bindings | da99dad + fix afd56fd | PASS ×5 (incl. both MUST-NOT-edge cases) | PASS — ambiguous −10 vs band ≤ +80 | **ACCEPT** |

## Adversarial verification (one skeptic per lever, refute-by-default)

All three verifiers drew blood; the two accepted levers were fixed under the prereg's A5
allowance (bug fix, never band motion) with each refutation added as a RED-first gate arm:

- **L1** REFUTED twice: the name-keyed instantiated set crossed namespace boundaries (evidence
  for one `Impl` wrongly filtered an unrelated hierarchy's cone, dropping a candidate — falsifying
  the code's own "collision only ever ENLARGES" comment), and RTA-narrowed calls lost their `amb=`
  marker (an unsound closed-world guess rendered indistinguishable from a sound CHA resolution).
  Combined with the inert evidence class (only `T()` temporaries count in C++; `new T`, `T{}`, and
  plain value declarations are invisible — fixing that is new extraction machinery, outside the
  preregistered lever scope), the lever was rejected and fully reverted. Retry path recorded in
  EVALS §7.
- **L2** REFUTED once: a real function's call site was silently re-tagged `role="macro"` because
  an unrelated same-named `#define` existed elsewhere in the corpus. Fixed: the retag now fires
  only for names UNIQUELY macro corpus-wide (a shared name stays a plain call); legends updated;
  on this repo's own tree the guard suppressed 4 of 379 macro retags, all genuine name-shares.
- **L3** REFUTED once: `fn = &alpha; indirect_mutate(&fn); fn();` still claimed the alpha edge —
  an undisclosed wrong-target edge through an address-of escape. Fixed: any address-of or
  reference-binding of a binding variable clobbers it (by-value uses do not); disclosure sentence
  added; zero cost on this repo's own tree (byte-identical map). The verifier also confirmed the
  lever's core claim on real code: 0 new edges, 33 removed edges, every sampled removal a
  confirmed pre-existing false edge (calls through lambda-bound locals resolving to the variable).

## Calibration ledger (pinned cpp corpus, per-lever attribution from the snapshot chain)

| Metric | L1 | L2 (+fix) | L3 (+fix) | final vs base |
|---|---|---|---|---|
| symbols | 0 | +38 | 0 | +38 |
| edges | 0 | +190 | −41 | +149 |
| ambiguous | 0 | +74 | −10 | +64 |
| unresolved | 0 | +1 | +1039 | +1040 |

The webpack corpus is flat on every metric (both accepted levers are C-family-scoped). The
private validation tree (validation only, never a gate) moved in the same directions as cpp.
The L3 `unresolved` jump is disclosure, not regression: fn-pointer call sites the resolver now
RECOGNIZES but refuses to resolve (tombstoned/escaped/table-dispatched) are counted instead of
silently ignored, and 41 previously-confident false edges are gone.

## Non-regression

Determinism double-run byte-identical at every snapshot and on the final binary; xmllint clean;
full gate suite green at every commit (369 gates at final HEAD); ASan/UBSan/LSan clean.
kParserVer 47→50 across the round (48 macro symbols/edges, 49 fn-ptr bindings, 50 escape guard),
each bump with mirror + golden re-pins. scip/clangd oracle: UNTESTED this round (no index built),
as preregistered.
