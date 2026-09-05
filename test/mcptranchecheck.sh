#!/usr/bin/env bash
# mcptranchecheck.sh — §B6 MCP-surface tranche, one assert per item.
#
# THE LAW THIS GATE ENCODES: the MCP surface dispatches TWICE — the live stdio server (`--mcp`, mcp.h) and
# the `batch` verb's sub-query chain (mcpverbs.h) — and every §B6 finding was a CALL-SITE argument or a
# legend clause, never an algorithm, which is exactly the class a CLI-side gate cannot see. So every item
# that is reachable from both arms is probed on BOTH: `mcp_call` pipes JSON-RPC into the live server, and
# `batch_sub` asks the same question through the batch verb. An item verified on only one arm is presumed
# broken (V2-1's lesson, twice confirmed: the qualified-spelling guard landed on one arm and drifted).
#
# Items covered here: M1 (analyze completeness gauges), M2 (exemplar via selectExemplar), M3 (the CLI
# purity fixpoint), M4 (limit/offset honored), M5 (quality_delta key parity — the shape half; the full
# key-set diff lives in mcpclidiffcheck.sh), M6 (uses bare-name refusal), M7 (one empty-value wording),
# M8 (echo + did-you-mean on not-found), M9 (the unknown-verb split), M10 (first-screen stanza), M11
# (situ run= + dependent counts), M12 (owners/grep legend ports), M13 (one exemplar wording), M14 (derived
# batch exclusion count + aliases), M15 (memory_recall top_k).
#
# Usage:
#   test/mcptranchecheck.sh                                    # uses build/ripwire
#   test/mcptranchecheck.sh /path/to/other/ripwire             # positional binary
#   RIPWIRE_BIN=build_base/ripwire test/mcptranchecheck.sh     # env binary (the RED run)
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

echo "mcptranchecheck: BIN=$BIN  CORPUS=$ROOT"

# ── the two arms ────────────────────────────────────────────────────────────────────────────────────────
# LIVE arm: initialize + one tools/call, piped into the stdio server; prints the verb's text payload, or
# "__ERROR__:<message>" for a JSON-RPC error. This is the arm a real MCP client speaks to.
mcp_text() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERROR__:" + r["error"].get("message",""))
else:            print(r["result"]["content"][0]["text"])
'
}

# BATCH arm: the same question as a single-element batch, unwrapped back to the sub-answer (or its err=).
# Byte-identical to the standalone verb by contract, which is what makes a divergence here meaningful.
batch_sub() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":"'"$ROOT"'","legend":"full","queries":['"$1"']}}}' \
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

# M1 RE-PIN (terminality round A, 2026-09-05): the MCP legend DEFAULT moved to compact, so every call this
# gate makes to an XML verb asks for `legend:"full"` and the comparison this file makes stays full <-> full.
# That is deliberate and is not gate inertia: what this file asserts is DATA parity (attribute sets, values,
# windows, legend clauses) between the CLI and the server, and both operands have to be the same dialect for
# the comparison to mean anything. compact <-> compact is pinned per verb, on the default path, by
# compactlegendcheck (N) — default == compact, legend:"full" restorable, payload byte-identical.
# The family list is the seventeen verbs that DECLARE `legend` (src/mcprefusal.h kMcpVerbFields); passing it
# to a verb that does not declare it is refused as an unknown field, so the injection is gated on membership.
call() {
    _cargs="$2"
    case " analyze lego owners batch exemplar impact uses path_between connect explore from_trace edit_check whereis stray_content flags doc_drift slice " in
        *" $1 "*) _cargs="${_cargs%\}},\"legend\":\"full\"}" ;;
    esac
    printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$_cargs"
}

echo
echo "=== M1 — analyze reports the call-graph COMPLETENESS gauges (both arms) ==="
# Truth check, not a magic number: this tree's resolver DOES guess (the CLI map says so), so a header
# claiming ambiguous=0 unresolved=0 is a false zero, not a clean repo. Assert both are non-zero on both
# arms, and that per-row amb= markers appear — the legend advertises them and they vanished with the gauge.
mcp_text "$( call analyze '{"path":"'"$ROOT"'"}' )" >"$TMP/m1.live"
batch_sub '{"verb":"analyze"}'                       >"$TMP/m1.batch"
for arm in live batch; do
    python3 - "$TMP/m1.$arm" "$arm" <<'PY' || no "M1 [$arm]: analyze header assertions could not run"
