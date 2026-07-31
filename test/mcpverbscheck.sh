#!/usr/bin/env bash
# mcpverbscheck.sh — gate for the `for` and `owners` MCP verbs, plus (§6, L4) the
# explore/pack_task/from_trace/edit_check B11-verb-parity MCP twins.
#
# Drives the MCP server via newline-delimited JSON-RPC over stdin, just like
# the existing situdiffcheck.sh gate.  Flow:
#   1. initialize
#   2. tools/list → assert `for` and `owners` appear in the tool listing
#   3. tools/call for  {path, task} → assert non-empty text result containing <sigs>
#   4. tools/call owners {path}     → assert valid owners XML (uses a synthetic git repo)
#   5. Determinism: call sequences 3 and 4 each run twice and produce byte-identical output.
#   6. L4: tools/list shows 30 verbs (`pack_task` dispatch-only, not separately advertised);
#      `explore` round-trips a pack-task-shaped bundle and is byte-identical to `pack_task`;
#      `from_trace` maps a fixture trace onto zoomfix's appMain; `edit_check` returns the
#      contract shape and refuses an unknown symbol; each of explore/pack_task/from_trace/
#      edit_check gives its own per-verb "missing required field" message (D3 convention).
#
# The owners call needs a real git repo with commit history so gitFileAuthors() has
# something to mine.  We reuse the same synthetic-repo construction pattern as
# ownerscheck.sh (two source files, controlled commits).
#
# The `for`/L4 calls use the zoomfix fixture corpus (the same one situdiffcheck uses) so
# we don't need to create extra fixtures.
#
# Usage:
#   test/mcpverbscheck.sh                          # uses build/ctxpack
#   CTXPACK_BIN=asan/ctxpack test/mcpverbscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/zoomfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpverbscheck: BIN=$BIN  CORPUS=$CORPUS"

# ─── helpers ─────────────────────────────────────────────────────────────────

# Send JSON-RPC messages to the MCP server; print all output lines.
mcp_call() {
    printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null
}

# ─── 1. Build a synthetic git repo for owners tests ──────────────────────────
REPO="$TMP/testrepo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "setup@x.com"
git -C "$REPO" config user.name  "Setup"

cat >"$REPO/file1.cpp" <<'EOF'
// file1.cpp — minimal parseable C++
void hello() {}
void world() { hello(); }
EOF

cat >"$REPO/file2.cpp" <<'EOF'
// file2.cpp — another minimal parseable C++
void alpha() {}
void beta() { alpha(); }
EOF

commit_file() {
    local file="$1" name="$2" email="$3" ts="$4" msg="$5"
    git -C "$REPO" add "$file"
    GIT_AUTHOR_NAME="$name"    GIT_AUTHOR_EMAIL="$email"    GIT_AUTHOR_DATE="$ts" \
    GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" GIT_COMMITTER_DATE="$ts" \
        git -C "$REPO" commit -q -m "$msg"
}

# file1.cpp: 5 recent commits by alice (recent = within last 30 days)
for i in 1 2 3 4 5; do
    echo "// alice $i" >>"$REPO/file1.cpp"
    commit_file file1.cpp "Alice" "alice@x.com" "2026-06-0${i}T12:00:00" "file1 alice $i"
done

# file2.cpp: 2 commits each from alice and bob (even split)
for i in 1 2; do
    echo "// alice f2 $i" >>"$REPO/file2.cpp"
    commit_file file2.cpp "Alice" "alice@x.com" "2026-06-1${i}T12:00:00" "file2 alice $i"
    echo "// bob f2 $i" >>"$REPO/file2.cpp"
    commit_file file2.cpp "Bob" "bob@x.com" "2026-06-1${i}T13:00:00" "file2 bob $i"
done

echo
echo "=== 2. tools/list — assert 'for' and 'owners' appear ==="

LIST_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )"

# Extract tool names from the JSON response using python3
python3 -c '
import sys, json
resp = json.loads('"'"''"'"' + sys.argv[1] + '"'"''"'"')
if "error" in resp:
    print("ERROR:" + json.dumps(resp["error"]))
    sys.exit(0)
