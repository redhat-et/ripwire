#!/usr/bin/env bash
# mcprobustcheck.sh — MCP protocol robustness gate + the 6 verbs mcpverbscheck.sh doesn't cover.
#
# Drives the MCP server via newline-delimited JSON-RPC over stdin, same technique as
# mcpverbscheck.sh / situdiffcheck.sh (printf JSON lines | "$BIN" --mcp).
#
# Part A — protocol robustness. One line each of:
#   (a) plain garbage `not-json`
#   (b) `{"jsonrpc":"2.0"}` — valid JSON, but no method and no id
#   (c) a valid initialize with id 7 — response must echo id 7
#   (d) `notifications/initialized` — no id — must produce NO response line (it's a notification)
#   (e) tools/call with no `arguments` object at all
#   (f) tools/call find_symbol with no `symbol` argument
#   (g) tools/call with an unknown tool name
# Assertions: every response line is valid JSON; every error response carries an
# `error.code`; the process never crashes (exit 0 at EOF); the count of response lines
# equals the count of requests that are NOT bare notifications (a,b,c,e,f,g = 6 lines; d
# produces none).
#
# Part B — the 6 verbs mcpverbscheck.sh leaves untested: find_symbol, find_referencing_symbols,
# grep, cochange, memory_recall, mentions. Run against test/fixture (the stable polyglot
# regression corpus: geometry.cpp defines distance()/perimeter() with perimeter -> distance;
# notes.md mentions `perimeter` in a backtick). Each verb is also called TWICE to assert
# byte-identical determinism.
#
# Part C — A3-F6: tools/call argument scoping (params.arguments only, envelope keys can't shadow).
#
# Part D — D3/D4 (plan X7): `ripwire <root> --mcp`'s startup root as the stdio default:
#   (D-1) an omitted `path` on a READ verb resolves against the startup root.
#   (D-2) an EDIT verb given a `path` OUTSIDE the startup root refuses with the named workspace-pin
#         error, and the startup-root workspace is left byte-identical.
#   (D-3) an EDIT verb with an OMITTED `path` targets (and actually mutates) the startup root.
#   (D-4) a missing required arg on a KNOWN verb names the missing field(s), not the old generic
#         "unknown tool or missing args" — which a genuinely unknown tool name still gets.
#   (D-5) the pre-X7 behavior is unchanged: a bare `--mcp` with NO startup root still requires an
#         explicit `path` on every verb.
#
# Usage:
#   test/mcprobustcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/mcprobustcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh or mcpverbscheck.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcprobustcheck: BIN=$BIN  FIX=$FIX"

# ─── helpers ─────────────────────────────────────────────────────────────────

