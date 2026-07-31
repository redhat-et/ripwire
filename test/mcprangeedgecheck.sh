#!/usr/bin/env bash
# mcprangeedgecheck.sh — MCP fetch_body partial-range EDGE CASES that mcpreloadcheck.sh (Wave-1's own gate)
# does not exercise: a single-line range (start_line==end_line), the exact partial=true/false boundary
# behavior, a range over a MULTIBYTE (UTF-8) symbol's body, and — the sharpest edge — that a STALE handle
# is refused BEFORE a range is even considered (the contentHash pin must be checked first, never bypassed
# by a client that only asks for a small slice).
#
# mcpreloadcheck.sh already covers: whole-range byte-match, end-clamp past EOF, start-OOB error, no-range
# backward-compat, a SEPARATE multibyte-body UTF-8 safety check (different fixture), and cross-process
# determinism. This gate is deliberately narrower and deeper on the cases that gate's own comment block
# does not claim to cover.
#
# Usage:
#   test/mcprangeedgecheck.sh
#   CTXPACK_BIN=asan/ctxpack test/mcprangeedgecheck.sh
#
# Exits non-zero on any failure. Every mutation happens on a scratch mktemp copy — the checked-in
# test/fixture is never modified. Does NOT edit regression.sh or any existing test file.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcprangeedgecheck: BIN=$BIN  FIX=$FIX"

mcp_call() { printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }
handle_of_symbol() {
    tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
print(json.loads(r["result"]["content"][0]["text"])["symbol"]["handle"])
'
}

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== setup: a pristine copy + a real handle for distance() (geometry.cpp lines 4-9, 6-line body) ==="
# ═══════════════════════════════════════════════════════════════════════════
WORK="$( mktemp -d "$TMP/work.XXXXXX" )"
cp -R "$FIX/"* "$WORK/"
GEO="$WORK/geometry.cpp"

H="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$WORK"'","symbol":"distance"}}}' \
    | handle_of_symbol )"
if ! printf '%s' "$H" | grep -Eq '^sym#[0-9a-f]{16}@[0-9a-f]{16}$'; then
    echo "could not obtain a handle for distance() (got '$H') — aborting"; exit 2
fi
ok "obtained distance() handle: $H"

fetch_range() {
    # $1=start $2=end (empty = omit end) → the body-JSON payload text, or __ERR__:code:msg
    local args
    if [ -n "${2:-}" ]; then args="\"start_line\":$1,\"end_line\":$2"; else args="\"start_line\":$1"; fi
    mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"fetch_body\",\"arguments\":{\"path\":\"$WORK\",\"handle\":\"$H\",$args}}}" \
        | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERR__:%d:%s" % (r["error"].get("code",0), r["error"].get("message","")))
else: print(r["result"]["content"][0]["text"])
'
}

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1. single-line range: start_line == end_line ==="
# ═══════════════════════════════════════════════════════════════════════════
# distance() body: 1='double distance( Point a, Point b )' 2='{' 3='const double dx...' ... 6='}'.
# start_line=end_line=3 must return EXACTLY file line 6 (the const dx line), partial=true.
SINGLE_JSON="$( fetch_range 3 3 )"
case "$SINGLE_JSON" in
    __ERR__*) no "single-line range 3..3 returned an error: $SINGLE_JSON";;
    *)
        echo "$SINGLE_JSON" | python3 -c '
import sys, json
b = json.load(sys.stdin)
print("body:%r" % b["body"])
print("META start=%d end=%d total=%d partial=%s" % (b["start_line"], b["end_line"], b["total_lines"], b["partial"]))
' > "$TMP/single_meta"
        cat "$TMP/single_meta"
        grep -q 'start=3 end=3' "$TMP/single_meta" && ok "single-line range reports start_line=3 end_line=3 (not silently widened)" || no "single-line range start/end wrong: $( cat "$TMP/single_meta" )"
        grep -q 'partial=True' "$TMP/single_meta" && ok "single-line range reports partial=true (it is a strict sub-range of a 6-line body)" || no "single-line range did not report partial=true"
        grep -q 'total=6' "$TMP/single_meta" && ok "single-line range reports the correct total_lines=6" || no "single-line range total_lines wrong: $( cat "$TMP/single_meta" )"
        # byte-match against the real source: body line 3 = file line 6.
        sed -n '6p' "$GEO" > "$TMP/single_truth"
        echo "$SINGLE_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["body"],end="")' > "$TMP/single_got"
        if [ "$( cat "$TMP/single_got" )" = "$( cat "$TMP/single_truth" )" ]; then
            ok "single-line range byte-matches source file line 6 exactly (no trailing/leading extra line)"
        else
            no "single-line range does not byte-match source line 6"
            echo "    got:   $( cat "$TMP/single_got" | tr '\n' '|' )"
            echo "    truth: $( cat "$TMP/single_truth" | tr '\n' '|' )"
        fi
    ;;
