#!/usr/bin/env bash
# fordemoteallcheck.sh — DEMOTE-ALL-DIALECTS (src/fordemoteall.h, card B26): SIBLING-DEMOTE and DECL-TWIN in every dialect of --for, so a
# question gets one answer shape: the no-budget XML answer (CLI and MCP `for`), --json (a demoted row is the pointer object
# {"pointer":"demote"|"decl-twin","p":,"sym":,"r":}), and a soft target (--token-budget / budget_tokens), where the rules run before the
# rows settle and the bytes they free buy rows past the cut.
#
# ONE C++ tree, generated here: cfg.h declares WidgetConfigHdr::parse_widget_config / check_widget_config (one-line prototypes whose
# out-of-line bodies are in cfg.cc: DECL-TWIN), cfg.cc holds 16 same-file sibling helpers widget_config_variant_NN (past <d> rank 10:
# SIBLING-DEMOTE), and five one-row files o1..o5.cc. No row carries a guard the dialects read differently (no hop callee, slot or
# mem= row among the picks), so the pointer sets of the dialects agree here.
# ARMS (RED on a binary without the lane: (j), (j2), (jb), (b+), (xb); the rest hold on both)
#   (d)  precondition: the CLI default answer prints >= 1 demote pointer and >= 1 decl-twin pointer in <sigs>
#   (x)  MCP `for` (no budget): its <sigs> block is byte-identical to the CLI's
#   (j)  --json: the pointer objects are at exactly the ranks the XML default points at, each rule named as the XML legend names it
#        (the decl-twin ranks are the XML rows the decl-twin legend covers); (j2) each pointer's p / r are the off twin's row at that r,
#        its sym the XML row's n= there, and every other row object is byte-identical to the off twin's
#   (b)  --token-budget sweep N = 1000 1300 1600 2000, each against its RIPWIRE_NO_SIBLING_DEMOTE=1 RIPWIRE_NO_DECL_TWIN=1 twin:
#        (bp) the ranked entries (<d> rows and <t r=> pointers) are r = 1..K (a rank prefix, score order), (b>=) K >= the twin's rows,
#        (bm) K never falls as N grows; (b+) at some N the freed bytes buy rows: K > the twin's rows; (bw) well formed
#   (jb) --json --token-budget=1300: pointer objects present, rows + pointers >= the twin's rows, r = 1..K
#   (xb) MCP budget_tokens=1300: pointers present, r = 1..K, K >= its twin's rows, and a rank both MCP and the CLI (--token-budget=1300)
#        show is a pointer in both or a row in both
#   (k8) TERM-HIT (K8, B26-FIX): under a budget, a row a question term hits (K4's taskNames; an identifier token of the row's name, sc=
#        or printed signature) stays whole. TASK_K8 names zorbQuux, the parameter of variants 05..16: under --token-budget=2000 and MCP
#        budget_tokens=2000 every hit variant past <d> rank 10 is a <d> row (>= 1 such, counted); (k8n) premise: the variants no term
#        hits (01..04) past rank 10 are still pointers in those answers (counted; FAILS on zero); (k8d) no budget: K8 does not run, a
#        hit variant past rank 10 is a pointer in the default answer (counted; FAILS on zero)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "fordemoteallcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset RIPWIRE_NO_SIBLING_DEMOTE RIPWIRE_NO_DECL_TWIN   # an inherited value (even 0) turns a rule off
TASK='how is the widget config parsed and checked'
TASK_K8='how is the widget config parsed and checked, and where is zorbQuux read'

python3 - "$TMP/t/src" <<'PY' || { echo "fixture generator failed"; exit 2; }
import os, sys
d = sys.argv[1]; os.makedirs( d )
w = lambda p, s: open( os.path.join( d, p ), "w" ).write( s )
w( "cfg.h", "struct WidgetConfigHdr {\n  int parse_widget_config(int x);\n  int check_widget_config(int x);\n};\n" )
s = '''#include "cfg.h"
// Parse the widget config value.
int WidgetConfigHdr::parse_widget_config(int x) {
  int y = x + 1;
  return y;
}
// Check the widget config value.
int WidgetConfigHdr::check_widget_config(int x) {
  int y = x - 1;
  return y;
}
'''
for i in range( 1, 17 ):
    # (k8): variants 05..16 name zorbQuux in their signatures (a parameter: no row is named that), the term K8's task asks about
    s += f'''// Widget config variant {i}: a helper that reads one widget config field.
int widget_config_variant_{i:02d}(int {"zorbQuux" if i >= 5 else "x"}) {{
  int y = {"zorbQuux" if i >= 5 else "x"} * {i};
  return y;
}}
'''
w( "cfg.cc", s )
for i in range( 1, 6 ):
    w( f"o{i}.cc", f"// Widget config other {i}.\nint widget_config_other_{i}(int x) {{ return x + {i}; }}\n" )
