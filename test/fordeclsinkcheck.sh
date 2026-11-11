#!/usr/bin/env bash
# fordeclsinkcheck.sh — DECL-SINK and DECL-TWIN (src/fordeclsink.h, precision card B14): a ONE-LINE OWNER-QUALIFIED DECLARATION row of
# <sigs> (l= equals e=, n= Owner.member / Owner::member) is a signature, not the definition. DECL-TWIN (first) prints such a row whose
# last segment names a BODIED <sigs> <d> row of the answer (l= and e= present, unequal) as a tail pointer <t p= sym= r=/> in its place;
# DECL-SINK (then) moves such a row among the first 10 answer rows (not a constant, no in=) to just after the 10th other <d> row. Keep guards (SIBLING-DEMOTE's): K1/K7 mem= / slot_by= /
# slot_fields=, K6 a <note>, K4 the task names the row (a qualified task word names the full name, a bare one the last segment).
#
# TWO trees. ts/: an interface WidgetService (readWidgetConfig at answer row 2, checkWidgetConfig), an interface WidgetParser whose
# parseWidgetConfig has a bodied twin in impl.ts, a one-line method with a caller (WidgetConfigUser.useWidgetConfig: in=1), a bodied
# check function at row 1 and 14 helpers (ten in a file each). cpp/: an in-class prototype WidgetConfigHdr::parse_widget_config with an out-of-line body, a
# prototype a member-pointer table calls (stop_widget_config: slot_by=), a static const member (WidgetConfigLimits::widget_config_max).
# ARMS (RED on a binary without the rules: (s), (s2), (t), (t2), (a) with rows, (l), (x); the negatives hold on both)
#   (a)  each answer equals its RIPWIRE_NO_DECL_SINK=1 RIPWIRE_NO_DECL_TWIN=1 twin with exactly the rows the rules pick (recomputed here
#        from the off answer) moved / rewritten, the legend comment of each rule that fired before its rows, est_tokens= aside
#   (s)  a TypeScript interface member at answer row 2 (WidgetService.readWidgetConfig) sinks to answer row 11, its bytes intact
#   (s2) WidgetService.checkWidgetConfig (row 10) sinks too, to row 12
#   (t)  a twinned declaration goes to the tail: cpp WidgetConfigHdr::parse_widget_config (a first-10 row, its cfg.cc body row in the
#        answer) is a pointer in its place;  (t2) ts WidgetParser.parseWidgetConfig (its body parseWidgetConfig printed) too
#   NEGATIVES, each a one-line owner-qualified row in the first 10 answer rows of the off answer, that stays a row and keeps its place
#        among the unmoved rows:
#   (n1) a constant: WidgetConfigLimits::widget_config_max (static const)     (n2) an in= row: WidgetConfigUser.useWidgetConfig
#   (n3) a slot row: WidgetConfigHdr::stop_widget_config (slot_by=)          (n4) a noted row: a --note-add note on readWidgetConfig
#   (n5) a task-named row: a task naming WidgetService.readWidgetConfig keeps it; the twin task naming another owner's member
#        (Checker.readWidgetConfig) does not keep WidgetService.readWidgetConfig
#   (n6) a mem= row: every extractor names a type row bare (C++, C#, Java, Kotlin, Swift, Scala, TypeScript, Python, Ruby probed), and
#        mem= rides only on class/struct/interface rows, so a mem= row is never owner-qualified: the arm checks that every mem= row of
#        both trees stays put (structural; the guard is SIBLING-DEMOTE's K1, kept for one guard set)
#   (b)  --token-budget leaves the answer as shaped: no decl legend, byte-identical to the off twin under the same budget
#   (b2) a bare --max-tokens (not read by --for) does not hold the rules: byte-identical to the flagless answer
#   (j)  --json never reaches the rules: byte-identical to the off twin
#   (e)  est_tokens= is re-priced on the final bytes (estchargecheck holds the rate); (w) well formed; (l) each legend once, no "--" inside
#   (x)  MCP `for` (one renderer): (a) on the MCP answer and its off twin
#   (o)  off twins: RIPWIRE_NO_DECL_SINK=1 alone leaves only pointers, RIPWIRE_NO_DECL_TWIN=1 alone only the sink
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "fordeclsinkcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export RIPWIRE_NO_SIBLING_DEMOTE=1   # the decl rules alone (forsiblingdemotecheck owns the demote; (sd) below runs both)
TTASK='how is the widget config value checked'
CTASK='how is the widget config parsed and stopped'