esac

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 2. partial=false boundary: a range that (after clamping) covers the WHOLE body ==="
# ═══════════════════════════════════════════════════════════════════════════
# distance() is 6 body-lines; requesting 1..6 explicitly (the full span, not omitted) must report
# partial=FALSE per the documented contract ("a range that covers the whole body is reported partial=false
# so callers can tell") — this is a sharper check than mcpreloadcheck's omitted-range case.
FULL_EXPLICIT_JSON="$( fetch_range 1 6 )"
case "$FULL_EXPLICIT_JSON" in
    __ERR__*) no "explicit full-range 1..6 returned an error: $FULL_EXPLICIT_JSON";;
    *) echo "$FULL_EXPLICIT_JSON" | python3 -c '
import sys, json
b = json.load(sys.stdin)
print("PARTIAL_FALSE" if b["partial"] == False else "PARTIAL_TRUE_WRONG")
' > "$TMP/fullexplicit_chk"
       grep -q PARTIAL_FALSE "$TMP/fullexplicit_chk" && ok "explicit 1..6 range (== the whole 6-line body) reports partial=false" || no "explicit full-span range incorrectly reports partial=true"
    ;;
esac
# and a range that OVER-REQUESTS past the end but clamps down to exactly the whole body (1..999) is ALSO
# partial=false (clamping to the full span, not a strict sub-range).
FULL_CLAMP_JSON="$( fetch_range 1 999 )"
case "$FULL_CLAMP_JSON" in
    __ERR__*) no "over-request 1..999 returned an error: $FULL_CLAMP_JSON";;
    *) echo "$FULL_CLAMP_JSON" | python3 -c '
import sys, json
b = json.load(sys.stdin)
print("PARTIAL_FALSE" if b["partial"] == False and b["end_line"] == b["total_lines"] else "WRONG:%s/%d/%d" % (b["partial"], b["end_line"], b["total_lines"]))
' > "$TMP/fullclamp_chk"
       grep -q PARTIAL_FALSE "$TMP/fullclamp_chk" && ok "1..999 clamps to the whole body AND reports partial=false" || no "1..999 clamp/partial wrong: $( cat "$TMP/fullclamp_chk" )"
    ;;
esac

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 3. range over a MULTIBYTE-symbol body, on a range that STOPS mid-multibyte-content ==="
# ═══════════════════════════════════════════════════════════════════════════
# A function whose body-relative line 2 contains a 4-byte emoji codepoint; request JUST that line (2..2)
# and confirm it is intact (not split, not U+FFFD) AND that a NEIGHBORING plain-ASCII line pinned in the
# same request is excluded correctly (proving the boundary is exact, not off-by-one into the emoji line).
UTF="$( mktemp -d "$TMP/utf.XXXXXX" )"
python3 - "$UTF/uni.py" <<'PY'
import sys
src = (
    "def greet():\n"                        # body line 1
    "    rocket = '\U0001F680'\n"            # body line 2 — 4-byte emoji codepoint
    "    return rocket\n"                    # body line 3
)
open(sys.argv[1], "w", encoding="utf-8").write(src)
PY
UH="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$UTF"'","symbol":"greet"}}}' \
    | handle_of_symbol )"
if ! printf '%s' "$UH" | grep -Eq '^sym#[0-9a-f]{16}@[0-9a-f]{16}$'; then
    no "could not obtain a handle for greet() (got '$UH') — skipping multibyte-symbol range check"
else
    mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"fetch_body\",\"arguments\":{\"path\":\"$UTF\",\"handle\":\"$UH\",\"start_line\":2,\"end_line\":2}}}" \
        | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
b = json.loads(r["result"]["content"][0]["text"])
body = b["body"]
has_rocket = "\U0001F680" in body
no_repl    = "�" not in body
no_leak    = ("def greet" not in body) and ("return rocket" not in body)   # neighboring lines excluded
print("UTF_LINE_OK" if (has_rocket and no_repl and no_leak) else "UTF_LINE_BAD rocket=%s norepl=%s noleak=%s body=%r" % (has_rocket, no_repl, no_leak, body))
' > "$TMP/utfline_chk"
    grep -q UTF_LINE_OK "$TMP/utfline_chk" && ok "range 2..2 over a multibyte-symbol body returns exactly the emoji line, intact, neighbors excluded" || no "multibyte single-line range failed: $( cat "$TMP/utfline_chk" )"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 4. STALE handle + a range request: the contentHash pin refuses BEFORE any range is considered ==="
