#!/usr/bin/env bash
# mcpframehonestycheck.sh — the capture-audit-4 wave-1 MCP lane: §H3 (an unterminated stdio frame was
# DISPATCHED, edit verbs included) plus the §B6 envelope-honesty tranche M3 / M5 / M6 / M7 / M8 / M9 / M10.
#
# THE LAW this file gates, in one line: a request is either WHOLE and read honestly, or it is REFUSED with the
# real cause — never half-answered, never answered about a different tree, and never answered with a cause that
# is about a different field than the one the caller got wrong.
#
#   §H3  [BROKEN HIGH]  nothing sat between the stdio read loop and the key-position scanner, and that scanner
#                       reads a complete `params` out of a TRUNCATED envelope — so a cut-off frame dispatched:
#                       a mid-stream `replace_symbol_body` REWROTE THE FILE, a `tools/list` with no closing
#                       brace returned a full successful listing, and a truncated tail refused with a FALSE
#                       cause about a field whose value was in the bytes. Arm (A), including a sha256 assertion
#                       that the edit target is byte-identical after the truncated write frame.
#   §B6 M6 [MISLEADING] `-32700 "parse error"` was the catch-all for FOUR unrelated inputs (truncated frame,
#                       spec-legal batch ARRAY, wrong-typed `method`, real garbage) naming no field/problem/
#                       got/example. Arm (B): four inputs, four distinct sentences, codes that fit them.
#   §B6 M7 [MISLEADING] wrong-TYPE envelope fields reported as MISSING (`"name":5` → "missing required field:
#                       name"), and a wrong-typed `arguments` — including the common host bug of a STRING of
#                       JSON — was SILENTLY IGNORED: the scope fell back to `params`, the caller's `path`
#                       vanished, and the verb answered about the DEFAULT root. Arm (C).
#   §B6 M5 [BROKEN]     an `id` containing invalid UTF-8 was spliced VERBATIM into every response, so the whole
#                       JSON-RPC line was invalid UTF-8 and a strict parser rejected a "successful" answer.
#                       Arm (D): the response line must always decode AND parse.
#   §B6 M3 [MISLEADING] false zeros: a nonexistent `path` and a FILE as `path` gave all-zero SUCCESS reports
#                       with the same `_index` hash. Arm (E) ENUMERATES the verbs from the live tools/list
#                       (never restates them) and requires every one to name which condition it hit.
#   §B6 M8 [GAP]        two JSON objects on one line: the second was silently dropped. Arm (F).
#   §B6 M9 [MISLEADING] `quality_baseline` over `paths` rendered the raw \x1f-separated workspace REGISTRY KEY
#                       into a client message under -32603 with the cause "unwritable directory?". Arm (G).
#   §B6 M10 [MISLEADING] a CORRUPT sidecar read as "no sidecar" — the only disclosure was a server-side stderr
#                       alert no MCP client surfaces. Arm (H).
#
# BOTH ARMS, AND BOTH TRANSPORTS. The framing gate lives in the SHARED handler (dispatchMcpLine), so the HTTP
# transport must return byte-identical refusal bodies for the same bytes — arm (A7)/(B6) assert that equality
# rather than re-listing the expectations, and the batch verb's own sub-query chain is probed in (E4).
#
# Usage:
#   test/mcpframehonestycheck.sh                                  # uses build/ripwire
#   test/mcpframehonestycheck.sh /path/to/other/ripwire           # positional binary (the RED run)
#   RIPWIRE_BIN=asan/ripwire test/mcpframehonestycheck.sh         # env binary
#
# Exits non-zero on any failure. Every mutation happens under a scratch mktemp dir; test/fixture is never
# modified. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }
command -v shasum  >/dev/null 2>&1 || { echo "shasum required for the §H3 byte-identity assertion"; exit 2; }

echo "mcpframehonestycheck: BIN=$BIN  FIX=$FIX"

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────
# one raw frame in, the LAST response line out (raw bytes — arm (D) needs the bytes, not a decoded string).
raw_one(){ printf '%s\n' "$1" | "$BIN" --mcp 2>/dev/null | tail -1; }

# "CODE|MESSAGE" for an error response, or "OK" for a result — the shape every refusal arm asserts on.
verdict(){ python3 -c '
import sys, json
d = sys.stdin.buffer.read()
try:    r = json.loads( d.decode( "utf-8" ) )
except Exception as e: print( "__BADLINE__:" + type( e ).__name__ ); raise SystemExit
if "error" in r: print( "%d|%s" % ( r["error"]["code"], r["error"]["message"] ) )
else:            print( "OK" )
'; }

frame_verdict(){ printf '%s\n' "$1" | "$BIN" --mcp 2>/dev/null | tail -1 | verdict; }

call(){ printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }
call_verdict(){ frame_verdict "$( call "$1" "$2" )"; }

# the batch arm: one sub-query over `path`, reported the way the batch envelope reports it.
batch_verdict(){ frame_verdict "$( call batch '{"path":"'"$1"'","queries":['"$2"']}' )"; }

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (A) §H3 — an INCOMPLETE frame is refused, not dispatched (and the edit target is untouched) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# (A1) the finding's own second probe: a tools/list frame with no closing brace returned a FULL LISTING.
A1="$( frame_verdict '{"jsonrpc":"2.0","id":816,"method":"tools/list"' )"
case "$A1" in
    -32700\|INCOMPLETE*) ok "(A1) truncated tools/list → -32700 naming the frame INCOMPLETE (was: a full successful listing)";;
    OK)                  no "(A1) truncated tools/list was ANSWERED — the framing gate is missing";;
    *)                   no "(A1) unexpected verdict: $A1";;
esac

# (A2) THE DESTRUCTIVE ONE. A truncated replace_symbol_body frame, mid-stream, with a well-formed frame after
# it: the write must not happen (sha256 identical), the refusal must name the framing fault, and the SESSION
# must survive (the following frame is still answered) — a gate that only checked the refusal would pass on a
# server that died instead of refusing.
W2="$( mktemp -d "$TMP/w2.XXXXXX" )"; cp -R "$FIX/"* "$W2/"
TARGET="$W2/geometry.cpp"
SHA_BEFORE="$( shasum -a 256 "$TARGET" | cut -d' ' -f1 )"
printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W2\",\"symbol\":\"distance\",\"file\":\"geometry.cpp\",\"new_body\":\"double distance(){return 0;}\"}}" \
    '{"jsonrpc":"2.0","id":3,"method":"tools/list"}' \
    | "$BIN" --mcp >"$TMP/a2.out" 2>/dev/null
SHA_AFTER="$( shasum -a 256 "$TARGET" | cut -d' ' -f1 )"
[ "$SHA_BEFORE" = "$SHA_AFTER" ] \
    && ok "(A2) a truncated replace_symbol_body frame leaves the file BYTE-IDENTICAL (sha256 unchanged)" \
    || no "(A2) *** the truncated edit frame REWROTE the file *** $SHA_BEFORE -> $SHA_AFTER"
A2V="$( sed -n 2p "$TMP/a2.out" | verdict )"
case "$A2V" in
    -32700\|INCOMPLETE*) ok "(A2) the truncated write frame is refused as INCOMPLETE";;
    OK)                  no "(A2) the truncated write frame reported success: $( sed -n 2p "$TMP/a2.out" | head -c 140 )";;
    *)                   no "(A2) truncated write frame verdict: $A2V";;
esac
[ "$( sed -n 3p "$TMP/a2.out" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id"))' 2>/dev/null )" = 3 ] \
    && ok "(A2) the session SURVIVES the refusal — the next frame is still answered (id 3)" \
    || no "(A2) the frame after the truncated one was not answered — the server did not survive"

# (A3) the truncated TAIL at EOF, which used to refuse with a FALSE cause: the `path`/`pattern` the caller sent
# was in the bytes, just past the cut, and the refusal named it MISSING.
printf '%s\n%s' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FIX\",\"pattern\":\"dist" \
    | "$BIN" --mcp >"$TMP/a3.out" 2>/dev/null
A3="$( tail -1 "$TMP/a3.out" | verdict )"
case "$A3" in
    *"missing required field"*) no "(A3) the truncated tail STILL refuses with a false cause: $A3";;
    -32700\|INCOMPLETE*)        ok "(A3) the truncated EOF tail names the framing fault, not a field the caller sent";;
    *)                          no "(A3) truncated tail verdict: $A3";;
esac
[ "$( grep -c . "$TMP/a3.out" )" = 2 ] \
    && ok "(A3) the unterminated tail is answered exactly once (2 lines: init + its refusal)" \
    || no "(A3) $( grep -c . "$TMP/a3.out" ) response lines, want 2"

