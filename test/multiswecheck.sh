#!/usr/bin/env bash
# multiswecheck.sh — smoke gate for bench/multiswe/run_multiswe.py (task #R3, Multi-SWE-bench C++ eval).
#
# Runs the harness fully OFFLINE against 3 hand-vendored fixture instances (mimicking the real
# Multi-SWE-bench JSONL row shape: org/repo/base.sha/resolved_issues/fix_patch) that reference a
# tiny local git repo built at test time — no network, no dependency on GitHub or HuggingFace.
# Asserts:
#   (i)   mining — the raw fixture row set (3 rows: 2 eligible, 1 with no linked issue) mines to
#         EXACTLY 2 instances, and dataset.lock is self-consistent (content_sha256 recomputes clean).
#   (ii)  offline checkout — --repo-map redirects the checkout to the local fixture repo (never
#         touches the network) and scores real ranks (n_scored>0, per-instance arm ranks present).
#   (iii) scoring — the scoreboard prints the expected arm rows and the mention-anchor ablation line.
#   (iv)  determinism x2 — two independent runs against the SAME frozen dataset.lock produce
#         byte-for-byte identical scoring (modulo wall-clock fields).
#   (v)   tamper rejection — a hand-edited dataset.lock is refused on the next run (fail-closed).
#
# Usage:  bash test/multiswecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/multiswecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null || { echo "python3 required"; exit 2; }
echo "multiswecheck: BIN=$BIN"

HARNESS="$ROOT/bench/multiswe/run_multiswe.py"
[ -f "$HARNESS" ] || { echo "missing $HARNESS"; exit 2; }

# ── build a tiny local fixture "repo" (2 commits worth of content, but we only need ONE checked-out
#    tree — gold is derived from the fabricated fix_patch text, not a live git diff) ────────────────
FIXREPO="$TMP/fixturerepo"
mkdir -p "$FIXREPO/src"
cat > "$FIXREPO/src/foo.cpp" <<'EOF'
int add( int a, int b )
{
    return a + b;
}
EOF
cat > "$FIXREPO/src/bar.cpp" <<'EOF'
int mul( int a, int b )
{
    return a * b;
}
EOF
git -C "$FIXREPO" init -q
git -C "$FIXREPO" config user.email "fixture@example.com"
git -C "$FIXREPO" config user.name "fixture"
git -C "$FIXREPO" add -A
git -C "$FIXREPO" commit -q -m "initial fixture commit with foo.cpp and bar.cpp"
BASESHA="$( git -C "$FIXREPO" rev-parse HEAD )"

# ── fabricate 3 raw Multi-SWE-bench-shaped rows: 2 eligible, 1 with no resolved_issues (must be
#    excluded from mining, counted in mining_stats, never scored) ───────────────────────────────────
RAWDIR="$TMP/raw/cpp"; mkdir -p "$RAWDIR"
python3 - "$RAWDIR/fixtureorg__fixturerepo_dataset.jsonl" "$BASESHA" <<'PY'
import json, sys
out_path, base_sha = sys.argv[1], sys.argv[2]
fix_patch_add = """diff --git a/src/foo.cpp b/src/foo.cpp
index 1111111..2222222 100644
--- a/src/foo.cpp
+++ b/src/foo.cpp
@@ -1,4 +1,5 @@
 int add( int a, int b )
 {
+    if ( a == 0 ) return b;
     return a + b;
 }
"""
fix_patch_mul = """diff --git a/src/bar.cpp b/src/bar.cpp
index 3333333..4444444 100644
--- a/src/bar.cpp
+++ b/src/bar.cpp
@@ -1,4 +1,5 @@
 int mul( int a, int b )
 {
+    if ( a == 0 || b == 0 ) return 0;
     return a * b;
 }
"""
rows = [
    dict( org="fixtureorg", repo="fixturerepo", number=1, state="closed",
         title="Fix add() edge case", body="Fixes the zero case in add().",
         base=dict( label="fixtureorg:main", ref="main", sha=base_sha ),
         resolved_issues=[ dict( number=10, title="add() mishandles a zero operand",
                                 body="When calling add with a equal to zero the result is still "
                                      "computed via addition instead of a fast path; add() in "
                                      "src/foo.cpp should short-circuit." ) ],
         fix_patch=fix_patch_add, test_patch="", instance_id="fixtureorg__fixturerepo-1" ),
    dict( org="fixtureorg", repo="fixturerepo", number=2, state="closed",
         title="Fix mul() edge case", body="Fixes the zero case in mul().",
         base=dict( label="fixtureorg:main", ref="main", sha=base_sha ),
         resolved_issues=[ dict( number=11, title="mul() is slow when an operand is zero",
                                 body="mul() in src/bar.cpp should return zero immediately when "
                                      "either operand a or b is zero instead of multiplying." ) ],
         fix_patch=fix_patch_mul, test_patch="", instance_id="fixtureorg__fixturerepo-2" ),
    dict( org="fixtureorg", repo="fixturerepo", number=3, state="closed",
         title="Unlinked cleanup PR", body="No linked issue — internal refactor only.",
         base=dict( label="fixtureorg:main", ref="main", sha=base_sha ),
         resolved_issues=[], fix_patch=fix_patch_add, test_patch="",
         instance_id="fixtureorg__fixturerepo-3" ),
]
with open(out_path, "w") as f:
    for r in rows: f.write(json.dumps(r) + "\n")
