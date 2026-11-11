#!/usr/bin/env bash
# pathfewestcheck.sh — among EQUAL-LENGTH --path chains the one with the fewest unproven hops prints, and the losing chain is never
# dropped silently (src/pathroute.h pathFewestUnproven, PATH-FEWEST-UNPROVEN).
#
# THE DEFECT (LD-2 django-07). `--for="path from Model.save to SQLInsertCompiler.execute_sql"` printed ONE chain, through
# QuerySet.aggregate -> Query.get_aggregation (3 by-name hops, hedged name-stitched), and it is false. The true chain
# save -> save_base -> _save_table -> _do_insert -> _insert -> execute_sql is also 5 hops, with 2 unproven: a by-name `manager._insert`
# and a DECLINED last call (cands=3) whose candidate list holds the to= definition. The plain BFS keeps the first chain it meets.
#
# THE CONTRACT (single-chain answers; a pairs answer keeps its own fewest-hedged ranking and gets only the test label):
#   * among chains of the found length, the minimum of (unproven hops, route_cands, test-path intermediates) prints; ties keep
#     today's chain byte for byte;
#   * the LAST hop may be a declined call whose stored candidate list holds the to= definition (by id), <= 3 candidates, not a
#     self-call, not builtin-spelled (the GV-ASSEMBLY met-bridge's crossing test, one predicate); its row says via="declined" cands=;
#   * a replaced chain says so on the root: route_tie="fewer-unproven|fewer-cands|source-first" route_tie_other=K (the plain
#     chain's unproven hops), with a legend clause only then;
#   * a shown chain with test-path intermediates (neither endpoint in tests) says route_tests=N; it is kept.
#
# ARMS
#   (T)  two 3-hop chains, the first found with 2 by-name hops, the other with 1: the 1-by-name chain prints, route_tie="fewer-unproven"
#        route_tie_other="2", no route_hedged= (1 unproven hop is below the hedge).
#   (T2) an inner tie: the better chain's pmid is reached from p1 and from p2 at equal keys: the first-found predecessor (p1) is kept.
#   (C2) the cpython-02 shape: a 3-hop chain of 3 by-name hops (cands 2 each) with no equal-length alternative: unchanged (hedged
#        name-stitched, no route_tie=); and (C2b) the better chain is the one found first: unchanged, no route_tie=.
#   (D)  the django-07 shape: the found 4-hop chain has 3 by-name hops; the other 4-hop chain's last call is declined (cands=2, its
#        list holds Sink.fin): the declined chain prints, its last row via="declined" cands="2", root route_declined="1"
#        route_tie="fewer-unproven" route_tie_other="3".
#   (D3) the same with cands=3 (the bound): the declined chain prints.
#   (DH) the django-07 verdict: the declined chain also carries one by-name hop (b1 -> BX.bx2): 2 unproven hops, so it stays HEDGED
#        (route_hedged="name-stitched" route_by_name="1" route_declined="1"): the declined hop counts in the verdict.
#   (D4) NEGATIVE: 4 candidates: unchanged (the by-name chain, no route_tie=, no via="declined").
#   (DX) NEGATIVE: a declined call (cands=2) at the right depth whose list does not hold to= (it names fin_x): unchanged.
#   (S)  source-first: two 3-hop chains equal on unproven hops and route_cands, the first found through tests/helper.py: the source
#        chain prints, route_tie="source-first".
#   (SL) the only chain runs through tests/: kept, route_tests="1".
#   (W)  increment 2, the django-07 tie: two 3-hop chains each ending on a declined call (cands=2, InsertCompiler.fin / UpdateCompiler.fin),
#        b_update defined first: the b_insert chain prints (its name shares "insert" with to='s owner InsertCompiler), route_equal="1"
#        discloses the equally proven b_update chain.
#   (W0) the same with no owner word in either name (b_one / b_two): the first found prints, route_equal="1".
#   (L)  the legend clauses (compact by default; full has its own) ride exactly when route_tie= / route_declined= / route_tests= do; every answer parses (xmllint).
#   (M)  MCP path_between carries the CLI's root attributes and rows on T, D and SL.
#   (F)  --for "path from start_entry to Sink.fin" on D: the <graph_verb> block's <path> is the declined chain.
#
# Usage: test/pathfewestcheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "pathfewestcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
mkdir -p "$TMP/home"

