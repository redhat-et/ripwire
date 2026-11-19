#!/usr/bin/env bash
# tanglecheck.sh — QD-TANGLE gate: the tangle kind (report-only), its steering-local fact, the D4 best-since ratchet and the
# QD-CREDIT-ROW <improved> section (STAGE0 2.1-2.8; quality.h appendTangleRows / appendTangleRatchet, qdbestsince.h).
#
# One seeded C++ repo, three stages (test/lib/tanglefixtures.py): v1 (tagged), c2 (committed), the working tree (judged).
#   (t1) TANGLED NEW: a depth-6 function with a steering flag rows: kind="tangle" sev="minor" origin="new-symbol", why= names the
#        nesting, fix= an extraction with its lines, locals= the flag.
#   (n1) LONG SEQUENTIAL, (n2) LONG ORCHESTRATOR, (n3) FLAT DISPATCHER, (n4) SHORT NESTED HELPER: no tangle row. Each counts its
#        premise in --metrics first (the function is there, and n3/n4 really reach depth 4+) and FAILS on a zero premise.
#   (n5) ARM NESTING: a 6-arm else-if chain whose short arms nest to depth 7, beside one depth-4 region outside it: no tangle row
#        (premise: nest 7 in --metrics, deep lines present). Census 11-19 (parseArgs): only the depth OUTSIDE the arms is the body's.
#   (s1) STEER FAR: a flag set, then tested 12 statements later: steer="1" in --metrics. (s2) STEER NEAR: tested in the next
#        statement: no steer=. (s3) CURSOR: a local advanced, then read 12 statements later only as a bound (`pos < limit`) and as
#        an index (`xs[ pos ]`): no steer= (premise: steercursor in --metrics). Census 11-19: lexCpp's `j`, buildGraph's indices.
#   (r1) RATCHET: creep gained 3 deep lines at c2 and 3 more in the working tree — each step under the rise rule (+5), so no
#        baseline row reason exists, but against its best since v1 it rose 6: a tangle row with ratchet="v1"; root ratchet_ref="v1".
#   (r2) CREDIT: shrink lost its deep region: listed in <improved> as kind="tangle", and no tangle row.
#   (r3) NEW FN: the tangled new function's row carries no ratchet= (a symbol created after the tag has no history here).
#   (c1) CREDIT: simplify ccx 21 -> 11: listed in <improved> as kind="complexity".
#   (g)  report-only: gating="0" on the root although tangle rows are present (premise: >= 1 tangle row).
#   (j)  --json carries the same tangle rows (count) and "improved".
#   (d)  determinism: the working-tree run twice is byte-identical.
# Red before the lane (main's bin): t1 r1 r2 r3 c1 s1 (no tangle kind, no steer=, no improved); red before the census fixes (11-19): n5 s3.
# Usage: test/tanglecheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"
export HOME="$TMP/home"; mkdir -p "$HOME"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "tanglecheck: BIN=$BIN"
G=( git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c tag.gpgsign=false )

R="$TMP/repo"; mkdir -p "$R"; "${G[@]}" -C "$R" init -q
python3 "$ROOT/test/lib/tanglefixtures.py" v1 "$R" || { echo "fixture writer failed"; exit 2; }
"${G[@]}" -C "$R" add -A && "${G[@]}" -C "$R" commit -qm v1 && "${G[@]}" -C "$R" tag v1
python3 "$ROOT/test/lib/tanglefixtures.py" c2 "$R" || { echo "fixture writer failed"; exit 2; }
"${G[@]}" -C "$R" add -A && "${G[@]}" -C "$R" commit -qm c2
python3 "$ROOT/test/lib/tanglefixtures.py" wt "$R" || { echo "fixture writer failed"; exit 2; }

