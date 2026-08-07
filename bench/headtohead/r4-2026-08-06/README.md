# Head-to-head round 4 — one binary, one evaluator, one table

**The point of this round is not a new number. It is retiring a caveat.**

r1 (2026-07-13/14) scored Aider's repo-map, codebase-memory-mcp and graphify. r2 (2026-08-03) scored
repowise and codeseek against a newer binary and a newer evaluator. Each round is paired *within
itself* and the two are **not** number-comparable, so the README had to print two tables and tell the
reader not to compare them — which costs a reader their whole attention budget at exactly the moment
they are deciding whether to care. Round 4 re-runs **all five competitors** under one harness so the
arms can sit in a single ranking honestly.

## Why the scripts live HERE and not in a scratchpad

r1's arm-runners did not survive. They lived under the session scratchpad in `/private/tmp`, which
macOS emptied; by 2026-08-06 that tree was a 0-byte husk of directories. Reproducing r1 therefore
meant *rewriting* three workers from the prose in its `REPORT.md`, not re-running a script. The r2
worker, which was committed, cost nothing to re-run.

That is the whole argument for this directory. A benchmark you cannot re-run is a claim, and this
project's contract is that a measurement you cannot check is a claim. **Anything needed to reproduce
a published number belongs in the tree.**

## What is here

| file | what it does |
| --- | --- |
| `r4_worker.py` | all five competitor arms, one `--arm` each; resumable; shardable with `--tag` |
| `r4_score.py` | aggregates the per-arm JSONL into the paired scoreboard — never recomputes a rank |

The ripwire arm is not in here because it needs no new code: it is `bench/locbench/run_locbench.py`
unchanged.

## Reproducing

Assets (checkouts, tool venvs, the frozen dataset row snapshot) are **not** committed — they are ~5 GB
of other people's repositories. Recreate them:

```bash
# 1. tool installs (versions as run; aider and cbm were still latest on 2026-08-06)
python3.12 -m venv tools/aider-venv    && tools/aider-venv/bin/pip install aider-chat==0.86.2
python3.12 -m venv tools/graphify-venv && tools/graphify-venv/bin/pip install graphifyy==0.9.34
npm --prefix tools/cbm-npm install codebase-memory-mcp@0.9.0
python3.12 -m venv tools/repowise-venv && tools/repowise-venv/bin/pip install repowise==0.37.0
# codeseek 0.1.31 installs itself to ~/.codeseek/bin/codeseek

# 2. the slice + dataset snapshot (sha256 5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97)
#    results/ripwire_for.json defines the 60 instances, their gold, and their base commits.

# 3. the ripwire arm (its own workdir, unrelated to the competitor checkouts)
RIPWIRE=$PWD/build/ripwire python3 bench/locbench/run_locbench.py \
    --split=heldout --max-scored 60 --arms for --n 560 \
    --work-dir <assets>/work --json-out <assets>/results/r4_ripwire_for.json

# 4. each competitor arm. Every arm MUTATES the checkout it works in (git checkout per instance,
#    .repowise / codeseek index dirs written in-tree), so concurrent arms need SEPARATE trees.
H2H_REPOS=$PWD/repos   python3 r4_worker.py --arm graphify
H2H_REPOS=$PWD/repos_b python3 r4_worker.py --arm cbm
# repowise is the long pole (index median ~11 s, worst ~275 s). Shard it:
H2H_REPOS=$PWD/repos_c python3 r4_worker.py --arm repowise --tag _s0 --only "$(cat shard0.txt)"

python3 r4_score.py
```

On APFS, `cp -Rc repos repos_b` clones a 1.2 GB tree in ~6 s and near-zero disk. Concurrent shards of
one arm **must** use separate `--tag` outputs: two processes appending multi-KB JSON lines to one file
is not atomic, and a torn line is a silently lost instance.

## Conventions, inherited rather than reinvented

- **Metric**: `file_ranks` / `first_hit` imported unmodified from `bench/locbench/run_locbench.py`.
  Neither worker nor scorer contains a second implementation that could drift from it.
- **Universe** (competitor arms): `git ls-files` of the shared checkout.
- **Ranked files**: first appearance of a result's file path in the tool's own output order.
- **Query**: the issue's `problem_statement`, whitespace-normalized, first 1200 chars — every arm.
- **Zero silent skip**: any arm failure raises. A missing result is never scored as a miss by omission.
- **No arm gets its noise filtered.** cbm's `<python-builtins>` rows and repowise's non-file wiki pages
  stay in output order and simply never match the universe. Filtering one tool's noise and not
  another's is how a comparison becomes an advertisement.

## Two harness bugs worth remembering

Both were found because a run *failed loudly* rather than scoring a zero.

1. **Aider's transport shared a channel with the tool under test.** The driver returned JSON on stdout;
   on larger repos aider prints its own progress there, so `json.loads` died at char 0 and a perfectly
   good run looked like an arm failure. The driver now writes to a file.
2. **Aider ran with the repo under test as `cwd`.** aider imports numpy and pandas; with the checkout
   as cwd, Python resolved those to the repository's own unbuilt source tree and refused
   (*"please exit the numpy source tree"*). It now runs from a neutral directory with `-P`. RepoMap
   receives an absolute root and absolute file paths, so no ranking depends on cwd.

Both would have been invisible under a harness that treated an exception as "the tool found nothing" —
which is exactly what the zero-silent-skip rule exists to prevent.