python3 - "$TMP" <<'PY' || { echo "fixture generator failed"; exit 2; }
import os, sys
d = sys.argv[1]
os.makedirs( d + "/ts/src" ); os.makedirs( d + "/cpp/src" )
w = lambda p, s: open( os.path.join( d, p ), "w" ).write( s )
w( "ts/src/types.ts", '''export interface WidgetService {
  /** Read the widget config value that is checked. */
  readWidgetConfig(path: string): string;
  /** Check the widget config value. */
  checkWidgetConfig(value: number): boolean;
}
export interface WidgetParser {
  /** Parse the widget config text. */
  parseWidgetConfig(text: string): number;
}
''' )
w( "ts/src/check.ts", '''/** How the widget config is checked: the value must be positive. */
export function widgetConfigCheckValue(value: number): boolean {
  const ok = value > 0;
  return ok;
}
''' )
w( "ts/src/impl.ts", '''export function parseWidgetConfig(text: string): number {
  const n = text.length;
  return n + 1;
}
export class WidgetConfigUser {
  useWidgetConfig(x: number): number { return x; }
  run(text: string): number {
    const v = this.useWidgetConfig(1);
    return v + parseWidgetConfig(text);
  }
}
''' )
helper = lambda i: f'''export function widgetConfigHelper{i:02d}(x: number): number {{
  const y = x + {i};
  return y;
}}
'''
for i in range( 1, 11 ):   # one file each: SIBLING-DEMOTE (arm sd) leaves them rows
    w( f"ts/src/h{i:02d}.ts", helper( i ) )
w( "ts/src/helpers.ts", "".join( helper( i ) for i in range( 11, 15 ) ) )
w( "cpp/src/cfg.h", '''struct WidgetConfigLimits { static const int widget_config_max = 3; };
struct WidgetConfigOuter { struct WidgetConfigInner { int widget_a; int widget_b; }; };
struct WidgetConfigHdr { int parse_widget_config(int x); int stop_widget_config(int x); };
typedef int (WidgetConfigHdr::*WidgetConfigFn)(int);
''' )
w( "cpp/src/cfg.cc", '''#include "cfg.h"
int WidgetConfigHdr::parse_widget_config(int x) {
  int y = x + 1;
  return y;
}
struct WidgetConfigSlot { const char* name; WidgetConfigFn fn; };
static const WidgetConfigSlot kWidgetConfigSlots[] = { { "parse", &WidgetConfigHdr::parse_widget_config }, { "stop", &WidgetConfigHdr::stop_widget_config } };
struct WidgetConfigBox { WidgetConfigHdr hdr; const WidgetConfigSlot* slot; };
int go_widget_config(int k) {
  WidgetConfigBox box;
  box.slot = &kWidgetConfigSlots[k];
  return (box.hdr.*box.slot->fn)(k);
}
''' )
PY