Q="$TMP/qd.xml"
"$BIN" "$R" --quality-delta --no-cache >"$Q" 2>"$Q.err"; echo $? >"$Q.rc"
"$BIN" "$R" --quality-delta --no-cache >"$Q.2" 2>/dev/null
"$BIN" "$R" --quality-delta --json --no-cache >"$TMP/qd.json" 2>/dev/null
M="$( "$BIN" "$R" --metrics --no-cache 2>/dev/null )"
rc="$( cat "$Q.rc" )"
case "$rc" in 0|2) ;; *) no "quality-delta exit status $rc (stderr: $( head -c 300 "$Q.err" ))";; esac

# tangle row for a symbol (sym= ends in ::NAME or is NAME), or empty
trow(){ grep -oE "<r kind=\"tangle\" sym=\"[^\"]*$1\"[^>]*>" "$Q" | head -1; }
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E "s/.*=\"([^\"]*)\"/\1/"; }
mrow(){ printf '%s' "$M" | tr '>' '\n' | grep "n=\"$1\"" | head -1; }
tangles="$( grep -oE '<r kind="tangle"' "$Q" | wc -l | tr -d ' ' )"
echo "  premise: $tangles tangle row(s) in the working-tree answer"

# (t1)
r="$( trow tangled )"
if [ -n "$r" ] && [ "$( attr "$r" sev )" = minor ] && [ "$( attr "$r" origin )" = new-symbol ] && attr "$r" why | grep -q 'nest 6' \
   && attr "$r" fix | grep -qE 'extract the [0-9]+-line deep region at L[0-9]+\.\.L[0-9]+' && [ "$( attr "$r" locals )" = found ]; then
    ok "(t1) tangled: minor new-symbol row, why/fix/locals: $r"
else no "(t1) tangled: want a minor new-symbol tangle row with why=nest 6, an extraction fix= and locals=found, got '${r:-none}'"; fi

# (n1)-(n4): premise from --metrics, then no row
neg(){ local label="$1" sym="$2" need="$3" m; m="$( mrow "$sym" )"
    if [ -z "$m" ]; then no "($label) PREMISE: $sym not in --metrics (fixture drifted)"; return; fi
    if [ "$need" = deep ] && ! { [ -n "$( attr "$m" deep )" ] && [ "$( attr "$m" nest )" -ge 4 ]; }; then
        no "($label) PREMISE: $sym should reach depth 4+ with deep lines, got $m"; return; fi
    if [ "$need" = long ] && [ "$( attr "$m" loc )" -le 100 ]; then no "($label) PREMISE: $sym should be over 100 lines, got $m"; return; fi
    if [ -z "$( trow "$sym" )" ]; then ok "($label) $sym: no tangle row (premise: $( attr "$m" loc ) lines, nest $( attr "$m" nest ), deep ${M:+$( attr "$m" deep )})"
    else no "($label) $sym: want no tangle row, got $( trow "$sym" )"; fi; }
neg n1 sequential long
neg n2 orchestrator long
neg n3 dispatcher deep
neg n4 shorthelper deep
m5="$( mrow armnest )"
if [ -z "$m5" ] || [ "$( attr "$m5" nest )" != 7 ] || [ -z "$( attr "$m5" deep )" ]; then no "(n5) PREMISE: armnest should reach nest 7 with deep lines, got '${m5:-none}'"
elif [ -z "$( trow armnest )" ]; then ok "(n5) armnest: no tangle row (premise: $( attr "$m5" loc ) lines, nest 7, deep $( attr "$m5" deep ), tangle=$( attr "$m5" tangle ))"
else no "(n5) armnest: want no tangle row, got $( trow armnest )"; fi

# (s1)/(s2)
mf="$( mrow steerfar )"; mn="$( mrow steernear )"
if [ -z "$mf" ] || [ -z "$mn" ]; then no "(s) PREMISE: steerfar/steernear missing from --metrics"
else
    [ "$( attr "$mf" steer )" = 1 ] && ok "(s1) steerfar: steer=\"1\"" || no "(s1) steerfar: want steer=\"1\", got $mf"
    [ -z "$( attr "$mn" steer )" ] && ok "(s2) steernear: no steer=" || no "(s2) steernear: want no steer=, got $mn"
