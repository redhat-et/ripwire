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

> Routing: a quality sweep, not perf-specific → **ripwire-fresh-eyes** · a specific BUG, not a slow path →
> **ripwire-find-bug**.

Start from a representative benchmark, flame graph, trace or profiler run. No measurement yet? Make the smallest one
first — ripwire cannot infer runtime cost from source shape.

1. **Pin the evidence** — the workload, the baseline, the symbol or subsystem the profile names; keep the workload.
2. **Navigate the measured surface** — `ripwire <dir> --for="measured operation or symbol" --detail=3`, then
   `--callers=SYM`, `--callees=SYM` or `--around=SYM`: a bounded reading set, not a measurement.
3. **Structure as change risk** — `ripwire <dir> --hotspots` (churn × complexity) and `ripwire <dir> --metrics --legend=compact
   --top-k=50` (`in=`, `cbo=`, `nest=` with its `humps=`/`deep=` profile). Structural evidence, not runtime heat: `in=` is static fan-in,
   not execution frequency; on C-family/C# code discount a body with `ppalt=` (it sums every `#ifdef` branch).
4. **Join measured heat onto static findings** — `ripwire <dir> --lint --with-profile=REPORT` (REPORT = a
   RIPWIRE_PROFILE build's stderr report) adds `heat_*` attributes inside profiled scopes.
5. **Counters say MEMORY, not compute** — `ripwire <dir> --lint --legend=compact` runs the **cache-\* pack** (8 static data-layout
   checks, no profile needed); for one implicated struct, `--field-affinity=STRUCT` shows which fields are accessed
   together against the 64-byte line — a hypothesis generator, never a measurement (LP64, no false-sharing verdict).
6. **Re-measure** with the same workload. Only the benchmark proves a speedup.

## Stop rule

Inspect only the symbols the profile names; prefer `--field-affinity=STRUCT` over the whole-repo ranking. A structural
suspicion the benchmark does not confirm is dropped.

## Reference file

`perf-reference.md` — every step in full, the recent-churn lens (`--since`), shape hypotheses from `cbo`/`nest`/`loc`,
the `--with-profile` join, field-affinity findings (`split-line`, `straddle`) and what it does not detect, the Output
shape.
