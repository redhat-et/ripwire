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

echo "=== (h) P17 — slice and edit_check are batchable: ONE <batch n=\"5\"> for the edit-loop sweep ==="
# ═══════════════════════════════════════════════════════════════════════════
# capture-audit 2026-09-04, finding P17 (lens 8 #17). batch served 14 verbs; slice (a per-definition on-disk
# re-parse) and edit_check (ms warm off the qheadsnap cache) were excluded, and they are the two an agent
# most wants in the SAME turn as callers/uses — "what did I just change, who calls it, where are the sites,
# what does the body actually flow". Both are READ-ONLY; edit_check is batched WITHOUT new_body, so the
# pre-apply preview (which builds a spliced tree) stays out of the fast sweep.
#
# The assertion is the whole five-verb sweep answering in one call, each sub-answer byte-identical to its
# standalone verb — the same property arm (a) pins for the original four, so a batched slice can never
# become a second, quietly-different slice.
Q5='[{"verb":"for","task":"distance between two points"},{"verb":"callers","symbol":"distance"},{"verb":"uses","symbol":"distance"},{"verb":"slice","symbol":"geometry.cpp:distance"},{"verb":"edit_check","symbol":"geometry.cpp:distance"}]'
BAT5="$( call_batch "$Q5" )"
printf '%s' "$BAT5" > "$TMP/batch_g.xml"
SLICE_STD="$( call_verb slice      '"symbol":"geometry.cpp:distance"' )"
EC_STD="$(    call_verb edit_check '"symbol":"geometry.cpp:distance"' )"
python3 - "$TMP/batch_g.xml" "$SLICE_STD" "$EC_STD" <<'PY2'
import sys, re
batch = open(sys.argv[1]).read()
slice_std, ec_std = sys.argv[2], sys.argv[3]
qs = re.findall(r'<q i="(\d+)" verb="([^"]*)" ok="([01])"(?:\s+err="([^"]*)")?\s*(?:/>|>(.*?)</q>)', batch, re.S)
order = [(v, o) for (_i, v, o, _e, _b) in qs]
expect = [("for","1"),("callers","1"),("uses","1"),("slice","1"),("edit_check","1")]
assert order == expect, "order/ok mismatch: %r  (errs: %r)" % (order, [(v,e) for (_i,v,o,e,_b) in qs if o=="0"])
m = re.search(r'<batch [^>]*n="(\d+)"', batch)
assert m and m.group(1) == "5", "expected one <batch n=\"5\">, got: %r" % (batch[:200],)
def cdata(body):
    body = body.replace("]]]]><![CDATA[>", "]]>")
    assert body.startswith("<![CDATA[") and body.endswith("]]>"), body[:60]
    return body[len("<![CDATA["):-len("]]>")]
payload = {v: cdata(b) for (_i, v, o, _e, b) in qs}
assert payload["slice"]      == slice_std, "batched slice payload != standalone slice"
assert payload["edit_check"] == ec_std,    "batched edit_check payload != standalone edit_check"
print("G_OK")
PY2
if [ $? -eq 0 ]; then
    ok "(h) one <batch n=\"5\"> answers for+callers+uses+slice+edit_check, slice/edit_check byte-identical to standalone"
else
    no "(h) slice/edit_check are not batchable (or answered differently inside the batch)"
    printf '%s\n' "$BAT5" | head -c 900; echo
fi
# the WRITE half stays out: a batched edit_check carrying new_body is the pre-apply PREVIEW, which builds a
# spliced tree — not a fast read. It must refuse as an undeclared field, inline, never silently ignored.
BATNB="$( call_batch '[{"verb":"edit_check","symbol":"geometry.cpp:distance","new_body":"int distance(){return 0;}"}]' )"
printf '%s' "$BATNB" | grep -q 'ok="0"' \
    && ok "(h) a batched edit_check with new_body refuses inline — the preview stays out of the sweep" \
    || { no "(h) new_body was accepted (or silently ignored) inside a batch"; printf '%s\n' "$BATNB" | head -c 500; }