fi
mc="$( mrow steercursor )"
if [ -z "$mc" ] || [ "$( attr "$mc" loc )" -le 50 ]; then no "(s3) PREMISE: steercursor (over 50 lines) missing from --metrics, got '${mc:-none}'"
else [ -z "$( attr "$mc" steer )" ] && ok "(s3) steercursor: no steer= (bound + index reads)" || no "(s3) steercursor: want no steer=, got $mc"; fi

# (r1)
r="$( trow creep )"
dw="$( attr "$r" why | sed -nE 's/.*best since v1: deep ([0-9]+)-&gt;([0-9]+) lines.*/\1 \2/p' )"
if [ -n "$r" ] && [ "$( attr "$r" ratchet )" = v1 ] && [ -n "$dw" ] && [ $(( ${dw#* } - ${dw% *} )) = 6 ]; then
    ok "(r1) creep: ratchet=\"v1\" row: $r"
else no "(r1) creep: want a tangle row with ratchet=\"v1\" and why=best since v1: deep N->N+6 lines, got '${r:-none}'"; fi
grep -q 'ratchet_ref="v1"' "$Q" && ok "(r1) root ratchet_ref=\"v1\"" || no "(r1) root: no ratchet_ref=\"v1\""
# (r2) / (c1)
grep -qE '<i kind="tangle" sym="[^"]*shrink"' "$Q" && ok "(r2) shrink credited in <improved>" || no "(r2) shrink: no <i kind=\"tangle\"> entry"
[ -z "$( trow shrink )" ] && ok "(r2) shrink: no tangle row" || no "(r2) shrink: unexpected tangle row $( trow shrink )"
grep -qE '<i kind="complexity" sym="[^"]*simplify" was="2[0-9]" now="1[0-9]"' "$Q" && ok "(c1) simplify credited in <improved> (complexity)" \
    || no "(c1) simplify: no <i kind=\"complexity\"> entry ($( grep -oE '<improved[^>]*>' "$Q" ))"
# (r3)
r="$( trow tangled )"; [ -n "$r" ] && [ -z "$( attr "$r" ratchet )" ] && ok "(r3) tangled (new): no ratchet=" || no "(r3) tangled: want a row without ratchet=, got '${r:-none}'"
# (g) report-only: no tangle row gates (other kinds' rows on these fixtures may)
tg="$( grep -oE '<r kind="tangle"[^>]*>' "$Q" | grep -c 'gating="1"' )"; tm="$( grep -oE '<r kind="tangle"[^>]*>' "$Q" | grep -c 'sev="minor"' )"
if [ "$tangles" -ge 1 ] && [ "$tg" = 0 ] && [ "$tm" = "$tangles" ]; then ok "(g) report-only: $tangles tangle row(s), all sev=\"minor\", none gating"
else no "(g) tangle rows $tangles: gating $tg, minor $tm"; fi
# (j) the JSON twin: the same tangle rows in "r" and an "improved" list
jt="$( python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for r in d["r"] if r.get("kind")=="tangle"), len(d.get("improved",[])))' "$TMP/qd.json" 2>/dev/null )"
if [ "${jt% *}" = "$tangles" ] && [ "${jt#* }" -ge 2 ]; then ok "(j) --json: ${jt% *} tangle row(s) and ${jt#* } improved entries"
else no "(j) --json: '$jt' (tangle rows, improved) vs XML $tangles rows"; fi
# (d)
cmp -s "$Q" "$Q.2" && ok "(d) two runs byte-identical" || no "(d) two runs differ"

[ "$fail" = 0 ] && echo "tanglecheck: PASS" || echo "tanglecheck: FAIL"
exit "$fail"
