#!/usr/bin/env bash
# cppbenchcheck.sh — smoke gate for bench/cppbench/run_cppbench.py (task #13, C++ localization eval).
#
# Runs the harness on a 3-commit slice of RIPWIRE'S OWN repo (never the owner's large private C++
# corpus — that tree is shared by ~20 sessions and this gate must not depend on it, or on network access). Asserts:
#   (i)   instance mining — a dataset.lock is written with the requested instance count and a
#         self-consistent content_sha256 (the fail-closed contract: a hand-edited lock must be
#         rejected on the NEXT run).
#   (ii)  archive-at-parent indexing — the harness actually extracts trees and scores real ranks
#         (checked via the JSON output shape: n_scored>0, per-instance arm ranks present).
#   (iii) scoring — the scoreboard prints the expected arm rows (for / for-no-mention / query) and
#         the mention-anchor ablation line.
#   (iv)  determinism x2 — two independent runs against the SAME frozen dataset.lock produce
#         byte-for-byte identical scoring (modulo wall-clock fields, stripped before compare).
#
# Cost (CI-FLAKES-2, 2026-10-27): the gate is ~70 ripwire calls over three ~340 MB extracted trees and was killed at its
# 1200 s budget on slow macOS runners three times (10-13, 10-23, 10-27; 640 s on a green run). Three scoring passes ran: run 1
# (cold WORK1), a re-mine that re-scored every arm only to restore the tampered lock, and run 2 (cold WORK2). The tamper now
# hits a COPY of the lock, so the lock never needs restoring and the (iv) comparison is run 1 against run 2 -- two independent
# COLD index builds, a stricter pair than the old cold-vs-warm one. The re-mine survives as its own arm: it still exercises
# --refresh-dataset, on one arm (`for`) instead of all three, and now also asserts that re-mining reproduces the lock hash.
#
# Usage:  bash test/cppbenchcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/cppbenchcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null || { echo "python3 required"; exit 2; }
echo "cppbenchcheck: BIN=$BIN"

HARNESS="$ROOT/bench/cppbench/run_cppbench.py"
[ -f "$HARNESS" ] || { echo "missing $HARNESS"; exit 2; }

LOCK="$TMP/dataset.lock"
WORK1="$TMP/work1"
OUT1="$TMP/out1.json"

# ── (i) mining: a fresh 3-instance slice of ripwire's OWN repo, bounded scan for gate speed ─────────
LOG1="$TMP/run1.log"
RIPWIRE="$BIN" python3 "$HARNESS" \
    --source-repo "$ROOT" --branch-scope head --cap 3 --max-scan 400 \
    --work-dir "$WORK1" --dataset-lock "$LOCK" --json-out "$OUT1" \
    >"$LOG1" 2>&1
rc1=$?
if [ $rc1 -eq 0 ] && [ -f "$LOCK" ]; then ok "harness completed rc=0, dataset.lock written"
else no "harness run 1 failed rc=$rc1 (see $LOG1)"; cat "$LOG1" >&2; fi

if command -v python3 >/dev/null && [ -f "$LOCK" ]; then
    n=$( python3 -c "import json; print(json.load(open('$LOCK'))['selected_count'])" 2>/dev/null )
    if [ "$n" = "3" ]; then ok "dataset.lock mined exactly 3 instances"; else no "dataset.lock instance count = ${n:-?} (expected 3)"; fi

    # self-consistency: recompute the lock's content hash the same way the harness does and compare
    if python3 - "$LOCK" <<'PY'; then ok "dataset.lock content_sha256 is self-consistent"; else no "dataset.lock content hash mismatch"; fi
import json, hashlib, sys
lock = json.load(open(sys.argv[1]))
canon = [dict(sha=i["sha"], parent=i["parent"], gold_files=i["gold_files"])
         for i in sorted(lock["instances"], key=lambda x: x["sha"])]
blob = json.dumps(canon, sort_keys=True, separators=(",", ":")).encode("utf-8")
got = hashlib.sha256(blob).hexdigest()
sys.exit(0 if got == lock["content_sha256"] else 1)
PY

    # tampering must be REJECTED on the next run (fail-closed contract). The tamper edits a COPY: $LOCK stays the frozen lock
    # both scoring runs below read.
    TLOCK="$TMP/tampered.lock"
    python3 - "$LOCK" "$TLOCK" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
lock["instances"][0]["gold_files"] = ["tampered.cpp"]
json.dump(lock, open(sys.argv[2], "w"))
PY
    RIPWIRE="$BIN" python3 "$HARNESS" --source-repo "$ROOT" --branch-scope head --cap 3 \
        --work-dir "$WORK1" --dataset-lock "$TLOCK" >"$TMP/tamper.log" 2>&1
    trc=$?
    if [ $trc -ne 0 ] && grep -q "content hash mismatch" "$TMP/tamper.log"; then
        ok "tampered dataset.lock is rejected (fail-closed)"
    else no "tampered dataset.lock was NOT rejected (rc=$trc)"; fi
