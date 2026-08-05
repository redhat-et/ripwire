---
name: ripwire-perf-target
description: >
  Investigate a measured performance problem. Start from a representative benchmark, a flame graph, or a
  profiler sample, then use ripwire to locate the measured symbols, map callers/callees, and inspect
  structural hypotheses such as complexity, churn, coupling, and nesting. Static graph metrics are
  maintenance/change-risk signals, not runtime heat or call frequency. Inspect only the symbols the
  profile names — no repo-wide hotspot sweeps for a localized measurement. Backed by ripwire
  (deterministic, on PATH).
allowed-tools: Bash, Read
---

# Performance targeting with ripwire

> Nearest neighbours:
> • Repo-wide quality/health sweep (not perf-specific) → **ripwire-fresh-eyes** (also uses --hotspots).
> • Finding a specific BUG, not a slow path → **ripwire-find-bug**.

Trigger: a representative benchmark, flame graph, trace, or profiler has identified a slow operation, file,
stack, or symbol and you need to understand where a safe optimization belongs. If you have no measurement
yet, create the smallest representative benchmark/profile first; ripwire cannot infer runtime cost from
source shape.

`<dir>` = repo root.

1. **Pin the measured evidence** — record the workload, baseline, profiler/trace result, and the symbol or
   subsystem it implicates. Keep the same workload for the after measurement.

2. **Navigate the measured surface** — `ripwire <dir> --for="measured operation or symbol" --detail=3`, then
   `--callers=SYM`, `--callees=SYM`, or `--around=SYM` as needed. This turns runtime evidence into a bounded
   source-reading set without pretending the graph measured execution.

3. **Maintenance/change-risk context** — `ripwire <dir> --hotspots`
   Output: `<hotspots>` ranked by `score = churn × ccx` (churn = git commit frequency over
   12mo; ccx = cognitive complexity). The `top=` attribute names the highest-complexity
   function in each file. High-score files are frequently changed and structurally complex: useful evidence
   about optimization risk and validation scope, but structural evidence, not runtime heat.
   **A slowdown/regression traced to a specific change, not an all-time read** — use the recent-churn
   lens: `ripwire <dir> --hotspots --since="2 weeks ago"` (or `--since=HEAD~20` for a deterministic rev)
   ranks by commits after that point instead of all-history, which is the right lens for "this got slower
   after X" rather than a static hot-function scan.

4. **Static dependency + shape hypotheses** — `ripwire <dir> --metrics --top-k=50`
   Output: the ranked map with `in=` (fan-in), `cx=`/`ccx=` (complexity), `cbo=` (coupling
   between objects — how many other types this symbol touches), `loc=` (body size), and
   `nest=` (max nesting depth) on each symbol. `in=` is static dependency fan-in, not execution frequency.
   Use `cbo`/`nest`/`loc` to form code-reading hypotheses inside the already-measured surface: coupling may
   constrain a rewrite, nesting may hide branchy or quadratic work, and large bodies may combine unrelated
   work. Confirm every suspected bottleneck with the benchmark/profile.

5. **Expand measured candidates** — `ripwire <dir> --expand=SYM` for the implicated symbols.
   Output: full body + callee signatures. Look for inner-loop allocations, redundant work,
   or O(N²) patterns that profiler data would confirm.

6. **Re-measure** — make one bounded change, rerun the same workload, and report latency/throughput plus any
   correctness/determinism gate. A structurally attractive refactor with no measured improvement is not a
   performance win.

## Output

Measured baseline and workload; the profiler/trace evidence; the bounded symbol/caller/callee surface;
structural hypotheses clearly labeled as non-runtime evidence; the change; and the same after measurement.
