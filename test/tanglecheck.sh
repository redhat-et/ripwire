#!/usr/bin/env bash
# tanglecheck.sh — QD-TANGLE gate: the tangle kind (rule (b) gates, owner 11-21), its steering-local fact, the D4 best-since ratchet and the
# QD-CREDIT-ROW <improved> section (STAGE0 2.1-2.8; quality.h appendTangleRows / appendTangleRatchet, qdbestsince.h).
#
# One seeded C++ repo, four stages (test/lib/tanglefixtures.py): v1 (tagged); a side branch with wip (cuts creep) then c2,
# merged --no-ff; the working tree (judged).
#   (t1) TANGLED NEW: a depth-6 function with a steering flag rows: kind="tangle" origin="new-symbol" gating="1" (rule (b)), why=
#        names the nesting, fix= an extraction with its lines, locals= the flag.
#   (b1) CROSSING: crossing was 100 flat lines (score 0) and now has tangled's body: a preexisting row (no origin=) with gating="1".
#   (b2) TEST CODE: harnessmain, new under test/ with tangled's body: a row with sev="minor" and no gating= (premise: the row exists).
#   (p1) PIN UNITS: the dirty-tree --quality-baseline refusal names a tangle row as "was=10.5 now=10.9", like the delta row.
#   (b3) EXIT: the answer exits 2 and the root's gating= counts at least t1 + b1; the stderr line names a tangled new function.
#   (n1) LONG SEQUENTIAL, (n2) LONG ORCHESTRATOR, (n3) FLAT DISPATCHER, (n4) SHORT NESTED HELPER: no tangle row. Each counts its
#        premise in --metrics first (the function is there, and n3/n4 really reach depth 4+) and FAILS on a zero premise.
#   (n5) ARM NESTING: a 6-arm else-if chain whose short arms nest to depth 7, beside one depth-4 region outside it: no tangle row
#        (premise: nest 7 in --metrics, deep lines present). Census 11-19 (parseArgs): only the depth OUTSIDE the arms is the body's.
#   (s1) STEER FAR: a flag set, then tested 12 statements later: steer="1" in --metrics. (s2) STEER NEAR: tested in the next
#        statement: no steer=. (s3) CURSOR: a local advanced, then read 12 statements later only as a bound (`pos < limit`) and as
#        an index (`xs[ pos ]`): no steer= (premise: steercursor in --metrics). Census 11-19: lexCpp's `j`, buildGraph's indices.
#        (s4) SCOPE: a counter rewritten in a block that closes, then a for-head local of the same name tested 12 statements
#        later: no steer= (premise: steerscope in --metrics). Census 11-19: genPathOf's `a`.
#   (r1) RATCHET: creep gained 3 deep lines at c2 and 3 more in the working tree — each step under the rise rule (+5); its score
#        grew against HEAD (a ratchet row, k1's rule), and against its best since v1 it rose 6: the row carries ratchet="v1" and why=
#        "best since v1: ..."; root ratchet_ref="v1".
#        The wip side branch's 5-deep-line creep is not its best: the ratchet reads the first-parent line (replay 11-19).
#   (k1) RATCHET VS THE BASE: grow1 (over the bar) gained 2 deep lines: under the rise step and under its best-since-v1 rise, yet
#        its score grew against HEAD: a GATING tangle row was= HEAD's score, now= higher, no ratchet= facet (QD-RATCHET-BASE gate).
#   (k2) MOVED, NOT GROWN: reflow's inputs moved (one flat line) but its score is HEAD's tenth: no row. Against its best since v1
#        it is 6 deep lines up, which made the tag-best compare row it (replay 11-21: buildGraph in #706).
#   (k3) FELL: settle's score fell against HEAD (48 -> 47 deep lines), still 7 over v1: no row and no <improved> entry (under the
#        rise step). Replay 11-21: captureTagsFacts 29.2 -> 29.1 in #714. k1-k3 read their premise from --metrics of HEAD and wt.
#   (r2) CREDIT: shrink lost its deep region: listed in <improved> as kind="tangle", and no tangle row.
#   (r4) NO CREDIT FOR A NUDGE: nudge (over the bar) lost 2 of its 40 deep lines, under the rise step: no <improved> entry
#        (premise: nudge over the bar in --metrics). Replay 11-19: buildGraph 56.9 -> 56.8 was credited for one deep line.
#   (r3) NEW FN: the tangled new function's row carries no ratchet= (a symbol created after the tag has no history here).
#   (c1) CREDIT: simplify ccx 21 -> 11: listed in <improved> as kind="complexity".
#   (g)  only rule (b) and the ratchet gate: the gating tangle rows are exactly creep crossing grow1 tangled; the rest are sev="minor".
#   (j)  --json carries the same tangle rows (count) and "improved".
#   (d)  determinism: the working-tree run twice is byte-identical.
# Red before QD-LESSONS-2 (main 8861b0d4d): t1 b1 b3 (every tangle row minor), k1 (no row: no rise), k2 k3 (the tag-best rows); b2
# is red only on a guard-off build (no test-path exemption).
# Red before the lane (main's bin): t1 r1 r2 r3 c1 s1 (no tangle kind, no steer=, no improved); red before the census fixes (11-19): n5 s3 s4; before the replay fixes (11-19): r1 (wip best) r4.
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
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "tanglecheck: BIN=$BIN"
G=( git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c tag.gpgsign=false )

