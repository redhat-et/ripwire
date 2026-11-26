#!/usr/bin/env bash
# tanglecapcheck.sh — TANGLE-RULE gate: the R-D false-positive rule on the QD-TANGLE score, and the same-rule baseline it needs
# (tmp/orch-1124/tangle-fp/RESULT.md; model.h tangleScore10, ingest_metrics.h tangleBlocks_*, quality.h appendTangleRows).
#
#   S' = min( S, worst top-level block's S + 2 per cross local ), and test code never gets a tangle row (F5).
#
# Fixtures: test/lib/tanglecapfixtures.py, each a reduced copy of a row labelled blind in tangle-fp/labels.tsv. One repo, v1
# committed, the working tree judged against HEAD; then the same history judged against a pinned floor WITHOUT block facts (the
# sidecar an older binary wrote).
#   (f1) FP REMOVED: famswitch (ripwire harvest), twoarms (sliceEmitBody), lambdasteps (envoy evictUnused), resolver (envoy
#        build_resolver, Rust), addressarms (twoarms plus record locals that one arm only asks `r.address()`: a verb prefix is a
#        word, so no write and no cross local): over the bar before the cap (tangle_raw= >= 6 in --metrics, the premise), under
#        it after, no row.
#   (f2) TEST CODE: the REAL statethread body under test/ (a harness main, an integration *_test.cc, a test_data file): over the
#        bar in --metrics (the premise), no tangle row. (f3) BENCH IS SOURCE: the same body under bench/ keeps its gating row.
#   (k1) REAL KEPT: statethread (pathReachingPairs: shallow, state threaded), deepmono (captureTagsFacts: deep throughout),
#        hdrparse (envoy parseHeader, the thin margin), refheader (parseHeader's reference local `T& header` threading the
#        guard blocks into the scanner: kept only because that slot counts): tangle >= 6 in --metrics and a gating new-symbol row
#        each.
#   (u1) KNOWN residual (out of scope, report-only): solelambda (a callback lambda as the whole body), initable (a table).
#   (q1) WORSE BY STATE: crossgrow (over the bar, the cap not binding) threads one more local across blocks by editing an existing
#        line: the score is HEAD's (premise), crossLocals +1 is the rise: a row, why= names "cross". It is sev="minor": a rising
#        input whose score did not grow does not gate (owner 11-21, tangleCauseGates). Red on the pre-rule binary (no row).
#        crossgrowgo is the same in Go with the local declared `var bias int` (a var spec is a top-level slot as `:=` is).
#   (q2) WORSE BY DEPTH: ruleworse (+6 deep lines): a gating row.
#   (q3) UNCHANGED: ruleonly (an FP shape, body identical at HEAD): no row, no <improved> entry.
#   (q4) OLD FLOOR, ONE RULE: the same history against a --quality-baseline floor whose block facts are stripped (the sidecar an
#        older binary wrote; premise: the pinned sidecar had tanglecap lines, the stripped one has none, the answer says
#        baseline="sidecar"). Scored by one rule on both sides (uncapped), the cap's discount is never a fall and never a cover:
#        (q4a) capworse (an FP shape, +6 deep lines; capped under the bar in wt, the premise) gets a GATING row — the regression
#              is not hidden behind the head's discount. Red on an ablation that scores the floor uncapped and the head capped.
#        (q4b) ruleonly, its body unchanged, whose floor line is rewritten to deep +6 (an older binary that measured the same body
#              differently; premise: exactly one line rewritten): no row, no <improved> entry — credit only for a real code
#              change (the body-identity guard). Red on an ablation without the guard.
#        (q4c) ruleflat (a constant edited: the body changed, every input the same) gets no row and no credit; ruleworse still gates.
#   (m1) MUST KEEP, main's sources: the 6 #721 parents (captureTagsFacts, lexicalScoresTiered, serialize, runQualityDelta,
#        compressBody, serializeJson) plus buildGraph and dispatchMcpLine stay over the bar on ripwire main 696d57a67 (the
#        labelled commit). Premise: the commit is reachable (CI clones with fetch-depth 0) and each name has a tangle= row.
# Every negative arm counts its premise first and FAILS on zero (gate-premise rule).
# Usage: test/tanglecapcheck.sh [BIN]
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
echo "tanglecapcheck: BIN=$BIN"
G=( git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c tag.gpgsign=false )
FX="$ROOT/test/lib/tanglecapfixtures.py"

