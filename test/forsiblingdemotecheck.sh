#!/usr/bin/env bash
# forsiblingdemotecheck.sh — SIBLING-DEMOTE (src/forsiblingdemote.h): a ranked <sigs> <d> row with <d> rank > 5, answer-row position > 10
# (the <d>, <y>, <s> and non-`used` <u> rows in output order) and a higher <d> row of the same file is printed in its place as a tail
# pointer <t p="FILE" sym="NAME"/>, unless a keep guard holds (K1 mem=, K2 a <c> callee of a <h> hop row, K3 Owner.member under its
# Owner row, K4 a proven call path of <= 2 edges to one of the first three resolved answer rows, K5 a kept row's same_as= names it).
#
# ONE Python tree (the rule reads answer bytes; K4 reads the index graph): widget.py holds the head parse_widget_config and 14 plain
# same-file siblings (widget_config_variant_NN), a name-only member callee of the head (WidgetConfigSink.widget_config_flush), a 2-hop proven
# caller (widget_config_far_caller -> widget_config_bridge -> head) and a 3-hop one (widget_config_farther_caller), a type whose members
# are not shown (WidgetVault: mem=), a class row with its members right below (WidgetShelf), and a top-level twin of a member's text
# (widget_shelf_row; the member row says same_as= it). other.py: five more helpers (its first row high, the rest deep).
# ARMS
#   (a)  the demoted answer equals the RIPWIRE_NO_SIBLING_DEMOTE=1 answer with exactly the rows the rule picks (recomputed here from the
#        off answer; K4's proven-path rows named) rewritten as <t p= sym= r=/> and the legend comment before the first, est_tokens= aside
#   (a2) a plain deep sibling is a pointer: widget_config_variant_04 (pos 11) and other.py's deep rows
#   (p)  position: the rows at answer positions <= 10 stay rows (widget_config_variant_03 at pos 10, rank 10)
#   (r)  rank: an unused-in-file table puts 28 <u> rows first; the <d> rows of rank <= 5 (all past position 10) stay rows, rank 6+ go
#   (k1) WidgetVault (mem=) stays a row          (k2) WidgetConfigSink.widget_config_flush (a <c> under the head's <h>) stays a row
#   (k3) WidgetShelf.widget_shelf_row (WidgetShelf right above) stays a row
#   (k4) widget_config_far_caller (proven 2-hop caller of the head) stays a row; twin: widget_config_farther_caller (3 hops) is a pointer
#   (k5) widget_shelf_row stays a row: the kept WidgetShelf.widget_shelf_row says same_as="widget_shelf_row"
#   (e)  est_tokens= is re-priced down (estchargecheck holds its value to the bytes); (w) well formed; (l) one legend comment, no "--" in it
#   (b)  --token-budget leaves the answer as shaped: no pointer in <sigs>, no legend comment
#   (x)  MCP `for` (one renderer): (a) on the MCP answer and its RIPWIRE_NO_SIBLING_DEMOTE=1 twin (its <h> rows differ from the CLI's,
#        so its K2 reads differ: the rule is checked on its own bytes)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forsiblingdemotecheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
TASK='how does parse widget config work'
UTASK='which widget config functions in widget.py are unused'

