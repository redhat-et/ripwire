#!/usr/bin/env bash
# cochangetailcheck.sh — a ONE-seed co-change list fills to 10 with 2-commit partners that something else corroborates.
#
# WHY. The co-change backtest (bench/cochange) asked for the partners of one file of a real commit and scored whether they
# named the commit's other files. Lowering the support floor from 3 shared commits to 2 raised Hit@10 on all four repos and
# cut the share of listed partners that were real on three (decision_rule_4repo: no ship). Owner ruling 2026-11-26: keep the
# floor of 3, and fill a one-seed list with a 2-commit partner only when it is corroborated — (C) it moved in at least half
# of the seed's commits, or (S) the code links the two files: an include/import or call edge either way, a test-of pair, or
# the same small directory (20 indexed files or fewer). The tail ranks below every 3-commit partner and only fills to 10.
#
# RED-FIRST: arms 1-8 fail on a binary without the tail (no 2-commit row, no why=, no floor_tail=). Arms 5 and 7 carry
# prohibitions (a rejected pair is not listed; fill displaces nothing), and each also requires the rows and the floor_tail=
# that must be there, so neither passes on an answer without the tail. Arm 9 is the multi-seed guard and holds on the base
# too. Arms 10-11 (determinism, well-formedness) hold on any binary.
#
# Fixture R (src/ is small; every pair below shares exactly the stated commits; the bulk "init" commit is over 30 files and
# is left out of every co-change miner, so it adds nothing):
#   seed src/a.c has 5 commits. other/c.c shares 3 (support). Each of these shares 2 (confidence 0.4, under C):
#     lib/k.c   — a.c calls k_func, defined there         (S: call edge)
#     lib/l.h   — a.c includes it                         (S: include edge)
#     src/s.c   — a.c's directory, 2 indexed files         (S: same small directory)
#     test/a_test.c — a.c's test by name                  (S: test-of pair)
#     other/u.c — nothing links it                        (rejected)
#   seed solo/q.c has 3 commits; other2/r.c shares 2 (confidence 0.67: C).
#   big/a.c sits in a directory of 22 indexed files; big/p.c shares 2 of its 5 commits (same directory, but not small: rejected).
# Fixture W (fill): seed w/a.c (3 commits) with 9 partners at 3 commits and 3 at 2 (all corroborated) — the list is 9 + 1.
#
# Arms:
#   1. --cochange=src/a.c: c.c (why=support) first, then lib/k.c, lib/l.h, src/s.c, test/a_test.c (why=link), path order
#   2. --cochange=solo/q.c lists other2/r.c with why="confidence"
#   3. the answer says floor_tail="corroborated" and floor="3"; the compact and full legends define floor_tail= and why=
#   4. --situ=src/a.c: the same rows, each ", together=N, why=W"; the header floor_tail="corroborated"
#   5. rejected: other/u.c (uncorroborated) and big/p.c (directory over 20 files) are listed nowhere, beside the rows that are
#   6. --pack-task with one seed (solo/q.c): <partners floor_tail="corroborated"> lists other2/r.c why="confidence"; JSON agrees
#   7. fill never displaces: fixture W lists its 9 support rows first and exactly 1 tail row (10 in all), 2 eligible ones left out
#   8. MCP: cochange(src/a.c) rows carry "why" and the root "floor_tail"; situational_awareness(src/a.c) the same on forgotten
#   9. several seeds are unchanged: --situ=src/a.c,solo/q.c and a two-seed --pack-task list no 2-commit row, carry no
#      floor_tail= and no why=, and still list c.c
#  10. deterministic: two runs of each answer are byte-identical
#  11. every XML answer is well-formed
#
# Usage: test/cochangetailcheck.sh [BIN]   (default build/ripwire; RIPWIRE_BIN= also selects it)
set -u
export RIPWIRE_NO_ROWLINES=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "cochangetailcheck: BIN=$BIN $( "$BIN" --version 2>/dev/null | head -1 )"
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