import re, sys
t = open(sys.argv[1]).read(); arm = sys.argv[2]
m = re.search(r"ambiguous=(\d+) unresolved=(\d+)", t)
if not m: print("NOGAUGE"); raise SystemExit
amb, unres, rows = int(m.group(1)), int(m.group(2)), len(re.findall(r' amb="\d+"', t))
print("OK" if amb > 0 and unres > 0 and rows > 0 else "FALSEZERO amb=%d unresolved=%d amb_rows=%d" % (amb, unres, rows))
PY
done >"$TMP/m1.res" 2>&1
grep -c '^OK$' "$TMP/m1.res" >"$TMP/m1.n" 2>/dev/null || true
[ "$( cat "$TMP/m1.n" )" = "2" ] \
    && ok "M1: analyze reports non-zero ambiguous=/unresolved= + per-row amb= on BOTH arms" \
    || no "M1: analyze still emits the false zero on at least one arm: $( tr '\n' ' ' <"$TMP/m1.res" )"

echo
echo "=== M10 — the files=/symbols=/shown=/order= stanza is on the FIRST SCREEN (both arms) ==="
for arm in live batch; do
    python3 - "$TMP/m1.$arm" <<'PY'
import sys
t = open(sys.argv[1]).read()
i, j = t.find("files="), t.find("<r")
print("OK" if 0 <= i < j >= 0 else "TRAILING files=%d <r>=%d" % (i, j))
PY
done >"$TMP/m10.res" 2>&1
[ "$( grep -c '^OK$' "$TMP/m10.res" )" = "2" ] \
    && ok "M10: the denominator + order= stanza precedes <r> on BOTH arms" \
    || no "M10: the stanza is still a trailing comment on at least one arm: $( tr '\n' ' ' <"$TMP/m10.res" )"

# and the tools/list claim about ORDER must state both halves (ranked membership, stable emitted order).
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 >"$TMP/tools.json"
python3 - "$TMP/tools.json" <<'PY' >"$TMP/m10b" 2>&1
import sys, json
d = { t["name"]: t for t in json.load(open(sys.argv[1]))["result"]["tools"] }
desc = d["analyze"]["description"]
print("OK" if ("MEMBERSHIP" in desc and "order=" in desc) else "GOT:" + desc[:160])
PY
[ "$( cat "$TMP/m10b" )" = "OK" ] \
    && ok "M10: tools/list separates ranked MEMBERSHIP from the emitted order" \
    || no "M10: the analyze order claim is still one undivided 'ranked by PageRank': $( cat "$TMP/m10b" )"

echo
echo "=== M2/M13 — exemplar goes through selectExemplar; MCP == CLI (both arms) ==="
# The probe the finding used: a nonsense task. The CLI flags low_confidence and falls back to fn; the
# hand-rolled MCP clone returned a confident pick of a different kind. Byte-compare the <exemplar> tag.
CLI_EX="$( "$BIN" "$ROOT" --exemplar="zzz qqq wibble" 2>/dev/null | tr '<' '\n' | grep '^exemplar ' | head -1 )"
LIVE_EX="$( mcp_text "$( call exemplar '{"path":"'"$ROOT"'","kind":"zzz qqq wibble"}' )" | tr '<' '\n' | grep '^exemplar ' | head -1 )"
BAT_EX="$( batch_sub '{"verb":"exemplar","task":"zzz qqq wibble"}' | tr '<' '\n' | grep '^exemplar ' | head -1 )"
[ -n "$CLI_EX" ] || no "M2: the CLI --exemplar probe produced no <exemplar> tag (probe broken, not the tool)"
[ "$LIVE_EX" = "$CLI_EX" ] \
    && ok "M2 [live]: the MCP <exemplar> tag is byte-identical to the CLI twin" \
    || no "M2 [live]: diverges — CLI [$CLI_EX] vs MCP [$LIVE_EX]"
