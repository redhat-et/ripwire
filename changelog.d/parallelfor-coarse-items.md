### Fixed — the warm snapshot's reference decode ran on one core of eighteen

`warmsnap::parallelFor` picks its worker count from the **item count** —
`min( hardware_concurrency, ceil( n / itemsPerWorker ) )`, serial at one worker. The threshold of
2048 suits a caller whose item is cheap. `readRefRows` and `readBindRows` hand over 4096-row
**chunks**, each costing ~163 µs, so on llvm-project `ceil( 1449 / 2048 ) == 1` and **~5.94 M
reference rows decoded on a single core** — in a format whose own comment says chunks decode in
parallel. Measured effective threads (per-chunk thread time over parallel-region wall, a ratio, so
contention can only depress it and 1.00 can only mean one worker): **1.00 on envoy's 287 chunks and
1.00 on llvm-project's 1,449**. The reference decode is 48–50% of the model section, and the model
section is the largest item in a warm run at that scale.

`parallelFor` gains an **opt-in** `itemsPerWorker`, defaulting to 2048 so **no existing call site
changes at all**, and the two chunk decodes pass 1. The default is deliberately untouched rather than
merely cautiously: `verbfs_qmetrics.h` folds its block digests in **block order**, so a caller that
never asked for coarse-item parallelism must keep the scheduling it has. The inner work-stealing batch
moves with the parameter — at a fixed `fetch_add( 256 )` over 1,449 items there are only ~6 batches,
so most workers would get nothing and fixing the ceiling alone would have bought a fraction of the
win while looking like the change not working. `max( itemsPerWorker / 8, 1 )` leaves the default 256.

The decode was already safe to parallelise and that is checked rather than argued: it writes
`ing.references[i]` at disjoint indices, reads only const tables, and its one shared write is a
relaxed atomic `bool` — a monotonic OR. `Reference` holds **no** float or double field and the decode
accumulates nothing, so the float-ordering constraint that governs ordered reductions does not reach
it.

`RIPWIRE_PARALLEL_WORKERS=<n>` caps the worker count. It is a **test seam, not a tuning knob**, in the
same sense as `RIPWIRE_PARSE_THREADS`: `test/parallelforcheck.sh` arm C needs it to show that a
one-worker run and a sixteen-worker run of one build write byte-identical maps, which only a run that
can pick its worker count can show. It is listed among `optionsKeyOf`'s `kObservers`, which is what
keeps setting it from re-keying the cache — an unlisted `RIPWIRE_*` variable is folded into the key, so
an undeclared seam would silently cost a full re-index. `snapshot-stats` now reports
`parallel_workers=`, so arm C can prove its two runs really differed before believing that they agreed.

**Eight arms, each with something that proves it can fail.** A1 a coarse-item caller obtains more than
one worker; A2 the default still serialises 287 items, pinning untouched callers; B output identical
across worker counts over 11 sizes; **Bp** an order-dependent lambda is *seen* to differ, so B's
comparison can fail; C byte-identical maps at 1 and 16 workers, refusing to run unless the two counts
are observably different; **C control** two deliberately different maps are seen to differ; D the seam
is inert unset and shares one cache; **D control** a cold run is seen to match the re-index pattern it
greps for. On the tree before this change the gate goes red on A+B (no such argument) and on C (no
observable — where it previously read green while comparing a run with itself).
