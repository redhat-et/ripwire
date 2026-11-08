#!/usr/bin/env bash
# agenttrapcheck.sh — AGENT-VISIBLE-TRAP (src/infra/agenttrap.h, src/infra/diagnostics.cpp): a failed dev-build ASSUME /
# EXPECTS / ENSURES / UNREACHABLE tells the AGENT, not only a debugger. Driven by the debug-only test trigger
# RIPWIRE_TEST_TRAP=assume|expects|ensures|unreachable (agenttrap fireTestTrap: main's CLI path, and dispatchMcpLine's
# tools/call branch).
#   (C)  CLI: stdout carries ONE well-formed <ripwire_internal_error kind= expr= at= fn= note= version= .../> line; stderr
#        keeps the notice with its "Next:" row; the exit status is the trap's signal (>= 128), never one of ripwire's 0-5.
#        Every agent-visible kind names itself.
#   (R)  The last-crash record: written to the cache dir (line 1 the summary, line 2 one JSON object with argv and its flags);
#        the NEXT CLI call prints one stderr line naming it and removes it; the call after that prints nothing.
#   (M)  MCP stdio: initialize, then a tools/call with a STRING id under the trigger gets a JSON-RPC error for THAT id on
#        stdout — parseable, code -32603, data.kind == "Expects", the message says it is a ripwire bug — and the server
#        exits. The record names transport mcp-stdio, the tool and the request id. The next server's initialize carries
#        the note in its instructions once; the one after does not.
#   (I)  Inert: the trigger unset and set to a value no arm takes give byte-identical stdout and stderr, exit 0, and no
#        record; an MCP tools/call without the trigger is a plain result.
#   (H)  MCP over --listen: the same error as an HTTP/1.1 200 response with an exact Content-Length, on the request's socket.
#   (N)  A release binary (NDEBUG) has none of it: the trigger string is not in the binary and the trigger changes nothing.
# Mutants that turn it red (measured, see changelog.d/agent-trap.md): no MCP error write -> (M); a wrong request id -> (M);
# no last-crash clear -> (R) and (M).
# Usage: bash test/agenttrapcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/agenttrapcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN - build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; : > "$TMP/failed"; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; : > "$TMP/failed"; }
echo "agenttrapcheck: BIN=$BIN"
FX="$ROOT/test/fixture"
mkdir -p "$TMP/home" "$TMP/t/"
CRASH="$TMP/t/ripwire/last-crash"   # cacheDirLadder: $TMPDIR/ripwire
# run [ENV=V...] -- ARGS: one CLI call in the fixture, private HOME/TMPDIR, stdin closed. Sets OUT ERR RC.
run(){
    local envs=()
    while [ "$1" != "--" ]; do envs+=( "$1" ); shift; done; shift
    ( cd "$FX" && env -u RIPWIRE_TEST_TRAP HOME="$TMP/home" TMPDIR="$TMP/t/" ${envs[@]+"${envs[@]}"} "$BIN" "$FX" --no-cache "$@" >"$TMP/out" 2>"$TMP/err" </dev/null ) 2>/dev/null; RC=$?   # 2>/dev/null: the shell's own "Trace/BPT trap" job line
    OUT="$( cat "$TMP/out" )"; ERR="$( cat "$TMP/err" )"
}

VER="$( "$BIN" --version 2>/dev/null )"
case "$VER" in
    *"(Release,"*|*"(RelWithDebInfo,"*|*"(MinSizeRel,"*) RELEASE=1 ;;
    *) RELEASE=0 ;;
esac
echo "  INFO  $VER (release=$RELEASE)"

if [ "$RELEASE" = 1 ]; then
    # (N) compiled out: no reader of the variable, no behaviour change
    if grep -q RIPWIRE_TEST_TRAP "$BIN"; then no "(N) the release binary carries the RIPWIRE_TEST_TRAP trigger string"; else ok "(N) the trigger string is not in the release binary"; fi
    run -- --for=area; base="$OUT"; berr="$ERR"
    run RIPWIRE_TEST_TRAP=expects -- --for=area
    if [ "$RC" = 0 ] && [ "$OUT" = "$base" ] && [ "$ERR" = "$berr" ] && [ ! -e "$CRASH" ]; then ok "(N) the trigger changes nothing in release (rc=0, stdout+stderr identical, no record)"; else no "(N) release rc=$RC or bytes moved or a record was written"; fi
    [ "$fail" = 0 ] && [ ! -e "$TMP/failed" ] && { echo "agenttrapcheck: PASS"; exit 0; }
    echo "agenttrapcheck: FAIL"; exit 1