names = [t["name"] for t in resp["result"]["tools"]]
has_for    = "for"    in names
has_owners = "owners" in names
print("FOR_OK"    if has_for    else "MISSING:for")
print("OWNERS_OK" if has_owners else "MISSING:owners")
print("NAMES:" + ",".join(names))
' "$LIST_OUT" >"$TMP/list_check"

if grep -q "FOR_OK" "$TMP/list_check"; then
    ok "tools/list: 'for' tool is listed"
else
    no "tools/list: 'for' tool is MISSING from listing"
fi

if grep -q "OWNERS_OK" "$TMP/list_check"; then
    ok "tools/list: 'owners' tool is listed"
else
    no "tools/list: 'owners' tool is MISSING from listing"
fi

echo
echo "=== 3. tools/call 'for' — task lens against zoomfix corpus ==="

FOR_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$CORPUS"'","task":"engine scheduling run loop"}}}'
)

mcp_call "${FOR_MSGS[@]}" >"$TMP/for_a"
mcp_call "${FOR_MSGS[@]}" >"$TMP/for_b"

# Extract inner text from the tools/call response (id=2, last line)
FOR_INNER="$( tail -1 "$TMP/for_a" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + json.dumps(r["error"]))
else:
    print(r["result"]["content"][0]["text"])
' )"

case "$FOR_INNER" in
    __ERROR__*) no "for verb returned error: ${FOR_INNER#__ERROR__:}";;
    "")         no "for verb: inner text is empty";;
    *)          ok "for verb: returned non-empty text result";;
esac

# Assert the result contains <sigs> — the core element that packSignatures emits
if echo "$FOR_INNER" | grep -q "<sigs>"; then
    ok "for verb: result contains <sigs> element"
else
    no "for verb: result does NOT contain <sigs> — got: $( echo "$FOR_INNER" | head -c 200 )"
fi

# A3-F1 gate: <sigs> must carry an actual signature PAYLOAD — at least one <f> file bucket holding a
# <d> declaration block. The 0-budget sentinel bug emitted a bare <sigs></sigs> (rank/fanIn computed,
# then discarded by the immediate budget break), and the presence-only grep above still passed.
if echo "$FOR_INNER" | grep -q "<sigs><f " && echo "$FOR_INNER" | grep -q "<d "; then
    ok "for verb: <sigs> is NON-EMPTY (has <f>/<d> signature blocks — A3-F1)"
else
    no "for verb: <sigs> is EMPTY (no <f>/<d> payload — A3-F1 0-budget sentinel) — got: $( echo "$FOR_INNER" | head -c 200 )"
fi

# Assert the result wraps in <ctx>
# §B1.7 (2026-07-29): the ctx root now carries task=/route= attributes (verbatim task echo) — match the
# element opening, not the old bare "<ctx>" spelling.
if echo "$FOR_INNER" | grep -qE "<ctx( |>)"; then
    ok "for verb: result wrapped in <ctx>"
else
    no "for verb: result missing <ctx> wrapper"
fi

# Determinism: two runs byte-identical
diff -q "$TMP/for_a" "$TMP/for_b" >/dev/null \
    && ok "for verb: deterministic (byte-identical across two MCP calls)" \
    || no "for verb: non-deterministic response"

echo
echo "=== 4. tools/call 'owners' — bus-factor on synthetic git repo ==="

OWNERS_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"owners","arguments":{"path":"'"$REPO"'"}}}'
)

mcp_call "${OWNERS_MSGS[@]}" >"$TMP/owners_a"
mcp_call "${OWNERS_MSGS[@]}" >"$TMP/owners_b"

OWNERS_INNER="$( tail -1 "$TMP/owners_a" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + json.dumps(r["error"]))
else:
    print(r["result"]["content"][0]["text"])
' )"

case "$OWNERS_INNER" in
    __ERROR__*) no "owners verb returned error: ${OWNERS_INNER#__ERROR__:}";;
    "")         no "owners verb: inner text is empty";;
    *)          ok "owners verb: returned non-empty text result";;
esac

