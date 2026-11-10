#!/usr/bin/env bash
# forsiblingdemotecheck.sh — SIBLING-DEMOTE (src/forsiblingdemote.h): a ranked <sigs> <d> row with <d> rank > 10 (kDemoteMinRank; its
# answer-row position — the <d>, <y>, <s> and non-`used` <u> rows in output order — is then past 10 too) and a higher <d> row of the same
# file is printed in its place as a tail pointer <t p="FILE" sym="NAME"/>, unless a keep guard holds (K1 mem=, K2 a <c> callee of a <h> hop row, K3 Owner.member under its
# Owner row, K4 a proven call path of <= 2 edges to one of the first three resolved answer rows or a row the task names, K5 a kept
# row's same_as= names it, K6 the row carries a <note>, K7 it carries slot_by= / slot_fields=).
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
#   (r)  rank (PRECISION-LAB 11-10: a demote at rank 6-10 pulls deeper rows into the top 10): an unused-in-file table puts 28 <u> rows
#        first, so every <d> row is past position 10; the decoys of rank <= 10 stay rows (rank 5, 6 and 10), rank 11 goes; on the plain
#        answer a decoy at rank 15 is a pointer
#   (k1) WidgetVault (mem=) stays a row          (k2) WidgetConfigSink.widget_config_flush (a <c> under the head's <h>) stays a row
#   (k3) WidgetShelf.widget_shelf_row (WidgetShelf right above) stays a row
#   (k4) widget_config_far_caller (proven 2-hop caller of the head) stays a row; twin: widget_config_farther_caller (3 hops) is a pointer
#   (k5) widget_shelf_row stays a row: the kept WidgetShelf.widget_shelf_row says same_as="widget_shelf_row"
#   (k6) a copy of the tree (a git repo) with a --note-add note on widget_config_variant_07: that row stays a row, its note intact,
#        and (a) holds on it; twin: widget_config_variant_08 (no note) is still a pointer. K7 (slot facts) is driven by fnslotcheck
#        (F1b/K2/K3/X2b/F4) and K4's task-named seeds by pymodcallsitescheck (X7/X7b/X7c), whose rows sit past rank 10.
#   (e)  est_tokens= is re-priced down (estchargecheck holds its value to the bytes); (w) well formed; (l) one legend comment, no "--" in it
#   (b)  --token-budget leaves the answer as shaped: no pointer in <sigs>, no legend comment
#   (b2) a bare --max-tokens (not read by --for: its notice says nothing was dropped) does not hold the demote: byte-identical to (a)'s
#   (g)  GROWTH (sit 11-08: 4 aborts): a second tree of ten one-row files and z.py's four short undocumented rows. The legend comment
#        and three pointers outweigh the rows they replace, so the answer GROWS: the run exits 0 and answers, (a) holds on it (default
#        and --signatures-only), and on --signatures-only (markup only) est_tokens = round(bytes/2.50) exactly and is above the off
#        twin's (re-priced UP; the unsigned cut used to wrap and fail repriceRootAfterCut's EXPECTS)
#   (x)  MCP `for` (one renderer): (a) on the MCP answer and its RIPWIRE_NO_SIBLING_DEMOTE=1 twin (its <h> rows differ from the CLI's,
#        so its K2 reads differ: the rule is checked on its own bytes)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forsiblingdemotecheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
        if not r["sigs"] or r["dpos"] <= 10 or "mem" in r["a"] or "slot_by" in r["a"] or "slot_fields" in r["a"]: continue
        if "<note " in t[r["s"]:r["e"]]: continue   # K6
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
arm p row widget_config_variant_03 "answer position 10, <d> rank 10, is never demoted"
arm r ptr widget_config_variant_08 "a same-file decoy at <d> rank 15"
arm k1 row WidgetVault "it carries mem="
arm k2 row WidgetConfigSink.widget_config_flush "a <c> callee under the head's <h> row"
arm k3 row WidgetShelf.widget_shelf_row "its owner row WidgetShelf sits right above"
arm k4 row widget_config_far_caller "a proven 2-hop caller of the head"
arm k4 ptr widget_config_farther_caller "3 hops from the head: no guard"
arm k5 row widget_shelf_row "the kept WidgetShelf.widget_shelf_row says same_as= it"
grep -q 'same_as="widget_shelf_row"' "$TMP/on.xml" || no "(k5) the fixture no longer prints same_as=\"widget_shelf_row\""

