#!/usr/bin/env bash
# mcpw3fixcheck.sh — the FINAL-VERIFIER findings against the round's own MCP argument layer
# (H3/H4/H5/M4/M5/M8 + the echo-cap NIT). Sibling of mcpw2fixcheck.sh, which gates the wave-2 verifier's
# eight findings; this file gates the six the final verifier found IN those fixes, plus the one the wave-2
# fixes introduced (H3 is a REGRESSION of that wave, not a pre-existing defect).
#
# THE LAW, unchanged from wave 2: the MCP surface dispatches TWICE — the live stdio server (`--mcp`, mcp.h)
# and the `batch` verb's sub-query chain (mcpverbs.h's runBatchSub). Every fix here lands in ONE shared
# helper (mcpjson.h's findKeyValuePos/objectKeys, mcpverbs.h's mcpIntArg/mcpStringArg/mcpArrayArg/
# mcpUnknownFieldRefusal, mcprefusal.h's kMcpValueFields/kMcpVerbFields/cappedEcho), and every item
# reachable from both arms is probed on BOTH.
#
# THE ARM THAT MUST NOT RESTATE THE CODE: M4's. kMcpVerbFields is a hand-written mirror of the tools/list
# inputSchemas — exactly the shape that drifts — so the M4 field-table arm ENUMERATES: it parses the live
# tools/list schemas and asks the live server which fields it accepts, and diffs those two. A gate that
# restated the table could not catch the table (the M14 lesson).
#
# Usage:
#   test/mcpw3fixcheck.sh                                      # uses build/ctxpack
#   test/mcpw3fixcheck.sh /path/to/other/ctxpack               # positional binary
#   CTXPACK_BIN=build_base/ctxpack test/mcpw3fixcheck.sh       # env binary (the RED run)
#
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpw3fixcheck: BIN=$BIN  CORPUS=$ROOT"

# ── the two arms (same helpers mcpw2fixcheck.sh uses, same contract) ──────────────────────────────────────
mcp_text() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERROR__:" + r["error"].get("message",""))
else:            print(r["result"]["content"][0]["text"])
'
}

batch_sub() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":"'"$ROOT"'","queries":['"$1"']}}}' \
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

printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 >"$TMP/tools.json"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== H3 — an argument VALUE that spells a key name can no longer shadow the key ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# The finding's own two probes. Both were WRONG in the same way for the same reason: findRawValue matched
# `"limit"` anywhere in the args text and then took the NEXT colon, so `pattern:"limit"` donated the key and
# `offset`'s value became the limit.
#
#   (a) pattern="limit" offset=2 limit=5  → limit was honored as 2 AND disclosed as 2 (the disclosure lied)
#   (b) pattern="limit" offset=0          → a hard refusal naming a `limit` the caller never sent
H3A="$( mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"limit","offset":2,"limit":5}' )" )"
case "$H3A" in
    *'"shown":5'*'"limit":5'*) ok "H3(a) [live]: limit=5 is honored AND disclosed as 5 (the value's text no longer shadows the key)";;
    __ERROR__*)                no "H3(a) [live]: refused outright: $H3A";;
    *)                         no "H3(a) [live]: the pattern VALUE still shadows the limit key: $( printf '%s' "$H3A" | head -c 200 )";;
esac
H3B="$( mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"limit","offset":0}' )" )"
case "$H3B" in
    __ERROR__*) no "H3(b) [live]: still refuses a field the caller never sent: $H3B";;
    *'"pattern":"limit"'*) ok "H3(b) [live]: pattern=\"limit\" offset=0 answers (no phantom limit refusal)";;
    *) no "H3(b) [live]: unexpected: $( printf '%s' "$H3B" | head -c 160 )";;
esac
# the SECOND arm, same two probes — one seam, so both must move together.
H3AB="$( batch_sub '{"verb":"grep","pattern":"limit","offset":2,"limit":5}' )"
case "$H3AB" in
    *'"shown":5'*'"limit":5'*) ok "H3(a) [batch]: same shared reader, same answer";;
    *)                         no "H3(a) [batch]: the batch arm still shadows: $( printf '%s' "$H3AB" | head -c 200 )";;
