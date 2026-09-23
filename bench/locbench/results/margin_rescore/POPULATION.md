# `margin_bp` re-score — population and provenance (2026-09-23 run)

Result of the §5.5 pre-committed, exactly-ONE `margin_bp` re-score registered in
`docs/research/confidence-and-abstention.md` (§5.5 pinned at
`860b4dfb34b364b46634b4e5af2208bf01d652bd`, `origin/lane/served-syms-prereg`, signed
`signoff/served-syms-prereg-860b4dfb.txt`). §5.5 fires because `served_syms`'s own §5.4 run
reached **FAIL** on a fingerprint-reproduced population: signed
`origin/lane/served-syms-result` @ `50c554e6077b252ee1f009b950d4666756668202`,
`signoff/served-syms-result-50c554e6.txt`, `docs/research/confidence-and-abstention.md` §10 at
that head. Per the result's C2 ruling (`reports/rv-served-syms-result.md`) and the prereg
signoff's nit, the re-score runs on the SAME asset tree with `lane/for-margin-resolution`'s own
binary — the only one that emits `margin_bp` — and that binary's own run must itself reproduce
§5.4.1's fingerprint before its numbers count.

## Asset tree

The identical `bench-assets/r4-rebuild` tree the `served_syms` §5.4 result run used — not a
fresh checkout (§5.5: "the same asset tree that produced the §5.4 non-pass"). Full construction
provenance (dataset hash, population rule, the `UCL/TLOmodel` LFS deviation) is recorded once, at
`bench/locbench/results/served_syms_prereg/POPULATION.md`, and not repeated here; this run reads
the same tree, unmodified, and confirms it via the fingerprint below rather than by disk
provenance alone.

## Binary

`ripwire 0.6.2 (dev, AppleClang 17.0.0.17000604, emit=std::print, built_from=e6f8942e9)` — built
from `origin/lane/for-margin-resolution` @ `e6f8942e9646e5dcf8d8701eec14339fe777fe14` (full sha
verified against `git rev-parse origin/lane/for-margin-resolution` before building), in
`$ORCH/wt/margin-rescore` (`cmake -S . -B build && cmake --build build -j4`, rc=0). This is the
only binary in the repo's history that emits `margin_bp=` (`860b4dfb3`, the binary the
served_syms result used, does not — `reports/rv-served-syms-result.md` C2).

## Fingerprint (§5.4.1) — reproduced, reused unchanged

Checked before any `margin_bp` number was read, via the same `check_fingerprint()` the
`served_syms` result used (a population property, not a statistic property — §5.5 is explicit
this is not re-derived for `margin_bp`):

| check | expected | measured | ok |
| --- | --- | --- | --- |
| n scored | 92 | 92 | yes |
| `confidence="high"` | 18 | 18 | yes |
| `confidence="low"` | 74 | 74 | yes |
| misses, file grain | 15 | 15 | yes |
| misses, func grain | 38 | 38 | yes |
| `rows_len == n_scored` | — | 92 == 92 | yes |
| score AUROC, file_hit (lattice 670.5/1155) | 0.580519 | 0.580519 | yes |
| score AUROC, func_hit (lattice 1276.5/2052) | 0.622076 | 0.622076 | yes |

All eight checks passed (`fingerprint_ok: true`) — on this run the measured `margin_pct=`/score
AUROC landed exactly on the pinned lattice point (not merely within the admitted-neighbour
tolerance, as the `served_syms` result run's did).

## Instance identity

`instance_ids.txt` in this directory lists the 92 scored `instance_id` values, one per line,
sorted. sha256 of that file (trailing newline included):
`73c4414d7863bb48bb7721f071d2891d1424ab670e62e88f4b16a857c7f8a02f` — **byte-identical to the
served_syms result's own `instance_ids.txt` hash**
(`bench/locbench/results/served_syms_prereg/instance_ids.txt`), confirming this run scored
exactly the same 92 instances the served_syms non-pass did, not merely a same-sized population.

## The `served_syms_5_4` block in this directory's `calib.json`/`calib.md` is a by-product, not a §5.4 result

`calibrate_confidence.py` scores `served_syms` against §5.4's band on every invocation, not behind
a flag (unconditional by design — see that script's own comment at the call site). Because this
run's binary is `lane/for-margin-resolution`'s (`built_from=e6f8942e9`), the `served_syms_5_4`
block in this directory's `calib.json` (`func_hit` AUROC 0.2768, `file_hit` AUROC 0.3307) and the
matching "§5.4 `served_syms`" section in `calib.md` are computed on a **different binary** than
the one that produced the signed §10 result (`built_from=860b4dfb3`: `func_hit` 0.2780, `file_hit`
0.3312) — a different served head, different numbers, present here only because the harness always
computes them, not because this run re-decided §5.4. **§5.4 was scored once, at §10, on the binary
named there, and that verdict stands.** No sentence from this directory's `served_syms_5_4` block
or its `calib.md` section is a licensed §5.4 report (§5.4.1 requires naming the binary a report
used; this one is not that report). The two binaries agree on the outcome (FAIL) and on the §5.2
rung (`does_not_meet_opposite_direction`), so this is a disclosure gap, not a discrepancy.
