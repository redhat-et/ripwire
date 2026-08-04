# r3 pre-registration — path-component subtokens as a low-weight BM25 field

**Registered 2026-08-03, BEFORE the candidate code ran on any benchmark instance.** This document
freezes the hypothesis, grid, metrics, and decision tree; anything not written here is post-hoc.

## Hypothesis

Symbols' FILE PATHS carry query-relevant vocabulary the current fields (name ×3, callee ×1,
doc-comment, body) never see — `requests/__init__.py` contains "requests" only in its path. The r2
head-to-head (bench/headtohead/r2-2026-08-03/) measured this as repowise's one clean win-shape
(file-page FTS counts path tokens as text), and the R1 mention fix covered only the *explicit
mention* case. Claim: adding path components as a low-weight BM25 field in `lexicalScoresTiered`
improves held-out strict file@10 without displacing name-field wins.

**Prior art constraining the design:** two anchor-hop candidates (r1_anchorhop, r1cpp_anchorhop)
REJECTED at +0.00pp held-out strict@10 — both were *structural score-mass* changes. This candidate
is *lexical evidence*, not graph mass; the failure mode to watch is instead generic-path noise
(`utils`, `tests`, `src` matching everywhere).

## Candidate mechanics (inert by default)

- New pass in `lexicalScoresTiered` (src/lexical.h): per symbol, scan its file's repo-relative path
  through the ONE shared tokenizer (`forEachLexSubtoken`) at integer weight `kwPath`.
- Runs in BOTH the scan branch and the persisted-stats branch (paths need no file text), so
  postings parity (test/postingscheck.sh) is preserved by construction; the cache format is
  untouched.
- `kwPath` defaults to **0** — behavior byte-identical until the env `RIPWIRE_PATHTOK_W` sets a
  positive weight. Shipping a nonzero default requires the acceptance gate below; until then this
  is calibration scaffolding only.

## Calibration (TRAIN ONLY)

- Harness: `bench/locbench/run_locbench.py --n 560 --split train --arms for` (top-k 200,
  query-chars 1200, history-depth 1) — the frozen repo-disjoint A7 split; held-out untouched.
- Grid: `RIPWIRE_PATHTOK_W` ∈ {1, 2, 3} vs baseline 0. No other knobs; no grid extension after
  seeing results (an extended grid = a new pre-registration).
- Selection rule: highest train strict file@10; tie → lower weight; any candidate that regresses
  train single-file strict@10 by >1pp is disqualified regardless of aggregate.

## Acceptance (held-out, run ONCE, after constants are baked)

- **Primary metric: strict file@10 on the held-out split (243 scored), paired vs the same binary
  with `RIPWIRE_PATHTOK_W` unset.** Repo-clustered bootstrap 95% LB per the two-tier proposal
  (`bench/locbench/GATE_DECISION.md`): tier-1 absolute SLA ceilings on warm/cold p95, tier-2
  quality-per-cost with LB > 0 required.
- Secondary (report, never switch to): any@10, file@1, fn-MRR, single/multi strata, all-patch.
- Perf: `bench/perfgate.sh` budgets must hold with the weight enabled (the path pass adds
  tokenization per symbol; if it breaks a budget, amortize per file before the acceptance run, not
  after).
- REJECT is archived here exactly like r1cpp_anchorhop (verdict, both runs' JSON, the diff), and
  the default stays 0.

## Outcome

**REJECT (2026-08-03)** — see `gate_verdict.txt`. Train (+1.97pp, monotone) did not generalize:
held-out +1.31pp aggregate with clustered-bootstrap 95% LB −0.96pp; the effect concentrates in the
multi-file stratum (+5.66pp, n=53). Tier-1 also failed on the predicted unamortized path-scan tails
(a recorded deviation — the perf clause above was not exercised before acceptance). Default stays 0;
scaffolding retained; any retry pre-registers multi-file-primary and amortizes first.