# (k6) NOTED: a row carrying a --note-add note stays a row (a pointer would drop the note)
cp -R "$TMP/py" "$TMP/py6"
( cd "$TMP/py6" && git init -q -b main . && git add -A && git -c user.email=gate@example.invalid -c user.name=gate commit -qm fx ) || no "(k6) could not make the fixture copy a git repo"
"$BIN" "$TMP/py6" --note-add="widget_config_variant_07: keep the variant table in step with the parser" >/dev/null 2>&1
( cd "$TMP/py6" && "$BIN" . --no-cache "--for=$TASK" ) >"$TMP/k6.on"
( cd "$TMP/py6" && RIPWIRE_NO_SIBLING_DEMOTE=1 "$BIN" . --no-cache "--for=$TASK" ) >"$TMP/k6.off"
python3 "$TMP/check.py" "$TMP/k6.off" "$TMP/k6.on" "$KEEP4" >"$TMP/k6.res" 2>&1
python3 "$TMP/names.py" "$TMP/k6.on" >"$TMP/k6.names"
ptr="$( sed -n 's/^ptr //p' "$TMP/k6.names" ),"; rws="$( sed -n 's/^rows //p' "$TMP/k6.names" ),"
grep -q 'keep the variant table in step' "$TMP/k6.off" || no "(k6) the off answer carries no note on widget_config_variant_07 — the arm cannot see K6"
arm k6 row widget_config_variant_07 "it carries a --note-add note"
arm k6 ptr widget_config_variant_08 "no note: the twin is still a pointer"
grep -q 'keep the variant table in step' "$TMP/k6.on" && grep -q '^PASS (a)' "$TMP/k6.res" && ok "(k6) the note is printed and (a) holds ($( grep -o '[0-9]* rows' "$TMP/k6.res" ))" \
  || no "(k6) note missing from the answer or (a): $( head -c 300 "$TMP/k6.res" )"
ptr="$( sed -n 's/^ptr //p' "$TMP/on.names" ),"; rws="$( sed -n 's/^rows //p' "$TMP/on.names" ),"

eon="$( grep -o '^<ctx [^>]*' "$TMP/on.xml" | grep -o ' est_tokens="[0-9]*"' | grep -o '[0-9]*' )"
eoff="$( grep -o '^<ctx [^>]*' "$TMP/off.xml" | grep -o ' est_tokens="[0-9]*"' | grep -o '[0-9]*' )"
if [ -n "$eon" ] && [ -n "$eoff" ] && [ "$eon" -lt "$eoff" ]; then ok "(e) est_tokens re-priced: $eoff -> $eon"; else no "(e) est_tokens off=$eoff on=$eon"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/on.xml" 2>"$TMP/w.err"; then ok "(w) well formed"; else no "(w) $( head -c 300 "$TMP/w.err" )"; fi
fi
nl="$( python3 -c 'import sys; print( open( sys.argv[1] ).read().count( "<!-- demote:" ) )' "$TMP/on.xml" )"
lc="$( python3 -c 'import sys; t = open( sys.argv[1] ).read(); a = t.find( "<!-- demote:" ) + 4; print( t[a:t.find( "-->", a )] )' "$TMP/on.xml" )"
if [ "$nl" = 1 ] && [ "${lc#*--}" = "$lc" ]; then ok "(l) one legend comment, no double hyphen inside"; else no "(l) legend comments=$nl"; fi

run "--for=$UTASK" >"$TMP/u.xml"
python3 "$TMP/names.py" "$TMP/u.xml" >"$TMP/u.names"
ptr="$( sed -n 's/^ptr //p' "$TMP/u.names" ),"; rws="$( sed -n 's/^rows //p' "$TMP/u.names" ),"
nu="$( grep -o '<u [^>]*v="unknown"' "$TMP/u.xml" | wc -l | tr -d ' ' )"
[ "$nu" -gt 10 ] || no "(r) the unused-in-file table no longer leads with > 10 rows ($nu)"
arm r row widget_config_reader "a same-file decoy at <d> rank 5, answer position $(( nu + 5 ))"
arm r row WidgetConfigSink "<d> rank 3"
arm r row widget_config_variant_01 "a same-file decoy at <d> rank 6, answer position $(( nu + 6 ))"
arm r row widget_config_variant_05 "a same-file decoy at <d> rank 10, answer position $(( nu + 10 ))"
arm r ptr widget_config_variant_06 "a same-file decoy at <d> rank 11"