# (T) / (C2b): start_entry -> aa_first -> W.wmid -> Sink.fin (2 by name) and start_entry -> bb_second -> pmid -> Sink.fin (1 by name).
# The BFS expands targets in id order, so the chain whose first hop is defined first is the one it finds.
tie_fixture(){ local d=$1 first=$2 second=$3; mkdir -p "$TMP/$d"; cat > "$TMP/$d/m.py" <<EOF
def start_entry(o):
    ${first}(o)
    ${second}(o)

def aa_first(o):
    return o.wmid(o)

class W:
    def wmid(self, o):
        return o.fin(o)

def bb_second(o):
    return pmid(o)

def pmid(o):
    return o.fin(o)

class Sink:
    def fin(self, o):
        return 1
EOF
}
tie_fixture t aa_first bb_second
# (T2): start_entry -> aa_first -> W.wmid -> Sink.fin first; start_entry -> p1 | p2 -> pmid -> Sink.fin (1 by name), p1 found before p2
mkdir -p "$TMP/t2"; sed -e 's/^    bb_second(o)$/    p1(o)\n    p2(o)/' -e 's/^def bb_second(o):$/def p1(o):\n    return pmid(o)\n\ndef p2(o):/' "$TMP/t/m.py" > "$TMP/t2/m.py"
# (C2b): the 1-by-name chain is defined first, so the BFS already finds it
mkdir -p "$TMP/c2b"; sed -e 's/^def aa_first/def zz_first/' -e 's/    aa_first(o)/    zz_first(o)/' -e 's/^def bb_second/def ab_second/' -e 's/    bb_second(o)/    ab_second(o)/' "$TMP/t/m.py" > "$TMP/c2b/m.py"
python3 - "$TMP/c2b/m.py" <<'PYEOF'
import sys
p = sys.argv[1]; t = open(p).read()
# ab_second's block before zz_first's so its id is lower
a = t.index("def zz_first"); b = t.index("class W:"); zz = t[a:b]; t = t[:a] + t[b:]
c = t.index("class Sink:"); t = t[:c] + zz + t[c:]
open(p, "w").write(t)
PYEOF
# (C2) the cpython-02 shape: three by-name hops, two same-named classes per hop, no equal-length alternative
mkdir -p "$TMP/c2"; cat > "$TMP/c2/m.py" <<'EOF'
class A1:
    def s1(self, o):
        return o.s2(o)
class B1:
    def s1(self, o):
        return 0
class A2:
    def s2(self, o):
        return o.fin(o)
class B2:
    def s2(self, o):
        return 0
class Sink:
    def fin(self, o):
        return 1
class Decoy:
    def fin(self, o):
        return 2
def start_entry(o):
    return o.s1(o)
