#!/usr/bin/env bash
# mcpreloadcheck.sh — gate for the two MCP-server improvements:
#
#   FEATURE 1 — proactive freshness (codanna hot-reload, adapted deterministically). The --mcp server keeps a
#     warm in-memory index. A kqueue FS-event watcher over the (denylist-pruned) directory set marks the index
#     dirty on any structural change (add/delete/rename), so the NEXT verb rebuilds WITHOUT a manual restart and
#     WITHOUT the directory stat-sweep on the common no-change path; content-only edits are ALWAYS caught by the
#     retained per-file mtime+size sweep (never gated by the watcher — the S1 authority). The watcher only elides
#     work it has itself covered (structural changes): RESULT bytes stay a pure function of tree state, byte-
#     identical run-to-run and across two processes, no clock/TTL involved. Degrades to the pre-feature full
#     stat-sweep if kqueue is unavailable. (Determinism argument + design: FsWatcher / getIndex / mcpStale.)
#
#   FEATURE 2 — partial-range fetch_body (octocode). fetch_body{handle, start_line?, end_line?} returns only
#     PART of a large body — 1-based, INCLUSIVE, BODY-RELATIVE line bounds (line 1 = the def's first line).
#     Clamped to the def's span (end past EOF clamps down; start past EOF → clear out-of-range error, never OOB),
#     UTF-8-safe (slices on line boundaries → never splits a codepoint), deterministic. The handle contentHash
#     staleness pin still applies. Result reports start_line/end_line/total_lines/partial.
#
# What this gate drives (mirrors mcpstalecheck's long-lived-server-over-FIFO edit technique + mcphandlecheck's
# handle plumbing):
#   1. STRUCTURAL hot-reload: warm the index, ADD a new source file, the next verb resolves its new symbol
#      (kqueue event → rebuild, no restart).
#   2. CONTENT-EDIT hot-reload in the SAME server: rename a symbol (content edit), the next verb reflects it
#      (the always-run per-file mtime+size sweep catches it — no restart).
#   3. fetch_body range: lines L..M byte-match the exact source lines of the def.
#   4. out-of-range start_line → a clean -32602 error, no body (never OOB).
#   5. UTF-8 safety: a range over a def containing multibyte characters returns a valid-UTF-8 slice that does
#      not split a codepoint, and byte-matches the intended source lines.
#   6. two-process determinism: two independent servers give byte-identical range output.
#   7. every response line is valid JSON.
#
# Mutation-tested (each mutation FAILS a specific step — proven against scratch binaries):
#   • make mcpStale() never report stale (never rebuild) → steps 1a/1b + the stamp check FAIL (no hot-reload).
#   • ignore start_line/end_line in fetch_body (always full body) → step 3 FAILS (whole body != the L..M slice).
#   • slice on BYTES instead of line boundaries → step 5's UTF-8 assertion FAILS (codepoints split).
#   • do not clamp / do not error on an out-of-range start_line → step 4 FAILS.
#
# Usage:
#   test/mcpreloadcheck.sh
#   CTXPACK_BIN=asan/ctxpack test/mcpreloadcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. NEVER edits the checked-in
# fixture — every mutation happens on a scratch COPY in a mktemp dir. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpreloadcheck: BIN=$BIN  FIX=$FIX"

# ─── helpers shared across sections ───────────────────────────────────────────────────────────────
# send a batch of JSON-RPC lines to a FRESH server, print all output lines.
mcp_call() { printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }

# extract the tools/call inner text (or __ERROR__:msg) for a given id from a server output file.
inner_for_id() {
    grep -E "\"id\":$2[,}]" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERROR__:" + r["error"].get("message",""))
else:            print(r["result"]["content"][0]["text"])
'
}
stamp_for_id() {
    grep -E "\"id\":$2[,}]" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin); print(r.get("result",{}).get("_index",""))