PY

cat >"$TMP/ranks.py" <<'PY'
"""ranks.py FILE xml|json -> one line: rows pointers r-list (r+kind, answer order), kinds per pointer (xml: demote/decl from the legend)"""
import json, re, sys
f, kind = sys.argv[1], sys.argv[2]
if kind == "json":
    d = json.load( open( f ) )
    ent = [ ( x["r"], "t" if "pointer" in x else "d", x.get( "pointer", "" ) ) for x in d["sigs"] ]
else:
    s = open( f ).read(); s = s[s.find( "<sigs" ):s.find( "</sigs>" )]
    ent, rule = [], ""
    for m in re.finditer( r'<!-- (demote|decl-twin):|<(d|t) ([^>]*?)/?>', s ):
        if m.group( 1 ): rule = m.group( 1 ); continue
        r = re.search( r'\br="(\d+)"', m.group( 3 ) )
        if r: ent.append( ( int( r.group( 1 ) ), m.group( 2 ), rule if m.group( 2 ) == "t" else "" ) )
rows = sum( 1 for e in ent if e[1] == "d" )
print( rows, len( ent ), " ".join( "%d%s" % ( e[0], e[1] ) for e in ent ), " ".join( "%d:%s" % ( e[0], e[2] ) for e in ent if e[1] == "t" ) )
PY
rk(){ python3 "$TMP/ranks.py" "$1" "${2:-xml}"; }
prefix(){ python3 - "$1" <<'PY'
import sys
r = sorted( int( x[:-1] ) for x in sys.argv[1].split() )
print( "yes" if r == list( range( 1, len( r ) + 1 ) ) else "no" )
PY
}
OFF=( env RIPWIRE_NO_SIBLING_DEMOTE=1 RIPWIRE_NO_DECL_TWIN=1 )
run(){ ( cd "$TMP/t" && "$BIN" . --no-cache "--for=$TASK" "$@" ); }
runoff(){ ( cd "$TMP/t" && "${OFF[@]}" "$BIN" . --no-cache "--for=$TASK" "$@" ); }
mcp(){ # mcp OUT [BUDGET] [env...]
    local out="$1" b=""; shift; [ -n "${1:-}" ] && b=",\"budget_tokens\":$1"; shift || true
    printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"%s}}}\n' "$TMP/t" "${MCPTASK:-$TASK}" "$b" \
      | ( cd "$TMP/t" && "$@" "$BIN" --mcp 2>/dev/null ) | python3 -c '
import json, sys
for line in sys.stdin:
    d = json.loads( line )
    if d.get( "id" ) == 1: print( d["result"]["content"][0]["text"], end="" )
' >"$out"
}
sigs(){ python3 -c 'import sys; s = open( sys.argv[1] ).read(); print( s[s.find( "<sigs" ):s.find( "</sigs>" ) + 7] )' "$1"; }

# (d) precondition
run >"$TMP/on.xml" || no "(d) the default run exited non-zero"
dkinds="$( rk "$TMP/on.xml" | awk '{ for( i = 1; i <= NF; ++i ) if( $i ~ /:/ ) printf "%s ", $i }' )"
case "$dkinds" in *":demote "*) case "$dkinds" in *":decl-twin "*) ok "(d) the default answer points at deep siblings and twinned prototypes: $dkinds";; *) no "(d) no decl-twin pointer: $dkinds";; esac;; *) no "(d) no demote pointer: $dkinds";; esac

# (x) MCP no-budget <sigs> == CLI
mcp "$TMP/m.xml" "" env
if [ -s "$TMP/m.xml" ] && [ "$( sigs "$TMP/m.xml" )" = "$( sigs "$TMP/on.xml" )" ]; then ok "(x) MCP for: <sigs> byte-identical to the CLI's"; else no "(x) MCP <sigs> differs from the CLI's"; fi

