#!/usr/bin/env bash
# mcpremotecheck.sh — the gate for the OPTIONAL remote MCP transport:
# Streamable HTTP over a hand-rolled HTTP/1.1 reader, plain request/response, single-threaded serialize.
# THE SECURITY POSTURE IS THE FEATURE — every rule below is gated:
#
#   protocol equivalence  — the SAME JSON-RPC body returns byte-identical bytes over stdio and over HTTP
#                           (tools/list + for + batch against the fixture) — the shared dispatchMcpLine path.
#   loopback default      — a bare 127.0.0.1 listener needs no token; a normal read verb answers 200.
#   non-loopback + token  — --listen=0.0.0.0:PORT with NO token REFUSES TO START (exit 1 + stderr banner).
#   bearer gate           — with a token, a missing/wrong Bearer → 401 (no index access); the right one → 200.
#   edit refusal          — a remote edit verb (no --allow-remote-edits) → JSON-RPC error, file BYTE-IDENTICAL.
#   workspace pinning      — a request naming a path OUTSIDE the startup workspace → clean error + NO rebuild
#                           (RIPWIRE_MCP_TIMINGS rebuilt=0), and the omitted-path form defaults to the workspace.
#   oversized body        — a > 8 MB body → 413; malformed HTTP → 400/405 and the server LIVES.
#   2 sequential clients  — two back-to-back HTTP clients both get correct answers off the one warm index.
#   client drops mid-reply — a client that closes or resets before/while reading a multi-MB response costs only
#                           its own connection: the SAME listener stays alive and answers the next request.
#   hostile-input parity  — the mcpaudit4hardencheck corpus (25-digit start_line, XML-comment-breaking task)
#                           degrades IDENTICALLY over HTTP — the hardened parser is transport-agnostic.
#
# Usage:  test/mcpremotecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/mcpremotecheck.sh
# Exits non-zero on any failure. Every mutation happens under a scratch mktemp dir; test/fixture is never
# modified. Does NOT edit regression.sh or any other existing test file.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'cleanup' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