esac
[ "$H3A" = "$H3AB" ] || no "H3(a): the two arms disagree — live and batch read the window through different code"

# the whole shadow FAMILY, one probe per paging/domain field: a value spelling the field name, as a plain
# substring AND as JSON-looking text, must never be read as that field.
for probe in 'grep|pattern|"limit"|limit' \
             'grep|pattern|"offset"|offset' \
             'grep|pattern|"\"limit\": 99"|limit' \
             'whereis|symbol|"limit"|limit'; do
    IFS='|' read -r verb host val field <<EOF
$probe
EOF
    case "$verb" in whereis) other='"symbol"';; *) other='"pattern"';; esac
    R="$( mcp_text "$( call "$verb" '{"path":"'"$ROOT"'",'"$other"':'"$val"'}' )" )"
    case "$R" in
        __ERROR__:"invalid value for field: $field"*) no "H3 [$verb $host=$val]: the VALUE was read as the $field key — $R";;
        *) ok "H3 [$verb $host=$val]: no phantom $field refusal (the value is a value)";;
    esac
done

# a key inside a NESTED object or array is not this request's key.
case "$( mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"escapeXml","filter":{"limit":9},"limit":3}' )" )" in
    __ERROR__*"unknown field: 'filter'"*) ok "H3: a nested object's key is not the request's key (and the undeclared wrapper is refused — M4)";;
    *'"limit":3'*)                        ok "H3: a nested object's `limit` is ignored; the top-level one wins";;
    *) no "H3: a nested key still leaks into the top-level read";;
esac

# DUPLICATE KEYS: FIRST-WINS, pinned. (Most parsers are last-wins; this deliberately is not — the value the
# verb READS comes from the same first-wins scan, so validating the last would validate a value never used.)
case "$( mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"escapeXml","limit":3,"limit":7}' )" )" in
    *'"limit":3'*) ok "H3: duplicate keys are FIRST-WINS (pinned: limit=3,limit=7 → 3)";;
    *'"limit":7'*) no "H3: duplicate keys resolved LAST-wins — mcpjson.h pins first-wins; move both together";;
    *)             no "H3: duplicate keys produced neither value";;
esac
# and the same pin on the VALUE a verb reads, not just the one it validates (the validator/parser split).
case "$( mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"escapeXml","pattern":"zzz_no_such_literal_zzz"}' )" )" in
    *'"pattern":"escapeXml"'*) ok "H3: the value READ is the same occurrence the shape check accepted (no validator/parser split)";;
    *)                         no "H3: the shape check and the read disagree on which duplicate wins";;
esac

# same family, one function away: the ENVELOPE id must not be shadowed by an argument value spelling `id`.
IDR="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"grep","arguments":{"path":"'"$ROOT"'","pattern":"id","limit":3}},"id":77}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id"))' )"
[ "$IDR" = "77" ] \
    && ok "H3: findRawId reads the ENVELOPE id (77), not an argument value spelling 'id'" \
    || no "H3: the reply echoed id=$IDR — an argument shadowed the envelope id"

# and the ONE deliberate reach-through-a-wrapper read must still work (params.protocolVersion).
PV="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["protocolVersion"])' )"
[ "$PV" = "2024-11-05" ] \
    && ok "H3: params.protocolVersion still negotiates (the top-level-only rule did not eat the handshake)" \
    || no "H3: protocolVersion negotiation broke — got '$PV'"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== H4 — explore/pack_task partition refuses out-of-band / WRAPPING / non-integer values ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# 4294967299 is the finding's own probe: the raw uint32 cast wrapped it to 3 and ran a 3-way fan-out; 2^32
# wrapped to 0 and served a single bundle. Nothing outside 2..16 may reach the core (the CLI's own band).
for bad in 4294967299 4294967296 0 -1 1 17 2.5 abc; do
    case "$bad" in abc) val='"abc"';; *) val="$bad";; esac
    for verb in explore pack_task; do
        R="$( mcp_text "$( call "$verb" '{"path":"'"$ROOT"'","task":"json escape","partition":'"$val"',"budget_tokens":3000}' )" )"
        case "$R" in
            __ERROR__:"invalid value for field: partition"*"2..16"*"got '$bad'"*"e.g. partition="*) ok "H4 [$verb] partition=$bad: refused with the band + got-echo + example";;
            __ERROR__*) no "H4 [$verb] partition=$bad: refuses but not in the shared wording: $R";;
            *'<ctx-partitions'*) no "H4 [$verb] partition=$bad: WRAPPED into a real fan-out — $( printf '%s' "$R" | head -c 120 )";;
            *) no "H4 [$verb] partition=$bad: silently ignored, single bundle served";;
        esac
    done