TMP="$( mktemp -d )"
trap '[ -n "${KEEP:-}" ] || rm -rf "$TMP"' EXIT
T=1780000000
tick(){ T=$(( T + 3600 )); export GIT_AUTHOR_DATE="@$T +0000" GIT_COMMITTER_DATE="@$T +0000"; }
export GIT_AUTHOR_NAME=Hana GIT_AUTHOR_EMAIL=hana@x.com GIT_COMMITTER_NAME=Hana GIT_COMMITTER_EMAIL=hana@x.com
C(){ tick; git -C "$1" add -A >/dev/null; git -C "$1" commit -qm "$2"; }
fn(){ printf 'int %s( int x )\n{\n    if( x > 1 ) return x + 1;\n    return x - 1;\n}\n' "$1"; }
t(){ local r="$1"; shift; local m="$1"; shift; for f in "$@"; do printf '// %s\n' "$m" >> "$r/$f"; done; C "$r" "$m"; }

# ── fixture R ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
R="$TMP/r"; mkdir -p "$R/src" "$R/lib" "$R/test" "$R/other" "$R/other2" "$R/solo" "$R/big" "$R/fill"
git -C "$R" init -q -b main
printf '#include "../lib/l.h"\nint k_func( int x );\nint alpha_widget_resize( int x )\n{\n    if( x > 1 ) return k_func( x ) + LEVEL;\n    return x - 1;\n}\n' > "$R/src/a.c"
printf '#define LEVEL 3\nint lib_level_probe( int x );\n' > "$R/lib/l.h"
fn k_func > "$R/lib/k.c"; fn zq_sierra > "$R/src/s.c"; fn zq_alpha_test_case > "$R/test/a_test.c"
fn zq_uniform > "$R/other/u.c"; fn zq_charlie > "$R/other/c.c"
fn quebec_gizmo_spin > "$R/solo/q.c"; fn zq_romeo > "$R/other2/r.c"
fn big_anchor_twist > "$R/big/a.c"; fn zq_papa > "$R/big/p.c"; for k in $( seq 1 20 ); do fn "zq_big_$k" > "$R/big/f$k.c"; done
for k in $( seq 1 31 ); do fn "zq_fill_$k" > "$R/fill/f$k.c"; done
C "$R" "init (over 30 indexed files: the bulk cut leaves it out)"
t "$R" "a with its linked and unlinked partners 1" src/a.c lib/k.c lib/l.h src/s.c test/a_test.c other/u.c other/c.c
t "$R" "a with its linked and unlinked partners 2" src/a.c lib/k.c lib/l.h src/s.c test/a_test.c other/u.c other/c.c
t "$R" "a and c" src/a.c other/c.c
t "$R" "a alone 1" src/a.c
t "$R" "a alone 2" src/a.c
t "$R" "q and r 1" solo/q.c other2/r.c
t "$R" "q and r 2" solo/q.c other2/r.c
t "$R" "q alone" solo/q.c
t "$R" "big a and p 1" big/a.c big/p.c
t "$R" "big a and p 2" big/a.c big/p.c
for i in 1 2 3; do t "$R" "big a alone $i" big/a.c; done

# ── fixture W (fill) ──────────────────────────────────────────────────────────────────────────────────────────────────────
W="$TMP/w"; mkdir -p "$W/w" "$W/fill"; git -C "$W" init -q -b main
fn whiskey_lever_turn > "$W/w/a.c"; for k in $( seq 1 9 ); do fn "zq_sup_$k" > "$W/w/s$k.c"; done; for k in 1 2 3; do fn "zq_tail_$k" > "$W/w/t$k.c"; done
for k in $( seq 1 31 ); do fn "zq_wfill_$k" > "$W/fill/f$k.c"; done
C "$W" "init (bulk)"
SUP="$( for k in $( seq 1 9 ); do printf 'w/s%s.c ' "$k"; done )"
t "$W" "a, the nine and the three 1" w/a.c $SUP w/t1.c w/t2.c w/t3.c
t "$W" "a, the nine and the three 2" w/a.c $SUP w/t1.c w/t2.c w/t3.c
t "$W" "a and the nine" w/a.c $SUP

# oracle
shared(){ local r="$1" a="$2" b="$3" n=0; for h in $( git -C "$r" log --format=%H ); do
    fs="$( git -C "$r" show --name-only --format= "$h" )"; [ "$( printf '%s\n' "$fs" | grep -c . )" -gt 30 ] && continue
    printf '%s\n' "$fs" | grep -qx "$a" && printf '%s\n' "$fs" | grep -qx "$b" && n=$(( n + 1 )); done; echo "$n"; }
