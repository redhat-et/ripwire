# VT-2 — file-level pooling, the free end-to-end statistic (2026-08-11)

**STOPPED AT THE FREE STATISTIC. No mechanism was designed, no grid ran, no held-out was touched,
no code changed.** This directory is the complete record.

## Why this round exists — and what it found before measuring anything

The round was commissioned as "E6 — file-level evidence pooling, the strongest unspent multi-file
retrieval hypothesis, flagged by three consecutive rounds and never run", sourced from the
`docs/EVALS.md` §7 nameboost entry ("remains UNSPENT — open headroom", committed 2026-08-11).

That premise was false. Pooling had already been spent, five days before that EVALS text was
written: pre-registered 2026-08-06 (`../r5_pooling/PREREG.md`), gridded on train, and **REJECTED ON
HELD-OUT at +0.00pp** (`../r5_pooling/gate_verdict.txt`) as a constrained mechanism (promote-only
slot ladder over `Σ top-K` with a blend). The same evening, r6 closed the stratum to ranking-side
mechanisms (`../r6_expansion/gate_verdict.txt`). Neither verdict had been carried into EVALS — the
stale "UNSPENT" line is exactly how a rejected idea gets re-attempted, and this round nearly was
that re-attempt. The EVALS correction landed with this directory.

What was still genuinely unmeasured: the r5_pooling REJECT covered one constrained mechanism on the
legacy n=60 slice. Whether ANY pooling function, applied without constraints (full file reordering,
no promote-only ladder, no blend — the best case a pooling mechanism could ever emit), has headroom
on the larger A7 train instrument had never been computed. Per the §7 rule ("compute the free
end-to-end statistic before spending anything scarce"), that number is free — so it was computed,
as pure post-processing of the complete routed `--for` scored candidate export.

## Step 1 — baseline reproduction (recorded vs measured)

Recorded invocation (r5_nameboost lineage): `run_locbench.py --n 560 --split train --arms for`.
Note the sibling recipe `--max-scored 60` in `../r5_pooling/r5_grid.sh` is the *pooling* round's
first-60 train slice — a different instrument; the numbers below are the full train split.

| metric (train strict file@10) | recorded (r5-era, ~kParserVer 50) | measured (origin/main, this round) |
| --- | ---: | ---: |
| overall (n=254) | 61.81% | 61.0% (155/254) |
| single-file stratum | 70.73% (n=205) | 70.9% (n=203) |
| multi-file stratum | 24.49% (n=49) | 21.6% (n=51) |

Drift explained: the binary moved (L2 macro edges, L3 fn-ptr bindings, decl-arm noise gate,
kParserVer 50 → 60); two instances migrated strata because indexing changed which gold files are
in-universe. Zero skips, parse coverage 484/484. The measured column is the baseline of record for
this round (`vt2_train_base.json`).

## Step 2 — the free statistic (the round's soul)

For every train instance: full `--for` candidate export (`--format=candidates --top-k=1000000000`,
scores included, mention-anchor lifts included), pooled per file over positive member scores, file
ordering by pooled score (tie: best member rank, then path), scored strict@10 with the harness's own
`file_ranks`. Family and decision bar fixed in the script header before any number was seen:
**material iff some fn nets ≥ +3 multi-file instances AND ≤ 2 single-file losses** (thresholds in
instances, floor ≥ 3 — the rule r5_pooling's own verdict demanded after its ±2pp bar proved to be
below single-instance granularity).

Presence guard: the `max` control replayed through the same pipeline reproduced the recorded
per-instance baseline on **all 254 instances (0 mismatches)** — the table is readable.

| pooling fn | multi@10 (n=51) | single@10 (n=203) | multi net | single net |
| --- | ---: | ---: | ---: | ---: |
| `max` (control = shipped behavior) | 11 (21.6%) | 144 (70.9%) | — | — |
| `sum` | 8 (15.7%) | 81 (39.9%) | **−3** | **−63** |
| `top2sum` | 11 (21.6%) | 140 (69.0%) | 0 | −4 |
| `top3sum` | 11 (21.6%) | 142 (70.0%) | 0 | −2 |
| `cw` = max·(1+log₂(1+n)) | 9 (17.6%) | 128 (63.1%) | −2 | −16 |

Per-instance gain/loss ledgers: `vt2_freestat_out.json`.

## Verdict

**NULL — no pooling function nets even +1 multi-file instance; the bar (+3) was never approached.
STOP, per the pre-registered rule.** Three findings worth the round:

1. **The unconstrained upper bound is NEGATIVE, not merely null.** `sum` makes file size the ranking
   signal and destroys the single-file stratum (−63 instances — Prefect/ray/prowler/jax-scale
   modules flood the top-10); `cw` loses 16. The constrained r5_pooling mechanism measured +0.00pp
   because its promote-only ladder was *suppressing this harm* — not because it left gains on the
   table. There is no less-constrained variant worth registering.
2. **The one recurring multi-file "gain" is `UXARRAY__uxarray-1117`** (`sum`, `top3sum`) — the same
   single instance whose flip laundered r5_pooling's train advance under its sub-granular ±2pp bar.
   Two instruments have now independently identified this instance as the entire pooling signal.
3. **Stage attribution (§7 third rule): the failure lives in the EVIDENCE, not the trigger and not
   the choice.** Pooling aggregates the query-derived per-symbol scores that already buried the
   sibling files; aggregation either moves nothing (`top2sum`/`top3sum`) or imports the file-size
   confound (`sum`/`cw`). This confirms, from the unconstrained side and on the larger instrument,
   both r5_pooling's own diagnosis ("the query produced NO evidence to re-weight") and the r6
   closure: the multi-file stratum is closed to ranking-side mechanisms. Open headroom lives in
   candidate GENERATION (11/22 decomposed failures), query understanding (4/22), and non-symbol
   gold (3/22) — different subsystems.

## Reproducing

```sh
RIPWIRE=<repo>/build/ripwire python3 ../../run_locbench.py --n 560 --split train --arms for \
    --work-dir <work> --json-out vt2_train_base.json
RIPWIRE=<repo>/build/ripwire LOCBENCH_WORK=<work> python3 vt2_freestat.py
```

Deterministic given (dataset slice, binary); the dataset row cache is hash-pinned by the harness.