# (A4) an UNTERMINATED STRING inside an otherwise brace-balanced frame — the truncation a brace counter alone
# would miss, and the reason the gate walks strings with the same escape-aware walk the key scanner uses.
case "$( frame_verdict '{"jsonrpc":"2.0","id":1,"method":"tools/list' )" in
    -32700\|INCOMPLETE*) ok "(A4) an unterminated STRING is INCOMPLETE (a brace count alone would call this balanced)";;
    *) no "(A4) unterminated string verdict: $( frame_verdict '{"jsonrpc":"2.0","id":1,"method":"tools/list' )";;
esac
# an escaped quote must NOT be read as the string's end (the frame below is complete and must be ANSWERED).
case "$( frame_verdict '{"jsonrpc":"2.0","id":"a\"b","method":"tools/list"}' )" in
    OK) ok "(A4) an escaped \\\" inside a value does not end the string — the complete frame is answered";;
    *)  no "(A4) a complete frame with an escaped quote was refused: $( frame_verdict '{"jsonrpc":"2.0","id":"a\"b","method":"tools/list"}' )";;
esac
# a brace INSIDE a string is not structure.
case "$( frame_verdict "$( call grep '{"path":"'"$FIX"'","pattern":"}{"}' )" )" in
    OK) ok "(A4) braces inside a string VALUE are not counted as structure (the request is answered)";;
    *)  no "(A4) a pattern of '}{' was mis-read as structure";;
esac

# (A5) a MISMATCHED closer is invalid JSON, not truncation — a plain depth counter cannot tell them apart.
case "$( frame_verdict '{"jsonrpc":"2.0","id":1,"method":"tools/list"]' )" in
    -32700\|*"does not match"*) ok "(A5) a closer that does not match its opener is named as such";;
    *) no "(A5) mismatched closer verdict: $( frame_verdict '{"jsonrpc":"2.0","id":1,"method":"tools/list"]' )";;
esac
case "$( frame_verdict '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"analyze"]}' )" in
    -32700\|*"does not match"*) ok "(A5) a NESTED mismatched closer is caught too (the stack, not a counter)";;
    *) no "(A5) nested mismatch verdict: $( frame_verdict '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"analyze"]}' )";;
esac

# (A6) THE CONTROLS — everything well-formed still behaves exactly as before, including the two framing shapes
# the read loop is contractually required to tolerate (a kept trailing '\r', and blank lines it SKIPS).
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '' '   ' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    "$( call grep '{"path":"'"$FIX"'","pattern":"distance"}' )" >"$TMP/a6.in"
printf '{"jsonrpc":"2.0","id":9,"method":"initialize"}\r\n' >>"$TMP/a6.in"
"$BIN" --mcp <"$TMP/a6.in" >"$TMP/a6.out" 2>/dev/null
[ "$( grep -c . "$TMP/a6.out" )" = 4 ] \
    && ok "(A6) blank lines still skipped, the notification still unanswered, the CRLF frame still answered (4 lines)" \
    || no "(A6) $( grep -c . "$TMP/a6.out" ) response lines, want 4 (blank-skip / notification / CRLF behaviour moved)"
[ "$( python3 -c 'import sys,json;print(json.loads(open(sys.argv[1]).read().strip().split("\n")[-1]).get("id"))' "$TMP/a6.out" )" = 9 ] \
    && ok "(A6) the trailing CRLF frame is answered (a kept '\\r' is whitespace to the framing gate)" \
    || no "(A6) the CRLF frame's answer is missing — the gate rejected a kept trailing '\\r'"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (B) §B6 M6 — the -32700 catch-all, split into four honest refusals ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
B_METHOD="$( frame_verdict '{"jsonrpc":"2.0","id":1,"method":5}' )"
case "$B_METHOD" in
    -32600\|*"field: method"*"got '5'"*) ok "(B1) a wrong-TYPED method → -32600 naming the field, the expected type and the got-value";;
    -32700*) no "(B1) `method:5` is still 'parse error' — the JSON parsed fine: $B_METHOD";;
    *)       no "(B1) method:5 verdict: $B_METHOD";;
esac
case "$B_METHOD" in *"e.g. method="*) ok "(B1) …and something runnable to type";; *) no "(B1) the refusal carries no example: $B_METHOD";; esac

B_BATCH="$( frame_verdict '[{"jsonrpc":"2.0","id":1,"method":"tools/list"},{"jsonrpc":"2.0","id":2,"method":"initialize"}]' )"
case "$B_BATCH" in
    -32600\|*batch*not\ supported*) ok "(B2) a spec-legal top-level batch ARRAY → -32600 saying batching is not supported";;
    -32700*) no "(B2) the batch array is still called unparseable — it parses perfectly: $B_BATCH";;
    *)       no "(B2) batch-array verdict: $B_BATCH";;
esac
case "$B_BATCH" in *'{"jsonrpc":"2.0"'*) ok "(B2) …and names the single-request form to send instead";; *) no "(B2) no single-request form named: $B_BATCH";; esac
# the honesty half: ONE response for TWO requests was the actual old behaviour. Exactly one line, and it is a refusal.
printf '%s\n' '[{"jsonrpc":"2.0","id":1,"method":"tools/list"},{"jsonrpc":"2.0","id":2,"method":"initialize"}]' \
    | "$BIN" --mcp >"$TMP/b2.out" 2>/dev/null
{ [ "$( grep -c . "$TMP/b2.out" )" = 1 ] && grep -q '"error"' "$TMP/b2.out"; } \
    && ok "(B2) the batch frame yields ONE line and it is a refusal (never one answer standing in for two)" \
    || no "(B2) batch frame produced $( grep -c . "$TMP/b2.out" ) lines: $( head -c 120 "$TMP/b2.out" )"

B_JUNK="$( frame_verdict 'not json at all' )"
case "$B_JUNK" in
    -32700\|*"parse error"*"got 'not json at all'"*) ok "(B3) genuinely unparseable bytes keep -32700 'parse error' AND now say what was wrong";;
    -32700\|*"parse error") no "(B3) real garbage still gets the bare catch-all with nothing got: $B_JUNK";;
    *) no "(B3) garbage verdict: $B_JUNK";;
esac
B_NOMETHOD="$( frame_verdict '{"jsonrpc":"2.0","id":1}' )"
case "$B_NOMETHOD" in
    -32600\|"missing required field: method"*) ok "(B4) a well-formed object with NO method → -32600 missing required field: method";;
    -32700*) no "(B4) a valid JSON object with no method is still called a parse error: $B_NOMETHOD";;
    *) no "(B4) no-method verdict: $B_NOMETHOD";;
esac