done
# the in-band values must still be honored exactly, and an ABSENT partition must still be one bundle.
case "$( mcp_text "$( call explore '{"path":"'"$ROOT"'","task":"json escape","partition":4,"budget_tokens":3000}' )" )" in
    *'<ctx-partitions partitions="4"'*) ok "H4: an in-band partition=4 still fans out (no over-refusal)";;
    *) no "H4: partition=4 is inside the declared band and must be honored";;
esac
case "$( mcp_text "$( call explore '{"path":"'"$ROOT"'","task":"json escape","budget_tokens":3000}' )" )" in
    *'<ctx-partitions'*) no "H4: an ABSENT partition must serve ONE un-split bundle";;
    *'<ctx '*|*'<ctx>'*)  ok "H4: an ABSENT partition still serves the single bundle";;
    *) no "H4: the absent-partition bundle shape moved";;
esac
# tools/list must DECLARE the band it enforces (a refusal naming a range the schema never stated is a trap).
python3 - "$TMP/tools.json" <<'PY' >"$TMP/h4.res" 2>&1
import json, sys
d = { t["name"]: t for t in json.load(open(sys.argv[1]))["result"]["tools"] }
e = d["explore"]["description"]
print("OK" if "2..16" in e and "refused" in e else "GOT:" + e[-200:])
PY
[ "$( cat "$TMP/h4.res" )" = "OK" ] \
    && ok "H4: the explore stanza DECLARES the 2..16 band and says it refuses outside it" \
    || no "H4: the band is enforced but undeclared: $( cat "$TMP/h4.res" )"
# the OTHER arm: explore/pack_task are not batch-served, so the second arm is a clean unknown-sub-verb refusal.
case "$( batch_sub '{"verb":"pack_task","task":"x"}' )" in
    __ERROR__*"unknown sub-verb 'pack_task'"*) ok "H4 [batch]: explore/pack_task are not batch-served — one partition seam, and it is the shared one";;
    *) no "H4 [batch]: the batch arm answered pack_task — a SECOND partition seam this gate does not cover";;
esac

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== H5 — every schema-typed STRING field refuses a wrong SHAPE (both arms) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# N11 fixed `files` and stopped one field short: `diff:["a","b"]` read as absent and situational_awareness
# answered about the working-tree git diff and reported it CLEAN with total confidence. The eight the verifier
# named, plus the rest of the enumeration, each with a DIFFERENT wrong shape so no single branch can carry them.
for probe in 'situational_awareness|diff|["a","b"]' \
             'situational_awareness|files|["a"]' \
             'whereis|kind|["x"]' \
             'stray_content|kind|5' \
             'flags|kind|{"a":1}' \
             'doc_drift|kind|true' \
             'owners|symbol|["x"]' \
             'flags|symbol|42' \
             'grep|pattern|["a"]' \
             'lego|type|5' \
             'for|task|["a"]' \
             'cochange|file|7' \
             'path_between|from|["a"]' \
             'fetch_body|handle|null' \
             'from_trace|trace|["a"]' \
             'exemplar|kind|["fn"]' \
             'find_symbol|symbol|{"n":1}' \
             'analyze|path|5'; do
    IFS='|' read -r verb field val <<EOF
$probe
EOF
    args='{"path":"'"$ROOT"'","'"$field"'":'"$val"'}'
    case "$field" in path) args='{"path":'"$val"'}';; esac
    R="$( mcp_text "$( call "$verb" "$args" )" )"
    case "$R" in
        __ERROR__:"invalid value for field: $field"*"got '"*"', e.g. $field="*) ok "H5 [live/$verb.$field=$val]: refused with the type + got-echo + example";;
        __ERROR__:"missing required field"*) no "H5 [live/$verb.$field=$val]: still collapsed onto absent — $R";;
        __ERROR__*) no "H5 [live/$verb.$field=$val]: refuses but not in the shared wording: $R";;
        *) no "H5 [live/$verb.$field=$val]: still accepted-and-ignored; the verb served a DEFAULT — $( printf '%s' "$R" | head -c 120 )";;
    esac
