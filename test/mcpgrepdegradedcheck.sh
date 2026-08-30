#!/usr/bin/env bash
# mcpgrepdegradedcheck.sh — the MCP grep dialect's parse-health twin (degradedhintcheck's arm (2)/(3),
# ported to the JSON payload).
#
# The 2026-08-30 degraded-routing round gave the CLI --grep's <f> rows parse_degraded="1" plus a legend
# clause, because over a shredded parse the "in= absent ⇒ no enclosing symbol" claim is unknowable. The
# MCP grep verb serves the SAME collection through a SEPARATE JSON serialization (grepHitsJson,
# src/mcpverbs.h) — so an MCP-only agent kept reading the undisclosed claim the CLI stopped making.
# This gate pins the twin: a hit row in a parse-degraded file carries "parse_degraded":true, the payload
# defines the key in-band (a note key, the JSON dialect's legend channel), a clean file's rows and a
# clean answer stay byte-untouched, and the batch sub-query arm (the SECOND dispatch through the same
# serializer) agrees with the live arm.
#
# RED-FIRST: recorded 2026-08-30 against the pre-port binary — arms (2)(3)(5) FAIL (no key, no note,
# batch arm blind), arms (1)(4)(6) already PASS (they pin the surfaces that must not move).
#
# Fixture: degradedhintcheck.sh's own (victim.cpp with an unclosed paren making the tail an ERROR
# region; ghostFn textually inside it, never extracted; clean.cpp the healthy control).
#
# Usage:  test/mcpgrepdegradedcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/mcpgrepdegradedcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpgrepdegradedcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/corpus"

cat > "$TMP/corpus/victim.cpp" <<'EOF'
int victimFn( int x ) { return x + 1; }
int callerFn( int x ) { return victimFn( x ); }
int brokenFn( int x ) { return ( x +
EOF
printf 'int ghostFn( int x ) { return x + 3; }\n' >> "$TMP/corpus/victim.cpp"
cat > "$TMP/corpus/clean.cpp" <<'EOF'
int cleanFn( int x ) { return x + 4; }
EOF

# ── the two MCP surfaces (mcpclidiffcheck.sh's own harness) ─────────────────────────────────────────
mcp_text() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message","") if "error" in r else r["result"]["content"][0]["text"])
'
}
batch_sub() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":"'"$TMP/corpus"'","queries":['"$1"']}}}' \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json, re, html
r = json.load(sys.stdin)
if "error" in r: print("__ERROR__:" + r["error"].get("message","")); raise SystemExit
t = r["result"]["content"][0]["text"]
m = re.search(r"<q i=\"0\" verb=\"[^\"]*\" ok=\"0\" err=\"([^\"]*)\"", t)
if m: print("__ERROR__:" + html.unescape(m.group(1))); raise SystemExit
m = re.search(r"<!\[CDATA\[(.*)\]\]>", t, re.S)
print(m.group(1) if m else "__NOPAYLOAD__")
'
}
call() { printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }

# hitflag PAYLOADFILE FILE — "true" iff the hit row for FILE carries parse_degraded true, "absent" iff
# the row exists without the key, "norow" iff no row for FILE. JSON-parsed, never grepped: a substring
# probe would match the note's own prose.
hitflag() {
    python3 - "$1" "$2" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
rows = [h for h in j.get("hits", []) if h.get("file","").endswith(sys.argv[2])]
if not rows: print("norow")
elif any(h.get("parse_degraded") is True for h in rows): print("true")
else: print("absent")
PY
}

# ── (1) presence guard: victim.cpp IS degraded (the CLI gate's precondition, re-asserted here) ──────
SKIP="$( "$BIN" "$TMP/corpus" --no-cache --skipped 2>/dev/null )"
printf '%s' "$SKIP" | grep -q 'p="victim.cpp" why="degraded-parse"' \
    && ok "(1) victim.cpp flagged degraded-parse by --skipped (precondition)" \
    || { no "(1) fixture no longer parses as degraded — every later arm is vacuous"; printf '%s\n' "$SKIP" | tail -1; }

# ── (2) live arm: the degraded file's hit row carries "parse_degraded":true ─────────────────────────
mcp_text "$( call grep '{"path":"'"$TMP/corpus"'","pattern":"return x + 1"}' )" >"$TMP/live.json"
case "$( hitflag "$TMP/live.json" victim.cpp )" in
    true )   ok "(2) live grep marks victim.cpp's hit row parse_degraded:true" ;;
    norow )  no "(2) live grep served no victim.cpp row at all — the probe is broken"; head -c 400 "$TMP/live.json"; echo ;;
    * )      no "(2) live grep's victim.cpp row carries no parse_degraded key"; head -c 400 "$TMP/live.json"; echo ;;
esac

# ── (3) the key is defined in-band: a note key rides the same payload ───────────────────────────────
python3 -c '
import json, sys
j = json.load(open(sys.argv[1]))
note = j.get("parse_degraded_note", "")
ok = "UNKNOWN" in note and "file scope" in note and "skipped" in note
raise SystemExit(0 if ok else 1)
' "$TMP/live.json" \
    && ok "(3) the payload defines parse_degraded in-band (note names UNKNOWN / file scope / skipped)" \
    || no "(3) parse_degraded is emitted but never defined in the payload"

# ── (4) precision: a clean answer is byte-untouched — no key, no note ───────────────────────────────
mcp_text "$( call grep '{"path":"'"$TMP/corpus"'","pattern":"return x + 4"}' )" >"$TMP/clean.json"
if [ "$( hitflag "$TMP/clean.json" clean.cpp )" = "absent" ] && ! grep -q 'parse_degraded' "$TMP/clean.json"; then
    ok "(4) a clean-file answer carries neither the key nor the note (purely additive)"
else
    no "(4) the healthy control answer moved"; head -c 400 "$TMP/clean.json"; echo
fi

# ── (5) batch arm: the SECOND dispatch through grepHitsJson agrees with the live arm ────────────────
batch_sub '{"verb":"grep","pattern":"return x + 1"}' >"$TMP/batch.json"
case "$( hitflag "$TMP/batch.json" victim.cpp )" in
    true )  ok "(5) batch grep sub-query marks victim.cpp's hit row parse_degraded:true" ;;
    * )     no "(5) the batch arm disagrees with the live arm"; head -c 400 "$TMP/batch.json"; echo ;;
esac

# ── (6) determinism with the new key ────────────────────────────────────────────────────────────────
mcp_text "$( call grep '{"path":"'"$TMP/corpus"'","pattern":"return x + 1"}' )" >"$TMP/live2.json"
diff -q "$TMP/live.json" "$TMP/live2.json" >/dev/null \
    && ok "(6) MCP grep payload deterministic run-to-run" \
    || no "(6) MCP grep payload differs run-to-run"

exit $fail