SRV_PID=""
cleanup(){ [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$TMP"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }
command -v curl    >/dev/null 2>&1 || { echo "curl required (present on macOS/Linux)"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required (the workspace needs history — see the WS setup below)"; exit 2; }

echo "mcpremotecheck: BIN=$BIN  FIX=$FIX"

# pick an ephemeral-ish port and wait for the listener to answer (poll, don't race a fixed sleep).
PORT=$(( 20000 + ( $$ % 20000 ) ))
URL="http://127.0.0.1:$PORT/mcp"
MCP_ACCEPT='application/json, text/event-stream'
MCP_CURRENT_INIT='{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"ripwire-test","version":"1.0"}}}'

# Every ordinary request in this gate is a conforming Streamable-HTTP request. Individual negative tests
# bypass this wrapper with `command curl` so one missing/bad header remains the only variable under test.
curl() {
    command curl -H "Accept: $MCP_ACCEPT" -H 'Content-Type: application/json' "$@"
}

start_server() { # $@ = extra flags; server pinned to a fresh copy of the fixture
    "$BIN" "$WS" --listen=127.0.0.1:"$PORT" "$@" >"$TMP/srv.out" 2>"$TMP/srv.err" &
    SRV_PID=$!
    for _ in $(seq 1 50); do
        curl -s -o /dev/null -m 1 -X POST "$URL" -d "$MCP_CURRENT_INIT" 2>/dev/null && return 0
        kill -0 "$SRV_PID" 2>/dev/null || return 1   # server died during startup
        sleep 0.1
    done
    return 1
}
stop_server() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; wait "$SRV_PID" 2>/dev/null; SRV_PID=""; }

WS="$( mktemp -d "$TMP/ws.XXXXXX" )"; cp -R "$FIX/"* "$WS/"

# The workspace carries git history, and the protocol-equivalence arm below is the reason. V3/F4 made
# tools/list OMIT the git-backed verbs when a PINNED workspace is not a git repository — pinning is what
# makes the omission provable (the listener refuses a `path` naming another tree), so the pinned HTTP
# server prunes where the stdio server, which still answers about any path a caller names, does not. On a
# non-git fixture the two catalogs then differ BY DESIGN, and this arm would report a designed policy
# difference as a transport bug. Same lesson the arm's own comment records from 2026-07-30, one policy
# later: hold configuration constant and vary only the transport. The non-git catalog is not going
# unchecked — test/mcptoolprunecheck.sh owns it, on both transports.
( cd "$WS" && git init -q . && git add -A \
  && git -c user.email=gate@example.invalid -c user.name=gate commit -qm "fixture baseline" ) >/dev/null 2>&1
git -C "$WS" rev-parse --verify --quiet HEAD >/dev/null 2>&1 \
    || { echo "could not give the workspace git history — the equivalence arm would compare two policies"; exit 2; }

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== loopback listener starts + answers a read verb (200) ==="
# ═══════════════════════════════════════════════════════════════════════════
if start_server; then
    ok "loopback --listen=127.0.0.1:$PORT starts and accepts connections"
else
    no "loopback listener failed to start; stderr: $( head -3 "$TMP/srv.err" )"; echo "SOME CHECKS FAILED"; exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== Streamable HTTP conformance: Origin, media types, lifecycle version, endpoint, GET/notification ==="
# ═══════════════════════════════════════════════════════════════════════════
INIT_CURRENT="$( curl -s -X POST "$URL" -d "$MCP_CURRENT_INIT" )"
printf '%s' "$INIT_CURRENT" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert r["result"]["protocolVersion"] == "2025-11-25", r
' 2>/dev/null && ok "initialize echoes the supported requested protocol version (2025-11-25)" \
              || no "initialize did not negotiate 2025-11-25: $( printf %s "$INIT_CURRENT" | head -c 160 )"

for version in 2025-06-18 2025-03-26 2024-11-05; do
    body="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"$version\",\"capabilities\":{},\"clientInfo\":{\"name\":\"ripwire-test\",\"version\":\"1.0\"}}}"
    got="$( curl -s -X POST "$URL" -d "$body" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("result",{}).get("protocolVersion",""))' 2>/dev/null )"
    if [ "$got" = "$version" ]; then ok "initialize echoes supported $version"; else no "initialize requested $version but returned '$got'"; fi
done

UNSUPPORTED='{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2099-01-01","capabilities":{},"clientInfo":{"name":"ripwire-test","version":"1.0"}}}'
got="$( curl -s -X POST "$URL" -d "$UNSUPPORTED" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("result",{}).get("protocolVersion",""))' 2>/dev/null )"
if [ "$got" = "2025-11-25" ]; then ok "unsupported initialize version negotiates to latest"; else no "unsupported initialize version returned '$got'"; fi

ORIGIN_BAD="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Origin: https://evil.example' -d "$MCP_CURRENT_INIT" )"
ORIGIN_NULL="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Origin: null' -d "$MCP_CURRENT_INIT" )"
ORIGIN_OK="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H "Origin: http://127.0.0.1:$PORT" -d "$MCP_CURRENT_INIT" )"
if [ "$ORIGIN_BAD" = "403" ]; then ok "foreign Origin is rejected with 403"; else no "foreign Origin got $ORIGIN_BAD (expected 403)"; fi
if [ "$ORIGIN_NULL" = "403" ]; then ok "Origin:null is rejected with 403"; else no "Origin:null got $ORIGIN_NULL (expected 403)"; fi
if [ "$ORIGIN_OK" = "200" ]; then ok "exact loopback Origin is accepted"; else no "exact loopback Origin got $ORIGIN_OK (expected 200)"; fi

ACCEPT_MISSING="$( command curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Content-Type: application/json' -d "$MCP_CURRENT_INIT" )"
ACCEPT_JSON="$( command curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Accept: application/json' -H 'Content-Type: application/json' -d "$MCP_CURRENT_INIT" )"
CTYPE_BAD="$( command curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H "Accept: $MCP_ACCEPT" -H 'Content-Type: text/plain' -d "$MCP_CURRENT_INIT" )"
CTYPE_OK="$( command curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H "Accept: $MCP_ACCEPT" -H 'Content-Type: application/json; charset=utf-8' -d "$MCP_CURRENT_INIT" )"
if [ "$ACCEPT_MISSING" = "406" ]; then ok "missing required Accept media pair is rejected with 406"; else no "missing Accept got $ACCEPT_MISSING (expected 406)"; fi
if [ "$ACCEPT_JSON" = "406" ]; then ok "JSON-only Accept is rejected with 406"; else no "JSON-only Accept got $ACCEPT_JSON (expected 406)"; fi
if [ "$CTYPE_BAD" = "415" ]; then ok "non-JSON Content-Type is rejected with 415"; else no "text/plain Content-Type got $CTYPE_BAD (expected 415)"; fi
if [ "$CTYPE_OK" = "200" ]; then ok "application/json with charset parameter is accepted"; else no "JSON charset Content-Type got $CTYPE_OK (expected 200)"; fi

DUP_ORIGIN="$( command curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H "Accept: $MCP_ACCEPT" -H 'Content-Type: application/json' \
    -H "Origin: http://127.0.0.1:$PORT" -H 'Origin: https://evil.example' -d "$MCP_CURRENT_INIT" )"
HUGE_LENGTH="$( command curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H "Accept: $MCP_ACCEPT" -H 'Content-Type: application/json' \
    -H 'Content-Length: 999999999999999999999999999999999999999999' -d '' )"
if [ "$DUP_ORIGIN" = "400" ]; then ok "duplicate Origin headers are rejected as ambiguous framing"; else no "duplicate Origin headers got $DUP_ORIGIN (expected 400)"; fi
if [ "$HUGE_LENGTH" = "413" ]; then ok "overflowing Content-Length saturates safely to 413"; else no "overflowing Content-Length got $HUGE_LENGTH (expected 413)"; fi

LIST='{"jsonrpc":"2.0","id":3,"method":"tools/list"}'
PROTO_BAD="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'MCP-Protocol-Version: 2099-01-01' -d "$LIST" )"
PROTO_MISSING="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -d "$LIST" )"
if [ "$PROTO_BAD" = "400" ]; then ok "unsupported MCP-Protocol-Version is rejected with 400"; else no "unsupported protocol header got $PROTO_BAD (expected 400)"; fi
if [ "$PROTO_MISSING" = "200" ]; then ok "missing protocol header uses the 2025-03-26 compatibility default"; else no "missing protocol header got $PROTO_MISSING (expected 200)"; fi

GET_CODE="$( command curl -s -o /dev/null -w '%{http_code}' -X GET "$URL" -H 'Accept: text/event-stream' )"
ROOT_CODE="$( curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/" -d "$MCP_CURRENT_INIT" )"
NOTIFY='{"jsonrpc":"2.0","method":"notifications/initialized"}'
NOTIFY_SHAPE="$( curl -s -o "$TMP/notify.body" -w '%{http_code}:%{size_download}' -X POST "$URL" -H 'MCP-Protocol-Version: 2025-11-25' -d "$NOTIFY" )"
if [ "$GET_CODE" = "405" ]; then ok "GET /mcp returns 405 when SSE is unsupported"; else no "GET /mcp got $GET_CODE (expected 405)"; fi
if [ "$ROOT_CODE" = "404" ]; then ok "the MCP listener exposes exactly /mcp (root is 404)"; else no "POST / got $ROOT_CODE (expected 404)"; fi
if [ "$NOTIFY_SHAPE" = "202:0" ]; then ok "accepted notification returns bodyless 202"; else no "notification response was $NOTIFY_SHAPE (expected 202:0)"; fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== protocol equivalence: stdio vs HTTP byte-identical (tools/list + for + batch) ==="
# ═══════════════════════════════════════════════════════════════════════════
CALL_list='{"jsonrpc":"2.0","id":11,"method":"tools/list"}'
CALL_for="{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"for\",\"arguments\":{\"path\":\"$WS\",\"task\":\"distance between two points\"}}}"
CALL_batch="{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"tools/call\",\"params\":{\"name\":\"batch\",\"arguments\":{\"path\":\"$WS\",\"queries\":[{\"verb\":\"grep\",\"pattern\":\"distance\"},{\"verb\":\"impact\",\"symbol\":\"distance\"}]}}}"
# The stdio arm MUST be started with the same workspace root the HTTP server was given ("$WS"), or this
# compares two differently-CONFIGURED servers and calls the difference a transport bug. It read `"$BIN" --mcp`
# — rootless — until 2026-07-30, and passed only because no part of the schema depended on configuration.
# Wave 2's §B6 M4 made `required` name `path` exactly when the server has NO startup root (rootless: the
# caller must supply it; rooted: they need not), so the rootless-vs-rooted pair began differing in 30 spans,
# all of them `"path"` removals — the fix working as designed, surfacing a gate that had been passing for the
# wrong reason. What this arm is FOR is transport equivalence; hold configuration constant and vary only the
# transport.
for label in list for batch; do
    eval "C=\$CALL_$label"
    STDIO="$( printf '%s\n%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$C" | "$BIN" "$WS" --mcp 2>/dev/null | tail -1 )"
    HTTP="$( curl -s -X POST "$URL" -d "$C" )"
    if [ -n "$HTTP" ] && [ "$STDIO" = "$HTTP" ]; then
        ok "tools/$label: HTTP payload byte-identical to stdio ($( printf %s "$HTTP" | wc -c | tr -d ' ' ) bytes)"
    else
        no "tools/$label: HTTP payload differs from stdio"
        diff <( printf %s "$STDIO" ) <( printf %s "$HTTP" ) | head -4
    fi