# (j) --json pointers at the XML default's ranks, each named for its rule; (j2) the rows around them unchanged
run --json >"$TMP/on.json"; runoff --json >"$TMP/off.json"; runoff >"$TMP/off.xml"
jk="$( rk "$TMP/on.json" json | awk '{ for( i = 1; i <= NF; ++i ) if( $i ~ /:/ ) printf "%s ", $i }' )"
if [ -n "$jk" ] && [ "$jk" = "$dkinds" ]; then ok "(j) --json: pointer objects at the XML default's ranks, same rules ($( echo "$jk" | wc -w | tr -d ' ' ) pointers)"
else no "(j) --json pointers [$jk] vs XML [$dkinds]"; fi
j2="$( python3 - "$TMP/on.json" "$TMP/off.json" "$TMP/off.xml" <<'PY'
import html, json, re, sys
on, off = json.load( open( sys.argv[1] ) )["sigs"], json.load( open( sys.argv[2] ) )["sigs"]
x = open( sys.argv[3] ).read(); x = x[x.find( "<sigs" ):x.find( "</sigs>" )]
xn = { int( r ): html.unescape( n ) for n, r in re.findall( r'<d [^>]*?\bn="([^"]*)"[^>]*?\br="(\d+)"', x ) }
offr = { o["r"]: o for o in off }
bad = []
if [ o["r"] for o in on ] != [ o["r"] for o in off ]: bad.append( "ranks differ" )
for o in on:
    t = offr.get( o["r"] )
    if t is None: bad.append( "r%d not in the twin" % o["r"] ); continue
    if "pointer" in o:
        if sorted( o ) != [ "p", "pointer", "r", "sym" ] or o["p"] != t["p"] or o["sym"] != xn.get( o["r"] ): bad.append( "pointer r%d %s" % ( o["r"], o ) )
    elif json.dumps( o, sort_keys = True ) != json.dumps( t, sort_keys = True ): bad.append( "row r%d changed" % o["r"] )
print( ";".join( bad ) or "ok" )
PY
)"
if [ "$j2" = ok ]; then ok "(j2) --json: each pointer is the twin's row (p, r, the XML n= as sym), every other row unchanged"; else no "(j2) $j2"; fi

# (b) the soft target sweep
prev=0; plus=""; bok=1
for N in 1000 1300 1600 2000; do
    run --token-budget=$N >"$TMP/b$N.xml"; runoff --token-budget=$N >"$TMP/b$N.off"
    on="$( rk "$TMP/b$N.xml" )"; of="$( rk "$TMP/b$N.off" )"
    ent="$( echo "$on" | awk '{ print $2 }' )"; offrows="$( echo "$of" | awk '{ print $1 }' )"
    list="$( echo "$on" | awk '{ for( i = 3; i <= NF; ++i ) if( $i !~ /:/ ) printf "%s ", $i }' )"
    [ "$( prefix "$list" )" = yes ] || { no "(bp) N=$N: the ranked entries are not r = 1..K: $list"; bok=0; }
    [ "$ent" -ge "$offrows" ] || { no "(b>=) N=$N: $ent ranked entries < the twin's $offrows rows"; bok=0; }
    [ "$ent" -ge "$prev" ] || { no "(bm) N=$N: $ent ranked entries < $prev at the smaller N"; bok=0; }
    [ "$ent" -gt "$offrows" ] && plus="$plus N=$N:$offrows->$ent"
    if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$TMP/b$N.xml" 2>/dev/null || { no "(bw) N=$N is not well formed"; bok=0; }; fi
    prev="$ent"
done
[ "$bok" = 1 ] && ok "(bp/b>=/bm/bw) --token-budget 1000..2000: rank prefixes, never fewer than the twin's rows, monotone in N, well formed"
if [ -n "$plus" ]; then ok "(b+) the freed bytes buy rows:$plus"; else no "(b+) no budget served more ranked entries than its undemoted twin"; fi

# (jb) --json under a soft target
run --json --token-budget=1300 >"$TMP/jb.json"; runoff --json --token-budget=1300 >"$TMP/jb.off"
jb="$( rk "$TMP/jb.json" json )"; jbo="$( rk "$TMP/jb.off" json | awk '{ print $1 }' )"
jbl="$( echo "$jb" | awk '{ for( i = 3; i <= NF; ++i ) if( $i !~ /:/ ) printf "%s ", $i }' )"
if echo "$jb" | grep -q ':demote' && [ "$( echo "$jb" | awk '{ print $2 }' )" -ge "$jbo" ] && [ "$( prefix "$jbl" )" = yes ]; then
    ok "(jb) --json --token-budget=1300: pointers, $( echo "$jb" | awk '{ print $2 }' ) entries >= the twin's $jbo rows, a rank prefix"
else no "(jb) --json --token-budget=1300: [$jb] twin rows $jbo"; fi

