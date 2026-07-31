#!/usr/bin/env bash
# mcphandlecheck.sh — gate for T4 (lazy bodies + stable content handles).
#
# Drives the MCP server over newline-delimited JSON-RPC (same piping as mcpverbscheck.sh) and proves the
# stable content-handle contract:
#   1. tools/list advertises the fetch_body verb.
#   2. a read verb (find_symbol) returns a `handle` on every symbol it surfaces (format sym#<16hex>@<16hex>).
#   3. fetch_body{handle} returns the EXACT def-span source (byte-compared against the source file's def line).
#   4. the handle is BYTE-IDENTICAL across two INDEPENDENT server processes (canonId + contentHash are
#      run-stable → warm==cold, process-independent).
#   5. a STALE handle (its file changed since issue) is REFUSED with no body returned.
#   6. a garbage / hand-mutated (non-existent-id) handle is REFUSED (no mis-resolve, no body).
#   7. determinism: two find_symbol calls are byte-identical.
#   8. every response line is valid JSON.
#
# Mutation-tested: removing the handle attribute fails step 2; making fetch_body ignore contentHash fails
# step 5; accepting any hex string fails step 6.
#
# Usage:
#   test/mcphandlecheck.sh                          # uses build/ctxpack
#   CTXPACK_BIN=asan/ctxpack test/mcphandlecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcphandlecheck: BIN=$BIN"

# Work on a PRIVATE copy of the zoomfix corpus so we can mutate a file for the staleness test.
CORPUS="$TMP/corpus"
cp -R "$ROOT/test/zoomfix" "$CORPUS"

SYM="engineStepA2"                 # one-line def in core/engine.cpp of the zoomfix corpus
SRCFILE="$CORPUS/core/engine.cpp"

# Send JSON-RPC messages to a fresh MCP server process; print all output lines.
mcp_call() { printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }

# Extract the `handle` field of the top-level `symbol` from a find_symbol response line-stream on stdin.
handle_of_symbol() {
    tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
print(json.loads(r["result"]["content"][0]["text"])["symbol"]["handle"])
'
}

FIND_MSGS=(
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$CORPUS"'","symbol":"'"$SYM"'"}}}'
)

echo
echo "=== 1. tools/list — assert 'fetch_body' verb is listed ==="
LIST_OUT="$( mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )"
python3 -c '
import sys, json
names = [t["name"] for t in json.loads(sys.argv[1])["result"]["tools"]]
print("FETCH_OK" if "fetch_body" in names else "MISSING")
' "$LIST_OUT" > "$TMP/listchk"
grep -q FETCH_OK "$TMP/listchk" && ok "fetch_body tool is listed" || no "fetch_body tool MISSING from tools/list"

echo
echo "=== 2. find_symbol returns a well-formed handle on every surfaced symbol ==="
mcp_call "${FIND_MSGS[@]}" | tail -1 > "$TMP/find_a"
python3 -c '
import sys, json, re
r = json.load(open(sys.argv[1]))
d = json.loads(r["result"]["content"][0]["text"])
syms = [d["symbol"]] + d.get("calledBy", []) + d.get("calls", [])
missing = [s["name"] for s in syms if not s.get("handle")]
bad = [s["handle"] for s in syms if s.get("handle") and not re.fullmatch(r"sym#[0-9a-f]{16}@[0-9a-f]{16}", s["handle"])]
print("NO_HANDLE:" + ",".join(missing) if missing else "ALL_HAVE_HANDLE")
print("BAD_FORMAT:" + ",".join(bad) if bad else "FORMAT_OK")
' "$TMP/find_a" > "$TMP/hchk"
grep -q ALL_HAVE_HANDLE "$TMP/hchk" && ok "every symbol carries a handle" || no "$(grep NO_HANDLE "$TMP/hchk")"
grep -q FORMAT_OK      "$TMP/hchk" && ok "handles match sym#<16hex>@<16hex>" || no "$(grep BAD_FORMAT "$TMP/hchk")"

H="$( mcp_call "${FIND_MSGS[@]}" | handle_of_symbol )"
# Hard gate: every later step depends on H being a REAL handle. A missing/garbage H (e.g. the handle
# attribute was removed) must FAIL loudly here, never let a later step spuriously "pass" on a broken H.
if ! printf '%s' "$H" | grep -Eq '^sym#[0-9a-f]{16}@[0-9a-f]{16}$'; then
    no "could not obtain a valid handle (got: '$H') — aborting handle-dependent checks"
    echo; echo "SOME CHECKS FAILED"; exit 1
fi
ok "obtained handle: $H"

