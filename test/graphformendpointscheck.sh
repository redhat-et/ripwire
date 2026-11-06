#!/usr/bin/env bash
# graphformendpointscheck.sh — GRAPH-FORM-ENDPOINTS (src/forgraphverb.h graphSubjectPathUnreachable / pathGapOpenXml, src/verbs_for.h
# appendPathGapSides): when the path verb a `--for "path from A to B"` task runs finds no directed path (reachable="0"), a <path_gap>
# block inside the graph block prints from='s callees and to='s callers. The ranking, route= and every found-path answer are untouched.
#   (f1) `what is the path from A to B`, path found: no <path_gap>, route= has no `dropped:`, and the <graph_verb> block is
#        byte-identical to the bare --path= call (compact legend; RIPWIRE_NO_HOP_BODY=1, as forroutecheck (v1))
#   (g1) gap: `path from A to B` with no directed path: reachable="0", then <path_gap from= to= reachable="0"> holding A's callees answer
#        (its callee listed) and B's callers answer (its caller listed), once, inside the graph block, well-formed, legend without `--`
#   (g2) the gap sides are the bare --callees= / --callers= answers at --limit=10, byte for byte
#   (g3) gap with an empty side (the reverse direction): the callees side is the bare answer for a symbol that calls nothing, shown, not missing
#   (g4) the cap: a side with 12 callees shows 10 rows, count= the total and next= the page after; still the bare --limit=10 answer
#   (n1) "where is the config path parsed": not the form (no graph block, no path_gap)
#   (n2) "strip the directory path from a_start() to the end": not the form (lead-in), no graph block, no path_gap
#   (c1) a crashing / silent binary turns the arms red (every arm reads rc and requires its positive text)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "graphformendpointscheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FX="$TMP/fx"; mkdir -p "$FX"
cat > "$FX/flow.c" <<'C'
void leaf_sink( void ) {}
void mid_hop( void ) { leaf_sink(); }
void startEntry( void ) { mid_hop(); }
void other_caller( void ) { leaf_sink(); }
void helper_alpha( void ) {}
void lonely_start( void ) { helper_alpha(); }
void target_end( void ) {}
void beta_caller( void ) { target_end(); }
void parse_config_path( void ) {}
void wide_a( void ) {}
void wide_b( void ) {}
void wide_c( void ) {}
void wide_d( void ) {}
void wide_e( void ) {}
void wide_f( void ) {}
void wide_g( void ) {}
void wide_h( void ) {}
void wide_i( void ) {}
void wide_j( void ) {}
void wide_k( void ) {}
void wide_l( void ) {}
void wide_start( void ) { wide_a(); wide_b(); wide_c(); wide_d(); wide_e(); wide_f(); wide_g(); wide_h(); wide_i(); wide_j(); wide_k(); wide_l(); }
int main( void ) { wide_start(); startEntry(); other_caller(); lonely_start(); beta_caller(); parse_config_path(); return 0; }
C
# rc-checked run: stdout to $2, rc kept in $TMP/<name>.rc
run(){ local name="$1"; shift; ( cd "$FX" || exit 1; "$BIN" "$FX" --no-cache "$@" 2>/dev/null ) >"$TMP/$name.xml"; echo $? >"$TMP/$name.rc"; }
rc(){ cat "$TMP/$1.rc"; }
route(){ python3 - "$TMP/$1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
m = re.search( r'<ctx [^>]*\broute="([^"]*)"', s )
print( m.group( 1 ) if m else '-' )
PY
}
count(){ python3 -c 'import sys; print(open(sys.argv[1], encoding="utf8", errors="replace").read().count(sys.argv[2]))' "$TMP/$1.xml" "$2"; }
xmlok(){ if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$1" 2>/dev/null; else return 0; fi; }
command -v xmllint >/dev/null 2>&1 || echo "  SKIP  xmllint not installed: the well-formedness half of (g1) is not checked"

# (f1) path form, path found
# (RIPWIRE_NO_HOP_BODY=1: a hop body the ranked answer already printed is not printed twice in the block, forroutecheck (v1b))
RIPWIRE_NO_HOP_BODY=1 run f1 --for="what is the path from startEntry to leaf_sink?"
RIPWIRE_NO_HOP_BODY=1 run f1v --path=startEntry,leaf_sink
r="$( route f1 )"
blk="$( python3 - "$TMP/f1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
m = re.search( r'<graph_verb [^>]*>(.*)</graph_verb>', s, re.S )
print( m.group( 1 ) if m else '' , end='' )
PY
)"
bare="$( cat "$TMP/f1v.xml" )"
if [ "$( rc f1 )" = 0 ] && [ "$( rc f1v )" = 0 ] && case "$r" in *"dropped:"*) false;; *) true;; esac \
   && [ "$( count f1 '<path_gap ' )" = 0 ] && grep -q 'reachable="1"' "$TMP/f1.xml" && [ -n "$bare" ] && [ "$blk" = "$bare" ]; then
    ok "(f1) path form: route= '$r' unchanged; path found, no <path_gap>; graph block == bare --path"