orc="$( shared "$R" src/a.c other/c.c ) $( shared "$R" src/a.c lib/k.c ) $( shared "$R" src/a.c other/u.c ) $( shared "$R" solo/q.c other2/r.c ) $( shared "$R" big/a.c big/p.c ) $( shared "$W" w/a.c w/s1.c ) $( shared "$W" w/a.c w/t1.c )"
[ "$orc" = "3 2 2 2 2 3 2" ] && ok "(oracle) shared commits outside the bulk cut: a/c 3, a/k 2, a/u 2, q/r 2, big a/p 2, W a/s 3, W a/t 2" \
                           || no "(oracle) shared commits are '$orc', not '3 2 2 2 2 3 2' — the arms prove nothing"

run(){ local r="$1"; shift; ( cd "$r" && "$BIN" . "$@" ) 2>/dev/null; }
payload(){ python3 -c 'import re,sys; print( re.sub( r"<!--.*?-->", "", open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read(), flags = re.S ) )' "$1"; }
attr_of(){ payload "$1" | grep -oE "<$2 [^>]*" | head -1 | grep -oE " $3=\"[^\"]*\"" | head -1 | sed -E "s/^ $3=\"//; s/\"\$//"; }
# XML rows of element $1: path:together:why (why "-" when absent)
xrows(){ payload "$2" | python3 -c '
import re, sys
m = re.search( r"<%s\b[^>]*>(.*?)</%s>" % ( sys.argv[1], sys.argv[1] ), sys.stdin.read(), re.S )
out = []
for row in re.findall( r"<f [^>]*>", m.group( 1 ) if m else "" ):
    g = lambda k: ( re.search( r"\b%s=\"([^\"]*)\"" % k, row ) or [ None, "-" ] )[1]
    out.append( "%s:%s:%s" % ( g( "p" ), g( "together" ), g( "why" ) ) )
print( " ".join( out ) or "NONE" )' "$1"; }
srows(){ sed -n '/^  \[3\] co-change/,/^  next:/p' "$1" | python3 -c '
import re, sys
out = []
for line in sys.stdin.read().splitlines()[1:]:
    m = re.match( r"^        (\S+)  \(co-edited in \d+% of commits(?:, together=(\d+))?(?:, why=(\w+))?\)$", line )
    if m:
        out.append( "%s:%s:%s" % ( m.group( 1 ), m.group( 2 ) or "-", m.group( 3 ) or "-" ) )
print( " ".join( out ) or "NONE" )'; }
shead(){ grep -m1 '^  \[3\] co-change' "$1"; }
lacks(){ case " $1 " in *" $2:"*) return 1;; *) return 0;; esac; }

WANT1="other/c.c:3:support lib/k.c:2:link lib/l.h:2:link src/s.c:2:link test/a_test.c:2:link"
# 1
run "$R" --cochange=src/a.c > "$TMP/c1.xml"; run "$R" --cochange=src/a.c --legend=full > "$TMP/c1f.xml"; X1="$( xrows cochange "$TMP/c1.xml" )"
[ "$X1" = "$WANT1" ] && ok "1. --cochange=src/a.c: c.c (support) first, then the four linked 2-commit partners (call, include, same dir, test-of)" \
                     || no "1. --cochange=src/a.c rows '$X1', want '$WANT1'"
# 2
run "$R" --cochange=solo/q.c > "$TMP/c2.xml"; X2="$( xrows cochange "$TMP/c2.xml" )"
[ "$X2" = "other2/r.c:2:confidence" ] && ok "2. --cochange=solo/q.c: other2/r.c (2 of q.c's 3 commits) is listed why=\"confidence\"" \
                                      || no "2. --cochange=solo/q.c rows '$X2'"
# 3
if [ "$( attr_of "$TMP/c1.xml" cochange floor_tail )" = corroborated ] && [ "$( attr_of "$TMP/c1.xml" cochange floor )" = 3 ] \
   && grep -q 'floor_tail=' "$TMP/c1.xml" && grep -q 'why=' "$TMP/c1.xml" && grep -q 'floor_tail=' "$TMP/c1f.xml" && grep -q 'why=' "$TMP/c1f.xml"; then
    ok "3. <cochange floor=\"3\" floor_tail=\"corroborated\">; both legends define floor_tail= and why="
