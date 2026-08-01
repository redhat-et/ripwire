# Universal software-quality metrics → ripwire verb → the fix

Reference for `ripwire-quality-bar` (and `ripwire-reuse-first`). Each metric is *measurable today*, has a
*defensible threshold*, and a *concrete fix*. Thresholds are heuristics — weigh them, don't blindly gate.

## Evidence-tier calibration — trust these unevenly
Not every metric below carries the same evidence.
- **VALIDATED — trust hardest.** Coupling (CBO/fan-out/fan-in, cycles, propagation cost) is the best
  single OO defect predictor across multiple studies, even after controlling for size. Churn/co-change/
  hotspots (complexity × churn) is process-metric evidence, rated *at least* as strong as code metrics —
  the best-validated cluster overall.
- **VALIDATED-AS-CORRELATE, CONTESTED AS INDEPENDENT.** Cyclomatic/cognitive complexity predicts
  defects, but a large share of that signal is LOC in disguise (the size confound is the
  most-replicated finding in this literature). Report complexity **alongside size**, never as a
  stand-alone verdict — and watch SIZE deltas hardest on agent-written code (verbosity is the
  documented agent failure mode, not complexity per se).
- **FOLKLORE — descriptive only, not independently validated.** Martin `I`/`A`/`D` ("main sequence"
  distance) and Lakos `nccd`/`ccd`/`acd` are widely implemented (NDepend, Sonargraph, ripwire `--arch`/
  `--deps`) but no study has independently validated that `D` or `nccd` predict defects or maintenance
  cost. They're cheap, mechanistically plausible, and fine to *look at* — never treat a `D` or `nccd`
  number as proof the way you'd treat a coupling or churn number.
- **BROKEN — do not use for this purpose.** Readability composite scores (Buse-Weimer style) do not
  correlate with *measured* human comprehension in the landmark study (121 metrics tested, zero
  correlated, 57 devs / 396 evaluations). ripwire does not ship one; don't build one on top of its output.

## The four that earn their keep
Complexity, coupling, churn, and duplication are the signals that — *combined* — predict the majority of
defect- and vulnerability-prone files in the empirical literature. Push hardest on coupling and churn
(VALIDATED); complexity is a real but size-confounded correlate (see calibration above).

| Metric | What it is / why it matters | Threshold | ripwire | The fix |
|---|---|---|---|---|
| **Cognitive complexity `ccx`** | nesting-weighted; "hard to change without breaking." Correlate — read with size, not alone. | ≤ 15 (hard ~25) | `--metrics`, `--hotspots` | split the fn; early-return; lift the nested branch into its own named fn |
| **Cyclomatic complexity `cx`** | independent paths; "hard to test." Correlates with defect count; size-confounded (see calibration above). | ≤ 10 | `--metrics` | reduce branches; replace a switch with a constexpr table |
| **Efferent coupling `Ce` / fan-out** | how many modules this one depends on → how fragile it is. VALIDATED — the best single OO defect predictor. | low; depend on stable + abstract | `--deps`, `--arch` `ce`/`I` | depend on an interface; don't reach across sibling dirs |
| **Afferent coupling `Ca` / fan-in** | how many depend on this → blast radius of changing it. VALIDATED. | high `Ca` ⇒ change carefully | `--metrics in=`, `--callers`, `--impact` | tests before touching; keep the contract stable |
| **Instability/Abstractness distance `D`** | `D=|A+I−1|`; high D = zone-of-pain (concrete+stable, rigid) or zone-of-uselessness. **FOLKLORE** — design heuristic, no independent outcome validation found. | near 0 | `--arch` `I/A/D zone=` | move concretions out of stable cores; add an abstraction seam |
| **Churn × complexity (hotspot)** | where defects concentrate — complex AND frequently changed. VALIDATED — process metrics are the best-validated cluster in the literature. | top-N = refactor targets | `--hotspots` | refactor the hotspot first, not the quiet complex file |
| **Duplication (clones)** | token-normalized repeated bodies; a change-amplifier. `type="2"` = exact/renamed, `type="3"` = a gapped near-miss (similarity 0.80-1.0, an inserted/changed statement) — check `type=` before assuming two members are identical. | Rule of Three | `--clones` | extract on the **3rd** occurrence; *prefer dup over the wrong abstraction* |