fi

if grep -q RIPWIRE_TEST_TRAP "$BIN"; then ok "(N) a dev binary carries the trigger (the release arm's absence check is not vacuous)"; else no "(N) a dev binary has no RIPWIRE_TEST_TRAP string"; fi

# ── (C) CLI ──────────────────────────────────────────────────────────────────────────────────────────────────────────
run RIPWIRE_TEST_TRAP=expects -- --for=area
LINE="$( printf '%s\n' "$OUT" | grep '^<ripwire_internal_error ' )"
n="$( printf '%s\n' "$OUT" | grep -c '^<ripwire_internal_error ' )"
if [ "$n" = 1 ]; then ok "(C) stdout carries one <ripwire_internal_error/> line"; else no "(C) stdout has $n <ripwire_internal_error/> lines: $(printf '%s' "$OUT" | head -c 300)"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$LINE" | xmllint --noout - 2>/dev/null; then ok "(C) the line is well-formed XML"; else no "(C) the line is not well-formed: $LINE"; fi
else
    echo "  SKIP  (C) well-formed (no xmllint)"
fi
for a in 'kind="Expects"' 'expr="which != &quot;expects&quot;"' 'at="diagnostics.cpp:' 'fn="' 'note="RIPWIRE_TEST_TRAP=expects' 'version="' 'built_from="' 'hint="This is a ripwire bug'; do
    case "$LINE" in *"$a"*) ok "(C) line has $a" ;; *) no "(C) line lacks $a: $LINE" ;; esac
done
case "$ERR" in *"EXPECTS FAILED (precondition)"*) ok "(C) stderr keeps the notice" ;; *) no "(C) stderr lacks the notice: $ERR" ;; esac
case "$ERR" in *"  Next:     This is a ripwire bug, not your input."*) ok "(C) the notice has the actionable Next: row" ;; *) no "(C) the notice lacks Next:" ;; esac
case "$ERR" in *"look up the stack"*) no "(C) the notice still says 'look up the stack'" ;; *) ok "(C) the notice no longer says 'look up the stack'" ;; esac
if [ "$RC" -ge 128 ]; then ok "(C) exit status is the trap's signal (rc=$RC), apart from ripwire's 0-5"; else no "(C) rc=$RC (want the trap signal, >= 128)"; fi

# ── (R) the last-crash record, then the next call reports it once ─────────────────────────────────────────────────────
if [ -f "$CRASH" ]; then ok "(R) last-crash written to the cache dir"; else no "(R) no last-crash at \$TMPDIR/ripwire/last-crash"; fi
if python3 - "$CRASH" <<'X'
import json, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
assert lines[0].startswith("Expects which != \"expects\" at diagnostics.cpp:"), lines[0]
r = json.loads(lines[1])
assert r["kind"] == "Expects" and r["transport"] == "cli" and r["flags"] == "--no-cache --for" and r["request_id"] is None, r
assert r["argv"][-1] == "--for=area" and r["file"] == "diagnostics.cpp" and r["line"] > 0 and r["version"] and r["built_from"], r
X
then ok "(R) record: summary line + one JSON object (kind, transport=cli, flags, argv, version, built_from)"; else no "(R) record malformed: $(head -c 400 "$CRASH" 2>/dev/null)"; fi
run -- --for=area; first_out="$OUT"
n="$( printf '%s\n' "$ERR" | grep -c '^ripwire: the previous ripwire call failed an internal check' )"
if [ "$RC" = 0 ] && [ "$n" = 1 ]; then ok "(R) the next CLI call names the record on stderr, once"; else no "(R) next call rc=$RC, $n report lines: $ERR"; fi
case "$ERR" in *"Expects which != \"expects\""*) ok "(R) the report carries the summary" ;; *) no "(R) the report lacks the summary" ;; esac
if [ ! -e "$CRASH" ] && [ -z "$( ls "$TMP/t/ripwire/" 2>/dev/null | grep 'last-crash' )" ]; then ok "(R) the record is removed (no aside left)"; else no "(R) the record (or its aside) is still there"; fi
run -- --for=area
case "$ERR" in *"previous ripwire call"*) no "(R) a second call reported it again" ;; *) ok "(R) the call after that reports nothing" ;; esac

