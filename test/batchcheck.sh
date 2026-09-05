#!/usr/bin/env bash
# batchcheck.sh — gate for  §E A4-R3: the `batch` retrieval verb (MCP + CLI).
# One-turn context sweep: N heterogeneous READ sub-queries answered in ONE call, merged, deduped,
# capped honestly. Asserts:
#   (a) a 4-sub-query batch (for + grep + callers + impact) returns all 4 IN ORDER, and each <q>'s
#       payload is byte-identical to the SAME standalone verb's output (modulo dedup markers);
#   (b) determinism — the same batch twice is byte-identical;
#   (c) one invalid sub-verb among valid ones → an inline ok="0" err= entry, the others intact;
#   (d) an oversized queries array → capped="1" with n<requested (excess REPORTED, not dropped);
#   (e) dedup fires when two sub-queries return the same symbol; the <dup-of q="i"/> marker points at
#       the first identical index;
#   (f) xmllint on the whole batch payload (one well-formed XML document — CDATA-wrapped sub-answers);
#   + hostile inputs: missing/empty/non-array `queries`, and the CLI `--batch=FILE` counterpart.
#
# Usage:  test/batchcheck.sh   |   RIPWIRE_BIN=build_r2c1/ripwire test/batchcheck.sh
# Exits non-zero on any failure. Never mutates the checked-in fixture. Does NOT edit regression.sh.

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

echo "batchcheck: BIN=$BIN  FIX=$FIX"

mcp_call() { printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }

# text payload of a tools/call result's content[0]
result_text() {
    tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
print(r["result"]["content"][0]["text"])
'
}

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize"}'
call_batch() { # $1 = queries JSON array literal
    mcp_call "$INIT" \
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"batch\",\"arguments\":{\"path\":\"$FIX\",\"queries\":$1}}}" \
      | result_text
}
call_verb() { # $1 = verb name  $2 = arguments-object body (without braces)
    mcp_call "$INIT" \
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":{\"path\":\"$FIX\",$2}}}" \
      | result_text
}

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (a) 4-sub-query batch returns all 4 in order, payloads match the standalone verbs ==="
# ═══════════════════════════════════════════════════════════════════════════
Q='[{"verb":"for","task":"distance between two points"},{"verb":"grep","pattern":"distance"},{"verb":"callers","symbol":"distance"},{"verb":"impact","symbol":"distance"}]'
BAT="$( call_batch "$Q" )"
printf '%s' "$BAT" > "$TMP/batch_a.xml"

FOR_STD="$(  call_verb for    '"task":"distance between two points"' )"
GREP_STD="$( call_verb grep   '"pattern":"distance"' )"
REF_STD="$(  call_verb find_referencing_symbols '"symbol":"distance"' )"
IMP_STD="$(  call_verb impact '"symbol":"distance"' )"

python3 - "$TMP/batch_a.xml" "$FOR_STD" "$GREP_STD" "$REF_STD" "$IMP_STD" <<'PY'
import sys, re
batch = open(sys.argv[1]).read()
for_std, grep_std, ref_std, imp_std = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

# parse <q i verb ok>...CDATA...</q> in order (self-closing errors have no body)
qs = re.findall(r'<q i="(\d+)" verb="([^"]*)" ok="([01])"(?:\s+err="[^"]*")?\s*(?:/>|>(.*?)</q>)', batch, re.S)
order  = [(v, o) for (_i, v, o, _b) in qs]
expect = [("for","1"),("grep","1"),("callers","1"),("impact","1")]
assert order == expect, "order/ok mismatch: %r" % order

def cdata(body):
    # unwrap a single CDATA section, rejoining any ]]> split boundary
    body = body.replace("]]]]><![CDATA[>", "]]>")
    assert body.startswith("<![CDATA[") and body.endswith("]]>"), body[:60]
    return body[len("<![CDATA["):-len("]]>")]

payload = {v: cdata(b) for (_i, v, o, b) in qs}
assert payload["for"]    == for_std,  "for payload != standalone"
assert payload["grep"]   == grep_std, "grep payload != standalone"
assert payload["callers"]== ref_std,  "callers payload != standalone find_referencing_symbols"
assert payload["impact"] == imp_std,  "impact payload != standalone"
print("A_OK")
PY
if [ $? -eq 0 ]; then ok "(a) 4 sub-answers in order, each byte-identical to its standalone verb"; else no "(a) batch payloads did not match standalone verbs"; fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (b) determinism — same batch twice is byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════
B1="$( call_batch "$Q" )"; B2="$( call_batch "$Q" )"
[ "$B1" = "$B2" ] && ok "(b) batch output is byte-identical across two runs" \
                  || no "(b) batch output differs between runs (non-deterministic)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (c) one invalid sub-verb among valid → inline error, others intact ==="
