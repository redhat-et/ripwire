# r4 pre-registration — slot-ladder same-directory sibling lift (the R2 bucket retry)

**Registered 2026-08-03, BEFORE the candidate code ran on any benchmark instance.** Freezes
hypothesis, mechanism, grid, metrics, and decision tree; anything not written here is post-hoc.

## Prior art this must answer (why this is not anchor-hop again)

Two hop candidates were REJECTED at exactly +0.00pp held-out strict@10 (`r1_anchorhop/`,
`r1cpp_anchorhop/`): both added *score mass* along call/import edges from *mention anchors*, and both
reshuffled inside the top-10 without moving the @10 frontier. This candidate differs on all three
axes the archive names:
1. **Seed**: the top *lexically-ranked* files (the query's winners), not mention anchors.
2. **Edge**: same *directory* siblinghood, not call/import hops — the r2 loss evidence
   (`bench/headtohead/r2-2026-08-03/REPORT.md` §iii R2) is `django/forms/*` and
   `src/transformers/*` package siblings, not graph neighbors.
3. **Mechanism**: the mention boost's *slot ladder* (forced placement below the top block — the
   mechanism that shipped and gates green), not additive mass a hub can accumulate.

## Hypothesis

On multi-file-gold issues ripwire finds one gold file at/near #1 and misses same-directory sibling
gold at ranks 11–50 (r2: worst=13/44; multi-file stratum 21.4% strict vs 78.6% any@10). Lifting the
strongest *query-relevant* same-directory siblings of the top-ranked files into the ranks just below
the existing top block moves sibling gold inside @10 without displacing single-file wins.

## Candidate mechanics (inert by default)

- After the routed ranker and mention boost produce `lensRank`: take the top `seedFiles` FILES by
  best-symbol score; for each, the `sibPerSeed` sibling files (same immediate directory, not the
  seed itself) with the highest existing positive `lensRank` symbol — a sibling with zero lexical
  evidence is never lifted (the anti-noise guard the hop candidates lacked). Lift each chosen
  sibling's top symbols into the slot ladder below the mention band; existing higher scores keep
  their place (`max()`, as in the mention boost). #1 is never displaced.
- Env-gated, default off: `RIPWIRE_SIBLIFT="<seedFiles>,<sibPerSeed>"`; unset → byte-identical
  output. A nonzero default requires the acceptance gate below.

## Calibration (TRAIN ONLY)

- Same harness/flags as r3 (`--split train`, frozen A7 split, held-out untouched).
- Grid: (seedFiles, sibPerSeed) ∈ {1,2} × {1,2} — four cells vs baseline. No post-hoc grid growth.
- Selection: highest train strict file@10; tie → fewer lifted files; any cell that regresses train
  single-file strict@10 by >1pp is disqualified regardless of aggregate.
- **Sequencing note (timing hygiene):** calibration runs start only after the r3 sweep's harness
  invocations have fully drained — two benchmarks never share the machine.

## Acceptance (held-out, run ONCE, after constants are baked)

Primary: strict file@10, held-out 243, paired vs same binary with the env unset; repo-clustered
bootstrap 95% LB per the two-tier proposal (`GATE_DECISION.md`) — tier-1 SLA ceilings, tier-2
quality-per-cost LB > 0. Secondary (report, never switch to): any@10, @1, fn-MRR, strata,
all-patch. Perf budgets must hold with the env set. REJECT is archived here like the anchor-hop
rounds, and the default stays off.

Known limit, stated up front: the zulip-31168 loss is a *cross*-directory pair
(`zerver/views/` + `zerver/lib/`) — same-directory siblinghood deliberately does not claim it.

## Outcome

**REJECT at calibration (2026-08-03)** — see `gate_verdict.txt`: no grid cell beat baseline; probes q01/q09 unmoved at every setting; chooser post-mortem (score-adjacent ≠ gold-adjacent) recorded for the file-pooling follow-up.