# every agent-visible kind names itself
for k in assume:Assume ensures:Ensures unreachable:Unreachable; do
    run "RIPWIRE_TEST_TRAP=${k%%:*}" -- --for=area
    case "$OUT" in
        *"<ripwire_internal_error kind=\"${k#*:}\""*)
            if [ "$RC" -ge 128 ]; then ok "(C) ${k#*:}: line + trap (rc=$RC)"; else no "(C) ${k#*:}: rc=$RC"; fi ;;
        *) no "(C) ${k#*:}: no line: $OUT" ;;
    esac
    rm -f "$CRASH"
done

# ── (I) inert without the trigger ─────────────────────────────────────────────────────────────────────────────────────
run -- --for=area; a_out="$OUT"; a_err="$ERR"; a_rc=$RC
run RIPWIRE_TEST_TRAP=off -- --for=area
if [ "$a_rc" = 0 ] && [ "$RC" = 0 ] && [ -n "$a_out" ] && [ "$OUT" = "$a_out" ] && [ "$ERR" = "$a_err" ] && [ "$OUT" = "$first_out" ] && [ ! -e "$CRASH" ]; then
    ok "(I) unset vs an unknown value: stdout+stderr byte-identical, rc=0, no record ($( printf '%s' "$OUT" | wc -c | tr -d ' ') B)"
else
    no "(I) the trigger's absence is not inert (rc=$a_rc/$RC, bytes ${#a_out}/${#OUT})"
fi

# ── (M) MCP stdio ─────────────────────────────────────────────────────────────────────────────────────────────────────
# mcp TRIGGER MODE: start the server as THIS script's child (python Popen), drive it, kill it by pid if it outlives the
# test. MODE trap = initialize + a tools/call under the trigger; MODE init = initialize twice in one server (the note
# must appear in the first only) + a plain tools/call.
mcp(){ ( cd "$FX" && env -u RIPWIRE_TEST_TRAP HOME="$TMP/home" TMPDIR="$TMP/t/" ${1:+RIPWIRE_TEST_TRAP=$1} python3 - "$BIN" "$FX" "$2" <<'X'
import json, subprocess, sys
bin_, fx, mode = sys.argv[1:4]
p = subprocess.Popen([bin_, fx, "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
def send(o): p.stdin.write((json.dumps(o) + "\n").encode()); p.stdin.flush()
def recv(): return p.stdout.readline().decode()
out = {}
try:
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "0"}}})
    out["init1"] = json.loads(recv())
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    if mode == "init":
        send({"jsonrpc": "2.0", "id": 2, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}}})
        out["init2"] = json.loads(recv())
    send({"jsonrpc": "2.0", "id": "trap-7", "method": "tools/call", "params": {"name": "find_symbol", "arguments": {"path": fx, "symbol": "total_area"}}})
    out["raw"] = recv()
    p.stdin.close()
    out["rc"] = p.wait(timeout=60)
except Exception as e:
    out["exc"] = repr(e)
finally:
    if p.poll() is None:
        p.kill(); p.wait()   # by pid: this child only
