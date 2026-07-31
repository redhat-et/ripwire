#!/usr/bin/env bash
# mcpw2fixcheck.sh — the Wave-2 VERIFIER findings against the round's own new MCP code (N1/N2/N3/N5/N6/N7/
# N8/N11). Sibling of mcptranchecheck.sh, which gates §B6 M1-M15; this file gates the eight defects the
# cross-lane verifier found IN those fixes.
#
# THE LAW, unchanged: the MCP surface dispatches TWICE — the live stdio server (`--mcp`, mcp.h) and the
# `batch` verb's sub-query chain (mcpverbs.h's runBatchSub). Every fix here lands in ONE shared helper
# (mcpjson.h's findRawValue/parseWholeInt, mcpverbs.h's mcpIntArg/mcpStringArg/mcpPageArgs, mcprefusal.h's
# kMcpValueFields + notFoundHintFor), and every item reachable from both arms is probed on BOTH. Three of
# the eight verbs (connect, edit_check, situational_awareness) are not batch-served, so their "other arm" is
# asserted to be exactly that — a clean unknown-sub-verb refusal, not a second dialect of the same answer.
#
# THE ONE ARM THAT MUST NOT RESTATE THE CODE: N1's. kBatchExcludedCount is a FORMULA, and the M14 arm in
# mcptranchecheck.sh passed for three commits because it restated the same formula (including the same
# double-subtraction of `batch`). Here the expectation is ENUMERATED — every advertised verb is actually
# asked through the batch arm and the ones that answer "unknown sub-verb" are counted — so the prose number,
# the C++ constant and reality are pinned to each other by observation, not by arithmetic agreement.
#
# Usage:
#   test/mcpw2fixcheck.sh                                      # uses build/ripwire
#   test/mcpw2fixcheck.sh /path/to/other/ripwire               # positional binary
#   RIPWIRE_BIN=build_prefix/ripwire test/mcpw2fixcheck.sh     # env binary (the RED run)
#
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpw2fixcheck: BIN=$BIN  CORPUS=$ROOT"

# ── the two arms (same helpers mcptranchecheck.sh uses, same contract) ──────────────────────────────────
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

echo
echo "=== N1 — the batch exclusion count is DERIVED and matches ENUMERATED reality ==="
# Not the formula restated: every advertised verb is asked through the live batch arm, and the ones that
# answer "unknown sub-verb" ARE the excluded set. Its size must equal the number the batch stanza prints.
# (kBatchCap is 16, so the sweep runs in chunks — an over-cap batch would silently answer fewer verbs.)
python3 - "$BIN" "$ROOT" "$TMP/tools.json" <<'PY' >"$TMP/n1.res" 2>&1
import json, re, html, subprocess, sys
BIN, ROOT, TOOLS = sys.argv[1], sys.argv[2], sys.argv[3]
def rpc(req):
    inp = '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' + req + "\n"
    out = subprocess.run([BIN, "--mcp"], input=inp, capture_output=True, text=True).stdout.strip().split("\n")
    return json.loads(out[-1])
names = [ t["name"] for t in json.load(open(TOOLS))["result"]["tools"] ]
excluded = []
for i in range(0, len(names), 12):                       # chunk well under kBatchCap=16
    args = {"path": ROOT, "queries": [ {"verb": n} for n in names[i:i+12] ]}
    req  = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":%s}' % json.dumps({"name":"batch","arguments":args})
    t    = rpc(req)["result"]["content"][0]["text"]
    for m in re.finditer(r'<q i="\d+" verb="([^"]*)" ok="0" err="([^"]*)"', t):
        if "unknown sub-verb" in html.unescape(m.group(2)): excluded.append(m.group(1))
stanza = { t["name"]: t for t in json.load(open(TOOLS))["result"]["tools"] }["batch"]["description"]
m = re.search(r"The other (\d+) advertised verbs", stanza)
problems = []
if not m:
    problems.append("the batch stanza states no exclusion count")
elif int(m.group(1)) != len(excluded):
    problems.append("stanza says %s excluded; ENUMERATION finds %d (%s)" % (m.group(1), len(excluded), ",".join(sorted(excluded))))