# ═══════════════════════════════════════════════════════════════════════════
QC='[{"verb":"impact","symbol":"distance"},{"verb":"bogus_verb","symbol":"x"},{"verb":"uses","symbol":"distance"}]'
BC="$( call_batch "$QC" )"; printf '%s' "$BC" > "$TMP/batch_c.xml"
python3 - "$TMP/batch_c.xml" <<'PY'
import sys, re
b = open(sys.argv[1]).read()
qs = re.findall(r'<q i="(\d+)" verb="([^"]*)" ok="([01])"', b)
assert qs == [("0","impact","1"),("1","bogus_verb","0"),("2","uses","1")], qs
assert 'verb="bogus_verb" ok="0" err="unknown sub-verb' in b, "no inline error for bad sub-verb"
print("C_OK")
PY
if [ $? -eq 0 ]; then ok "(c) bad sub-verb is an inline ok=0 error; the two valid sub-answers are intact"; else no "(c) one-bad-among-good handling wrong"; fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (d) oversized array → capped honestly (n<requested, capped=1) ==="
# ═══════════════════════════════════════════════════════════════════════════
QBIG="$( python3 -c 'import json;print(json.dumps([{"verb":"uses","symbol":"distance"} for _ in range(20)]))' )"
BD="$( call_batch "$QBIG" )"
echo "$BD" | grep -q '<batch n="16" requested="20" cap="16" capped="1"' \
    && ok "(d) 20 sub-queries capped to 16, requested=20 reported, capped=1 (not silently dropped)" \
    || { no "(d) over-cap batch not reported honestly"; echo "     head: $( printf '%s' "$BD" | head -c 120 )"; }

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (e) dedup fires; <dup-of q=\"i\"/> points at the first identical index ==="
# ═══════════════════════════════════════════════════════════════════════════
QE='[{"verb":"impact","symbol":"distance"},{"verb":"grep","pattern":"distance"},{"verb":"impact","symbol":"distance"}]'
BE="$( call_batch "$QE" )"; printf '%s' "$BE" > "$TMP/batch_e.xml"
python3 - "$TMP/batch_e.xml" <<'PY'
import sys, re
b = open(sys.argv[1]).read()
# q0 impact = full CDATA; q2 impact = identical payload → must be <dup-of q="0"/>
m0 = re.search(r'<q i="0" verb="impact" ok="1">(<!\[CDATA\[.*?\]\]>)</q>', b, re.S)
assert m0, "q0 impact should carry a full CDATA payload"
m2 = re.search(r'<q i="2" verb="impact" ok="1">(.*?)</q>', b, re.S)
assert m2, "q2 impact missing"
assert m2.group(1).strip() == '<dup-of q="0"/>', "q2 should dedup to q0, got: %r" % m2.group(1)[:80]
# a DIFFERENT verb between them (grep) must NOT be deduped
assert '<q i="1" verb="grep" ok="1"><![CDATA[' in b, "grep must not dedup"
print("E_OK")
PY
if [ $? -eq 0 ]; then ok "(e) identical impact payload dedups to <dup-of q=\"0\"/>; the differing grep is untouched"; else no "(e) dedup did not fire / points at the wrong index"; fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (f) the whole batch payload is one well-formed XML document (xmllint) ==="
# ═══════════════════════════════════════════════════════════════════════════
if command -v xmllint >/dev/null 2>&1; then
    ff=0
    for f in "$TMP/batch_a.xml" "$TMP/batch_c.xml" "$TMP/batch_e.xml"; do
        printf '%s' "$( cat "$f" )" | xmllint --noout - 2>"$TMP/xl_err" || { no "(f) not well-formed XML: $f — $( cat "$TMP/xl_err" )"; ff=1; }
    done
    [ "$ff" -eq 0 ] && ok "(f) every batch payload is xmllint-clean (CDATA-wrapped sub-answers, mix of XML+JSON)"
else
    echo "  (xmllint not found — skipping (f) well-formedness check)"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== hostile inputs: missing / empty / non-array queries never crash the server ==="
# ═══════════════════════════════════════════════════════════════════════════
assert_err() { # $1 = arguments body ; $2 = label
    OUT="$( mcp_call "$INIT" "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"batch\",\"arguments\":{$1}}}" | tail -1 )"
    printf '%s' "$OUT" | python3 -c '
import sys, json
r = json.load(sys.stdin)
assert "error" in r, ("expected a JSON-RPC error, got: %r" % r)
' 2>/dev/null && ok "hostile: $2 → clean JSON-RPC error (no crash)" \
             || no "hostile: $2 did not yield a clean error: $OUT"
}
assert_err "\"path\":\"$FIX\""                        "queries absent"
assert_err "\"path\":\"$FIX\",\"queries\":[]"         "queries empty array"
assert_err "\"path\":\"$FIX\",\"queries\":\"nope\""   "queries not an array (string)"