cat >"$TMP/ref.py" <<'PY'
"""ref.py OFF ON TASK [twin,sink] -> the DECL rules recomputed on OFF (independent of the C++): `sunk`, `ptr` names and PASS/FAIL (a)."""
import re, sys
ATTR = re.compile( r'([\w:-]+)="([^"]*)"' )
def unesc( v ): return v.replace( "&lt;", "<" ).replace( "&gt;", ">" ).replace( "&quot;", '"' ).replace( "&apos;", "'" ).replace( "&amp;", "&" )
def mask( t ): return re.sub( r"<!--.*?-->|<!\[CDATA\[.*?\]\]>", lambda m: " " * len( m.group( 0 ) ), t, flags = re.S )
def rows( t ):
    m = mask( t ); out = []
    sigs = [ ( x.start(), m.find( "</sigs>", x.start() ) ) for x in re.finditer( r"<sigs[ >]", m ) ]
    for x in re.finditer( r'<(d|y|s|u) ([^>]*?)(/?)>', m ):
        a = { k: unesc( v ) for k, v in ATTR.findall( x.group( 2 ) ) }
        if x.group( 1 ) == "u" and a.get( "v" ) == "used": continue
        e = x.end()
        if x.group( 1 ) == "d" and not x.group( 3 ): e = m.find( "</d>", e ) + 4
        out.append( dict( tag = x.group( 1 ), a = a, raw = dict( ATTR.findall( x.group( 2 ) ) ), s = x.start(), e = e, pos = len( out ) + 1,
                          sigs = any( a0 < x.start() < b0 for a0, b0 in sigs ) ) )
    return out
def last( n ): return re.split( r"::|\.|#", n )[-1]
WORD = re.compile( r"[A-Za-z_~][\w]*(?:(?:\.|::|#)[A-Za-z_~#][\w]*)*" )
def task_words( task ): return [ w for w in WORD.findall( task ) if "." in w or "::" in w or "_" in w or re.search( r"[a-z][A-Z]", w ) ]
def named( n, task ):
    q = n.replace( "::", "." ).replace( "#", "." )
    for w in task_words( task ):
        w2 = w.replace( "::", "." ).replace( "#", "." )
        if "." in w2:
            if q == w2 or q.endswith( "." + w2 ): return True
        elif last( n ) == w: return True
    return False
def decl( r ):
    n = r["a"].get( "n", "" ); i = min( [ x for x in ( n.find( "." ), n.find( "::" ) ) if x >= 0 ] or [ -1 ] )
    return r["tag"] == "d" and r["sigs"] and r["a"].get( "l" ) and r["a"].get( "l" ) == r["a"].get( "e" ) and i > 0
def kept( r, t, task ):
    return "<note " in t[r["s"]:r["e"]] or any( k in r["a"] for k in ( "mem", "slot_by", "slot_fields" ) ) or named( r["a"].get( "n", "" ), task )
def const( r, t ):
    b = t[r["s"]:r["e"]]; b = b[b.find( ">" ) + 1:]
    if b.startswith( "<doc>" ): b = b[b.find( "</doc>" ) + 6:]
    return re.match( r"[ \t]*(const|var|enum|#define|static const|let |export const)", b ) is not None
def sink( t, task ):
    R = rows( t ); S = []; stay = 0; after = None
    for r in R:
        if r["tag"] != "d": continue
        if r["pos"] <= 10 and decl( r ) and "in" not in r["a"] and not const( r, t ) and not kept( r, t, task ): S.append( r )
        else:
            stay += 1
            if stay == 10: after = r; break
    if not S or after is None or not after["sigs"]: return t, []
    out, at = [], 0
    for r in S: out.append( t[at:r["s"]] ); at = r["e"]
    out.append( t[at:after["e"]] )
    out.append( ( "<!-- decl-sink: the next <d> row is a one-line Owner.member declaration" if len( S ) == 1 else
                  "<!-- decl-sink: the next %d <d> rows are one-line Owner.member declarations" % len( S ) )
                + " moved down from the first 10 answer rows (r= keeps its rank; none removed) -->" )
    out += [ t[r["s"]:r["e"]] for r in S ]
    return "".join( out ) + t[after["e"]:], [ r["a"]["n"] for r in S ]
LEG = ( "<!-- decl-twin: a <t> in sigs is a one-line Owner.member declaration whose bodied same-name row is in this answer, a pointer "
        "(p= file, sym= name, r= rank), not the answer -->" )
