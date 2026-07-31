# agentloop — Phase B4 agent-in-the-loop eval

Everything ctxpack has measured so far (`bench/locbench/`, `bench/ANSWERQUALITY.md`) scores
**retrieval quality** — did the ranked candidate list contain the right file/function. It has never
measured the thing that actually matters: **does giving a coding agent ctxpack change whether it
solves the task.** This directory is that harness.

Design source: `PLAN_researchImprove2026.md` Phase B4 and
`research/2026-07/R4-eval-methodology.md` ("Minimal agent-in-the-loop eval design").

**Status: EXEC STEP WIRED, NOT YET RUN.** `select_tasks.py` and `analyze.py` are complete and runnable
today. `run_agentloop.py`'s run-matrix/schema/`--dry-run` machinery is complete and runnable, and
`run_one()` is now wired to candidate harness (A) — `claude -p` with a per-arm tool allowlist and a
generated `--mcp-config` for the `ctxpack_mcp` arm (see the module docstring's EXEC STUB section and
`write_mcp_config()`'s docstring for the verified `ctxpack --mcp` invocation). `--evaluator=swebench`
(resolved= via the official swebench PyPI harness + Docker) is coded to the documented CLI interface but
UNEXERCISED — neither Docker nor the `swebench` package is installed anywhere this was built, so several
field/flag names carry an explicit `TODO-verify` in `run_swebench_harness()`; `--evaluator=none` needs
neither and lets the rest of the pipeline run today. Nothing in this directory has spent any money yet:
`--dry-run` still makes zero external calls, and the new `--live-one` smoke flag (run exactly ONE real
`(task, arm, seed)`, print the record) has been coded but deliberately not executed here — see the SAFETY
NOTE below before ever passing `--live-one` or `--live`.

## The protocol

**Arms** (vary only the harness, hold the model fixed — Terminal-Bench template,
https://arxiv.org/html/2601.11868v1):

| arm | what the agent has |
|---|---|
| `baseline` | grep / read / glob only |
| `ctxpack_mcp` | same agent + ctxpack wired in as an MCP server |

**Seeds:** K=3 per (task, arm). A single-seed SWE-bench number is an unreliable "lucky pass"
(https://arxiv.org/pdf/2605.12925) — always report across seeds, never a single run.

**Tasks:** SWE-bench-Lite instances (`princeton-nlp/SWE-bench_Lite`, test split), **repository-disjoint
from the LocBench train split** — see "Task selection" below. `PLAN_researchImprove2026.md` targets
30-40; SWE-bench-Lite's small repo universe (12 repos total) means the actual achievable count under a
fair per-repo cap is smaller — see the honest count in `tasks.lock` and the note below.

**Metrics** (per `run_agentloop.py`'s record schema):
- `resolved` — did the agent's patch pass the instance's SWE-bench held-out test suite
  (`FAIL_TO_PASS`/`PASS_TO_PASS`)? The primary metric.
- `localization_hit` — did the agent touch at least one gold file from the reference patch?
- `tokens_in` / `tokens_out`, `wall_seconds`, `cost_usd` — cost side of the ledger.

**Cost estimate:** $0.30-$1.50/instance (https://arxiv.org/pdf/2412.21139) x tasks x 2 arms x 3 seeds.
`run_agentloop.py --dry-run` prints the exact projected range for the locked task count — **read that
number before ever passing `--live`.**

**Analysis:** `analyze.py` pairs every `(instance_id, seed)` across the two arms and computes a
**repository-clustered bootstrap** 95% lower bound on the resolved-rate delta (multiple instances from
one repo are not independent trials). The clustering method is adapted from
`bench/locbench/compare_runs.py`'s paired LocBench acceptance bootstrap — see `analyze.py`'s header
comment for the exact attribution; `compare_runs.py` itself is not imported or modified.

### Decision rule (draft — confirm before spending money)

Mirrors the two-tier gate `PLAN_researchImprove2026.md` Phase B1 proposes for LocBench, adapted here:

1. **Hard floor:** resolved-rate delta bootstrap 95% lower bound must be `> 0` (ctxpack_mcp beats
   baseline with high confidence, not just on the point estimate).
2. **Soft utility check:** the cost/wall-clock/token overhead of the `ctxpack_mcp` arm must not erase
   the win — report the paired ratio deltas (`analyze.py`'s `tokens_out_ratio_p50/p95`, etc.) alongside
   the resolved-rate delta and make the call by inspection; a fixed cost ceiling is deliberately not
   hard-coded here (R4's whole point is quality-adjusted acceptance, not a flat cap).
3. **Localization correlation** (secondary, "buys the answer LocBench cannot"): report whether
   `localization_hit` delta and `resolved` delta move together — if ctxpack lifts localization but not
   resolution, that is a real, reportable finding, not a harness bug.

This is a draft, not yet exercised on real data — revisit once the pilot (below) has results.

## Task selection

```sh
python3 bench/agentloop/select_tasks.py --work-dir /tmp/agentloop
```

Rule (verify against `bench/locbench/run_locbench.py`'s `frozen_partition()` — do not trust this
README, read the code): a SWE-bench-Lite instance is **excluded** if
`sha256("ctxpack-a7-v2\0" + repo.lower()).digest()[0] < 128` (i.e. the same repo would land in
LocBench's TRAIN partition). This needs no LocBench re-fetch — it's a pure function of the repo
string, applied directly to SWE-bench-Lite's repo field.

Offline fallback (no fabricated instance ids, ever):

```sh
python3 bench/agentloop/select_tasks.py --from-file rows.json --work-dir /tmp/agentloop
```

`rows.json` must be a real local dump of HF rows (list of `{repo, instance_id, base_commit, ...}`);
the script refuses to run without either a network fetch or this file.

**Honest result on this machine (2026-07-13):** SWE-bench-Lite's test split spans exactly **12
repos**. The repo-disjoint split excludes 6 of them (`django/django`, `matplotlib/matplotlib`,
`mwaskom/seaborn`, `pallets/flask`, `sphinx-doc/sphinx`, `sympy/sympy`), leaving 6 eligible
(`astropy/astropy`, `psf/requests`, `pydata/xarray`, `pylint-dev/pylint`, `pytest-dev/pytest`,
`scikit-learn/scikit-learn`). At the spec'd cap of 4 instances/repo, the maximum achievable is
**24 instances**, not 40 — `tasks.lock` locks 24 (6 repos x 4), and that is reported here rather than
silently raising the cap to hit a round number. Raise `--cap-per-repo` (e.g. to 6 or 7) if a larger N
is wanted; that is a reviewed decision, not something this script decides for you.

`tasks.lock` mirrors `bench/locbench/dataset.lock`'s fail-closed pattern: it carries a
`content_sha256` over the canonicalized instance list, and both `run_agentloop.py` and `analyze.py`
recompute and check it before trusting the file — a hand-edited or corrupted lock file is refused, not
silently re-derived.

## Running the pipeline today (zero cost)

```sh
# 1. select tasks (writes tasks.lock; already done, safe to re-run — deterministic given the seed)
python3 bench/agentloop/select_tasks.py --work-dir /tmp/agentloop

# 2. validate the run matrix + schema, zero agent calls, zero dollars
python3 bench/agentloop/run_agentloop.py --dry-run \
    --tasks-lock bench/agentloop/tasks.lock \
    --results-out /tmp/agentloop/dry.json

# 3. prove the paired/bootstrap analysis math works, on a synthetic fixture
python3 bench/agentloop/analyze.py --self-test

# (analyze.py also runs against the --dry-run output above — it will correctly report zero paired
#  runs, since every dry-run record has status="not_implemented", not "ok")
python3 bench/agentloop/analyze.py --results /tmp/agentloop/dry.json
```

## Running the pilot (harness (A) is wired; NOT yet run — see SAFETY NOTE)

`run_agentloop.py`'s `run_one()` is wired to candidate **(A)** — `claude -p` (Claude Code
print/non-interactive mode) with a tool allowlist per arm and a generated `--mcp-config` for the
`ctxpack_mcp` arm only (module docstring EXEC STUB section has the exact invocation). Candidate **(B)**
(SWE-agent / mini-swe-agent) remains undocumented-as-unimplemented — (A) was chosen, per the module
docstring's "pick ONE, do not half-wire both."

First, smoke-test with exactly ONE real run (`--live-one`) before ever touching the full matrix:

```sh
python3 bench/agentloop/run_agentloop.py --live-one \
    --tasks-lock bench/agentloop/tasks.lock \
    --limit 1 --arms baseline --seeds 1 \
    --work-dir /tmp/agentloop --evaluator none --model <model-id>
```

That's **1 run**, ~$0.30-$1.50 — prints the filled record to stdout so you can eyeball the checkout,
the `claude -p` invocation, the captured `git diff`, and whether token/cost accounting came back
non-null (see `run_one()`'s `TODO-verify` note on the `--output-format json` field names) before
spending anything on the 6-run pilot:

```sh
python3 bench/agentloop/run_agentloop.py --live \
    --tasks-lock bench/agentloop/tasks.lock \
    --limit 3 --seeds 1 --arms baseline,ctxpack_mcp \
    --harness claude-code-p --model <model-id> \
    --work-dir /tmp/agentloop --evaluator none \
    --results-out /tmp/agentloop/pilot.json

python3 bench/agentloop/analyze.py --results /tmp/agentloop/pilot.json
```

That's **3 tasks x 2 arms x 1 seed = 6 runs**, ~$2-9 at the $0.30-$1.50/instance estimate — small
enough to sanity-check the harness plumbing (checkout succeeds, patch applies, MCP server registers
in the `ctxpack_mcp` arm only, cost/token accounting comes back non-null) before committing to the
full run. Pass `--evaluator swebench` once Docker + `pip install swebench` are available to get real
`resolved=` scores instead of `null`.

## SAFETY NOTE — read before ever passing `--live`

**The full run (24 tasks x 2 arms x 3 seeds = 144 runs at the current `tasks.lock`) spends real
money** against a real LLM API and real Docker compute — projected **$43-$216** at 24 locked
instances (scale linearly if `--cap-per-repo` is raised toward the original 40-task target; R4's
original 40-task estimate was ~$150-350). This is not a number `run_agentloop.py` will ever spend
without:

1. An explicit human reading the `--dry-run` cost projection for the exact run count being requested.
2. Explicit human approval of *that specific run* — not a standing "yes, always run this" — before
   `--live` is invoked. Treat this the same as any other real-money agent action: state the projected
   cost, wait for a clear go-ahead, then run.
3. The pilot (3 tasks x 2 arms x 1 seed, ~$2-9) run and its results sanity-checked FIRST, per R4's
   own gate ("harness runs end-to-end on 3 pilot tasks with zero silent skips before the paid full
   run") — no jumping straight to the full matrix.

`run_agentloop.py` currently cannot spend anything: `run_one()` raises `NotImplementedError`
unconditionally. This note stays here for when that changes.
