#!/usr/bin/env bash
# jsoncheck.sh — gate for L2 (--json output mode).
#
# --json mirrors the XML content, machine-parseable, for the CI/scripting core verbs ONLY: the default
# map, --for, --pack-task, --callers/--callees, --impact, --quality-delta, --test-gate. Every other verb
# must refuse loudly (stderr + exit 1) rather than silently falling back to XML.
#
# This gate:
#   (1) each supported verb's --json output parses as JSON (python3 -m json.tool)
#   (2) spot-checks key PARITY with the XML sibling for 3 attrs per verb (same value, same name)
#   (3) an unsupported verb refuses loudly (stderr names the flag) + exit 1 — never silent XML fallback
#   (4) determinism: 2 runs of --json are byte-identical (the det-gate contract applies to JSON too)
#   (5) G5: --json is additive — plain XML output (no --json) is untouched (spot-checked here, not
#       re-litigating the full det-gate golden which regression.sh already runs)
#   (10) NO DUPLICATE KEYS (verify-wave1 R2): every JSON object any surface emits spells each key once —
#       the CLI --json verbs (#1-#7 and the #8b universe), every MCP tools/call payload and envelope over
#       every tools/list verb, and the CLI --batch CDATA payloads. RFC 8259 names SHOULD be unique; Python
#       and Go keep the last value, strict parsers error. MCP grep on a cut default window spelled
#       "total" twice (its own row count plus M2's paging quintet) on e3b52d3 — this arm is RED there.
#
# A self-contained tmp git repo fixture (not test/fixture — that one is shared by other goldens and isn't
# its own git repo) gives --quality-delta/--test-gate a real, controlled HEAD + working-tree diff so this
# gate never drifts as the LIVE ripwire repo's own history changes.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/jsoncheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
# NOTE: ok/no print to STDERR (not stdout) — several checks below capture a verb's raw --json output via
# `x="$( parses ... )"` and ok/no are called from inside that same command substitution (parses() reports
# AND returns the payload); stdout must stay reserved for the payload or the PASS/FAIL lines corrupt it.
ok(){ printf '  PASS  %s\n' "$*" >&2; }
no(){ printf '  FAIL  %s\n' "$*" >&2; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found — required to validate JSON"; exit 2; }
echo "jsoncheck: BIN=$BIN"

TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/src" "$REPO/test"

cat > "$REPO/src/calc.h" <<'EOF'
#pragma once
int add( int a, int b );
int sub( int a, int b );
EOF
cat > "$REPO/src/calc.cpp" <<'EOF'
#include "calc.h"
int add( int a, int b ) { return a + b; }
int sub( int a, int b ) { return a - b; }
EOF
cat > "$REPO/src/main.cpp" <<'EOF'
#include "calc.h"
int main() { return add( sub( 4, 1 ), 2 ); }
EOF
cat > "$REPO/test/calc_test.cpp" <<'EOF'
#include "../src/calc.h"
int run_tests() { return add( 1, 1 ) == 2 ? 0 : 1; }
EOF

( cd "$REPO" \
  && git init -q \
  && git config user.email "t@example.com" && git config user.name "t" \
  && git add -A && git commit -q -m "initial" )

# #10 — nodupes FILE: exit 0 when every object in the JSON text spells each key once; prints the first
# duplicate otherwise. json.loads with an object_pairs_hook sees every pair BEFORE dict() collapses them —
# `python3 -m json.tool` alone keeps the last value and would call a duplicate-keyed payload valid.
nodupes(){
    python3 - "$1" <<'PY'
import json, sys
text = open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read()
def hook( pairs ):
    seen = set()
    for k, _ in pairs:
        if k in seen:
            raise ValueError( "duplicate key %r" % k )
        seen.add( k )
    return dict( pairs )
try:
    json.loads( text, object_pairs_hook = hook )
except ValueError as e:
    print( e ); sys.exit( 1 )
PY
}

# a parses as JSON via python3 -m json.tool; prints nothing on success. Fails the check on parse error.
# #10: and spells every key once (nodupes) — a parse that keeps the last value is not a parity check.
parses(){
    local desc="$1"; shift
    local out; out="$( "$@" 2>/dev/null )"
    if printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1; then
        ok "$desc: --json parses (python3 -m json.tool)"
        printf '%s' "$out" >"$TMP/parses.json"
        local dup; dup="$( nodupes "$TMP/parses.json" )" \
            && ok "#10 $desc: no duplicate keys" \
            || no "#10 $desc: duplicate JSON key — $dup"
    else
        no "$desc: --json did NOT parse as valid JSON"
        printf '%s\n' "$out" | head -c 300
        echo
    fi
    printf '%s' "$out"
}

# jget FIELD <<<JSON — a small python3 dotted-path getter (a.b[0].c), prints the value or nothing.
jget(){
    python3 -c '
import json, sys
d = json.load(sys.stdin)
path = sys.argv[1]
cur = d
for part in path.split("."):
    if part.endswith("]"):
        name, idx = part[:-1].split("[")
        cur = cur[name][int(idx)] if name else cur[int(idx)]
    else:
        cur = cur[part]
print(cur)
' "$1" 2>/dev/null
}

cd "$REPO"

# ═══ #1 default map ════════════════════════════════════════════════════════════════════════════════════
XML1="$( "$BIN" . --no-cache 2>/dev/null )"
JSON1="$( parses "default map" "$BIN" . --json --no-cache )"
XFILES="$( printf '%s' "$XML1" | grep -oE 'files=[0-9]+' | grep -oE '[0-9]+' | head -1 )"
JFILES="$( printf '%s' "$JSON1" | jget files )"
[ -n "$XFILES" ] && [ "$XFILES" = "$JFILES" ] \
    && ok "default map: files= parity (xml=$XFILES json=$JFILES)" \
    || no "default map: files= MISMATCH (xml='$XFILES' json='$JFILES')"
XSYM="$( printf '%s' "$XML1" | grep -oE 'symbols=[0-9]+' | grep -oE '[0-9]+' | head -1 )"
JSYM="$( printf '%s' "$JSON1" | jget symbols )"
[ -n "$XSYM" ] && [ "$XSYM" = "$JSYM" ] \
    && ok "default map: symbols= parity (xml=$XSYM json=$JSYM)" \
    || no "default map: symbols= MISMATCH (xml='$XSYM' json='$JSYM')"
JT0="$( printf '%s' "$JSON1" | jget 'r[0].s[0].t' )"
printf '%s' "$XML1" | grep -q "t=\"$JT0\"" \
    && ok "default map: first symbol t= parity ($JT0 appears in the XML too)" \
    || no "default map: first symbol t='$JT0' not found in the XML sibling"

# G5: plain (no --json) output is untouched — spot-check the XML still starts with the schema comment.
printf '%s' "$XML1" | head -c 20 | grep -q '<!-- ripwire' \
    && ok "G5: default map WITHOUT --json is still plain XML (untouched)" \
    || no "G5: default map without --json looks different — --json must be purely additive"

# ═══ #2 --for ═══════════════════════════════════════════════════════════════════════════════════════════
XML2="$( "$BIN" . --for="add two numbers" --no-cache 2>/dev/null )"
JSON2="$( parses "--for" "$BIN" . --for="add two numbers" --json --no-cache )"
JTASK="$( printf '%s' "$JSON2" | jget task )"
[ "$JTASK" = "add two numbers" ] \
    && ok "--for: task= parity ($JTASK)" \
    || no "--for: task mismatch (got '$JTASK')"
JSIG0="$( printf '%s' "$JSON2" | jget 'sigs[0].sig' )"
printf '%s' "$XML2" | grep -qF "$JSIG0" \
    && ok "--for: first sig text appears verbatim in the XML sibling" \
    || no "--for: first sig text ('$JSIG0') not found in the XML sibling"
JADD="$( printf '%s' "$JSON2" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(any("add" in (s.get("sig","")) for s in d["sigs"]))' 2>/dev/null )"
[ "$JADD" = "True" ] \
    && ok "--for: ranked set includes add() (relevance sanity)" \
    || no "--for: ranked set did not surface add() for an 'add two numbers' query"

# ═══ #3 --pack-task ═════════════════════════════════════════════════════════════════════════════════════
JSON3="$( parses "--pack-task" "$BIN" . --pack-task="add two numbers" --json --no-cache )"
JBT="$( printf '%s' "$JSON3" | jget budget_tokens )"
[ "$JBT" = "6000" ] \
    && ok "--pack-task: budget_tokens= default (6000)" \
    || no "--pack-task: budget_tokens unexpected (got '$JBT')"
JBODY0="$( printf '%s' "$JSON3" | jget 'bodies[0].n' )"
[ -n "$JBODY0" ] \
    && ok "--pack-task: bodies[0].n present ($JBODY0)" \
    || no "--pack-task: bodies[] empty — expected at least one full body"
JCALLERSOF="$( printf '%s' "$JSON3" | jget callers_of_top )"
[ -n "$JCALLERSOF" ] \
    && ok "--pack-task: callers_of_top= present ($JCALLERSOF)" \
    || no "--pack-task: callers_of_top missing"

# ═══ #4 --callers / --callees ═══════════════════════════════════════════════════════════════════════════
XML4="$( "$BIN" . --callers=add --no-cache 2>/dev/null )"
JSON4="$( parses "--callers" "$BIN" . --callers=add --json --no-cache )"
JOF="$( printf '%s' "$JSON4" | jget of )"
[ "$JOF" = "add" ] \
    && ok "--callers: of= parity (add)" \
    || no "--callers: of= mismatch (got '$JOF')"
JCOUNT="$( printf '%s' "$JSON4" | jget count )"
XCOUNT="$( printf '%s' "$XML4" | grep -oE 'count="[0-9]+"' | grep -oE '[0-9]+' | head -1 )"
[ -n "$XCOUNT" ] && [ "$JCOUNT" = "$XCOUNT" ] \
    && ok "--callers: count= parity (xml=$XCOUNT json=$JCOUNT)" \
    || no "--callers: count= MISMATCH (xml='$XCOUNT' json='$JCOUNT')"
JCN0="$( printf '%s' "$JSON4" | jget 'callers[0].n' )"
printf '%s' "$XML4" | grep -q "n=\"$JCN0\"" \
    && ok "--callers: first caller n= parity ($JCN0)" \
    || no "--callers: first caller n='$JCN0' not found in the XML sibling"

# ═══ #5 --impact ════════════════════════════════════════════════════════════════════════════════════════
XML5="$( "$BIN" . --impact=add --no-cache 2>/dev/null )"
JSON5="$( parses "--impact" "$BIN" . --impact=add --json --no-cache )"
JDEFS="$( printf '%s' "$JSON5" | jget defs )"
XDEFS="$( printf '%s' "$XML5" | grep -oE 'defs="[0-9]+"' | grep -oE '[0-9]+' | head -1 )"
[ -n "$XDEFS" ] && [ "$JDEFS" = "$XDEFS" ] \
    && ok "--impact: defs= parity (xml=$XDEFS json=$JDEFS)" \
    || no "--impact: defs= MISMATCH (xml='$XDEFS' json='$JDEFS')"
JREACHES="$( printf '%s' "$JSON5" | jget reaches )"
XREACHES="$( printf '%s' "$XML5" | grep -oE 'reaches="[0-9]+"' | grep -oE '[0-9]+' | head -1 )"
[ -n "$XREACHES" ] && [ "$JREACHES" = "$XREACHES" ] \
    && ok "--impact: reaches= parity (xml=$XREACHES json=$JREACHES)" \
    || no "--impact: reaches= MISMATCH (xml='$XREACHES' json='$JREACHES')"
JIN0="$( printf '%s' "$JSON5" | jget 'impact[0].n' )"
printf '%s' "$XML5" | grep -q "n=\"$JIN0\"" \
    && ok "--impact: first row n= parity ($JIN0)" \
    || no "--impact: first row n='$JIN0' not found in the XML sibling"

# ═══ #6 --quality-delta ═════════════════════════════════════════════════════════════════════════════════
XML6="$( "$BIN" . --quality-delta --no-cache 2>/dev/null )"
JSON6="$( parses "--quality-delta" "$BIN" . --quality-delta --json --no-cache )"
JBASELINE="$( printf '%s' "$JSON6" | jget baseline )"
printf '%s' "$XML6" | grep -q "baseline=\"$JBASELINE\"" \
    && ok "--quality-delta: baseline= parity ($JBASELINE)" \
    || no "--quality-delta: baseline='$JBASELINE' not found in the XML sibling"
JREG="$( printf '%s' "$JSON6" | jget regressions )"
XREG="$( printf '%s' "$XML6" | grep -oE 'regressions="[0-9]+"' | grep -oE '[0-9]+' | head -1 )"
[ -n "$XREG" ] && [ "$JREG" = "$XREG" ] \
    && ok "--quality-delta: regressions= parity (xml=$XREG json=$JREG)" \
    || no "--quality-delta: regressions= MISMATCH (xml='$XREG' json='$JREG')"
JMINOR="$( printf '%s' "$JSON6" | jget minor )"
XMINOR="$( printf '%s' "$XML6" | grep -oE 'minor="[0-9]+"' | grep -oE '[0-9]+' | head -1 )"
[ -n "$XMINOR" ] && [ "$JMINOR" = "$XMINOR" ] \
    && ok "--quality-delta: minor= parity (xml=$XMINOR json=$JMINOR)" \
    || no "--quality-delta: minor= MISMATCH (xml='$XMINOR' json='$JMINOR')"

# ═══ #7 --test-gate ═════════════════════════════════════════════════════════════════════════════════════
# explicit files (not the live git diff, which is empty right after commit) so this is deterministic.
XML7="$( "$BIN" . --test-gate=src/calc.cpp --no-cache 2>/dev/null )"
JSON7="$( parses "--test-gate" "$BIN" . --test-gate=src/calc.cpp --json --no-cache )"
JCHANGED="$( printf '%s' "$JSON7" | jget changed )"
XCHANGED="$( printf '%s' "$XML7" | grep -oE 'changed="[0-9]+"' | grep -oE '[0-9]+' | head -1 )"
[ -n "$XCHANGED" ] && [ "$JCHANGED" = "$XCHANGED" ] \
    && ok "--test-gate: changed= parity (xml=$XCHANGED json=$JCHANGED)" \
    || no "--test-gate: changed= MISMATCH (xml='$XCHANGED' json='$JCHANGED')"
JTESTS="$( printf '%s' "$JSON7" | jget tests )"
XTESTS="$( printf '%s' "$XML7" | grep -oE 'tests="[0-9]+"' | grep -oE '[0-9]+' | head -1 )"
[ -n "$XTESTS" ] && [ "$JTESTS" = "$XTESTS" ] \
    && ok "--test-gate: tests= parity (xml=$XTESTS json=$JTESTS)" \
    || no "--test-gate: tests= MISMATCH (xml='$XTESTS' json='$JTESTS')"
JTP0="$( printf '%s' "$JSON7" | jget 'tests_to_run[0].p' )"
[ "$JTESTS" != "0" ] && { printf '%s' "$XML7" | grep -qF "p=\"$JTP0\"" \
    && ok "--test-gate: first tests_to_run[].p parity ($JTP0)" \
    || no "--test-gate: tests_to_run[0].p='$JTP0' not found in the XML sibling"; } || ok "--test-gate: no tests to run (skipping row parity)"

# ═══ #8 unsupported verb refuses LOUDLY (stderr + exit 1), never silent XML ════════════════════════════
ERR8="$( "$BIN" . --deps --json --no-cache 2>&1 1>/dev/null )"; rc8=$?
{ [ "$rc8" -eq 1 ] && printf '%s' "$ERR8" | grep -qi 'not yet supported'; } \
    && ok "--deps --json refuses loudly (exit 1, stderr names it): $ERR8" \
    || no "--deps --json expected exit 1 + a named refusal, got exit=$rc8 stderr='$ERR8'"

ERR8B="$( "$BIN" . --grep=add --json --no-cache 2>&1 1>/dev/null )"; rc8b=$?
{ [ "$rc8b" -eq 1 ] && printf '%s' "$ERR8B" | grep -qi 'not yet supported'; } \
    && ok "--grep --json refuses loudly (exit 1)" \
    || no "--grep --json expected exit 1 + a named refusal, got exit=$rc8b stderr='$ERR8B'"

# §B1.4 (2026-07-29) — REPINNED from the literal "not yet supported" to the two MEANING halves: exit 1, and
# the refusal NAMES the flag. --format=candidates is an output-SHAPE modifier, not a verb, so it no longer
# gets the verb sentence ("--json is not yet supported for X — supported: …the default map…"): enumerating
# supported VERBS at someone who typed an encoding names nothing they can act on. The refusal it gets now
# says the two encodings collide. The contract this arm defends — refuse loudly, name the flag — is unchanged.
ERR8C="$( "$BIN" . --for="x" --format=candidates --json --no-cache 2>&1 1>/dev/null )"; rc8c=$?
{ [ "$rc8c" -eq 1 ] && printf '%s' "$ERR8C" | grep -q -- '--format=candidates'; } \
    && ok "--for --format=candidates --json refuses loudly and names the modifier"  \
    || no "--for --format=candidates --json expected exit 1 + the flag named, got exit=$rc8c stderr='$ERR8C'"

# ═══ #8b (capture-audit 2026-09-04, H2) — the UNIVERSE: every flag the binary parses, under --json ═════
#
# Arm #8 above probes three verbs by name. That is how twelve verbs (--dmm --handoff --readability
# --quality-panel --field-affinity --lint-catalog --comment-coherence --context-ratio --ensemble
# --naming-calibration --naming-consistency --nonlocal-state) shipped emitting XML at exit 0 under --json
# with nothing on stderr: jsonUnsupportedVerb was a deny CHAIN, and a verb nobody added to the chain was
# silently allowed. This arm iterates the flag universe DERIVED FROM src/cli.h (test/flaguniverse.py: the
# three tables plus the hand-written parseArgs arms) and allows exactly two outcomes per flag:
#     JSON      stdout's first non-blank byte is `{` or `[` (and it parses)
#     REFUSAL   exit != 0, EMPTY stdout, stderr names the flag
# A third outcome — XML (or anything else) on stdout — fails by name. The probe VALUE is irrelevant for an
# unsupported verb (the refusal is pre-dispatch) and only has to clear the parser: the JSON verbs get a real
# argv on this fixture, parse-time domains get a legal value, everything else a bogus token. --help/--version
# print usage and exit 0 by contract and are the only two rows not probed.
UNIV="$TMP/universe.tsv"
python3 "$ROOT/test/flaguniverse.py" "$ROOT/src/cli.h" > "$UNIV"
UROWS="$( grep -c . "$UNIV" )"
[ "$UROWS" -ge 190 ] && ok "#8b: derived $UROWS flag rows from src/cli.h" \
                     || no "#8b: only $UROWS rows derived — the scrape broke, so the sweep below asserts nothing"
probeFor()
{
    case "$1" in
        --for=)          printf '%s' '--for=addition' ;;          # one token: the probe is word-split on purpose below
        --pack-task=)    printf '%s' '--pack-task=addition' ;;
        --callers=)      printf '%s' '--callers=add' ;;
        --callees=)      printf '%s' '--callees=add' ;;
        --impact=)       printf '%s' '--impact=add' ;;
        --test-gate=)    printf '%s' '--test-gate=src/calc.cpp' ;;
        --quality-delta=) printf '%s' '--quality-delta=HEAD' ;;
        --order=)        printf '%s' '--order=stable' ;;
        --rank-by=)      printf '%s' '--rank-by=churn' ;;
        --format=)       printf '%s' '--format=columnar' ;;
        --color-by=)     printf '%s' '--color-by=lang' ;;
        --grep-scope=)   printf '%s' '--grep-scope=file' ;;
        --grep-in=)      printf '%s' '--grep-in=any' ;;
        --legend=)       printf '%s' '--legend=compact' ;;
        --slice-flow=)   printf '%s' '--slice-flow=back' ;;
        --agent=)        printf '%s' '--agent=codex' ;;
        --export=)       printf '%s' '--export=cc.json' ;;
        --quality-panel=) printf '%s' '--quality-panel=default' ;;
        --token-budget=) printf '%s' '--token-budget=100' ;;
        --limit=)        printf '%s' '--limit=3' ;;
        --offset=)       printf '%s' '--offset=1' ;;
        --max-file-size=) printf '%s' '--max-file-size=1M' ;;
        --pack-budget-bytes=) printf '%s' '--pack-budget-bytes=1000' ;;
        --cache=)        printf '%s' "--cache=$TMP/probe.cache" ;;
        --index-out=)    printf '%s' "--index-out=$TMP/probe.idx" ;;
        --pin-census=)   printf '%s' "--pin-census=$TMP/probe.tsv" ;;
        --run-trace=)    printf '%s' '--run-trace=true' ;;          # a harmless command, should it ever reach exec
        --listen=)       printf '%s' '--listen=127.0.0.1:1' ;;      # sets --mcp; refused before any socket is bound
        --note-add=)     printf '%s' '--note-add=add: t' ;;
        --at=)           printf '%s' '--at=src/calc.cpp:2' ;;
        --help|--version) return 1 ;;
        *=)              printf '%s' "${1}zzqq9" ;;                # bogus: the refusal is pre-dispatch, the value never matters
        *)               printf '%s' "$1" ;;
    esac
}
nJson=0; nRefuse=0; jsonVerbs=""
while IFS="$( printf '\t' )" read -r flag kind example policy; do
    [ -n "$flag" ] || continue
    case "$kind" in int) probe="${flag}3" ;; *) probe="$( probeFor "$flag" )" || continue ;; esac
    case "$flag" in --max-tokens=) probe="--max-tokens=100000" ;; esac
    "$BIN" . $probe --json --no-cache >"$TMP/u.out" 2>"$TMP/u.err" </dev/null; rc=$?
    first="$( tr -d ' \n\t\r' <"$TMP/u.out" | head -c 1 )"
    name="${flag%%=*}"
    if [ "$first" = "{" ] || [ "$first" = "[" ]; then
        if python3 -m json.tool <"$TMP/u.out" >/dev/null 2>&1; then
            nJson=$(( nJson + 1 )); jsonVerbs="$jsonVerbs $name"
            dup="$( nodupes "$TMP/u.out" )" || no "#10 #8b: $probe --json spells a key twice — $dup"
        else
            no "#8b: $probe --json put a '$first' on stdout that does not parse as JSON"
        fi
    elif [ "$rc" -ne 0 ] && [ ! -s "$TMP/u.out" ] && grep -qF -- "$name" "$TMP/u.err"; then
        nRefuse=$(( nRefuse + 1 ))
    else
        no "#8b: $probe --json — neither JSON nor a refusal naming the flag: exit=$rc stdout starts with '$first' ($( wc -c <"$TMP/u.out" | tr -d ' ' ) B) stderr=[$( head -c 160 "$TMP/u.err" | tr '\n' ' ' )]"
    fi
