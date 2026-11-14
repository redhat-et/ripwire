#!/usr/bin/env bash
# connectdeclinedjointcheck.sh — CONNECT-SOURCE-JOINT (b): when no source function has a call edge to every --connect terminal,
# a source function that reaches every terminal by an edge or by a DECLINED call is printed as a hedged <dj> row (CLI --connect,
# the <graph_verb> block inside --for, the MCP `connect` verb — one core, three surfaces).
#
# THE DEFECT THIS PINS. terraform `--connect=Context.Plan,Context.Apply`: the only non-test caller of both is Local.opApply, through
# `lr.Core.Plan( … )` and `lr.Core.Apply( … )`, two calls the resolver declined (several in-tree candidates). The answer named a
# long undirected join instead (restore -> apply -> ApplyAndEval <- Apply) and never the caller.
#
# Arms (fixture: Go, Context.Plan/Apply and View.Plan/Apply, so `lr.Core.Plan()` on an untyped field is declined between two):
#   P  premise: --callers on each terminal lists opApply as a declined <dc> row; FAIL on zero
#   A  CLI --connect prints <dj n="opApply"> with both calls (site=, call=, via="declined" cands=2) and declined_joints="1"  (RED on main)
#   B  the same through --for's <graph_verb> block                                                                           (RED on main)
#   C  the same through the MCP connect verb                                                                                  (RED on main)
#   D  additive: with an undirected source join beside it (restore), the <g> group is unchanged and the <dj> row is added     (RED on main)
#   E  mixed: a function with a graph edge to Plan and a declined call to Apply is a declined joint; its Plan row has no via=  (RED on main)
#   N1 a resolved source common caller exists: no <dj>, no declined_joints= (premise: driver is the <s> joint)
#   N2 the declined caller is test code: no <dj> (premise: --callers sees the test's declined call)
#   N3 the declined call has 17 candidates (> kBackHopWidth 16): no <dj> (premise: --callers prints cands="17")
#   N4 the declined caller reaches only one terminal: no <dj> (premise: --callers on Plan sees it, on Apply does not)
#   G  legend: declined_joints= and <dj> are defined in both dialects when present, absent otherwise
#   G2 both dialects say N is a floor (declined calls wider than 16 candidates are not followed)               (CodeRabbit 4570578062)
#   H  determinism (3 runs) + xmllint
#
# Usage: test/connectdeclinedjointcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "connectdeclinedjointcheck: BIN=$BIN"

brief(){ printf '%s' "$1" | sed 's/^.*<connect /<connect /' | head -c 900; }

# ── corpora ──────────────────────────────────────────────────────────────────────────────────────────────
mkbase(){   # $1 dir: Context.Plan/Apply plus a same-named View pair, so an untyped receiver's call is declined between two
    mkdir -p "$1/core" "$1/view" "$1/backend"
    printf 'module example.com/fx\n\ngo 1.21\n' > "$1/go.mod"
    printf 'package core\n\ntype Context struct{}\n\nfunc (c *Context) Plan() int { return 1 }\n\nfunc (c *Context) Apply() int { return c.applyAndEval() }\n\nfunc (c *Context) applyAndEval() int { return 2 }\n' > "$1/core/context.go"
    printf 'package view\n\ntype View struct{}\n\nfunc (v *View) Plan() int { return 3 }\n\nfunc (v *View) Apply() int { return 4 }\n' > "$1/view/view.go"
}
OPAPPLY='package backend

type Runner struct {
	Core interface{}
}

func opApply(lr *Runner) int {
	p := lr.Core.Plan()
	a := lr.Core.Apply()
	return p + a
}
'
DJ="$TMP/declined";    mkbase "$DJ";  printf '%s' "$OPAPPLY" > "$DJ/backend/apply.go"

# D: plus an undirected source join that calls neither the way the question means (restore -> c.Plan, restore -> c.applyAndEval)
AD="$TMP/additive";    mkbase "$AD";  printf '%s' "$OPAPPLY" > "$AD/backend/apply.go"
mkdir -p "$AD/cleanup"
printf 'package cleanup\n\nimport "example.com/fx/core"\n\nfunc restore(c *core.Context) int {\n\treturn c.Plan() + c.applyAndEval()\n}\n' > "$AD/cleanup/restore.go"