python3 - "$TMP/py" <<'PY' || { echo "fixture generator failed"; exit 2; }
import os, sys
d = sys.argv[1]; os.makedirs( d, exist_ok = True )
s = '''def parse_widget_config(path, sink):
    """Parse the widget config file."""
    data = widget_config_reader(path)
    sink.widget_config_flush(data)
    return widget_config_check(data)


def widget_config_reader(path):
    """Read the widget config bytes."""
    return path


def widget_config_check(data):
    """Check the widget config."""
    return data


def widget_config_bridge(path):
    """Bridge into the widget config parser."""
    return parse_widget_config(path, None)


def widget_config_far_caller(path):
    """Calls the widget config parser through the bridge."""
    return widget_config_bridge(path)


def widget_config_farther_caller(path):
    """Calls the widget config parser three calls away."""
    return widget_config_far_caller(path)

'''
for i in range( 1, 15 ):
    s += f'''
def widget_config_variant_{i:02d}(x):
    """Widget config variant {i}."""
    return x
'''
s += '''

class WidgetVault:
    """A widget vault."""
    def alpha(self):
        return 1

    def beta(self):
        return 2


def widget_shelf_row(self, first_index=0, last_index=10, include_hidden=False):
    """Widget shelf row: the first row of the shelf, kept for the display table and its tests."""
    return 1


class WidgetShelf:
    """A widget shelf."""
    def widget_shelf_row(self, first_index=0, last_index=10, include_hidden=False):
        """Widget shelf row: the first row of the shelf, kept for the display table and its tests."""
        return 1

    def widget_shelf_col(self):
        """Widget shelf col."""
        return 2


class WidgetConfigSink:
    def widget_config_flush(self, data):
        """Flush the widget config."""
        return data
'''
open( os.path.join( d, "widget.py" ), "w" ).write( s )
open( os.path.join( d, "other.py" ), "w" ).write( "".join( f'''
def widget_config_other_{i:02d}(x):
    """Other widget config helper {i}."""
    return x
''' for i in range( 1, 6 ) ) )
open( os.path.join( d, "lone.py" ), "w" ).write( '\ndef widget_lone(x):\n    """Lone."""\n    return x\n' )
PY

cat >"$TMP/check.py" <<'PY'
"""check.py OFF ON KEEP4 -> the rule recomputed on OFF; prints `rows` (the picked names) and PASS/FAIL (a) for ON."""
import re, sys
ATTR = re.compile( r'([\w:-]+)="([^"]*)"' )
def unesc( v ): return v.replace( "&lt;", "<" ).replace( "&gt;", ">" ).replace( "&quot;", '"' ).replace( "&apos;", "'" ).replace( "&amp;", "&" )
def mask( t ): return re.sub( r"<!--.*?-->|<!\[CDATA\[.*?\]\]>", lambda m: " " * len( m.group( 0 ) ), t, flags = re.S )
def rows( t ):
    m = mask( t ); out = []; dp = 0
    sigs = [ ( x.start(), m.find( "</sigs>", x.start() ) ) for x in re.finditer( r"<sigs[ >]", m ) ]
    for x in re.finditer( r'<(d|y|s|u) ([^>]*?)(/?)>', m ):
        a = { k: unesc( v ) for k, v in ATTR.findall( x.group( 2 ) ) }
        if x.group( 1 ) == "u" and a.get( "v" ) == "used": continue
        e = x.end()
        if x.group( 1 ) == "d":
            dp += 1
            if not x.group( 3 ): e = m.find( "</d>", e ) + 4
        out.append( dict( tag = x.group( 1 ), a = a, raw = dict( ATTR.findall( x.group( 2 ) ) ), s = x.start(), e = e, pos = len( out ) + 1,
                          dpos = dp if x.group( 1 ) == "d" else 0, sigs = any( a0 < x.start() < b0 for a0, b0 in sigs ) ) )
    return out
def calls( t ):
    out = set()
    for h in re.finditer( r'<h\s[^>]*>(.*?)</h>', mask( t ), re.S ):
        out |= { unesc( c ) for c in re.findall( r'<c\s[^>]*?\bn="([^"]*)"', h.group( 1 ) ) }
    return out
def last( n ): return re.split( r"::|\.|#", n )[-1]
def rule( t, keep4 ):
    R = rows( t ); C = calls( t ); D = [ r for r in R if r["tag"] == "d" ]; pick = []
    for r in D:
        n = r["a"].get( "n", "" ); f = r["a"].get( "p", "" ).split( ":" )[0]
        if not r["sigs"] or r["dpos"] <= 5 or r["pos"] <= 10 or "mem" in r["a"]: continue
        if not any( x["a"].get( "p", "" ).split( ":" )[0] == f for x in D[: r["dpos"] - 1] ): continue
        if n in C or last( n ) in C: continue
        if ( "." in n or "::" in n ) and any( x["a"].get( "n" ) == re.split( r"\.|::", n )[0] for x in D[max( 0, r["dpos"] - 5 ): r["dpos"] - 1] ): continue
        if n in keep4: continue
        pick.append( r )
    for _ in range( len( pick ) + 1 ):   # K5 to a fixpoint
        kept = [ r for r in D if r not in pick ]
        pick = [ r for r in pick if not any( k["a"].get( "same_as" ) == r["a"].get( "n" ) for k in kept ) ]
    return pick