else no "3. floor_tail='$( attr_of "$TMP/c1.xml" cochange floor_tail )' floor='$( attr_of "$TMP/c1.xml" cochange floor )'; legends: compact floor_tail $( grep -c 'floor_tail=' "$TMP/c1.xml" ) why $( grep -c 'why=' "$TMP/c1.xml" ), full floor_tail $( grep -c 'floor_tail=' "$TMP/c1f.xml" )"; fi
# 4
run "$R" --situ=src/a.c > "$TMP/s1.txt"; S1="$( srows "$TMP/s1.txt" )"
if [ "$S1" = "$WANT1" ] && shead "$TMP/s1.txt" | grep -q ' floor_tail="corroborated"'; then ok "4. --situ=src/a.c: the same five rows with together= and why=, floor_tail=\"corroborated\""
else no "4. --situ=src/a.c rows '$S1', header '$( shead "$TMP/s1.txt" )'"; fi
# 5
run "$R" --cochange=big/a.c > "$TMP/c3.xml"; X3="$( xrows cochange "$TMP/c3.xml" )"
if [ "$X1" != NONE ] && lacks "$X1" other/u.c && lacks "$S1" other/u.c && [ "$( attr_of "$TMP/c3.xml" cochange floor_tail )" = corroborated ] && lacks "$X3" big/p.c; then
    ok "5. rejected: other/u.c (nothing corroborates it) and big/p.c (a 22-file directory) are not listed"
else no "5. rejections: src/a.c rows '$X1', big/a.c rows '$X3' floor_tail='$( attr_of "$TMP/c3.xml" cochange floor_tail )'"; fi
# 6
TASK1='fix `quebec_gizmo_spin` in solo/q.c'
run "$R" --pack-task="$TASK1" > "$TMP/p1.xml"; run "$R" --pack-task="$TASK1" --json > "$TMP/p1.json"; P1="$( xrows partners "$TMP/p1.xml" )"
if [ "$( attr_of "$TMP/p1.xml" partners seeds )" = 1 ] && [ "$( attr_of "$TMP/p1.xml" partners floor_tail )" = corroborated ] && [ "$P1" = "other2/r.c:2:confidence" ] \
   && python3 - "$TMP/p1.json" <<'PY_EOF'
import json, sys
d = json.load( open( sys.argv[1] ) )
rows = [ ( r.get( 'p' ), r.get( 'together' ), r.get( 'why' ) ) for r in d.get( 'partners', [] ) ]
sys.exit( 0 if d.get( 'partners_floor_tail' ) == 'corroborated' and rows == [ ( 'other2/r.c', 2, 'confidence' ) ] else 1 )
PY_EOF
then ok "6. --pack-task, one seed (solo/q.c): <partners floor_tail=\"corroborated\"> lists other2/r.c why=\"confidence\", the JSON twin too"
else no "6. --pack-task: seeds='$( attr_of "$TMP/p1.xml" partners seeds )' floor_tail='$( attr_of "$TMP/p1.xml" partners floor_tail )' rows '$P1'"; fi
# 7
run "$W" --cochange=w/a.c > "$TMP/w1.xml"; XW="$( xrows cochange "$TMP/w1.xml" )"
WANTW="$( for k in $( seq 1 9 ); do printf 'w/s%s.c:3:support ' "$k"; done )w/t1.c:2:confidence"
run "$W" --situ=w/a.c --limit=20 > "$TMP/w1.txt"; SW="$( srows "$TMP/w1.txt" )"
if [ "$XW" = "$WANTW" ] && [ "$SW" = "$WANTW" ]; then ok "7. fill never displaces: the 9 support rows first, then 1 tail row (w/t1.c) — 10 in all; w/t2.c and w/t3.c left out"
else no "7. fill: cochange '$XW' situ '$SW', want '$WANTW'"; fi
# 8
mcp(){ printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$1"'","arguments":{"path":"'"$R"'",'"$2"'}}}' \
    | perl -e 'alarm 30; exec @ARGV' "$BIN" "$R" --mcp --no-cache 2>/dev/null | tail -1; }