done < "$UNIV"
[ "$nJson" -ge 9 ] && ok "#8b: $nJson flags answered in JSON:$jsonVerbs" \
                   || no "#8b: only $nJson flags answered in JSON (want >= 9 — the documented set):$jsonVerbs"
[ "$nRefuse" -ge 150 ] && ok "#8b: $nRefuse flags refused --json loudly, naming themselves" \
                       || no "#8b: only $nRefuse flags refused (want >= 150) — the sweep is not covering the universe"
# --help's supported-set sentence must name every JSON verb the sweep found (it omitted --metrics for a round).
HELPJSON="$( "$BIN" --help 2>&1 | sed -n '/^    --json /,/refuses loudly/p' | tr '\n' ' ' )"
for v in $jsonVerbs; do
    case "$v" in --for|--pack-task|--callers|--callees|--impact|--quality-delta|--test-gate|--metrics)
        printf '%s' "$HELPJSON" | grep -q -- "$v" || no "#8b: --help's --json paragraph does not name $v, which answers in JSON" ;;
    esac
done
printf '%s' "$HELPJSON" | grep -q -- '--metrics' && ok "#8b: --help's --json paragraph names --metrics" \
                                                  || no "#8b: --help's --json paragraph omits --metrics"

# ═══ #10 NO DUPLICATE KEYS on every MCP payload + envelope, and on the CLI --batch CDATA payloads ═════════
# The alpha fixture mcpcontractprobe.py's baseArgs() make every verb ANSWER on (a refusal carries no payload
# to check), plus a file with >100 `int` hits so grep's DEFAULT window is cut — the shape on which the
# duplicate lived (a --limit spells the own-name total once by construction). Every verb tools/list
# advertises is driven, edit verbs against a throwaway copy; the sweep must see a JSON payload from the
# JSON-answering verbs (11 measured on this fixture: find_symbol find_referencing_symbols grep cochange
# mentions quality_baseline whereis stray_content + the three edit verbs; the rest answer XML/prose, which
# is not this arm's question) or it asserts nothing — floor 8. The envelope line itself is checked too.
ALPHA="$TMP/alpha"; mkdir -p "$ALPHA"
printf '// alphaOne does a thing.\nint alphaOne( int x ) { return x + 1; }\nint alphaTwo( int x ) { return alphaOne( x ) * 2; }\nint alphaThree() { return alphaTwo( 1 ); }\n' >"$ALPHA/alpha.cpp"
printf '# Notes\n`alphaOne` is the entry point.\n' >"$ALPHA/notes.md"
for i in $( seq 1 120 ); do printf 'int v%d = %d;\n' "$i" "$i"; done >"$ALPHA/many.cpp"
( cd "$ALPHA" && git init -q && git config user.email "t@example.com" && git config user.name "t" \
  && git add -A && git commit -q -m "alpha" )