else no "(f1) rc=$( rc f1 )/$( rc f1v ) route='$r' path_gap=$( count f1 '<path_gap ' ) block_eq=$( [ "$blk" = "$bare" ] && echo 1 || echo 0 )"; fi

# (g1) gap: no directed path lonely_start -> target_end
run g1 --for="path from lonely_start to target_end"
facts="$( python3 - "$TMP/g1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
gv = re.search( r'<graph_verb [^>]*>(.*)</graph_verb>', s, re.S )
inner = gv.group( 1 ) if gv else ''
pg = re.search( r'<path_gap ([^>]*)>(.*)</path_gap>', inner, re.S )
leg = re.search( r'<!-- ripwire for path_gap:(.*?)-->', inner, re.S )
a = pg.group( 1 ) if pg else ''
body = pg.group( 2 ) if pg else ''
print( "n=%d reach0=%d gapreach0=%d from=%s to=%s missing=%d callee=%d caller=%d legdash=%d" % (
    s.count( '<path_gap ' ), int( ' reachable="0"' in inner ), int( 'reachable="0"' in a ),
    ( re.search( r'from="([^"]*)"', a ) or [0, '-'] )[1], ( re.search( r'\bto="([^"]*)"', a ) or [0, '-'] )[1], int( 'missing=' in a ),
    int( 'helper_alpha' in body ), int( 'beta_caller' in body ), int( '--' in leg.group( 1 ) ) if leg else 9 ) )
PY
)"
if [ "$( rc g1 )" = 0 ] && [ "$facts" = "n=1 reach0=1 gapreach0=1 from=lonely_start to=target_end missing=0 callee=1 caller=1 legdash=0" ] \
   && xmlok "$TMP/g1.xml"; then
    ok "(g1) gap: reachable=0, <path_gap> lists from's callee and to's caller ($facts)"
else no "(g1) rc=$( rc g1 ) facts='$facts'"; fi

# (g2) the two sides are the bare --callees= / --callers= answers
run g2a --callees=lonely_start --limit=10
run g2b --callers=target_end --limit=10
gap="$( python3 - "$TMP/g1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
m = re.search( r'<path_gap [^>]*>(.*)</path_gap>', s, re.S )
print( m.group( 1 ) if m else '', end='' )
PY
)"
both="$( cat "$TMP/g2a.xml" "$TMP/g2b.xml" )"
if [ "$( rc g2a )" = 0 ] && [ "$( rc g2b )" = 0 ] && [ -n "$gap" ] && [ "$gap" = "$both" ]; then ok "(g2) gap sides == bare --callees + --callers"
else no "(g2) rc=$( rc g2a )/$( rc g2b ) gap_bytes=${#gap} bare_bytes=${#both}"; fi