def twin( t, task ):
    R = rows( t )
    bodied = { last( r["a"].get( "n", "" ) ) for r in R if r["tag"] == "d" and r["sigs"] and r["a"].get( "l" ) and r["a"].get( "e" ) and r["a"].get( "l" ) != r["a"].get( "e" ) }
    P = [ r for r in R if decl( r ) and not kept( r, t, task ) and last( r["a"]["n"] ) in bodied ]
    exp, at = [], 0
    for k, r in enumerate( P ):
        exp += [ t[at:r["s"]], LEG if k == 0 else "", '<t p="%s" sym="%s"%s/>' % ( r["raw"]["p"], r["raw"]["n"], ' r="%s"' % r["raw"]["r"] if "r" in r["raw"] else "" ) ]
        at = r["e"]
    return "".join( exp ) + t[at:], [ r["a"]["n"] for r in P ]
off, on, task = open( sys.argv[1] ).read(), open( sys.argv[2] ).read(), sys.argv[3]
modes = sys.argv[4] if len( sys.argv ) > 4 else "twin,sink"
exp, S, P = off, [], []
if "twin" in modes: exp, P = twin( exp, task )
if "sink" in modes: exp, S = sink( exp, task )
est = lambda s: re.sub( r' est_tokens="\d+"', "", s, count = 1 )
print( "sunk " + ",".join( S ) )
print( "ptr " + ",".join( P ) )
print( ( "PASS" if est( exp ) == est( on ) else "FAIL" ) + " (a) %d sunk %d pointers" % ( len( S ), len( P ) ) )
PY
# pos NAME FILE: the answer-row position of the <d> row NAME (0 when it is not a <d> row); ptr NAME FILE: 1 when it is an in-sigs pointer
cat >"$TMP/pos.py" <<'PY'
import re, sys
t = re.sub( r"<!--.*?-->|<!\[CDATA\[.*?\]\]>", "", open( sys.argv[2] ).read(), flags = re.S )
want = sys.argv[3]
if sys.argv[1] == "ptr":
    s = t[t.find( "<sigs" ):t.find( "</sigs>" )]
    print( 1 if want.replace( "&", "&amp;" ) in re.findall( r'<t p="[^"]*" sym="([^"]*)"', s ) else 0 ); sys.exit()
k = 0
for m in re.finditer( r'<(d|y|s|u) ([^>]*?)/?>', t ):
    if m.group( 1 ) == "u" and 'v="used"' in m.group( 2 ): continue
    k += 1
    if m.group( 1 ) == "d" and re.search( r'\bn="([^"]*)"', m.group( 2 ) ).group( 1 ) == want: print( k ); sys.exit()