'
}
wait_for_id() {
    local i
    for i in $( seq 1 200 ); do
        grep -Eq "\"id\":$2[,}]" "$1" 2>/dev/null && return 0
        sleep 0.05
    done
    return 1
}
# the `handle` of the top-level symbol from a single find_symbol response line on stdin.
handle_of_symbol() {
    tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
print(json.loads(r["result"]["content"][0]["text"])["symbol"]["handle"])
'
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== FEATURE 1: hot-reload in a long-lived server (no restart) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
WORK="$( mktemp -d "$TMP/work.XXXXXX" )"
cp -R "$FIX/"* "$WORK/"

FIFO="$WORK/in.fifo"; mkfifo "$FIFO"
"$BIN" --mcp <"$FIFO" >"$WORK/out.txt" 2>/dev/null &
SRV=$!
exec 9>"$FIFO"

printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&9
# warm the index + probe two symbols that DON'T exist yet.
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"reloadAddedSym\"}}}" >&9
# also grab a stamp on a symbol that exists both before and after (perimeter) to prove the stamp moves.
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"perimeter\"}}}" >&9
wait_for_id "$WORK/out.txt" 2 || no "server never answered the warm-up read verb (id=2)"
wait_for_id "$WORK/out.txt" 20 || no "server never answered the warm-up stamp probe (id=20)"
STAMP_BEFORE="$( stamp_for_id "$WORK/out.txt" 20 )"

case "$( inner_for_id "$WORK/out.txt" 2 )" in
    __ERROR__*) ok "warm-up: 'reloadAddedSym' correctly absent before the add";;
    *)          no "warm-up: 'reloadAddedSym' unexpectedly present before the add";;
esac

# --- 1a. STRUCTURAL change: add a NEW source file (kqueue dir NOTE_WRITE → eager rebuild) ---
cat > "$WORK/reloadmod.cpp" <<'EOF'
int reloadAddedSym() { return 7; }
EOF
sleep 0.15   # allow the dir-mtime + kqueue event to settle (still well within a normal round-trip)
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"reloadAddedSym\"}}}" >&9
wait_for_id "$WORK/out.txt" 3 || no "server never answered the post-add read verb (id=3)"
case "$( inner_for_id "$WORK/out.txt" 3 )" in
    __ERROR__*) no "post-add: 'reloadAddedSym' STILL not found — the watcher/sweep did not trigger a rebuild (no hot-reload)";;
    *reloadmod.cpp*) ok "post-add: new file's symbol resolves WITHOUT a restart (hot-reload works)";;
    *)          ok "post-add: 'reloadAddedSym' resolves — hot-reload works";;
esac

# --- 1b. CONTENT edit in the SAME server: rename an existing symbol (caught by the always-run file sweep) ---
python3 - "$WORK/geometry.cpp" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
b2 = b.replace(b"double distance(", b"double distanceRENAMED(")
assert b2 != b, "content must actually change"
open(p, "wb").write(b2)
PY
sleep 0.1    # let the write settle; the per-file mtime+size sweep runs on the very next verb (no TTL)
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"distanceRENAMED\"}}}" >&9
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"perimeter\"}}}" >&9
wait_for_id "$WORK/out.txt" 4  || no "server never answered the post-content-edit read verb (id=4)"
wait_for_id "$WORK/out.txt" 21 || no "server never answered the post-content-edit stamp probe (id=21)"

exec 9>&-
wait "$SRV" 2>/dev/null

case "$( inner_for_id "$WORK/out.txt" 4 )" in
    __ERROR__*) no "post-content-edit: 'distanceRENAMED' not found — the content edit was not picked up (stale index)";;
    *)          ok "post-content-edit: renamed symbol resolves WITHOUT a restart (content-edit hot-reload works)";;
esac
STAMP_AFTER="$( stamp_for_id "$WORK/out.txt" 21 )"
if [ -n "$STAMP_BEFORE" ] && [ "$STAMP_BEFORE" != "$STAMP_AFTER" ]; then
    ok "_index stamp moved across the reload ('$STAMP_BEFORE' -> '$STAMP_AFTER')"
else
    no "_index stamp did NOT change across the reload (before='$STAMP_BEFORE' after='$STAMP_AFTER')"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== FEATURE 2: partial-range fetch_body ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# Use a PRISTINE copy so the perimeter def matches the checked-in source exactly.
RANGE="$( mktemp -d "$TMP/range.XXXXXX" )"
cp -R "$FIX/"* "$RANGE/"
GEO="$RANGE/geometry.cpp"

FIND_PERIM=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$RANGE"'","symbol":"perimeter"}}}'
)
H="$( mcp_call "${FIND_PERIM[@]}" | handle_of_symbol )"
if ! printf '%s' "$H" | grep -Eq '^sym#[0-9a-f]{16}@[0-9a-f]{16}$'; then
    no "could not obtain a valid handle for perimeter (got '$H') — aborting range checks"
    echo; echo "SOME CHECKS FAILED"; exit 1