python3 - "$BIN" "$ALPHA" "$ROOT/test" <<'PY' >"$TMP/mcpdup.out" 2>&1
import json, os, shutil, sys, tempfile
binPath, root, testDir = sys.argv[ 1 ], sys.argv[ 2 ], sys.argv[ 3 ]
sys.path.insert( 0, testDir )
from mcpcontractprobe import Server, baseArgs, EDIT_VERBS
def hook( pairs ):
    seen = set()
    for k, _ in pairs:
        if k in seen:
            raise ValueError( "duplicate key %r" % k )
        seen.add( k )
    return dict( pairs )
def dupOf( text ):
    try:
        json.loads( text, object_pairs_hook = hook )
    except ValueError as e:
        return str( e )
    except Exception:
        return None            # not JSON at all: not this arm's question
    return ""
srv = Server( binPath )
tools = srv.call( "tools/list", {} )[ "result" ][ "tools" ]
payloads = 0; answered = 0; bad = []
for t in tools:
    verb = t[ "name" ]
    args = dict( baseArgs( verb ) )
    scratch = None
    if verb in EDIT_VERBS:
        scratch = tempfile.mkdtemp(); shutil.copytree( root, os.path.join( scratch, "c" ) ); args[ "path" ] = os.path.join( scratch, "c" )
    else:
        args[ "path" ] = root
    srv.n += 1
    req = { "jsonrpc": "2.0", "id": srv.n, "method": "tools/call", "params": { "name": verb, "arguments": args } }
    srv.p.stdin.write( json.dumps( req ).encode() + b"\n" ); srv.p.stdin.flush()
    line = srv.p.stdout.readline().decode( "utf-8", "replace" )
    if scratch: shutil.rmtree( scratch, ignore_errors = True )
    d = dupOf( line )
    if d: bad.append( "%s envelope: %s" % ( verb, d ) )
    try:
        env = json.loads( line )
    except Exception:
        bad.append( "%s: envelope is not JSON" % verb ); continue
    if "error" in env: continue
    answered += 1
    for c in env.get( "result", {} ).get( "content", [] ):
        text = c.get( "text", "" )
        if text.lstrip()[ :1 ] in ( "{", "[" ):
            payloads += 1
            d = dupOf( text )
            if d: bad.append( "%s payload: %s" % ( verb, d ) )