[ "$BAT_EX" = "$CLI_EX" ] \
    && ok "M2 [batch]: the batched <exemplar> tag is byte-identical to the CLI twin" \
    || no "M2 [batch]: diverges — CLI [$CLI_EX] vs batch [$BAT_EX]"
case "$LIVE_EX" in *'low_confidence="1"'*) ok "M2: low_confidence= is REACHABLE on the MCP arm (it was structurally impossible)";;
                   *) no "M2: low_confidence= still unreachable on a nonsense task: $LIVE_EX";; esac
# M13: one wording, three surfaces. The selection rule is exemplar.h's constant, so a distinctive phrase
# from it must appear in the CLI legend, the MCP legend AND the tools/list description.
RULE='chosen by ROLE, NEVER by text similarity'
"$BIN" "$ROOT" --exemplar=fn 2>/dev/null | grep -qF "$RULE" && m13cli=1 || m13cli=0
mcp_text "$( call exemplar '{"path":"'"$ROOT"'","kind":"fn"}' )" | grep -qF "$RULE" && m13mcp=1 || m13mcp=0
grep -qF "$RULE" "$TMP/tools.json" && m13list=1 || m13list=0
[ "$m13cli$m13mcp$m13list" = "111" ] \
    && ok "M13: the exemplar selection rule is ONE wording across CLI legend / MCP legend / tools/list" \
    || no "M13: the rule still forks (cli=$m13cli mcp=$m13mcp tools/list=$m13list)"

echo
echo "=== M3 — the CLI purity fixpoint reaches --from-trace and --pack-task ==="
# runMcp does I/O in its own body, so the fixpoint demotes it. --for already omitted pure=; the two
# signature emitters that grew their own call sites without joining the gate claimed pure="1".
printf 'Traceback (most recent call last):\n  File "src/mcp.h", line 795, in runMcp\n    x = 1\n' >"$TMP/trace.txt"
purecount() { "$BIN" "$ROOT" "$1" 2>/dev/null | tr '<' '\n' | grep 'n="runMcp"' | grep -c 'pure="1"' || true; }
FT="$( purecount "--from-trace=$TMP/trace.txt" )"
PT="$( purecount "--pack-task=the mcp stdio server loop runMcp" )"
FOR="$( purecount "--for=the mcp stdio server loop runMcp" )"
[ "$FOR" = "0" ] || no "M3: the CONTROL is broken — --for should never claim pure= on runMcp (got $FOR)"
{ [ "$FT" = "0" ] && [ "$PT" = "0" ]; } \
    && ok "M3: --from-trace and --pack-task no longer claim pure=\"1\" on an I/O-performing symbol" \
    || no "M3: the fixpoint still misses a verb (from-trace=$FT pack-task=$PT, --for control=$FOR)"

echo
echo "=== M4 — limit/offset are HONORED (both arms), byte-identically to the CLI ==="
IMP_LIVE="$( mcp_text "$( call impact '{"path":"'"$ROOT"'","symbol":"escapeXml","limit":3,"offset":2}' )" | tr '<' '\n' | grep '^impact ' | head -1 )"
IMP_BAT="$( batch_sub '{"verb":"impact","symbol":"escapeXml","limit":3,"offset":2}'                        | tr '<' '\n' | grep '^impact ' | head -1 )"
IMP_CLI="$( "$BIN" "$ROOT" --impact=escapeXml --limit=3 --offset=2 2>/dev/null | tr '<' '\n' | grep '^impact ' | head -1 )"
[ -n "$IMP_CLI" ] || no "M4: the CLI --impact probe produced no <impact> tag (probe broken)"
[ "$IMP_LIVE" = "$IMP_CLI" ] \
    && ok "M4 [live]: paged <impact> is byte-identical to --impact --limit=3 --offset=2" \
    || no "M4 [live]: CLI [$IMP_CLI] vs MCP [$IMP_LIVE]"
[ "$IMP_BAT" = "$IMP_CLI" ] \
    && ok "M4 [batch]: paged <impact> is byte-identical to the CLI page" \
    || no "M4 [batch]: CLI [$IMP_CLI] vs batch [$IMP_BAT]"