# server still alive after the hostile calls (fresh process, one normal batch)
STILL="$( call_batch '[{"verb":"uses","symbol":"distance"}]' )"
printf '%s' "$STILL" | grep -q '<batch n="1"' \
    && ok "hostile: a normal batch still works after malformed inputs" \
    || no "hostile: server broken after malformed inputs: $STILL"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== CLI --batch=FILE counterpart (shared machinery) ==="
# ═══════════════════════════════════════════════════════════════════════════
printf 'for:distance between two points\ngrep:distance\n# comment line\ncallers:distance\nimpact:distance\n' > "$TMP/b.txt"
CLI1="$( "$BIN" "$FIX" --batch="$TMP/b.txt" 2>/dev/null )"
CLI2="$( "$BIN" "$FIX" --batch="$TMP/b.txt" 2>/dev/null )"
[ "$CLI1" = "$CLI2" ] && ok "CLI: --batch is deterministic" || no "CLI: --batch not deterministic"
printf '%s' "$CLI1" | grep -q '<q i="0" verb="for" ok="1">' \
    && printf '%s' "$CLI1" | grep -q '<q i="3" verb="impact" ok="1">' \
    && ok "CLI: verb:arg lines map to the right sub-verbs in order (comment line skipped)" \
    || no "CLI: verb:arg parsing wrong"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$CLI1" | xmllint --noout - 2>"$TMP/xl_cli" \
        && ok "CLI: --batch output is well-formed XML" \
        || no "CLI: --batch output not well-formed: $( cat "$TMP/xl_cli" )"
fi
# CLI stdin form + cap honesty
CLIBIG="$( python3 -c 'print("uses:distance\n"*20)' | "$BIN" "$FIX" --batch=- 2>/dev/null )"
printf '%s' "$CLIBIG" | grep -q 'requested="20" cap="16" capped="1"' \
    && ok "CLI: stdin '-' form works and over-cap is reported honestly" \
    || no "CLI: stdin/cap handling wrong"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (g) M5 — ONE sub-query grammar: the CLI's verb:arg strings answer over MCP too ==="
# ═══════════════════════════════════════════════════════════════════════════
# capture-audit 2026-09-04 M5: `--batch=FILE` took `verb:arg` LINES with CLI verb names; MCP `batch` took
# {verb, …args} OBJECTS with MCP verb names and REFUSED the string form. One verb, one name, two grammars —
# so the capture's own ["for:…","callers:…"] example was a refusal captioned as a success, and an agent that
# knew the CLI spelling paid a failed call to learn the other one. Both grammars now answer; the assertion
# is that they answer THE SAME, not merely that neither errors.
STR="$( call_batch '["for:distance between two points","callers:distance"]' )"
OBJ="$( call_batch '[{"verb":"for","task":"distance between two points"},{"verb":"callers","symbol":"distance"}]' )"
case "$STR" in
    __ERR__*) no "(g) the verb:arg string form is still refused: $( printf '%s' "$STR" | head -c 160 )" ;;
    *)  [ "$STR" = "$OBJ" ] \
            && ok "(g) queries=[\"for:…\",\"callers:…\"] answers BYTE-IDENTICALLY to the object form" \
            || no "(g) the two grammars produced different answers for the same two questions" ;;
esac
# and the CLI file form of the same two lines agrees with both (one grammar, three front doors: CLI file,
# live MCP verb, MCP batch) — modulo the root, which legitimately differs between the surfaces.
printf 'for:distance between two points\ncallers:distance\n' > "$TMP/g.txt"
CLIG="$( "$BIN" "$FIX" --batch="$TMP/g.txt" 2>/dev/null )"
printf '%s' "$CLIG" | grep -q '<q i="0" verb="for" ok="1">' \
    && printf '%s' "$CLIG" | grep -q '<q i="1" verb="callers" ok="1">' \
    && ok "(g) the CLI file form parses the identical two lines to the identical two sub-verbs" \
    || no "(g) the CLI file form disagrees with the MCP string form about these lines"
# The GUARD: an array of arbitrary strings is NOT silently reinterpreted as sub-queries. `["x"]` names no
# served verb, so it must keep getting the bad-value refusal rather than becoming a sub-query called "x".
BAD="$( call_batch '[1,"x",null]' )"
case "$BAD" in
    __ERR__*) ok "(g) an array of arbitrary values still gets the bad-value refusal, not a string-grammar read" ;;
    *)        no "(g) [1,\"x\",null] was accepted — the string grammar is too permissive" ;;
esac

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