# Assert the result contains <owners — the XML tag emitted by gitFileAuthors output path
if echo "$OWNERS_INNER" | grep -q "<owners"; then
    ok "owners verb: result contains <owners> element"
else
    no "owners verb: result does NOT contain <owners> element — got: $( echo "$OWNERS_INNER" | head -c 200 )"
fi

# Assert at least one <f element (file ownership entry)
if echo "$OWNERS_INNER" | grep -q "<f "; then
    ok "owners verb: result contains at least one <f> file entry"
else
    no "owners verb: no <f> file entries found"
fi

# Determinism: two runs byte-identical
diff -q "$TMP/owners_a" "$TMP/owners_b" >/dev/null \
    && ok "owners verb: deterministic (byte-identical across two MCP calls)" \
    || no "owners verb: non-deterministic response"

echo
echo "=== 5. Existing verbs still work (regression sanity) ==="

# Quick smoke-test: `analyze` on the zoomfix corpus returns a result, not an error.
ANALYZE_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"analyze","arguments":{"path":"'"$CORPUS"'"}}}' | tail -1 )"

python3 -c '
import sys, json
r = json.loads(sys.argv[1])
print("OK" if "result" in r and "error" not in r else "ERROR:" + json.dumps(r.get("error",{})))
' "$ANALYZE_OUT" >"$TMP/analyze"
[ "$( cat "$TMP/analyze" )" = "OK" ] \
    && ok "existing 'analyze' verb still works" \
    || no "existing 'analyze' verb broken: $( cat "$TMP/analyze" )"

# Unknown tool still returns -32602.
UNKNOWN_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"no_such_tool","arguments":{"path":"'"$CORPUS"'"}}}' | tail -1 )"

python3 -c '
import sys, json
r = json.loads(sys.argv[1])
code = r.get("error", {}).get("code", 0)
print("OK" if code == -32602 else "GOT:" + str(code))
' "$UNKNOWN_OUT" >"$TMP/unknown"
[ "$( cat "$TMP/unknown" )" = "OK" ] \
    && ok "unknown tool still returns -32602" \
    || no "unknown tool did not return -32602: $( cat "$TMP/unknown" )"

echo
echo "=== 6. L4 — explore/pack_task/from_trace/edit_check (B11 verb parity) ==="

# ── tools/list shows 30 verbs, including the L4 three and the field-notes four ───────────────
LIST_OUT2="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )"
l4_field() {   # l4_field <python-expr-over-`names`> — one value per call (no bash arrays; macOS bash 3.2 has no mapfile)
    python3 -c '
import sys, json
r = json.loads(sys.argv[1])
names = [t["name"] for t in r["result"]["tools"]]
print(eval(sys.argv[2]))
' "$LIST_OUT2" "$1"
}
L4_COUNT="$(  l4_field 'len(names)' )"
L4_EXPLORE="$( l4_field '"explore" in names' )"
L4_TRACE="$(  l4_field '"from_trace" in names' )"
L4_EDITCHK="$( l4_field '"edit_check" in names' )"
L4_PACKTASK="$( l4_field '"pack_task" in names' )"   # dispatch-only alias — NOT separately advertised in tools/list
L4_WHEREIS="$( l4_field '"whereis" in names' )"
L4_STRAY="$(   l4_field '"stray_content" in names' )"
L4_FLAGS="$(   l4_field '"flags" in names' )"
L4_DDRIFT="$( l4_field '"doc_drift" in names' )"
[ "$L4_COUNT" = "30" ]     && ok "tools/list shows exactly 30 verbs" || no "tools/list shows $L4_COUNT verbs, expected 30"
[ "$L4_DDRIFT" = "True" ]  && ok "tools/list includes 'doc_drift'"     || no "tools/list is missing 'doc_drift'"
[ "$L4_WHEREIS" = "True" ] && ok "tools/list includes 'whereis'"       || no "tools/list is missing 'whereis'"
[ "$L4_STRAY" = "True" ]   && ok "tools/list includes 'stray_content'" || no "tools/list is missing 'stray_content'"
[ "$L4_FLAGS" = "True" ]   && ok "tools/list includes 'flags'"         || no "tools/list is missing 'flags'"
[ "$L4_EXPLORE" = "True" ] && ok "tools/list includes 'explore'"    || no "tools/list is missing 'explore'"
[ "$L4_TRACE" = "True" ]   && ok "tools/list includes 'from_trace'" || no "tools/list is missing 'from_trace'"
[ "$L4_EDITCHK" = "True" ] && ok "tools/list includes 'edit_check'" || no "tools/list is missing 'edit_check'"
[ "$L4_PACKTASK" = "False" ] && ok "'pack_task' is NOT separately advertised in tools/list (dispatch-only alias)" \
                              || no "'pack_task' unexpectedly appears in tools/list"