done

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== a successful remote 'for' call (transcript sample) ==="
# ═══════════════════════════════════════════════════════════════════════════
FOR_HTTP="$( curl -s -X POST "$URL" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"tools/call\",\"params\":{\"name\":\"for\",\"arguments\":{\"path\":\"$WS\",\"task\":\"distance\"}}}" )"
printf '%s' "$FOR_HTTP" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert "error" not in r, r
# §B1.7 (2026-07-29): ctx root carries task=/route= attributes now — match the element open.
assert ("<ctx>" in r["result"]["content"][0]["text"] or "<ctx " in r["result"]["content"][0]["text"]), "no <ctx> lens payload"
' 2>/dev/null && ok "remote for{task:distance} returns a well-formed lens result" \
              || no "remote for call malformed: $( printf %s "$FOR_HTTP" | head -c 200 )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== workspace pinning: off-workspace path refused + NO rebuild; omitted path defaults to workspace ==="
# ═══════════════════════════════════════════════════════════════════════════
OFF="$( curl -s -X POST "$URL" \
    -d '{"jsonrpc":"2.0","id":31,"method":"tools/call","params":{"name":"analyze","arguments":{"path":"/etc","task":"x"}}}' )"
printf '%s' "$OFF" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert "error" in r and "workspace" in r["error"]["message"], r
' 2>/dev/null && ok "off-workspace path (/etc) is refused with a clean workspace error" \
             || no "off-workspace path not cleanly refused: $( printf %s "$OFF" | head -c 200 )"