PY

LOCK="$TMP/dataset.lock"
WORK1="$TMP/work1"
OUT1="$TMP/out1.json"
REPOMAP="fixtureorg/fixturerepo=$FIXREPO"

# ── (i) mining: offline, from the fixture raw dir ────────────────────────────────────────────────
LOG1="$TMP/run1.log"
RIPWIRE="$BIN" python3 "$HARNESS" \
    --languages cpp --lang cpp --offline --raw-dir "$TMP/raw" --repo-map "$REPOMAP" \
    --work-dir "$WORK1" --dataset-lock "$LOCK" --json-out "$OUT1" \
    >"$LOG1" 2>&1
rc1=$?
if [ $rc1 -eq 0 ] && [ -f "$LOCK" ]; then ok "harness completed rc=0, dataset.lock written"
else no "harness run 1 failed rc=$rc1 (see $LOG1)"; cat "$LOG1" >&2; fi

if [ -f "$LOCK" ]; then
    n=$( python3 -c "import json; print(json.load(open('$LOCK'))['selected_count']['cpp'])" 2>/dev/null )
    [ "$n" = "2" ] && ok "mined exactly 2 eligible instances (1 no-resolved-issue row excluded)" \
        || no "mined instance count = ${n:-?} (expected 2)"

    noissue=$( python3 -c "import json; print(json.load(open('$LOCK'))['mining_stats']['cpp']['no_resolved_issue'])" 2>/dev/null )
    [ "$noissue" = "1" ] && ok "mining_stats counts the excluded no-issue row (not a silent drop)" \
        || no "mining_stats.no_resolved_issue = ${noissue:-?} (expected 1)"

    python3 - "$LOCK" <<'PY' && ok "dataset.lock content_sha256 is self-consistent" || no "dataset.lock content hash mismatch"
import json, hashlib, sys
lock = json.load(open(sys.argv[1]))
all_inst = [i for insts in lock["instances_by_lang"].values() for i in insts]
canon = [dict(instance_id=i["instance_id"], base_sha=i["base_sha"], gold_files=i["gold_files"],
              query_sha256=hashlib.sha256(i["query"].encode("utf-8")).hexdigest())
         for i in sorted(all_inst, key=lambda x: x["instance_id"])]
blob = json.dumps(canon, sort_keys=True, separators=(",", ":")).encode("utf-8")
got = hashlib.sha256(blob).hexdigest()
sys.exit(0 if got == lock["content_sha256"] else 1)
PY

    # tampering must be REJECTED on the next run (fail-closed contract)
    python3 - "$LOCK" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
lock["instances_by_lang"]["cpp"][0]["gold_files"] = ["tampered.cpp"]
json.dump(lock, open(sys.argv[1], "w"))
PY
    RIPWIRE="$BIN" python3 "$HARNESS" \
        --languages cpp --lang cpp --offline --raw-dir "$TMP/raw" --repo-map "$REPOMAP" \
        --work-dir "$WORK1" --dataset-lock "$LOCK" >"$TMP/tamper.log" 2>&1
    trc=$?
    if [ $trc -ne 0 ] && grep -q "content hash mismatch" "$TMP/tamper.log"; then
        ok "tampered dataset.lock is rejected (fail-closed)"
    else no "tampered dataset.lock was NOT rejected (rc=$trc)"; fi
else
    no "dataset.lock missing — cannot check mining/tamper contract"
fi

# ── (ii) + (iii) offline checkout + scoring shape ────────────────────────────────────────────────
if [ -f "$OUT1" ]; then
    python3 - "$OUT1" <<'PY' && ok "JSON shows n_scored>0 with per-instance arm ranks (offline checkout+scoring ran)" \
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
    grep -q "license" "$OUT1" && ok "JSON records the dataset license" || no "JSON missing license field"
else
    no "missing $OUT1 — harness did not write JSON"
fi

# ── (iv) determinism x2 — rerun against the SAME frozen lock, compare modulo wall-clock ─────────────
RIPWIRE="$BIN" python3 "$HARNESS" \
    --languages cpp --lang cpp --offline --raw-dir "$TMP/raw" --repo-map "$REPOMAP" --refresh-dataset \
    --work-dir "$WORK1" --dataset-lock "$LOCK" --json-out "$OUT1" >"$TMP/run_a.log" 2>&1
WORK2="$TMP/work2"; OUT2="$TMP/out2.json"
RIPWIRE="$BIN" python3 "$HARNESS" \
    --languages cpp --lang cpp --offline --raw-dir "$TMP/raw" --repo-map "$REPOMAP" \
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

# ── offline contract: refuse to mine without a pre-populated raw dir ────────────────────────────────
EMPTYRAW="$TMP/empty-raw"; mkdir -p "$EMPTYRAW"
RIPWIRE="$BIN" python3 "$HARNESS" \
    --languages cpp --lang cpp --offline --raw-dir "$EMPTYRAW" --repo-map "$REPOMAP" \
    --work-dir "$TMP/work3" --dataset-lock "$TMP/nolock.lock" --refresh-dataset \
    >"$TMP/offlinefail.log" 2>&1
orc=$?
if [ $orc -ne 0 ] && grep -qi "pre-populate" "$TMP/offlinefail.log"; then
    ok "--offline with an empty --raw-dir refuses loudly (no silent empty-lock write)"
else no "--offline with empty --raw-dir did not fail as expected (rc=$orc)"; fi

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