# ── explore round-trip: a pack-task-shaped bundle (same shape as CLI --pack-task) ────────────────
EXPLORE_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"explore","arguments":{"path":"'"$CORPUS"'","task":"engine scheduling run loop"}}}'
)
mcp_call "${EXPLORE_MSGS[@]}" >"$TMP/explore_a"
mcp_call "${EXPLORE_MSGS[@]}" >"$TMP/explore_b"
EXPLORE_INNER="$( tail -1 "$TMP/explore_a" | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + json.dumps(r["error"])) if "error" in r else print(r["result"]["content"][0]["text"])
' )"
case "$EXPLORE_INNER" in
    __ERROR__*) no "explore verb returned error: ${EXPLORE_INNER#__ERROR__:}";;
    "")         no "explore verb: inner text is empty";;
    *)          ok "explore verb: returned non-empty text result";;
esac
# §B1.7 (2026-07-29): same root-attribute change — the legend comment still follows the ctx open tag,
# but task=/route= attributes now sit between; assert the two meaning halves separately.
{ printf '%s' "$EXPLORE_INNER" | grep -qE '<ctx( |>)' \
  && printf '%s' "$EXPLORE_INNER" | grep -q '<!-- ctxpack task bundle for' \
  && printf '%s' "$EXPLORE_INNER" | grep -q 'budget=' \
  && printf '%s' "$EXPLORE_INNER" | grep -q '<sigs>' \
  && printf '%s' "$EXPLORE_INNER" | grep -q '</ctx>'; } \
    && ok "explore verb: pack-task-shaped bundle (header/budget/<sigs>/</ctx>)" \
    || { no "explore verb: not pack-task-shaped"; printf '%s\n' "$EXPLORE_INNER" | head -c 300; echo; }
diff -q "$TMP/explore_a" "$TMP/explore_b" >/dev/null \
    && ok "explore verb: deterministic (byte-identical across two MCP calls)" \
    || no "explore verb: non-deterministic response"

# ── pack_task is the SAME handler as explore (dispatch-only alias) — byte-identical inner text ──
PACKTASK_INNER="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"pack_task","arguments":{"path":"'"$CORPUS"'","task":"engine scheduling run loop"}}}' \
    | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + json.dumps(r["error"])) if "error" in r else print(r["result"]["content"][0]["text"])
' )"
[ "$PACKTASK_INNER" = "$EXPLORE_INNER" ] \
    && ok "pack_task dispatches identically to explore (same handler)" \
    || { no "pack_task diverged from explore's output"; }

# ── from_trace round-trip: a synthetic trace pointing at zoomfix's appMain (app.cpp:9) ──────────
FROMTRACE_OUT="$( python3 - "$CORPUS" <<'PYEOF' | "$BIN" --mcp 2>/dev/null | tail -1
import json, sys
root = sys.argv[1]
trace = "Traceback (most recent call last):\n  File \"app.cpp\", line 9, in appMain\n    schedRun()\n"
print(json.dumps({"jsonrpc":"2.0","id":1,"method":"initialize"}))
print(json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"from_trace","arguments":{"path":root,"trace":trace}}}))
PYEOF
)"
FROMTRACE_INNER="$( printf '%s' "$FROMTRACE_OUT" | python3 -c '
import sys, json
r = json.loads(sys.stdin.read())
print("__ERROR__:" + json.dumps(r["error"])) if "error" in r else print(r["result"]["content"][0]["text"])
' )"
case "$FROMTRACE_INNER" in
    __ERROR__*) no "from_trace verb returned error: ${FROMTRACE_INNER#__ERROR__:}";;
    *)          ok "from_trace verb: returned non-empty text result";;