mcp_call() {
    printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== Part A: MCP protocol robustness ==="
# ═══════════════════════════════════════════════════════════════════════════

MSG_A='not-json'
MSG_B='{"jsonrpc":"2.0"}'
MSG_C='{"jsonrpc":"2.0","id":7,"method":"initialize"}'
MSG_D='{"jsonrpc":"2.0","method":"notifications/initialized"}'
MSG_E='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol"}}'
MSG_F="{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$FIX\"}}}"
MSG_G="{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"bogus_tool_name\",\"arguments\":{\"path\":\"$FIX\"}}}"

# run the whole battery in one stream (also proves the server survives a mixed batch,
# not just isolated single-line calls).
mcp_call "$MSG_A" "$MSG_B" "$MSG_C" "$MSG_D" "$MSG_E" "$MSG_F" "$MSG_G" >"$TMP/battery_out" 2>"$TMP/battery_err"
BATTERY_EXIT=$?

[ "$BATTERY_EXIT" -eq 0 ] \
    && ok "process never crashes — exit 0 at EOF after garbage/malformed/unknown input" \
    || no "process exited non-zero ($BATTERY_EXIT) on the robustness battery"

# every non-empty output line must parse as JSON.
python3 - "$TMP/battery_out" <<'PYEOF' >"$TMP/battery_parse"
import sys, json
path = sys.argv[1]
bad = []
n = 0
with open(path) as f:
    for i, line in enumerate(f, 1):
        line = line.rstrip("\n")
        if not line:
            continue
        n += 1
        try:
            json.loads(line)
        except Exception as e:
            bad.append((i, str(e)))
print("LINES:%d" % n)
if bad:
    print("BAD:" + ";".join("%d:%s" % (i, e) for i, e in bad))
else:
    print("ALL_JSON_OK")
PYEOF

grep -q "ALL_JSON_OK" "$TMP/battery_parse" \
    && ok "every response line parses as valid JSON" \
    || no "some response line(s) are not valid JSON: $( grep BAD: "$TMP/battery_parse" )"

# response-line count == number of id-bearing / non-notification requests (6: a,b,c,e,f,g).
LINE_COUNT="$( grep '^LINES:' "$TMP/battery_parse" | cut -d: -f2 )"
[ "$LINE_COUNT" = "6" ] \
    && ok "response line count is exactly 6 (garbage+no-method each yield a parse-error line, notification yields none)" \
    || no "expected 6 response lines, got $LINE_COUNT"

# (a) garbage — must come back as a JSON error object with a numeric code.
python3 - "$TMP/battery_out" <<'PYEOF' >"$TMP/check_a"
import sys, json
lines = [l for l in open(sys.argv[1]) if l.strip()]
r = json.loads(lines[0])
code = r.get("error", {}).get("code")
print("OK" if isinstance(code, int) else "BAD:" + json.dumps(r))
PYEOF
[ "$( cat "$TMP/check_a" )" = "OK" ] \
    && ok "(a) garbage 'not-json' -> JSON error object with numeric error.code" \
    || no "(a) garbage: $( cat "$TMP/check_a" )"

# (b) no method/id — still a well-formed JSON error with a code (method-less request is invalid).
python3 - "$TMP/battery_out" <<'PYEOF' >"$TMP/check_b"
import sys, json
lines = [l for l in open(sys.argv[1]) if l.strip()]
r = json.loads(lines[1])
code = r.get("error", {}).get("code")
print("OK" if isinstance(code, int) else "BAD:" + json.dumps(r))
PYEOF
[ "$( cat "$TMP/check_b" )" = "OK" ] \
    && ok "(b) no-method/no-id request -> JSON error object with numeric error.code" \
    || no "(b) no-method: $( cat "$TMP/check_b" )"

# (c) valid initialize id=7 -> response echoes id 7, no error.
python3 - "$TMP/battery_out" <<'PYEOF' >"$TMP/check_c"
import sys, json
lines = [l for l in open(sys.argv[1]) if l.strip()]
r = json.loads(lines[2])
print("OK" if r.get("id") == 7 and "error" not in r else "BAD:" + json.dumps(r))
PYEOF
[ "$( cat "$TMP/check_c" )" = "OK" ] \
    && ok "(c) initialize id=7 -> response echoes id 7, no error" \
    || no "(c) initialize: $( cat "$TMP/check_c" )"

# Current lifecycle negotiation: supported versions are echoed; unsupported/missing versions use the
# latest server version as a compatibility policy. These checks cover stdio independently of HTTP headers.
for version in 2025-11-25 2025-06-18 2025-03-26 2024-11-05; do
    reply="$( mcp_call "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"$version\",\"capabilities\":{},\"clientInfo\":{\"name\":\"ripwire-test\",\"version\":\"1.0\"}}}" )"
    got="$( printf '%s' "$reply" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("result",{}).get("protocolVersion",""))' 2>/dev/null )"
    [ "$got" = "$version" ] && ok "initialize negotiates supported $version" || no "initialize requested $version but returned '$got'"
done

reply="$( mcp_call '{"jsonrpc":"2.0","id":9,"method":"initialize","params":{"protocolVersion":"2099-01-01","capabilities":{},"clientInfo":{"name":"ripwire-test","version":"1.0"}}}' )"
got="$( printf '%s' "$reply" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("result",{}).get("protocolVersion",""))' 2>/dev/null )"
[ "$got" = "2025-11-25" ] && ok "unsupported initialize version negotiates latest" || no "unsupported initialize version returned '$got'"

reply="$( mcp_call '{"jsonrpc":"2.0","id":10,"method":"initialize"}' )"
got="$( printf '%s' "$reply" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("result",{}).get("protocolVersion",""))' 2>/dev/null )"
[ "$got" = "2025-11-25" ] && ok "missing initialize version uses the latest compatibility policy" || no "missing initialize version returned '$got'"

# (d) notifications/initialized — a standalone call MUST produce zero output lines.
NOTIF_OUT="$( mcp_call "$MSG_D" )"
[ -z "$NOTIF_OUT" ] \
    && ok "(d) notifications/initialized (no id) produces NO response line" \
    || no "(d) notification unexpectedly produced output: $NOTIF_OUT"