R="$TMP/repo"; mkdir -p "$R"; "${G[@]}" -C "$R" init -q
python3 "$FX" v1 "$R" || { echo "fixture writer failed"; exit 2; }
"${G[@]}" -C "$R" add -A && "${G[@]}" -C "$R" commit -qm v1
mkdir -p "$TMP/head" && "${G[@]}" -C "$R" archive HEAD | tar -x -C "$TMP/head"
python3 "$FX" wt "$R" || { echo "fixture writer failed"; exit 2; }

Q="$TMP/qd.xml"
"$BIN" "$R" --quality-delta --no-cache >"$Q" 2>"$Q.err"; rc=$?
M="$( "$BIN" "$R" --metrics --page-bytes=0 --no-cache 2>/dev/null )"; rcm=$?
MH="$( "$BIN" "$TMP/head" --metrics --page-bytes=0 --no-cache 2>/dev/null )"; rcmh=$?
case "$rc" in 0|2) ;; *) no "quality-delta exit status $rc (stderr: $( head -c 300 "$Q.err" ))";; esac
if [ "$rcm" != 0 ] || [ "$rcmh" != 0 ]; then no "--metrics exit status $rcm (working tree), $rcmh (HEAD)"; fi

trow(){ grep -oE "<r kind=\"tangle\" sym=\"[^\"]*$2\"[^>]*>" "$1" | head -1; }
irow(){ grep -oE "<i kind=\"tangle\" sym=\"[^\"]*$2\"[^>]*>" "$1" | head -1; }
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E "s/.*=\"([^\"]*)\"/\1/"; }
mrow(){ printf '%s' "$M" | tr '>' '\n' | grep "n=\"$1\"" | head -1; }
hrow(){ printf '%s' "$MH" | tr '>' '\n' | grep "n=\"$1\"" | head -1; }
over(){ [ -n "$1" ] && [ "${1%.*}" -ge 6 ]; }   # a tangle value (one decimal) at or over the bar

# (f1) FP removed by the cap
for f in famswitch twoarms lambdasteps resolver addressarms; do
    m="$( mrow "$f" )"; raw="$( attr "$m" tangle_raw )"; t="$( attr "$m" tangle )"
    if [ -z "$m" ] || ! over "$raw"; then no "(f1) PREMISE: $f should be over the bar before the cap (tangle_raw >= 6) in --metrics, got '${m:-none}'"
    elif over "$t"; then no "(f1) $f: the cap left it over the bar: tangle=$t tangle_raw=$raw"
    elif [ -n "$( trow "$Q" "$f" )" ]; then no "(f1) $f: want no tangle row, got $( trow "$Q" "$f" )"
    else ok "(f1) $f: tangle ${t:-0} (was $raw before the cap), no row"; fi
done
# (f2) test code / (f3) bench
for f in harnessmain mergeLoadStats onTick; do
    m="$( mrow "$f" )"; t="$( attr "$m" tangle )"
    if [ -z "$m" ] || ! over "$t"; then no "(f2) PREMISE: $f (test code) should be over the bar in --metrics, got '${m:-none}'"
    elif [ -n "$( trow "$Q" "$f" )" ]; then no "(f2) $f (test code): want no tangle row, got $( trow "$Q" "$f" )"
    else ok "(f2) $f (test code, tangle=$t): no row"; fi
done
r="$( trow "$Q" benchmain )"
if [ -n "$r" ] && [ "$( attr "$r" gating )" = 1 ] && attr "$r" p | grep -q '^bench/'; then ok "(f3) benchmain under bench/ (source): a gating row: $r"
else no "(f3) benchmain under bench/: want a gating tangle row (bench is not test), got '${r:-none}'"; fi
# (k1) REAL kept
for f in statethread deepmono hdrparse refheader; do
    m="$( mrow "$f" )"; t="$( attr "$m" tangle )"; r="$( trow "$Q" "$f" )"
    if [ -z "$m" ]; then no "(k1) PREMISE: $f missing from --metrics"
    elif over "$t" && [ -n "$r" ] && [ "$( attr "$r" gating )" = 1 ]; then ok "(k1) $f (REAL): tangle=$t, a gating row"
    else no "(k1) $f (REAL): want tangle >= 6 and a gating row, got tangle=${t:-0} row='${r:-none}'"; fi
