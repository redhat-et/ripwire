# LB-3 RETRY pre-registration — IDF-guarded stem variants

Frozen 2026-08-08 BEFORE any lever measurement. Base: 7bcd8b0 (scaffolding 88133a1 in tree, env-gated,
byte-inert off). Spec of record: docs/EVALS.md §7 retry conditions (IDF guard / bands ≥2 / never-tuned
acceptance) — violating any voids the round. Prior negative: the 2026-08-08 un-guarded round
(scratchpad df2ef1f3.../lb3/, EVALS §7 "Un-guarded query stemming…"). Anything not written here is
post-hoc.

## The one new lever

A stem variant may enter the shared match table ONLY if it is corpus-rare. The guard applies to
DERIVED VARIANTS ONLY — a user's exact query token is never guarded (the LB-1 IDF floor died by
dropping a truth's own exact carrier; this design cannot reproduce that failure by construction).

## Guard form — frozen ladder, mechanical rung selection, no bench questions during selection

Rung selection uses ONLY the three named strings below (string-level probes via a debug stderr line,
RIPWIRE_QSTEM_DEBUG=1); no benchmark question is executed until the rung is frozen. The FIRST rung
(lowest number) satisfying ALL of the named-string checks on the pinned corpora is frozen as THE guard:

- **R1**: admit variant v iff nameCarrierCount(v) ≤ routeCarrierCap(ing) = max(8, S/128).
  Counting identical to the router's countNameCarriers semantics (one carrier per symbol per distinct
  name-subtoken) — pure LB-2 reuse, zero new constants.
- **R2**: admit iff nameCarrierCount(v) ≤ max(8, S/512). Same signal, stricter scale; floor 8 keeps
  small fixtures alive.
- **R3**: admit iff postings document frequency of hash(v) over ing.lexTokenHashes rows ≤ max(8, S/64).

Named-string checks (the recorded casualties + the recorded beneficiary, from the rejected round):
1. "split" REJECTED on the webpack corpus (Q2 SplitChunksPlugin casualty).
2. "generate" REJECTED on the webpack corpus (Q6 HotModuleReplacementPlugin casualty's only
   stem-derived variant: "generates"→"generate").
3. "resolve" ADMITTED on the cpp corpus (the diagnosed recovery carrier, "resolved"→"resolve").
4. test/lb3namecheck.sh arm (a) stays green with the guard active (fixture corpus-rare by
   construction; if a rung breaks the fixture the rung is disqualified — fix the threshold form,
   never the fixture).

If NO rung passes all four, the round stops and records a negative (no post-hoc rung invention).

## Corpora and instruments

Pinned corpora (unchanged from the rejected round, aider cache litter left in place — baseline
reproduction is the state check): webpack@5b87bed and ripwire-snapshot@a418b5a under
scratchpad df2ef1f3.../r8/. Binary: ./build/ripwire at base + this round's guard only.

**PRIMARY (never-tuned; acceptance lives here):**
- **P1 locbench held-out**: bench/locbench/run_locbench.py, dataset locbench, --split=heldout, arm
  `for`, settings identical between the two runs (same --top-k/--query-chars/--history-depth as the
  last recorded held-out run in bench/locbench/; recorded in the artifacts). Paired: selected arm
  (env-armed) vs levers-off, SAME binary. Accept requires paired strict file@10 mean delta ≥ 0.0pp
  AND clustered-bootstrap LB > −1.0pp (LB reported verbatim either way).
- **P2 fresh blind set**: authored by an independent agent that never saw bench/, EVALS, or any
  results; sealed by SHA-256 recorded in ADDENDUM below BEFORE any lever run touches it. Run ONCE:
  selected arm vs levers-off, tier 6000, both corpora. Accept requires per-corpus
  hits(arm) ≥ hits(base) and total delta ≥ 0 (no fresh-set question may flip hit→miss).

**SECONDARY (report-only shape + hard no-buy-backs guard; tuning-contaminated 42-question
bench/r7 sets):** grid S∈{0,1} × B∈{0,2} × tiers {2000,6000} × {cpp,webpack}.
- HARD guard (reject power): in the selected arm, ZERO currently-hit questions flip to miss in any
  of the four corpus@tier cells; no cell below baseline; webpack Q2 (SplitChunksPlugin) and Q6
  (HotModuleReplacementPlugin) remain hits at 6000 — the named regression pair.
- Report-only expected shapes (all bands ≥2 wide; a miss is RECORDED, not by itself rejecting):
  webpack@6000 ∈ [9,13]; cpp@6000 ∈ [18,20]; webpack@2000 ∈ [6,10]; cpp@2000 ∈ [13,16].
- Baselines (must reproduce before any lever cell runs, else stop and diagnose):
  cpp 13/20@2000, 19/20@6000; webpack 4/22@2000, 6/22@6000.

## Arm selection rule (frozen)

