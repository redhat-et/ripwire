# agentloop — Phase B4 agent-in-the-loop eval

Everything ripwire has measured so far (`bench/locbench/`, `bench/ANSWERQUALITY.md`) scores
**retrieval quality** — did the ranked candidate list contain the right file/function. It has never
measured the thing that actually matters: **does giving a coding agent ripwire change whether it
solves the task.** This directory is that harness.

Design source: the Phase B4 research and R4 eval-methodology notes ("Minimal agent-in-the-loop eval design").

**Status: HARNESS READY FOR AN UNATTENDED MATRIX; RESOLUTION SCORING STILL UNEXERCISED.**
`run_agentloop.py` supports `claude -p`, `codex exec`, and `opencode run`. Every arm disables MCP; the
ripwire arms use the CLI through a logging shim. Codex and opencode runs get fully isolated homes,
`--resume` skips already-completed cells so an interruption cannot re-spend money, and `--concurrency`
runs N cells at once in separate checkout lanes. One locked Astropy pair plus one post-skill-fix
treatment rerun completed on 2026-08-04; see [`PLAN.md`](../../PLAN.md).

**The headline metric has still never been produced.** `--evaluator swebench` remains unexercised:
scoring needs the `swebench` package (not installed) plus ~120GB of free disk *inside the Docker VM*.
Measured 2026-08-10: Docker is up and usable, the **host** has ~531GB free, but the active colima
`amd64` profile is provisioned with a 40GiB virtual disk (~31GB free). That is an allocation, not a
hardware limit — `colima stop amd64 && colima start amd64 --disk 250 --cpu 8 --memory 16` grows it
(colima grows disks but never shrinks them). Note also that this profile's VM arch is `aarch64`, so
SWE-bench's official `linux/amd64` images run emulated; budget wall-clock accordingly, or track
upstream's experimental native-arm64 support. Until that runs, these arms measure
localization / tokens / wall time — **not solve rate** — and localization is already at ceiling
(6/6 on both arms in the pilot), so it has no discriminating power left. Two defects in the scoring
path were fixed on 2026-08-10 without being able to execute it: the report was being written to the
*caller's* cwd, and an infrastructure failure (Docker down, disk full) was being recorded as
`resolved=False` — indistinguishable from a patch that genuinely did not fix the bug, which would
have read as "ripwire did not help". Infra failures now stop the run instead of scoring it.

## The protocol

**Arms** (vary only the harness, hold the model fixed — Terminal-Bench template,
https://arxiv.org/html/2601.11868v1):

| arm | what the agent has |
|---|---|
| `baseline` | grep / read / glob only |
| `ripwire_cli` | same agent + the shipped `ripwire wrap` rules blurb driving the ripwire CLI; **no skills tree**; MCP disabled |
| `ripwire_skills` | `ripwire_cli` **plus** this checkout's `skills/` tree |

**Why three arms and not two (changed 2026-08-10, schema v3).** The 2026-08-04 Codex pilot measured
+80% tokens for `ripwire_cli` and the loss was diagnosed as *skill-policy* — whole `SKILL.md` bodies
re-read and re-billed every turn — not retrieval. That diagnosis was only possible after the fact,
because the old two-arm `ripwire_cli` **also symlinked the entire skills tree** on the codex harness:
the arm did not mean what its name said, so ripwire's cost and the skills' cost were one number. They
are now two. `ripwire_skills − ripwire_cli` **is** the skills tax, measured rather than argued about,
and `ripwire_cli` is exactly what `ripwire wrap <agent>` tells a real user to install — the eval tests
the shipped recipe. Both ripwire arms share a byte-identical prompt; they differ only on disk.

**Harnesses.** `claude-code-p`, `codex-exec`, and `opencode` (`opencode run --format json`). opencode
is the only one of the three that is open source and scriptable enough for an unattended matrix.

Two things about the opencode harness are load-bearing and easy to get wrong:

- **It reads `$HOME/.claude/CLAUDE.md`** into every run unless `OPENCODE_DISABLE_CLAUDE_CODE=1`, and
  it has **no `--ignore-user-config` equivalent** — `OPENCODE_CONFIG` *merges on top of* the global
  config rather than replacing it. Isolation is therefore done by relocating `HOME` and every `XDG_*`
  dir into an ephemeral per-run home. This matters here specifically: this project's developers keep a
  ripwire usage protocol in `~/.claude/CLAUDE.md`, so an unguarded baseline arm is briefed on the tool
  it is a control for, and every run still reports `status=ok`. `test/agentloopopencodecheck.sh`
  asserts the recipe, and confirms it live against `opencode debug paths` when opencode is installed.
- **It does not fail closed without credentials.** With an empty auth store, `opencode run` silently
  routes to opencode's own free hosted model and completes the turn (verified v1.18.16:
  `providerID=opencode`, `modelID=big-pickle`, `cost=0`). Every record now carries `resolved_model`
  read back from the transcript, and a run whose model contradicts `--model` is recorded as an error
  rather than averaged into an arm.