EOF
# (D*) app/m.py: start_entry -> a1 -> W.w2 -> W.w3 -> Sink.fin (3 by name, lib/ is the candidates' directory) and
# start_entry -> b1 -> b2 -> b3 -> Sink.fin, b3's `o.<callee>(o)` DECLINED (its candidates are all in lib/, none in app/).
decl_fixture(){ local d=$1 n=$2 callee=$3; mkdir -p "$TMP/$d/app" "$TMP/$d/lib"; cat > "$TMP/$d/app/m.py" <<EOF
def start_entry(o):
    a1(o)
    b1(o)

def a1(o):
    return o.w2(o)

def b1(o):
    return b2(o)

def b2(o):
    return b3(o)

def b3(o):
    return o.${callee}(o)
EOF
    { printf 'class W:\n    def w2(self, o):\n        return o.w3(o)\n    def w3(self, o):\n        return o.fin(o)\n\n'
      printf 'class Sink:\n    def fin(self, o):\n        return 1\n\n'
      for i in $( seq 2 "$n" ); do printf 'class Other%s:\n    def fin(self, o):\n        return %s\n    def fin_x(self, o):\n        return %s\n\n' "$i" "$i" "$i"; done; } > "$TMP/$d/lib/k.py"
}
decl_fixture d 2 fin
decl_fixture d3 3 fin
decl_fixture d4 4 fin
decl_fixture dh 2 fin
python3 - "$TMP/dh/app/m.py" <<'PYEOF'
import sys
p = sys.argv[1]; t = open(p).read()
t = t.replace("def b1(o):\n    return b2(o)\n", "def b1(o):\n    return o.bx2(o)\n\nclass BX:\n    def bx2(self, o):\n        return b3(o)\n")
open(p, "w").write(t)
PYEOF
decl_fixture dx 3 fin_x   # two fin_x definitions: b3's call is DECLINED, its list [Other2.fin_x, Other3.fin_x] does not hold Sink.fin
# (S) / (SL): start_entry -> a1 -> tests/helper.py:th -> Sink.fin and start_entry -> b1 -> core/zz.py:ph -> Sink.fin (each 1 by name)
src_fixture(){ local d=$1 withSource=$2; mkdir -p "$TMP/$d/tests" "$TMP/$d/core"
    printf 'from tests.helper import th\nfrom core.zz import ph\n\ndef start_entry(o):\n    a1(o)\n    b1(o)\n\ndef a1(o):\n    return th(o)\n\ndef b1(o):\n    return %s\n' \
        "$( [ "$withSource" = 1 ] && echo 'ph(o)' || echo '0' )" > "$TMP/$d/core/m.py"
    printf 'def th(o):\n    return o.fin(o)\n' > "$TMP/$d/tests/helper.py"
    printf 'def ph(o):\n    return o.fin(o)\n\nclass Sink:\n    def fin(self, o):\n        return 1\n' > "$TMP/$d/core/zz.py"
}
src_fixture s 1
src_fixture sl 0
# (W) / (W0): start_entry -> a1 -> W.w2 -> InsertCompiler.fin (2 by name) and start_entry -> b1 -> {first, second} -> fin (declined)
word_fixture(){ local d=$1 first=$2 second=$3; mkdir -p "$TMP/$d/app" "$TMP/$d/lib"
    printf 'def start_entry(o):\n    a1(o)\n    b1(o)\n\ndef a1(o):\n    return o.w2(o)\n\ndef b1(o):\n    %s(o)\n    %s(o)\n\ndef %s(o):\n    return o.fin(o)\n\ndef %s(o):\n    return o.fin(o)\n' \
        "$first" "$second" "$first" "$second" > "$TMP/$d/app/m.py"
    printf 'class W:\n    def w2(self, o):\n        return o.fin(o)\n\nclass InsertCompiler:\n    def fin(self, o):\n        return 1\n\nclass UpdateCompiler:\n    def fin(self, o):\n        return 2\n' > "$TMP/$d/lib/k.py"
}
word_fixture w b_update b_insert
word_fixture w0 b_one b_two