# (xb) MCP budget_tokens
mcp "$TMP/xb.xml" 1300 env; mcp "$TMP/xb.off" 1300 "${OFF[@]}"
xb="$( rk "$TMP/xb.xml" )"; xbo="$( rk "$TMP/xb.off" | awk '{ print $1 }' )"
xbl="$( echo "$xb" | awk '{ for( i = 3; i <= NF; ++i ) if( $i !~ /:/ ) printf "%s ", $i }' )"
agree="$( python3 - "$xbl" "$( echo "$( rk "$TMP/b1300.xml" )" | awk '{ for( i = 3; i <= NF; ++i ) if( $i !~ /:/ ) printf "%s ", $i }' )" <<'PY'
import sys
a = { x[:-1]: x[-1] for x in sys.argv[1].split() }; b = { x[:-1]: x[-1] for x in sys.argv[2].split() }
print( ",".join( r for r in a if r in b and a[r] != b[r] ) or "ok" )
PY
)"
if echo "$xb" | grep -q ':demote' && [ "$( echo "$xb" | awk '{ print $2 }' )" -ge "$xbo" ] && [ "$( prefix "$xbl" )" = yes ] && [ "$agree" = ok ]; then
    ok "(xb) MCP budget_tokens=1300: pointers, $( echo "$xb" | awk '{ print $2 }' ) entries >= the twin's $xbo rows, a rank prefix, the CLI's reading on every shared rank"
else no "(xb) MCP budget_tokens=1300: [$xb] twin rows $xbo, disagreeing ranks: $agree"; fi

# (k8) TERM-HIT: a budgeted row a question term hits stays whole; (k8n) its premise; (k8d) the no-budget answer is untouched
k8(){ # k8 FILE -> "<hit rows past r10> <hit pointers> <unhit pointers>" over widget_config_variant_NN (hit: NN >= 05)
    python3 - "$1" <<'PY'
import re, sys
s = open( sys.argv[1] ).read(); s = s[s.find( "<sigs" ):s.find( "</sigs>" )]
hr = hp = up = 0
for m in re.finditer( r'<(d|t) [^>]*?(?:n|sym)="widget_config_variant_(\d+)"[^>]*?\br="(\d+)"', s ):
    hit = int( m.group( 2 ) ) >= 5
    if m.group( 1 ) == "t": hp += hit; up += not hit
    elif hit and int( m.group( 3 ) ) > 10: hr += 1
print( hr, hp, up )
PY
}
( cd "$TMP/t" && "$BIN" . --no-cache "--for=$TASK_K8" --token-budget=2000 ) >"$TMP/k8.xml"
( cd "$TMP/t" && "$BIN" . --no-cache "--for=$TASK_K8" ) >"$TMP/k8d.xml"
MCPTASK="$TASK_K8" mcp "$TMP/k8m.xml" 2000 env
read -r k8r k8h k8u <<<"$( k8 "$TMP/k8.xml" )"; read -r k8mr k8mh k8mu <<<"$( k8 "$TMP/k8m.xml" )"; read -r _ k8dh _ <<<"$( k8 "$TMP/k8d.xml" )"
if [ "$k8r" -ge 1 ] && [ "$k8h" = 0 ] && [ "$k8mr" -ge 1 ] && [ "$k8mh" = 0 ]; then
    ok "(k8) --token-budget=2000 / MCP budget_tokens=2000: every variant zorbQuux hits stays a row ($k8r / $k8mr of them past rank 10), none is a pointer"
else no "(k8) a term-hit variant was pointed under a budget: CLI rows past r10 $k8r, pointers $k8h; MCP rows past r10 $k8mr, pointers $k8mh"; fi
if [ "$k8u" -ge 1 ] && [ "$k8mu" -ge 1 ]; then ok "(k8n) premise: the same budgeted answers still point $k8u (CLI) / $k8mu (MCP) variants no term hits"
else no "(k8n) premise: no pointer among the variants no term hits (CLI $k8u, MCP $k8mu) — the arm proves nothing"; fi
if [ "$k8dh" -ge 1 ]; then ok "(k8d) no budget: K8 does not run — $k8dh hit variant(s) past rank 10 are pointers in the default answer"
else no "(k8d) no hit variant is a pointer in the default answer ($k8dh): K8 ran without a budget, or the premise is gone"; fi

[ "$fail" = 0 ] && echo "fordemoteallcheck: PASS" || echo "fordemoteallcheck: FAIL"
exit "$fail"