run "--for=$TASK" --token-budget=4000 >"$TMP/b.xml"
python3 "$TMP/names.py" "$TMP/b.xml" >"$TMP/b.names"
if grep -q '^ptr $' "$TMP/b.names" && ! grep -q '<!-- demote:' "$TMP/b.xml"; then ok "(b) --token-budget: no pointer in <sigs>"; else no "(b) $( head -c 300 "$TMP/b.names" )"; fi
run "--for=$TASK" --max-tokens=4000 >"$TMP/m.xml" 2>/dev/null
if cmp -s "$TMP/m.xml" "$TMP/on.xml"; then ok "(b2) a bare --max-tokens (not read by --for) leaves the demoted answer byte-identical to the flagless one"; else no "(b2) --max-tokens=4000 changed the answer (it is not read by --for: forbodyfoldcheck F8m)"; fi

# (g) GROWTH: short rows, the answer grows (the legend comment and three pointers outweigh the rows they replace)
python3 - "$TMP/g" <<'PY' || { echo "fixture generator failed"; exit 2; }
import os, sys
d = sys.argv[1]; os.makedirs( d, exist_ok = True )
for i in range( 1, 11 ):
    open( os.path.join( d, f"m{i:02d}.py" ), "w" ).write( f'\ndef zap_mode_{i:02d}(x):\n    """Zap mode {i}."""\n    return x\n' )
open( os.path.join( d, "z.py" ), "w" ).write( "".join( f'\ndef zap_m{i}(x):\n    return x\n' for i in range( 1, 5 ) ) )
PY
grun(){ ( cd "$TMP/g" && "$BIN" . --no-cache --for="zap mode" "$@" 2>"$TMP/g.err" ); }
for shape in default sigonly; do
    flag=(); [ "$shape" = sigonly ] && flag=( --signatures-only )
    grun ${flag[@]+"${flag[@]}"} >"$TMP/g.$shape.on"; grc=$?
    RIPWIRE_NO_SIBLING_DEMOTE=1 grun ${flag[@]+"${flag[@]}"} >"$TMP/g.$shape.off"
    gon="$( wc -c <"$TMP/g.$shape.on" | tr -d ' ' )"; goff="$( wc -c <"$TMP/g.$shape.off" | tr -d ' ' )"
    python3 "$TMP/check.py" "$TMP/g.$shape.off" "$TMP/g.$shape.on" "" >"$TMP/g.res" 2>&1
    if [ "$grc" = 0 ] && [ "$gon" -gt "$goff" ] && grep -q '^PASS (a)' "$TMP/g.res" && ! grep -q '^PASS (a) 0 rows' "$TMP/g.res"; then
        ok "(g) $shape: the demote grows the answer $goff -> $gon B, rc 0, (a) holds ($( grep -o '[0-9]* rows' "$TMP/g.res" ))"
    else
        no "(g) $shape: rc=$grc bytes off=$goff on=$gon $( head -c 300 "$TMP/g.res" ) $( grep -m1 'Expr:' "$TMP/g.err" )"
    fi
done
gest="$( RIPWIRE_TESTLIB="$ROOT/test/lib" python3 - "$TMP/g.sigonly.on" "$TMP/g.sigonly.off" <<'PY'
import os, re, sys; sys.path.insert( 0, os.environ[ "RIPWIRE_TESTLIB" ] ); from softbudget import strip_appended_bytes
def est( f ):
    d = strip_appended_bytes( open( f, "rb" ).read() ); m = re.search( rb'est_tokens="(\d+)"', d )
    return ( int( m.group( 1 ) ) if m else -1 ), int( len( d ) / 2.50 + 0.5 )
( e, x ), ( eo, xo ) = est( sys.argv[1] ), est( sys.argv[2] )
print( f"{'PASS' if e == x and eo == xo and e > eo else 'FAIL'} on est={e} expected={x}, off est={eo} expected={xo}" )
PY
)"
case "$gest" in PASS*) ok "(g) --signatures-only est_tokens exact and re-priced up: ${gest#PASS }";; *) no "(g) est_tokens: $gest";; esac

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
