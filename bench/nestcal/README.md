# nestcal — calibration rounds for the nesting-depth metrics

The `nest=`/`humps=`/`deep=` family feeds the quality panel's structural bar, so any change to how
cc_walk assigns nesting is ranking-affecting and runs as a pre-registered round (the same r-round
discipline as `headtohead/` and `locbench/`): freeze hypothesis, labeled predictions, invariants and
the decision rule **before** touching code; measure the shift on held-out corpora; record
ACCEPT/REJECT.

- `measure.py BINARY CORPUS LABEL OUTDIR` — per-symbol (id, nest, humps, deep, cx, ccx, loc) TSV
  plus a summary histogram, ids corpus-relative (the public check forbids home paths).
- `compare.py PRE.tsv POST.tsv [BAR]` — the round's invariant checker; exit 0 iff I1–I4 hold.
- `fixtures/` — hand-derivable labeled fixtures referenced by the round docs.
- `r1-2026-08-07/` — the else/elif phantom-depth round: `PREREGISTRATION.md` (frozen first),
  baselines, post-fix measurements, `REPORT.md` with the verdict.