fi
ok "obtained perimeter handle: $H"

fetch_range() {
    # $1=start $2=end  → prints the body JSON payload text (or __ERR__:code:msg) to stdout.
    local args
    if [ -n "$2" ]; then args="\"start_line\":$1,\"end_line\":$2"; else args="\"start_line\":$1"; fi
    mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"fetch_body\",\"arguments\":{\"path\":\"$RANGE\",\"handle\":\"$H\",$args}}}" \
        | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    e = r["error"]; print("__ERR__:%d:%s" % (e.get("code"), e.get("message","")))
else:
    print(r["result"]["content"][0]["text"])
'
}

# --- 3. lines L..M byte-match the exact source lines of the def ---
# perimeter spans lines 11..19 in geometry.cpp (1-based file lines). Body line 1 = file line 11.
# Body lines 3..5 = file lines 13..15. Compare the fetched slice against sed of those file lines.
echo
echo "--- 3. fetch_body lines 3..5 byte-match the source ---"
SLICE_JSON="$( fetch_range 3 5 )"
case "$SLICE_JSON" in
    __ERR__*) no "range 3..5 returned an error: $SLICE_JSON";;
    *)
        echo "$SLICE_JSON" | python3 -c 'import sys,json;b=json.load(sys.stdin);open(sys.argv[1],"w").write(b["body"]);print("PARTIAL" if b["partial"] else "FULL", "start",b["start_line"],"end",b["end_line"])' "$TMP/slice_got" > "$TMP/slice_meta"
        # truth: def starts at the perimeter signature line; body lines 3..5 = def start line + (2..4).
        DEFLINE="$( grep -n '^double perimeter(' "$GEO" | head -1 | cut -d: -f1 )"
        A=$(( DEFLINE + 2 )); B=$(( DEFLINE + 4 ))
        sed -n "${A},${B}p" "$GEO" > "$TMP/slice_truth"
        if [ "$( cat "$TMP/slice_got" )" = "$( cat "$TMP/slice_truth" )" ]; then
            ok "range 3..5 byte-matches source lines $A..$B ($( cat "$TMP/slice_meta" ))"
        else
            no "range 3..5 != source"
            echo "    got:   $( cat "$TMP/slice_got"  | tr '\n' '|' )"
            echo "    truth: $( cat "$TMP/slice_truth" | tr '\n' '|' )"
        fi
        grep -q PARTIAL "$TMP/slice_meta" && ok "range 3..5 reports partial=true" || no "range 3..5 did not report partial=true"
    ;;
esac

# --- end clamp: end_line past EOF clamps down (not an error) ---
echo
echo "--- 3b. end_line past EOF clamps down to the last line (no error) ---"
CLAMP_JSON="$( fetch_range 8 999 )"
case "$CLAMP_JSON" in
    __ERR__*) no "end-clamp range 8..999 errored: $CLAMP_JSON";;
    *) echo "$CLAMP_JSON" | python3 -c '
import sys, json
b = json.load(sys.stdin)
# end_line must clamp to total_lines, and start must stay 8
print("CLAMP_OK" if (b["end_line"] == b["total_lines"] and b["start_line"] == 8) else "CLAMP_BAD:%d/%d" % (b["end_line"], b["total_lines"]))
' > "$TMP/clampchk"
       grep -q CLAMP_OK "$TMP/clampchk" && ok "end_line=999 clamped to the last line" || no "end clamp wrong: $( cat "$TMP/clampchk" )";;
esac

# --- 4. start_line past EOF → clean -32602 error, no body ---
echo
echo "--- 4. out-of-range start_line → clean error, no body ---"
OOB_JSON="$( fetch_range 999 "" )"
case "$OOB_JSON" in
    __ERR__:-32602:*) ok "out-of-range start_line=999 refused with -32602 (no body): ${OOB_JSON#__ERR__:-32602:}";;
    __ERR__*)         no "out-of-range returned the WRONG error code: $OOB_JSON";;
    *)                no "out-of-range start_line=999 returned a BODY instead of an error (OOB risk): $( echo "$OOB_JSON" | head -c 100 )";;
esac

# --- backward-compat: no range → whole body, partial=false ---
echo
echo "--- 4b. no range → whole body (backward-compatible) ---"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"fetch_body\",\"arguments\":{\"path\":\"$RANGE\",\"handle\":\"$H\"}}}" \
    | tail -1 | python3 -c '