done
# the batch arm's own string set (the item schema), same reader, same sentence.
for probe in 'grep|pattern|["a"]' 'lego|type|5' 'for|task|{"a":1}' 'cochange|file|7' \
             'find_symbol|symbol|["x"]' 'path_between|from|3' 'fetch_body|handle|null' 'grep|verb|5'; do
    IFS='|' read -r verb field val <<EOF
$probe
EOF
    if [ "$field" = "verb" ]; then sub='{"verb":'"$val"'}'; else sub='{"verb":"'"$verb"'","'"$field"'":'"$val"'}'; fi
    R="$( batch_sub "$sub" )"
    case "$R" in
        __ERROR__:"invalid value for field: $field"*"got '"*) ok "H5 [batch/$verb.$field=$val]: the second arm refuses through the same reader";;
        __ERROR__:"missing required field"*) no "H5 [batch/$verb.$field=$val]: still collapsed onto absent — $R";;
        *) no "H5 [batch/$verb.$field=$val]: unexpected: $( printf '%s' "$R" | head -c 140 )";;
    esac
done
# and the confidently-wrong ANSWER the finding is really about must be gone: a bad `diff` must NOT produce a
# clean-tree report, on either arm's wording.
case "$( mcp_text "$( call situational_awareness '{"path":"'"$ROOT"'","diff":["a","b"]}' )" )" in
    *'working tree is clean'*|*'"changed_files":[]'*) no "H5: a wrong-shaped diff STILL answers 'the tree is clean' — the finding's actual harm";;
    *) ok "H5: a wrong-shaped diff can no longer produce a confidently-wrong clean-tree answer";;
esac
# no over-refusal: every one of those fields still works when given a STRING.
for probe in 'whereis|symbol|"escapeXml"' 'stray_content|kind|"main"' 'flags|kind|"CTXPACK"' \
             'doc_drift|kind|"README"' 'owners|symbol|"escapeXml"' 'for|task|"json escape"'; do
    IFS='|' read -r verb field val <<EOF
$probe
EOF
    extra=''
    case "$verb" in whereis) ;; esac
    R="$( mcp_text "$( call "$verb" '{"path":"'"$ROOT"'","'"$field"'":'"$val"'}' )" )"
    case "$R" in
        __ERROR__:"invalid value for field"*) no "H5 OVER-REFUSAL [$verb.$field=$val]: a valid STRING was refused — $R";;
        *) ok "H5 no-over-refusal [$verb.$field=$val]: a valid string still answers";;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== M8 — a present-but-wrong-shaped ARRAY is a bad VALUE, not a missing field ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
for probe in 'connect|symbols|5' \
             'connect|symbols|{"a":1}' \
             'connect|symbols|["main"]' \
             'batch|queries|5' \
             'batch|queries|[1,"x",null]' \
             'batch|queries|{"verb":"grep"}' \
             'analyze|paths|5' \
             'analyze|paths|[]'; do
    IFS='|' read -r verb field val <<EOF
$probe
EOF
    case "$field" in
        paths) args='{"'"$field"'":'"$val"'}';;
        *)     args='{"path":"'"$ROOT"'","'"$field"'":'"$val"'}';;
    esac
    R="$( mcp_text "$( call "$verb" "$args" )" )"
    case "$R" in
        __ERROR__:"invalid value for field: $field"*"got '"*"', e.g. $field="*) ok "M8 [$verb.$field=$val]: bad VALUE with the domain + got-echo + example";;
        __ERROR__:"missing required field"*) no "M8 [$verb.$field=$val]: still says MISSING for a field that WAS sent — $R";;
        __ERROR__*) no "M8 [$verb.$field=$val]: refuses but not in the shared wording: $R";;
        *) no "M8 [$verb.$field=$val]: accepted and ignored — $( printf '%s' "$R" | head -c 120 )";;
    esac