R="$TMP/repo"; mkdir -p "$R"; "${G[@]}" -C "$R" init -q
python3 "$ROOT/test/lib/tanglefixtures.py" v1 "$R" || { echo "fixture writer failed"; exit 2; }
"${G[@]}" -C "$R" add -A && "${G[@]}" -C "$R" commit -qm v1 && "${G[@]}" -C "$R" tag v1
main="$( "${G[@]}" -C "$R" symbolic-ref --short HEAD )"
"${G[@]}" -C "$R" checkout -qb wip
python3 "$ROOT/test/lib/tanglefixtures.py" wip "$R" || { echo "fixture writer failed"; exit 2; }
"${G[@]}" -C "$R" commit -qam wip
python3 "$ROOT/test/lib/tanglefixtures.py" c2 "$R" || { echo "fixture writer failed"; exit 2; }
"${G[@]}" -C "$R" add -A && "${G[@]}" -C "$R" commit -qm c2
"${G[@]}" -C "$R" checkout -q "$main" && "${G[@]}" -C "$R" merge -q --no-ff -m "merge wip" wip || { echo "fixture merge failed"; exit 2; }
python3 "$ROOT/test/lib/tanglefixtures.py" wt "$R" || { echo "fixture writer failed"; exit 2; }

Q="$TMP/qd.xml"
"$BIN" "$R" --quality-delta --no-cache >"$Q" 2>"$Q.err"; echo $? >"$Q.rc"
"$BIN" "$R" --quality-delta --no-cache >"$Q.2" 2>/dev/null; rc2=$?
"$BIN" "$R" --quality-delta --json --no-cache >"$TMP/qd.json" 2>/dev/null; rcj=$?
M="$( "$BIN" "$R" --metrics --page-bytes=0 --no-cache 2>/dev/null )"; rcm=$?   # the whole answer: main pages --metrics at 24 KB
# CR721 r2: both ends of the pipe are checked, so a partial HEAD fixture stops the gate instead of feeding --metrics
mkdir -p "$TMP/head" && ( set -o pipefail; "${G[@]}" -C "$R" archive HEAD | tar -x -C "$TMP/head" ) \
    || { echo "HEAD fixture extraction failed (git archive | tar)"; exit 2; }
MH="$( "$BIN" "$TMP/head" --metrics --page-bytes=0 --no-cache 2>/dev/null )"; rcmh=$?
rc="$( cat "$Q.rc" )"
case "$rc" in 0|2) ;; *) no "quality-delta exit status $rc (stderr: $( head -c 300 "$Q.err" ))";; esac
if [ "$rc2" != "$rc" ] || [ "$rcj" != "$rc" ]; then no "quality-delta exit status differs between runs: $rc, again $rc2, --json $rcj"; fi
if [ "$rcm" != 0 ] || [ "$rcmh" != 0 ]; then no "--metrics exit status $rcm (working tree), $rcmh (HEAD)"; fi

# tangle row for a symbol (sym= ends in ::NAME or is NAME), or empty
trow(){ grep -oE "<r kind=\"tangle\" sym=\"[^\"]*$1\"[^>]*>" "$Q" | head -1; }
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E "s/.*=\"([^\"]*)\"/\1/"; }
mrow(){ printf '%s' "$M" | tr '>' '\n' | grep "n=\"$1\"" | head -1; }
hrow(){ printf '%s' "$MH" | tr '>' '\n' | grep "n=\"$1\"" | head -1; }
kpre(){ local h w; h="$( hrow "$1" )"; w="$( mrow "$1" )"; printf '%s %s %s %s' "$( attr "$h" tangle )" "$( attr "$w" tangle )" "$( attr "$h" loc )" "$( attr "$w" loc )"; }
tangles="$( grep -oE '<r kind="tangle"' "$Q" | wc -l | tr -d ' ' )"
echo "  premise: $tangles tangle row(s) in the working-tree answer"