print( 0 )
PY
pos(){ python3 "$TMP/pos.py" pos "$2" "$1"; }
isptr(){ [ "$( python3 "$TMP/pos.py" ptr "$2" "$1" )" = 1 ]; }
OFFENV=( env RIPWIRE_NO_DECL_SINK=1 RIPWIRE_NO_DECL_TWIN=1 )
run(){ local tree="$1"; shift; ( cd "$TMP/$tree" && "$BIN" . --no-cache "$@" ); }
runoff(){ local tree="$1"; shift; ( cd "$TMP/$tree" && "${OFFENV[@]}" "$BIN" . --no-cache "$@" ); }
check_a(){ # check_a ID OFF ON TASK [modes]
    python3 "$TMP/ref.py" "$2" "$3" "$4" "${5:-twin,sink}" >"$TMP/$1.res" 2>&1
    if grep -q '^PASS (a)' "$TMP/$1.res" && ! grep -q '^PASS (a) 0 sunk 0 pointers' "$TMP/$1.res"; then ok "(a) $1: the off answer with exactly the rules' rows moved ($( grep -o '[0-9]* sunk [0-9]* pointers' "$TMP/$1.res" ))"
    else no "(a) $1: $( head -c 700 "$TMP/$1.res" )"; fi
}
# stays NAME OFF ON WHAT: a row of the off answer's first 10 that keeps its place among the unmoved rows
stays(){
    local id="$1" n="$2" po pn moved
    po="$( pos "$n" "$3" )"; pn="$( pos "$n" "$4" )"
    moved="$( python3 - "$3" "$TMP/$5.res" "$n" <<'PY'
import re, sys
t = re.sub( r"<!--.*?-->|<!\[CDATA\[.*?\]\]>", "", open( sys.argv[1] ).read(), flags = re.S )
res = open( sys.argv[2] ).read().split( "\n" )
sunk = [ x for x in res[0][5:].split( "," ) + res[1][4:].split( "," ) if x ]   # sunk rows and pointers both leave the rows above it
names = []
for m in re.finditer( r'<(d|y|s|u) ([^>]*?)/?>', t ):
    if m.group( 1 ) == "u" and 'v="used"' in m.group( 2 ): continue
    names.append( ( re.search( r'\bn="([^"]*)"', m.group( 2 ) ) or re.search( r'p="([^"]*)"', m.group( 2 ) ) ).group( 1 ) if m.group( 1 ) == "d" else "" )
k = names.index( sys.argv[3] ) if sys.argv[3] in names else -1
print( sum( 1 for x in names[:k] if x in sunk ) )
PY
)"
    if [ "$po" -ge 1 ] && [ "$po" -le 10 ] && [ "$pn" = "$(( po - moved ))" ] && ! isptr "$n" "$4"; then ok "($id) $n stays a row in place: $6 (off row $po, on row $pn, $moved moved from above it)"
    else no "($id) $n: $6 — off row $po, on row $pn ($moved moved from above it; a negative must sit in the first 10 of the off answer)"; fi
}

# ---- ts tree
run ts "--for=$TTASK" >"$TMP/ts.on"; rc1=$?
runoff ts "--for=$TTASK" >"$TMP/ts.off"; rc2=$?
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] || no "ts runs exited $rc1 / $rc2"
check_a ts "$TMP/ts.off" "$TMP/ts.on" "$TTASK"
p2="$( pos WidgetService.readWidgetConfig "$TMP/ts.off" )"; p11="$( pos WidgetService.readWidgetConfig "$TMP/ts.on" )"
if [ "$p2" = 2 ] && [ "$p11" = 11 ]; then ok "(s) the TypeScript interface member WidgetService.readWidgetConfig sinks from answer row 2 to row 11"; else no "(s) WidgetService.readWidgetConfig off row $p2, on row $p11 (want 2 -> 11)"; fi
p7="$( pos WidgetService.checkWidgetConfig "$TMP/ts.off" )"; p12="$( pos WidgetService.checkWidgetConfig "$TMP/ts.on" )"
if [ "${p7:-99}" -le 10 ] && [ "$p12" = 12 ]; then ok "(s2) WidgetService.checkWidgetConfig sinks from row $p7 to row 12, after readWidgetConfig"; else no "(s2) WidgetService.checkWidgetConfig off row $p7, on row $p12 (want <= 10 -> 12)"; fi
if isptr WidgetParser.parseWidgetConfig "$TMP/ts.on" && [ "$( pos parseWidgetConfig "$TMP/ts.on" )" -gt 0 ]; then ok "(t2) the twinned WidgetParser.parseWidgetConfig is a tail pointer; its body row parseWidgetConfig is printed"
else no "(t2) WidgetParser.parseWidgetConfig pointer=$( python3 "$TMP/pos.py" ptr "$TMP/ts.on" WidgetParser.parseWidgetConfig ) body row=$( pos parseWidgetConfig "$TMP/ts.on" )"; fi
stays n2 WidgetConfigUser.useWidgetConfig "$TMP/ts.off" "$TMP/ts.on" ts "it has in=1 (a caller reuses it)"
grep -q 'n="WidgetConfigUser.useWidgetConfig"[^>]* in="1"' "$TMP/ts.off" || no "(n2) the fixture's WidgetConfigUser.useWidgetConfig row lost in=1"