done
# connect's 1-name case must carry the DOMAIN clause and an example, not the old bespoke sentence.
C1="$( mcp_text "$( call connect '{"path":"'"$ROOT"'","symbols":["main"]}' )" )"
case "$C1" in
    *"connect needs 2..16 symbols (got 1)"*) no "M8: connect symbols:[\"main\"] still serves the bespoke fourth dialect";;
    *"2..16 symbol names"*"e.g. symbols="*)   ok "M8: connect symbols:[\"main\"] gets the domain clause + a runnable example";;
    *) no "M8: unexpected connect 1-name refusal: $C1";;
esac
# and ABSENT must still be the M7 missing-field sentence — the two halves stay distinguishable.
for pair in 'connect|symbols' 'batch|queries'; do
    v="${pair%%|*}"; f="${pair#*|}"
    case "$( mcp_text "$( call "$v" '{"path":"'"$ROOT"'"}' )" )" in
        __ERROR__:"missing required field: $f"*) ok "M8 [$v]: an ABSENT $f is still reported MISSING (the split holds in both directions)";;
        *) no "M8 [$v]: an absent $f no longer reads as missing — the split inverted";;
    esac
done
# no over-refusal: the good shapes, including connect's documented comma-string.
for probe in 'connect|{"path":"'"$ROOT"'","symbols":["main","parseArgs"]}' \
             'connect|{"path":"'"$ROOT"'","symbols":"main,parseArgs"}' \
             'batch|{"path":"'"$ROOT"'","queries":[{"verb":"grep","pattern":"escapeXml","limit":2}]}' \
             'analyze|{"paths":["'"$ROOT"'/src","'"$ROOT"'/test"]}'; do
    v="${probe%%|*}"; a="${probe#*|}"
    case "$( mcp_text "$( call "$v" "$a" )" )" in
        __ERROR__*) no "M8 OVER-REFUSAL [$v]: a documented good shape was refused — $( mcp_text "$( call "$v" "$a" )" )";;
        *) ok "M8 no-over-refusal [$v]: the documented shape still answers";;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== M4 — an argument the verb does not DECLARE refuses, with a near-miss ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# The finding's own probes: explore honors budget_tokens while token_budget / max_tokens were DROPPED in
# silence, and no unknown field was ever refused on either arm.
for f in token_budget max_tokens budget_token budgettokens; do
    R="$( mcp_text "$( call explore '{"path":"'"$ROOT"'","task":"json escape","'"$f"'":200}' )" )"
    case "$R" in
        __ERROR__:"unknown field: '$f'"*"explore accepts:"*"budget_tokens"*) ok "M4 [live] $f: refused, naming the field and listing explore's declared set";;
        __ERROR__*) no "M4 [live] $f: refuses but not in the shared wording: $R";;
        *) no "M4 [live] $f: STILL silently dropped — the near-miss class is open";;
    esac
done
# the near-miss must actually fire when one is close, and must NOT fire when nothing is (a 3-edit suggestion
# for a 4-character field is noise, not help).
case "$( mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"x","limitt":3}' )" )" in
    *"unknown field: 'limitt' (did you mean 'limit'?)"*) ok "M4: a 1-edit typo gets the near-miss (limitt → limit)";;
    *) no "M4: limitt did not suggest limit";;
esac
case "$( mcp_text "$( call analyze '{"path":"'"$ROOT"'","task":"x"}' )" )" in
    *"unknown field: 'task' (did you mean"*) no "M4: 'task' suggested a 3-edit match for a 4-char name — the bar is too loose";;
    *"unknown field: 'task'"*"analyze accepts:"*) ok "M4: no near-miss offered when nothing is close (the set is listed instead)";;
    *) no "M4: analyze accepted an undeclared task field";;
esac
# the batch arm, against the batch ITEM schema — and the sub-VERB must be judged first (an unknown verb has
# no schema for the field check to use).
case "$( batch_sub '{"verb":"grep","pattern":"x","limitt":3}' )" in
    __ERROR__:"unknown field: 'limitt' (did you mean 'limit'?)"*"grep accepts:"*) ok "M4 [batch] limitt: refused against the batch item schema, with the near-miss";;
    *) no "M4 [batch] limitt: $( batch_sub '{"verb":"grep","pattern":"x","limitt":3}' )";;