# and the enumerated set must name `batch` itself — the verb whose double-subtraction caused the undercount.
if "batch" not in excluded: problems.append("`batch` is batchable?! the enumeration probe is broken, not the count")
print("OK(%d)" % len(excluded) if not problems else "; ".join(problems))
PY
case "$( cat "$TMP/n1.res" )" in
    OK*) ok "N1: the stanza's exclusion count equals the ENUMERATED refusing set $( cat "$TMP/n1.res" )";;
    *)   no "N1: $( cat "$TMP/n1.res" )";;
esac

echo
echo "=== N2 — a present-but-invalid limit/offset REFUSES (both arms), absent still defaults ==="
# The five values the CLI refuses loudly and MCP accepted-and-ignored (or truncated). Each refusal must
# name the field, state the domain, ECHO the value as typed, and show something runnable.
for bad in '"limit":0|0' '"limit":-1|-1' '"limit":"abc"|abc' '"limit":3.9|3.9' '"offset":-2|-2'; do
    arg="${bad%%|*}"; got="${bad##*|}"
    field="limit"; case "$arg" in '"offset"'*) field="offset";; esac
    L="$( mcp_text "$( call impact '{"path":"'"$ROOT"'","symbol":"escapeXml",'"$arg"'}' )" )"
    B="$( batch_sub '{"verb":"impact","symbol":"escapeXml",'"$arg"'}' )"
    for pair in "live:$L" "batch:$B"; do
        arm="${pair%%:*}"; body="${pair#*:}"
        case "$body" in
            __ERROR__:"invalid value for field: $field"*"got '$got'"*"e.g. $field="*) ok "N2 [$arm] $arg: refused, domain + got-echo + example";;
            __ERROR__*) no "N2 [$arm] $arg: refuses but not in the shared wording: $body";;
            *)          no "N2 [$arm] $arg: still accepted and ignored";;
        esac
    done
    [ "$L" = "$B" ] || no "N2 $arg: the two arms word it differently — live [$L] vs batch [$B]"
done
# absent stays the default: the un-paged answer must be byte-identical to the CLI's un-paged answer.
IMP_MCP="$( mcp_text "$( call impact '{"path":"'"$ROOT"'","symbol":"escapeXml"}' )" | tr '<' '\n' | grep '^impact ' | head -1 )"
IMP_CLI="$( "$BIN" "$ROOT" --impact=escapeXml 2>/dev/null | tr '<' '\n' | grep '^impact ' | head -1 )"
{ [ -n "$IMP_CLI" ] && [ "$IMP_MCP" = "$IMP_CLI" ]; } \
    && ok "N2: an ABSENT limit/offset still gives the byte-identical un-paged answer (no over-refusal)" \
    || no "N2: the un-paged answer moved — CLI [$IMP_CLI] vs MCP [$IMP_MCP]"
# a VALID window still works on both arms (the refusal must not have eaten the feature M4 shipped).
V_LIVE="$( mcp_text "$( call impact '{"path":"'"$ROOT"'","symbol":"escapeXml","limit":3,"offset":2}' )" | tr '<' '\n' | grep '^impact ' | head -1 )"
V_CLI="$( "$BIN" "$ROOT" --impact=escapeXml --limit=3 --offset=2 2>/dev/null | tr '<' '\n' | grep '^impact ' | head -1 )"
[ -n "$V_CLI" ] && [ "$V_LIVE" = "$V_CLI" ] \
    && ok "N2: a VALID limit/offset still pages byte-identically to the CLI" \
    || no "N2: a valid window regressed — CLI [$V_CLI] vs MCP [$V_LIVE]"

echo
echo "=== N3 — connect radius refuses out-of-band / non-integer / WRAPPING values ==="
# 2^40 is the finding's own probe: it wrapped modulo 2^32 to 0, clamped to 1, and the verb answered a
# 1-hop question while echoing radius="1". Nothing outside 1..12 may reach the core.
for bad in 1099511627776 3.7 0 -5 abc 13; do
    case "$bad" in abc) val='"abc"';; *) val="$bad";; esac
    R="$( mcp_text "$( call connect '{"path":"'"$ROOT"'","symbols":["main","parseArgs"],"radius":'"$val"'}' )" )"
    case "$R" in
        __ERROR__:"invalid value for field: radius"*"1..12"*"got '$bad'"*"e.g. radius="*) ok "N3 [live] radius=$bad: refused with the band + got-echo + example";;
        __ERROR__*) no "N3 [live] radius=$bad: refuses but not in the shared wording: $R";;
        *)          no "N3 [live] radius=$bad: still answered (a DIFFERENT question) — $( printf '%s' "$R" | head -c 120 )";;
    esac