esac
{ printf '%s' "$FROMTRACE_INNER" | grep -q '<trace src=' \
  && printf '%s' "$FROMTRACE_INNER" | grep -q 'n="appMain"' \
  && printf '%s' "$FROMTRACE_INNER" | grep -q 'in_corpus="1"'; } \
    && ok "from_trace verb: mapped the fixture trace onto appMain (innermost frame)" \
    || { no "from_trace verb: did not map onto appMain"; printf '%s\n' "$FROMTRACE_INNER" | head -c 300; echo; }

# ── edit_check round-trip: the contract shape (status= + callers=) ──────────────────────────────
EDITCHECK_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":"'"$CORPUS"'","symbol":"appMain"}}}' | tail -1 )"
EDITCHECK_INNER="$( printf '%s' "$EDITCHECK_OUT" | python3 -c '
import sys, json
r = json.loads(sys.stdin.read())
print("__ERROR__:" + json.dumps(r["error"])) if "error" in r else print(r["result"]["content"][0]["text"])
' )"
case "$EDITCHECK_INNER" in
    __ERROR__*) no "edit_check verb returned error: ${EDITCHECK_INNER#__ERROR__:}";;
    *)          ok "edit_check verb: returned non-empty text result";;
esac
{ printf '%s' "$EDITCHECK_INNER" | grep -q '<edit-check sym="appMain"' \
  && printf '%s' "$EDITCHECK_INNER" | grep -qE 'status="(unchanged|new-symbol|contract-change)"' \
  && printf '%s' "$EDITCHECK_INNER" | grep -q 'callers="'; } \
    && ok "edit_check verb: contract shape (sym/status/callers)" \
    || { no "edit_check verb: wrong shape"; printf '%s\n' "$EDITCHECK_INNER" | head -c 300; echo; }

# unknown symbol → -32602 naming it
EDITCHECK_UNKNOWN="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":"'"$CORPUS"'","symbol":"noSuchSymbolXYZ"}}}' | tail -1 )"
python3 -c '
import sys, json
r = json.loads(sys.argv[1])
msg = r.get("error", {}).get("message", "")
print("OK" if r.get("error",{}).get("code")==-32602 and "noSuchSymbolXYZ" in msg else "GOT:" + json.dumps(r))
' "$EDITCHECK_UNKNOWN" >"$TMP/editcheck_unknown"
[ "$( cat "$TMP/editcheck_unknown" )" = "OK" ] \
    && ok "edit_check: unknown symbol -> -32602 naming it" \
    || no "edit_check: unknown symbol did not refuse correctly: $( cat "$TMP/editcheck_unknown" )"

# ── missing-arg gives the per-verb message (D3 convention) ──────────────────────────────────────
check_missing_arg() {
    local verb="$1" argsJson="$2" wantSubstr="$3"
    local out
    out="$( mcp_call \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$verb"'","arguments":'"$argsJson"'}}' | tail -1 )"
    python3 -c '
import sys, json
r = json.loads(sys.argv[1])
msg = r.get("error", {}).get("message", "")
print("OK" if r.get("error",{}).get("code")==-32602 and sys.argv[2] in msg else "GOT:" + json.dumps(r))
' "$out" "$wantSubstr" >"$TMP/missing_$verb"
    [ "$( cat "$TMP/missing_$verb" )" = "OK" ] \
        && ok "$verb: missing-arg gives 'missing required field: $wantSubstr'" \
        || no "$verb: missing-arg message wrong: $( cat "$TMP/missing_$verb" )"
}
check_missing_arg "explore"    '{"path":"'"$CORPUS"'"}' "task"
check_missing_arg "pack_task"  '{"path":"'"$CORPUS"'"}' "task"
check_missing_arg "from_trace" '{"path":"'"$CORPUS"'"}' "trace"
check_missing_arg "edit_check" '{"path":"'"$CORPUS"'"}' "symbol"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