# (e) tools/call with no arguments object at all -> error with code.
python3 - "$TMP/battery_out" <<'PYEOF' >"$TMP/check_e"
import sys, json
lines = [l for l in open(sys.argv[1]) if l.strip()]
r = json.loads(lines[3])
code = r.get("error", {}).get("code")
print("OK" if isinstance(code, int) else "BAD:" + json.dumps(r))
PYEOF
[ "$( cat "$TMP/check_e" )" = "OK" ] \
    && ok "(e) tools/call with missing arguments object -> error with numeric code" \
    || no "(e) missing arguments: $( cat "$TMP/check_e" )"

# (f) find_symbol with no symbol argument -> error with code.
python3 - "$TMP/battery_out" <<'PYEOF' >"$TMP/check_f"
import sys, json
lines = [l for l in open(sys.argv[1]) if l.strip()]
r = json.loads(lines[4])
code = r.get("error", {}).get("code")
print("OK" if isinstance(code, int) else "BAD:" + json.dumps(r))
PYEOF
[ "$( cat "$TMP/check_f" )" = "OK" ] \
    && ok "(f) find_symbol with no symbol argument -> error with numeric code" \
    || no "(f) find_symbol no-symbol: $( cat "$TMP/check_f" )"

# (g) unknown tool name -> error with code.
python3 - "$TMP/battery_out" <<'PYEOF' >"$TMP/check_g"
import sys, json
lines = [l for l in open(sys.argv[1]) if l.strip()]
r = json.loads(lines[5])
code = r.get("error", {}).get("code")
print("OK" if isinstance(code, int) else "BAD:" + json.dumps(r))
PYEOF
[ "$( cat "$TMP/check_g" )" = "OK" ] \
    && ok "(g) unknown tool name -> error with numeric code" \
    || no "(g) unknown tool: $( cat "$TMP/check_g" )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== Part B: the 6 untested verbs, against test/fixture ==="
# ═══════════════════════════════════════════════════════════════════════════
# test/fixture ground truth (confirmed by reading test/fixture/*.cpp / *.md before writing
# these assertions):
#   geometry.cpp: perimeter() (line 11) calls distance() (line 4)          -> perimeter -> distance
#   sub/consumer.cpp: diagonal() also calls distance()                     -> another caller of distance
#   notes.md: "`distance` and `perimeter` live in the C++ files..."        -> mentions `perimeter` in backticks

run_two(){
    # $1 = output-basename, remaining = JSON-RPC lines (after initialize)
    local base="$1"; shift
    mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$@" >"$TMP/${base}_a"
    mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$@" >"$TMP/${base}_b"
}

inner_text(){
    # extract tools/call (id=2) response text, or __ERROR__:<json> on error.
    tail -1 "$TMP/$1" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + json.dumps(r["error"]))
else:
    print(r["result"]["content"][0]["text"])
'
}

# --- find_symbol: perimeter -> mentions its own file (geometry.cpp) --------------------
run_two fs "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$FIX\",\"symbol\":\"perimeter\"}}}"
FS_INNER="$( inner_text fs_a )"
case "$FS_INNER" in
    __ERROR__*) no "find_symbol: returned error: ${FS_INNER#__ERROR__:}";;
    *geometry.cpp*) ok "find_symbol(perimeter): result mentions its defining file geometry.cpp";;
    *) no "find_symbol(perimeter): geometry.cpp not found in result: $( echo "$FS_INNER" | head -c 200 )";;
esac
diff -q "$TMP/fs_a" "$TMP/fs_b" >/dev/null \
    && ok "find_symbol: deterministic (byte-identical across two calls)" \
    || no "find_symbol: non-deterministic response"

# --- find_referencing_symbols: distance -> mentions caller perimeter -------------------
run_two frs "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_referencing_symbols\",\"arguments\":{\"path\":\"$FIX\",\"symbol\":\"distance\"}}}"
FRS_INNER="$( inner_text frs_a )"
case "$FRS_INNER" in
    __ERROR__*) no "find_referencing_symbols: returned error: ${FRS_INNER#__ERROR__:}";;
    *perimeter*) ok "find_referencing_symbols(distance): result mentions the caller perimeter";;
    *) no "find_referencing_symbols(distance): perimeter not found in result: $( echo "$FRS_INNER" | head -c 200 )";;