off, on, keep4 = open( sys.argv[1] ).read(), open( sys.argv[2] ).read(), set( sys.argv[3].split( "," ) )
pick = rule( off, keep4 )
LEG = "<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->"
exp, at = [], 0
for k, r in enumerate( pick ):
    exp += [ off[at:r["s"]], LEG if k == 0 else "", '<t p="%s" sym="%s"%s/>' % ( r["raw"]["p"], r["raw"]["n"], ' r="%s"' % r["raw"]["r"] if "r" in r["raw"] else "" ) ]; at = r["e"]
exp = "".join( exp ) + off[at:]
est = lambda s: re.sub( r' est_tokens="\d+"', "", s, count = 1 )
print( "rows " + ",".join( r["a"]["n"] for r in pick ) )
print( ( "PASS" if est( exp ) == est( on ) else "FAIL" ) + " (a) %d rows" % len( pick ) )
PY
# names of the in-sigs pointers, and of the <d> rows, of an answer
cat >"$TMP/names.py" <<'PY'
import re, sys
t = re.sub( r"<!--.*?-->", "", open( sys.argv[1] ).read(), flags = re.S )
s = t[t.find( "<sigs" ):t.find( "</sigs>" )]
print( "ptr " + ",".join( re.findall( r'<t p="[^"]*" sym="([^"]*)"(?: r="\d+")?/>', s ) ) )
print( "rows " + ",".join( re.findall( r'<d [^>]*?\bn="([^"]*)"', s ) ) )
PY

run(){ ( cd "$TMP/py" && "$BIN" . --no-cache "$@" ); }
run "--for=$TASK" >"$TMP/on.xml"; rc1=$?
RIPWIRE_NO_SIBLING_DEMOTE=1 run "--for=$TASK" >"$TMP/off.xml"; rc2=$?
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] || no "runs exited $rc1 / $rc2"
KEEP4='parse_widget_config,widget_config_reader,widget_config_check,widget_config_bridge,widget_config_far_caller'
python3 "$TMP/check.py" "$TMP/off.xml" "$TMP/on.xml" "$KEEP4" >"$TMP/a.res" 2>&1
grep -q '^PASS (a)' "$TMP/a.res" && ! grep -q '^PASS (a) 0 rows' "$TMP/a.res" && ok "(a) the answer is the off answer with exactly the rule's rows as pointers ($( grep -o '[0-9]* rows' "$TMP/a.res" ))" \
  || no "(a) $( head -c 600 "$TMP/a.res" )"
python3 "$TMP/names.py" "$TMP/on.xml" >"$TMP/on.names"
ptr="$( sed -n 's/^ptr //p' "$TMP/on.names" ),"; rws="$( sed -n 's/^rows //p' "$TMP/on.names" ),"
isptr(){ case ",$ptr" in *",$1,"*) return 0;; esac; return 1; }
isrow(){ case ",$rws" in *",$1,"*) return 0;; esac; return 1; }
arm(){ # arm ID want(row|ptr) NAME WHAT
  if { [ "$2" = row ] && isrow "$3" && ! isptr "$3"; } || { [ "$2" = ptr ] && isptr "$3" && ! isrow "$3"; }; then ok "($1) $3 is a $2: $4"; else no "($1) $3 is not a $2 ($4): ptr=$ptr rows=$rws"; fi
}
arm a2 ptr widget_config_variant_04 "a plain same-file sibling at position 11"
arm a2 ptr widget_config_other_03 "a deep row of the second file"
arm p row widget_config_variant_03 "answer position 10 is never demoted"
arm k1 row WidgetVault "it carries mem="
arm k2 row WidgetConfigSink.widget_config_flush "a <c> callee under the head's <h> row"
arm k3 row WidgetShelf.widget_shelf_row "its owner row WidgetShelf sits right above"
arm k4 row widget_config_far_caller "a proven 2-hop caller of the head"
arm k4 ptr widget_config_farther_caller "3 hops from the head: no guard"
arm k5 row widget_shelf_row "the kept WidgetShelf.widget_shelf_row says same_as= it"
grep -q 'same_as="widget_shelf_row"' "$TMP/on.xml" || no "(k5) the fixture no longer prints same_as=\"widget_shelf_row\""