run(){ local d=$1; shift; ( cd "$TMP/$d" || exit 1; env -u RIPWIRE_LEGEND HOME="$TMP/home" "$BIN" "$TMP/$d" --no-cache "$@" < /dev/null 2>/dev/null ); }
root(){ grep -o '<path [^>]*>' | head -1; }
attr(){ local a=$1; root | python3 -c 'import re,sys; m=re.search(r" '"$a"'=\"([^\"]*)\"",sys.stdin.read()); print(m.group(1) if m else "")'; }
rows(){ python3 -c 'import re,sys
t=sys.stdin.read(); m=re.search(r"<path [^>]*>(.*?)</path>",t,re.S); b=m.group(1) if m else ""
print(" ".join(re.findall(r"<s [^>]*n=\"([^\"]*)\"",b)))'; }
lastrow(){ python3 -c 'import re,sys
t=sys.stdin.read(); m=re.search(r"<path [^>]*>(.*?)</path>",t,re.S); r=re.findall(r"<s [^>]*/>",m.group(1) if m else ""); print(r[-1] if r else "")'; }
legend(){ python3 -c 'import re,sys; m=re.search(r"<!-- ripwire path[ :](.*?)-->",sys.stdin.read(),re.S); print(m.group(1) if m else "")'; }

check(){ # arm out want_rows want_tie want_other want_declined want_tests [want_hedged]
    local arm=$1 out=$2 wr=$3 wt=$4 wo=$5 wd=$6 ws=$7 wh=${8-}
    local gr gt go gd gs gh
    gr="$( rows <<<"$out" )"; gt="$( attr route_tie <<<"$out" )"; go="$( attr route_tie_other <<<"$out" )"
    gd="$( attr route_declined <<<"$out" )"; gs="$( attr route_tests <<<"$out" )"; gh="$( attr route_hedged <<<"$out" )"
    if [ "$gr" = "$wr" ] && [ "$gt" = "$wt" ] && [ "$go" = "$wo" ] && [ "$gd" = "$wd" ] && [ "$gs" = "$ws" ] && [ "$gh" = "$wh" ]; then
        ok "($arm) rows [$gr] route_tie=[$gt] other=[$go] declined=[$gd] tests=[$gs] hedged=[$gh]"
    else
        no "($arm) got rows [$gr] route_tie=[$gt] other=[$go] declined=[$gd] tests=[$gs] hedged=[$gh]; want [$wr] [$wt] [$wo] [$wd] [$ws] [$wh]"
    fi
}

T="$( run t --path=start_entry,Sink.fin )"
check T "$T" "start_entry bb_second pmid Sink.fin" fewer-unproven 2 "" ""
T2="$( run t2 --path=start_entry,Sink.fin )"
check T2 "$T2" "start_entry p1 pmid Sink.fin" fewer-unproven 2 "" ""
C2="$( run c2 --path=start_entry,Sink.fin )"
check C2 "$C2" "start_entry A1.s1 A2.s2 Sink.fin" "" "" "" "" name-stitched
C2B="$( run c2b --path=start_entry,Sink.fin )"
check C2b "$C2B" "start_entry ab_second pmid Sink.fin" "" "" "" ""
D="$( run d --path=start_entry,Sink.fin )"
check D "$D" "start_entry b1 b2 b3 Sink.fin" fewer-unproven 3 1 ""
last="$( lastrow <<<"$D" )"
if grep -qF 'via="declined"' <<<"$last" && grep -qF 'cands="2"' <<<"$last" && grep -qF 'n="Sink.fin"' <<<"$last"; then
    ok "(D) the declined hop's row says via=\"declined\" cands=\"2\""
else
    no "(D) declined row: $last"
fi
D3="$( run d3 --path=start_entry,Sink.fin )"
check D3 "$D3" "start_entry b1 b2 b3 Sink.fin" fewer-unproven 3 1 ""
DH="$( run dh --path=start_entry,Sink.fin )"
check DH "$DH" "start_entry b1 BX.bx2 b3 Sink.fin" fewer-unproven 3 1 "" name-stitched
if [ "$( attr route_by_name <<<"$DH" )" = 1 ]; then ok "(DH) route_by_name=\"1\" beside route_declined=\"1\""; else no "(DH) route_by_name=[$( attr route_by_name <<<"$DH" )]"; fi
D4="$( run d4 --path=start_entry,Sink.fin )"
check D4 "$D4" "start_entry a1 W.w2 W.w3 Sink.fin" "" "" "" "" name-stitched
if grep -qF 'via="declined"' <<<"$D4"; then no "(D4) a via=\"declined\" row with 4 candidates"; else ok "(D4) no declined row past 3 candidates"; fi
DX="$( run dx --path=start_entry,Sink.fin )"
check DX "$DX" "start_entry a1 W.w2 W.w3 Sink.fin" "" "" "" "" name-stitched
S="$( run s --path=start_entry,Sink.fin )"
check S "$S" "start_entry b1 ph Sink.fin" source-first 1 "" ""
SL="$( run sl --path=start_entry,Sink.fin )"
check SL "$SL" "start_entry a1 th Sink.fin" "" "" "" 1
W="$( run w --path=start_entry,InsertCompiler.fin )"
check W "$W" "start_entry b1 b_insert InsertCompiler.fin" fewer-unproven 2 1 ""
if [ "$( attr route_equal <<<"$W" )" = 1 ]; then ok "(W) route_equal=\"1\" discloses the equally proven b_update chain"; else no "(W) route_equal=[$( attr route_equal <<<"$W" )]"; fi
W0="$( run w0 --path=start_entry,InsertCompiler.fin )"
check W0 "$W0" "start_entry b1 b_one InsertCompiler.fin" fewer-unproven 2 1 ""
if [ "$( attr route_equal <<<"$W0" )" = 1 ]; then ok "(W0) route_equal=\"1\""; else no "(W0) route_equal=[$( attr route_equal <<<"$W0" )]"; fi

# (L) legends ride exactly with their attributes; well-formed
lfail=0
for a in T T2 C2 C2B D D3 DH D4 DX S SL W W0; do
    out="${!a}"; lg="$( legend <<<"$out" )"
    for pair in "route_tie:route_tie=" "route_declined:route_declined=1" "route_tests:route_tests=N" "route_equal:route_equal=N"; do
        at="${pair%%:*}"; cl="${pair#*:}"
        has="$( attr "$at" <<<"$out" )"
        if [ -n "$has" ] && ! grep -qF "$cl" <<<"$lg"; then no "(L) $a: $at= without its legend clause"; lfail=1; fi
        if [ -z "$has" ] && grep -qF "$cl" <<<"$lg"; then no "(L) $a: the $at legend clause without $at="; lfail=1; fi
    done
    if command -v xmllint >/dev/null 2>&1 && ! xmllint --noout - <<<"$out" 2>/dev/null; then no "(L) $a: not well-formed"; lfail=1; fi
done
[ "$lfail" = 0 ] && ok "(L) every clause rides exactly with its attribute; every answer parses"
DF="$( run d --path=start_entry,Sink.fin --legend=full )"; SLF="$( run sl --path=start_entry,Sink.fin --legend=full )"; CF="$( run c2 --path=start_entry,Sink.fin --legend=full )"
if grep -qF 'route_tie=fewer-unproven|fewer-cands|source-first|owner-word route_tie_other=K: the plain search' <<<"$( legend <<<"$DF" )" \
   && grep -qF 'route_declined=1: the last row' <<<"$( legend <<<"$DF" )" && grep -qF 'route_tests=N: N intermediate rows' <<<"$( legend <<<"$SLF" )" \
   && ! grep -qE 'route_tie=|route_declined=|route_tests=' <<<"$( legend <<<"$CF" )"; then
    ok "(L) --legend=full carries the full clauses exactly when they fire"
else
    no "(L) --legend=full clauses: D/SL missing one, or C2 carries one"
fi

# (M) MCP path_between
mcp(){ local d=$1 f=$2 t=$3; printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"g","version":"0"}}}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"path_between\",\"arguments\":{\"path\":\"$TMP/$d\",\"from\":\"$f\",\"to\":\"$t\"}}}" \
    | ( cd "$TMP/$d" || exit 1; HOME="$TMP/home" "$BIN" --mcp --mcp-legend=inline 2>/dev/null ) | python3 -c 'import json,sys