WH="$( mcp_text "$( call whereis '{"path":"'"$ROOT"'","symbol":"runMcp","limit":2}' )" | tr '<' '\n' | grep '^whereis ' | head -1 )"
case "$WH" in *'shown="2"'*'has_more="1"'*'next_offset="2"'*) ok "M4 [live]: whereis honors limit= and discloses has_more/next_offset";;
              *) no "M4 [live]: whereis still ignores limit= — $WH";; esac

echo
echo "=== M5 — quality_delta speaks the CLI's key vocabulary ==="
mcp_text "$( call quality_delta '{"path":"'"$ROOT"'"}' )" >"$TMP/qd.mcp"
python3 - "$TMP/qd.mcp" <<'PY' >"$TMP/qd.res" 2>&1
import sys, json
j = json.load(open(sys.argv[1]))
problems = []
if not isinstance(j.get("regressions"), int): problems.append("regressions is not an int count")
if not isinstance(j.get("r"), list):          problems.append("no `r` array")
for k in ("minor", "at"):
    if k not in j: problems.append("missing " + k)
if "regressions_count" in j: problems.append("regressions_count survived (two names for one number)")
print("OK" if not problems else "; ".join(problems))
PY
[ "$( cat "$TMP/qd.res" )" = "OK" ] \
    && ok "M5: regressions is an INT, the array is r, minor/at present, regressions_count gone" \
    || no "M5: $( cat "$TMP/qd.res" )"

echo
echo "=== M6 — uses on an unresolvable BARE name refuses instead of claiming external=1 (both arms) ==="
U_LIVE="$( mcp_text "$( call uses '{"path":"'"$ROOT"'","symbol":"parsArgs"}' )" )"
U_BAT="$( batch_sub '{"verb":"uses","symbol":"parsArgs"}' )"
for pair in "live:$U_LIVE" "batch:$U_BAT"; do
    arm="${pair%%:*}"; body="${pair#*:}"
    case "$body" in
        __ERROR__*"parsArgs"*"did you mean"*) ok "M6 [$arm]: refuses the typo, echoes it, and suggests the near-miss";;
        __ERROR__*)                           no "M6 [$arm]: refuses but without echo/suggestion: $body";;
        *)                                    no "M6 [$arm]: still answers a typo as an external symbol";;
    esac
done
# the OTHER half of the predicate: a real external name (defs empty, use-sites present) must still ANSWER.
U_EXT="$( mcp_text "$( call uses '{"path":"'"$ROOT"'","symbol":"snprintf"}' )" )"
case "$U_EXT" in __ERROR__*) no "M6: over-refuses — a genuine external name with use-sites must stay a valid answer";;
                 *'<uses '*) ok "M6: a genuine external name with real use-sites still answers (no over-refusal)";;
                 *)          no "M6: unexpected uses payload for an external name";; esac

echo
echo "=== M7 — ONE empty-value wording, with the CLI's example clause, on both arms ==="
E_LIVE="$( mcp_text "$( call grep '{"path":"'"$ROOT"'"}' )" )"
E_BAT="$( batch_sub '{"verb":"grep"}' )"
for pair in "live:$E_LIVE" "batch:$E_BAT"; do
    arm="${pair%%:*}"; body="${pair#*:}"
    case "$body" in
        __ERROR__:"missing required field: pattern"*"e.g. pattern="*) ok "M7 [$arm]: same prefix, and it names what to type";;
        *) no "M7 [$arm]: wording still diverges: $body";;
    esac
done
[ "$E_LIVE" = "$E_BAT" ] \
    && ok "M7: the two arms emit the IDENTICAL empty-value refusal (one table, one wording)" \
    || no "M7: the arms still word it differently — live [$E_LIVE] vs batch [$E_BAT]"

echo
echo "=== M8 — not-found refusals echo the spelling AND suggest, on both arms ==="
for v in find_symbol find_referencing_symbols impact mentions; do
    got="$( mcp_text "$( call "$v" '{"path":"'"$ROOT"'","symbol":"parsArgs"}' )" )"
    case "$got" in
        __ERROR__*"'parsArgs'"*"did you mean 'parseArgs'"*) ok "M8 [live/$v]: echoes 'parsArgs' and suggests 'parseArgs'";;
        *) no "M8 [live/$v]: $got";;
    esac