# E: a graph edge to Plan, a declined call to Apply
MX="$TMP/mixed";       mkbase "$MX"
printf 'package backend\n\nimport "example.com/fx/core"\n\ntype Runner struct {\n\tCore interface{}\n}\n\nfunc opMixed(c *core.Context, lr *Runner) int {\n\treturn c.Plan() + lr.Core.Apply()\n}\n' > "$MX/backend/mixed.go"

# N1: a resolved source common caller exists beside the declined one
RC="$TMP/resolved";    mkbase "$RC";  printf '%s' "$OPAPPLY" > "$RC/backend/apply.go"
printf 'package backend\n\nimport "example.com/fx/core"\n\nfunc driver(c *core.Context) int {\n\treturn c.Plan() + c.Apply()\n}\n' > "$RC/backend/driver.go"

# N2: the declined caller is test code
TC="$TMP/testcaller";  mkbase "$TC";  printf '%s' "$OPAPPLY" | sed 's/func opApply/func TestOpApply/' > "$TC/backend/apply_test.go"

# N3: 17 candidates for each name (> the 16 a hop follows)
WD="$TMP/wide";        mkbase "$WD";  printf '%s' "$OPAPPLY" > "$WD/backend/apply.go"
mkdir -p "$WD/many"
{
    printf 'package many\n\n'
    for i in $( seq 1 15 ); do printf 'type V%d struct{}\n\nfunc (v *V%d) Plan() int { return %d }\n\nfunc (v *V%d) Apply() int { return %d }\n\n' "$i" "$i" "$i" "$i" "$i"; done
} > "$WD/many/many.go"

# N4: the declined caller reaches Plan only
ON="$TMP/onlyone";     mkbase "$ON"
printf 'package backend\n\ntype Runner struct {\n\tCore interface{}\n}\n\nfunc opPlan(lr *Runner) int {\n\treturn lr.Core.Plan()\n}\n' > "$ON/backend/plan.go"

CN='--connect=Context.Plan,Context.Apply'
djOf(){ printf '%s' "$1" | grep -o '<dj n="[^>]*>.*</dj>'; }

# ── P) premise: the declined calls exist and name the terminals ─────────────────────────────────────────
premise=0
for t in Context.Plan Context.Apply; do
    cl="$( "$BIN" "$DJ" --no-cache --callers="$t" 2>/dev/null )" || no "premise: --callers=$t exited $?"
    printf '%s' "$cl" | grep -q '<dc in="opApply" p="backend/apply.go:[0-9]*" cands="2" via="declined"' && premise=$(( premise + 1 ))
done
if [ "$premise" -eq 2 ]; then
    ok "(P) premise: opApply's declined calls name both terminals (seen by --callers on each: $premise/2)"
else
    no "(P) premise: opApply is a declined caller of $premise/2 terminals — the arms below would be vacuous"
fi

checkDj(){   # $1 label, $2 document
    local d; d="$( djOf "$2" )"
    if printf '%s' "$d" | grep -q '^<dj n="opApply" t="fn" p="backend/apply.go:7">'; then ok "($1) <dj> names opApply at its definition"; else no "($1) no <dj n=\"opApply\"> row: $( brief "$2" )"; fi
    if printf '%s' "$d" | grep -q '<e t="Plan" via="declined" cands="2" site="backend/apply.go:8" call="p := lr.Core.Plan()"/>'; then ok "($1) the Plan call: declined, cands=2, site and call text"; else no "($1) Plan row wrong or missing: $d"; fi
    if printf '%s' "$d" | grep -q '<e t="Apply" via="declined" cands="2" site="backend/apply.go:9" call="a := lr.Core.Apply()"/>'; then ok "($1) the Apply call: declined, cands=2, site and call text"; else no "($1) Apply row wrong or missing: $d"; fi
    if printf '%s' "$2" | grep -q '<connect [^>]*declined_joints="1"'; then ok "($1) the root counts it: declined_joints=\"1\""; else no "($1) no declined_joints=\"1\" on the root: $( brief "$2" )"; fi
    if printf '%s' "$2" | grep -q 'nodes="2" edges="0"'; then ok "($1) nodes=/edges= do not count the hedge"; else no "($1) nodes=/edges= moved: $( brief "$2" )"; fi
}
noDj(){   # $1 label, $2 document
    if printf '%s' "$2" | grep -q '<dj \|declined_joints='; then no "($1) a <dj> row / declined_joints= printed: $( brief "$2" )"; else ok "($1) no <dj> row, no declined_joints="; fi
}