# (t1)
r="$( trow tangled )"
if [ -n "$r" ] && [ -z "$( attr "$r" sev )" ] && [ "$( attr "$r" gating )" = 1 ] && [ "$( attr "$r" origin )" = new-symbol ] && attr "$r" why | grep -q 'nest 6' \
   && attr "$r" fix | grep -qE 'extract the [0-9]+-line deep region at L[0-9]+\.\.L[0-9]+' && [ "$( attr "$r" locals )" = found ]; then
    ok "(t1) tangled: gating new-symbol row, why/fix/locals: $r"
else no "(t1) tangled: want a gating new-symbol tangle row with why=nest 6, an extraction fix= and locals=found, got '${r:-none}'"; fi
# (b1) crossing / (b2) test code / (b3) exit + root count + stderr
r="$( trow crossing )"
if [ -n "$r" ] && [ "$( attr "$r" gating )" = 1 ] && [ -z "$( attr "$r" origin )" ] && [ -z "$( attr "$r" sev )" ] && [ "$( attr "$r" was )" = 0.0 ]; then
    ok "(b1) crossing: preexisting gating row: $r"
else no "(b1) crossing: want a gating tangle row with was=\"0.0\" and no origin=, got '${r:-none}'"; fi
r="$( trow harnessmain )"
if [ -z "$r" ]; then no "(b2) PREMISE: harnessmain (test/harness.cpp) has no tangle row"
elif [ "$( attr "$r" sev )" = minor ] && [ -z "$( attr "$r" gating )" ]; then ok "(b2) harnessmain (test code): minor, not gating: $r"
else no "(b2) harnessmain (test code): want sev=\"minor\" and no gating=, got $r"; fi
rg="$( grep -oE '<quality-delta [^>]*' "$Q" | grep -oE ' gating="[0-9]+"' | grep -oE '[0-9]+' )"
if [ "$rc" = 2 ] && [ "${rg:-0}" -ge 2 ] && grep -qF 'a tangled new function (tangle 6.0 or more)' "$Q.err"; then
    ok "(b3) exit 2, root gating=$rg, stderr: $( grep -F 'gating:' "$Q.err" | head -c 300 )"
else no "(b3) want exit 2, root gating >= 2 and the tangled-new stderr line; got rc=$rc gating=${rg:-none} stderr='$( grep -F 'gating:' "$Q.err" | head -c 300 )'"; fi

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
    if [ "$( attr "$mf" steer )" = 1 ]; then ok "(s1) steerfar: steer=\"1\""; else no "(s1) steerfar: want steer=\"1\", got $mf"; fi
    if [ -z "$( attr "$mn" steer )" ]; then ok "(s2) steernear: no steer="; else no "(s2) steernear: want no steer=, got $mn"; fi
fi
mc="$( mrow steercursor )"
if [ -z "$mc" ] || [ "$( attr "$mc" loc )" -le 50 ]; then no "(s3) PREMISE: steercursor (over 50 lines) missing from --metrics, got '${mc:-none}'"
else if [ -z "$( attr "$mc" steer )" ]; then ok "(s3) steercursor: no steer= (bound + index reads)"; else no "(s3) steercursor: want no steer=, got $mc"; fi; fi
ms="$( mrow steerscope )"
if [ -z "$ms" ] || [ "$( attr "$ms" loc )" -le 50 ]; then no "(s4) PREMISE: steerscope (over 50 lines) missing from --metrics, got '${ms:-none}'"
else if [ -z "$( attr "$ms" steer )" ]; then ok "(s4) steerscope: no steer= (closed block's local)"; else no "(s4) steerscope: want no steer=, got $ms"; fi; fi