mtext(){ python3 -c 'import json,sys
try:
    print( json.loads( sys.stdin.read() )["result"]["content"][0]["text"] )
except Exception as e:
    print( "{\"error\": \"%s\"}" % e )'; }
mcp cochange '"file":"src/a.c"' | mtext > "$TMP/m1.json"
mcp situational_awareness '"files":"src/a.c"' | mtext > "$TMP/m2.json"
mcp situational_awareness '"files":"src/a.c,solo/q.c"' | mtext > "$TMP/m3.json"
if python3 - "$TMP/m1.json" "$TMP/m2.json" "$WANT1" <<'PY_EOF'
import json, sys
cc, sa, want = json.load( open( sys.argv[1] ) ), json.load( open( sys.argv[2] ) ), sys.argv[3]
a = " ".join( "%s:%s:%s" % ( r.get( 'file' ), r.get( 'together' ), r.get( 'why' ) ) for r in cc.get( 'rows', [] ) )
b = " ".join( "%s:%s:%s" % ( r.get( 'file' ), r.get( 'together' ), r.get( 'why' ) ) for r in sa.get( 'forgotten', [] ) )
sys.exit( 0 if a == want and b == want and cc.get( 'floor_tail' ) == 'corroborated' and sa.get( 'cochange_floor_tail' ) == 'corroborated' else 1 )
PY_EOF
then ok "8. MCP cochange and situational_awareness: the same rows with why, floor_tail corroborated"
else no "8. MCP: cochange $( grep -oE '"floor_tail":"[a-z]*"|"rows":\[[^]]*\]' "$TMP/m1.json" | head -c 400 ) | situ $( grep -oE '"cochange_floor_tail":"[a-z]*"|"forgotten":\[[^]]*\]' "$TMP/m2.json" | head -c 300 )"; fi
# 9
run "$R" --situ=src/a.c,solo/q.c > "$TMP/s2.txt"; S2="$( srows "$TMP/s2.txt" )"
run "$R" --pack-task='fix `alpha_widget_resize` in src/a.c and `quebec_gizmo_spin` in solo/q.c' > "$TMP/p2.xml"; P2="$( xrows partners "$TMP/p2.xml" )"
M3="$( python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print( "tail" if "cochange_floor_tail" in d else "", " ".join( "%s:%s:%s" % ( r.get("file"), r.get("together"), r.get("why","-") ) for r in d.get("forgotten",[]) ) )' "$TMP/m3.json" )"
if [ "$S2" = "other/c.c:3:-" ] && ! shead "$TMP/s2.txt" | grep -q 'floor_tail=' && [ "$( attr_of "$TMP/p2.xml" partners seeds )" -ge 2 ] 2>/dev/null \
   && [ "$P2" = "other/c.c:3:-" ] && [ -z "$( attr_of "$TMP/p2.xml" partners floor_tail )" ] && [ "$M3" = " other/c.c:3:-" ]; then
    ok "9. several seeds unchanged: c.c alone, no 2-commit row, no floor_tail=, no why= (--situ, <partners>, MCP)"
else no "9. several seeds: situ '$S2' head '$( shead "$TMP/s2.txt" )', partners seeds=$( attr_of "$TMP/p2.xml" partners seeds ) '$P2' tail='$( attr_of "$TMP/p2.xml" partners floor_tail )', mcp '$M3'"; fi
# 10
det=1
for a in "--cochange=src/a.c" "--situ=src/a.c" "--situ=src/a.c,solo/q.c" "--pack-task=$TASK1"; do
    run "$R" "$a" > "$TMP/d1"; run "$R" "$a" > "$TMP/d2"; cmp -s "$TMP/d1" "$TMP/d2" || { det=0; echo "    two runs of $a differ"; }
done
run "$W" --cochange=w/a.c > "$TMP/d1"; cmp -s "$TMP/d1" "$TMP/w1.xml" || { det=0; echo "    two runs of W --cochange differ"; }
[ "$det" = 1 ] && ok "10. deterministic: every answer above is byte-identical across two runs" || no "10. a non-deterministic answer"
# 11
bad=0
for f in c1 c1f c2 c3 p1 p2 w1; do xmllint --noout "$TMP/$f.xml" 2>/dev/null || { bad=1; echo "    malformed: $f.xml"; }; done
[ "$bad" = 0 ] && ok "11. every XML answer is well-formed" || no "11. a malformed answer"

[ "$fail" = 0 ] && { echo "cochangetailcheck: PASS"; exit 0; }
echo "cochangetailcheck: FAIL"; exit 1