esac
case "$( batch_sub '{"verb":"connect","symbols":["main","parseArgs"],"radius":6}' )" in
    __ERROR__*"unknown sub-verb 'connect'"*) ok "M4 [batch]: an unknown sub-VERB is reported before its fields are judged";;
    *) no "M4 [batch]: the field check pre-empted the unknown-sub-verb refusal — wrong order";;
esac
# THE ENUMERATED ARM (the M14 lesson): the live tools/list schemas vs what the server actually accepts.
# Every declared property must be accepted, and a made-up name must be refused, for EVERY advertised verb.
# Nothing here restates kMcpVerbFields — the expectation comes from the wire.
python3 - "$BIN" "$ROOT" "$TMP/tools.json" <<'PY' >"$TMP/m4enum.res" 2>&1
import json, re, subprocess, sys
BIN, ROOT, TOOLS = sys.argv[1], sys.argv[2], sys.argv[3]

def rpc(name, args):
    req = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":%s}' % json.dumps({"name": name, "arguments": args})
    inp = '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' + req + "\n"
    out = subprocess.run([BIN, "--mcp"], input=inp, capture_output=True, text=True).stdout.strip().split("\n")
    return json.loads(out[-1])

def err(r):
    return r["error"]["message"] if "error" in r else ""

tools    = json.load(open(TOOLS))["result"]["tools"]
problems = []
# a value shaped right for each declared type, so the only thing under test is field ACCEPTANCE.
sample = {"string": "zzz_probe_zzz", "integer": 1, "array": [], "object": {}}
for t in tools:
    name  = t["name"]
    props = t["inputSchema"].get("properties", {})
    for field, spec in props.items():
        if field in ("path", "paths"): continue          # the universal root selectors, exercised elsewhere
        args = {"path": ROOT, field: sample.get(spec.get("type"), "zzz")}
        m = err(rpc(name, args))
        if m.startswith("unknown field:"):
            problems.append("%s DECLARES %s but the server refuses it as unknown — kMcpVerbFields is missing it" % (name, field))
    # and a name the schema does NOT declare must be refused (the check is real, not vacuous).
    m = err(rpc(name, {"path": ROOT, "zzz_not_a_field_zzz": 1}))
    if "unknown field: 'zzz_not_a_field_zzz'" not in m:
        problems.append("%s accepted an undeclared field (got: %s)" % (name, m[:80] or "<no error>"))
# `pack_task` is a callable ALIAS: it must accept explore's declared set and refuse a made-up name too.
for field in ("task", "budget_tokens", "partition"):
    if err(rpc("pack_task", {"path": ROOT, field: 2 if field != "task" else "x"})).startswith("unknown field:"):
        problems.append("pack_task rejects explore's declared field %s — the alias does not share the row" % field)
if "unknown field: 'zzz_not_a_field_zzz'" not in err(rpc("pack_task", {"path": ROOT, "zzz_not_a_field_zzz": 1})):
    problems.append("pack_task accepted an undeclared field")
print("OK(%d verbs)" % len(tools) if not problems else "; ".join(problems[:6]))
PY
case "$( cat "$TMP/m4enum.res" )" in
    OK*) ok "M4: every tools/list-declared field is ACCEPTED and every undeclared name REFUSED, enumerated from the wire $( cat "$TMP/m4enum.res" )";;
    *)   no "M4 enumeration: $( cat "$TMP/m4enum.res" )";;
esac
# pack_task: ADVERTISED, not refused — and advertised in BOTH arms' surfaces.
case "$( mcp_text "$( call pack_task '{"path":"'"$ROOT"'","task":"json escape","budget_tokens":2000}' )" )" in
    __ERROR__*) no "M4: the pack_task alias stopped working — the round chose to advertise it, not refuse it";;
    *) ok "M4: the pack_task alias still answers (advertising was the chosen shape)";;