srv.close()
print( "TOOLS=%d ANSWERED=%d PAYLOADS=%d" % ( len( tools ), answered, payloads ) )
for b in bad: print( "DUP " + b )
PY
mcpStats="$( grep '^TOOLS=' "$TMP/mcpdup.out" )"
mcpPayloads="$( printf '%s' "$mcpStats" | sed -E 's/.*PAYLOADS=([0-9]+).*/\1/' )"
[ -n "$mcpPayloads" ] && [ "$mcpPayloads" -ge 8 ] \
    && ok "#10 MCP sweep is live: $mcpStats" \
    || no "#10 MCP sweep inert: [$mcpStats] $( grep -v '^TOOLS=' "$TMP/mcpdup.out" | head -3 | tr '\n' ' ' )"
if grep -q '^DUP ' "$TMP/mcpdup.out"; then
    while IFS= read -r line; do no "#10 MCP ${line#DUP }"; done < <( grep '^DUP ' "$TMP/mcpdup.out" )
else
    ok "#10 MCP: no verb's envelope or payload spells a key twice"
fi
# the CLI --batch form rides the SAME emitters inside CDATA: extract every JSON payload and check each.
printf 'grep:int\ncallers:alphaOne\nfor:add a thing\n' >"$TMP/batch.txt"
"$BIN" "$ALPHA" --batch="$TMP/batch.txt" --no-cache >"$TMP/batch.xml" 2>/dev/null
python3 - "$TMP/batch.xml" <<'PY' >"$TMP/batchdup.out"
import re, sys
t = open( sys.argv[ 1 ], encoding = "utf-8", errors = "replace" ).read()
n = 0
for m in re.finditer( r"<!\[CDATA\[(.*?)\]\]>", t, re.S ):
    body = m.group( 1 ).lstrip()
    if body[ :1 ] in ( "{", "[" ):
        n += 1
        print( "PAYLOAD " + body )
