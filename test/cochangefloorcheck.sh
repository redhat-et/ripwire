#!/usr/bin/env bash
# cochangefloorcheck.sh — every co-change partner list says the support floor it used, and every --situ row its support count.
#
# WHY. The co-change backtest (bench/cochange) found the support floor of 3 shared commits decides most of what a one-file
# --situ can answer, and the answers never said so: --situ's [3] rows printed a percentage alone, so "co-edited in 67% of
# commits" could not be told from 2 of 3 or 200 of 300, and no answer named the floor a partner had to reach. Owner ruling
# 2026-11-26: the support count and the floor ship regardless of any change to the floor itself, because they move no row.
#
# RED-FIRST: arms 1-6 fail on a binary without the disclosure (no together= on a [3] row, no floor= anywhere). Arm 7 is the
# guard that the disclosure moved no support row, so it holds on the base too. Arms 8-9
# (determinism, well-formedness) hold on any binary.
#
# The fixture (every pair also shares the "init" commit):
#   b.c shares 2 commits with a.c; c.c shares 3; g.c shares 1; h.c shares 2 with e.c and 1 with a.c.
#
# Arms:
#   1. --situ=a.c: every [3] row ends ", together=N" and N is the oracle's count (c.c 3); the header says floor="3"
#   2. --situ=a.c,e.c (two seeds): the same — rows carry together=, the header floor="3"
#   3. --cochange=a.c: <cochange floor="3">; the compact and full legends define floor=
#   4. --pack-task: <partners floor="3"> and the JSON twin's partners_floor 3; the compact and full legends define floor=
#   5. MCP situational_awareness(a.c): "cochange_floor":3 and each forgotten row's "together" (c.c 3)
#   6. MCP cochange(a.c): "floor":3
#   7. no SUPPORT row moved: every list starts with c.c, the one partner at the floor, in --situ, --cochange, <partners> and
#      MCP alike; two-seed lists are c.c alone. (COCHANGE-TAIL 2026-11-26: a one-seed list may add corroborated 2-commit rows
#      after it — b.c, 2 of a.c's 4 commits — which test/cochangetailcheck.sh owns.)
#   8. deterministic: two runs of each answer are byte-identical
#   9. every XML answer is well-formed
#
# Usage: test/cochangefloorcheck.sh [BIN]   (default build/ripwire; RIPWIRE_BIN= also selects it)
set -u
export RIPWIRE_NO_ROWLINES=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "cochangefloorcheck: BIN=$BIN $( "$BIN" --version 2>/dev/null | head -1 )"
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

TMP="$( mktemp -d )"
trap '[ -n "${KEEP:-}" ] || rm -rf "$TMP"' EXIT
R="$TMP/repo"
mkdir -p "$R"

mkfn(){ printf 'int %s( int x )\n{\n    if( x > 1 ) return x + 1;\n    return x - 1;\n}\n' "$1"; }
T=1780000000
tick(){ T=$(( T + 3600 )); export GIT_AUTHOR_DATE="@$T +0000" GIT_COMMITTER_DATE="@$T +0000"; }
export GIT_AUTHOR_NAME=Hana GIT_AUTHOR_EMAIL=hana@x.com GIT_COMMITTER_NAME=Hana GIT_COMMITTER_EMAIL=hana@x.com
C(){ tick; git -C "$R" add -A >/dev/null; git -C "$R" commit -qm "$1"; }
touchf(){ printf '// %s\n' "$2" >> "$R/$1"; }

git -C "$R" init -q -b main
mkfn alpha_widget_resize > "$R/a.c"; mkfn zq_bravo > "$R/b.c"; mkfn zq_charlie > "$R/c.c"
mkfn echo_gadget_rotate > "$R/e.c"; mkfn zq_golf > "$R/g.c"; mkfn zq_hotel > "$R/h.c"
C "init"                                                        # one shared commit for every pair
touchf a.c ab; touchf b.c ab; C "a and b"                       # b.c: 2 shared with a.c
for i in 1 2; do touchf a.c "ac $i"; touchf c.c "ac $i"; C "a and c $i"; done   # c.c: 3 shared with a.c
touchf e.c eh; touchf h.c eh; C "e and h"                       # h.c: 2 shared with e.c (1 with a.c); g.c: 1 with a.c
for i in 1 2 3; do touchf e.c "e $i"; C "e alone $i"; done