esac
python3 - "$TMP/tools.json" <<'PY' >"$TMP/m4alias.res" 2>&1
import json, sys
d = { t["name"]: t for t in json.load(open(sys.argv[1]))["result"]["tools"] }
problems = []
if "pack_task" in d: problems.append("pack_task got its own tools/list stanza — kMcpVerbCount must then count it")
if "pack_task" not in d["explore"]["description"]: problems.append("the explore stanza does not advertise the pack_task alias")
if "pack_task" not in d["batch"]["description"]:   problems.append("the batch stanza's exclusion list does not name pack_task")
print("OK" if not problems else "; ".join(problems))
PY
[ "$( cat "$TMP/m4alias.res" )" = "OK" ] \
    && ok "M4: pack_task is advertised in BOTH surfaces (explore stanza + batch exclusion list), with no double-counted stanza" \
    || no "M4: $( cat "$TMP/m4alias.res" )"
# an unknown TOOL still gets the tool-level refusal (the field check must not swallow it), and the alias is
# in the near-miss pool while the printed count stays the ADVERTISED one.
python3 - "$BIN" "$ROOT" "$TMP/tools.json" <<'PY' >"$TMP/m4tool.res" 2>&1
import json, subprocess, sys
BIN, ROOT, TOOLS = sys.argv[1], sys.argv[2], sys.argv[3]
def err(name, args):
    req = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":%s}' % json.dumps({"name": name, "arguments": args})
    inp = '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' + req + "\n"
    r = json.loads(subprocess.run([BIN, "--mcp"], input=inp, capture_output=True, text=True).stdout.strip().split("\n")[-1])
    return r["error"]["message"] if "error" in r else ""
n = len(json.load(open(TOOLS))["result"]["tools"])
m = err("packtask", {"path": ROOT, "task": "x"})
problems = []
if "unknown tool: 'packtask'" not in m:            problems.append("a typo'd TOOL name no longer gets the tool refusal: " + m[:90])
if "did you mean 'pack_task'" not in m:            problems.append("the callable alias is not in the near-miss pool: " + m[:90])
if ("for the %d available tools" % n) not in m:    problems.append("the refusal promises a count != the %d advertised tools: %s" % (n, m[-60:]))
print("OK" if not problems else "; ".join(problems))
PY
[ "$( cat "$TMP/m4tool.res" )" = "OK" ] \
    && ok "M4: a typo'd tool name still gets the TOOL refusal, suggests the alias, and quotes the ADVERTISED count" \
    || no "M4: $( cat "$TMP/m4tool.res" )"

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== M5 — numeric-string / float / overflow values refuse; in-range integers still work ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# top_k:"1e3" and budget_tokens:"1e3" both coerced to 1; top_k:2^40 silently CLAMPED to an undeclared ceiling.
for bad in '"1e3"|1e3' '1099511627776|1099511627776' '0|0' '-1|-1' '3.7|3.7' '1001|1001' '"abc"|abc'; do
    val="${bad%%|*}"; got="${bad##*|}"
    R="$( mcp_text "$( call memory_recall '{"path":"'"$ROOT"'","task":"cache key","top_k":'"$val"'}' )" )"
    case "$R" in
        __ERROR__:"invalid value for field: top_k"*"1..1000"*"got '$got'"*"e.g. top_k="*) ok "M5 top_k=$val: refused with the band + got-echo + example";;
        __ERROR__*) no "M5 top_k=$val: refuses but not in the shared wording: $R";;
        *) no "M5 top_k=$val: still coerced/clamped silently — $( printf '%s' "$R" | head -c 110 )";;
    esac
done
for bad in '"1e3"|1e3' '0|0' '-5|-5' '2.5|2.5' '"abc"|abc'; do
    val="${bad%%|*}"; got="${bad##*|}"
    R="$( mcp_text "$( call explore '{"path":"'"$ROOT"'","task":"json escape","budget_tokens":'"$val"'}' )" )"
    case "$R" in
        __ERROR__:"invalid value for field: budget_tokens"*"got '$got'"*"e.g. budget_tokens="*) ok "M5 budget_tokens=$val: refused with the domain + got-echo + example";;
        __ERROR__*) no "M5 budget_tokens=$val: refuses but not in the shared wording: $R";;
        *) no "M5 budget_tokens=$val: still coerced silently — $( printf '%s' "$R" | head -c 110 )";;
    esac
done
# in-range integers keep working, including the quoted form clients stringify, and the CEILING is declared.
case "$( mcp_text "$( call memory_recall '{"path":"'"$ROOT"'","task":"cache key","top_k":1000}' )" )" in
    __ERROR__*) no "M5: top_k=1000 is the declared ceiling and must be accepted";;
    *) ok "M5: top_k=1000 (the declared ceiling) is honored";;