print( "N=%d" % n )
PY
nb="$( grep -o '^N=[0-9]*' "$TMP/batchdup.out" | cut -d= -f2 )"
[ -n "$nb" ] && [ "$nb" -ge 1 ] && ok "#10 --batch: $nb JSON payload(s) in CDATA to check" \
                                || no "#10 --batch: no JSON payload found in the batch document — the arm asserts nothing"
batchDups=0
while IFS= read -r payload; do
    printf '%s' "$payload" >"$TMP/batchpayload.json"
    dup="$( nodupes "$TMP/batchpayload.json" )" || { no "#10 --batch payload spells a key twice — $dup"; batchDups=$(( batchDups + 1 )); }
done < <( grep '^PAYLOAD ' "$TMP/batchdup.out" | sed 's/^PAYLOAD //' )
[ "$batchDups" = 0 ] && ok "#10 --batch: every CDATA JSON payload spells each key once"

# ═══ #9 determinism — 2 runs are byte-identical (the det-gate contract applies to --json too) ═══════════
D1="$( "$BIN" . --json --no-cache 2>/dev/null )"
D2="$( "$BIN" . --json --no-cache 2>/dev/null )"
[ "$D1" = "$D2" ] \
    && ok "det-gate: default map --json byte-identical across 2 runs" \
    || no "det-gate: default map --json differs run-to-run"

D3="$( "$BIN" . --pack-task="add two numbers" --json --no-cache 2>/dev/null )"
D4="$( "$BIN" . --pack-task="add two numbers" --json --no-cache 2>/dev/null )"
[ "$D3" = "$D4" ] \
    && ok "det-gate: --pack-task --json byte-identical across 2 runs" \
    || no "det-gate: --pack-task --json differs run-to-run"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