# omitted path must default to the pinned workspace (a real answer, not an error).
OMIT="$( curl -s -X POST "$URL" \
    -d '{"jsonrpc":"2.0","id":32,"method":"tools/call","params":{"name":"for","arguments":{"task":"distance"}}}' )"
printf '%s' "$OMIT" | python3 -c '
import sys, json
r = json.load(sys.stdin)
# §B1.7 (2026-07-29): same root-attribute change — element-open match.
assert "error" not in r and ("<ctx>" in r["result"]["content"][0]["text"] or "<ctx " in r["result"]["content"][0]["text"]), r
' 2>/dev/null && ok "omitted path defaults to the pinned workspace (answers normally)" \
             || no "omitted path did not default to the workspace: $( printf %s "$OMIT" | head -c 200 )"

# the "NO rebuild" half of gate 10: restart with RIPWIRE_MCP_TIMINGS and assert the off-workspace refusal
# emits NO rebuilt=1 line (the refusal is built before getIndex, so mcpRebuildCounter cannot advance).
stop_server
if RIPWIRE_MCP_TIMINGS=1 start_server; then
    : > "$TMP/srv.err"   # clear the banner/startup lines so we only inspect this request's timing
    RB_BEFORE="$( grep -c 'rebuilt=' "$TMP/srv.err" 2>/dev/null || echo 0 )"
    curl -s -o /dev/null -X POST "$URL" \
        -d '{"jsonrpc":"2.0","id":33,"method":"tools/call","params":{"name":"analyze","arguments":{"path":"/nonexistent-tree-xyz","task":"x"}}}'
    sleep 0.2
    if grep -q 'verb=analyze .*rebuilt=1' "$TMP/srv.err"; then
        no "off-workspace refusal triggered an index rebuild (rebuilt=1) — must refuse BEFORE getIndex"
    else
        ok "off-workspace refusal did NOT rebuild the index (no rebuilt=1 timing line)"
    fi
    stop_server
