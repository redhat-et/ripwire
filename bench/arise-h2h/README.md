# ARISE fault-localization head-to-head — harness home

The protocol of record is **docs/EVALS.md § "ARISE fault-localization head-to-head —
PRE-REGISTERED 2026-08-31"**. Read it before running anything; every pin (ARISE commit, SWE-agent
version, dataset revision), the three arms, the 60-instance rung, the primary comparison and the
improve-first rule live there. **Numbers live in EVALS only** — nothing in this directory reports
a result.

What is here:

- `swe_agent_bundle_ripwire/` — the arm-(c) SWE-agent tool bundle, mirroring ARISE's bin-shim
  pattern (one tiny executable per verb + `config.yaml` docstrings + `install.sh`). Every shim
  calls the binary pinned by `RIPWIRE_BIN`; nothing falls back to PATH.
- `ripwire.yaml` — the arm-(c) condition overlay (counterpart of ARISE's `configs/arise.yaml`).
- `fl_ripwire.yaml` — ARISE's `configs/fl.yaml` with ONLY the tool names and usage lines
  substituted verb-for-verb (derivation rule stated in the file and in the registration).

To run (blocked on a model endpoint at registration time): sync `swe_agent_bundle_ripwire/` into
the SWE-agent tree as `tools/ripwire`, stage a container-platform ripwire binary, pin
`RIPWIRE_BIN`, then stack the overlays exactly as `ripwire.yaml`'s header comment shows. Scoring
is ARISE's own `evaluation/run_eval.py` + `parse_preds.py`, byte-unmodified.

Gate: `test/ariseshimcheck.sh` smoke-tests every shim against a local corpus with the tree's own
`build/ripwire`.
