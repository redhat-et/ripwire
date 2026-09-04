# Codex lane orchestration plan — 2026-09-03

## Outcome

Make `--plan-lanes` directly usable by a Codex orchestrator. Every lane will carry one deterministic,
auditable execution recommendation: current Codex model, reasoning effort, the rule that selected it,
the structural signals used, and the limits that should make the orchestrator override it.

The recommendation is advisory and structural-only. Ripwire does not infer runtime behavior, security
sensitivity, or the semantic difficulty of prose. The orchestrator remains responsible for overrides.

## Current model roles

- `gpt-5.6-sol`: flagship lane for wide, complex, or contract-sensitive work.
- `gpt-5.6-terra`: balanced default for moderate cross-module work.
- `gpt-5.6-luna`: efficient lane for bounded, low-risk work.

These roles follow the current official OpenAI model guidance. The policy is versioned in output so a future
model-family refresh is explicit rather than silently changing an old plan.

## Ordered implementation

1. Extend `test/planlanescheck.sh` with a red schema contract for `lanes[].execution`; retain the additive
   top-level schema version and version the independent recommendation policy as `codex-lane/v1`.
2. Add execution signal/recommendation data to `src/lanes.h`.
3. Compute each recommendation after pair conflicts and contract touches are known.
4. Serialize the complete recommendation in each lane row.
5. Update `--help` and generated `docs/COMMANDS.md` with the structural-only/advisory contract.
6. Update Codex-facing skill/wrap guidance only where it fits the existing bounded primer.
7. Build; run `planlanescheck.sh`, documentation/wrap gates, determinism, scoped quality delta,
   `--edit-check`, and affected tests. Run the full foreground gate suite if the focused gates are green.

## Orchestrated lanes used for this change

| Lane | Model | Effort | Work |
| --- | --- | --- | --- |
| Architecture | `gpt-5.6-sol` | high | Policy, thresholds, honesty contract |
| Test contract | `gpt-5.6-terra` | medium | Existing gate and JSON schema analysis |
| Delivery audit | `gpt-5.6-luna` | medium | Skills, hooks, wrap, doctor, and docs surface |

All three lanes were read-only because the explicit `--plan-lanes --brief` result predicted shared-file
conflicts in `src/lanes.h` and `src/cli.h`. The root orchestrator owns integration and validation.

## Acceptance

- [x] Every produced lane has exactly one execution recommendation.
- [x] Recommendations are byte-deterministic and contain only in-band evidence.
- [x] Low-risk work can reach Luna; moderate work defaults to Terra; wide/contract-sensitive work reaches Sol.
- [x] Truncation and partial-coverage limitations are present in the lane recommendation itself.
- [x] Existing conflict, landing-order, and JSON-native behavior do not regress.

## Verification record

- Plain and ASan builds pass; the sanitized repository scan exits 0.
- `planlanescheck.sh`, `taskroutecheck.sh`, `wrapverbscheck.sh`, `codexwrapcheck.sh`,
  `skilltruthcheck.sh`, `docscommandscheck.sh`, and the ASan freshness gate pass.
- The lane gate directly proves bounded disjoint work selects Luna and cross-lane contract work selects Sol.
- `--quality-delta` exits 0 with `gating="0"`; remaining findings are all minor.
- Default output is byte-identical across two runs and XML well-formed.
- The six-way full suite reported 461 pass, 2 skip, and 63 fail. Most failures were timeout starvation;
  all four sandbox-blocked loopback MCP gates passed individually with localhost access. Community drill,
  affected-test selection, C++ qualifier, and impact-partition gates also passed individually. The one
  reproduced failure was a flaky live-checkout probe in `testgatepagecheck.sh`: a 20-second alarm turned a
  slow cold parse into empty captured output. Its cap-disclosure fixture is now synthetic and bounded, and
  the gate passes repeatedly.
- A clean 232 MB verification clone at the same `HEAD`, carrying only this task's tracked diff, removed the
  live checkout's 9.1 GB `bench/external` payload from the experiment. Its full six-worker suite completed
  in 488.3 seconds with 524 pass, 2 expected skips, and 0 fail. Both normal and ASan binaries were built
  inside that clone, and the sanitized repository scan passed before the suite.
- After the upstream history rewrite, the feature was rebased onto the live `origin/main` tip `8083ea9`.
  A clean clone of feature commit `088c37f` ran 532 gates in 441.5 seconds: 529 passed, 3 made their declared
  skips, and 0 failed. The complete changed-surface battery and range-scoped quality delta pass with
  `gating="0"`.