# (n5) task-named: the qualified name keeps the row; a bare name of another owner's member keeps only its own owner's row
NTASK='how is WidgetService.readWidgetConfig used when the widget config value is checked'
run ts "--for=$NTASK" >"$TMP/n5.on"; runoff ts "--for=$NTASK" >"$TMP/n5.off"
python3 "$TMP/ref.py" "$TMP/n5.off" "$TMP/n5.on" "$NTASK" >"$TMP/n5.res" 2>&1
grep -q '^PASS (a)' "$TMP/n5.res" && ok "(a) n5: $( grep -o '[0-9]* sunk [0-9]* pointers' "$TMP/n5.res" )" || no "(a) n5: $( head -c 500 "$TMP/n5.res" )"
stays n5 WidgetService.readWidgetConfig "$TMP/n5.off" "$TMP/n5.on" n5 "the task names WidgetService.readWidgetConfig"
OTASK='how is Checker.readWidgetConfig used when the widget config value is checked'
run ts "--for=$OTASK" >"$TMP/o5.on"; runoff ts "--for=$OTASK" >"$TMP/o5.off"
python3 "$TMP/ref.py" "$TMP/o5.off" "$TMP/o5.on" "$OTASK" >"$TMP/o5.res" 2>&1
if grep -q '^PASS (a)' "$TMP/o5.res" && grep -q '^sunk .*WidgetService.readWidgetConfig' "$TMP/o5.res" && grep -q '<shortkey [^>]*of="Checker.readWidgetConfig"' "$TMP/o5.on" \
   && ! isptr WidgetService.readWidgetConfig "$TMP/o5.on"; then
    ok "(n5) a task naming Checker.readWidgetConfig (another owner) does not keep WidgetService.readWidgetConfig: it sinks (and the <shortkey> rung's <d n= l=/> is no bodied twin)"
else no "(n5) other-owner task: $( head -c 500 "$TMP/o5.res" )"; fi

# (n4) NOTED: a --note-add note on readWidgetConfig keeps it in place
cp -R "$TMP/ts" "$TMP/ts4"
( cd "$TMP/ts4" && git init -q -b main . && git add -A && git -c user.email=gate@example.invalid -c user.name=gate commit -qm fx ) || no "(n4) could not make the fixture copy a git repo"
"$BIN" "$TMP/ts4" --note-add="WidgetService.readWidgetConfig: the path is already validated by the loader" >/dev/null 2>&1
run ts4 "--for=$TTASK" >"$TMP/n4.on"; runoff ts4 "--for=$TTASK" >"$TMP/n4.off"
grep -q 'already validated by the loader' "$TMP/n4.off" || no "(n4) the off answer carries no note on readWidgetConfig — the arm cannot see K6"
python3 "$TMP/ref.py" "$TMP/n4.off" "$TMP/n4.on" "$TTASK" >"$TMP/n4.res" 2>&1
grep -q '^PASS (a)' "$TMP/n4.res" && grep -q 'already validated by the loader' "$TMP/n4.on" && ok "(a) n4: the note is printed ($( grep -o '[0-9]* sunk [0-9]* pointers' "$TMP/n4.res" ))" || no "(a) n4: $( head -c 500 "$TMP/n4.res" )"
stays n4 WidgetService.readWidgetConfig "$TMP/n4.off" "$TMP/n4.on" n4 "it carries a --note-add note"

# ---- cpp tree
run cpp "--for=$CTASK" >"$TMP/cpp.on"; rc1=$?
runoff cpp "--for=$CTASK" >"$TMP/cpp.off"; rc2=$?
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] || no "cpp runs exited $rc1 / $rc2"
check_a cpp "$TMP/cpp.off" "$TMP/cpp.on" "$CTASK"
pt="$( pos WidgetConfigHdr::parse_widget_config "$TMP/cpp.off" )"
if isptr WidgetConfigHdr::parse_widget_config "$TMP/cpp.on" && [ "$pt" -le 10 ] && grep -q 'n="WidgetConfigHdr::parse_widget_config" p="src/cfg.cc"' "$TMP/cpp.on"; then
    ok "(t) the twinned prototype WidgetConfigHdr::parse_widget_config (off row $pt) is a tail pointer in its place; its cfg.cc body row stays"
