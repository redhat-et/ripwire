# `served_syms` pre-registration — population and provenance (2026-09-23 run)

Result of the §5.4/§5.5 measurement registered in `docs/research/confidence-and-abstention.md`
(pinned at `860b4dfb34b364b46634b4e5af2208bf01d652bd`, `origin/lane/served-syms-prereg`, signed
`signoff/served-syms-prereg-860b4dfb.txt`). This directory holds the run's raw outputs; the
narrative result lives in the doc's own new results section.

## Asset tree

A LocBench asset tree (`datasets/` + `repos/`) rebuilt locally, because the original 92-instance
tree from the prior measurement round lived on different hardware. Construction rule, exactly as
`REBUILD_NOTES.md` for that tree records it:

- Dataset rows fetched via `run_locbench.fetch_rows`; frozen 560-row slice, sha256
  `5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97` (matches the pinned dataset
  hash `docs/research/confidence-and-abstention.md` §3.2 names).
- **Population rule:** each held-out repository is left checked out at its *last* instance's
  `base_commit` in dataset order, giving **92 instances across 88 repositories**
  (`candidate92.json` in that tree).
- 87 of the 88 repositories were checked out by `run_locbench.checkout()` (depth-1 clone,
  `git clean -fdx`, one `.ripwire_at_<sha>` marker each).
- **Manual deviation — `UCL/TLOmodel`.** Its checkout failed under `run_locbench.checkout()`
  because the machine's global gitconfig requires the Git LFS filter and `git-lfs` was not
  installed. It was checked out by hand instead: LFS disabled, so its **152 LFS-tracked files are
  unresolved pointer files, not their real binary content**; `git clean -fdx` was still run and the
  checkout marker was written by hand to match what `checkout()` would have written. If a future
  re-run's fingerprint (below) ever fails, this repository is the first thing to redo, this time
  with real LFS content.

## Fingerprint (§5.4.1) — reproduced

Checked before any `served_syms` number was read, exactly as §5.4.1 requires:

| check | expected | measured | ok |
| --- | --- | --- | --- |
| n scored | 92 | 92 | yes |
| `confidence="high"` | 18 | 18 | yes |
| `confidence="low"` | 74 | 74 | yes |
| misses, file grain | 15 | 15 | yes |
| misses, func grain | 38 | 38 | yes |
| `rows_len == n_scored` | — | 92 == 92 | yes |
| score AUROC, file_hit (lattice 670.5/1155) | 0.580519 ± 0.0006 | 0.580087 | yes |
| score AUROC, func_hit (lattice 1276.5/2052) | 0.622076 ± 0.0003 | 0.621832 | yes |

All eight checks passed (`fingerprint_ok: true`), so this run's 92 rows count as "the 92" under
§5.4.1's fingerprint-identifies-the-population rule, not by disk provenance alone.

## Instance identity

`instance_ids.txt` in this directory lists the 92 scored `instance_id` values, one per line,
sorted. sha256 of that file (trailing newline included): `73c4414d7863bb48bb7721f071d2891d1424ab670e62e88f4b16a857c7f8a02f`.

Cross-checked against the asset tree's own `candidate92.json`: **identical sets, 92/92**, closing
the population-identification gap the review (Delta review 4) flagged — this run's 92 rows are
provably the same 92 the tree was constructed to hold, not merely the same count.

## Binary

`ripwire 0.6.1 (dev, AppleClang 17.0.0.17000604, emit=std::print, built_from=860b4dfb3)` — built
from this lane's own worktree at `860b4dfb34b364b46634b4e5af2208bf01d652bd` (the commit this
registration is pinned to; §5.4 does not pin a separate binary sha, only requires that every report
name the one it used).

## Files in this directory

- `calib.json` — full machine-readable output of `bench/locbench/calibrate_confidence.py`
  (`--assets`/`asset_tree` fields redacted to a relative description; absolute host paths are not
  committed).
- `calib.md` — the same run's rendered tables (§3.3 shape).
- `instance_ids.txt` — the 92 scored instance ids, sorted, sha256 above.