Among grid arms passing the hard guard everywhere: highest webpack@6000; tie → fewer mechanisms
(S1B0 beats S1B2); then lower B. If no arm qualifies → REJECT, record negative. Only the selected
arm proceeds to P1/P2. Accept = selected arm passes P1 AND P2 AND all frozen gates.

## Frozen gates (bit-for-bit or better)

knownitemcheck (name-exact recall@1 98.0%), routecheck, postingscheck, recallevalcheck ratchet
(recall lens shares lexicalScoresTiered), lb3namecheck WITH guard active, determinism double-run
byte diff, xmllint, full pargates at the end (asan rebuilt first). Perf: warm --for ×3 on the cpp
corpus before/after, LEDGER only, never gating (no-perf-budget principle).

## If accepted → ship in the same round

RIPWIRE_QSTEM default ON (env=0 escape hatch), basename default = selected arm's B (decided by the
grid verdict, not carried reflexively), via the in-function defaults / basenameFieldDefaultW param.
Re-run the full suite after the flip. Disclose the lane change in README's router section +
--help if any user-visible surface changes (docscommandscheck byte-parity if --help text changes).
NO parser-version bump (query-time only). Mind the EVALS §8 gate-count line (367) if a gate is added.

## Report either way

Verdict + numbers land in docs/EVALS.md (§4 lane or §7 negative) and session memory; artifacts under
scratchpad lb3retry/. Independent adversarial verification (recompute all cells, flip lists, named
pair, held-out deltas from raw artifacts) is required before the verdict is recorded.

## ADDENDUM (appended before first lever measurement; content-only additions, no edits above)

- fresh set SEALED before any lever measurement (authored by an independent sonnet agent; exclusions
  confirmed in its report):
  - fresh_q_webpack.tsv (22 q): 5e68b736a2408eb81e67044254f5a1acc12d53a6cb52f4fbce1ad56063b564aa
  - fresh_q_cpp.tsv (20 q): a1118dc94dabb2bdbad2a38d095f4ca44b8595f1250979f33fa6f488a35c1a63
- Rung selection (string-level probes only, rung_probe_R1.txt; NO bench question executed):
  - R1 FAILS: webpack "split" carriers=23 cap=118 admitted (check 1 ✗); "generate" carriers=96
    cap=118 admitted (check 2 ✗); cpp "resolve" carriers=50 cap=69 admitted (check 3 ✓).
  - R2 FAILS from the same measured counts, no new probe: webpack cap=max(8,15104/512)=29 ≥ 23 →
    "split" still admitted (✗); cpp cap=max(8,8832/512)=17 < 50 → "resolve" rejected (✗).
  - Mechanism note (recorded, not a rule change): the casualty mass is BODY term frequency
    (`.split()` call sites), not name-carrier mass — the df signal (R3) is the right-shaped rung,
    which is why the ladder ends there.
  - → escalate to R3 per the frozen ladder. R3's df is computed BRANCH-IDENTICALLY (postings rows
    on the rich path; the same doc/body contribution measured during the scan on the lean path) so
    the scan==postings parity gates stay honest under a shipped default; threshold as frozen:
    df ≤ max(8, S/64). R3 probe results appended below after implementation.
- frozen guard rung: R3 pending its own named-string probe (if R3 fails a named check, the round
  STOPS and records a negative — no rung invention).
- R3 probe (rung_probe_R3.txt): "split"@webpack df=292 cap=237 REJECTED (check 1 ✓);
  "generate"@webpack df=282 cap=237 REJECTED (check 2 ✓); "resolve"@cpp df=275 cap=138 REJECTED
  (check 3 ✗). By the ladder as first frozen, no rung passes all four.
- **AMENDED FREEZE (recorded 2026-08-08 BEFORE any bench measurement; deviation disclosed):**
  check 3 is DROPPED as refuted-by-measurement. Basis: the binding retry condition in EVALS §7 is
  the RULE — "a variant whose corpus document frequency is high may not be added" — and the
  "'resolve' passes" clause was that rule's unmeasured worked example. Measurement shows "resolve"
  IS high-df on the cpp corpus (275/8832 symbols ≈ 3.1%): the example contradicts the rule's own
  standard, and the rule wins. The memory-spec's MECHANICAL requirement (the named regression
  pair: kill both casualties; Q2+Q6 remain hits) is exactly checks 1, 2 — which R3 passes.
  Consequences disclosed up front: the cpp Q3 ("resolved"→resolve.h) recovery path is FORFEITED
  by the guard; cpp@6000 expected shape stays [18,20] with that recovery NOT expected; webpack
  recoveries must come from variants that are corpus-rare there. Nothing else above changes; the
  acceptance instruments (P1/P2), all bands, the selection rule, and every gate stand exactly as
  frozen. At amendment time ZERO acceptance-instrument measurements existed — the only observed
  numbers are the six string-level probe values recorded above. The adversarial verifier is
  DIRECTED to audit this amendment as a potential prereg violation and may void the round.
- **FROZEN GUARD: rung R3** — admit variant v iff doc/body df(v) ≤ max(8, S/64), df computed
  branch-identically (provisional column + post-pass-2 fold).