# (r1)
r="$( trow creep )"
dw="$( attr "$r" why | sed -nE 's/.*best since v1: deep ([0-9]+)-&gt;([0-9]+) lines.*/\1 \2/p' )"
read -r ht wt hl wl <<<"$( kpre creep )"
if [ -n "$r" ] && [ "$( attr "$r" ratchet )" = v1 ] && [ -n "$dw" ] && [ $(( ${dw#* } - ${dw% *} )) = 6 ] && [ "$( attr "$r" was )" = "$ht" ]; then
    ok "(r1) creep: ratchet=\"v1\" row: $r"
else no "(r1) creep: want a tangle row was=\"$ht\" (HEAD) with ratchet=\"v1\" and why=best since v1: deep N->N+6 lines, got '${r:-none}'"; fi
if grep -q 'ratchet_ref="v1"' "$Q"; then ok "(r1) root ratchet_ref=\"v1\""; else no "(r1) root: no ratchet_ref=\"v1\""; fi
# (k1)-(k3): the ratchet against the range base; premise from HEAD's and the working tree's --metrics
read -r ht wt hl wl <<<"$( kpre grow1 )"; r="$( trow grow1 )"
if [ -z "$ht" ] || [ -z "$wt" ] || [ "${ht%.*}" -lt 6 ] || [ "${ht/./}" -ge "${wt/./}" ]; then no "(k1) PREMISE: grow1 over the bar and higher in wt, got HEAD=$ht wt=$wt"
elif [ -n "$r" ] && [ "$( attr "$r" was )" = "$ht" ] && [ "$( attr "$r" now )" = "$wt" ] && [ "$( attr "$r" gating )" = 1 ] && [ -z "$( attr "$r" ratchet )" ]; then
    ok "(k1) grow1 $ht -> $wt: a gating ratchet row, no ratchet= facet: $r"
else no "(k1) grow1 $ht -> $wt: want a gating tangle row was=\"$ht\" now=\"$wt\" without ratchet=, got '${r:-none}'"; fi
read -r ht wt hl wl <<<"$( kpre reflow )"
if [ -z "$ht" ] || [ "$ht" != "$wt" ] || [ "$hl" = "$wl" ] || [ "${ht%.*}" -lt 6 ]; then no "(k2) PREMISE: reflow over the bar, same score, lines moved; got $ht/$wt, $hl/$wl lines"
elif [ -z "$( trow reflow )" ]; then ok "(k2) reflow (S $ht, $hl -> $wl lines): no tangle row"
else no "(k2) reflow: want no tangle row (score unchanged), got $( trow reflow )"; fi
read -r ht wt hl wl <<<"$( kpre settle )"
if [ -z "$ht" ] || [ -z "$wt" ] || [ "${wt%.*}" -lt 6 ] || [ "${wt/./}" -ge "${ht/./}" ]; then no "(k3) PREMISE: settle over the bar and lower in wt, got HEAD=$ht wt=$wt"
elif [ -z "$( trow settle )" ] && ! grep -qE '<i kind="tangle" sym="[^"]*settle"' "$Q"; then ok "(k3) settle $ht -> $wt: no tangle row, no <improved> entry"
else no "(k3) settle $ht -> $wt: want no row and no credit, got row '$( trow settle )' / $( grep -oE '<i kind="tangle" sym="[^"]*settle"[^>]*>' "$Q" )"; fi
# (r2) / (c1)
if grep -qE '<i kind="tangle" sym="[^"]*shrink"' "$Q"; then ok "(r2) shrink credited in <improved>"; else no "(r2) shrink: no <i kind=\"tangle\"> entry"; fi
if [ -z "$( trow shrink )" ]; then ok "(r2) shrink: no tangle row"; else no "(r2) shrink: unexpected tangle row $( trow shrink )"; fi
grep -qE '<i kind="complexity" sym="[^"]*simplify" was="2[0-9]" now="1[0-9]"' "$Q" && ok "(c1) simplify credited in <improved> (complexity)" \
    || no "(c1) simplify: no <i kind=\"complexity\"> entry ($( grep -oE '<improved[^>]*>' "$Q" ))"
# (r4)
mg="$( mrow nudge )"
if [ -z "$mg" ] || [ -z "$( attr "$mg" tangle )" ] || [ "$( printf '%s' "$( attr "$mg" tangle )" | cut -d. -f1 )" -lt 6 ]; then
    no "(r4) PREMISE: nudge should be over the tangle bar in --metrics, got '${mg:-none}'"
elif grep -qE '<i kind="tangle" sym="[^"]*nudge"' "$Q"; then no "(r4) nudge: a 2-line fall credited: $( grep -oE '<i kind="tangle" sym="[^"]*nudge"[^>]*>' "$Q" )"
else ok "(r4) nudge (tangle=$( attr "$mg" tangle ), 2 deep lines fewer): no <improved> entry"; fi
# (r3)
if r="$( trow tangled )"; [ -n "$r" ] && [ -z "$( attr "$r" ratchet )" ]; then ok "(r3) tangled (new): no ratchet="; else no "(r3) tangled: want a row without ratchet=, got '${r:-none}'"; fi
# (g) only rule (b) gates: the gating tangle rows are exactly the new and crossing ones; every other tangle row is minor
gsyms="$( grep -oE '<r kind="tangle"[^>]*gating="1"[^>]*>' "$Q" | grep -oE ' sym="[^"]*"' | sed -E 's/.*(::|")([A-Za-z0-9_]+)"$/\2/' | sort | tr '\n' ' ' )"
tg="$( grep -oE '<r kind="tangle"[^>]*>' "$Q" | grep -c 'gating="1"' )"; tm="$( grep -oE '<r kind="tangle"[^>]*>' "$Q" | grep -c 'sev="minor"' )"
if [ "$tangles" -ge 3 ] && [ "$gsyms" = "creep crossing grow1 tangled " ] && [ $(( tg + tm )) = "$tangles" ]; then ok "(g) $tangles tangle row(s): gating $gsyms, the other $tm sev=\"minor\""
else no "(g) tangle rows $tangles: want gating exactly 'creep crossing grow1 tangled ', got '$gsyms' (gating $tg, minor $tm)"; fi
# (j) the JSON twin: the same tangle rows in "r" and an "improved" list
jt="$( python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for r in d["r"] if r.get("kind")=="tangle"), len(d.get("improved",[])))' "$TMP/qd.json" 2>/dev/null )"
if [ "${jt% *}" = "$tangles" ] && [ "${jt#* }" -ge 2 ]; then ok "(j) --json: ${jt% *} tangle row(s) and ${jt#* } improved entries"
else no "(j) --json: '$jt' (tangle rows, improved) vs XML $tangles rows"; fi
# (d)
if cmp -s "$Q" "$Q.2"; then ok "(d) two runs byte-identical"; else no "(d) two runs differ"; fi

# (p1) CR721 PIN UNITS: --quality-baseline on a dirty tree whose one gating row is a tangle (grow1 over the bar, growing) refuses
#      and names that row in the SAME display units as the --quality-delta row (was="10.5" now="10.9"), not raw tenths.
#      RED before CR721 (train GE3 cbed31d4c): "First: tangle grow1 (was=105 now=109)".
P="$TMP/pin"; mkdir -p "$P/src"; "${G[@]}" -C "$P" init -q
g1(){ python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import tanglefixtures as t; open(sys.argv[2], "w").write("#include <vector>\n" + t.overbar("grow1", int(sys.argv[3]), mult=17))' "$ROOT/test/lib" "$P/src/grow1.cpp" "$1"; }
g1 40; "${G[@]}" -C "$P" add -A && "${G[@]}" -C "$P" commit -qm v1; g1 42
pr="$( "$BIN" "$P" --quality-delta --no-cache 2>/dev/null | grep -oE '<r kind="tangle"[^>]*sym="grow1"[^>]*gating="1"[^>]*' )"   # status: the delta exits 2 on this gating row; an empty $pr FAILs the (p1) premise below
pw="$( attr "$pr" was )"; pn="$( attr "$pr" now )"
"$BIN" "$P" --quality-baseline --no-cache >/dev/null 2>"$TMP/pin.err"; prc=$?
first="$( tr '\n' ' ' <"$TMP/pin.err" | grep -oE 'First: [^)]*\)' )"
# CR721: BOTH values are display units (tenths as one decimal place: the fixture's was 40 -> now 42 calls both land in 10.x)
if [ -z "$pr" ] || ! printf '%s %s' "$pw" "$pn" | grep -qE '^[0-9]+\.[0-9] [0-9]+\.[0-9]$'; then no "(p1) PREMISE: want a gating tangle row on grow1 with decimal was= and now=, got '${pr:-none}'"
elif [ "$prc" = 1 ] && [ "$first" = "First: tangle grow1 (was=$pw now=$pn)" ]; then ok "(p1) the pin refusal names the tangle row in display units: $first"
else no "(p1) want rc 1 and 'First: tangle grow1 (was=$pw now=$pn)', got rc=$prc '$first'"; fi

[ "$fail" = 0 ] && echo "tanglecheck: PASS" || echo "tanglecheck: FAIL"
exit "$fail"
