---
name: ripwire-perf-target
description: >
  A MEASURED performance problem: start from a benchmark, flame graph, perf sample or profiler run,
  locate the hot symbol the profile names, test structural hypotheses (memory-bound → cache-line data
  layout). Static metrics are change-risk signals, not runtime heat. Inspect only the symbols the
  profile names.
allowed-tools: Bash, Read
---

# Performance targeting with ripwire

> Routing: a repo-wide quality sweep, not perf-specific → **ripwire-fresh-eyes** · a specific BUG, not a slow path
> → **ripwire-find-bug** · unsure → **ripwire-router**.

Trigger: a representative benchmark, flame graph, trace or profiler run has identified a slow operation, stack or
symbol. No measurement yet? Make the smallest representative benchmark or profile first — ripwire cannot infer
runtime cost from source shape.

## The recipe

1. **Pin the measured evidence** — the workload, the baseline, and the symbol or subsystem the profile names.
   Keep the same workload for the after-measurement.
2. **Navigate the measured surface** — `ripwire <dir> --for="measured operation or symbol" --detail=3`, then
   `--callers=SYM`, `--callees=SYM` or `--around=SYM` as needed: a bounded reading set, not a measurement.
3. **Structure as change risk** — `ripwire <dir> --hotspots --legend=compact` (churn × complexity) and
   `ripwire <dir> --metrics --legend=compact --top-k=50` (`in=`, `cbo=`, `nest=` with its `humps=`/`deep=`
   profile): structural evidence, not runtime heat. `in=` is static fan-in, not execution frequency. On C-family/C#
   code, discount a body carrying `ppalt=` — its metrics sum every `#ifdef` branch.
4. **Join the measured heat onto the static findings** — `ripwire <dir> --lint --legend=compact --with-profile=REPORT`
   (REPORT = a RIPWIRE_PROFILE build's stderr report) adds `heat_*` attributes to findings inside profiled scopes.
5. **If the counters say MEMORY, not compute** — `ripwire <dir> --lint --legend=compact` runs the built-in
   **cache-\* pack** (8 static data-layout checks) with no profile needed; when one struct is implicated,
   `--field-affinity=STRUCT` shows which fields are accessed together against the 64-byte line geometry — a
   hypothesis generator, never a measurement (no runtime frequency, no false-sharing verdict, LP64 model).
6. **Re-measure** with the same workload. Only the benchmark proves a speedup.

## Stop rule

Inspect only the symbols the profile names. Prefer the narrow `--field-affinity=STRUCT` form over the bare
whole-repo ranking. Every structural suspicion is confirmed by the benchmark or it is dropped.

## Reference file

`perf-reference.md` — every step in full, the recent-churn lens (`--since`), shape hypotheses from `cbo`/`nest`/
`loc`, the `--with-profile` join, the field-affinity findings (`split-line`, `straddle`) and everything it does not
detect, and the Output shape.
