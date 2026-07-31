#!/usr/bin/env bash
# jsoncheck.sh — gate for L2 (--json output mode, PLAN_audit5Public2026.md).
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
#
# A self-contained tmp git repo fixture (not test/fixture — that one is shared by other goldens and isn't
# its own git repo) gives --quality-delta/--test-gate a real, controlled HEAD + working-tree diff so this
# gate never drifts as the LIVE ctxpack repo's own history changes.
#
# Usage:  CTXPACK_BIN=build/ctxpack bash test/jsoncheck.sh   |   CTXPACK_BIN=asan/ctxpack bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
# NOTE: ok/no print to STDERR (not stdout) — several checks below capture a verb's raw --json output via
# `x="$( parses ... )"` and ok/no are called from inside that same command substitution (parses() reports
# AND returns the payload); stdout must stay reserved for the payload or the PASS/FAIL lines corrupt it.
ok(){ printf '  PASS  %s\n' "$*" >&2; }
no(){ printf '  FAIL  %s\n' "$*" >&2; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
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

# a parses as JSON via python3 -m json.tool; prints nothing on success. Fails the check on parse error.
parses(){
    local desc="$1"; shift
    local out; out="$( "$@" 2>/dev/null )"
    if printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1; then
        ok "$desc: --json parses (python3 -m json.tool)"
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
printf '%s' "$XML1" | head -c 20 | grep -q '<!-- ctxpack' \
    && ok "G5: default map WITHOUT --json is still plain XML (untouched)" \
    || no "G5: default map without --json looks different — --json must be purely additive"

# ═══ #2 --for ═══════════════════════════════════════════════════════════════════════════════════════════
XML2="$( "$BIN" . --for="add two numbers" --no-cache 2>/dev/null )"
JSON2="$( parses "--for" "$BIN" . --for="add two numbers" --json --no-cache )"
JTASK="$( printf '%s' "$JSON2" | jget task )"
[ "$JTASK" = "add two numbers" ] \
    && ok "--for: task= parity ($JTASK)" \
    || no "--for: task mismatch (got '$JTASK')"
JSIG0="$( printf '%s' "$JSON2" | jget 'sigs[0].symbols[0].sig' )"
printf '%s' "$XML2" | grep -qF "$JSIG0" \
    && ok "--for: first sig text appears verbatim in the XML sibling" \
    || no "--for: first sig text ('$JSIG0') not found in the XML sibling"
JADD="$( printf '%s' "$JSON2" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(any("add" in (s.get("sig","")) for f in d["sigs"] for s in f["symbols"]))' 2>/dev/null )"
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