fi
start_server   # back to the plain loopback server for the remaining loopback checks

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== edit verb refused over the remote transport (no --allow-remote-edits); file byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════
TARGET="$( ls "$WS"/*.cpp 2>/dev/null | head -1 )"
[ -z "$TARGET" ] && TARGET="$( ls "$WS"/* 2>/dev/null | head -1 )"
BEFORE_SHA="$( shasum "$TARGET" | awk '{print $1}' )"
EDIT="$( curl -s -X POST "$URL" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":41,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$WS\",\"symbol\":\"distance\",\"new_body\":\"CORRUPTED\"}}}" )"
AFTER_SHA="$( shasum "$TARGET" | awk '{print $1}' )"
printf '%s' "$EDIT" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert "error" in r and ("remote" in r["error"]["message"] or "disabled" in r["error"]["message"]), r
' 2>/dev/null && ok "remote replace_symbol_body is refused with a JSON-RPC error" \
             || no "remote edit was not cleanly refused: $( printf %s "$EDIT" | head -c 200 )"
[ "$BEFORE_SHA" = "$AFTER_SHA" ] && ok "the target file is byte-identical after the refused remote edit" \
                                 || no "the target file CHANGED despite the refusal — safety contract broken"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== oversized body → 413; malformed HTTP → 4xx and the server LIVES ==="
# ═══════════════════════════════════════════════════════════════════════════
python3 -c "import sys; sys.stdout.write('x'*(9*1024*1024))" > "$TMP/big.bin"
BIG_CODE="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" --data-binary @"$TMP/big.bin" )"
[ "$BIG_CODE" = "413" ] && ok "a > 8 MB body is rejected with 413 Payload Too Large" \
                        || no "oversized body got HTTP $BIG_CODE (expected 413)"

# malformed HTTP: a non-HTTP first line. Server must answer a 4xx (or drop) and STILL serve the next request.
printf 'THIS IS NOT HTTP\r\n\r\n' | (exec 3<>/dev/tcp/127.0.0.1/"$PORT"; cat >&3; head -1 <&3) >/dev/null 2>&1 || true
STILL="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -d '{"jsonrpc":"2.0","id":51,"method":"initialize"}' )"
[ "$STILL" = "200" ] && ok "server survives malformed HTTP and still answers the next request (200)" \
                     || no "server did not recover after malformed HTTP (next request got $STILL)"

# a partial/slow request (headers, then stall past the read timeout) must not wedge the server. We open a
# connection, send only a partial request line, then close — the server's SO_RCVTIMEO drops it. Assert the
# server still answers afterward. (Timeout is 10s; we don't wait for it — just prove the next request works.)
( exec 3<>/dev/tcp/127.0.0.1/"$PORT"; printf 'POST /mcp HTTP/1.1\r\nContent-Length: 999\r\n\r\n{partial' >&3; sleep 0.3 ) 2>/dev/null || true
ALIVE="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -d '{"jsonrpc":"2.0","id":52,"method":"initialize"}' )"
[ "$ALIVE" = "200" ] && ok "a partial (slow-loris-ish) request does not wedge the single-threaded server" \
                     || no "server unresponsive after a partial request (next got $ALIVE)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== two sequential clients both answered off the one warm index ==="
# ═══════════════════════════════════════════════════════════════════════════
C1="$( curl -s -X POST "$URL" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":61,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WS\",\"symbol\":\"distance\"}}}" )"
C2="$( curl -s -X POST "$URL" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":62,\"method\":\"tools/call\",\"params\":{\"name\":\"impact\",\"arguments\":{\"path\":\"$WS\",\"symbol\":\"distance\"}}}" )"
{ printf '%s' "$C1" | grep -q 'handle' && printf '%s' "$C2" | python3 -c 'import sys,json; json.load(sys.stdin)["result"]' 2>/dev/null; } \
    && ok "two sequential clients (find_symbol then impact) both answered correctly" \
    || no "one of two sequential clients failed: C1=$( printf %s "$C1" | head -c 80 ) C2=$( printf %s "$C2" | head -c 80 )"