import sys, json
b = json.loads(json.load(sys.stdin)["result"]["content"][0]["text"])
print("FULL_OK" if (b["partial"] == False and b["start_line"] == 1 and b["end_line"] == b["total_lines"]) else "FULL_BAD")
' > "$TMP/fullchk"
grep -q FULL_OK "$TMP/fullchk" && ok "no-range fetch returns the whole body, partial=false" || no "no-range fetch regressed: $( cat "$TMP/fullchk" )"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== FEATURE 2: UTF-8-safe range slicing on a multibyte fixture ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# A scratch corpus with a function whose body contains multibyte UTF-8 (accents, CJK, emoji) on distinct lines.
UTF="$( mktemp -d "$TMP/utf.XXXXXX" )"
python3 - "$UTF/uni.py" <<'PY'
import sys
# body-relative lines: 1=def, 2=café, 3=CJK, 4=emoji, 5=return  → slicing 2..4 must be valid UTF-8.
src = (
    "def greet():\n"
    "    a = 'café naïve'   # Latin-1 accents\n"
    "    b = '你好世界'      # CJK\n"
    "    c = '\U0001F600\U0001F680'          # emoji (4-byte codepoints)\n"
    "    return a + b + c\n"
)
open(sys.argv[1], "w", encoding="utf-8").write(src)
PY
UH="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$UTF"'","symbol":"greet"}}}' \
    | handle_of_symbol )"
if ! printf '%s' "$UH" | grep -Eq '^sym#[0-9a-f]{16}@[0-9a-f]{16}$'; then
    no "could not obtain a handle for greet() (got '$UH') — skipping UTF-8 check"
else
    mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"fetch_body\",\"arguments\":{\"path\":\"$UTF\",\"handle\":\"$UH\",\"start_line\":2,\"end_line\":4}}}" \
        | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
b = json.loads(r["result"]["content"][0]["text"])
body = b["body"]
# 1. it must be valid UTF-8 (json.loads already decoded it; re-encode to be sure it round-trips cleanly).
try:
    body.encode("utf-8")
    valid = True
except Exception:
    valid = False
# 2. it must contain the multibyte characters intact (no split codepoint / no U+FFFD replacement).
intact = ("café" in body) and ("你好世界" in body) and ("\U0001F600\U0001F680" in body)
norepl = "�" not in body
open(sys.argv[1], "w", encoding="utf-8").write(body)
print("UTF8_OK" if (valid and intact and norepl) else "UTF8_BAD valid=%s intact=%s norepl=%s" % (valid, intact, norepl))
' "$TMP/utf_got" > "$TMP/utfchk"
    grep -q UTF8_OK "$TMP/utfchk" && ok "range over multibyte body is valid UTF-8, codepoints intact, no U+FFFD" || no "UTF-8 range unsafe: $( cat "$TMP/utfchk" )"
    # cross-check the fetched slice byte-matches source lines 2..4 of the file.
    sed -n '2,4p' "$UTF/uni.py" > "$TMP/utf_truth"
    if [ "$( cat "$TMP/utf_got" )" = "$( cat "$TMP/utf_truth" )" ]; then
        ok "multibyte slice byte-matches source lines 2..4"
    else
        no "multibyte slice != source lines 2..4"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== two-process determinism + valid-JSON ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
DET_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$RANGE"'","handle":"'"$H"'","start_line":2,"end_line":6}}}'
)
mcp_call "${DET_MSGS[@]}" > "$TMP/det_a"
mcp_call "${DET_MSGS[@]}" > "$TMP/det_b"
diff -q "$TMP/det_a" "$TMP/det_b" >/dev/null \
    && ok "range fetch byte-identical across two independent server processes" \
    || no "range fetch differs across processes"

python3 -c '
import sys, json
bad = 0
for i, ln in enumerate(open(sys.argv[1]), 1):
    ln = ln.strip()
    if not ln: continue
    try: json.loads(ln)
    except Exception as e: print("LINE", i, "INVALID:", e); bad += 1
print("JSON_OK" if bad == 0 else "JSON_BAD:" + str(bad))
' "$TMP/det_a" > "$TMP/jchk"
grep -q JSON_OK "$TMP/jchk" && ok "all response lines are valid JSON" || no "$( grep -v JSON_OK "$TMP/jchk" )"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