out["stderr"] = p.stderr.read().decode(errors="replace")
print(json.dumps(out))
X
) }
M="$( mcp expects trap )"
if python3 - "$M" <<'X'
import json, sys
m = json.loads(sys.argv[1]); assert "exc" not in m, m.get("exc")
r = json.loads(m["raw"])
assert r["jsonrpc"] == "2.0" and r["id"] == "trap-7", r.get("id")
e = r["error"]; d = e["data"]
assert e["code"] == -32603, e["code"]
assert e["message"].startswith("ripwire internal check failed (this is a ripwire bug): Expects which != \"expects\" at diagnostics.cpp:"), e["message"]
assert d["kind"] == "Expects" and d["file"] == "diagnostics.cpp" and d["line"] > 0 and d["function"] and d["note"].startswith("RIPWIRE_TEST_TRAP=expects"), d
assert d["version"] and d["built_from"] and "reconnect" in d["hint"], d
assert m["rc"] != 0, m["rc"]
assert "EXPECTS FAILED" in m["stderr"]
X
then ok "(M) tools/call under the trigger: a parseable JSON-RPC error for id \"trap-7\", code -32603, data.kind Expects, then the server exits"; else no "(M) MCP error missing or wrong: $( printf '%s' "$M" | head -c 600 )"; fi
if python3 - "$CRASH" <<'X'
import json, sys
r = json.loads(open(sys.argv[1], encoding="utf-8").read().split("\n")[1])
assert r["transport"] == "mcp-stdio" and r["tool"] == "find_symbol" and r["request_id"] == "trap-7" and r["kind"] == "Expects", r
X
then ok "(M) last-crash names transport mcp-stdio, tool find_symbol, request_id trap-7"; else no "(M) MCP record missing or wrong: $(head -c 400 "$CRASH" 2>/dev/null)"; fi
M="$( mcp '' init )"
if python3 - "$M" <<'X'
import json, sys
m = json.loads(sys.argv[1]); assert "exc" not in m, m.get("exc")
i1 = m["init1"]["result"]["instructions"]; i2 = m["init2"]["result"]["instructions"]
assert "the previous ripwire call ended on an internal check failure" in i1 and "Expects which != \"expects\"" in i1, i1[-400:]
assert "previous ripwire call" not in i2
assert m["stderr"].count("ripwire: the previous ripwire call failed an internal check") == 1, m["stderr"]
r = json.loads(m["raw"]); assert r["id"] == "trap-7" and "result" in r and "error" not in r, m["raw"][:300]
assert m["rc"] == 0, m["rc"]
X
then ok "(M) the next server's first initialize carries the note once (instructions + one stderr line), the second does not; a plain tools/call is a result"; else no "(M) initialize note wrong: $( printf '%s' "$M" | head -c 600 )"; fi
if [ ! -e "$CRASH" ]; then ok "(M) initialize removed the record"; else no "(M) the record survived initialize"; fi

# ── (H) MCP over --listen: the error is an HTTP/1.1 response (Content-Length framed) on the request's own socket ────────
rm -f "$CRASH"
H="$( cd "$FX" && env -u RIPWIRE_TEST_TRAP HOME="$TMP/home" TMPDIR="$TMP/t/" RIPWIRE_TEST_TRAP=expects RIPWIRE_MCP_TOKEN=agenttrap-gate python3 - "$BIN" "$FX" <<'X'
import http.client, json, socket, subprocess, sys
bin_, fx = sys.argv[1:3]
s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
p = subprocess.Popen([bin_, fx, "--mcp", "--listen=127.0.0.1:%d" % port], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
out = {}
def post(o):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=60)
    c.request("POST", "/mcp", json.dumps(o), {"Authorization": "Bearer agenttrap-gate", "Content-Type": "application/json", "Accept": "application/json, text/event-stream"})
    r = c.getresponse(); return r.status, r.getheader("Content-Length"), r.read().decode()
try:
    out["ready"] = p.stderr.readline().decode()   # the listener startup line: the socket is bound
    out["init"] = post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}})[0]
    out["status"], out["length"], out["body"] = post({"jsonrpc": "2.0", "id": 42, "method": "tools/call", "params": {"name": "find_symbol", "arguments": {"symbol": "total_area"}}})
    out["rc"] = p.wait(timeout=60)
except Exception as e:
    out["exc"] = repr(e)
finally:
    if p.poll() is None:
        p.kill(); p.wait()
print(json.dumps(out))
X
)"
if python3 - "$H" <<'X'
import json, sys
h = json.loads(sys.argv[1]); assert "exc" not in h, h.get("exc")
assert h["init"] == 200 and h["status"] == 200, h
assert h["length"] is not None and int(h["length"]) == len(h["body"].encode()), (h["length"], len(h["body"]))
r = json.loads(h["body"]); assert r["id"] == 42 and r["error"]["code"] == -32603 and r["error"]["data"]["kind"] == "Expects", r
assert h["rc"] != 0
X
then ok "(H) --listen: a 200 with an exact Content-Length and the JSON-RPC error for id 42 (data.kind Expects) on the request's socket"; else no "(H) HTTP error missing or wrong: $( printf '%s' "$H" | head -c 500 )"; fi
if python3 -c 'import json,sys; r=json.loads(open(sys.argv[1]).read().split("\n")[1]); assert r["transport"]=="mcp-http" and r["request_id"]==42, r' "$CRASH" 2>/dev/null; then ok "(H) last-crash names transport mcp-http, request_id 42"; else no "(H) HTTP record wrong: $(head -c 300 "$CRASH" 2>/dev/null)"; fi

[ "$fail" = 0 ] && [ ! -e "$TMP/failed" ] && { echo "agenttrapcheck: PASS"; exit 0; }
echo "agenttrapcheck: FAIL"; exit 1