# ═══════════════════════════════════════════════════════════════════════════
# Take the ALREADY-obtained handle H (minted against the pristine geometry.cpp), then edit the file so the
# file's content hash no longer matches WITHOUT renaming distance() itself (a rename would make the symbol
# unresolvable and hit a DIFFERENT refusal path — "no current symbol" — rather than the contentHash-mismatch
# path this check targets). Adding a harmless comment line changes the file's byte hash while distance()
# still resolves as a symbol, isolating the exact refusal this check is about. A range fetch on the now-
# stale handle MUST refuse with the stale/content-changed error — never silently apply the range to
# whatever the shifted new bytes happen to contain.
python3 - "$GEO" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
b2 = b"// a harmless comment that only changes the file's byte hash\n" + b
assert b2 != b
open(p, "wb").write(b2)
PY
STALE_RANGE_JSON="$( fetch_range 1 2 )"
case "$STALE_RANGE_JSON" in
    __ERR__:-32602:*chang*) ok "stale handle + range request refused with -32602 mentioning the file changed (range never applied to a stale handle): ${STALE_RANGE_JSON#__ERR__:-32602:}";;
    __ERR__:-32602:*)       no "stale handle + range refused with -32602 but the message does not mention the file changing (may be the wrong refusal reason): $STALE_RANGE_JSON";;
    __ERR__*)               no "stale handle + range refused with the WRONG error code (want -32602/stale): $STALE_RANGE_JSON";;
    *)                      no "stale handle + range request returned a BODY instead of refusing — the staleness pin was bypassed by the range path: $( echo "$STALE_RANGE_JSON" | head -c 150 )";;
esac

# control: the SAME stale handle with NO range ALSO refuses (proves the range path is not the only thing
# that got the staleness check right — the underlying pin is what's shared, not a per-path duplicate).
STALE_FULL_JSON="$( fetch_range "" "" )"
STALE_FULL_JSON2="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"fetch_body\",\"arguments\":{\"path\":\"$WORK\",\"handle\":\"$H\"}}}" \
    | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERR__:%d:%s" % (r["error"]["code"], r["error"]["message"]) if "error" in r else "NO_ERROR")
' )"
case "$STALE_FULL_JSON2" in
    __ERR__:-32602:*) ok "control: the same stale handle with NO range also refuses with -32602 (staleness check is shared, not range-path-specific)";;
    *) no "control: stale handle with no range did not refuse as expected: $STALE_FULL_JSON2";;
esac

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism: the single-line range result is byte-identical across two fresh processes ==="
# ═══════════════════════════════════════════════════════════════════════════
FRESH="$( mktemp -d "$TMP/fresh.XXXXXX" )"; cp -R "$FIX/"* "$FRESH/"
FH="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$FRESH"'","symbol":"distance"}}}' \
    | handle_of_symbol )"
DET_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$FRESH"'","handle":"'"$FH"'","start_line":3,"end_line":3}}}'
)
mcp_call "${DET_MSGS[@]}" > "$TMP/det_a"
mcp_call "${DET_MSGS[@]}" > "$TMP/det_b"
diff -q "$TMP/det_a" "$TMP/det_b" >/dev/null \
    && ok "single-line range fetch byte-identical across two independent server processes" \
    || no "single-line range fetch differs across processes"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION: prove the partial=true/false + staleness assertions are load-bearing ==="
# ═══════════════════════════════════════════════════════════════════════════
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        if grep -q PARTIAL_TRUE_WRONG "$TMP/fullexplicit_chk" 2>/dev/null; then no; else
            # force the mutation: assert the explicit full range should be partial=TRUE (it is really false)
            if echo "$FULL_EXPLICIT_JSON" | python3 -c 'import sys,json;b=json.load(sys.stdin);sys.exit(0 if b["partial"]==True else 1)' 2>/dev/null; then ok; else no; fi
        fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (asserting the full-span range is partial=true when it is really false correctly fails)" \
                       || no "mutation self-test broke — the partial=false boundary assertion is not live"

# mutation: assert the stale response is NOT an error (it really is one) — this must be detected as wrong.
IS_ERR=0
case "$STALE_RANGE_JSON" in
    __ERR__*) IS_ERR=1;;
esac
MUT2="$( ok(){ :; }; no(){ echo TRIPPED; }
        if [ "$IS_ERR" = "0" ]; then ok; else no; fi )"
[ "$MUT2" = "TRIPPED" ] && ok "mutation self-test (asserting the stale-handle response is NOT an error, when it really is, correctly fails)" \
                        || no "mutation self-test broke — the staleness-refusal assertion is not live"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