esac
diff -q "$TMP/frs_a" "$TMP/frs_b" >/dev/null \
    && ok "find_referencing_symbols: deterministic (byte-identical across two calls)" \
    || no "find_referencing_symbols: non-deterministic response"

# --- grep pattern="perimeter" -> hit + enclosing symbol ---------------------------------
run_two gr "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FIX\",\"pattern\":\"perimeter\"}}}"
GR_INNER="$( inner_text gr_a )"
case "$GR_INNER" in
    __ERROR__*) no "grep: returned error: ${GR_INNER#__ERROR__:}";;
    *) : ;;
esac
python3 -c '
import sys, json
d = json.loads(sys.argv[1])
hits = d.get("hits", [])
has_hit = len(hits) > 0
has_enclosing = any(h.get("in") == "perimeter" for h in hits)
print("OK" if (has_hit and has_enclosing) else "BAD:" + json.dumps(d))
' "$GR_INNER" >"$TMP/gr_check" 2>/dev/null || echo "BAD:parse-failed" >"$TMP/gr_check"
[ "$( cat "$TMP/gr_check" )" = "OK" ] \
    && ok "grep(perimeter): hit found with enclosing symbol 'perimeter'" \
    || no "grep(perimeter): $( cat "$TMP/gr_check" )"
diff -q "$TMP/gr_a" "$TMP/gr_b" >/dev/null \
    && ok "grep: deterministic (byte-identical across two calls)" \
    || no "grep: non-deterministic response"

# --- cochange: valid JSON result, may legitimately be empty (fixture has shallow git history) --
run_two cc "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"cochange\",\"arguments\":{\"path\":\"$FIX\",\"file\":\"geometry.cpp\"}}}"
CC_INNER="$( inner_text cc_a )"
case "$CC_INNER" in
    __ERROR__*) no "cochange: returned error: ${CC_INNER#__ERROR__:}";;
    *)
        python3 -c '
import sys, json
json.loads(sys.argv[1])
print("OK")
' "$CC_INNER" >"$TMP/cc_check" 2>/dev/null || echo "BAD:not-json" >"$TMP/cc_check"
        [ "$( cat "$TMP/cc_check" )" = "OK" ] \
            && ok "cochange: JSON-valid result (partners may legitimately be empty)" \
            || no "cochange: result is not valid JSON: $( echo "$CC_INNER" | head -c 200 )"
        ;;
esac
diff -q "$TMP/cc_a" "$TMP/cc_b" >/dev/null \
    && ok "cochange: deterministic (byte-identical across two calls)" \
    || no "cochange: non-deterministic response"

# --- memory_recall: task string -> fixture's markdown content (notes.md exists) --------
run_two mr "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"memory_recall\",\"arguments\":{\"path\":\"$FIX\",\"task\":\"geometry perimeter\"}}}"
MR_INNER="$( inner_text mr_a )"
case "$MR_INNER" in
    __ERROR__*) no "memory_recall: returned error: ${MR_INNER#__ERROR__:}";;
    "") no "memory_recall: inner text is empty";;
    *"Geometry Fixture"*) ok "memory_recall('geometry perimeter'): returns notes.md's markdown content";;
    *) no "memory_recall: did not return fixture markdown content: $( echo "$MR_INNER" | head -c 200 )";;
esac
diff -q "$TMP/mr_a" "$TMP/mr_b" >/dev/null \
    && ok "memory_recall: deterministic (byte-identical across two calls)" \
    || no "memory_recall: non-deterministic response"

# --- mentions: JSON-valid (perimeter is named in notes.md's backticks) -----------------
run_two mn "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"mentions\",\"arguments\":{\"path\":\"$FIX\",\"symbol\":\"perimeter\"}}}"
MN_INNER="$( inner_text mn_a )"
case "$MN_INNER" in
    __ERROR__*) no "mentions: returned error: ${MN_INNER#__ERROR__:}";;
    *)
        python3 -c '
import sys, json
d = json.loads(sys.argv[1])
print("OK" if isinstance(d, dict) else "BAD:not-object")
' "$MN_INNER" >"$TMP/mn_check" 2>/dev/null || echo "BAD:not-json" >"$TMP/mn_check"
        [ "$( cat "$TMP/mn_check" )" = "OK" ] \
            && ok "mentions(perimeter): JSON-valid result" \
            || no "mentions: result is not valid JSON: $( echo "$MN_INNER" | head -c 200 )"
        ;;