done
# the in-band values must still be honored exactly, and an ABSENT radius must still default to 6.
case "$( mcp_text "$( call connect '{"path":"'"$ROOT"'","symbols":["main","parseArgs"],"radius":12}' )" )" in
    *'radius="12"'*) ok "N3: an in-band radius=12 is honored verbatim (no over-refusal at the boundary)";;
    *)               no "N3: radius=12 is inside the declared band and must be accepted";;
esac
case "$( mcp_text "$( call connect '{"path":"'"$ROOT"'","symbols":["main","parseArgs"]}' )" )" in
    *'radius="6"'*) ok "N3: an ABSENT radius still defaults to 6";;
    *)              no "N3: the absent-radius default moved off 6";;
esac
# tools/list must DECLARE the band it enforces (a refusal naming a range the schema never stated is a trap).
python3 - "$TMP/tools.json" <<'PY' >"$TMP/n3.res" 2>&1
import json, sys
d = { t["name"]: t for t in json.load(open(sys.argv[1]))["result"]["tools"] }
print("OK" if "1..12" in d["connect"]["description"] else "GOT:" + d["connect"]["description"][-160:])
PY
[ "$( cat "$TMP/n3.res" )" = "OK" ] \
    && ok "N3: the connect stanza DECLARES the 1..12 band it refuses outside of" \
    || no "N3: the band is enforced but undeclared: $( cat "$TMP/n3.res" )"
# the OTHER arm: connect is not batch-served, so its second arm is a clean unknown-sub-verb refusal.
case "$( batch_sub '{"verb":"connect","symbols":["main","parseArgs"],"radius":1099511627776}' )" in
    __ERROR__*"unknown sub-verb 'connect'"*) ok "N3 [batch]: connect is not batch-served — one radius seam, and it is the shared one";;
    *) no "N3 [batch]: the batch arm answered connect — there is a SECOND radius seam this gate does not cover";;
esac

echo
echo "=== N5 — edit_check's not-found joins the shared M8 dialect ==="
E5="$( mcp_text "$( call edit_check '{"path":"'"$ROOT"'","symbol":"parsArgs"}' )" )"
case "$E5" in
    __ERROR__:"symbol not found: 'parsArgs'"*"did you mean 'parseArgs'"*" — "*) ok "N5 [live]: echoes the spelling, suggests the near-miss, and carries the verb's guidance clause";;
    __ERROR__*"did you mean"*) no "N5 [live]: suggests but drops the guidance clause: $E5";;
    *)                         no "N5 [live]: still the pre-fix dialect: $E5";;
esac
case "$( batch_sub '{"verb":"edit_check","symbol":"parsArgs"}' )" in
    __ERROR__*"unknown sub-verb 'edit_check'"*) ok "N5 [batch]: edit_check is not batch-served — one not-found seam, and it is the shared one";;
    *) no "N5 [batch]: the batch arm answered edit_check — a SECOND not-found seam exists";;
esac

echo
echo "=== N6 — connect {} and batch {} speak the M7 verb+field TABLE, not bespoke sentences ==="
C6="$( mcp_text "$( call connect '{"path":"'"$ROOT"'"}' )" )"
case "$C6" in
    __ERROR__:"missing required field: symbols"*"2..16 symbol names"*"e.g. symbols="*) ok "N6: connect {} → the table's sentence, specifics kept (2..16 names)";;
    *) no "N6: connect {} still bespoke: $C6";;