else no "(t) WidgetConfigHdr::parse_widget_config off row $pt, pointer=$( python3 "$TMP/pos.py" ptr "$TMP/cpp.on" WidgetConfigHdr::parse_widget_config )"; fi
stays n1 WidgetConfigLimits::widget_config_max "$TMP/cpp.off" "$TMP/cpp.on" cpp "a static const member"
stays n3 WidgetConfigHdr::stop_widget_config "$TMP/cpp.off" "$TMP/cpp.on" cpp "it carries slot_by="
grep -q 'n="WidgetConfigHdr::stop_widget_config"[^>]* slot_by=' "$TMP/cpp.off" || no "(n3) the fixture's stop_widget_config row lost slot_by="

# (n6) mem= rows: never owner-qualified, and none moves
nm="$( python3 - "$TMP/ts.off" "$TMP/ts.on" "$TMP/cpp.off" "$TMP/cpp.on" <<'PY'
import re, sys
bad, seen = [], 0
for off, on in ( ( sys.argv[1], sys.argv[2] ), ( sys.argv[3], sys.argv[4] ) ):
    for f in ( off, on ):
        for m in re.finditer( r'<d ([^>]*\bmem="[^"]*"[^>]*)>', open( f ).read() ):
            n = re.search( r'\bn="([^"]*)"', m.group( 1 ) ).group( 1 ); seen += 1
            if "." in n or "::" in n: bad.append( n )
    rowsof = lambda f: re.findall( r'<d [^>]*?\bn="([^"]*)"[^>]*\bmem=', open( f ).read() )
    if rowsof( off ) != rowsof( on ): bad.append( "moved" )
print( "%d %s" % ( seen, ",".join( bad ) ) )
PY
)"
case "$nm" in *" ") ok "(n6) mem= rows: ${nm% } seen, none owner-qualified, none moved (K1 kept for one guard set)";; *) no "(n6) mem= rows: $nm";; esac

# (b) --token-budget holds both rules; (b2) a bare --max-tokens does not; (j) --json never reaches them
run ts "--for=$TTASK" --token-budget=4000 >"$TMP/b.on"; runoff ts "--for=$TTASK" --token-budget=4000 >"$TMP/b.off"
if cmp -s "$TMP/b.on" "$TMP/b.off" && ! grep -q '<!-- decl-' "$TMP/b.on"; then ok "(b) --token-budget: byte-identical to the off twin, no decl legend"; else no "(b) --token-budget changed the answer"; fi
run ts "--for=$TTASK" --max-tokens=4000 >"$TMP/m.on" 2>/dev/null
if cmp -s "$TMP/m.on" "$TMP/ts.on"; then ok "(b2) a bare --max-tokens leaves the answer byte-identical to the flagless one"; else no "(b2) --max-tokens=4000 changed the answer"; fi
run ts "--for=$TTASK" --json >"$TMP/j.on"; runoff ts "--for=$TTASK" --json >"$TMP/j.off"
if cmp -s "$TMP/j.on" "$TMP/j.off"; then ok "(j) --json: byte-identical to the off twin"; else no "(j) --json changed"; fi

eon="$( grep -o '^<ctx [^>]*' "$TMP/ts.on" | grep -o ' est_tokens="[0-9]*"' | grep -o '[0-9]*' )"
eoff="$( grep -o '^<ctx [^>]*' "$TMP/ts.off" | grep -o ' est_tokens="[0-9]*"' | grep -o '[0-9]*' )"
if [ -n "$eon" ] && [ -n "$eoff" ] && [ "$eon" != "$eoff" ]; then ok "(e) est_tokens re-priced on the final bytes: $eoff -> $eon"; else no "(e) est_tokens off=$eoff on=$eon"; fi
if command -v xmllint >/dev/null 2>&1; then
    for f in ts.on cpp.on n4.on; do xmllint --noout "$TMP/$f" 2>"$TMP/w.err" || no "(w) $f: $( head -c 300 "$TMP/w.err" )"; done
    ok "(w) well formed (ts, cpp, noted)"