# ── A) CLI ─────────────────────────────────────────────────────────────────────────────────────────────────
A_FULL="$( "$BIN" "$DJ" --no-cache "$CN" --legend=full 2>/dev/null )" || no "A_FULL: ripwire exited $?"
A_CMP="$( "$BIN" "$DJ" --no-cache "$CN" --legend=compact 2>/dev/null )" || no "A_CMP: ripwire exited $?"
checkDj "A" "$A_FULL"

# ── B) --for's <graph_verb> block ────────────────────────────────────────────────────────────────────────
B_DOC="$( "$BIN" "$DJ" --no-cache --for='common caller of Context.Plan and Context.Apply' 2>/dev/null )" || no "B_DOC: ripwire exited $?"
B_GV="$( printf '%s' "$B_DOC" | grep -o '<graph_verb .*</graph_verb>' )"
if printf '%s' "$B_GV" | grep -q 'verb="--connect='; then
    ok "(B) premise: --for ran the --connect graph verb"
    checkDj "B" "$B_GV"
else
    no "(B) premise: --for printed no --connect <graph_verb> block: $( printf '%s' "$B_DOC" | tail -c 400 )"
fi

# ── C) MCP connect verb ──────────────────────────────────────────────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
    CMSG='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"connect","arguments":{"path":"'"$DJ"'","symbols":["Context.Plan","Context.Apply"]}}}'
    C_RAW="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$CMSG" | "$BIN" --mcp 2>/dev/null )" || no "(C) ripwire --mcp exited $?"
    C_DOC="$( printf '%s\n' "$C_RAW" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + json.dumps(r["error"]) if "error" in r else r["result"]["content"][0]["text"])
' )"
    case "$C_DOC" in
        __ERROR__*) no "(C) MCP connect returned an error: ${C_DOC#__ERROR__:}";;
        *) checkDj "C" "$C_DOC";;
    esac
else
    ok "(C) python3 absent — MCP arm skipped"
fi

# ── D) additive beside an undirected source join ─────────────────────────────────────────────────────────
D_DOC="$( "$BIN" "$AD" --no-cache "$CN" 2>/dev/null )" || no "D_DOC: ripwire exited $?"
if printf '%s' "$D_DOC" | grep -q '<g terminals="2">.*<s n="restore"'; then ok "(D) premise: the undirected source join (restore) is still the <g> group"; else no "(D) premise: no <g> through restore: $( brief "$D_DOC" )"; fi
if printf '%s' "$( djOf "$D_DOC" )" | grep -q '^<dj n="opApply"'; then ok "(D) the declined common caller is added beside it"; else no "(D) no <dj n=\"opApply\"> beside the restore join: $( brief "$D_DOC" )"; fi
D_G="$( printf '%s' "$D_DOC" | grep -o '<g terminals.*</g>' )"
if printf '%s' "$D_G" | grep -q 'opApply'; then no "(D) opApply leaked into the <g> group (counted as a node/edge)"; else ok "(D) the <g> group does not hold the hedge"; fi

# ── E) mixed: an edge to Plan, a declined call to Apply ────────────────────────────────────────────────
E_DOC="$( "$BIN" "$MX" --no-cache "$CN" 2>/dev/null )" || no "E_DOC: ripwire exited $?"
E_DJ="$( djOf "$E_DOC" )"
if printf '%s' "$E_DJ" | grep -q '^<dj n="opMixed".*<e t="Plan" site="backend/mixed.go:10"[^>]*/><e t="Apply" via="declined" cands="2" site="backend/mixed.go:10"'; then
    ok "(E) opMixed: a resolved Plan row (no via=) and a declined Apply row"
else
    no "(E) expected the mixed <dj n=\"opMixed\">: $( brief "$E_DOC" )"
fi

# ── N1..N4) negative arms, each with its premise ─────────────────────────────────────────────────────────
N1_DOC="$( "$BIN" "$RC" --no-cache "$CN" 2>/dev/null )" || no "N1_DOC: ripwire exited $?"
if printf '%s' "$N1_DOC" | grep -q '<s n="driver"'; then ok "(N1) premise: driver is the resolved <s> joint"; else no "(N1) premise: driver is not the joint: $( brief "$N1_DOC" )"; fi
noDj "N1" "$N1_DOC"

