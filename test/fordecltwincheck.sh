#!/usr/bin/env bash
# fordecltwincheck.sh — DECL-TWIN (src/fordecltwin.h, precision card B14): a ONE-LINE OWNER-QUALIFIED DECLARATION row of <sigs>
# (l= equals e=, n= Owner.member / Owner::member) is a signature, not the definition. Such a row whose last segment names a BODIED
# <sigs> <d> row of the answer (l= and e= present, unequal) is printed as a tail pointer <t p= sym= r=/> in its place, at any rank.
# Keep guards (SIBLING-DEMOTE's): K1/K7 mem= / slot_by= / slot_fields=, K6 a <note>, K4 the task names the row (a qualified task word
# names the full name, a bare one the last segment).
#
# TWO trees. ts/: an interface WidgetService (readWidgetConfig, checkWidgetConfig: no bodied twin), an interface WidgetParser whose
# parseWidgetConfig has a bodied twin in impl.ts, a bodied check function at row 1 and 14 helpers (ten in a file each). cpp/: an
# in-class prototype WidgetConfigHdr::parse_widget_config with an out-of-line body, a prototype a member-pointer table calls
# (WidgetConfigHdr::stop_widget_config: slot_by=) whose last segment also names a bodied free function stop_widget_config.
# ARMS (RED on a binary without the rule: (t), (t2), (a) with pointers, (l), (x), (n5o); the negatives hold on both)
#   (a)  each answer equals its RIPWIRE_NO_DECL_TWIN=1 twin with exactly the rows the rule picks (recomputed here from the off answer)
#        rewritten as pointers, the legend comment before the first, est_tokens= aside
#   (t)  a twinned declaration goes to the tail: cpp WidgetConfigHdr::parse_widget_config (a first-10 row, its cfg.cc body row in the
#        answer) is a pointer in its place;  (t2) ts WidgetParser.parseWidgetConfig (its body parseWidgetConfig printed) too
#   NEGATIVES, each a one-line owner-qualified row of the off answer whose last segment names a bodied row of it, that stays a row in
#        its place among the unmoved rows (except (n5r), which has no bodied twin):
#   (n3) a slot row: WidgetConfigHdr::stop_widget_config (slot_by=)          (n4) a noted row: a --note-add note on WidgetParser.parseWidgetConfig
#   (n5) a task-named row: a task naming WidgetParser.parseWidgetConfig keeps it; (n5o) a task naming another owner's member
#        (Other.parseWidgetConfig) does not keep it; (n5r) a <shortkey> rung's <d n= l=/> (task Checker.readWidgetConfig) is no bodied twin
#   (n6) a mem= row: every extractor names a type row bare (C++, C#, Java, Kotlin, Swift, Scala, TypeScript, Python, Ruby probed), and
#        mem= rides only on class/struct/interface rows, so a mem= row is never owner-qualified and DECL-TWIN never reads one (K1 is
#        kept for one guard set, unreachable here). The arm proves that premise on rows it sees: the ts tree carries mem= rows
#        (WidgetConfigKeeper, and WidgetConfigHolder inside `namespace WidgetConfigNs`), every mem= row of both trees is bare and stays
#        a row in place, and the C++ out-of-line nested type `struct WidgetConfigNest::WidgetConfigDeep` is a bare WidgetConfigDeep row
#        (the shapes most likely to give a qualified type name). It FAILS when it sees no mem= row (CodeRabbit #607: it once passed on 0)
#   (b)  --token-budget runs the rule too (DEMOTE-ALL-DIALECTS, fordemoteall.h): (a) on the budgeted answer and its off twin
#   (b2) a bare --max-tokens (not read by --for) does not hold the rule: byte-identical to the flagless answer
#   (j)  --json: the twinned row is a {"pointer":"decl-twin",...} object in its place, every other row as the off twin's
#   (e)  est_tokens= is re-priced on the final bytes (estchargecheck holds the rate); (w) well formed; (l) the legend once, no "--" inside
#   (sd) with SIBLING-DEMOTE on, (a) on its result;  (x) MCP `for` (one renderer): (a) on the MCP answer and its off twin
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "fordecltwincheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export RIPWIRE_NO_SIBLING_DEMOTE=1   # the decl rule alone (forsiblingdemotecheck owns the demote; (sd) below runs both)
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
export namespace WidgetConfigNs {
  export class WidgetConfigHolder {
    alphaSlot(x: number): number { return x; }
    betaSlot(y: number): number { return y; }
  }
}
export class WidgetConfigKeeper {
  keepAlpha(x: number): number { return x; }
  keepBeta(y: number): number { return y; }
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
struct WidgetConfigNest { struct WidgetConfigDeep; };
struct WidgetConfigNest::WidgetConfigDeep { int deep_alpha(int x); int deep_beta(int y); };
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
static int stop_widget_config(int k) {
  int z = k - 1;
  return z;
}
int halt_widget_config(int k) { return stop_widget_config(k); }
''' )
PY

cat >"$TMP/ref.py" <<'PY'
"""ref.py OFF ON TASK -> DECL-TWIN recomputed on OFF (independent of the C++): `ptr` names and PASS/FAIL (a)."""
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
exp, P = twin( off, task )
est = lambda s: re.sub( r' est_tokens="\d+"', "", s, count = 1 )
print( "ptr " + ",".join( P ) )
print( ( "PASS" if est( exp ) == est( on ) else "FAIL" ) + " (a) %d pointers" % len( P ) )
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
OFFENV=( env RIPWIRE_NO_DECL_TWIN=1 )
run(){ local tree="$1"; shift; ( cd "$TMP/$tree" && "$BIN" . --no-cache "$@" ); }
runoff(){ local tree="$1"; shift; ( cd "$TMP/$tree" && "${OFFENV[@]}" "$BIN" . --no-cache "$@" ); }
check_a(){ # check_a ID OFF ON TASK
    python3 "$TMP/ref.py" "$2" "$3" "$4" >"$TMP/$1.res" 2>&1
    if grep -q '^PASS (a)' "$TMP/$1.res" && ! grep -q '^PASS (a) 0 pointers' "$TMP/$1.res"; then ok "(a) $1: the off answer with exactly the rule's rows rewritten ($( grep -o '[0-9]* pointers' "$TMP/$1.res" ))"
    else no "(a) $1: $( head -c 700 "$TMP/$1.res" )"; fi
}
# stays ID NAME OFF ON RES WHAT: a row of the off answer that keeps its place among the unmoved rows
stays(){
    local id="$1" n="$2" po pn moved
    po="$( pos "$n" "$3" )"; pn="$( pos "$n" "$4" )"
    moved="$( python3 - "$3" "$TMP/$5.res" "$n" <<'PY'
import re, sys
t = re.sub( r"<!--.*?-->|<!\[CDATA\[.*?\]\]>", "", open( sys.argv[1] ).read(), flags = re.S )
res = open( sys.argv[2] ).read().split( "\n" )
ptrs = [ x for x in res[0][4:].split( "," ) if x ]   # pointers leave the rows above it
names = []
for m in re.finditer( r'<(d|y|s|u) ([^>]*?)/?>', t ):
    if m.group( 1 ) == "u" and 'v="used"' in m.group( 2 ): continue
    names.append( ( re.search( r'\bn="([^"]*)"', m.group( 2 ) ) or re.search( r'p="([^"]*)"', m.group( 2 ) ) ).group( 1 ) if m.group( 1 ) == "d" else "" )
k = names.index( sys.argv[3] ) if sys.argv[3] in names else -1
print( sum( 1 for x in names[:k] if x in ptrs ) )
PY
)"
    if [ "$po" -ge 1 ] && [ "$pn" = "$(( po - moved ))" ] && ! isptr "$n" "$4"; then ok "($id) $n stays a row in place: $6 (off row $po, on row $pn, $moved pointers above it)"
    else no "($id) $n: $6 — off row $po, on row $pn ($moved pointers above it)"; fi
}

# ---- ts tree
run ts "--for=$TTASK" >"$TMP/ts.on"; rc1=$?
runoff ts "--for=$TTASK" >"$TMP/ts.off"; rc2=$?
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] || no "ts runs exited $rc1 / $rc2"
check_a ts "$TMP/ts.off" "$TMP/ts.on" "$TTASK"
if isptr WidgetParser.parseWidgetConfig "$TMP/ts.on" && [ "$( pos parseWidgetConfig "$TMP/ts.on" )" -gt 0 ]; then ok "(t2) the twinned WidgetParser.parseWidgetConfig is a tail pointer; its body row parseWidgetConfig is printed"
else no "(t2) WidgetParser.parseWidgetConfig pointer=$( python3 "$TMP/pos.py" ptr "$TMP/ts.on" WidgetParser.parseWidgetConfig ) body row=$( pos parseWidgetConfig "$TMP/ts.on" )"; fi

# (n5) task-named: the qualified name keeps the twinned row; another owner's member does not; a <shortkey> rung is no bodied twin
NTASK='how is WidgetParser.parseWidgetConfig used when the widget config value is checked'
run ts "--for=$NTASK" >"$TMP/n5.on"; runoff ts "--for=$NTASK" >"$TMP/n5.off"
python3 "$TMP/ref.py" "$TMP/n5.off" "$TMP/n5.on" "$NTASK" >"$TMP/n5.res" 2>&1
if grep -q '^PASS (a)' "$TMP/n5.res"; then ok "(a) n5: $( grep -o '[0-9]* pointers' "$TMP/n5.res" )"; else no "(a) n5: $( head -c 500 "$TMP/n5.res" )"; fi
[ "$( pos parseWidgetConfig "$TMP/n5.off" )" -gt 0 ] || no "(n5) the fixture's body row parseWidgetConfig is not in the n5 answer — the arm cannot see K4"
stays n5 WidgetParser.parseWidgetConfig "$TMP/n5.off" "$TMP/n5.on" n5 "the task names WidgetParser.parseWidgetConfig"
OTASK='how is Other.parseWidgetConfig used when the widget config value is checked'
run ts "--for=$OTASK" >"$TMP/o5.on"; runoff ts "--for=$OTASK" >"$TMP/o5.off"
python3 "$TMP/ref.py" "$TMP/o5.off" "$TMP/o5.on" "$OTASK" >"$TMP/o5.res" 2>&1
if grep -q '^PASS (a)' "$TMP/o5.res" && isptr WidgetParser.parseWidgetConfig "$TMP/o5.on"; then
    ok "(n5o) a task naming Other.parseWidgetConfig (another owner) does not keep WidgetParser.parseWidgetConfig: it is a pointer"
else no "(n5o) other-owner task: $( head -c 500 "$TMP/o5.res" )"; fi
RTASK='how is Checker.readWidgetConfig used when the widget config value is checked'
run ts "--for=$RTASK" >"$TMP/r5.on"; runoff ts "--for=$RTASK" >"$TMP/r5.off"
python3 "$TMP/ref.py" "$TMP/r5.off" "$TMP/r5.on" "$RTASK" >"$TMP/r5.res" 2>&1
if grep -q '^PASS (a)' "$TMP/r5.res" && grep -q '<shortkey [^>]*of="Checker.readWidgetConfig"' "$TMP/r5.on" && [ "$( pos WidgetService.readWidgetConfig "$TMP/r5.on" )" -gt 0 ] \
   && ! isptr WidgetService.readWidgetConfig "$TMP/r5.on"; then
    ok "(n5r) the <shortkey> rung's <d n=\"readWidgetConfig\" l=/> is no bodied twin: WidgetService.readWidgetConfig stays a row"
else no "(n5r) shortkey task: $( head -c 500 "$TMP/r5.res" )"; fi

# (n4) NOTED: a --note-add note on the twinned WidgetParser.parseWidgetConfig keeps it in place
cp -R "$TMP/ts" "$TMP/ts4"
( cd "$TMP/ts4" && git init -q -b main . && git add -A && git -c user.email=gate@example.invalid -c user.name=gate commit -qm fx ) || no "(n4) could not make the fixture copy a git repo"
"$BIN" "$TMP/ts4" --note-add="WidgetParser.parseWidgetConfig: the text is already validated by the loader" >/dev/null 2>&1
run ts4 "--for=$TTASK" >"$TMP/n4.on"; runoff ts4 "--for=$TTASK" >"$TMP/n4.off"
grep -q 'already validated by the loader' "$TMP/n4.off" || no "(n4) the off answer carries no note on WidgetParser.parseWidgetConfig — the arm cannot see K6"
python3 "$TMP/ref.py" "$TMP/n4.off" "$TMP/n4.on" "$TTASK" >"$TMP/n4.res" 2>&1
if grep -q '^PASS (a)' "$TMP/n4.res" && grep -q 'already validated by the loader' "$TMP/n4.on"; then ok "(a) n4: the note is printed ($( grep -o '[0-9]* pointers' "$TMP/n4.res" ))"
else no "(a) n4: $( head -c 500 "$TMP/n4.res" )"; fi
stays n4 WidgetParser.parseWidgetConfig "$TMP/n4.off" "$TMP/n4.on" n4 "it carries a --note-add note"

# ---- cpp tree
run cpp "--for=$CTASK" >"$TMP/cpp.on"; rc1=$?
runoff cpp "--for=$CTASK" >"$TMP/cpp.off"; rc2=$?
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] || no "cpp runs exited $rc1 / $rc2"
check_a cpp "$TMP/cpp.off" "$TMP/cpp.on" "$CTASK"
pt="$( pos WidgetConfigHdr::parse_widget_config "$TMP/cpp.off" )"
if isptr WidgetConfigHdr::parse_widget_config "$TMP/cpp.on" && [ "$pt" -le 10 ] && grep -q 'n="WidgetConfigHdr::parse_widget_config" p="src/cfg.cc"' "$TMP/cpp.on"; then
    ok "(t) the twinned prototype WidgetConfigHdr::parse_widget_config (off row $pt) is a tail pointer in its place; its cfg.cc body row stays"
else no "(t) WidgetConfigHdr::parse_widget_config off row $pt, pointer=$( python3 "$TMP/pos.py" ptr "$TMP/cpp.on" WidgetConfigHdr::parse_widget_config )"; fi
stays n3 WidgetConfigHdr::stop_widget_config "$TMP/cpp.off" "$TMP/cpp.on" cpp "it carries slot_by="
grep -q 'n="WidgetConfigHdr::stop_widget_config"[^>]* slot_by=' "$TMP/cpp.off" || no "(n3) the fixture's stop_widget_config row lost slot_by="
grep -q '<d l="[0-9]*" e="[0-9]*" n="stop_widget_config"' "$TMP/cpp.off" || no "(n3) the bodied stop_widget_config row is not in the answer — the arm cannot see K7"

# (n6) mem= rows: seen (the premise), never owner-qualified, none moves; qualified type spellings print bare
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
case "$nm" in   # the arm checks its own premise: no mem= row in either tree means it saw nothing (CodeRabbit #607)
    "0 "*) no "(n6) no mem= row in either tree — the arm cannot see K1";;
    *" ") ok "(n6) mem= rows: ${nm% } seen across the off/on answers, none owner-qualified, none moved";;
    *) no "(n6) mem= rows: $nm";;
esac
for t in WidgetConfigHolder WidgetConfigKeeper; do
    grep -q "<d [^>]*n=\"$t\"[^>]* mem=\"" "$TMP/ts.off" || no "(n6) the fixture's $t row carries no mem= — the arm cannot see K1 there"
    stays n6 "$t" "$TMP/ts.off" "$TMP/ts.on" ts "it carries mem= (named bare: $t)"
done
if grep -q '<d [^>]*n="WidgetConfigDeep" sc="WidgetConfigNest"' "$TMP/cpp.off" && ! grep -q 'n="WidgetConfigNest::WidgetConfigDeep"' "$TMP/cpp.off"; then
    ok "(n6) the out-of-line nested type struct WidgetConfigNest::WidgetConfigDeep prints as a bare WidgetConfigDeep row (sc= names the owner)"
else no "(n6) WidgetConfigNest::WidgetConfigDeep: $( grep -o '<d [^>]*WidgetConfigDeep"[^>]*>' "$TMP/cpp.off" | head -2 )"; fi

# (b) --token-budget runs the rule; (b2) a bare --max-tokens does not hold it; (j) --json carries the pointer object
run ts "--for=$TTASK" --token-budget=4000 >"$TMP/b.on"; runoff ts "--for=$TTASK" --token-budget=4000 >"$TMP/b.off"
python3 "$TMP/ref.py" "$TMP/b.off" "$TMP/b.on" "$TTASK" >"$TMP/b.res" 2>&1
if grep -q '^PASS (a)' "$TMP/b.res" && ! grep -q '^PASS (a) 0 pointers' "$TMP/b.res"; then ok "(b) --token-budget (DEMOTE-ALL-DIALECTS): (a) on the budgeted answer and its off twin ($( grep -o '[0-9]* pointers' "$TMP/b.res" ); no row cut, so no refill)"
else no "(b) --token-budget: $( head -c 500 "$TMP/b.res" )"; fi
run ts "--for=$TTASK" --max-tokens=4000 >"$TMP/m.on" 2>/dev/null
if cmp -s "$TMP/m.on" "$TMP/ts.on"; then ok "(b2) a bare --max-tokens leaves the answer byte-identical to the flagless one"; else no "(b2) --max-tokens=4000 changed the answer"; fi
run ts "--for=$TTASK" --json >"$TMP/j.on"; runoff ts "--for=$TTASK" --json >"$TMP/j.off"
jres="$( python3 - "$TMP/j.on" "$TMP/j.off" <<'PY'
import json, sys
on, off = json.load( open( sys.argv[1] ) )["sigs"], json.load( open( sys.argv[2] ) )["sigs"]
ptr = [ o for o in on if "pointer" in o ]
rest = [ o for o in on if "pointer" not in o ] == [ o for o in off if o["r"] not in { p["r"] for p in ptr } ]
print( "ok" if rest and [ ( p["pointer"], p["sym"] ) for p in ptr ] == [ ( "decl-twin", "WidgetParser.parseWidgetConfig" ) ] else "%s rest=%s" % ( ptr, rest ) )
PY
)"
if [ "$jres" = ok ]; then ok "(j) --json (DEMOTE-ALL-DIALECTS): WidgetParser.parseWidgetConfig is a decl-twin pointer object, every other row as the off twin"; else no "(j) --json: $jres"; fi

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
for k in ( "<!-- decl-twin:", ):
    a = on.find( k ) + 4; c = on[a:on.find( "-->", a )]
    out.append( "%s=%d/%d%s" % ( k[5:-1], on.count( k ), off.count( k ), "" if "--" not in c else " has--" ) )
print( " ".join( out ) )
PY
)"
case "$leg" in "decl-twin=1/0") ok "(l) the legend comment once when the rule fires, none on the off twin, no double hyphen inside";; *) no "(l) legend counts on/off: $leg";; esac

# (sd) with SIBLING-DEMOTE on (the shipped default) the rule reads its result: (a) on the demoted answer
# (the cpp tree: on the ts tree SIBLING-DEMOTE already prints WidgetParser.parseWidgetConfig and its body past row 10 as pointers)
( cd "$TMP/cpp" && env -u RIPWIRE_NO_SIBLING_DEMOTE "$BIN" . --no-cache "--for=$CTASK" ) >"$TMP/sd.on"
( cd "$TMP/cpp" && env -u RIPWIRE_NO_SIBLING_DEMOTE "${OFFENV[@]}" "$BIN" . --no-cache "--for=$CTASK" ) >"$TMP/sd.off"
check_a sd "$TMP/sd.off" "$TMP/sd.on" "$CTASK"

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
[ "$fail" = 0 ] && echo "fordecltwincheck: PASS" || echo "fordecltwincheck: FAIL"
exit "$fail"