esac
# W3FIX M8 split this arm's two probes apart, deliberately, and the assertion follows. N6 asserted that an
# ABSENT `queries` and a `queries:[]` produce the SAME "missing required field" sentence, on the reasoning that
# both need the same fix. M8's finding is that saying "missing" to a caller who DID send the field is the
# absent-vs-wrong-shape collapse — so `queries:[]` is now the bad-VALUE sentence, which carries the identical
# needs-text and example PLUS an echo of what was sent. Each probe now names its own prefix; what N6 actually
# gates — the table's specifics rather than a hand-written parenthetical — is still asserted on both.
for probe in '{"path":"'"$ROOT"'"}|missing required field: queries' \
             '{"path":"'"$ROOT"'","queries":[]}|invalid value for field: queries'; do
    args="${probe%%|*}"; prefix="${probe#*|}"
    B6="$( mcp_text "$( call batch "$args" )" )"
    case "$B6" in
        __ERROR__:"$prefix"*"{verb, ...args} sub-query objects"*"e.g. queries="*) ok "N6: batch $args → the table's sentence, specifics kept ({verb, ...} objects)";;
        *) no "N6: batch $args still bespoke: $B6";;
    esac
done

echo
echo "=== N7 — the not-found GUIDANCE clause is served in full to BOTH arms ==="
# The live arm carried a trailing clause on three verbs and the batch arm truncated it. The assertion is
# EQUALITY of the two arms' whole sentence, plus each verb's own distinctive clause actually being there.
for pair in 'find_symbol|add scope to disambiguate' \
            'find_referencing_symbols|add scope to disambiguate' \
            'mentions|named in doc backticks' \
            'owners|no git history'; do
    v="${pair%%|*}"; clause="${pair#*|}"
    L="$( mcp_text "$( call "$v" '{"path":"'"$ROOT"'","symbol":"parsArgs"}' )" )"
    B="$( batch_sub '{"verb":"'"$v"'","symbol":"parsArgs"}' )"
    case "$L" in *"$clause"*) ;; *) no "N7 [live/$v]: the live arm itself lost the clause \"$clause\" — the gate's anchor moved: $L"; continue;; esac
    [ "$L" = "$B" ] \
        && ok "N7 [$v]: both arms serve the IDENTICAL full sentence (clause \"$clause\" intact)" \
        || no "N7 [$v]: the batch arm truncates — live [$L] vs batch [$B]"
done

echo
echo "=== N8 — MCP grep pages (both arms), and a page-walk reproduces the CLI exactly ==="
python3 - "$TMP/tools.json" <<'PY' >"$TMP/n8decl" 2>&1
import json, sys
p = { t["name"]: t for t in json.load(open(sys.argv[1]))["result"]["tools"] }["grep"]["inputSchema"]["properties"]
missing = [ k for k in ("limit","offset") if k not in p ]
print("OK" if not missing else "grep declares no " + ",".join(missing))
PY
[ "$( cat "$TMP/n8decl" )" = "OK" ] \
    && ok "N8: the grep stanza DECLARES limit/offset" \
    || no "N8: $( cat "$TMP/n8decl" )"
G_LIVE="$( mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"pageDisclosure","limit":3,"offset":1}' )" )"
G_BAT="$( batch_sub '{"verb":"grep","pattern":"pageDisclosure","limit":3,"offset":1}' )"
[ "$G_LIVE" = "$G_BAT" ] \
    && ok "N8: the paged grep payload is byte-identical on BOTH arms" \
    || no "N8: the arms page differently"
python3 - "$BIN" "$ROOT" <<'PY' >"$TMP/n8.res" 2>&1
import json, re, subprocess, sys
BIN, ROOT = sys.argv[1], sys.argv[2]
def mcp(args):
    req = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":%s}' % json.dumps({"name":"grep","arguments":args})
    inp = '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' + req + "\n"
    out = subprocess.run([BIN, "--mcp"], input=inp, capture_output=True, text=True).stdout.strip().split("\n")[-1]
    return json.loads(json.loads(out)["result"]["content"][0]["text"])
paged  = mcp({"path": ROOT, "pattern": "pageDisclosure", "limit": 3, "offset": 1})
full   = mcp({"path": ROOT, "pattern": "pageDisclosure"})
problems = []
for k in ("has_more", "next_offset", "offset", "limit", "total", "shown", "capped"):
    if k not in paged: problems.append("the paged answer has no " + k)