# run(): one call into $RUN, its exit status checked (a crashed run must not read as "no <dj> row")
run(){ RUN="$( "$BIN" "$@" 2>/dev/null )" || { no "ripwire $* exited $?"; RUN=""; }; }

run "$TC" --no-cache --callers=Context.Apply; n2p="$( printf '%s' "$RUN" | grep -c '<dc in="TestOpApply"' )"
if [ "$n2p" -ge 1 ]; then ok "(N2) premise: --callers sees the test's declined call ($n2p)"; else no "(N2) premise: the test's declined call is not seen (0) — the arm would be vacuous"; fi
run "$TC" --no-cache "$CN"; noDj "N2" "$RUN"

run "$WD" --no-cache --callers=Context.Apply; n3p="$( printf '%s' "$RUN" | grep -c '<dc in="opApply" [^>]*cands="17"' )"
if [ "$n3p" -ge 1 ]; then ok "(N3) premise: the declined call holds 17 candidates ($n3p)"; else no "(N3) premise: no cands=\"17\" row (0) — the arm would be vacuous"; fi
run "$WD" --no-cache "$CN"; noDj "N3" "$RUN"

run "$ON" --no-cache --callers=Context.Plan;  n4a="$( printf '%s' "$RUN" | grep -c '<dc in="opPlan"' )"
run "$ON" --no-cache --callers=Context.Apply; n4b="$( printf '%s' "$RUN" | grep -c '<dc in="opPlan"' )"
if [ "$n4a" -ge 1 ] && [ "$n4b" -eq 0 ]; then ok "(N4) premise: opPlan's declined call names Plan only"; else no "(N4) premise: Plan $n4a / Apply $n4b"; fi
run "$ON" --no-cache "$CN"; noDj "N4" "$RUN"

# ── G) legend ────────────────────────────────────────────────────────────────────────────────────────────
if printf '%s' "$A_FULL" | grep -q '<!-- ripwire connect: declined_joints=N: '; then ok "(G) full dialect defines declined_joints= and <dj>"; else no "(G) full legend lacks the declined_joints= clause"; fi
if printf '%s' "$A_CMP" | sed 's/<connect .*//' | grep -q 'declined_joints=N: .*dj n= t= p='; then ok "(G) compact dialect defines declined_joints= and dj"; else no "(G) compact legend lacks declined_joints= / dj"; fi
if printf '%s' "$N1_DOC" | grep -q 'declined_joints'; then no "(G) the clause rides on an answer without a <dj> row"; else ok "(G) absent from an answer without a <dj> row"; fi
# (G2) CodeRabbit 4570578062: N counts only callers through declined calls of at most 16 candidates, so both dialects call it a floor
if printf '%s' "$A_FULL" | grep -q 'declined_joints=N: [^>]*a wider declined call is not followed, so N is a floor'; then ok "(G2) full dialect labels declined_joints=N a floor (declined calls over 16 candidates are not followed)"; else no "(G2) the full clause does not say N is a floor"; fi
if printf '%s' "$A_CMP" | sed 's/<connect .*//' | grep -q 'declined_joints=N: [^>]*a floor: a declined call over 16 cands is not followed'; then ok "(G2) compact dialect labels declined_joints=N a floor"; else no "(G2) the compact clause does not say N is a floor"; fi


# ── H) determinism + well-formedness ─────────────────────────────────────────────────────────────────────
run "$AD" --no-cache "$CN"; h1="$RUN"; run "$AD" --no-cache "$CN"; h2="$RUN"; run "$AD" --no-cache "$CN"; h3="$RUN"
if [ "$h1" = "$h2" ] && [ "$h2" = "$h3" ]; then ok "(H) 3 runs byte-identical"; else no "(H) runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    for doc in "$A_FULL" "$A_CMP" "$D_DOC" "$E_DOC"; do
        printf '%s' "$doc" | xmllint --noout - 2>/dev/null || no "(H) xmllint rejects: $( brief "$doc" )"
    done
    ok "(H) xmllint on the A/D/E answers"
fi

[ "$fail" -eq 0 ] && echo "connectdeclinedjointcheck: PASS" || echo "connectdeclinedjointcheck: FAIL"
exit "$fail"