for l in sys.stdin:
    try: m=json.loads(l)
    except Exception: continue
    if m.get("id")==2: print("".join(c.get("text","") for c in m.get("result",{}).get("content",[])))'; }
for a in T D SL; do
    if [ "$a" = T ]; then cli="$T"; d=t; elif [ "$a" = D ]; then cli="$D"; d=d; else cli="$SL"; d=sl; fi
    m="$( mcp "$d" start_entry Sink.fin )"
    same=1
    for at in route_tie route_tie_other route_declined route_tests route_hedged reachable hops; do
        [ "$( attr "$at" <<<"$m" )" = "$( attr "$at" <<<"$cli" )" ] || same=0
    done
    [ "$( rows <<<"$m" )" = "$( rows <<<"$cli" )" ] && [ "$( lastrow <<<"$m" )" = "$( lastrow <<<"$cli" )" ] || same=0
    if [ "$same" = 1 ]; then ok "(M) $a: path_between carries the CLI's root attributes and rows"; else no "(M) $a: MCP $( root <<<"$m" ) vs CLI $( root <<<"$cli" )"; fi
done

# (F) --for graph_verb block on D
F="$( run d '--for=path from start_entry to Sink.fin' )"
blk="$( python3 -c 'import re,sys; t=sys.stdin.read(); m=re.search(r"<graph_verb[^>]*>.*?</graph_verb>",t,re.S); print(m.group(0) if m else "")' <<<"$F" )"
if [ -n "$blk" ] && [ "$( rows <<<"$blk" )" = "start_entry b1 b2 b3 Sink.fin" ] && [ "$( attr route_tie <<<"$blk" )" = fewer-unproven ] \
   && grep -qF 'via="declined"' <<<"$( lastrow <<<"$blk" )"; then
    ok "(F) the --for <graph_verb> block prints the declined chain with route_tie="
else
    no "(F) graph_verb path: $( root <<<"$blk" ) rows [$( rows <<<"$blk" )]"
fi
[ "$fail" = 0 ] && echo "pathfewestcheck: PASS" || echo "pathfewestcheck: FAIL"
exit "$fail"
