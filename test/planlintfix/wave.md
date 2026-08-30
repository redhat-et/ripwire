# PLAN — wave fixture (mid-wave state)

This fixture reproduces the field failure this feature's own planning note describes: a task card left
with no terminal status line, caught here mechanically instead of by a closer's eye. It also exercises
the ledger cross-check and the discharge check on the SAME small document. Deliberately carries no
hourglass card — the staleness check needs a controlled commit history, which a file committed to this
repo's own ever-growing history cannot give a stable answer for, so it is covered separately by
planlintcheck.sh's own throwaway git repo instead of here.

### T1
Setup work, finished cleanly.
✅ done

### T2
Investigation task, abandoned.
❌ blocked, will not pursue

### T5
Kickoff work for the harvest lane.

## §Status
- 2026-08-01 — T2 owed a re-check
- 2026-08-02 — T2 re-check done ✅
- 2026-08-03 — T9 owed a kickoff review, still pending