stop_server

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== a client that drops mid-response costs only its own connection (no SIGPIPE) ==="
# ═══════════════════════════════════════════════════════════════════════════
# A peer that closes or resets its socket while the listener is still writing makes send() fail with EPIPE,
# and unsuppressed that raises SIGPIPE, whose default action ends the process: ONE client that stopped
# reading took the listener down for every client after it (2026-09-12, pre-fix binary on macOS: killed by
# signal 13 on each of the three shapes below, the next client refused). A reply that fits in the socket
# buffers is written in full before the peer's reset lands, so this arm first PROVES its reply is bigger than
# any default buffer (4 MiB is Linux's tcp_wmem ceiling; macOS's sendspace is 131 KB). The `for` task is
# echoed into the payload, which is what makes the reply large on a small fixture. A reply that shrinks below
# the floor is a FAIL, so the arm cannot keep passing after it stops reaching a failing send().
python3 -c 'import json,sys; sys.stdout.write(json.dumps({"jsonrpc":"2.0","id":91,"method":"tools/call","params":{"name":"for","arguments":{"path":sys.argv[1],"task":"distance "*350000}}}))' "$WS" \
    > "$TMP/bigreply.json"
drop_client() { # $1 = read-all | close-before-read | reset-before-read | close-midway; prints "BYTES STATUSLINE"
    python3 - "$PORT" "$1" "$TMP/bigreply.json" <<'PY'
import socket, struct, sys, time
port, mode, body = int(sys.argv[1]), sys.argv[2], open(sys.argv[3], "rb").read()
head = ("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nAccept: application/json, text/event-stream\r\n"
        "Content-Type: application/json\r\nContent-Length: %d\r\n\r\n" % (port, len(body))).encode()
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
if mode == "close-midway":
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)   # before connect: the listener blocks in send()
s.settimeout(120)
s.connect(("127.0.0.1", port))
s.sendall(head + body)
data = b""
if mode in ("read-all", "close-midway"):
    want = 4096 if mode == "close-midway" else None
    while want is None or len(data) < want:
        chunk = s.recv(65536 if want is None else want - len(data))
        if not chunk:
            break
        data += chunk
elif mode == "reset-before-read":
    time.sleep(0.3)                                             # an RST before the listener READ the request discards it
    s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))   # close() now sends RST, not FIN
s.close()
print(len(data), data.split(b"\r\n", 1)[0].decode("latin-1") or "-")
PY
}
if start_server; then
    read -r BIG_BYTES _ BIG_CODE _ <<<"$( drop_client read-all 2>/dev/null )"
    if [ "${BIG_BYTES:-0}" -gt 4194304 ] 2>/dev/null && [ "${BIG_CODE:-}" = "200" ]; then
        ok "the probe reply outgrows every default socket buffer ($BIG_BYTES bytes, 200, read in full)"
    else
        no "the probe reply is '${BIG_BYTES:-}' bytes (HTTP '${BIG_CODE:-}'), not a 200 over 4 MiB — the drop shapes below would not reach a failing send()"
    fi
    for shape in close-before-read reset-before-read close-midway; do
        drop_client "$shape" >/dev/null 2>&1
        # The next request queues behind the dropped one on the single-threaded loop, so no sleep is needed: it
        # is answered only if the listener outlived the failed write.
        NEXT="$( curl -s -o /dev/null -w '%{http_code}' -m 60 -X POST "$URL" -d '{"jsonrpc":"2.0","id":92,"method":"initialize"}' )"
        if [ "$NEXT" = "200" ] && kill -0 "$SRV_PID" 2>/dev/null; then
            ok "$shape: the same listener is alive and answers the next request (200)"
        else
            # status 141 = the listener died of SIGPIPE on its own; 143 = it was alive and this kill ended it.
            kill "$SRV_PID" 2>/dev/null; wait "$SRV_PID" 2>/dev/null; RC=$?; SRV_PID=""
            no "$shape: the listener did not outlive the dropped client (next request got $NEXT, listener status $RC; 141 = SIGPIPE)"
            start_server || no "$shape: the listener could not be restarted for the remaining shapes"
        fi
    done
    stop_server
else
    no "drop-mid-response listener failed to start"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== security: non-loopback bind without a token REFUSES to start (exit 1 + banner) ==="
