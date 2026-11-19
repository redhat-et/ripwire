# Stop quality regressions from becoming the baseline

You are working in a ripwire checkout with the tool built (`./build/ripwire`). This prompt is about one
weakness of `--quality-delta`, the "report only what your change made worse" verb, and how a great
engineer would close it. Treat every idea below as a hypothesis: write the gate first, measure it, keep
what wins.

## The problem

`--quality-delta` compares a change against `git HEAD`, or against `A..B` in its range form. Once a
regression merges, the next comparison's base already contains it. It never appears again as a finding
or as a cost: it is silently the new baseline. Without something else, quality can only ratchet down.

Three real cases from one recent round of work on this repo:

| regression | how it slipped through |
| --- | --- |
| `chooseInWindow` complexity 12 → 16 (a gating finding) | merged with PR #693; the session ran `--quality-delta` mid-task but not after its last code commit |
| `defGroupsDropSilent` complexity 14 → 16 | came in with a batch merge; it gates on the single commit, but nothing ran it there |
| `defTableLegend` api-surface 2 → 4 | came in with a batch merge; it gates only over the branch range, not on a single commit — a regression made in two steps |

All three surfaced only later, when an integration branch ran the check against a base that predated
them. A fourth, in the same round, was caught by its own lane's check and fixed in a few turns: the
mechanism works when it runs at the right moment over the right range.

Related facts:
- CI tests the `--quality-delta` verb itself (`test/qualitycheck.sh`) but does not gate this repo's own
  pull requests on it.
- A per-commit check misses a two-step regression; `--quality-delta=BASE..HEAD` over the branch catches it.
- A non-clean range answer can be dominated by stale-acknowledgement rows. That noise, `--test-gate`'s
  mapping of shell-script gates, and `--test-gate` missing an untracked new test file are being fixed
  separately — leave those three alone.

## Ideas, ranked by expected value

1. **A pull-request range gate on this repo.** CI runs `--quality-delta=<merge-base>..HEAD` on every PR and
   fails on a gating finding unless it is fixed or acknowledged in `.ripwire_quality_acks` with a reason.
   The range form catches two-step regressions and a check that ran before the last edit. Keep it to one
   cheap job; the project runs light CI on main and the full matrix on an interval.
2. **An upward ratchet.** Compare each symbol against its best value since a reference point — the last
   release tag, or the symbol's creation — not only against the parent. A merged regression keeps showing
   as drift since that point until it is fixed or acknowledged. Acknowledgements are the only way down and
   carry a reason, an owner and a revisit date. The determinism contract and the existing ack format apply.
3. **A release drift report.** `--quality-delta=<last tag>..HEAD` as a release-checklist step: every
   regression accumulated since the last release, attributed to the commit that introduced it, with the
   easy ones fixed in the same release and an acknowledgement for the rest.
4. **Make a stale check visible.** When the working tree holds uncommitted changes newer than the tree
   `--quality-delta` compared, say so in its header, so a check that ran before the last edit cannot
   pass for a current one.
5. **Say what a great engineer would do with each finding.** Name the fix shape (split the function,
   extract a helper, reduce parameters, restore the error path) and its rough size, so fixing a small
   regression now is the default. The `ripwire-quality-bar` skill already maps shapes to fixes; the
   answer could carry it.

## How to measure

- Replay is the instrument: check out the tree just before each slipped regression merged, run the
  mechanism, and record whether it would have blocked or flagged it. The three cases above are the first
  test set; add every later slip you find with `git log` and `--quality-delta=A..B` over old ranges.
- Pair every proposal with: slipped regressions it would have caught (of the known set), false positives
  on clean PRs, answer bytes, and CI cost.
- Write each gate before the code it measures. The honesty contract applies: counts are floors where they
  cannot be totals, truncation is disclosed, and a zero means "none found", not "none exist".

## House rules

Merge commits only (no squash, rebase or force push). Plain dev build — never `-DCMAKE_BUILD_TYPE=Release`
in a dev tree. Never edit the tree while a build runs; `--clean-first` after a branch switch. A new
`test/*check.sh` goes into `test/regression.sh` in the same commit. Changelog entries go in `changelog.d/`.
Run `./build/ripwire . --quality-delta --legend=compact` before calling anything done.

**End by presenting the plan and stopping for the user's go-ahead. Nothing lands before they approve.**