eon="$( grep -o '^<ctx [^>]*' "$TMP/on.xml" | grep -o ' est_tokens="[0-9]*"' | grep -o '[0-9]*' )"
eoff="$( grep -o '^<ctx [^>]*' "$TMP/off.xml" | grep -o ' est_tokens="[0-9]*"' | grep -o '[0-9]*' )"
[ -n "$eon" ] && [ -n "$eoff" ] && [ "$eon" -lt "$eoff" ] && ok "(e) est_tokens re-priced: $eoff -> $eon" || no "(e) est_tokens off=$eoff on=$eon"
if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$TMP/on.xml" 2>"$TMP/w.err" && ok "(w) well formed" || no "(w) $( head -c 300 "$TMP/w.err" )"; fi
nl="$( python3 -c 'import sys; print( open( sys.argv[1] ).read().count( "<!-- demote:" ) )' "$TMP/on.xml" )"
lc="$( python3 -c 'import sys; t = open( sys.argv[1] ).read(); a = t.find( "<!-- demote:" ) + 4; print( t[a:t.find( "-->", a )] )' "$TMP/on.xml" )"
[ "$nl" = 1 ] && [ "${lc#*--}" = "$lc" ] && ok "(l) one legend comment, no double hyphen inside" || no "(l) legend comments=$nl"

run "--for=$UTASK" >"$TMP/u.xml"
python3 "$TMP/names.py" "$TMP/u.xml" >"$TMP/u.names"
ptr="$( sed -n 's/^ptr //p' "$TMP/u.names" ),"; rws="$( sed -n 's/^rows //p' "$TMP/u.names" ),"
nu="$( grep -o '<u [^>]*v="unknown"' "$TMP/u.xml" | wc -l | tr -d ' ' )"
[ "$nu" -gt 10 ] || no "(r) the unused-in-file table no longer leads with > 10 rows ($nu)"
arm r row widget_config_reader "<d> rank 5, answer position $(( nu + 5 ))"
arm r row WidgetConfigSink "<d> rank 3"
arm r ptr widget_config_variant_01 "<d> rank 6"

run "--for=$TASK" --token-budget=4000 >"$TMP/b.xml"
python3 "$TMP/names.py" "$TMP/b.xml" >"$TMP/b.names"
if grep -q '^ptr $' "$TMP/b.names" && ! grep -q '<!-- demote:' "$TMP/b.xml"; then ok "(b) --token-budget: no pointer in <sigs>"; else no "(b) $( head -c 300 "$TMP/b.names" )"; fi

mcp(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$TMP/py" "$TASK" \
  | ( cd "$TMP/py" || exit 1; "$BIN" --mcp 2>/dev/null ) | python3 -c '
import json, sys
for line in sys.stdin:
    d = json.loads( line )
    if d.get( "id" ) == 1:
        print( d["result"]["content"][0]["text"], end="" )
'; }
mcp >"$TMP/x.xml"
RIPWIRE_NO_SIBLING_DEMOTE=1 mcp >"$TMP/xoff.xml"
python3 "$TMP/check.py" "$TMP/xoff.xml" "$TMP/x.xml" "$KEEP4" >"$TMP/x.res" 2>&1
if [ -s "$TMP/x.xml" ] && grep -q '^PASS (a)' "$TMP/x.res" && ! grep -q '^PASS (a) 0 rows' "$TMP/x.res"; then ok "(x) MCP for (one renderer): its answer with exactly the rule's rows as pointers ($( grep -o '[0-9]* rows' "$TMP/x.res" ))"
else no "(x) MCP $( head -c 400 "$TMP/x.res" )"; fi
[ "$fail" = 0 ] && echo "forsiblingdemotecheck: PASS" || echo "forsiblingdemotecheck: FAIL"
exit "$fail"