# (B5) the whole point of the item: the four inputs must be FOUR distinct sentences, not one.
A1M="$( frame_verdict '{"jsonrpc":"2.0","id":1,"method":"tools/list"' )"
DISTINCT="$( printf '%s\n%s\n%s\n%s\n%s\n' "$A1M" "$B_METHOD" "$B_BATCH" "$B_JUNK" "$B_NOMETHOD" | sort -u | grep -c . )"
[ "$DISTINCT" = 5 ] \
    && ok "(B5) all five envelope faults speak DIFFERENT sentences (truncated / method-type / batch / garbage / no-method)" \
    || no "(B5) only $DISTINCT distinct sentences across the five faults — the catch-all is still collapsing cases"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (C) §B6 M7 — wrong-SHAPED envelope fields refuse; a wrong-typed \`arguments\` never falls back ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
for bad in '5' 'null' '["analyze"]' '{"a":1}'; do
    V="$( frame_verdict '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":'"$bad"',"arguments":{"path":"'"$FIX"'"}}}' )"
    case "$V" in
        *"missing required field: name"*) no "(C1) name:$bad is reported MISSING — the absent-vs-wrong-shape collapse: $V";;
        *"invalid value for field: name"*) ok "(C1) name:$bad → invalid VALUE for name, with the expected type and the got-value";;
        *) no "(C1) name:$bad verdict: $V";;
    esac
done

# The silent one. With a startup root, a wrong-typed `arguments` answered about THAT root while the caller's
# `path` (a 1-file subdir) was dropped — so the assertion is a REFUSAL, and the control proves the sub-path
# request is otherwise served.
SUB="$FIX/sub"
args_stamp(){ printf '%s\n' "$1" | "$BIN" "$FIX" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
if "error" in r: print( "REFUSED|" + r["error"]["message"] )
else:            print( "ANSWERED|" + r["result"].get( "_index", "" ) )
'; }
C2="$( args_stamp '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"analyze","arguments":5}}' )"
case "$C2" in
    REFUSED\|*"field: arguments"*) ok "(C2) arguments:5 REFUSES naming the field (was: answered about the default root)";;
    ANSWERED*) no "(C2) arguments:5 was silently ignored and answered: $C2";;
    *) no "(C2) arguments:5 verdict: $C2";;
esac
C3="$( args_stamp '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"analyze","arguments":"{\"path\":\"'"$SUB"'\"}"}}' )"
case "$C3" in
    REFUSED\|*"field: arguments"*) ok "(C3) the common host bug — \`arguments\` as a STRING of JSON — REFUSES instead of dropping every argument in it";;
    ANSWERED*) no "(C3) a JSON-STRING \`arguments\` still answers about the wrong tree: $C3";;
    *) no "(C3) arguments-as-string verdict: $C3";;
esac
C3C="$( args_stamp '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"analyze","arguments":{"path":"'"$SUB"'"}}}' )"
case "$C3C" in
    ANSWERED\|*files=1*) ok "(C3) control: the same request with a real \`arguments\` object answers about the SUB tree (files=1)";;
    *) no "(C3) control: a well-formed sub-path request did not answer about the sub tree: $C3C";;
esac

for bad in '5' '"x"' '["a"]'; do
    V="$( frame_verdict '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":'"$bad"'}' )"
    case "$V" in
        *"invalid value for field: params"*) ok "(C4) params:$bad → invalid VALUE for params (was: silently ignored, then a refusal about \`path\`)";;
        *) no "(C4) params:$bad verdict: $V";;
    esac
done

# (C5) THE CONTROLS. `null` means "no parameters" to real MCP hosts (test/mcpreadloopcheck.sh's hostile corpus
# carries both spellings) and must keep reading as ABSENT, not as a shape fault; and the FLATTENED form — args
# at `params` level, no `arguments` object — must keep working, because findArgsScope tolerated it and the
# guarded reader has to tolerate exactly the same set.
for nullish in '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":null}' \
               '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grep","arguments":null}}'; do
    V="$( frame_verdict "$nullish" )"
    case "$V" in
        *"invalid value"*) no "(C5) a null params/arguments is treated as a SHAPE fault — that breaks real hosts: $V";;
        *"missing required field"*) ok "(C5) a null params/arguments still reads as ABSENT (the verb's own missing-field message)";;
        *) no "(C5) nullish verdict: $V";;
    esac
done
C5F="$( frame_verdict '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grep","path":"'"$FIX"'","pattern":"distance"}}' )"
case "$C5F" in
    OK) ok "(C5) control: the FLATTENED form (arguments at \`params\` level) still answers — the tolerated set is unchanged";;
    *)  no "(C5) the flattened argument form broke: $C5F";;
esac

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (D) §B6 M5 — an id with invalid UTF-8 must never corrupt the response line ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
utf8_probe(){ python3 - "$BIN" "$1" <<'PY'
import subprocess, sys, json
binPath, kind = sys.argv[ 1 : 3 ]
bad = { "ff": b"\xff\xfe", "overlong": b"\xc0\xaf", "lonecont": b"\x80", "truncated": b"\xe2\x82" }[ kind ]
frame = b'{"jsonrpc":"2.0","id":"a' + bad + b'b","method":"tools/list"}\n'
out = subprocess.run( [ binPath, "--mcp" ], input=frame, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL ).stdout
line = [ l for l in out.split( b"\n" ) if l.strip() ][ -1 ] if out.strip() else b""
try:               text = line.decode( "utf-8" )
except Exception:  print( "INVALID_UTF8" ); raise SystemExit
try:               print( "id=" + json.dumps( json.loads( text ).get( "id" ) ) )
except Exception:  print( "BADJSON" )
PY
}
for kind in ff overlong lonecont truncated; do
    R="$( utf8_probe "$kind" )"
    case "$R" in
        id=null) ok "(D) an id containing invalid UTF-8 ($kind) → the line is valid UTF-8, parses, and the id degrades to null";;
        INVALID_UTF8) no "(D) the $kind id was spliced VERBATIM — the whole response line is invalid UTF-8";;
        *) no "(D) $kind id: $R";;
    esac
done
# the control that keeps the fix from being a blunt instrument: a VALID multibyte id is still echoed verbatim.
D_OK="$( python3 - "$BIN" <<'PY'
import subprocess, sys, json
out = subprocess.run( [ sys.argv[1], "--mcp" ], input='{"jsonrpc":"2.0","id":"café","method":"tools/list"}\n'.encode(),
                      stdout=subprocess.PIPE, stderr=subprocess.DEVNULL ).stdout
print( json.loads( out.decode( "utf-8" ).strip().split( "\n" )[ -1 ] ).get( "id" ) )
PY
)"
if [ "$D_OK" = "café" ]; then
    ok "(D) control: a VALID multibyte id is still echoed verbatim ($D_OK)"
else
    no "(D) a valid multibyte id was destroyed: $D_OK"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (E) §B6 M3 — a nonexistent path and a FILE-as-path name WHICH condition, on every verb ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# THE ARM THAT MUST NOT RESTATE THE CODE: the verb list is ENUMERATED from the live tools/list, so a verb that
# joins the server joins this arm automatically (the M14 lesson: a gate that restates the table cannot catch it).
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | "$BIN" --mcp 2>/dev/null | tail -1 >"$TMP/tools.json"
python3 - "$TMP/tools.json" >"$TMP/verbargs.txt" <<'PY'
import sys, json
# one minimal argument set per verb, so the request reaches the path check rather than a missing-field refusal.
need = { "symbol": '"distance"', "pattern": '"x"', "file": '"a.cpp"', "task": '"t"', "type": '"Shape"',
         "handle": '"sym#0000000000000000@0000000000000000"', "from": '"a"', "to": '"b"',
         "trace": '"File \\"x.py\\", line 3, in f"', "new_body": '"x"', "text": '"x"',
         "queries": '[{"verb":"grep","pattern":"x"}]', "symbols": '["a","b"]', "kind": '"fn"' }
tools = json.load( open( sys.argv[1] ) )["result"]["tools"]
for t in tools:
    schema = t.get( "inputSchema", {} )
    req    = list( schema.get( "required", [] ) )
    # exemplar's kind-or-task is an anyOf in practice: give it `kind` so the call is complete.
    if t["name"] == "exemplar" and not req: req = [ "kind" ]
    parts = [ '"%s":%s' % ( f, need[f] ) for f in req if f in need ]
    print( "%s\t{%s}" % ( t["name"], ",".join( parts ) ) )
PY
VERBS="$( grep -c . "$TMP/verbargs.txt" )"
[ "$VERBS" -ge 30 ] \
    && ok "(E) enumerated $VERBS advertised verbs from the live tools/list (not restated here)" \
    || no "(E) only enumerated $VERBS verbs — the enumeration broke"

BADPATH="$TMP/no/such/tree"
FILEPATH="$FIX/geometry.cpp"
# ONE SESSION for the whole 2xN sweep. Every probe here is an independent tools/call judged purely on the
# SHAPE of its response — nothing in this arm asserts startup, restart, staleness-reload or watcher
# behaviour, and every `path` is bad so no probe registers a workspace another could inherit — so the frames
# go down one stdio pipe instead of forking 2xN servers. `verdict`'s three outcomes are reproduced exactly
# (CODE|MESSAGE / OK / __BADLINE__:Type); a dead pipe yields the same __BADLINE__ row a dead process did.
python3 - "$BIN" "$TMP/verbargs.txt" "$BADPATH" "$FILEPATH" >"$TMP/verbverdicts.txt" <<'PY'
import json, subprocess, sys
binPath, table, badPath, filePath = sys.argv[ 1 : 5 ]
rows = [ l.rstrip( "\n" ).split( "\t" ) for l in open( table ) if l.strip() ]
p = subprocess.Popen( [ binPath, "--mcp" ], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                      stderr=subprocess.DEVNULL )
def send( obj ):                                       # raw bytes back, exactly what `verdict` is handed
    p.stdin.write( json.dumps( obj ).encode() + b"\n" ); p.stdin.flush()
    return p.stdout.readline()
send( { "jsonrpc": "2.0", "id": 1, "method": "initialize" } )
for verb, argstub in rows:
    for cond, path in ( ( "missing", badPath ), ( "file", filePath ) ):
        args = json.loads( argstub ); args[ "path" ] = path
        line = send( { "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                       "params": { "name": verb, "arguments": args } } )
        try:                   r = json.loads( line.decode( "utf-8" ) )
        except Exception as e: v = "__BADLINE__:" + type( e ).__name__
        else:                  v = "%d|%s" % ( r["error"]["code"], r["error"]["message"] ) if "error" in r else "OK"
        # one row per probe, so the shell classifier below is unchanged apart from where it reads from.
        # tab/newline are the row's own delimiters — neutralised so a message can never split a row.
        print( "%s\t%s\t%s" % ( verb, cond, v.replace( "\t", " " ).replace( "\r", " " ).replace( "\n", " " ) ) )
p.stdin.close(); p.wait( 15 )
PY
missCount=0; fileCount=0; missBad=""; fileBad=""
while IFS="$( printf '\t' )" read -r verb cond V; do
    [ -n "$verb" ] || continue
    if [ "$cond" = missing ]; then
        case "$V" in -32602\|"path does not exist"*) missCount=$(( missCount + 1 ));; *) missBad="$missBad $verb($V)";; esac
    else
        case "$V" in -32602\|"path is a FILE"*)      fileCount=$(( fileCount + 1 ));; *) fileBad="$fileBad $verb($V)";; esac
    fi
done <"$TMP/verbverdicts.txt"
[ "$missCount" = "$VERBS" ] \
    && ok "(E1) all $VERBS verbs refuse a NONEXISTENT path naming that condition (was: 9 answered all-zero SUCCESS, the rest gave false causes)" \
    || no "(E1) $missCount/$VERBS named the condition; deviations:$( printf '%s' "$missBad" | cut -c1-400 )"
[ "$fileCount" = "$VERBS" ] \
    && ok "(E2) all $VERBS verbs refuse a FILE-as-path naming that condition" \
    || no "(E2) $fileCount/$VERBS named the condition; deviations:$( printf '%s' "$fileBad" | cut -c1-400 )"

# (E3) the CONTROL that keeps the check honest: an EMPTY but REAL directory is a valid empty answer, not a
# refusal — "nothing there" and "no such place" are different answers (the CLI's own rule).
EMPTY="$( mktemp -d "$TMP/empty.XXXXXX" )"
case "$( call_verdict analyze '{"path":"'"$EMPTY"'"}' )" in
    OK) ok "(E3) control: an EMPTY but real directory still answers (an empty tree is a measurement)";;
    *)  no "(E3) an empty directory is now refused — the check over-reaches: $( call_verdict analyze '{"path":"'"$EMPTY"'"}' )";;
esac
case "$( call_verdict grep '{"path":"'"$FIX"'","pattern":"distance"}' )" in
    OK) ok "(E3) control: a real tree still answers";;
    *)  no "(E3) a real tree stopped answering";;
esac

# (E4) the SECOND arm: the batch verb's own chain shares the batch's root, so the same two conditions must
# arrive with the same two causes there.
case "$( batch_verdict "$BADPATH" '{"verb":"grep","pattern":"x"}' )" in
    -32602\|"path does not exist"*) ok "(E4) batch arm: a nonexistent root names the condition";;
    *) no "(E4) batch arm nonexistent root: $( batch_verdict "$BADPATH" '{"verb":"grep","pattern":"x"}' )";;
esac
case "$( batch_verdict "$FILEPATH" '{"verb":"grep","pattern":"x"}' )" in
    -32602\|"path is a FILE"*) ok "(E4) batch arm: a FILE root names the condition";;
    *) no "(E4) batch arm file root: $( batch_verdict "$FILEPATH" '{"verb":"grep","pattern":"x"}' )";;
esac

# (E5) the EDIT verbs' safety contract under the same two conditions: the refusal must precede any write, so a
# real file passed as `path` is byte-identical afterward.
W5="$( mktemp -d "$TMP/w5.XXXXXX" )"; cp "$FIX/geometry.cpp" "$W5/geometry.cpp"
SHA5="$( shasum -a 256 "$W5/geometry.cpp" | cut -d' ' -f1 )"
call_verdict replace_symbol_body '{"path":"'"$W5/geometry.cpp"'","symbol":"distance","new_body":"double distance(){return 0;}"}' >/dev/null
[ "$( shasum -a 256 "$W5/geometry.cpp" | cut -d' ' -f1 )" = "$SHA5" ] \
    && ok "(E5) an edit verb given a FILE as \`path\` leaves that file byte-identical" \
    || no "(E5) an edit verb given a FILE as \`path\` MODIFIED it"

# (E6) the refusal written for this case (analyze's "empty corpus or unreadable directory") was UNREACHABLE
# because analyzeToString always emits the legend — so it must not still be shipping that false cause.
grep -q "empty corpus or unreadable directory" "$ROOT/src/mcp.h" \
    && no "(E6) the unreachable analyze refusal with its false cause is still in src/mcp.h" \
    || ok "(E6) the unreachable 'empty corpus or unreadable directory' cause is gone from src/mcp.h"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (F) §B6 M8 — two JSON objects on one line: refused, never silently half-answered ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}{"jsonrpc":"2.0","id":2,"method":"initialize"}' \
    | "$BIN" --mcp >"$TMP/f.out" 2>/dev/null
F="$( tail -1 "$TMP/f.out" | verdict )"
case "$F" in
    -32600\|"one JSON-RPC request per frame"*) ok "(F) two objects on one line → refused, naming the one-frame-per-line contract";;
    OK) no "(F) the first object was answered and the second silently DROPPED: $F";;
    *) no "(F) two-object verdict: $F";;
esac
{ [ "$( grep -c . "$TMP/f.out" )" = 1 ] && ! grep -q '"result"' "$TMP/f.out"; } \
    && ok "(F) …and neither request was answered (one line, no result)" \
    || no "(F) $( grep -c . "$TMP/f.out" ) lines / a result slipped through"
case "$F" in *"got '{"*) ok "(F) …and the refusal ECHOES the trailing bytes so the caller can see the second frame";; *) no "(F) the refusal does not echo what followed: $F";; esac

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (G) §B6 M9 — quality_baseline over \`paths\`: right code, real cause, no internal key rendered ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
WS="$( mktemp -d "$TMP/ws.XXXXXX" )"; mkdir -p "$WS/r1" "$WS/r2"
cp "$FIX/geometry.cpp" "$WS/r1/"; cp "$FIX/app.py" "$WS/r2/"
G="$( call_verdict quality_baseline '{"paths":["'"$WS/r1"'","'"$WS/r2"'"]}' )"
case "$G" in
    -32602\|*single-root*) ok "(G) quality_baseline over \`paths\` → -32602 (a caller usage error), naming that it is single-root";;
    -32603*) no "(G) still -32603 'internal error' for a caller usage error: $G";;
    *) no "(G) quality_baseline multi-root verdict: $G";;
esac
case "$G" in
    *"unwritable directory"*) no "(G) still blames the filesystem for a request-shape problem: $G";;
    *) ok "(G) …and no longer blames an 'unwritable directory'";;
esac
# the registry key is \x1f-separated; jsonEscape renders that as . Neither spelling may reach a client.
printf '%s\n' "$( call quality_baseline '{"paths":["'"$WS/r1"'","'"$WS/r2"'"]}' )" | "$BIN" --mcp 2>/dev/null | tail -1 >"$TMP/g.out"
{ ! grep -q 'u001f' "$TMP/g.out" && ! LC_ALL=C grep -q "$( printf '\037' )" "$TMP/g.out"; } \
    && ok "(G) the raw \\x1f workspace REGISTRY KEY never reaches the client (neither raw nor \\u001f)" \
    || no "(G) the internal registry key is still rendered into the message"
case "$( call_verdict quality_baseline '{"path":"'"$WS/r1"'"}' )" in
    OK) ok "(G) control: single-root quality_baseline still writes its sidecar";;
    *)  no "(G) single-root quality_baseline broke: $( call_verdict quality_baseline '{"path":"'"$WS/r1"'"}' )";;
esac

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (H) §B6 M10 — a CORRUPT sidecar is disclosed in the marker, not only in a stderr alert ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
WQ="$( mktemp -d "$TMP/wq.XXXXXX" )"; cp -R "$FIX/"* "$WQ/"
( cd "$WQ" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
marker(){ printf '%s\n' "$( call quality_delta '{"path":"'"$WQ"'"}' )" | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
if "error" in r: print( "__ERROR__:" + r["error"]["message"][:80] ); raise SystemExit
print( json.loads( r["result"]["content"][0]["text"] )["baseline"] )
'; }
[ "$( marker )" = "git-HEAD" ] \
    && ok "(H) no sidecar → baseline=\"git-HEAD\"" \
    || no "(H) no-sidecar marker is $( marker ), want git-HEAD"
printf 'not a baseline at all\nzzz\n' >"$WQ/.ripwire_quality_baseline"
CORRUPT="$( marker )"
case "$CORRUPT" in
    *"unreadable sidecar"*) ok "(H) a CORRUPT sidecar is disclosed in the marker: \"$CORRUPT\"";;
    "git-HEAD") no "(H) a corrupt sidecar still reads as NO sidecar — the only disclosure is a stderr alert no client sees";;
    *) no "(H) corrupt-sidecar marker: $CORRUPT";;
esac
: >"$WQ/.ripwire_quality_baseline"
case "$( marker )" in
    *"unreadable sidecar"*) ok "(H) an EMPTY sidecar reports the same state (readBaseline rejects both identically)";;
    *) no "(H) empty-sidecar marker: $( marker )";;
esac
[ -s "$WQ/.ripwire_quality_baseline" ] || [ -f "$WQ/.ripwire_quality_baseline" ] \
    && ok "(H) the read-only arm LEFT the unreadable sidecar on disk (quality_delta never deletes)" \
    || no "(H) the MCP arm deleted a sidecar — this verb is read-only"
rm -f "$WQ/.ripwire_quality_baseline"
printf '%s\n' "$( call quality_baseline '{"path":"'"$WQ"'"}' )" | "$BIN" --mcp >/dev/null 2>&1
[ "$( marker )" = "sidecar" ] \
    && ok "(H) control: a VALID sidecar is still honored (baseline=\"sidecar\")" \
    || no "(H) a valid sidecar is no longer honored: $( marker )"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (I) the HTTP transport returns BYTE-IDENTICAL bodies for the same bytes (one shared handler) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# The framing gate lives in dispatchMcpLine, which both transports route through — so this arm asserts EQUALITY
# with the stdio answers above rather than re-listing the expectations (a second list is a second thing to drift).
# WAIT ON THE CONDITION, not on a guess: poll until the listener ACCEPTS a TCP connection on $PORT (20 ms
# interval, 30 s ceiling), abandoning the wait the moment the child dies. Exit 1 covers both give-up reasons,
# which the caller then tells apart — a dead child and a live-but-unreachable one are different faults and
# get different sentences. Either way the arm FAILS loudly; it never probes a server that is not there.
wait_listening(){ python3 - "$1" "$2" <<'PY'
import os, socket, sys, time
port, pid = int( sys.argv[1] ), int( sys.argv[2] )
deadline = time.time() + 30.0
while time.time() < deadline:
    try:               os.kill( pid, 0 )              # the child is gone — stop waiting on a dead port
    except OSError:    sys.exit( 1 )
    try:
        socket.create_connection( ( "127.0.0.1", port ), 0.25 ).close()
        sys.exit( 0 )
    except OSError:    time.sleep( 0.02 )
sys.exit( 1 )
PY
}
PORT=$(( 21000 + ( $$ % 9000 ) ))
"$BIN" "$FIX" --listen=127.0.0.1:"$PORT" >"$TMP/http.log" 2>&1 &
HTTP_PID=$!
wait_listening "$PORT" "$HTTP_PID"; LISTENING=$?
if ! kill -0 "$HTTP_PID" 2>/dev/null; then
    no "(I) the HTTP listener did not start: $( head -c 200 "$TMP/http.log" )"
elif [ "$LISTENING" != 0 ]; then
    no "(I) the HTTP listener never ACCEPTED on 127.0.0.1:$PORT within 30 s: $( head -c 200 "$TMP/http.log" )"
    kill "$HTTP_PID" 2>/dev/null; wait "$HTTP_PID" 2>/dev/null
else
    http_body(){ python3 - "$PORT" "$1" <<'PY'
import socket, sys
port, body = int( sys.argv[1] ), sys.argv[2].encode()
req = ( b"POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n"
        b"Accept: application/json, text/event-stream\r\nContent-Length: " + str( len( body ) ).encode()
        + b"\r\n\r\n" + body )
s = socket.create_connection( ( "127.0.0.1", port ), 5 ); s.sendall( req )
chunks = b""
while True:
    c = s.recv( 65536 )
    if not c: break
    chunks += c
    head, sep, tail = chunks.partition( b"\r\n\r\n" )
    if sep and tail.endswith( b"}" ): break
s.close()
sys.stdout.write( chunks.partition( b"\r\n\r\n" )[2].decode( "utf-8", "replace" ) )
PY
    }
    for frame in '{"jsonrpc":"2.0","id":1,"method":"tools/list"' \
                 '[{"jsonrpc":"2.0","id":1,"method":"tools/list"}]' \
                 '{"jsonrpc":"2.0","id":1,"method":"tools/list"}{"jsonrpc":"2.0","id":2,"method":"initialize"}' \
                 '{"jsonrpc":"2.0","id":1,"method":5}' \
                 '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":5}'; do
        S="$( raw_one "$frame" )"
        H="$( http_body "$frame" )"
        [ "$S" = "$H" ] \
            && ok "(I) stdio == HTTP for $( printf '%s' "$frame" | cut -c1-46 )…" \
            || no "(I) transports DIFFER for $( printf '%s' "$frame" | cut -c1-46 )…  stdio=$( printf '%s' "$S" | cut -c1-90 )  http=$( printf '%s' "$H" | cut -c1-90 )"
    done
    kill "$HTTP_PID" 2>/dev/null
    wait "$HTTP_PID" 2>/dev/null
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (J) ITEM A — a WHITESPACE-ONLY payload is the same unset argument as an omitted one ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# The §H2 ruling ("an omitted payload and new_body:\"\" are the same refusal") was pinned as !empty(), so
# anything of size >= 1 passed it and a whitespace-only payload still DELETED the definition and reported
# {"applied":…}. The ruling's real class is "a payload that carries no definition" — see src/infra/blanktext.h's
# isMcpEditVerb header for the derived rule and why the read verbs' strings are NOT widened.
#
# Every case asserts THREE things at once: the verdict, the DEFINITION still being on disk, and the refusal
# message being the SAME missing-field sentence (the caller's mistake is the same mistake). The positives at
# the end are what stop the rule from becoming "reject anything with leading whitespace".
#
# (J) asserts CLASSES a human enumerated, at the readable end; section (K) below asserts the derived TABLE at
# its range boundaries, mechanically, because F2's lesson is that a human enumeration of this set is wrong by
# construction. Two arms, two different questions — do not fold one into the other.
python3 - "$BIN" <<'PY'
import hashlib, json, os, shutil, subprocess, sys, tempfile

BIN = sys.argv[1]
SRC = ( "// alpha adds one.\nint alpha( int x ) { return x + 1; }\n\n"
        "// beta doubles.\nint beta( int x ) { return x * 2; }\n" )

# label, payload, must-refuse
CASES = [
    ( "ascii space",      " ",                                 True  ),
    ( "newline",          "\n",                                 True  ),
    ( "tab",              "\t",                                 True  ),
    ( "CR",               "\r",                                 True  ),
    ( "VT+FF",            "\v\f",                               True  ),
    ( "mixed ASCII ws",   "   \n\t  ",                          True  ),
    ( "NUL",              "\u0000",                             True  ),
    ( "DEL",              "\u007f",                             True  ),
    ( "NBSP U+00A0",      " ",                             True  ),
    ( "ZWSP U+200B",      "​",                             True  ),
    ( "BOM U+FEFF",       "﻿",                             True  ),
    ( "EM space U+2003",  " ",                             True  ),
    ( "IDEO sp U+3000",   "　",                             True  ),
    ( "ws + ZWSP mix",    " ​\n ",                         True  ),
    # F2: the witnesses the wave-1 verifier proved DELETED the definition against the 23-entry list, kept
    # as named rows so the finding stays readable even though (K) re-derives the whole set — a boundary
    # sweep says the table is intact, these say WHICH bug it was. Written as \uXXXX escapes, never as
    # literal bytes: putting a raw C1 control into a text file is F3, one finding over.
    ( "F2 U+200E LRM (bidi)",                  "\u200e",                     True  ),
    ( "F2 U+200F RLM (bidi)",                  "\u200f",                     True  ),
    ( "F2 U+0085 NEL (C1 line sep)",           "\u0085",                     True  ),
    ( "F2 U+009F APC (C1 control)",            "\u009f",                     True  ),
    ( "F2 U+00AD SOFT HYPHEN",                 "\u00ad",                     True  ),
    ( "F2 U+180E MONGOLIAN VOWEL SEP",         "\u180e",                     True  ),
    ( "F2 U+2800 BRAILLE PATTERN BLANK",       "\u2800",                     True  ),
    ( "F2 U+3164 HANGUL FILLER",               "\u3164",                     True  ),
    ( "F2 U+115F HANGUL CHOSEONG FILLER",      "\u115f",                     True  ),
    ( "F2 U+FFA0 HALFWIDTH HANGUL FILLER",     "\uffa0",                     True  ),
    ( "F2 U+FE0F VARIATION SELECTOR-16",       "\ufe0f",                     True  ),
    ( "F2 U+202E RLO (Trojan-Source)",         "\u202e",                     True  ),
    ( "F2 U+2066 LRI (bidi isolate)",          "\u2066",                     True  ),
    ( "F2 U+061C ARABIC LETTER MARK",          "\u061c",                     True  ),
    ( "F2 U+17B4 KHMER INHERENT AQ",           "\u17b4",                     True  ),
    ( "F2 U+FFF9 INTERLINEAR ANCHOR",          "\ufff9",                     True  ),
    ( "F2 U+E0020 TAG SPACE (astral)",         "\U000e0020",                 True  ),
    ( "F2 one of every class",                 " \u200e\u0085\u2800\ufe0f\U000e0020\u00a0",  True  ),
    ( "EMPTY (the §H2 case, must not regress)", "",             True  ),
    ( "a real definition","int alpha( int x ) { return 5; }",   False ),
    ( "a comment only",   "// x",                               False ),
    ( "leading ws + def", "  int alpha( int x ) { return 5; }", False ),
    ( "non-ASCII text",   "// コメント",        False ),
    # RULED CONTENT, pinned so they cannot drift into the blank set by accident.
    #   U+0301 — a lone COMBINING ACUTE renders as a visible mark (on a dotted circle in every conforming
    #   renderer), and Mn is tens of thousands of code points of real text. The Mn members that ARE blank
    #   (U+034F, U+17B4-B5, U+180B-180F) are in the table on Default_Ignorable grounds, by property, not by
    #   hand. The wave-1 verifier flagged this one "borderline"; the ruling is CONTENT and this row IS the
    #   ruling — a future round that finds it "still applying" is reading a decision, not a residual.
    #   U+FFFC — OBJECT REPLACEMENT CHARACTER renders a visible placeholder box, not nothing.
    #   the lone 0xC0 — invalid UTF-8 is ruled CONTENT (garbage bytes are a different problem, different fix).
    ( "U+0301 COMBINING ACUTE (ruled CONTENT)",  "\u0301",     False ),
    ( "U+FFFC OBJ REPLACEMENT (ruled CONTENT)",  "\ufffc",     False ),
    ( "lone 0xC0 (invalid UTF-8, ruled CONTENT)","\udcc0",     False ),
    ( "U+0041 'A' (the trivial control)",        "A",           False ),
]

# ONE long-lived server per write verb rather than a fork+exec per payload — the same harness (K1) uses one
# arm below, for the same reason: every case here is an independent tools/call judged on its response and on
# the file it did or did not touch, and nothing asserts startup, restart, staleness-reload or watcher
# behaviour. Each case still gets a FRESH corpus under its own path, so no index, no handle and no refusal
# carries from one case to the next. An absent or unparseable reply degrades to {} — the same value the
# per-process form produced from an empty stdout — so a server that dies still lands on the same FAIL rows.
class Server:
    def __init__( self ):
        self.p = subprocess.Popen( [ BIN, "--mcp" ], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL )
        self.send( { "jsonrpc": "2.0", "id": 1, "method": "initialize" } )
    def send( self, obj ):
        try:
            self.p.stdin.write( json.dumps( obj ).encode() + b"\n" ); self.p.stdin.flush()
            line = self.p.stdout.readline().decode( "utf-8", "replace" ).strip()
            return json.loads( line ) if line else {}
        except Exception:
            return {}
    def close( self ):
        try:    self.p.stdin.close(); self.p.wait( 15 )
        except Exception: self.p.kill()

def sha256( path ):                                    # in-process; a shasum(1) fork per probe was pure cost
    with open( path, "rb" ) as fh: return hashlib.sha256( fh.read() ).hexdigest()

def attempt( srv, verb, field, payload ):
    d = tempfile.mkdtemp()
    open( os.path.join( d, "a.h" ), "w" ).write( SRC )
    target = os.path.join( d, "a.h" )
    before = sha256( target )
    r = srv.send( { "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                    "params": { "name": verb,
                                "arguments": { "path": d, "symbol": "alpha", "file": "a.h", field: payload } } } )
    after = sha256( target )
    body = open( target ).read()
    shutil.rmtree( d )
    return ( "error" in r, r.get( "error", {} ).get( "message", "" ), before == after, "int alpha( int x )" in body )

fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

for verb, field in ( ( "replace_symbol_body", "new_body" ),
                     ( "insert_before_symbol", "text" ),
                     ( "insert_after_symbol", "text" ) ):
    srv = Server()
    for label, payload, mustRefuse in CASES:
        refused, msg, sameSha, defIntact = attempt( srv, verb, field, payload )
        if mustRefuse:
            check( refused, "(J) %-20s %-42s → REFUSED" % ( verb, label ) )
            check( sameSha and defIntact,
                   "(J) %-20s %-42s → file sha256 UNCHANGED, definition still on disk" % ( verb, label ) )
            if refused:
                check( "missing required field" in msg and field in msg,
                       "(J) %-20s %-42s → the SAME missing-field sentence, naming %s" % ( verb, label, field ) )
        else:
            check( not refused, "(J) %-20s %-42s → still APPLIES (the rule does not over-reach)" % ( verb, label ) )
    srv.close()

print( "  INFO  (J) %d payload classes x 3 write verbs" % len( CASES ) )
sys.exit( 1 if fails else 0 )
PY
[ $? -eq 0 ] || fail=1

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (K) F2 — the DERIVED blank-code-point table, probed at every range BOUNDARY, both transports ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# WHY THIS ARM EXISTS. (J) above is a list a human wrote, and F2 is the finding that a human-written list of
# this set is wrong by construction: the shipped 23-entry table carried U+200B/200C/200D and U+2060 and missed
# their block siblings U+200E/200F, and stopped at 0x7F so every C1 control counted as a definition. So the
# implementation is now a DERIVED range table (src/infra/blanktext.h kBlankRanges, Unicode 16.0.0, re-derivable with
# test/derive_blankcodepoints.py) and this arm probes THAT TABLE rather than restating it:
#
#   the rows are PARSED OUT OF src/infra/blanktext.h, and for every range { lo, hi } the four bytes that matter are
#   exercised — lo, hi (must REFUSE) and lo-1, hi+1 (must APPLY). A range table breaks at its edges: an
#   off-by-one in a `lo` silently un-refuses one code point, and no class-based arm would ever notice.
#
# ASSERTED PER REFUSAL PROBE, because these verbs delete code when they are wrong:
#   • JSON-RPC error -32602 whose message names the field AND spells the offending code point `U+XXXX`
#     (F2's echo half: the refusal must show WHICH invisible thing was sent, and must never echo the raw
#     byte into a client-facing message — that is §B4's defect and F3's cousin);
#   • the target file's identity quadruple — sha256 + size + mtime_ns + inode — is byte-for-byte unchanged;
#   • the corpus directory gained no stray file (no .tmp, no .orig, no lockfile left behind).
# Every probe gets a FRESH corpus so one miss cannot cascade into "symbol not found" for the rest of the
# sweep — a red-first run has to produce a countable number, not an avalanche.
#
# ASSERTED PER APPLY PROBE: the rule does not OVER-reach. lo-1 / hi+1 are content by construction (the table
# is canonically merged, so a neighbour of a range is never in the set), plus a MIX arm — an in-set code point
# next to an out-of-set one is CONTENT, which is the shape the 23-entry table also got wrong.
#
# BOTH TRANSPORTS: wave 1 established that the HTTP arm inherits the shared dispatchMcpLine, so this asserts
# that inheritance instead of assuming it — the same request body over stdio and over
# `--listen --allow-remote-edits --mcp-token` must come back BYTE-IDENTICAL, and the remote sweep must leave
# the workspace file untouched. Both servers are pinned to the same workspace and `path` is OMITTED, because
# the remote transport refuses an off-workspace path (a subdir of the workspace is off-workspace too) — that
# refusal is correct and would mask this one.
# (K0) FIRST: is the table in the source still the DERIVATION's output? The whole finding is that a
# hand-maintained set of this shape drifts, so the derivation is a gate, not a document. Exit 1 = same Unicode
# version, different table (somebody hand-edited a row); exit 2 = this python's UCD is not the version the
# header cites, which is an environment fact and is reported, not failed.
python3 "$ROOT/test/derive_blankcodepoints.py" --check >"$TMP/derive.log" 2>&1
case $? in
    0) ok "(K0) $( tail -1 "$TMP/derive.log" )";;
    2) printf '  INFO  (K0) %s\n' "$( tail -2 "$TMP/derive.log" | tr '\n' ' ' )";;
    *) no "(K0) src/infra/blanktext.h kBlankRanges no longer matches test/derive_blankcodepoints.py: $( tail -4 "$TMP/derive.log" | tr '\n' ' ' )";;
esac

python3 - "$BIN" "$ROOT" <<'PY'
import hashlib, json, os, re, shutil, socket, subprocess, sys, tempfile, time

BIN, ROOT = sys.argv[1], sys.argv[2]
SRC = ( "// alpha adds one.\nint alpha( int x ) { return x + 1; }\n\n"
        "// beta doubles.\nint beta( int x ) { return x * 2; }\n" )
SURROGATES  = range( 0xD800, 0xE000 )
WRITE_VERBS = ( ( "replace_symbol_body", "new_body" ),
                ( "insert_before_symbol", "text" ),
                ( "insert_after_symbol",  "text" ) )

fails = 0
def check( cond, msg ):
    global fails
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: fails += 1

# ─── the table, parsed out of the source (never restated here — the §B6 M14 lesson) ──────────────────────
def parseBlankRanges( headerPath ):
    src   = open( headerPath, "rb" ).read().decode( "utf-8", "replace" )
    start = src.find( "kBlankRanges[]" )
    if start < 0: return []
    body = src[ start : src.find( "};", start ) ]
    return [ ( int( lo, 16 ), int( hi, 16 ) )
             for lo, hi in re.findall( r"\{\s*0x([0-9A-Fa-f]+)\s*,\s*0x([0-9A-Fa-f]+)\s*\}", body ) ]

ranges = parseBlankRanges( os.path.join( ROOT, "src", "infra", "blanktext.h" ) )
check( len( ranges ) > 0, "(K) kBlankRanges parsed out of src/infra/blanktext.h (%d ranges)" % len( ranges ) )
if not ranges:
    print( "  FAIL  (K) cannot probe a table this gate cannot find — is hasVisibleContent still table-driven?" )
    sys.exit( 1 )

# canonical form is a compile-time static_assert in the header; re-checked here so a gate run on a tree whose
# assert was weakened still reports it (a tripwire that only fires at compile time is invisible to a suite).
canonical = all( lo <= hi for lo, hi in ranges ) and \
            all( ranges[ i ][ 0 ] > ranges[ i - 1 ][ 1 ] + 1 for i in range( 1, len( ranges ) ) )
check( canonical, "(K) the parsed table is sorted, non-overlapping and MERGED" )

inSet, outSet = set(), set()
for lo, hi in ranges:
    inSet.update( ( lo, hi ) )
    if lo > 0: outSet.add( lo - 1 )
    outSet.add( hi + 1 )
outSet -= inSet
encodable = lambda cp: cp not in SURROGATES and cp <= 0x10FFFF
inSet  = sorted( cp for cp in inSet  if encodable( cp ) )
outSet = sorted( cp for cp in outSet if encodable( cp ) )

# ─── (G5) the NOUN the blank-payload clause calls each field by, parsed out of the source table ───────────
# Verifier G5: both insert verbs said "and no definition" about a field kMcpRequiredFields contracts as "the
# text to insert" — the clause hardcoded one noun for three verbs. The noun now comes from
# mcprefusal.h's kMcpPayloadNouns, and this gate reads THAT TABLE rather than restating the strings, for the
# same reason (K) parses kBlankRanges: a gate that restates the fix cannot notice the fix being un-done.
def parsePayloadNouns( headerPath ):
    src   = open( headerPath, "rb" ).read().decode( "utf-8", "replace" )
    start = src.find( "kMcpPayloadNouns[]" )
    if start < 0: return {}
    body = src[ start : src.find( "};", start ) ]
    return dict( re.findall( r'\{\s*"([A-Za-z_]+)"\s*,\s*"([^"]+)"\s*\}', body ) )

PAYLOAD_NOUNS = parsePayloadNouns( os.path.join( ROOT, "src", "mcprefusal.h" ) )
check( sorted( PAYLOAD_NOUNS ) == [ "new_body", "text" ],
       "(G5) kMcpPayloadNouns parsed out of src/mcprefusal.h: %s" % ( PAYLOAD_NOUNS or "<none>" ) )
# The defect in one line: the two fields must not share a noun, or the clause is hardcoded again.
check( len( set( PAYLOAD_NOUNS.values() ) ) == len( PAYLOAD_NOUNS ),
       "(G5) each payload field has its OWN noun (the defect was one noun for all three verbs)" )
print( "  INFO  (K) %d range lo/hi bytes must REFUSE, %d neighbour bytes must APPLY, x %d write verbs"
       % ( len( inSet ), len( outSet ), len( WRITE_VERBS ) ) )

# ─── the harness: a long-lived stdio server, one request at a time so the file can be stat'ed between them ──
class StdioServer:
    def __init__( self, root=None ):
        argv = [ BIN ] + ( [ root ] if root else [] ) + [ "--mcp" ]
        self.p = subprocess.Popen( argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL )
        self.send( { "jsonrpc": "2.0", "id": 1, "method": "initialize" } )
    def sendRaw( self, line ):
        self.p.stdin.write( line.encode() + b"\n" ); self.p.stdin.flush()
        return self.p.stdout.readline().decode( "utf-8", "replace" ).strip()
    def send( self, obj ):
        return json.loads( self.sendRaw( json.dumps( obj ) ) )
    def close( self ):
        try:
            self.p.stdin.close(); self.p.wait( 15 )
        except Exception:
            self.p.kill()

def identity( path ):
    st = os.stat( path )
    with open( path, "rb" ) as fh: sha = hashlib.sha256( fh.read() ).hexdigest()   # in-process; a shasum(1)
    return ( st.st_size, st.st_mtime_ns, st.st_ino, sha )                         # fork ran twice per probe

def freshCorpus():
    d = tempfile.mkdtemp()
    open( os.path.join( d, "a.h" ), "w" ).write( SRC )
    return d

def editFrame( verb, field, payload, corpus, requestId=2 ):
    return { "jsonrpc": "2.0", "id": requestId, "method": "tools/call",
             "params": { "name": verb,
                         "arguments": { "path": corpus, "symbol": "alpha", "file": "a.h", field: payload } } }

# ═══ (K1) stdio: every range boundary, every write verb ════════════════════════════════════════════════════
for verb, field in WRITE_VERBS:
    srv = StdioServer()
    missedRefusal, wrote, noSpelling, strayFile, badCode, wrongNoun = [], [], [], [], [], []
    # (G5) the noun THIS field's clause must use, and the nouns belonging to the OTHER fields, which it must
    # not borrow — that borrowing is precisely the defect (`text` refused with `new_body`'s noun).
    myNoun     = PAYLOAD_NOUNS.get( field, "" )
    otherNouns = [ n for f, n in PAYLOAD_NOUNS.items() if f != field ]
    for cp in inSet:
        corpus = freshCorpus()
        target = os.path.join( corpus, "a.h" )
        before, beforeList = identity( target ), sorted( os.listdir( corpus ) )
        r = srv.send( editFrame( verb, field, chr( cp ), corpus ) )
        if "error" not in r:                                          missedRefusal.append( cp )
        else:
            if r[ "error" ].get( "code" ) != -32602:                   badCode.append( cp )
            msg = r[ "error" ].get( "message", "" )
            if ( "U+%04X" % cp ) not in msg or field not in msg:       noSpelling.append( ( cp, msg ) )
            clause = " and no " + myNoun + ":"
            if clause not in msg or any( ( " and no " + n + ":" ) in msg for n in otherNouns ):
                                                                       wrongNoun.append( ( cp, msg ) )
        if identity( target ) != before:                              wrote.append( cp )
        if sorted( os.listdir( corpus ) ) != beforeList:               strayFile.append( cp )
        shutil.rmtree( corpus )

    overReached = []
    for cp in outSet:
        corpus = freshCorpus()
        r = srv.send( editFrame( verb, field, chr( cp ), corpus, 3 ) )
        if "error" in r: overReached.append( ( cp, r[ "error" ].get( "message", "" ) ) )
        shutil.rmtree( corpus )

    # MIX: an in-set code point next to an out-of-set one is CONTENT. Sampled across the table rather than
    # exhaustive — the pairing is what is under test, and one sample per decade of the table proves it.
    #
    # U+0000 IS EXCLUDED FROM THIS ARM, deliberately, and the original rule above still stands for every
    # other code point in the table. The blank-payload contract asks "is this payload only whitespace, or
    # does it carry content?" — and by that question alone a NUL beside a real definition IS content, which
    # is why this arm was written to expect it to APPLY. The full-audit round of 2026-08-28 established a
    # SECOND, independent reason to refuse that is not about blankness at all: a payload containing a NUL
    # byte, however much real code sits beside it, makes the target file binary-sniffed on the next crawl,
    # so its entire symbol table silently vanishes from the index and every later edit to ANY symbol in
    # that file fails with a false `symbol not found`. That was reproduced end to end before it was fixed
    # (mcpedit.h's payload guard, shared by all three write verbs and by --edit-plan). Refusing it is the
    # stronger contract and it wins here; the blankness rule is not weakened, it is simply not the only
    # rule a payload must satisfy. The `looksBinary` predicate is the authority, so this exclusion is
    # exactly one code point wide — every other in-set point still has to APPLY beside real content.
    mixMissed = []
    for cp in [ c for c in inSet[ ::6 ] if c != 0 ]:
        corpus = freshCorpus()
        r = srv.send( editFrame( verb, field, chr( cp ) + "int alpha( int x ) { return 5; }" + chr( cp ), corpus, 4 ) )
        if "error" in r: mixMissed.append( ( cp, r[ "error" ].get( "message", "" ) ) )
        shutil.rmtree( corpus )

    # The other half of that exclusion: U+0000 beside real content must be REFUSED, and the refusal must
    # say why. Dropping the case from the loop above without asserting the replacement rule here would
    # leave a hole exactly where the round found a real defect, so the code point stays covered — the
    # expectation is inverted, not removed.
    corpus = freshCorpus()
    nulMix = srv.send( editFrame( verb, field, "\x00int alpha( int x ) { return 5; }\x00", corpus, 5 ) )
    nulRefused = "error" in nulMix
    nulNamesReason = nulRefused and "NUL" in nulMix[ "error" ].get( "message", "" )
    shutil.rmtree( corpus )
    srv.close()

    for cp in missedRefusal[ :6 ]:
        print( "  FAIL  (K1) %-20s U+%04X APPLIED — a blank payload reached the file" % ( verb, cp ) )
    for cp in wrote[ :6 ]:
        print( "  FAIL  (K1) %-20s U+%04X the file's identity quadruple CHANGED behind a refusal" % ( verb, cp ) )
    for cp, msg in noSpelling[ :6 ]:
        print( "  FAIL  (K1) %-20s U+%04X refusal does not name the field and spell the code point: %s"
               % ( verb, cp, msg[ -110: ] ) )
    for cp, msg in overReached[ :6 ]:
        print( "  FAIL  (K1) %-20s U+%04X (a NEIGHBOUR of a range) was refused — the rule over-reaches: %s"
               % ( verb, cp, msg[ :110 ] ) )
    for cp, msg in mixMissed[ :6 ]:
        print( "  FAIL  (K1) %-20s U+%04X + a real definition was refused — a MIX must be content: %s"
               % ( verb, cp, msg[ :110 ] ) )

    check( not missedRefusal, "(K1) %-20s all %d range lo/hi code points REFUSED (%d applied)"
                              % ( verb, len( inSet ), len( missedRefusal ) ) )
    check( not badCode,       "(K1) %-20s every refusal is -32602 (%d were not)" % ( verb, len( badCode ) ) )
    check( not noSpelling,    "(K1) %-20s every refusal names %s and SPELLS the code point (%d did not)"
                              % ( verb, field, len( noSpelling ) ) )
    for cp, msg in wrongNoun[ :3 ]:
        print( "  FAIL  (G5) %-20s U+%04X clause calls `%s` by the wrong noun: %s"
               % ( verb, cp, field, msg[ -110: ] ) )
    check( not wrongNoun,     "(G5) %-20s all %d refusals say 'and no %s' — %s's own noun, never another field's (%d wrong)"
                              % ( verb, len( inSet ), myNoun, field, len( wrongNoun ) ) )
    check( not wrote,         "(K1) %-20s sha256+size+mtime_ns+inode unchanged behind all %d refusals (%d wrote)"
                              % ( verb, len( inSet ), len( wrote ) ) )
    check( not strayFile,     "(K1) %-20s no stray temp file in the corpus dir (%d left one)"
                              % ( verb, len( strayFile ) ) )
    check( not overReached,   "(K1) %-20s all %d range NEIGHBOURS still APPLY (%d over-reached)"
                              % ( verb, len( outSet ), len( overReached ) ) )
    check( not mixMissed,     "(K1) %-20s all %d MIX payloads (blank + real definition) APPLY (%d refused)"
                              % ( verb, len( [ c for c in inSet[ ::6 ] if c != 0 ] ), len( mixMissed ) ) )
    check( nulRefused,        "(K1) %-20s U+0000 beside a real definition is REFUSED — a NUL would un-index the file"
                              % verb )
    check( nulNamesReason,    "(K1) %-20s the U+0000 refusal names the NUL byte as the reason" % verb )

# ═══ (K2) stdio ≡ HTTP with --allow-remote-edits, byte-for-byte ════════════════════════════════════════════
# One workspace, two servers, `path` OMITTED so both resolve their pinned root: identical request bytes must
# yield identical response bytes, and the remote sweep must not touch the file.
port  = 22000 + ( os.getpid() % 8000 )
token = "k2-%d" % os.getpid()
ws    = freshCorpus()
target = os.path.join( ws, "a.h" )
http  = subprocess.Popen( [ BIN, ws, "--listen=127.0.0.1:%d" % port, "--allow-remote-edits",
                            "--mcp-token=" + token ], stdout=subprocess.PIPE, stderr=subprocess.STDOUT )

# WAIT ON THE CONDITION: poll until the listener ACCEPTS on `port` (20 ms interval, 30 s ceiling), returning
# early if the child dies. A timeout FAILS the arm here rather than letting a 96-probe sweep fall through
# against a socket nobody is listening on. `http.stdout` is only read once the child has EXITED — reading a
# live child's pipe would block forever, which is the one thing a timeout path must not do.
def waitListening( port, proc, timeoutSec = 30.0 ):
    deadline = time.time() + timeoutSec
    while time.time() < deadline:
        if proc.poll() is not None: return False
        try:
            socket.create_connection( ( "127.0.0.1", port ), 0.25 ).close()
            return True
        except OSError:
            time.sleep( 0.02 )
    return False

listening = waitListening( port, http )
if http.poll() is not None:
    check( False, "(K2) the --allow-remote-edits listener did not start: %s"
                  % http.stdout.read()[ :180 ].decode( "utf-8", "replace" ) )
elif not listening:
    check( False, "(K2) the --allow-remote-edits listener never ACCEPTED on 127.0.0.1:%d within 30 s" % port )
    http.terminate(); http.wait( 15 )
else:
    def post( line ):
        body = line.encode()
        req  = ( b"POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n"
                 b"Authorization: Bearer " + token.encode() + b"\r\n"
                 b"Accept: application/json, text/event-stream\r\nContent-Length: "
                 + str( len( body ) ).encode() + b"\r\n\r\n" + body )
        s = socket.create_connection( ( "127.0.0.1", port ), 5 ); s.sendall( req )
        chunks = b""
        while True:
            c = s.recv( 65536 )
            if not c: break
            chunks += c
            head, sep, tail = chunks.partition( b"\r\n\r\n" )
            if sep and tail.strip().endswith( b"}" ): break
        s.close()
        return chunks.partition( b"\r\n\r\n" )[ 2 ].decode( "utf-8", "replace" ).strip()

    stdio  = StdioServer( ws )
    before = identity( target )
    differ, remoteApplied = [], []
    for verb, field in WRITE_VERBS:
        for cp in inSet[ ::3 ]:
            line = json.dumps( { "jsonrpc": "2.0", "id": 7, "method": "tools/call",
                                 "params": { "name": verb,
                                             "arguments": { "symbol": "alpha", "file": "a.h", field: chr( cp ) } } } )
            s, h = stdio.sendRaw( line ), post( line )
            if s != h:                          differ.append( ( verb, cp, s[ :90 ], h[ :90 ] ) )
            if '"error"' not in h:              remoteApplied.append( ( verb, cp ) )
    stdio.close()
    for verb, cp, s, h in differ[ :5 ]:
        print( "  FAIL  (K2) %-20s U+%04X transports DIFFER  stdio=%s  http=%s" % ( verb, cp, s, h ) )
    for verb, cp in remoteApplied[ :5 ]:
        print( "  FAIL  (K2) %-20s U+%04X APPLIED over the remote transport" % ( verb, cp ) )
    probes = len( inSet[ ::3 ] ) * len( WRITE_VERBS )
    check( not differ,        "(K2) %d probes byte-identical stdio vs HTTP (%d differed)" % ( probes, len( differ ) ) )
    check( not remoteApplied, "(K2) every remote probe REFUSED (%d applied)" % len( remoteApplied ) )
    check( identity( target ) == before,
           "(K2) the workspace file is byte-identical after %d remote blank-payload writes" % probes )
    http.terminate(); http.wait( 15 )
shutil.rmtree( ws, ignore_errors=True )

print( "  INFO  (K) %d ranges x 4 boundaries, 3 write verbs, 2 transports" % len( ranges ) )
sys.exit( 1 if fails else 0 )
PY
[ $? -eq 0 ] || fail=1

echo
[ "$fail" = 0 ] && { echo "mcpframehonestycheck: ALL PASS"; exit 0; }
echo "mcpframehonestycheck: FAILURES above"; exit 1