if paged.get("shown") != 3: problems.append("limit=3 served %s rows" % paged.get("shown"))
# the CLI's own page-walk over the SAME window, concatenated, must equal the MCP's — and both must equal
# the CLI's full listing. M12's files=/order facts must survive paging unchanged.
walk, off = [], 0
while True:
    j = mcp({"path": ROOT, "pattern": "pageDisclosure", "limit": 7, "offset": off})
    walk += [ (h["file"], h["line"]) for h in j["hits"] ]
    if j["files"] != full["files"]:                 problems.append("files= moved between pages (%s vs %s)" % (j["files"], full["files"]))
    if j.get("order") != full.get("order"):         problems.append("the order= sentence moved between pages")
    if not j.get("has_more"): break
    off = j["next_offset"]
cli  = subprocess.run([BIN, ROOT, "--grep=pageDisclosure", "--limit=100000"], capture_output=True, text=True).stdout
rows = [ (f, int(l)) for f, l in re.findall(r'<hit p="([^"]+):(\d+)"', cli) ]
if not rows:        problems.append("the CLI probe produced no <hit> rows (probe broken, not the tool)")
elif walk != rows:  problems.append("the MCP page-walk (%d rows) != the CLI listing (%d rows)" % (len(walk), len(rows)))
if full["total"] != len(rows): problems.append("total=%s but the CLI lists %d hits" % (full["total"], len(rows)))
print("OK" if not problems else "; ".join(problems))
PY
[ "$( cat "$TMP/n8.res" )" = "OK" ] \
    && ok "N8: the page-walk concatenates to the CLI's listing; files=/order/total stay correct under paging" \
    || no "N8: $( cat "$TMP/n8.res" )"
# an UN-paged grep must stay byte-identical (this verb's JSON is read by three other gates).
mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"pageDisclosure"}' )" \
    | grep -q '"files":[0-9]*,"total":[0-9]*,"shown":[0-9]*,"capped":' \
    && ok "N8: the UN-paged grep JSON keeps its historic key order (files,total,shown,capped)" \
    || no "N8: the un-paged grep JSON shape moved — other gates read this payload"
# and the paging knobs inherit N2's validation.
case "$( mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"x","limit":0}' )" )" in
    __ERROR__:"invalid value for field: limit"*) ok "N8: grep's new knobs inherit N2's validation (limit=0 refuses)";;
    *) no "N8: grep accepts limit=0 — the new knobs bypassed the shared reader";;
esac

echo
echo '=== N11 — a non-STRING situational_awareness files= refuses, never falls back to git diff ==='
S11="$( mcp_text "$( call situational_awareness '{"path":"'"$ROOT"'","files":["src/pageview.h","src/serialize.h"]}' )" )"
case "$S11" in
    __ERROR__:"invalid value for field: files"*"not an array"*"got '["*"e.g. files="*) ok "N11: an ARRAY files= is refused, naming the expected type + an example";;
    __ERROR__*) no "N11: refuses but not in the shared wording: $S11";;
    *'"changed_files"'*) no "N11: still silently ignored — the verb answered about something else entirely";;
    *) no "N11: unexpected: $S11";;
esac
# the two shapes that must NOT have been caught in the blast: a real string, and an absent files=.
case "$( mcp_text "$( call situational_awareness '{"path":"'"$ROOT"'","files":"src/pageview.h,src/serialize.h"}' )" )" in
    *'"changed_files"'*'pageview.h'*) ok "N11: a STRING files= still answers about exactly those files";;
    *) no "N11: over-refusal — the documented string form must still work";;
esac
case "$( mcp_text "$( call situational_awareness '{"path":"'"$ROOT"'"}' )" )" in
    __ERROR__*) no "N11: over-refusal — an ABSENT files= must still default to the working-tree git diff";;
    *)          ok "N11: an ABSENT files= still defaults to the working-tree git diff";;
esac
case "$( batch_sub '{"verb":"situational_awareness","files":["a"]}' )" in
    __ERROR__*"unknown sub-verb 'situational_awareness'"*) ok "N11 [batch]: situational_awareness is not batch-served — one files= seam, and it is the shared one";;
    *) no "N11 [batch]: the batch arm answered situational_awareness — a SECOND files= seam exists";;
esac

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "SOME CHECKS FAILED"; exit 1