esac
diff -q "$TMP/mn_a" "$TMP/mn_b" >/dev/null \
    && ok "mentions: deterministic (byte-identical across two calls)" \
    || no "mentions: non-deterministic response"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== Part C: A3-F6 — argument extraction is scoped to params.arguments ==="
# ═══════════════════════════════════════════════════════════════════════════
# The bug: findString/findInt scanned the WHOLE JSON-RPC line for the first "key", so a string
# request-id (or any string value) equal to an argument key name shadowed the real argument. The
# fix scopes argument keys to the params.arguments object only. Each case drives find_symbol against
# test/fixture; a correct scope resolves path=$FIX and symbol=perimeter → geometry.cpp in the result.

# extract the tools/call inner text, or __ERROR__:<msg>
c_inner_text(){
    tail -1 "$1" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERROR__:" + r["error"].get("message",""))
else: print(r["result"]["content"][0]["text"])
'
}

# (a) a STRING request-id equal to a key name ("path") must not shadow the real path argument.
#     id:"path" lives OUTSIDE arguments — it must be invisible to the arg scanner.
MSG_CA="{\"jsonrpc\":\"2.0\",\"id\":\"path\",\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$FIX\",\"symbol\":\"perimeter\"}}}"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$MSG_CA" | "$BIN" --mcp 2>/dev/null >"$TMP/ca_out"
CA_INNER="$( c_inner_text "$TMP/ca_out" )"
case "$CA_INNER" in
    *geometry.cpp*) ok "(a) string id equal to key name 'path' does NOT shadow the real path argument (resolved to \$FIX)";;
    __ERROR__*)     no "(a) string id 'path' shadowed the real path: ${CA_INNER#__ERROR__:}";;
    *)              no "(a) unexpected result (geometry.cpp missing): $( echo "$CA_INNER" | head -c 160 )";;
esac

# (b) a string ARG value equal to a key name must not shadow the real later key of that name.
#     The DECOY CARRIER moved from find_symbol's `file` to grep's `pattern` (W3FIX M4): an argument the verb's
#     inputSchema does not declare is now refused outright, and find_symbol declares no second string field to
#     park a decoy in — so parking one there tested the M4 refusal instead of the shadow. grep declares BOTH
#     the carrier (`pattern`) and the shadowed key (`limit`), which is the same defect on a verb where the
#     probe is legal — and it is the exact pair the W3FIX H3 finding was reported against.
MSG_CB="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FIX\",\"pattern\":\"limit\",\"limit\":3}}}"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$MSG_CB" | "$BIN" --mcp 2>/dev/null >"$TMP/cb_out"
CB_INNER="$( c_inner_text "$TMP/cb_out" )"
case "$CB_INNER" in
    *'"limit":3'*) ok "(b) an arg value equal to a key name ('limit') does NOT shadow the real later limit key";;
    __ERROR__*) no "(b) decoy arg value shadowed the real limit key: ${CB_INNER#__ERROR__:}";;
    *)          no "(b) unexpected result: $( echo "$CB_INNER" | head -c 160 )";;
esac

# (c) an arguments-object string value containing a `}` (brace-in-string) must not truncate the
#     arguments span early — a later key must still resolve past the embedded brace. Same carrier move as (b).
MSG_CC="{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"pattern\":\"a } brace } inside\",\"path\":\"$FIX\",\"limit\":3}}}"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$MSG_CC" | "$BIN" --mcp 2>/dev/null >"$TMP/cc2_out"
CC2_INNER="$( c_inner_text "$TMP/cc2_out" )"
case "$CC2_INNER" in
    *'"limit":3'*) ok "(c) a brace '}' inside an arguments-object string value does not truncate the arg span (later keys still resolve)";;
    __ERROR__*)     no "(c) brace-in-string truncated the arguments span: ${CC2_INNER#__ERROR__:}";;
    *)              no "(c) unexpected result: $( echo "$CC2_INNER" | head -c 160 )";;
esac