**Counting ripwire invocations** is done by a **PATH shim** the arm's prompt points at, not by
grepping the agent's transcript. Codex and opencode both self-log shell commands; `claude -p` does
not, which is why every claude-harness run recorded `ripwire_calls=None` until this change. The shim
`exec`s the real binary, so it cannot alter what ripwire returns. Where a transcript count is also
available it is cross-checked against the shim, and the shim wins.

**Seeds:** K=3 per (task, arm). A single-seed SWE-bench number is an unreliable "lucky pass"
(https://arxiv.org/pdf/2605.12925) — always report across seeds, never a single run.

### READ THIS BEFORE FUNDING A RUN: the design is underpowered, and more instances will not fix it

Computed 2026-08-10 (`power_sim.py`, `power_sim_results.json`), **before** spending anything.

`analyze.py` bootstraps **clustered by repo**, and with equal paired-row counts per repo — always the
case here — pooling then averaging is algebraically identical to resampling the **G repo-level mean
deltas**. The whole bootstrap distribution is a resample of G numbers, and **G is 6**. Effective N is
the cluster count, not the instance count. That is the few-clusters regime (reliable coverage wants
G ≳ 20–40).

Minimum detectable effect on resolution rate, 80% power, baseline 30%, across the plausible
intra-cluster correlation range (ICC is **unmeasured** — no scored resolution data exists anywhere in
this repo, which is exactly the gap):

| config | instances | clusters | MDE (pp) @ ICC 0 / .05 / .15 / .30 |
|---|---|---|---|
| 24 / 6 / K=1 | 24 | 6 | 35.8 / 36.2 / 35.3 / 39.6 |
| **24 / 6 / K=3 (the planned design)** | 24 | 6 | **19.4 / 21.6 / 23.1 / 28.3** |
| 48 / 6 / K=3 | 48 | 6 | 13.5 / 16.1 / 20.3 / 25.3 |
| 96 / 6 / K=3 | 96 | 6 | 9.4 / 12.9 / 18.8 / 24.4 |
| *96 / 12 / K=3 (hypothetical: no disjointness rule)* | 96 | 12 | 9.6 / 11.5 / 14.2 / 16.9 |

**The planned design detects an 18–32pp lift.** Adding one navigation CLI to an already-capable
coding agent is a low-single-digits-to-~10pp intervention; a fifth-to-a-third of the whole scale is
not a plausible effect. Worse, at **G=6 with any ICC above zero, a 5pp or 10pp effect is not
detectable at any instance count** — the search ran to 49,152 instances and never crossed 80% power,
because the heterogeneity floor does not shrink with more instances at fixed G. Holding G=6, MDE
plateaus near 16pp by ~400 instances and never improves out to 3,072.

**The lever is clusters, not instances.** For the same marginal instance budget, spending it on new
repos delivers ~4× the power improvement of spending it inside the existing six (20.3 → 14.2pp vs
20.3 → 18.8pp). 12 repos × 8 instances beats 6 repos at *any* instance count.

So: **a null from this design would be uninformative, and must never be reported as "ripwire has no
effect."** Before funding a full matrix, either (a) widen the repo universe — which means revisiting
the LocBench repo-disjointness rule, or moving off SWE-bench-Lite's 12-repo universe to full
SWE-bench / SWE-bench-Verified — or (b) run a small scored pilot whose only job is to **measure the
ICC**, replacing the assumed 0–0.30 range with a number, and re-decide with it.

Assumptions on record: baseline rate 20/30/40% (unmeasured, swept); ICC 0–0.30 (unmeasured, swept —
the single biggest lever); the treatment effect modelled as repo-heterogeneous, which is what drives
the "not reachable" rows; Monte-Carlo noise ±1–2pp. Every one of these is a modelling choice, not a
measurement, and a real scored pilot replaces the first two.

**Tasks:** SWE-bench-Lite instances (`princeton-nlp/SWE-bench_Lite`, test split), **repository-disjoint
from the LocBench train split** — see "Task selection" below. The design targets
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

Mirrors the two-tier gate the Phase B1 design proposes for LocBench, adapted here:

1. **Hard floor:** resolved-rate delta bootstrap 95% lower bound must be `> 0` (ripwire_cli beats
   baseline with high confidence, not just on the point estimate).
2. **Soft utility check:** the cost/wall-clock/token overhead of the `ripwire_cli` arm must not erase
   the win — report the paired ratio deltas (`analyze.py`'s `tokens_out_ratio_p50/p95`, etc.) alongside
   the resolved-rate delta and make the call by inspection; a fixed cost ceiling is deliberately not
   hard-coded here (R4's whole point is quality-adjusted acceptance, not a flat cap).
3. **Localization correlation** (secondary, "buys the answer LocBench cannot"): report whether
   `localization_hit` delta and `resolved` delta move together — if ripwire lifts localization but not
   resolution, that is a real, reportable finding, not a harness bug.

This is a draft, not yet exercised on real data — revisit once the pilot (below) has results.

## Task selection

```sh
python3 bench/agentloop/select_tasks.py --work-dir /tmp/agentloop
```

Rule (verify against `bench/locbench/run_locbench.py`'s `frozen_partition()` — do not trust this
README, read the code): a SWE-bench-Lite instance is **excluded** if
`sha256("ripwire-a7-v2\0" + repo.lower()).digest()[0] < 128` (i.e. the same repo would land in
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

## The QUESTIONS mode — scenario instances, graded answers

The section above measures **patches**: a SWE-bench issue in, a diff out, `resolved` scored by Docker.
The E1 scenario-efficiency bank measures **answers**: one self-contained question at one pinned
commit, whose outcome is a set of files, symbols, verdicts or an ordering — no patch exists to score.
Two pieces carry that shape, and they are deliberately additive; nothing above changes.

| piece | what it does |
| --- | --- |
| `run_agentloop.py --questions TSV` | a local task source that bypasses `tasks.lock` and the HuggingFace gold-row fetch entirely. Rows come from the graded TSV (id / repo / pin\_ref / tier / grader / question / gt\_command / accept\_rule). `--local-corpus DIR` materializes private trees with `git worktree add --detach` at the pinned sha; the per-tier budget cap and wall timeout come from the row, never from the observed chain. |
| `grade_answers.py` | grades the retained transcripts against keys **derived at the pin by running each row's `gt_command`**. |

```sh
# no agent, no cost: what does the bank still owe before it can be run?
python3 bench/agentloop/grade_answers.py --instances BANK.tsv --audit

# grade a completed run (a results JSON from --questions) against keys derived at the pin
python3 bench/agentloop/grade_answers.py --instances BANK.tsv --results run.json \
    --pin-root /tmp/e1-pins --key sealed.json
```

Four rules in the grader are load-bearing, and `test/agentloopgradercheck.sh` asserts every one:

- **Ground truth is a command, never a list.** Each row's `gt_command` is executed at the pin and the
  key derived from its stdout. A frozen list rots invisibly; a command makes "the tree changed" loud.
- **Non-circularity.** No `gt_command` may *invoke* ripwire — a key produced by the instrument under
  test is not a key — and such a row is `REFUSED_CIRCULAR`, never scored. The distinction is precise:
  nine rows of the real bank name `ripwire/src` as a **path argument** to grep/ls, which is fine.
- **Sealed judgement.** Where a key has a judgement half (every `V` row, and any `E` row whose second
  half is a classification), the grader takes a `--key` file and `REFUSED_NO_KEY`s without it. It
  never improvises the judgement half.
- **Honest partials.** An `accept_rule` is prose. A closed clause grammar scores what it recognises;
  an unrecognised clause **demotes the verdict to `PARTIAL`** and is printed. A row is never `PASS` on
  the strength of clauses that were silently skipped.

Verdicts: `PASS` · `FAIL` · `PARTIAL` · `HALLUCINATED` (a named path absent at the pin fails the
instance outright, on every grader type) · `NO_ANSWER` · `GT_EMPTY` · `REFUSED_*` · `UNSUPPORTED`.
Hitting a budget cap is **`cap=1`, a flag beside the verdict — censored, not failed**: the answer the
agent held at cap time is still scored, and a control arm that cannot finish inside the budget is a
reportable result rather than a token ratio. Exit 3 means at least one row was refused.

**One machine dependency worth knowing.** Several `gt_command`s use `**`, which needs bash 4+;
macOS ships bash 3.2, where `**` silently matches nothing and the key comes back empty — a false zero
that looks exactly like a legitimate "no results". The grader probes for a globstar-capable shell once
and `REFUSED_SHELL`s those rows when none exists, rather than deriving a wrong key.

## Control-arm isolation — all three harnesses, not two

Every harness now builds its own child environment; none inherits the operator's shell. This was not
true until 2026-08-12: `claude-code-p`, the **default** `--harness`, ran with `child_env = None` and
inherited `~/.claude` whole — CLAUDE.md, both ripwire hooks, all 18 installed skills, the per-project
auto-memory. On this project's own machine 81 of the 84 lines of the global CLAUDE.md are a ripwire
use-when protocol, so the **baseline arm was briefed on the tool it is a control for**, and every such
run still reported `status=ok`. A contaminated A/B is silent by construction, which is why each
harness's recipe has a canary gate rather than a code review:
`test/agentloopclaudecheck.sh`, `test/agentloopopencodecheck.sh`, `test/agentloopcodexcheck.sh`.

`prepare_claude_environment()` gives each run a fresh `CLAUDE_CONFIG_DIR` with only credentials
symlinked in, and `build_claude_command()` adds `--setting-sources ''` (drops the hook block *and* the
`env.PATH` that would re-prepend the real `ripwire` after the shim), `--strict-mcp-config` (drops the
global competitor MCP server and the repo-local `.mcp.json`) and `--disable-slash-commands` on every
arm except `ripwire_skills`. The meter is pointed at per-run scratch so a benchmark can never append
to the operator's live substitution telemetry. **Unresolved, and a blocker for the first funded claude
run:** `--bare` is the cleanest switch but forces `ANTHROPIC_API_KEY` and never reads OAuth — confirm
with one `--live-one` that OAuth survives a redirected `CLAUDE_CONFIG_DIR` before booking a matrix.

## Running the Codex CLI pilot

Use the Codex harness for the requested comparison. `--limit` selects repositories round-robin, so the
three-task pilot spans Astropy, Requests, and Xarray instead of taking three adjacent Astropy rows.

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
    --limit 3 --seeds 1 --arms baseline,ripwire_cli \
    --harness codex-exec --model <model-id> \
    --work-dir /tmp/agentloop --evaluator none \
    --results-out /tmp/agentloop/pilot.json

python3 bench/agentloop/analyze.py --results /tmp/agentloop/pilot.json
```

That's **3 tasks x 2 arms x 1 seed = 6 runs**, ~$2-9 at the $0.30-$1.50/instance estimate — small
enough to sanity-check checkout, patch capture, CLI-use evidence, skill isolation, and token accounting before committing to the
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

The runner checkpoints after every call. A timeout retains partial JSONL and gold-file localization rather
than losing the whole matrix.
