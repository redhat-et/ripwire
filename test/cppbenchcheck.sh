#!/usr/bin/env bash
# cppbenchcheck.sh — smoke gate for bench/cppbench/run_cppbench.py (task #13, C++ localization eval).
#
# Runs the harness on a 3-commit slice of CTXPACK'S OWN repo (never the owner's large private C++
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
# Usage:  bash test/cppbenchcheck.sh   |   CTXPACK_BIN=asan/ctxpack bash test/cppbenchcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null || { echo "python3 required"; exit 2; }
echo "cppbenchcheck: BIN=$BIN"

HARNESS="$ROOT/bench/cppbench/run_cppbench.py"
[ -f "$HARNESS" ] || { echo "missing $HARNESS"; exit 2; }

LOCK="$TMP/dataset.lock"
WORK1="$TMP/work1"
OUT1="$TMP/out1.json"

# ── (i) mining: a fresh 3-instance slice of ctxpack's OWN repo, bounded scan for gate speed ─────────
LOG1="$TMP/run1.log"
CTXPACK="$BIN" python3 "$HARNESS" \
    --source-repo "$ROOT" --branch-scope head --cap 3 --max-scan 400 \
    --work-dir "$WORK1" --dataset-lock "$LOCK" --json-out "$OUT1" \
    >"$LOG1" 2>&1
rc1=$?
if [ $rc1 -eq 0 ] && [ -f "$LOCK" ]; then ok "harness completed rc=0, dataset.lock written"
else no "harness run 1 failed rc=$rc1 (see $LOG1)"; cat "$LOG1" >&2; fi

if command -v python3 >/dev/null && [ -f "$LOCK" ]; then
    n=$( python3 -c "import json; print(json.load(open('$LOCK'))['selected_count'])" 2>/dev/null )
    [ "$n" = "3" ] && ok "dataset.lock mined exactly 3 instances" || no "dataset.lock instance count = ${n:-?} (expected 3)"

    # self-consistency: recompute the lock's content hash the same way the harness does and compare
    python3 - "$LOCK" <<'PY' && ok "dataset.lock content_sha256 is self-consistent" || no "dataset.lock content hash mismatch"
import json, hashlib, sys
lock = json.load(open(sys.argv[1]))
canon = [dict(sha=i["sha"], parent=i["parent"], gold_files=i["gold_files"])
         for i in sorted(lock["instances"], key=lambda x: x["sha"])]
blob = json.dumps(canon, sort_keys=True, separators=(",", ":")).encode("utf-8")
got = hashlib.sha256(blob).hexdigest()
sys.exit(0 if got == lock["content_sha256"] else 1)
PY

    # tampering must be REJECTED on the next run (fail-closed contract)
    python3 - "$LOCK" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
lock["instances"][0]["gold_files"] = ["tampered.cpp"]
json.dump(lock, open(sys.argv[1], "w"))
PY
    CTXPACK="$BIN" python3 "$HARNESS" --source-repo "$ROOT" --branch-scope head --cap 3 \
        --work-dir "$WORK1" --dataset-lock "$LOCK" >"$TMP/tamper.log" 2>&1
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

# ── (iv) determinism x2 — rerun against the SAME frozen lock, compare modulo wall-clock ─────────────
# restore the untampered lock by re-mining fresh (deterministic given the same repo state) rather than
# reusing the tampered copy above.
CTXPACK="$BIN" python3 "$HARNESS" \
    --source-repo "$ROOT" --branch-scope head --cap 3 --max-scan 400 --refresh-dataset \
    --work-dir "$WORK1" --dataset-lock "$LOCK" --json-out "$OUT1" >"$TMP/run_a.log" 2>&1
WORK2="$TMP/work2"; OUT2="$TMP/out2.json"
CTXPACK="$BIN" python3 "$HARNESS" \
    --source-repo "$ROOT" --branch-scope head --cap 3 \
    --work-dir "$WORK2" --dataset-lock "$LOCK" --json-out "$OUT2" >"$TMP/run_b.log" 2>&1
rc2=$?
if [ $rc2 -eq 0 ] && [ -f "$OUT2" ]; then
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

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