fi
leg="$( python3 - "$TMP/ts.on" "$TMP/ts.off" <<'PY'
import sys
on, off = open( sys.argv[1] ).read(), open( sys.argv[2] ).read()
out = []
for k in ( "<!-- decl-sink:", "<!-- decl-twin:" ):
    a = on.find( k ) + 4; c = on[a:on.find( "-->", a )]
    out.append( "%s=%d/%d%s" % ( k[5:-1], on.count( k ), off.count( k ), "" if "--" not in c else " has--" ) )
print( " ".join( out ) )
PY
)"
case "$leg" in "decl-sink=1/0 decl-twin=1/0") ok "(l) each legend comment once when its rule fires, none on the off twin, no double hyphen inside";; *) no "(l) legend counts on/off: $leg";; esac

# (o) each rule's own switch
( cd "$TMP/ts" && RIPWIRE_NO_DECL_SINK=1 "$BIN" . --no-cache "--for=$TTASK" ) >"$TMP/o.twin"
( cd "$TMP/ts" && RIPWIRE_NO_DECL_TWIN=1 "$BIN" . --no-cache "--for=$TTASK" ) >"$TMP/o.sink"
python3 "$TMP/ref.py" "$TMP/ts.off" "$TMP/o.twin" "$TTASK" twin >"$TMP/ot.res" 2>&1
python3 "$TMP/ref.py" "$TMP/ts.off" "$TMP/o.sink" "$TTASK" sink >"$TMP/os.res" 2>&1
if grep -q '^PASS' "$TMP/ot.res" && grep -q '^PASS' "$TMP/os.res" && ! grep -q '<!-- decl-sink' "$TMP/o.twin" && ! grep -q '<!-- decl-twin' "$TMP/o.sink"; then
    ok "(o) RIPWIRE_NO_DECL_SINK=1 leaves the twin rule alone ($( grep -o '[0-9]* pointers' "$TMP/ot.res" )), RIPWIRE_NO_DECL_TWIN=1 the sink alone ($( grep -o '[0-9]* sunk' "$TMP/os.res" ))"
else no "(o) $( head -c 300 "$TMP/ot.res" ) / $( head -c 300 "$TMP/os.res" )"; fi

# (sd) with SIBLING-DEMOTE on (the shipped default) the rules read its result: (a) on the demoted answer
( cd "$TMP/ts" && env -u RIPWIRE_NO_SIBLING_DEMOTE "$BIN" . --no-cache "--for=$TTASK" ) >"$TMP/sd.on"
( cd "$TMP/ts" && env -u RIPWIRE_NO_SIBLING_DEMOTE "${OFFENV[@]}" "$BIN" . --no-cache "--for=$TTASK" ) >"$TMP/sd.off"
check_a sd "$TMP/sd.off" "$TMP/sd.on" "$TTASK"

mcp(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$TMP/ts" "$TTASK" \
  | ( cd "$TMP/ts" || exit 1; "$@" "$BIN" --mcp 2>/dev/null ) | python3 -c '
import json, sys
for line in sys.stdin:
    d = json.loads( line )
    if d.get( "id" ) == 1:
        print( d["result"]["content"][0]["text"], end="" )
'; }
mcp env >"$TMP/x.on"
mcp "${OFFENV[@]}" >"$TMP/x.off"
check_a x "$TMP/x.off" "$TMP/x.on" "$TTASK"
[ "$fail" = 0 ] && echo "fordeclsinkcheck: PASS" || echo "fordeclsinkcheck: FAIL"
exit "$fail"