# (g3) gap with an empty side: leaf_sink calls nothing, so the path leaf_sink -> startEntry does not exist; the callees side is the bare answer
run g3 --for="path from leaf_sink to startEntry"
run g3a --callees=leaf_sink --limit=10
run g3b --callers=startEntry --limit=10
gap3="$( python3 - "$TMP/g3.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
m = re.search( r'<path_gap ([^>]*)>(.*)</path_gap>', s, re.S )
print( ( m.group( 2 ) if m else '' ) + ( '|MISSING' if m and 'missing=' in m.group( 1 ) else '' ), end='' )
PY
)"
both3="$( cat "$TMP/g3a.xml" "$TMP/g3b.xml" )"
if [ "$( rc g3 )" = 0 ] && [ "$( rc g3a )" = 0 ] && [ "$( rc g3b )" = 0 ] && [ -n "$gap3" ] && [ "$gap3" = "$both3" ] && [ "$( count g3 '<path_gap ' )" = 1 ] \
   && grep -q 'main' "$TMP/g3b.xml"; then ok "(g3) gap with an empty callees side == bare answers"
else no "(g3) rc=$( rc g3 )/$( rc g3a )/$( rc g3b ) gap_bytes=${#gap3} bare_bytes=${#both3} n=$( count g3 '<path_gap ' )"; fi

# (g4) the cap: wide_start has 12 callees, so its side of the gap shows 10 rows, says so (count= the total, next= the page after), and is the
# bare --callees --limit=10 answer
run g4 --for="path from wide_start to target_end"
run g4a --callees=wide_start --limit=10
run g4b --callers=target_end --limit=10
gap4="$( python3 - "$TMP/g4.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
m = re.search( r'<path_gap [^>]*>(.*)</path_gap>', s, re.S )
print( m.group( 1 ) if m else '', end='' )
PY
)"
both4="$( cat "$TMP/g4a.xml" "$TMP/g4b.xml" )"
callees4="$( python3 - "$TMP/g4.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
m = re.search( r'<callees [^>]*>.*?</callees>', s, re.S )
t = m.group( 0 ) if m else ''
print( "rows=%d count12=%d next=%d" % ( t.count( '<s ' ), int( 'count="12"' in t ), int( ' next=' in t ) ) )
PY
)"
if [ "$( rc g4 )" = 0 ] && [ "$( rc g4a )" = 0 ] && [ "$( rc g4b )" = 0 ] && [ -n "$gap4" ] && [ "$gap4" = "$both4" ] \
   && [ "$callees4" = "rows=10 count12=1 next=1" ]; then ok "(g4) gap sides are capped at 10 rows and say so ($callees4)"
else no "(g4) rc=$( rc g4 )/$( rc g4a )/$( rc g4b ) callees='$callees4' gap_bytes=${#gap4} bare_bytes=${#both4}"; fi

# (n1) a non-path task holding the word path
run n1 --for="where is the config path parsed"
r="$( route n1 )"
if [ "$( rc n1 )" = 0 ] && [ "$r" != "-" ] && case "$r" in *"dropped:"*) false;; *) true;; esac && [ "$( count n1 '<graph_verb ' )" = 0 ] && [ "$( count n1 '<path_gap ' )" = 0 ]; then
    ok "(n1) 'where is the config path parsed' is not the form: route= '$r'"
else no "(n1) rc=$( rc n1 ) route='$r'"; fi

# (n2) `path from` behind a non-question lead-in
run n2 --for="strip the directory path from parse_config_path() to the end"
r="$( route n2 )"
if [ "$( rc n2 )" = 0 ] && [ "$r" != "-" ] && case "$r" in *"dropped:"*) false;; *) true;; esac \
   && [ "$( count n2 '<graph_verb ' )" = 0 ] && [ "$( count n2 '<path_gap ' )" = 0 ]; then ok "(n2) lead-in 'strip the directory' is not the form: route= '$r'"
else no "(n2) rc=$( rc n2 ) route='$r'"; fi

[ "$fail" = 0 ] && echo "graphformendpointscheck: PASS" || echo "graphformendpointscheck: FAIL"
exit "$fail"