else
    no "dataset.lock missing — cannot check mining/tamper contract"
fi

# ── (ii) + (iii) archive-at-parent indexing + scoring shape ─────────────────────────────────────────
if [ -f "$OUT1" ]; then
    python3 - "$OUT1" <<'PY' && ok "JSON shows n_scored>0 with per-instance arm ranks (archive-at-parent indexing ran)" \
        || no "JSON output missing scored instances / arm ranks"
import json, sys
d = json.load(open(sys.argv[1]))
ok = d.get("n_scored", 0) > 0 and d.get("instances") and all("arms" in i and i["arms"] for i in d["instances"])
sys.exit(0 if ok else 1)
PY
    grep -Eq '^for(-no-mention)?[[:space:]]+\|' "$LOG1" && ok "scoreboard prints for/for-no-mention/query rows" \
        || no "scoreboard missing expected arm rows"
    grep -q "mention-anchor ablation" "$LOG1" && ok "mention-anchor ablation line present" \
        || no "mention-anchor ablation line missing"
else
    no "missing $OUT1 — harness did not write JSON"
fi

# ── (iv) determinism x2 — a second, fully independent run against the SAME frozen lock, compared with run 1 ─────────────────
# Run 1 built its indexes cold in WORK1; this run builds its own in an empty WORK2 (own archives, own caches), so the pair is two
# independent cold builds. Modulo wall-clock fields the scoring must be byte-identical.
WORK2="$TMP/work2"; OUT2="$TMP/out2.json"
RIPWIRE="$BIN" python3 "$HARNESS" \
    --source-repo "$ROOT" --branch-scope head --cap 3 \
    --work-dir "$WORK2" --dataset-lock "$LOCK" --json-out "$OUT2" >"$TMP/run_b.log" 2>&1
rc2=$?
if [ $rc2 -eq 0 ] && [ -f "$OUT2" ] && [ -f "$OUT1" ]; then
    python3 - "$OUT1" "$OUT2" <<'PY' && ok "determinism x2 (scoring byte-identical modulo wall-clock)" \
        || no "determinism x2 FAILED — scoring differs between runs"
import json, sys
def strip(d):
    d = json.loads(json.dumps(d))
    for arm in d.get("arms", {}).values(): arm.pop("wall", None)
    d.pop("wall_total", None)
    for inst in d.get("instances", []):
        for arm in inst.get("arms", {}).values(): arm.pop("wall", None)
    return d
a, b = strip(json.load(open(sys.argv[1]))), strip(json.load(open(sys.argv[2])))
sys.exit(0 if a == b else 1)
PY
else
    no "determinism run 2 failed rc=$rc2 (see $TMP/run_b.log)"
fi

# ── (v) --refresh-dataset re-mines from scratch and reproduces the lock ──────────────────────────────────────────────────────
# Reuses WORK1's indexes (no cold build) and scores ONE arm: this arm is about the mining path, not the scoring one (the two
# runs above cover that). The refreshed lock goes to its own file; its content hash must equal the frozen lock's.
RLOCK="$TMP/refreshed.lock"
# CR 4396503879 (train 40): RLOCK starts as a TAMPERED copy of the frozen lock. The harness mines a MISSING lock anyway, so an arm that
# starts without one passes when --refresh-dataset stops working; with a lock present, only the refresh replaces it (a plain run on
# this one refuses: the hash does not match its instances).
python3 - "$LOCK" "$RLOCK" <<'PY' || { no "(v) could not seed the tampered lock"; }
import json, sys
d = json.load(open(sys.argv[1]))
d["content_sha256"] = "0" * 64
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
RIPWIRE="$BIN" python3 "$HARNESS" \
    --source-repo "$ROOT" --branch-scope head --cap 3 --max-scan 400 --refresh-dataset --arms=for \
    --work-dir "$WORK1" --dataset-lock "$RLOCK" >"$TMP/run_r.log" 2>&1
rcr=$?
if [ $rcr -eq 0 ] && [ -f "$RLOCK" ]; then
    h0="$( python3 -c "import json; print(json.load(open('$LOCK'))['content_sha256'])" 2>/dev/null )"
    h1="$( python3 -c "import json; print(json.load(open('$RLOCK'))['content_sha256'])" 2>/dev/null )"
    if [ -n "$h0" ] && [ "$h0" = "$h1" ]; then ok "--refresh-dataset re-mines the same lock (content_sha256 identical)"
    else no "--refresh-dataset mined a different lock (frozen ${h0:-?} vs refreshed ${h1:-?})"; fi
else
    no "--refresh-dataset run failed rc=$rcr (see $TMP/run_r.log)"; cat "$TMP/run_r.log" >&2
fi

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