# oracle: the fixture is what the arms claim
shared(){ for h in $( git -C "$R" log --format=%H ); do git -C "$R" show --name-only --format= "$h" | grep -cxE "$1|$2"; done | grep -cx 2; }
if [ "$( shared 'a\.c' 'b\.c' )" = 2 ] && [ "$( shared 'a\.c' 'c\.c' )" = 3 ] && [ "$( shared 'a\.c' 'g\.c' )" = 1 ] \
   && [ "$( shared 'e\.c' 'h\.c' )" = 2 ] && [ "$( shared 'a\.c' 'h\.c' )" = 1 ] && [ "$( shared 'e\.c' 'b\.c' )" = 1 ]; then
    ok "(oracle) shared commits: a/b 2, a/c 3, a/g 1, e/h 2, a/h 1, e/b 1"
else no "(oracle) the fixture's shared-commit counts are not the ones the arms assume — the arms prove nothing"; fi

run(){ ( cd "$R" && "$BIN" . "$@" ) 2>/dev/null; }
# --situ's [3] section: one "path:together" word per row (together= absent on a row reads as path:?)
situ_rows(){ sed -n '/^  \[3\] co-change/,/^  next:/p' "$1" | python3 -c '
import re, sys
rows = []
for line in sys.stdin.read().splitlines()[1:]:
    m = re.match( r"^        (\S+)  \(co-edited in \d+% of commits(?:, together=(\d+))?(?:, why=\w+)?\)$", line )
    if m:
        rows.append( "%s:%s" % ( m.group( 1 ), m.group( 2 ) or "?" ) )
print( " ".join( rows ) or "NONE" )'; }
situ_head(){ grep -m1 '^  \[3\] co-change' "$1"; }
payload(){ python3 -c 'import re,sys; print( re.sub( r"<!--.*?-->", "", open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read(), flags = re.S ) )' "$1"; }
attr_of(){ payload "$1" | grep -oE "<$2 [^>]*" | head -1 | grep -oE " $3=\"[^\"]*\"" | head -1 | sed -E "s/^ $3=\"//; s/\"\$//"; }
rows_of(){ payload "$2" | python3 -c '
import re, sys
doc = sys.stdin.read()
m = re.search( r"<%s\b[^>]*>(.*?)</%s>" % ( sys.argv[1], sys.argv[1] ), doc, re.S )
print( " ".join( "%s:%s" % pn for pn in re.findall( r"<f p=\"([^\"]*)\" together=\"(\d+)\"", m.group( 1 ) ) ) if m else "NONE" )' "$1"; }
has(){ case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }
lacks_file(){ case " $1 " in *" $2:"*) return 1;; *) return 0;; esac; }
has_file(){ ! lacks_file "$1" "$2"; }


# 1
run --situ=a.c > "$TMP/s1.txt"; S1="$( situ_rows "$TMP/s1.txt" )"
if [ "${S1%% *}" = "c.c:3" ] && situ_head "$TMP/s1.txt" | grep -q ' floor="3"'; then ok "1. --situ=a.c: the [3] row says together=3 and the header floor=\"3\" ($S1)"
else no "1. --situ=a.c: rows '$S1', header '$( situ_head "$TMP/s1.txt" )'"; fi
# 2
run --situ=a.c,e.c > "$TMP/s2.txt"; S2="$( situ_rows "$TMP/s2.txt" )"
if [ "$S2" = "c.c:3" ] && situ_head "$TMP/s2.txt" | grep -q ' floor="3"'; then ok "2. --situ=a.c,e.c: together=3 on the row, floor=\"3\" on the header ($S2)"
else no "2. --situ=a.c,e.c: rows '$S2', header '$( situ_head "$TMP/s2.txt" )'"; fi
# 3
run --cochange=a.c > "$TMP/c1.xml"; run --cochange=a.c --legend=full > "$TMP/c1f.xml"; C1="$( rows_of cochange "$TMP/c1.xml" )"
if [ "$( attr_of "$TMP/c1.xml" cochange floor )" = 3 ] && grep -q 'floor=N' "$TMP/c1.xml" && grep -q 'floor=' "$TMP/c1f.xml"; then
    ok "3. --cochange=a.c: floor=\"3\", defined by both legends ($C1)"