# (d) a string id equal to a NUMERIC-key name ('start_line') lives outside arguments and must be
#     invisible to the numeric-arg scanner (findInt) too — path/symbol still resolve normally.
MSG_CD="{\"jsonrpc\":\"2.0\",\"id\":\"start_line\",\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$FIX\",\"symbol\":\"perimeter\"}}}"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$MSG_CD" | "$BIN" --mcp 2>/dev/null >"$TMP/cd_out"
CD_INNER="$( c_inner_text "$TMP/cd_out" )"
case "$CD_INNER" in
    *geometry.cpp*) ok "(d) an id equal to a numeric-key name ('start_line') is outside arguments and ignored by the arg scanner";;
    *)              no "(d) unexpected result: $( echo "$CD_INNER" | head -c 160 )";;
esac

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== Part D: X7 (D3/D4) — stdio startup-root default + edit-verb workspace pin ==="
# ═══════════════════════════════════════════════════════════════════════════
# `ripwire <root> --mcp` (a startup root on the command line) now behaves like the remote HTTP
# transport's own pinned-workspace default, but SOFTER: an omitted `path` defaults to that root for
# EVERY verb (read and edit alike); only the 3 EDIT verbs are refused when an EXPLICIT `path` resolves
# OUTSIDE it (read verbs stay unrestricted — a multi-root user reading a sibling checkout is a feature,
# per the decided policy). A bare `ripwire --mcp` (no root, exercised everywhere else in this file via
# mcp_call()) is untouched: no default exists, so every verb still requires its own `path` (D-5).
# NEVER edits test/fixture itself: every mutation happens on a scratch COPY under a fresh mktemp root.

mcp_call_root(){   # $1 = startup root dir; remaining = JSON-RPC lines
    local root="$1"; shift
    printf '%s\n' "$@" | "$BIN" "$root" --mcp 2>/dev/null
}

# --- (D-1) omitted path on a READ verb resolves to the startup root ----------------------------
D1_WS="$( mktemp -d "$TMP/d1ws.XXXXXX" )"; cp -R "$FIX/"* "$D1_WS/"
D1_MSG='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"symbol":"perimeter"}}}'
mcp_call_root "$D1_WS" '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$D1_MSG" >"$TMP/d1_out"
D1_INNER="$( c_inner_text "$TMP/d1_out" )"
case "$D1_INNER" in
    *geometry.cpp*) ok "(D-1) find_symbol with an OMITTED path resolves against the startup root";;
    __ERROR__*)     no "(D-1) omitted-path read verb errored instead of defaulting to the startup root: ${D1_INNER#__ERROR__:}";;
    *)              no "(D-1) unexpected result: $( echo "$D1_INNER" | head -c 200 )";;
esac

# --- (D-2) an EDIT verb given a path OUTSIDE the startup root refuses with the named error -------
D2_WS="$( mktemp -d "$TMP/d2ws.XXXXXX" )"; cp -R "$FIX/"* "$D2_WS/"
D2_OTHER="$( mktemp -d "$TMP/d2other.XXXXXX" )"                                      # a real dir, never a subdir of D2_WS
D2_SNAPSHOT="$( mktemp -d "$TMP/d2snap.XXXXXX" )"; cp -R "$D2_WS/"* "$D2_SNAPSHOT/"  # pristine copy for the byte-identical check
D2_MSG="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"insert_before_symbol\",\"arguments\":{\"path\":\"$D2_OTHER\",\"symbol\":\"perimeter\",\"file\":\"geometry.cpp\",\"text\":\"// x7-outside\\n\"}}}"
mcp_call_root "$D2_WS" '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$D2_MSG" >"$TMP/d2_out"
D2_INNER="$( c_inner_text "$TMP/d2_out" )"
[ "$D2_INNER" = "__ERROR__:path outside workspace; start the server on that root or pass an absolute in-root path" ] \
    && ok "(D-2) edit verb with an outside-root path refuses with the named workspace-pin error" \
    || no "(D-2) unexpected: $D2_INNER"
diff -rq "$D2_SNAPSHOT" "$D2_WS" >/dev/null \
    && ok "(D-2) the refused edit left the startup-root workspace byte-identical" \
    || no "(D-2) the startup-root workspace changed despite the refusal"

# --- (D-3) an EDIT verb with an OMITTED path targets (and actually mutates) the startup root -----
D3_WS="$( mktemp -d "$TMP/d3ws.XXXXXX" )"; cp -R "$FIX/"* "$D3_WS/"
D3_MSG='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"insert_before_symbol","arguments":{"symbol":"perimeter","file":"geometry.cpp","text":"// x7-marker\n"}}}'
mcp_call_root "$D3_WS" '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$D3_MSG" >"$TMP/d3_out"
D3_INNER="$( c_inner_text "$TMP/d3_out" )"
case "$D3_INNER" in
    *applied*insert_before_symbol*) ok "(D-3) edit verb with an OMITTED path applies against the startup root";;
    __ERROR__*) no "(D-3) omitted-path edit verb errored instead of defaulting to the startup root: ${D3_INNER#__ERROR__:}";;
    *)          no "(D-3) unexpected result: $( echo "$D3_INNER" | head -c 200 )";;