# ═══════════════════════════════════════════════════════════════════════════
OUT="$( "$BIN" "$WS" --listen=0.0.0.0:"$PORT" 2>&1 )"; RC=$?
{ [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -qi 'token'; } \
    && ok "0.0.0.0 without --mcp-token refuses to start (exit $RC, message names the token)" \
    || no "non-loopback bind without a token did NOT refuse to start (rc=$RC): $OUT"

OUT2="$( "$BIN" "$WS" --listen=127.0.0.1:"$PORT" --allow-remote-edits 2>&1 )"; RC2=$?
{ [ "$RC2" -ne 0 ] && printf '%s' "$OUT2" | grep -qi 'token'; } \
    && ok "--allow-remote-edits without a token refuses to start (forces the token even on loopback)" \
    || no "--allow-remote-edits without a token did NOT refuse (rc=$RC2): $OUT2"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== security: with a token, missing/wrong Bearer → 401, right Bearer → 200 ==="
# ═══════════════════════════════════════════════════════════════════════════
TOKEN="s3cr3t-$$"
if start_server --mcp-token="$TOKEN"; then
    # start_server's own probe has no Authorization header, so a successful start already proves the poll
    # tolerates a 401 — re-check explicitly below.
    NO="$(   curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -d '{"jsonrpc":"2.0","id":71,"method":"initialize"}' )"
    WRONG="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Authorization: Bearer WRONG' -d '{"jsonrpc":"2.0","id":72,"method":"initialize"}' )"
    RIGHT="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H "Authorization: Bearer $TOKEN" -d '{"jsonrpc":"2.0","id":73,"method":"initialize"}' )"
    if [ "$NO" = "401" ]; then ok "missing bearer token → 401"; else no "missing token got $NO (expected 401)"; fi
    if [ "$WRONG" = "401" ]; then ok "wrong bearer token → 401"; else no "wrong token got $WRONG (expected 401)"; fi
    if [ "$RIGHT" = "200" ]; then ok "correct bearer token → 200"; else no "correct token got $RIGHT (expected 200)"; fi
    stop_server
else
    no "token-guarded loopback server failed to start"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== hostile-input parity: the mcpaudit4 corpus degrades identically over HTTP ==="
# ═══════════════════════════════════════════════════════════════════════════
if start_server; then
    # (A4-F6) a 26-digit start_line must not crash the server; it returns a well-formed JSON-RPC response.
    H="$( curl -s -X POST "$URL" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":81,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WS\",\"symbol\":\"distance\"}}}" \
        | python3 -c 'import sys,json; print(json.loads(json.load(sys.stdin)["result"]["content"][0]["text"])["symbol"]["handle"])' 2>/dev/null )"
    if [ -n "$H" ]; then
        BOMB="$( curl -s -X POST "$URL" \
            -d "{\"jsonrpc\":\"2.0\",\"id\":82,\"method\":\"tools/call\",\"params\":{\"name\":\"fetch_body\",\"arguments\":{\"path\":\"$WS\",\"handle\":\"$H\",\"start_line\":12345678901234567890123456}}}" )"
        printf '%s' "$BOMB" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null \
            && ok "A4-F6 over HTTP: 26-digit start_line yields a well-formed JSON-RPC response (no UB/crash)" \
            || no "A4-F6 over HTTP: response not valid JSON: $( printf %s "$BOMB" | head -c 120 )"
    else
        no "A4-F6 over HTTP: could not obtain a handle to probe"
    fi

    # (A4-F7) an XML-comment-breaking task must not survive verbatim / break well-formedness.
    EVIL='--> <evil/> <!-- reopen: distance calculation'
    EVIL_JSON="$( python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$EVIL" )"
    FOR_EVIL="$( curl -s -X POST "$URL" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":83,\"method\":\"tools/call\",\"params\":{\"name\":\"for\",\"arguments\":{\"path\":\"$WS\",\"task\":$EVIL_JSON}}}" \
        | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r["result"]["content"][0]["text"] if "error" not in r else "__ERR__")' 2>/dev/null )"
    if printf '%s' "$FOR_EVIL" | grep -q -- '--> <evil/>'; then
        no "A4-F7 over HTTP: the literal '--> <evil/>' survived uncollapsed (comment injection possible)"
    else
        ok "A4-F7 over HTTP: the '--' run was collapsed before landing in the XML comment"
    fi
    # server still alive after both hostile calls
    LIVE="$( curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -d '{"jsonrpc":"2.0","id":84,"method":"initialize"}' )"
    [ "$LIVE" = "200" ] && ok "server remains responsive after the hostile-input corpus" \
                        || no "server unresponsive after hostile input (got $LIVE)"
    stop_server
else
    no "hostile-input server failed to start"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
