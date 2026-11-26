# bench/cochange — co-change partner backtest

**Question.** When a real change is incomplete, how often do ripwire's co-change partners name the file that
was left out? The partners are the `[3] co-change` section of `--situ=F1,F2,...`. `--pr-context` and
`--cochange=FILE` read the same `cochangePartners` component (src/gitmine.h). `--situ` is the one surface that
merges the partners of several changed files into one ranked list, so it is the surface measured here.

**Why a self-history backtest.** The external oracle was checked first, on 2026-11-26.

- Ramadhanty et al., arXiv:2609.34317 (2,428 BFC-BIC pairs, 17 Apache projects): the abstract page and the
  HTML full text list no dataset, replication-package or artifact link, and carry no data-availability
  statement.
- GitCF, arXiv:2609.37045 (543 incomplete changes, the TAR co-change-rule baseline at Hit@10 0.322): no
  artifact link either. It attributes the dataset to a 2021 master's thesis and gives no URL.

Nothing was downloaded. This harness replays history instead. Its numbers are NOT comparable to GitCF's 0.322.
The populations differ: every multi-file commit here, against confirmed incomplete changes there. The queries
differ too: file sets, against GitCF's method-level elements.

## Protocol (stated before the first run)

**Repositories and fixed tips.**
- `ripwire` at `f7cfcec7a` (origin/main, 2026-11-26). Its history starts 2026-07-31, at the public cutover.
- `kubernetes` at `3596eb69d` (`/Users/qgames/m5-work/repos/kubernetes`, read-only).
- Every other repo under `/Users/qgames/m5-work/repos/` is a depth-1 shallow clone and has no history to
  replay, so the brief's 2-3 external repos shrink to 1.
- Kubernetes crawl root: the repository root. If a warm `--situ` call there takes more than 20 s, the root
  becomes `pkg/` and the RESULT says so. Either way, only files under the crawl root count, for every arm.
- Sources are never written. The harness makes a `git clone --shared --no-checkout` into a work directory,
  and checks out each parent commit there.

**Eval window.**
- ripwire: committer date 2026-09-30 to the tip. That leaves each eval commit at least two months of history.
- kubernetes: committer date 2025-11-26 to the tip.

**Eligible commits.** A commit is eligible when all of these hold:
- it is a non-merge commit with exactly one parent, reachable from the tip;
- after `--no-renames`, it changes 30 paths or fewer (the cap ripwire's own miner applies to history);
- at least 2 of its paths have status `M` and sit under the crawl root.

Only `M` paths join a task. An added file has no history before the commit, and a deleted file cannot be
named by anything at the parent, so neither can be a seed or a target.

**Sample.** A seeded random sample: `random.Random(1126)`, drawing up to 200 eligible commits per repo from the
eligible list sorted by sha. If fewer than 200 are eligible, all of them are used. The draw happens before
any tool runs.

**Tasks.** Each sampled commit yields one task under each of two protocols.
- `L1O` (leave one out): one `M` file is held out, chosen by `random.Random("l1o:1126:<sha>")` from the sorted
  `M` files. The seeds are the other `M` files. The target is the held-out file. With one target,
  Recall@10 equals Hit@10.
- `SEED1` (one file seen): one `M` file is the only seed, chosen by `random.Random("seed1:1126:<sha>")`. The
  targets are all the other `M` files. This is the protocol with a Recall@10 that differs from Hit@10.

**Time order.** Every arm sees only history reachable from the commit's FIRST PARENT, so the commit itself and
everything after it are invisible.
- ripwire runs on a checkout of the parent. Its own 18-month window is anchored on HEAD's committer date, and
  here HEAD is the parent.
- The baselines run `git log <parent>` with the same anchored window.
- The gate (`test/cochangebacktestcheck.sh`) proves this. A future-only coupling must be missed, and a
  test-only `--leak-future` mode, which reads the tip, must find it. That second arm shows the fixture can
  detect a leak at all.

**Arms.** Each arm ranks up to 10 candidates. A candidate is a file at the parent that is not a seed.
- `ripwire`: `--situ=<seeds> --limit=10`, rows of section `[3]`, in ripwire's order (max degree over seeds,
  then path).
  - A seed that ripwire refuses as unindexed is dropped and the call retried. The dropped count is reported.
  - If no seed survives, the task gets an empty ranking and counts as a miss.
  - Ripwire's own rules apply unchanged: support of 3 or more shared commits, only indexed files, at most
    30 indexed files per mined commit, `-c` merges, and at most the first 20 seeds probed (`kSituCochangeProbeFiles`).
- `samedir`: files in a seed's directory (non-recursive) at the parent. Score = the number of seeds in that
  directory. Ties break on path, ascending.
- `cofreq`: an independent Python count over `git log <parent> -c --name-only` in the same 18-month window
  anchored on the parent's committer date, skipping commits with more than 30 paths. Score = the number of
  window commits that touch the candidate and at least one seed. Score must be 1 or more. Ties break on path.
- `cofreq3`: `cofreq` with ripwire's support floor of 3 or more. It separates the floor from the ranking.

**Metrics.** Hit@k is 1 if any target is in the top k. Recall@10 is |top-10 ∩ targets| / |targets|. Each is
reported as a mean over tasks, with n.

**Populations.**
- `all`: every task. A target ripwire cannot index is a ripwire miss.
- `indexed`: tasks where ripwire indexes at least one seed and every target. Indexing is probed at the
  parent with `--situ=<every M file>`, dropping each file ripwire refuses as "matches no indexed file" until
  the call succeeds. This is the population where ripwire could have answered.

**What a result does NOT mean.**
- A commit that touched N files is not an incomplete change. The held-out file was edited in the same
  commit, so this is the recall question, "would the partner list have reminded me", asked of every
  multi-file commit.
- One project plus ripwire's own repo is two populations. It is not a survey.

## Running

```bash
python3 bench/cochange/backtest.py --repo /Users/qgames/m5-work/repos/kubernetes --tip 3596eb69d \
    --since 2025-11-26 --n 200 --ripwire ./build/ripwire --work /tmp/cobt_k8s --out results/k8s.jsonl
python3 bench/cochange/backtest.py --summarize results/k8s.jsonl
python3 bench/cochange/backtest.py --self-test        # the metric arithmetic, no git
```

The gate: `bash test/cochangebacktestcheck.sh` (it needs `build/ripwire`, or `RIPWIRE_BIN`).