done
# (u1) known residual, report-only
for f in solelambda initable; do
    m="$( mrow "$f" )"; printf '  KNOWN %s: tangle=%s tangle_raw=%s (out of scope: %s)\n' "$f" "$( attr "$m" tangle )" "$( attr "$m" tangle_raw )" \
        "$( [ "$f" = solelambda ] && echo 'a callback lambda as the whole body' || echo 'a lookup-table initializer' )"
done
# (q1) worse by state: crossLocals +1, the score unchanged
for f in crossgrow crossgrowgo; do
ht="$( attr "$( hrow "$f" )" tangle )"; wt="$( attr "$( mrow "$f" )" tangle )"; r="$( trow "$Q" "$f" )"
if ! over "$ht" || [ "$ht" != "$wt" ]; then no "(q1) PREMISE: $f over the bar with the same score at HEAD and in wt, got $ht -> $wt"
elif [ -n "$r" ] && [ "$( attr "$r" sev )" = minor ] && [ -z "$( attr "$r" gating )" ] && attr "$r" why | grep -qE 'cross [0-9]+-&gt;[0-9]+'; then
    ok "(q1) $f (S $ht -> $wt, one more cross local): a minor row: $r"
else no "(q1) $f: want a sev=\"minor\" row (a rising input, the score not grown) whose why= names cross N->N+1, got '${r:-none}'"; fi
done
# (q2) worse by depth
r="$( trow "$Q" ruleworse )"
if [ -n "$r" ] && [ "$( attr "$r" gating )" = 1 ]; then ok "(q2) ruleworse (+6 deep lines): gating row"; else no "(q2) ruleworse: want a gating row, got '${r:-none}'"; fi
# (q3) unchanged
m="$( mrow ruleonly )"
if [ -z "$m" ] || ! over "$( attr "$m" tangle_raw )"; then no "(q3) PREMISE: ruleonly over the bar before the cap, got '${m:-none}'"
elif [ -z "$( trow "$Q" ruleonly )" ] && [ -z "$( irow "$Q" ruleonly )" ]; then ok "(q3) ruleonly (unchanged): no row, no <improved> entry"
else no "(q3) ruleonly: want no row and no credit, got '$( trow "$Q" ruleonly )' / '$( irow "$Q" ruleonly )'"; fi