## Supporting signals
| Metric | What it is / why it matters | Threshold | ripwire | The fix |
|---|---|---|---|---|
| **Function length `loc`** | reader working-set; the size confound — LOC is the master variable most complexity signal reduces to (Shepperd'88, Herraiz-Hassan'10). Also the #1 measured agent-code failure mode: agent code runs **2.3×** more verbose than human code on matched tasks. | ~≤ 60 lines | `--metrics loc=`, `--expand`/`--outline` span, `--quality-delta kind="verbosity"` | extract a cohesive block; don't just reformat — cut the generated boilerplate |
| **Param count `params`** | signature complexity; compare to the LOCAL median in this codebase, never a fixed number — "keep params ≤7" is a debunked, misattributed-to-Miller'56 myth. | judgment vs local median | `--metrics params=`, `--quality-delta kind="params"` | bundle related params into a struct, or split the function |
| **Nesting depth `nest`** | compounds `ccx`; erosion signal — present in 77% of agent trajectories (SlopCodeBench). | ≤ 3 | `--metrics nest=`, `--lint`, `--quality-delta kind="nesting"` | guard clauses; invert conditions; extract the nested block |
| **CBO `cbo`** | count of DISTINCT dependency targets (callees + composed types) per symbol — one of the two best-VALIDATED coupling forms in the whole catalog, alongside propagation cost. | low | `--metrics cbo=` | depend on fewer distinct things; route through an interface |
| **LCOM4** | class/struct/interface cohesion via connected-components (shares-field OR calls-a-sibling-method); the accepted graph-based cohesion form (LCOM1/2 are BROKEN — null defect result). Emitted only for class-having kinds — absent (not a fabricated 1) for free functions. | 1 component = cohesive | `--metrics lcom4=` | split a >1-component class along its component boundary |
| **Propagation cost** | density of the transitive closure over the file→file dep graph: `(Σ reachable(i))/N²` — one of the two best-validated coupling forms (MacCormack-Rusnak-Baldwin MgmtSci'06). | low | `--arch=FILE` → `<metrics propagation_cost=`> | shrink the file's reachable set; break a hub dependency |
| **`tested=`** | cheapest "safety net present" signal: referenced from any test-path file. | `tested="1"` before you touch it | `--metrics`, `--for` (folded into the quality lens) | add a test across the seam before refactoring an untested symbol |
| **Change-amplification `amp`** | `|direct callers| + |co-change partners|` — "editing this historically touches N places" in one number. Granularity note: callers are symbol-level, co-change is file-level — read it as a blast-radius proxy, not a pure per-symbol count. | high `amp` ⇒ change carefully | `--metrics amp=`, `--for` | add tests before touching a high-`amp` symbol; don't refactor it and three callers in the same diff |
| **Dependency cycles / god-files** | tangled, hard to test in isolation. VALIDATED — defects concentrate in cyclic-dependent components. | 0 cycles; no 100-fan-in header | `--deps`, `--report` | break the cycle (introduce an interface); split the god-file |
| **External dependency surface** | supply-chain + build weight + reader-learning tax | add only when it earns it | `--external-surface`, `--uses` import role | reuse an in-tree dep first; justify each new import |
| **Dead code** | latent risk + reader tax | 0 newly-orphaned | `--dead-code` | review high-confidence internal zero-caller candidates; verify before deletion |
| **Bus factor** | knowledge concentration (`bf=1` = one owner) | flag `bf=1` on code you touch | `--owners` | add a second reviewer; leave a doc/comment trail |
| **Untested integration seams** | cross-module calls no test reaches | 0 new uncovered seams | `--seams`, `--affected` | add a test across the seam you introduced |
| **Resolution ambiguity `amb=`** | the map's OWN honesty signal — K calls the resolver guessed | verify high-`amb` in source | header `ambiguous=`, per-symbol `amb=` | read the source before trusting a high-`amb` edge |
| **Cache-friendly data layout (DOD)** | hot-path perf + this codebase's house value: SoA over AoS, smallest type that fits, 32-bit ids | contextual | judgment; `--for` finds the hot struct | mirror the surrounding hot-path layout; don't AoS a hot loop |

## Why `--quality-delta`'s 10 kinds — the measured agent failure modes
Not a generic lint list; each targets what the 2025-26 literature found agent-written code actually
degrades on (large-N studies):
- **Verbosity**: agent code runs **2.3× more verbose** than human code on matched tasks.
- **Structural erosion** (nesting/complexity creep): present in **77%** of trajectories (SlopCodeBench).
- **Smells**: **+63%** vs a human baseline; **89.3%** of issues in a 302.6k-commit AI-authored corpus.
- **Contract drift**: unplanned API-surface growth is a documented failure mode distinct from complexity —
  classic complexity metrics lost predictive power for real agent-maintainability failures once controlled
  for size; contract drift and code growth are what remained predictive (arXiv:2606.21804).
- **Pass-rate ≠ design quality**: fewer than half of test-passing agent patches satisfy design constraints
  (DesignBench) — tests passing is not evidence the delta is clean.
- One-time "write good code" prompting cuts initial verbosity/erosion by about a third but does **not**
  change the degradation rate over time — the loop must be continuous delta discipline, not a prompt-time
  reminder. Metric feedback into the next attempt is not optional decoration either: fed back into the
  prompt, complexity/static-analysis findings measurably fix things (Pass@1 35.7% vs 12.5% baseline;
  security issues cut from >40%→13% over iterations) — `ripwire-quality-bar`'s loop **is** that mechanism.

## The three steering rules (why this beats a linter)
1. **Delta, not absolute.** The regression *you introduced* is the signal. A file that was already a hotspot
   is not your bug; a function you pushed from `ccx=12` to `ccx=22` is. Compare before vs after your change.
2. **Descriptive, not dogmatic.** Surface the number and the nuance; never hard-fail. Duplication is
   sometimes right (Rule of Three; a wrong abstraction is worse). A high-`amb` symbol can be a dispatch hub.
   Cache layout is contextual. A metric that "cries wolf" gets turned off — so don't.
3. **Structure, not flow.** ripwire measures shape + complexity deterministically. It cedes data-flow/type
   analysis (use-after-move, taint, null-deref) to the compiler. Use it for what it's strong at.

## One-liner the agent can run on its own diff
```
for v in --hotspots --clones --deps --dead-code --external-surface; do echo "== $v =="; ripwire <dir> $v; done
ripwire <dir> --situ        # blast radius + tests + co-change, defaults to the current git diff
```