esac
case "$( mcp_text "$( call memory_recall '{"path":"'"$ROOT"'","task":"cache key","top_k":"4"}' )" )" in
    __ERROR__*) no "M5: a client-stringified integer top_k:\"4\" must still parse (findRawValue's isQuoted path)";;
    *) ok "M5: a client-stringified integer top_k:\"4\" still parses";;
esac
python3 - "$TMP/tools.json" <<'PY' >"$TMP/m5decl.res" 2>&1
import json, sys
d = { t["name"]: t for t in json.load(open(sys.argv[1]))["result"]["tools"] }
r = d["memory_recall"]["description"]
print("OK" if "1..1000" in r else "GOT:" + r[-200:])
PY
[ "$( cat "$TMP/m5decl.res" )" = "OK" ] \
    && ok "M5: the memory_recall stanza DECLARES the 1..1000 ceiling it enforces (no undeclared clamp)" \
    || no "M5: the top_k ceiling is enforced but undeclared: $( cat "$TMP/m5decl.res" )"
# start_line/end_line were the last unguarded numerics — both arms.
for arm in live batch; do
    if [ "$arm" = live ]; then R="$( mcp_text "$( call fetch_body '{"path":"'"$ROOT"'","handle":"zzz","start_line":3.9}' )" )"
    else                       R="$( batch_sub '{"verb":"fetch_body","handle":"zzz","start_line":3.9}' )"; fi
    case "$R" in
        __ERROR__:"invalid value for field: start_line"*"got '3.9'"*) ok "M5 [$arm] start_line=3.9: refused, not truncated to 3";;
        *) no "M5 [$arm] start_line=3.9: $( printf '%s' "$R" | head -c 140 )";;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== NIT — a hostile-sized argument cannot mint a hostile-sized refusal frame ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
BIG="$( python3 -c 'print("A"*400000)' )"
for probe in "value|$( call grep '{"path":"'"$ROOT"'","pattern":"x","limit":"'"$BIG"'"}' )" \
             "key|$( call grep '{"path":"'"$ROOT"'","pattern":"x","'"$BIG"'":1}' )" \
             "symbol|$( call impact '{"path":"'"$ROOT"'","symbol":"'"$BIG"'"}' )" \
             "toolname|$( printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s"}}}' "$BIG" "$ROOT" )"; do
    what="${probe%%|*}"; req="${probe#*|}"
    n="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$req" | "$BIN" --mcp 2>/dev/null | tail -1 | wc -c | tr -d ' ' )"
    if [ "$n" -lt 2000 ]; then ok "NIT [$what]: a 400 KB $what yields a ${n}-byte frame (echo capped)"
    else                       no "NIT [$what]: a 400 KB $what minted a ${n}-byte response — the echo is uncapped"; fi
done
# the cap must land on a UTF-8 codepoint boundary (a half character would be scrubbed to U+FFFD).
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "$( call grep '{"path":"'"$ROOT"'","pattern":"x","limit":"'"$( python3 -c 'print("é"*200)' )"'"}' )" \
    | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
m = json.load(sys.stdin)["error"]["message"]
print("OK" if "\ufffd" not in m and "\u2026" in m else "GOT:" + repr(m[-40:]))
' >"$TMP/nitutf8.res" 2>&1
[ "$( cat "$TMP/nitutf8.res" )" = "OK" ] \
    && ok "NIT: the trim backs off to a codepoint boundary (no U+FFFD, ellipsis present)" \
    || no "NIT: the cap split a multibyte character: $( cat "$TMP/nitutf8.res" )"
# and a SHORT value's echo is untouched, so every gate asserting an exact echo still holds.
case "$( mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"x","limit":0}' )" )" in
    *"got '0', e.g. limit=40"*) ok "NIT: a short echo is byte-identical to before the cap";;
    *) no "NIT: the cap changed a short echo";;
esac

echo
if [ "$fail" -eq 0 ]; then echo "mcpw3fixcheck: ALL PASS"; else echo "mcpw3fixcheck: FAILURES"; fi
exit "$fail"