# (q4) the old floor: pin v1 with --quality-baseline, strip its block facts, judge the working tree
O="$TMP/old"; mkdir -p "$O"; "${G[@]}" -C "$O" init -q
python3 "$FX" v1 "$O" || { echo "fixture writer failed"; exit 2; }
"${G[@]}" -C "$O" add -A && "${G[@]}" -C "$O" commit -qm v1
"$BIN" "$O" --quality-baseline --no-cache >/dev/null 2>"$TMP/pin.err"; prc=$?
SC="$O/.ripwire_quality_baseline"
capl="$( grep -c '^tanglecap' "$SC" 2>/dev/null )"; capl="${capl:-0}"
# ruleonly at v1: loc 93, nest 5, deep 40, steer 0 (packTangle: loc<<32 | nest<<24 | deep<<8 | steer) -> the same body measured
# with deep 46
old1="$( printf '%x' $(( (93 << 32) | (5 << 24) | (40 << 8) )) )"; new1="$( printf '%x' $(( (93 << 32) | (5 << 24) | (46 << 8) )) )"
hit="$( grep -cE "^tangle [0-9a-f]+ $old1\$" "$SC" 2>/dev/null )"; hit="${hit:-0}"
if [ "$prc" = 0 ] && [ -f "$SC" ]; then grep -v '^tanglecap' "$SC" | sed -E "s/^(tangle [0-9a-f]+) $old1\$/\1 $new1/" >"$SC.old" && mv "$SC.old" "$SC"; fi
left="$( grep -c '^tanglecap' "$SC" 2>/dev/null )"; left="${left:-0}"
python3 "$FX" wt "$O" || { echo "fixture writer failed"; exit 2; }
Q4="$TMP/qd4.xml"
"$BIN" "$O" --quality-delta --no-cache >"$Q4" 2>/dev/null
src="$( grep -oE '<quality-delta [^>]*' "$Q4" | grep -oE ' baseline="[^"]*"' )"
mc="$( mrow capworse )"
if [ "$prc" != 0 ] || [ "$capl" -lt 1 ] || [ "$left" != 0 ] || [ "$src" != ' baseline="sidecar"' ] || [ "$hit" != 1 ]; then
    no "(q4) PREMISE: pin rc=$prc, tanglecap lines pinned $capl (want >= 1) / left $left (want 0), ruleonly floor lines rewritten $hit (want 1), answer$src (want baseline=\"sidecar\"); $( head -c 200 "$TMP/pin.err" )"
elif [ -z "$mc" ] || over "$( attr "$mc" tangle )" || ! over "$( attr "$mc" tangle_raw )"; then
    no "(q4a) PREMISE: capworse should be under the bar capped and over it uncapped in wt, got '${mc:-none}'"
else
    r="$( trow "$Q4" capworse )"
    if [ -n "$r" ] && [ "$( attr "$r" gating )" = 1 ]; then ok "(q4a) capworse (+6 deep lines, capped $( attr "$mc" tangle ) in wt) against the old floor: a gating row: $r"
    else no "(q4a) capworse against the old floor: want a gating row (scored uncapped on both sides), got '${r:-none}'"; fi
    if [ -z "$( trow "$Q4" ruleonly )" ] && [ -z "$( irow "$Q4" ruleonly )" ]; then ok "(q4b) ruleonly (body unchanged, floor measured deep +6): no row, no <improved> entry"
    else no "(q4b) ruleonly (body unchanged): want no row and no credit, got '$( trow "$Q4" ruleonly )' / '$( irow "$Q4" ruleonly )'"; fi
    if [ -z "$( trow "$Q4" ruleflat )" ] && [ -z "$( irow "$Q4" ruleflat )" ]; then ok "(q4c) ruleflat against the old floor: no row, no <improved> entry"
    else no "(q4c) ruleflat against the old floor: want no row and no credit, got '$( trow "$Q4" ruleflat )' / '$( irow "$Q4" ruleflat )'"; fi
    r="$( trow "$Q4" ruleworse )"
    if [ -n "$r" ] && [ "$( attr "$r" gating )" = 1 ]; then ok "(q4c) ruleworse against the old floor: still a gating row"
    else no "(q4c) ruleworse against the old floor: want a gating row, got '${r:-none}'"; fi
fi

# (m1) must-keep rows on main's labelled sources
MAIN=696d57a67
if ! git -C "$ROOT" cat-file -e "$MAIN^{commit}" 2>/dev/null; then no "(m1) PREMISE: commit $MAIN not reachable (fetch full history)"
else
    MS="$TMP/main"; mkdir -p "$MS"
    git -C "$ROOT" archive "$MAIN" src/graph.h src/ingest_sidecap.h src/mcp.h src/lexical.h src/serialize.h src/verbs_quality.h | tar -x -C "$MS"
    MM="$( "$BIN" "$MS" --metrics --top-k=100000 --no-cache 2>/dev/null | tr '>' '\n' )"
    for f in captureTagsFacts lexicalScoresTiered serialize runQualityDelta compressBody serializeJson buildGraph dispatchMcpLine; do
        t="$( printf '%s\n' "$MM" | grep "n=\"$f\"" | grep -oE ' tangle="[0-9.]+"' | sed -E 's/[^0-9.]//g' | sort -n | tail -1 )"   # the largest overload
        if [ -z "$t" ]; then no "(m1) PREMISE: $f has no tangle= row on main $MAIN"
        elif over "$t"; then ok "(m1) $f on main $MAIN: tangle=$t (over the bar)"
        else no "(m1) $f on main $MAIN: the rule pulled it under the bar: tangle=$t"; fi
    done
fi

[ "$fail" = 0 ] && echo "tanglecapcheck: PASS" || echo "tanglecapcheck: FAIL"
exit "$fail"
