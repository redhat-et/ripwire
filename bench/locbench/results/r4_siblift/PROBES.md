# r4 out-of-domain success probes (report-only — never gates)

Contributed 2026-08-03 by the r3-headroom audit session (bench/headtohead/r3-headroom-2026-08-03/,
results @ b6068c3): two natural-phrasing `--for` misses on django @ `70f39e46` (the r3-headroom
harness pins the checkout) whose gold file is a SAME-DIRECTORY sibling of the top-ranked seed with
POSITIVE candidate score — exactly the r4 mechanism's reachable case, on a corpus and query style
disjoint from the LocBench train split. Report-only: out-of-domain probes inform, they do not gate.

| probe | query (abridged) | seed (rank/score) | gold (rank/score, same dir) |
|---|---|---|---|
| q01 | "database cache backend grows past max size — where is the logic that deletes old/expired entries" | `django/core/cache/backends/filebased.py` FileBasedCache r=1 s=42.6 | `backends/db.py` DatabaseCache r=146 s=27.45 |
| q09 | "add a new built-in template filter to Django itself — which files and functions matter" | `django/template/library.py` (in bundle) | `django/template/defaultfilters.py` r=124 s=22.85 |

q09 caveat (recorded before running): the gold file is 63 tiny same-decorator functions, so its
best-symbol score is diluted. The r4 chooser ranks siblings by single best symbol, which should
still fire; if the lift alone does not move q09, that is evidence for FILE-LEVEL EVIDENCE POOLING
as a follow-up hypothesis, not for widening r4 post-hoc.

Protocol: after r4 calibration bakes its constants, run both probes once with the selected
`RIPWIRE_SIBLIFT` value against the same pinned binary as the acceptance run; record gold ranks
before/after here, beside the held-out verdict. Success = gold inside the emitted bundle's top
ranks; any outcome is recorded.

## Outcome

(unfilled — lands with the r4 verdict)