done
B8="$( batch_sub '{"verb":"find_symbol","symbol":"parsArgs"}' )"
case "$B8" in __ERROR__*"'parsArgs'"*"did you mean"*) ok "M8 [batch]: the batch arm echoes and suggests too";;
              *) no "M8 [batch]: $B8";; esac
# cochange takes a FILE, so its suggestion must come from the path pool, not the symbol pool.
C8="$( mcp_text "$( call cochange '{"path":"'"$ROOT"'","file":"src/mian.cpp"}' )" )"
case "$C8" in __ERROR__*"src/mian.cpp"*"did you mean"*main.cpp*) ok "M8: cochange suggests a real FILE, not a symbol";;
              *) no "M8: cochange file suggestion wrong: $C8";; esac
# path_between names WHICH endpoint failed (it takes two).
P8="$( mcp_text "$( call path_between '{"path":"'"$ROOT"'","from":"parsArgs","to":"ingest"}' )" )"
case "$P8" in __ERROR__*"from="*"parsArgs"*) ok "M8: path_between names the failing endpoint";;
              *) no "M8: path_between refusal does not say which endpoint failed: $P8";; esac

echo
echo "=== M9 — unknown verb and incomplete args are DIFFERENT refusals ==="
UNK="$( mcp_text "$( call find_symbl '{"path":"'"$ROOT"'"}' )" )"
INC="$( mcp_text "$( call find_symbol '{"path":"'"$ROOT"'"}' )" )"
case "$UNK" in __ERROR__:"unknown tool: 'find_symbl'"*"did you mean 'find_symbol'"*) ok "M9: an unknown tool is named, with a near-miss from the registry";;
               *) no "M9: unknown-tool refusal still generic: $UNK";; esac
case "$INC" in __ERROR__:"missing required field: symbol"*) ok "M9: a KNOWN verb with incomplete args gets the field message, not the tool message";;
               *) no "M9: incomplete-args refusal wrong: $INC";; esac
[ "$UNK" != "$INC" ] \
    && ok "M9: the two failures no longer share one sentence" \
    || no "M9: both failures still produce the same message"
BUNK="$( batch_sub '{"verb":"grepp","pattern":"x"}' )"
case "$BUNK" in __ERROR__*"grepp"*"did you mean 'grep'"*) ok "M9 [batch]: unknown sub-verb names it and suggests";;
                *) no "M9 [batch]: $BUNK";; esac

echo
echo "=== M11 — situational_awareness carries run= hints and dependent-symbol counts ==="
mcp_text "$( call situational_awareness '{"path":"'"$ROOT"'","files":"src/pageview.h,src/serialize.h"}' )" >"$TMP/situ.json"
python3 - "$TMP/situ.json" <<'PY' >"$TMP/situ.res" 2>&1
import sys, json
j = json.load(open(sys.argv[1]))
br, tests = j.get("blast_radius", []), j.get("tests_to_run", [])
problems = []
if not br:    problems.append("probe produced an EMPTY blast radius — the fixture, not the tool")
if not tests: problems.append("probe produced NO tests_to_run — the fixture, not the tool")
if br and any("dependent_symbols" not in r for r in br): problems.append("a blast_radius row has no dependent_symbols")
if br and all(r.get("dependent_symbols", 0) == 0 for r in br): problems.append("every dependent_symbols is 0")
if tests and not any("run" in r for r in tests): problems.append("no tests_to_run row carries a run= hint")
print("OK" if not problems else "; ".join(problems))
PY
[ "$( cat "$TMP/situ.res" )" = "OK" ] \
    && ok "M11: blast_radius rows carry dependent_symbols and tests_to_run carries run=" \
    || no "M11: $( cat "$TMP/situ.res" )"

echo
echo "=== M12 — the CLI-only legend disclosures reached the MCP payloads ==="
mcp_text "$( call owners '{"path":"'"$ROOT"'"}' )" | grep -q "two different things by DEPTH" \
    && ok "M12: owners carries the files=-depth-collision clause" \
    || no "M12: the owners depth collision is still shipped undefused on the MCP arm"
mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"pageDisclosure"}' )" >"$TMP/grep.json"
GREP_CLI_FILES="$( "$BIN" "$ROOT" --grep=pageDisclosure 2>/dev/null | tr '<' '\n' | grep '^grep ' | head -1 \
                   | sed -n 's/.*files="\([0-9]*\)".*/\1/p' )"
python3 - "$TMP/grep.json" "$GREP_CLI_FILES" <<'PY' >"$TMP/grep.res" 2>&1
import sys, json
j = json.load(open(sys.argv[1])); want = sys.argv[2]
problems = []
if "order" not in j:                         problems.append("no ORDER sentence")
if "files" not in j:                         problems.append("no files= denominator")
elif not want:                               problems.append("the CLI probe yielded no files= to compare against")
elif str(j["files"]) != want:                problems.append("files=%s but the CLI says %s" % (j["files"], want))
print("OK" if not problems else "; ".join(problems))
PY
[ "$( cat "$TMP/grep.res" )" = "OK" ] \
    && ok "M12: grep JSON carries the ORDER sentence and a files= that MATCHES the CLI's" \
    || no "M12: $( cat "$TMP/grep.res" )"

echo
echo "=== M14/M15 — batch's exclusion count is derived; memory_recall has a budget knob ==="
python3 - "$TMP/tools.json" <<'PY' >"$TMP/m14.res" 2>&1
import sys, json, re
d = { t["name"]: t for t in json.load(open(sys.argv[1]))["result"]["tools"] }
b = d["batch"]["description"]
# P17 (capture-audit 2026-09-04): slice and edit_check joined the served set — the two READ verbs an agent
# most wants in the same turn as callers/uses. Re-pinned to the NEW served set, not loosened.
served = { "for","grep","find_symbol","find_referencing_symbols","impact","uses","mentions",
           "analyze","lego","owners","cochange","path_between","exemplar","fetch_body",
           "slice","edit_check" }
# verifier N1: this line used to carry the SAME `- 1` the shipped formula did ("minus batch itself"), which
# double-subtracts `batch` — it is advertised and is NOT in `served`, so the first subtraction already
# excluded it. A gate that restates the formula cannot catch the formula, so this arm passed on 15 while 16
# verbs actually refuse. The number is now derived here without the phantom term, and the ENUMERATED arm
# that asks the live batch server which verbs refuse lives in test/mcpw2fixcheck.sh.
truth = len(d) - len(served)              # advertised, minus what batch serves (batch is not in `served`)
m = re.search(r"The other (\d+) advertised verbs", b)
problems = []
if not m:                       problems.append("batch still states no exclusion count")
elif int(m.group(1)) != truth:  problems.append("says %s excluded, tools/list arithmetic says %d" % (m.group(1), truth))
if "callers=" not in b or "callees=" not in b: problems.append("the two batch aliases are still undocumented")
if "top_k" not in d["memory_recall"]["inputSchema"]["properties"]: problems.append("memory_recall declares no top_k")
print("OK" if not problems else "; ".join(problems))
PY
[ "$( cat "$TMP/m14.res" )" = "OK" ] \
    && ok "M14/M15: the exclusion count agrees with tools/list arithmetic; aliases documented; top_k declared" \
    || no "M14/M15: $( cat "$TMP/m14.res" )"
# and top_k must actually SHAPE the answer, not just be declared (the accept-and-ignore class).
# This arm measures top_k DOC-COUNT shaping, not the body-budget policy: pin an explicit high
# budget_tokens so memory_recall's default 8K-token ceiling (recallbudgetcheck.sh owns that contract)
# cannot cut the emission below the requested doc count on a large self-scan corpus.
R8="$( mcp_text "$( call memory_recall '{"path":"'"$ROOT"'","task":"mcp server refusal wording","top_k":2,"budget_tokens":1000000}' )" | head -c 400 )"
case "$R8" in *'shown=2'*) ok "M15: top_k=2 actually shapes the recall (shown=2, not the hardcoded 8)";;
              *)           no "M15: top_k is declared but ignored — $( printf '%s' "$R8" | head -c 200 )";; esac

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "SOME CHECKS FAILED"; exit 1