echo
echo "=== 3. fetch_body{handle} returns the EXACT def-span source ==="
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"'"$H"'"}}}' \
    | tail -1 > "$TMP/fetch_a"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
b = json.loads(r["result"]["content"][0]["text"])
open(sys.argv[2], "w").write(b["body"])
print("BYTES:" + str(b["bytes"]))
' "$TMP/fetch_a" "$TMP/body_got" > "$TMP/fetchmeta" 2>&1
if grep -q __ERR__ "$TMP/fetchmeta"; then
    no "fetch_body returned an error: $(cat "$TMP/fetchmeta")"
else
    grep -F "int ${SYM}(" "$SRCFILE" | head -1 > "$TMP/body_truth"
    if [ "$(cat "$TMP/body_got")" = "$(cat "$TMP/body_truth")" ]; then
        ok "fetch_body body byte-matches the source def span"
    else
        no "fetch_body body != source span"
        echo "    got:   $(cat "$TMP/body_got")"
        echo "    truth: $(cat "$TMP/body_truth")"
    fi
fi

echo
echo "=== 4. handle is byte-identical across TWO independent server processes ==="
H1="$( mcp_call "${FIND_MSGS[@]}" | handle_of_symbol )"
H2="$( mcp_call "${FIND_MSGS[@]}" | handle_of_symbol )"
[ "$H1" = "$H2" ] && ok "handle stable across two processes ($H1)" || no "handle differs across processes: $H1 vs $H2"

echo
echo "=== 5. STALE handle is REFUSED (file changed since issue), no body returned ==="
printf '// mutation to change file bytes for the staleness test\n' >> "$SRCFILE"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"'"$H"'"}}}' \
    | tail -1 > "$TMP/stale"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
has_result = "result" in r
code = r.get("error", {}).get("code")
msg  = r.get("error", {}).get("message", "")
print("STALE_REFUSED" if (not has_result and code == -32602 and "stale" in msg) else "STALE_SERVED:" + json.dumps(r)[:200])
' "$TMP/stale" > "$TMP/stalechk"
grep -q STALE_REFUSED "$TMP/stalechk" && ok "stale handle refused with -32602 'stale', no body" || no "stale handle NOT refused: $(cat "$TMP/stalechk")"

echo
echo "=== 6. garbage / mutated handle is REFUSED ==="
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"not-a-handle"}}}' \
    | tail -1 > "$TMP/garbage"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
print("GARBAGE_REFUSED" if ("result" not in r and r.get("error",{}).get("code")==-32602) else "GARBAGE_SERVED")
' "$TMP/garbage" > "$TMP/gchk"
grep -q GARBAGE_REFUSED "$TMP/gchk" && ok "garbage handle refused" || no "garbage handle NOT refused"

# well-formed but non-existent id: flip the first id hex nibble deterministically → resolves to nothing.
MUT="$( python3 -c '
import sys
h=sys.argv[1]
c=h[4]; nc="0" if c!="0" else "1"
print(h[:4]+nc+h[5:])
' "$H" )"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$CORPUS"'","handle":"'"$MUT"'"}}}' \
    | tail -1 > "$TMP/mut"
python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
print("MUT_REFUSED" if ("result" not in r and r.get("error",{}).get("code")==-32602) else "MUT_SERVED:" + json.dumps(r)[:160])
' "$TMP/mut" > "$TMP/mchk"
grep -q MUT_REFUSED "$TMP/mchk" && ok "mutated (non-existent id) handle refused, no body" || no "mutated handle NOT refused: $(cat "$TMP/mchk")"

echo
echo "=== 7. determinism: two find_symbol calls byte-identical ==="
mcp_call "${FIND_MSGS[@]}" > "$TMP/det_a"
mcp_call "${FIND_MSGS[@]}" > "$TMP/det_b"
diff -q "$TMP/det_a" "$TMP/det_b" >/dev/null && ok "find_symbol deterministic (byte-identical)" || no "find_symbol non-deterministic"

echo
echo "=== 8. every response line is valid JSON ==="
mcp_call "${FIND_MSGS[@]}" > "$TMP/json_lines"
python3 -c '
import sys, json
bad = 0
for i, ln in enumerate(open(sys.argv[1]), 1):
    ln = ln.strip()
    if not ln: continue
    try: json.loads(ln)
    except Exception as e: print("LINE", i, "INVALID:", e); bad += 1
print("JSON_OK" if bad == 0 else "JSON_BAD:" + str(bad))
' "$TMP/json_lines" > "$TMP/jchk"
grep -q JSON_OK "$TMP/jchk" && ok "all response lines are valid JSON" || no "$(grep -v JSON_OK "$TMP/jchk")"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
