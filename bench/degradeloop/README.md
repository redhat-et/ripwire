# bench/degradeloop — scaffolding for the gate-vs-degradation harness

**UNTESTED. Nothing in this directory has been run.** These scripts were written alongside
[`docs/research/gate-vs-iterative-degradation.md`](../../docs/research/gate-vs-iterative-degradation.md)
(read that first — it's the design these scripts implement) as a starting point for whoever runs the
actual experiment. No model API is wired in anywhere; the one seam that needs one
(`call_model()` in `run_degradeloop.py`) raises `NotImplementedError` on purpose rather than faking a
call site that looks functional. Every number these scripts *could* produce would be synthetic until
that seam is filled in and the scripts are actually exercised against a real model and a real
`build/ripwire` binary.

## What's here

- `run_degradeloop.py` — drives one arm (`ungated` / `gated` / `neutral-control` / `wrong-target`,
  see the design doc §2.1/§2.4) of the loop for one seed task: calls the model seam each iteration,
  commits the result to a scratch git repo, and calls `measure.py`'s functions to snapshot it. Writes
  one JSONL trajectory file per (seed task, arm) pair.
- `measure.py` — the deterministic measurement layer. Wraps `ripwire --quality-delta --json` and
  `ripwire --test-gate --json` as subprocess calls against a scratch working tree, plus a stub for
  the public security-scanner call (`run_security_scanner()`, also unimplemented — pick and pin a
  scanner per §2.2 of the design doc before filling this in). Parses only what the design doc's
  §2.2/§2.3 instruments need; does not attempt to be a general ripwire-output parser.
- `analyze_trajectory.py` — reads the JSONL trajectory files `run_degradeloop.py` writes (for however
  many arms and seed tasks are on disk) and computes the four pre-registered instruments from the
  design doc's §2.3: cumulative-regression slope (paired Wilcoxon across seed tasks), terminal-state
  comparison, sub-bar growth rate, and — if a scanner ran — the security-finding trajectory. Refuses
  to report an instrument it cannot compute rather than silently omitting it from a table (a design
  doc's own house rule, `src/quality.h`'s honesty framing applied here to our own output).

## Before running any of this

1. Fill in `call_model()` in `run_degradeloop.py` against whatever model access you have. It takes
   `(prompt: str, current_code: str) -> str` and returns the new code — that's the whole contract.
2. Pick and pin a security scanner per seed-task language in `measure.py::run_security_scanner()`
   (a version and ruleset hash, not just a tool name — see the design doc's §2.2 caveat on this).
3. Assemble a seed-task set (see the design doc's "what we'd like help with" — we don't have one).
4. Point `RIPWIRE_BIN` (env var, read by `measure.py`) at a real `build/ripwire` built from this
   repository's `CLAUDE.md` build instructions. `measure.py` refuses to run against a bare `ripwire`
   on `PATH` without this being set explicitly, so a stale system install can't silently produce
   numbers.

## Determinism note

`measure.py`'s ripwire calls are deterministic (same binary, same tree → same output, per this
project's own determinism contract). The loop as a whole is **not** deterministic end to end, because
`call_model()` isn't — that's expected and is not something these scripts try to paper over. Record
the model, its version/date, and the temperature/sampling settings used alongside every trajectory
file; `run_degradeloop.py`'s JSONL header line has fields for exactly this and refuses to run without
them filled in.