else no "3. --cochange=a.c: floor='$( attr_of "$TMP/c1.xml" cochange floor )', compact legend floor=N: $( grep -c 'floor=N' "$TMP/c1.xml" )"; fi
# 4
TASK1='fix `alpha_widget_resize` in a.c'
run --pack-task="$TASK1" > "$TMP/p1.xml"; run --pack-task="$TASK1" --legend=full > "$TMP/p1f.xml"; run --pack-task="$TASK1" --json > "$TMP/p1.json"
P1="$( rows_of partners "$TMP/p1.xml" )"
if [ "$( attr_of "$TMP/p1.xml" partners floor )" = 3 ] && grep -q 'floor=' "$TMP/p1.xml" && grep -q 'floor=' "$TMP/p1f.xml" \
   && python3 -c 'import json,sys; sys.exit( 0 if json.load( open( sys.argv[1] ) ).get( "partners_floor" ) == 3 else 1 )' "$TMP/p1.json"; then
    ok "4. --pack-task: <partners floor=\"3\">, partners_floor 3 in JSON, both legends define floor= ($P1)"
else no "4. --pack-task: floor='$( attr_of "$TMP/p1.xml" partners floor )' json='$( grep -o '"partners_floor":[0-9]*' "$TMP/p1.json" )'"; fi
# 5, 6
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
mcp situational_awareness '"files":"a.c"' | mtext > "$TMP/m1.json"
mcp situational_awareness '"files":"a.c,e.c"' | mtext > "$TMP/m2.json"
mcp cochange '"file":"a.c"' | mtext > "$TMP/m3.json"
if python3 - "$TMP/m1.json" <<'PY_EOF'
import json, sys
d = json.load( open( sys.argv[1] ) )
sys.exit( 0 if d.get( 'cochange_floor' ) == 3 and [ ( r.get( 'file' ), r.get( 'together' ) ) for r in d.get( 'forgotten', [] ) ][:1] == [ ( 'c.c', 3 ) ] else 1 )
PY_EOF
then ok "5. MCP situational_awareness(a.c): cochange_floor 3, forgotten [c.c together 3]"
else no "5. MCP situational_awareness: $( grep -oE '"cochange_floor":[0-9]+|"forgotten":\[[^]]*\]' "$TMP/m1.json" | tr '\n' ' ' )"; fi
if python3 -c 'import json,sys; sys.exit( 0 if json.load( open( sys.argv[1] ) ).get( "floor" ) == 3 else 1 )' "$TMP/m3.json"; then ok "6. MCP cochange(a.c): floor 3"
else no "6. MCP cochange: $( head -c 200 "$TMP/m3.json" )"; fi
# 7
run --pack-task='fix `alpha_widget_resize` in a.c and `echo_gadget_rotate` in e.c' > "$TMP/p2.xml"
mv7="$( python3 - "$TMP/m1.json" "$TMP/m2.json" <<'PY_EOF'
import json, sys
f = [ [ r['file'] for r in json.load( open( p ) ).get( 'forgotten', [] ) ] for p in sys.argv[1:] ]
print( ( f[0] or [ "NONE" ] )[0], ",".join( f[1] ) or "NONE" )
PY_EOF
)"
first(){ echo "${1%% *}"; }
if [ "$( first "$( situ_rows "$TMP/s1.txt" )" )" = c.c:3 ] && [ "$( situ_rows "$TMP/s2.txt" )" = c.c:3 ] \
   && [ "$( first "$( rows_of cochange "$TMP/c1.xml" )" )" = c.c:3 ] && [ "$( first "$( rows_of partners "$TMP/p1.xml" )" )" = c.c:3 ] && [ "$( rows_of partners "$TMP/p2.xml" )" = c.c:3 ] \
   && [ "$mv7" = "c.c c.c" ]; then ok "7. no support row moved: c.c first on every surface, and alone with two seeds"
else no "7. rows moved: situ '$S1' / '$S2', cochange '$( rows_of cochange "$TMP/c1.xml" )', partners '$( rows_of partners "$TMP/p1.xml" )' / '$( rows_of partners "$TMP/p2.xml" )', mcp '$mv7'"; fi
# 8
det=1
for a in "--situ=a.c" "--situ=a.c,e.c" "--cochange=a.c" "--pack-task=$TASK1"; do
    run "$a" > "$TMP/d1"; run "$a" > "$TMP/d2"; cmp -s "$TMP/d1" "$TMP/d2" || { det=0; echo "    two runs of $a differ"; }
done
[ "$det" = 1 ] && ok "8. deterministic: every answer above is byte-identical across two runs" || no "8. a non-deterministic answer"
# 9
bad=0
for f in c1 c1f p1 p1f p2; do xmllint --noout "$TMP/$f.xml" 2>/dev/null || { bad=1; echo "    malformed: $f.xml"; }; done
[ "$bad" = 0 ] && ok "9. every XML answer is well-formed" || no "9. a malformed answer"

[ "$fail" = 0 ] && { echo "cochangefloorcheck: PASS"; exit 0; }
echo "cochangefloorcheck: FAIL"; exit 1
