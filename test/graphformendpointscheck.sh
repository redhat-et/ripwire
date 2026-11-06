#!/usr/bin/env bash
# graphformendpointscheck.sh — GRAPH-FORM-ENDPOINTS (src/lexical.h parsePathFormSpans, src/subjectanchor.h, src/verbs_for.h
# appendPathGapSides): a --for task worded as a two-endpoint graph question ranks on its two endpoints only, its frame words are
# dropped (route= says `dropped:`), and when the path verb it runs finds no path, <path_gap> prints from='s callees and to='s callers.
#   (f1) `what is the path from A to B`: route= drops `path`; the path is found, so no <path_gap>, and the <graph_verb> block is
#        byte-identical to the bare --path= call (compact legend; RIPWIRE_NO_HOP_BODY=1, as forroutecheck (v1))
#   (f2) `call chain from <plain words> to <plain words>`: NOT the form (no endpoint is a name; the frame describes the task too)
#   (f2b) `call chain from <name> to <plain words>`: the form, route= drops `call chain`; the prose side resolves nothing, no graph block
#   (f3) `how does A reach B`: route= drops `reach`
#   (f4) `lowest common caller of A and B`: route= drops `lowest common caller`; the --connect block still runs
#   (g1) gap: `path from A to B` with no directed path: reachable="0", then <path_gap from= to=> holding A's callees answer (its
#        callee listed) and B's callers answer (its caller listed), once, inside the graph block, well-formed, legend without `--`
#   (g2) the gap sides are the bare --callees= / --callers= answers, byte for byte
#   (n1) "where is the config path parsed": not the form (no dropped:, no graph block, no path_gap)
#   (n2) "strip the directory path from a_start() to the end": not the form (lead-in), no dropped:
#   (n3) a qualifier tail is not ranked: "path from A to B for the cache" drops `cache` too (route= names it)
#   (c1) a crashing / silent binary turns the arms red (the arms read rc and require their positive text)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "graphformendpointscheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
int main( void ) { startEntry(); other_caller(); lonely_start(); beta_caller(); parse_config_path(); return 0; }
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
if [ "$( rc f1 )" = 0 ] && [ "$( rc f1v )" = 0 ] && case "$r" in *"dropped: path"*) true;; *) false;; esac \
   && [ "$( count f1 '<path_gap ' )" = 0 ] && grep -q 'reachable="1"' "$TMP/f1.xml" && [ -n "$bare" ] && [ "$blk" = "$bare" ]; then
    ok "(f1) path form: route= '$r' drops path; path found, no <path_gap>; graph block == bare --path"
else no "(f1) rc=$( rc f1 )/$( rc f1v ) route='$r' path_gap=$( count f1 '<path_gap ' ) block_eq=$( [ "$blk" = "$bare" ] && echo 1 || echo 0 )"; fi

# (f2) call chain from plain words to plain words: no endpoint is a name, so not the form (the frame describes the task too)
run f2 --for="call chain from the router service call to the handler function"
r="$( route f2 )"
if [ "$( rc f2 )" = 0 ] && [ "$r" != "-" ] && case "$r" in *"dropped:"*) false;; *) true;; esac && [ "$( count f2 '<graph_verb ' )" = 0 ]; then
    ok "(f2) two prose endpoints are not the form: route= '$r'"
else no "(f2) rc=$( rc f2 ) route='$r' graph_verb=$( count f2 '<graph_verb ' )"; fi

# (f2b) call chain from a NAME to plain words: the form (one named endpoint is enough); the prose side names no symbol, so no graph block
run f2b --for="call chain from startEntry to the sink function"
r="$( route f2b )"
if [ "$( rc f2b )" = 0 ] && case "$r" in *"dropped: call chain"*) true;; *) false;; esac && [ "$( count f2b '<graph_verb ' )" = 0 ]; then
    ok "(f2b) one named endpoint: route= '$r'"
else no "(f2b) rc=$( rc f2b ) route='$r' graph_verb=$( count f2b '<graph_verb ' )"; fi

# (f3) how does A reach B
run f3 --for="how does startEntry reach leaf_sink"
r="$( route f3 )"
if [ "$( rc f3 )" = 0 ] && case "$r" in *"dropped: reach"*) true;; *) false;; esac; then ok "(f3) reach form: route= '$r'"
else no "(f3) rc=$( rc f3 ) route='$r'"; fi

# (f4) lowest common caller of A and B
run f4 --for="lowest common caller of mid_hop and other_caller"
r="$( route f4 )"
if [ "$( rc f4 )" = 0 ] && case "$r" in *"dropped: lowest common caller"*) true;; *) false;; esac && [ "$( count f4 '<connect ' )" = 1 ]; then
    ok "(f4) common-caller form: route= '$r', --connect block runs"
else no "(f4) rc=$( rc f4 ) route='$r' connect=$( count f4 '<connect ' )"; fi

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
print( "n=%d reach0=%d from=%s to=%s missing=%d callee=%d caller=%d legdash=%d" % (
    s.count( '<path_gap ' ), int( ' reachable="0"' in inner ),
    ( re.search( r'from="([^"]*)"', a ) or [0, '-'] )[1], ( re.search( r'\bto="([^"]*)"', a ) or [0, '-'] )[1], int( 'missing=' in a ),
    int( 'helper_alpha' in body ), int( 'beta_caller' in body ), int( '--' in leg.group( 1 ) ) if leg else 9 ) )
PY
)"
if [ "$( rc g1 )" = 0 ] && [ "$facts" = "n=1 reach0=1 from=lonely_start to=target_end missing=0 callee=1 caller=1 legdash=0" ] \
   && case "$( route g1 )" in *"dropped: path"*) true;; *) false;; esac && xmlok "$TMP/g1.xml"; then
    ok "(g1) gap: reachable=0, <path_gap> lists from's callee and to's caller ($facts)"
else no "(g1) rc=$( rc g1 ) facts='$facts' route='$( route g1 )'"; fi

# (g2) the two sides are the bare --callees= / --callers= answers
run g2a --callees=lonely_start
run g2b --callers=target_end
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

# (n1) a non-path task holding the word path
run n1 --for="where is the config path parsed"
r="$( route n1 )"
if [ "$( rc n1 )" = 0 ] && [ "$r" != "-" ] && case "$r" in *"dropped:"*) false;; *) true;; esac && [ "$( count n1 '<graph_verb ' )" = 0 ] && [ "$( count n1 '<path_gap ' )" = 0 ]; then
    ok "(n1) 'where is the config path parsed' is not the form: route= '$r'"
else no "(n1) rc=$( rc n1 ) route='$r'"; fi

# (n2) `path from` behind a non-question lead-in
run n2 --for="strip the directory path from parse_config_path() to the end"
r="$( route n2 )"
if [ "$( rc n2 )" = 0 ] && [ "$r" != "-" ] && case "$r" in *"dropped:"*) false;; *) true;; esac; then ok "(n2) lead-in 'strip the directory' is not the form: route= '$r'"
else no "(n2) rc=$( rc n2 ) route='$r'"; fi

# (n3) the qualifier tail is not ranked, and route= says so
run n3 --for="path from startEntry to leaf_sink for the cache"
r="$( route n3 )"
if [ "$( rc n3 )" = 0 ] && case "$r" in *"dropped: path"*cache*) true;; *) false;; esac; then ok "(n3) qualifier tail dropped: route= '$r'"
else no "(n3) rc=$( rc n3 ) route='$r'"; fi

[ "$fail" = 0 ] && echo "graphformendpointscheck: PASS" || echo "graphformendpointscheck: FAIL"
exit "$fail"