# and the served-set advertisement must name them, so an agent can learn the capability from tools/list.
TOOLS="$( mcp_call "$INIT" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )"
printf '%s' "$TOOLS" | python3 -c '
import sys, json
tools = { t["name"]: t for t in json.load(sys.stdin)["result"]["tools"] }
d = tools["batch"]["description"]
served_ok  = "slice" in d.split("each verb is one of")[1].split("The other")[0] and "edit_check" in d.split("each verb is one of")[1].split("The other")[0]
excluded   = d.split("are NOT batchable:")[1]
still_excl = ("slice" in excluded) or ("edit_check" in excluded)
sys.exit(0 if (served_ok and not still_excl) else 1)
'     && ok "(h) tools/list names slice and edit_check as SERVED and no longer as excluded"     || { no "(h) the batch tools/list stanza still contradicts what batch dispatches"; }

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (i) verify-wave2 F8/F11: a MIXED queries array is refused, not silently reduced ==="
# ═══════════════════════════════════════════════════════════════════════════
# M5 made both grammars legal, which made MIXING them a natural mistake — and the object reader wins a mixed
# array by discarding every string in it:
#   queries:["callers:distance", {"verb":"impact","symbol":"distance"}]
#   → <batch n="1" requested="1" cap="16">…   exit 0, isError unset
# Two sub-queries in, one answered, and requested="1" telling the caller they asked for one. requested= is
# the CALLER'S array length or it is not a disclosure. Both uniform grammars must keep working unchanged —
# that is the half a "just refuse arrays with objects in them" fix would break.
MIX="$( call_batch '["callers:distance",{"verb":"impact","symbol":"distance"}]' )"
case "$MIX" in
    __ERR__*mixes\ the\ two\ grammars*)
        ok "(i) a mixed queries array is refused, naming both counts" ;;
    __ERR__*)
        no "(i) a mixed queries array was refused for the wrong reason: $( printf '%s' "$MIX" | head -c 160 )" ;;
    *)
        n="$(  printf '%s' "$MIX" | grep -oE '<batch n="[0-9]+"' | grep -oE '[0-9]+' )"
        req="$( printf '%s' "$MIX" | grep -oE 'requested="[0-9]+"' | grep -oE '[0-9]+' )"
        no "(i) a mixed queries array answered n=$n requested=$req for a 2-element array — a member was dropped in silence" ;;
esac
# the two uniform grammars are untouched: same two sub-queries, each spelled one way
for label in objects strings; do
    case "$label" in
        objects) Q='[{"verb":"callers","symbol":"distance"},{"verb":"impact","symbol":"distance"}]' ;;
        strings) Q='["callers:distance","impact:distance"]' ;;
    esac
    U="$( call_batch "$Q" )"
    printf '%s' "$U" | grep -q '<batch n="2" requested="2"' \
        && ok "(i) an all-$label array still answers both sub-queries (n=2 requested=2)" \
        || no "(i) an all-$label array broke: $( printf '%s' "$U" | head -c 160 )"
done
# F11: the colon is a SEPARATOR. `callers: distance` is how a human writes one, and the untrimmed space used
# to ride into the symbol and come back as a did-you-mean whose suggestion was the string the caller typed.
SP="$( call_batch '["callers: distance"]' )"
printf '%s' "$SP" | grep -q '<q i="0" verb="callers" ok="1"' \
    && ok "(i) F11: whitespace after the sub-verb colon is trimmed — 'callers: distance' resolves" \
    || no "(i) F11: 'callers: distance' did not resolve: $( printf '%s' "$SP" | grep -oE 'err="[^"]*"' | head -c 200 )"
# and the same parser on the CLI front door, which shares it (main.cpp reads batchObjectFromCliSpec too)
printf 'callers: distance\n' | "$BIN" "$FIX" --batch=- 2>/dev/null | grep -q '<q i="0" verb="callers" ok="1"' \
    && ok "(i) F11: --batch=- trims it too (one parser, two front doors)" \
    || no "(i) F11: the CLI --batch front door still passes the leading space into the symbol"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (j) verify-wave2 F7: a refused sub-query names the schema it was actually judged against ==="
# ═══════════════════════════════════════════════════════════════════════════
# The sub-query IS refused (measured on 2d40209: ok="0" with the unknown-field sentence) — what was wrong is
# the ATTRIBUTION. It read "slice accepts: verb, symbol, pattern, task, …", which is the batch ITEM schema
# under the sub-verb's name; slice accepts no `pattern` and no `from`, so the recovery list was false for the
# verb it named. Judging against the item schema is correct and documented (mcprefusal.h kBatchSubQueryFields).
BADF="$( call_batch '[{"verb":"slice","symbol":"distance","zzz":1}]' )"
printf '%s' "$BADF" | grep -q 'ok="0"' \
    && ok "(j) an undeclared sub-query field is refused inline, never accepted-and-ignored" \
    || no "(j) an undeclared sub-query field was ANSWERED: $( printf '%s' "$BADF" | head -c 200 )"
printf '%s' "$BADF" | grep -q 'batch sub-queries accepts' \
    && ok "(j) the refusal names the batch item schema, not the sub-verb, as the set it applied" \
    || no "(j) the refusal attributes the batch item schema to the sub-verb: $( printf '%s' "$BADF" | grep -oE 'err="[^"]*"' | head -c 220 )"
printf '%s' "$BADF" | grep -qE 'err="[^"]*(slice|edit_check|grep) accepts' \
    && no "(j) the refusal still says '<verb> accepts:' while listing fields that verb does not accept" \
    || ok "(j) no sub-verb is credited with the item schema's fields"


echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