esac
grep -q "// x7-marker" "$D3_WS/geometry.cpp" \
    && ok "(D-3) the edit actually landed in the startup root's geometry.cpp" \
    || no "(D-3) marker text not found in the startup root's geometry.cpp after the edit"

# --- (D-4) a missing required arg names the field(s); an unknown tool keeps the generic wording --
D4_WS="$( mktemp -d "$TMP/d4ws.XXXXXX" )"; cp -R "$FIX/"* "$D4_WS/"

mcp_call_root "$D4_WS" '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{}}}' >"$TMP/d4a_out"
# §B6 M7: the assertion moved from whole-message EQUALITY to the two MEANING HALVES, because the shared
# refusal table (src/mcprefusal.h) now appends the CLI's other two clauses — what the field is and an
# EXAMPLE to type — to the same "missing required field: X" prefix. Pinning the whole sentence would pin the
# absence of the help text this round exists to add; pinning the prefix AND the example pins what matters.
case "$( c_inner_text "$TMP/d4a_out" )" in
    "__ERROR__:missing required field: pattern"*'e.g. pattern='*) d4a=ok;; *) d4a=no;; esac
[ "$d4a" = ok ] \
    && ok "(D-4a) grep with no 'pattern' names the missing field AND an example to type" \
    || no "(D-4a) unexpected: $( c_inner_text "$TMP/d4a_out" )"

mcp_call_root "$D4_WS" '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"exemplar","arguments":{}}}' >"$TMP/d4b_out"
case "$( c_inner_text "$TMP/d4b_out" )" in
    "__ERROR__:missing required field: kind or task"*'e.g. kind='*) d4b=ok;; *) d4b=no;; esac
[ "$d4b" = ok ] \
    && ok "(D-4b) exemplar with neither 'kind' nor 'task' names both alternatives AND an example" \
    || no "(D-4b) unexpected: $( c_inner_text "$TMP/d4b_out" )"

mcp_call_root "$D4_WS" '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"path_between","arguments":{}}}' >"$TMP/d4c_out"
case "$( c_inner_text "$TMP/d4c_out" )" in
    "__ERROR__:missing required fields: from, to"*'e.g. from='*'to='*) d4c=ok;; *) d4c=no;; esac
[ "$d4c" = ok ] \
    && ok "(D-4c) path_between with neither 'from' nor 'to' names both missing fields AND both examples" \
    || no "(D-4c) unexpected: $( c_inner_text "$TMP/d4c_out" )"

mcp_call_root "$D4_WS" '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"bogus_tool_name","arguments":{}}}' >"$TMP/d4d_out"
# §B6 M9: the old message ran TWO failures together ("unknown tool or missing args") and named neither the
# verb nor a near-miss. The split is the fix, so this arm now asserts the unknown-tool half specifically:
# it must NAME the typed verb and must NOT be the missing-args message.
case "$( c_inner_text "$TMP/d4d_out" )" in
    "__ERROR__:unknown tool: 'bogus_tool_name'"*'tools/list'*) d4d=ok;; *) d4d=no;; esac
[ "$d4d" = ok ] \
    && ok "(D-4d) a genuinely unknown tool name is refused as an UNKNOWN TOOL, naming it" \
    || no "(D-4d) unexpected: $( c_inner_text "$TMP/d4d_out" )"

# --- (D-5) pre-X7 behavior unchanged: bare '--mcp' (no startup root) still requires 'path' -------
mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"symbol":"perimeter"}}}' >"$TMP/d5_out"
case "$( c_inner_text "$TMP/d5_out" )" in
    "__ERROR__:missing required field: path"*) d5=ok;; *) d5=no;; esac
[ "$d5" = ok ] \
    && ok "(D-5) bare '--mcp' with no startup root still requires an explicit 'path' (pre-X7 behavior preserved)" \
    || no "(D-5) unexpected: $( c_inner_text "$TMP/d5_out" )"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
