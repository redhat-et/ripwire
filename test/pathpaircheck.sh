#!/usr/bin/env bash
# pathpaircheck.sh — --path / path_between list EVERY reaching definition pair of a many-definition endpoint (src/pathpairs.h).
#
# THE DEFECT. --path=A,B with several definitions of A or B printed the first chain one multi-source BFS met and nothing else,
# so a reader could not tell that another definition pair also reached — fzf `--path=Loop,extendedMatch` printed Terminal.Loop's
# chain while Matcher.Loop (the one meant) reaches in 5 proven hops. No reach or hop key can pick between such pairs.
#
# THE CONTRACT. When two or more definition pairs reach (a directed chain each, then at most one hedged bridge per to= definition
# no chain reaches), the answer prints pairs_reaching=N and up to 3 <pair hops= hedged=> chains: fewest hedged hops first (an
# all-proven chain before any hedged one), then fewest hops; hedged= counts the chain's via=/prov=split/anchor=missing rows, so a
# hedged chain never reads as proven. More than 3 → alt=N + one <alt> row each + next= running the first alternative. A chain
# whose tail repeats an earlier printed chain stops where it meets it (joins=J). Exactly one reaching pair and no reaching pair
# keep today's answer (no pairs_reaching=, hop rows directly under <path>). A glob endpoint keeps its any-of-these meaning.
# MCP path_between prints the same rows.
#
# ARMS
#   (A) Go: A.Run -> midA -> leaf and B.Run -> leaf: pairs_reaching=2, two all-proven chains, the 1-hop one first.
#   (B) Python: Wrong.go -> target (proven) and Gold.go -> x.relay() (via=name) -> target: both printed, the proven one first,
#       the hedged one hedged=1 with its via="name" row; the via=name legend clause rides.
#   (C) Python: five C<i>.go -> mid<i> -> target: pairs_reaching=5, 3 chains, alt=2 + 2 <alt> rows; next= replays the first alt
#       as a one-definition answer (from_defs=1, reachable=1, from_p= the alt row's).
#   (W) twenty C<i>.go: alt=17, 12 <alt> rows, alt_capped="1" (the row cap is disclosed, the count is whole).
#   (D) exactly-one control: only A.go reaches: no pairs_reaching=, no <pair>, the hop rows sit under <path>.
#   (E) none-reach control: reachable=0, no pairs_reaching=, no <pair>.
#   (J) shared tail: B.go -> a_hop -> m1 -> m2 -> m3 -> target beside A.go -> m1 -> …: joins="1", 3 rows printed for pair 2.
#   (G) glob endpoint (g*): no pairs_reaching= (a glob already means any of these).
#   (X) every printed non-joined pair's hedged= equals its marked rows; hedged=0 pairs carry no via=/prov= row.
#   (L) the full legend carries the pairs clause exactly when pairs print; answers parse as XML (xmllint when present).
#   (T) one site, two definitions: JS `compile: function compile` is the property and the function expression on ONE line — one
#       pair, today's bytes (no pairs_reaching=, no <pair>); rv-trace-ep F1 printed two byte-identical pairs, pairs_reaching=2.
#   (V) minified same-line SIBLINGS `class A{render(){}}class B{render(){}}` (disjoint spans) are TWO sites: pairs_reaching=2, two
#       <pair>s; only NESTED same-line twins (T) fold (rv-delta-38 F1-b: the fold keyed on file+line+name folded these into one).
#   (U) 17 to= definition groups (past the 16 walked): the one chain stays, DISCLOSED — pairs_unlisted="17" + next= + the legend
#       clause, and no pairs_reaching=; a 16-group control lists its pairs (no pairs_unlisted=).
#   (N) five to= definition groups no chain reaches (past the 4 bridge searches): bridges_unsearched="1" says one was not searched;
#       a 4-group control carries no bridges_unsearched= (CodeRabbit 4387143972: the cap was silent).
#   (M) MCP path_between prints the CLI's <pair>/<alt>/<s> rows on A, B, C, J.
#   P1 PATH-ORDER (fzf-14 / zed-03):
#   (Q) question words: Terminal.Loop (1 hop) and Matcher.Loop (2 hops) reach matcher.go:extendedMatch; the argv's own word
#       `matcher` equals Matcher.Loop's owner, so that pair prints FIRST with qword="matcher" and the qword legend clause rides.
#       (QN) near miss: `--path=Loop,extendedMatch` (no owner word in the argv) keeps the reach order, no qword=, no clause.
#   (QA) a word every listed pair's owner carries orders nothing: no qword= (zed `Editor::backspace,Buffer::edit`).
#   (QH) a question word never lifts a hedged chain over a proven one: Gold.go (owner word, via=name) stays after Wrong.go.
#   (Z) test twin: the bound from= backspace is fixtures/copy/before.py's (the shorter chain) while src/core.py:backspace exists:
#       from_test="1" + next= naming src/core.py's; next= replays as that one definition. (ZS) the same when only the fixture
#       copy reaches (one pair, no pairs_reaching=). (ZT) to= side: to_test="1" for a tests/ copy of the to= name (no source edit reaches from the tests/ backspace: no next=).
#       (ZN) near misses: the bound def is a source one (a fixture copy also reaches, another source def exists) -> none;
#       every def in tests -> none.
#   (ZM) MCP path_between prints the same from_test= / next= root attributes.
#   P1 PATH-ORDER fix 1 (rv-path-order F1-F3):
#   (QM) the from= owner is read first: Terminal.Loop and Matcher.Loop both reach matcher.go:scan, whose OWNER (Matcher) is a word
#       too; the to= owner fallback marked EVERY pair (all-marked clear, no reorder). Now only Matcher.Loop is marked and leads.
#   (QT) the to= owner is read only when no pair's from= owner carries a word: `matcher.go:start,scan`, to= Matcher.scan (2 hops)
#       and Other.scan (1 hop): Matcher's leads. (Mutant: drop the to= fallback -> red.)
#   (ZF) the twin's next= names a definition that REACHES: an unrelated source Foo.backspace sorted first is skipped. (ZS) when no
#       source definition reaches, from_test=1 prints with NO next=.
#   (ZD) a C declaration is never the source twin (tests/x.c defines backspace, src/core.h declares it: no disclosure); (ZE) a real
#       definition beside the declaration is named. (ZP) a twin next= beside alt=: the alt continuation is alt_next=, not lost.
#   (ZX) the same beside pairs_unlisted=: a bound tests/ `start` with 17 to= groups: unlisted_next= keeps the cap's continuation, next= is the source
#       twin's (cr-prepass-39; the alt= arm above never reached the unlisted_next= branch).
#
# Usage: test/pathpaircheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "pathpaircheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

mkdir -p "$TMP/min" "$TMP/site" "$TMP/capd" "$TMP/capok" "$TMP/wide" "$TMP/two" "$TMP/hedge" "$TMP/many" "$TMP/bcap" "$TMP/bok" "$TMP/one" "$TMP/none" "$TMP/join"
cat > "$TMP/two/m.go" <<'EOF'
package m

type A struct{}
type B struct{}

func leaf() int { return 1 }
func midA() int { return leaf() }
func (a A) Run() int { return midA() }
func (b B) Run() int { return leaf() }
EOF
cat > "$TMP/hedge/h.py" <<'EOF'
class Relay:
    def relay(self):
        return target()

def target():
    return 1

class Wrong:
    def go(self):
        return target()

class Gold:
    def go(self, x):
        return x.relay()
EOF
cat > "$TMP/site/a.js" <<'EOF'
function sink() { return 1; }
function helper() { return sink(); }
module.exports = {
  compile: function compile(src) { return helper(); }
};
EOF
cat > "$TMP/site/c.js" <<'EOF'
const a = require('./a');
function start(x) { return a.compile(x); }
EOF
cat > "$TMP/min/m.js" <<'EOF'
class A{render(){return 1}}class B{render(){return 2}}
function viaA(a){return a.render()}
function viaB(b){return b.render()}
function start(){const a=new A();const b=new B();viaA(a);viaB(b);a.render();b.render()}
module.exports={A,B,start}
EOF
python3 - "$TMP" <<'PY'
import sys
t = sys.argv[1]
for d, n in ( ( "capd", 17 ), ( "capok", 16 ) ):
    open( t + "/" + d + "/k.py", "w" ).write( "".join( "class C%d:\n    def target(self):\n        return 1\n\n" % i for i in range( n ) ) + "def start(x):\n    return x.target()\n" )
for d, n in ( ( "bcap", 5 ), ( "bok", 4 ) ):   # two go() definitions reach the module target; n more target() definitions nothing reaches
    open( t + "/" + d + "/k.py", "w" ).write( "def target():\n    return 1\n\n" + "".join( "class G%d:\n    def go(self):\n        return target()\n\n" % i for i in range( 2 ) )
                                              + "".join( "class U%d:\n    def target(self):\n        return 2\n\n" % i for i in range( n ) ) )
open( t + "/many/k.py", "w" ).write( "def target():\n    return 1\n\n" + "".join( "class C%d:\n    def go(self):\n        return mid%d()\n\ndef mid%d():\n    return target()\n\n" % ( i, i, i ) for i in range( 5 ) ) )
open( t + "/wide/w.py", "w" ).write( "def target():\n    return 1\n\n" + "".join( "class C%d:\n    def go(self):\n        return target()\n\n" % i for i in range( 20 ) ) )
open( t + "/one/o.py", "w" ).write( "def target():\n    return 1\n\nclass A:\n    def go(self):\n        return target()\n\nclass B:\n    def go(self):\n        return 2\n" )
open( t + "/none/n.py", "w" ).write( "def target():\n    return 1\n\nclass A:\n    def go(self):\n        return 3\n\nclass B:\n    def go(self):\n        return 2\n" )
open( t + "/join/j.py", "w" ).write( "def target():\n    return 1\n\ndef m3():\n    return target()\n\ndef m2():\n    return m3()\n\ndef m1():\n    return m2()\n\n"
                                     "class A:\n    def go(self):\n        return m1()\n\nclass B:\n    def go(self):\n        return a_hop()\n\ndef a_hop():\n    return m1()\n" )
PY
run(){ ( cd "$TMP/$1" || exit 1; "$BIN" "$TMP/$1" --no-cache "--path=$2" "${@:3}" </dev/null ); }
run two  Run,leaf     > "$TMP/A.out"; run hedge go,target > "$TMP/B.out"; run many go,target > "$TMP/C.out"
run one  go,target    > "$TMP/D.out"; run none  go,target > "$TMP/E.out"; run join go,target > "$TMP/J.out"
run min start,render > "$TMP/V.out"; run site start,compile > "$TMP/T.out"; run capd start,target > "$TMP/U.out"; run capok start,target > "$TMP/UK.out"
run many 'g*,target'  > "$TMP/G.out"; run wide go,target > "$TMP/W.out"
mkdir -p "$TMP/twu/src" "$TMP/twu/tests"
printf 'def edit():\n    return 1\n\ndef helper():\n    return edit()\n\ndef backspace():\n    return helper()\n' > "$TMP/twu/src/core.py"
printf 'def edit():\n    return 1\n\ndef backspace():\n    return edit()\n' > "$TMP/twu/tests/fake.py"
mkdir -p "$TMP/zp/src" "$TMP/zp/tests"
cp "$TMP/many/k.py" "$TMP/zp/src/k.py"; printf 'from src.k import target\n\ndef go():\n    return target()\n' > "$TMP/zp/tests/t.py"
mkdir -p "$TMP/zx/src" "$TMP/zx/tests"
python3 - "$TMP" <<'PY'
import sys
t = sys.argv[1]
open( t + "/zx/src/k.py", "w" ).write( "".join( "class C%d:\n    def target(self):\n        return 1\n\n" % i for i in range( 17 ) ) + "def helper():\n    return C0().target()\n\ndef start():\n    return helper()\n" )
open( t + "/zx/tests/t.py", "w" ).write( "from src.k import C0\n\ndef start():\n    return C0().target()\n" )
PY
mkdir -p "$TMP/qm" "$TMP/qt" "$TMP/twf/src" "$TMP/twf/fixtures/copy" "$TMP/cd/src" "$TMP/cd/tests" "$TMP/ce/src" "$TMP/ce/tests"
printf 'package m\n\ntype Matcher struct{}\n\nfunc (m *Matcher) helper() int { return m.scan() }\nfunc (m *Matcher) Loop() int   { return m.helper() }\nfunc (m *Matcher) scan() int   { return 1 }\n' > "$TMP/qm/matcher.go"
printf 'package m\n\ntype Terminal struct{ m *Matcher }\n\nfunc (t Terminal) Loop() int { return t.m.scan() }\n' > "$TMP/qm/terminal.go"
printf 'package m\n\ntype Other struct{}\ntype Matcher struct{}\n\nfunc (o Other) scan() int { return 2 }\nfunc (m Matcher) scan() int { return 1 }\nfunc helper(m Matcher) int { return m.scan() }\nfunc start(m Matcher, o Other) int { return o.scan() + helper(m) }\n' > "$TMP/qt/matcher.go"
printf 'def edit():\n    return 1\n\ndef helper():\n    return edit()\n\ndef backspace():\n    return helper()\n' > "$TMP/twf/src/core.py"
printf 'from src.core import edit\n\ndef backspace():\n    return edit()\n' > "$TMP/twf/fixtures/copy/before.py"
printf 'class Foo:\n    def backspace(self):\n        return 0\n' > "$TMP/twf/src/aaa.py"
for d in cd ce; do printf 'int edit(void);\nint backspace(void);\n' > "$TMP/$d/src/core.h"; printf '#include "core.h"\nint edit(void) { return 1; }\n' > "$TMP/$d/src/edit.c"
                   printf '#include "../src/core.h"\nint backspace(void) { return edit(); }\n' > "$TMP/$d/tests/x.c"; done
printf '#include "core.h"\nstatic int helper(void) { return edit(); }\nint backspace(void) { return helper(); }\n' > "$TMP/ce/src/impl.c"
mkdir -p "$TMP/qw" "$TMP/qh" "$TMP/tw/src" "$TMP/tw/fixtures/copy" "$TMP/tws/src" "$TMP/tws/fixtures/copy" "$TMP/twt/src" "$TMP/twt/tests" \
         "$TMP/twn/src" "$TMP/twn/fixtures/copy" "$TMP/twa/tests"
cat > "$TMP/qw/terminal.go" <<'EOF'
package m

type Terminal struct{}

func (t Terminal) Loop() int { return extendedMatch() }
EOF
cat > "$TMP/qw/matcher.go" <<'EOF'
package m

type Matcher struct{}

func extendedMatch() int { return 1 }
func scan() int { return extendedMatch() }
func (m Matcher) Loop() int { return scan() }
EOF
cat > "$TMP/qh/gold.py" <<'EOF'
class Relay:
    def relay(self):
        return target()

def target():
    return 1

class Wrong:
    def go(self):
        return target()

class Gold:
    def go(self, x):
        return x.relay()
EOF
mkdir -p "$TMP/qa"; for f in a b; do printf 'def edit():\n    return 1\n\nclass Edit:\n    def backspace(self):\n        return edit()\n' > "$TMP/qa/$f.py"; done
printf 'def edit():\n    return 1\n\ndef helper():\n    return edit()\n\ndef backspace():\n    return helper()\n' > "$TMP/tw/src/core.py"
printf 'from src.core import edit\n\ndef backspace():\n    return edit()\n' > "$TMP/tw/fixtures/copy/before.py"
printf 'def edit():\n    return 1\n\ndef backspace():\n    return 0\n' > "$TMP/tws/src/core.py"
printf 'from src.core import edit\n\ndef backspace():\n    return edit()\n' > "$TMP/tws/fixtures/copy/before.py"
printf 'def backspace():\n    return edit()\n\ndef edit():\n    return 1\n' > "$TMP/twt/tests/fake.py"
printf 'def edit():\n    return 1\n\ndef helper():\n    return edit()\n' > "$TMP/twt/src/core.py"
printf 'def edit():\n    return 1\n\ndef backspace():\n    return edit()\n' > "$TMP/twn/src/core.py"
printf 'from src.core import edit\n\ndef helper():\n    return edit()\n\ndef backspace():\n    return helper()\n' > "$TMP/twn/fixtures/copy/before.py"
printf 'def backspace():\n    return 0\n' > "$TMP/twn/src/other.py"   # a second SOURCE def: the bound one is not in tests, so none
printf 'def edit():\n    return 1\n\ndef backspace():\n    return edit()\n' > "$TMP/twa/tests/a_test.py"
printf 'def edit():\n    return 2\n\ndef helper():\n    return edit()\n\ndef backspace():\n    return helper()\n' > "$TMP/twa/tests/b_test.py"
run qw Loop,matcher.go:extendedMatch > "$TMP/Q.out"; run qw Loop,extendedMatch > "$TMP/QN.out"
run qw Loop,matcher.go:extendedMatch --legend=full > "$TMP/QL.out"; run qw Loop,extendedMatch --legend=full > "$TMP/QNL.out"
run qh go,gold.py:target > "$TMP/QH.out"; run qa backspace,edit > "$TMP/QA.out"
run qm Loop,matcher.go:scan > "$TMP/QM.out"; run qt matcher.go:start,scan > "$TMP/QT.out"
run zx start,target > "$TMP/ZX.out"; run zx start,target --legend=full > "$TMP/ZXL.out"
run zp go,target > "$TMP/ZP.out"; run zp go,target --legend=full > "$TMP/ZPL.out"; run twu backspace,edit > "$TMP/ZU.out"; run twf backspace,edit > "$TMP/ZF.out"; run cd backspace,edit > "$TMP/ZD.out"; run ce backspace,edit > "$TMP/ZE.out"
run tw backspace,edit > "$TMP/Z.out"; run tws backspace,edit > "$TMP/ZS.out"; run twt backspace,edit > "$TMP/ZT.out"
run twn backspace,edit > "$TMP/ZN.out"; run twa backspace,edit > "$TMP/ZA.out"
run tw backspace,edit --legend=full > "$TMP/ZL.out"; run twn backspace,edit --legend=full > "$TMP/ZNL.out"
run bcap go,target > "$TMP/BC.out"; run bok go,target > "$TMP/BK.out"

python3 - "$TMP" "$BIN" <<'PY'
import re, shlex, subprocess, sys
tmp, binp = sys.argv[1], sys.argv[2]
def rd( k ): return open( "%s/%s.out" % ( tmp, k ) ).read()
def root( x ):
    m = re.search( r'<path [^>]*>', x ); return dict( re.findall( r'(\w+)="([^"]*)"', m.group( 0 ) ) ) if m else {}
def pairs( x ): return re.findall( r'<pair ([^>]*)>(.*?)</pair>', x, re.S )
def attrs( s ): return dict( re.findall( r'(\w+)="([^"]*)"', s ) )
bad = []
def check( arm, cond, msg ):
    print( "  %s  (%s) %s" % ( "PASS" if cond else "FAIL", arm, msg ) )
    if not cond: bad.append( arm )
a = rd( "A" ); ra, pa = root( a ), pairs( a )
check( "A", ra.get( "pairs_reaching" ) == "2" and len( pa ) == 2 and all( attrs( p[0] ).get( "hedged" ) == "0" for p in pa )
       and [ attrs( p[0] ).get( "hops" ) for p in pa ] == [ "1", "2" ], "two all-proven pairs, 1-hop first: %r" % [ p[0] for p in pa ] )
b = rd( "B" ); rb, pb = root( b ), pairs( b )
hb = [ attrs( p[0] ) for p in pb ]
check( "B", rb.get( "pairs_reaching" ) == "2" and len( pb ) == 2 and hb[0].get( "hedged" ) == "0" and hb[1].get( "hedged" ) == "1"
       and 'via="name"' in pb[1][1] and 'via="name"' not in pb[0][1] and "h.py:13" in hb[1].get( "from_p", "" ) and "via=name" in b,
       "proven chain first, the hedged one labelled hedged=1 with its via=name row: %r" % hb )
c = rd( "C" ); rc, pc = root( c ), pairs( c )
alts = [ attrs( s ) for s in re.findall( r'<alt ([^>]*)/>', c ) ]
check( "C", rc.get( "pairs_reaching" ) == "5" and rc.get( "alt" ) == "2" and len( pc ) == 3 and len( alts ) == 2 and rc.get( "next", "" ).startswith( "--path=" ),
       "3 chains + alt=2 + 2 <alt> rows + next=: %r" % { k: rc.get( k ) for k in ( "pairs_reaching", "alt", "next" ) } )
if rc.get( "next" ):
    argv = shlex.split( rc[ "next" ].replace( "&apos;", "'" ) )
    o = subprocess.run( [ binp, tmp + "/many", "--no-cache" ] + argv, capture_output = True, text = True, cwd = tmp + "/many", stdin = subprocess.DEVNULL ).stdout
    r2 = root( o )
    check( "C", r2.get( "reachable" ) == "1" and r2.get( "from_defs" ) == "1" and alts and r2.get( "from_p" ) == alts[0].get( "from_p" ) and "pairs_reaching" not in r2,
           "next= replays the first alt as one pair: %r" % { k: r2.get( k ) for k in ( "reachable", "from_defs", "from_p" ) } )
w = rd( "W" ); rw_ = root( w )
check( "W", rw_.get( "pairs_reaching" ) == "20" and rw_.get( "alt" ) == "17" and rw_.get( "alt_capped" ) == "1" and len( re.findall( r'<alt ', w ) ) == 12 and len( pairs( w ) ) == 3,
       "20 pairs: 3 chains, alt=17, 12 rows, alt_capped=1: %r" % { k: rw_.get( k ) for k in ( "pairs_reaching", "alt", "alt_capped" ) } )
check( "W", "alt_capped" not in root( rd( "C" ) ), "alt_capped= absent when every alt row prints" )
d = rd( "D" ); rd_ = root( d )
check( "D", "pairs_reaching" not in rd_ and "<pair" not in d and rd_.get( "reachable" ) == "1" and re.search( r'<path [^>]*><s ', d ) is not None,
       "exactly one reaching pair keeps the hop rows under <path>, no pairs_reaching=" )
e = rd( "E" )
check( "E", "pairs_reaching" not in e and "<pair" not in e and root( e ).get( "reachable" ) == "0", "no reaching pair keeps today's reachable=0 answer" )
j = rd( "J" ); pj = pairs( j )
check( "J", len( pj ) == 2 and attrs( pj[1][0] ).get( "joins" ) == "1" and len( re.findall( r'<s ', pj[1][1] ) ) == 3 and attrs( pj[1][0] ).get( "hops" ) == "5",
       "shared tail: pair 2 joins=1 after 3 rows, hops=5 counts the whole chain: %r" % [ p[0] for p in pj ] )
g = rd( "G" )
check( "G", "pairs_reaching" not in g and root( g ).get( "reachable" ) == "1", "a glob endpoint keeps today's answer" )
t = rd( "T" ); rt = root( t )
check( "T", "pairs_reaching" not in rt and "<pair" not in t and rt.get( "reachable" ) == "1" and rt.get( "to_defs" ) == "2",
       "one JS site = one pair, today's bytes: %r" % { k: rt.get( k ) for k in ( "pairs_reaching", "to_defs", "reachable" ) } )
v = rd( "V" ); rv = root( v )
check( "V", rv.get( "pairs_reaching" ) == "2" and len( pairs( v ) ) == 2 and rv.get( "to_defs" ) == "2",
       "minified same-line siblings stay two pairs: %r" % { k: rv.get( k ) for k in ( "pairs_reaching", "to_defs", "reachable" ) } )
u = rd( "U" ); ru = root( u )
check( "U", ru.get( "pairs_unlisted" ) == "17" and "pairs_reaching" not in ru and "<pair" not in u and ru.get( "reachable" ) == "1" and ru.get( "next", "" ).startswith( "--path=" ),
       "17 to= groups: the one chain, disclosed with pairs_unlisted= + next=: %r" % { k: ru.get( k ) for k in ( "pairs_unlisted", "pairs_reaching", "next", "to_defs" ) } )
if ru.get( "next" ):
    argv = shlex.split( ru[ "next" ].replace( "&apos;", "'" ) )
    o = subprocess.run( [ binp, tmp + "/capd", "--no-cache" ] + argv, capture_output = True, text = True, cwd = tmp + "/capd", stdin = subprocess.DEVNULL ).stdout
    r2 = root( o )
    check( "U", r2.get( "to_defs" ) == "1" and "pairs_unlisted" not in r2, "next= narrows to one to= definition: %r" % { k: r2.get( k ) for k in ( "to_defs", "reachable", "pairs_unlisted" ) } )
uk = rd( "UK" ); ruk = root( uk )
check( "U", "pairs_unlisted" not in ruk and ruk.get( "pairs_reaching", "" ) != "", "16 to= groups are walked and listed (no pairs_unlisted=): %r" % { k: ruk.get( k ) for k in ( "pairs_unlisted", "pairs_reaching" ) } )
bc = rd( "BC" ); rbc = root( bc ); bk = rd( "BK" ); rbk = root( bk )
check( "N", rbc.get( "pairs_reaching" ) == "2" and rbc.get( "to_defs" ) == "6" and rbc.get( "bridges_unsearched" ) == "1",
       "5 unreached to= groups, 4 bridge searches: the 5th is counted, not silent (CodeRabbit 4387143972): %r" % { k: rbc.get( k ) for k in ( "pairs_reaching", "to_defs", "bridges_unsearched" ) } )
check( "N", rbk.get( "pairs_reaching" ) == "2" and rbk.get( "to_defs" ) == "5" and "bridges_unsearched" not in rbk,
       "4 unreached to= groups are all searched: no bridges_unsearched=: %r" % { k: rbk.get( k ) for k in ( "pairs_reaching", "to_defs", "bridges_unsearched" ) } )
xbad = []
for k in ( "A", "B", "C", "J" ):
    for at, body in pairs( rd( k ) ):
        h = attrs( at )
        if "joins" in h or "bridge" in h: continue
        marked = sum( 1 for s in re.findall( r'<s [^>]*/>', body )[1:] if re.search( r'via="|prov="split"|anchor="missing"', s ) )
        if str( marked ) != h.get( "hedged" ): xbad.append( ( k, at ) )
check( "X", not xbad, "hedged= equals the marked rows of every whole printed chain: %r" % xbad )
q = rd( "Q" ); pq = [ attrs( p[0] ) for p in pairs( q ) ]
check( "Q", len( pq ) == 2 and "matcher.go" in pq[0].get( "from_p", "" ) and pq[0].get( "qword" ) == "matcher" and "qword" not in pq[1]
       and "terminal.go" in pq[1].get( "from_p", "" ) and "matcher.go" in root( q ).get( "from_p", "" ) and "qword=WORD:" in rd( "QL" ),
       "the owner-word pair (Matcher.Loop, 2 hops) prints first with qword=matcher, the root binds it: %r" % pq )
qn = rd( "QN" ); pqn = [ attrs( p[0] ) for p in pairs( qn ) ]
check( "QN", len( pqn ) == 2 and "terminal.go" in pqn[0].get( "from_p", "" ) and not any( "qword" in a for a in pqn ) and "qword=WORD:" not in rd( "QNL" ),
       "no owner word in the argv: reach order (1 hop first), no qword=, no clause: %r" % pqn )
qa = rd( "QA" )
check( "QA", "qword=" not in qa and len( pairs( qa ) ) == 2 and root( qa ).get( "pairs_reaching" ) == "2", "no pair told apart by the word: no qword= (%d pairs)" % len( pairs( qa ) ) )
pqh = [ attrs( p[0] ) for p in pairs( rd( "QH" ) ) ]
check( "QH", len( pqh ) == 2 and pqh[0].get( "hedged" ) == "0" and pqh[1].get( "hedged" ) == "1" and pqh[1].get( "qword" ) == "gold"
       and "gold.py:13" in pqh[1].get( "from_p", "" ), "a hedged owner-word pair stays after the proven one: %r" % pqh )
z = rd( "Z" ); rz = root( z )
check( "Z", rz.get( "from_test" ) == "1" and "fixtures/copy/before.py" in rz.get( "from_p", "" ) and rz.get( "next", "" ).startswith( "--path=src/core.py:backspace," )
       and "from_test=1 / to_test=1:" in rd( "ZL" ) and "to_test" not in rz,
       "bound fixture copy disclosed, next= names src/core.py's def: %r" % { k: rz.get( k ) for k in ( "from_p", "from_test", "next", "pairs_reaching" ) } )
if rz.get( "next" ):
    o = subprocess.run( [ binp, tmp + "/tw", "--no-cache" ] + shlex.split( rz[ "next" ].replace( "&apos;", "'" ) ), capture_output = True, text = True, cwd = tmp + "/tw", stdin = subprocess.DEVNULL ).stdout
    r2 = root( o )
    check( "Z", r2.get( "from_defs" ) == "1" and "src/core.py" in r2.get( "from_p", "" ) and r2.get( "reachable" ) == "1" and "from_test" not in r2,
           "next= replays from the source def: %r" % { k: r2.get( k ) for k in ( "from_defs", "from_p", "reachable" ) } )
rzs = root( rd( "ZS" ) )
check( "ZS", rzs.get( "from_test" ) == "1" and "pairs_reaching" not in rzs and "next" not in rzs,
       "only the fixture copy reaches (one pair): still disclosed, and no next= (the source def reaches nothing): %r" % { k: rzs.get( k ) for k in ( "from_test", "next", "pairs_reaching" ) } )
rzt = root( rd( "ZT" ) )
check( "ZT", rzt.get( "to_test" ) == "1" and "from_test" not in rzt and "tests/fake.py" in rzt.get( "to_p", "" ) and "next" not in rzt,
       "to= side: a tests/ copy bound is disclosed; no source edit is reached, so no next=: %r" % { k: rzt.get( k ) for k in ( "to_p", "to_test", "next" ) } )
# CR 4392937862: the compact legend reads an attribute only when THAT attribute is on the answer, so from_test= and to_test= (independent:
# ZT carries to_test= alone) each own a self-contained reading. A to_test-only page must define to_test=; a from_test-only page must not carry
# the other side's reading; both sides carry both.
check( "ZT", "to_test=1: the bound to= definition" in rd( "ZT" ) and "from_test=1:" not in rd( "ZT" ) and "from_test=1 / to_test=1:" not in rd( "ZT" ),
       "compact legend of a to_test-only answer defines to_test= (and not the other side)" )
check( "Z", "from_test=1: the bound from= definition" in z and "to_test=1:" not in z, "compact legend of a from_test-only answer defines from_test= alone" )
zn = rd( "ZN" ); rzn = root( zn ); rza = root( rd( "ZA" ) )
check( "ZN", "from_test" not in rzn and "src/core.py" in rzn.get( "from_p", "" ) and "from_test=1 / to_test=1:" not in rd( "ZNL" ),
       "bound source def (a fixture copy also reaches): no disclosure: %r" % { k: rzn.get( k ) for k in ( "from_p", "from_test" ) } )
check( "ZN", "from_test" not in rza and "to_test" not in rza and rza.get( "reachable" ) == "1", "every def in tests: no source twin, no disclosure: %r" % rza )
pqm = [ attrs( p[0] ) for p in pairs( rd( "QM" ) ) ]
check( "QM", len( pqm ) == 2 and "matcher.go:6" in pqm[0].get( "from_p", "" ) and pqm[0].get( "qword" ) == "matcher" and "qword" not in pqm[1]
       and "terminal.go" in pqm[1].get( "from_p", "" ), "from= owner first: only Matcher.Loop is marked and leads (the to= owner Matcher marks none): %r" % pqm )
pqt = [ attrs( p[0] ) for p in pairs( rd( "QT" ) ) ]
check( "QT", len( pqt ) == 2 and pqt[0].get( "qword" ) == "matcher" and "qword" not in pqt[1] and pqt[0].get( "hops" ) == "2" and pqt[1].get( "hops" ) == "1",
       "no from= owner word: the to= owner's word orders (Matcher.scan, 2 hops, before Other.scan, 1 hop): %r" % pqt )
rzf = root( rd( "ZF" ) )
check( "ZF", rzf.get( "from_test" ) == "1" and rzf.get( "next", "" ).startswith( "--path=src/core.py:backspace," ) and "aaa.py" not in rzf.get( "next", "" ),
       "next= names the source def that reaches, not the unrelated Foo.backspace sorted first: %r" % { k: rzf.get( k ) for k in ( "from_test", "next" ) } )
rzu = root( rd( "ZU" ) )
check( "ZU", rzu.get( "from_test" ) == "1" and rzu.get( "to_test" ) == "1" and rzu.get( "next", "" ) == "--path=src/core.py:backspace,src/core.py:edit",
       "both sides in tests/: each names the source def that reaches: %r" % { k: rzu.get( k ) for k in ( "from_test", "to_test", "next" ) } )
check( "ZU", "from_test=1: the bound from= definition" in rd( "ZU" ) and "to_test=1: the bound to= definition" in rd( "ZU" ), "compact legend of a both-sides answer defines both attributes" )
rzp = root( rd( "ZP" ) )
check( "ZP", rzp.get( "from_test" ) == "1" and rzp.get( "alt" ) == "3" and rzp.get( "next", "" ).startswith( "--path=src/k.py::C" ) and rzp.get( "alt_next", "" ).startswith( "--path=src/k.py::C" )
       and rzp.get( "next" ) != rzp.get( "alt_next" ) and "alt_next=" in rd( "ZPL" ),
       "twin next= and the alt continuation each on their own attribute: %r" % { k: rzp.get( k ) for k in ( "alt", "next", "alt_next" ) } )
rzx = root( rd( "ZX" ) )
check( "ZX", rzx.get( "from_test" ) == "1" and rzx.get( "pairs_unlisted" ) == "17" and rzx.get( "next", "" ).startswith( "--path=src/k.py:start," )
       and rzx.get( "unlisted_next", "" ).startswith( "--path=tests/t.py:start," ) and "alt_next" not in rzx and "alt" not in rzx and "unlisted_next=" in rd( "ZXL" ),
       "17 to= groups + a tests/ copy bound: unlisted_next= keeps the cap's continuation, next= is the source twin's: %r" % { k: rzx.get( k ) for k in ( "pairs_unlisted", "next", "unlisted_next", "alt_next" ) } )
rzd = root( rd( "ZD" ) )
check( "ZD", "from_test" not in rzd and "next" not in rzd and "tests/x.c" in rzd.get( "from_p", "" ) and rzd.get( "from_defs" ) == "2",
       "a C header declaration is not a source twin (no disclosure): %r" % { k: rzd.get( k ) for k in ( "from_p", "from_defs", "from_test", "next" ) } )
rze = root( rd( "ZE" ) )
check( "ZE", rze.get( "from_test" ) == "1" and rze.get( "next", "" ).startswith( "--path=src/impl.c:backspace," ),
       "a real definition beside the declaration is the twin: %r" % { k: rze.get( k ) for k in ( "from_p", "from_test", "next" ) } )
sys.exit( 1 if bad else 0 )
PY
[ $? -eq 0 ] || fail=1

echo "(L) legend clause and well-formedness"
run many go,target --legend=full > "$TMP/CL.out"; run one go,target --legend=full > "$TMP/DL.out"
if grep -q 'pairs_reaching=N: N from=/to= definition pairs reach each other' "$TMP/CL.out" && ! grep -q 'pairs_reaching=N' "$TMP/DL.out"; then
    ok "(L) the full legend carries the pairs clause exactly when pairs print"
else
    no "(L) the pairs clause rides wrongly (with pairs: $(grep -c 'pairs_reaching=N' "$TMP/CL.out"), without: $(grep -c 'pairs_reaching=N' "$TMP/DL.out"))"
fi
run capd start,target --legend=full > "$TMP/UL.out"
if grep -q 'pairs_unlisted=G: to= names G definition groups' "$TMP/UL.out" && ! grep -q 'pairs_unlisted=G' "$TMP/DL.out"; then
    ok "(L) the full legend carries the pairs_unlisted clause exactly when a cap disclosure prints"
else
    no "(L) the pairs_unlisted clause rides wrongly"
fi
run bcap go,target --legend=full > "$TMP/BL.out"
if grep -q 'bridges_unsearched=K' "$TMP/BL.out" && grep -q 'first 4 ' "$TMP/CL.out" && ! grep -q 'bridges_unsearched=K' "$TMP/CL.out"; then
    ok "(L) the pairs clause names the 4-search cap; the bridges_unsearched clause rides exactly when a search was skipped"
else
    no "(L) the bridge-search cap is not stated in the pairs legend"
fi
if command -v xmllint >/dev/null 2>&1; then
    xb=0; for k in A B C J CL T V U UL Q QL Z ZL ZT ZP ZU ZX BL; do xmllint --noout "$TMP/$k.out" 2>/dev/null || { xb=1; echo "    $k.out is not well-formed"; }; done
    if [ $xb -eq 0 ]; then ok "(L) A B C J and the full-legend answer parse as XML"; else no "(L) malformed answer"; fi
else
    echo "  SKIP  (L) xmllint absent"
fi

echo "(M) MCP path_between serves the CLI's pair rows"
python3 - "$BIN" "$TMP" <<'PY'
import json, re, subprocess, sys
binp, tmp = sys.argv[1], sys.argv[2]
cases = [ ( "two", "Run", "leaf" ), ( "hedge", "go", "target" ), ( "many", "go", "target" ), ( "join", "go", "target" ), ( "tw", "backspace", "edit" ), ( "qw", "Loop", "matcher.go:extendedMatch" ) ]
reqs = [ { "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "g", "version": "1" } } } ]
for i, ( d, a, b ) in enumerate( cases ):
    reqs.append( { "jsonrpc": "2.0", "id": i + 1, "method": "tools/call", "params": { "name": "path_between", "arguments": { "path": tmp + "/" + d, "from": a, "to": b } } } )
p = subprocess.run( [ binp, "--mcp", "--mcp-legend=inline" ], input = "".join( json.dumps( r ) + "\n" for r in reqs ), capture_output = True, text = True, timeout = 120 )
resp = {}
for line in p.stdout.splitlines():
    try:
        o = json.loads( line )
    except ValueError:
        continue
    if isinstance( o.get( "id" ), int ) and o[ "id" ] > 0:
        resp[ o[ "id" ] ] = "".join( c.get( "text", "" ) for c in o.get( "result", {} ).get( "content", [] ) )
bad = 0
rows = lambda x: re.findall( r'<pair [^>]*>|<alt [^>]*/>|<s [^>]*/>|</pair>', x )
for i, ( d, a, b ) in enumerate( cases ):
    mcp = resp.get( i + 1, "" )
    cli = open( "%s/%s.out" % ( tmp, { "two": "A", "hedge": "B", "many": "C", "join": "J", "tw": "Z", "qw": "Q" }[ d ] ) ).read()
    mr, cr = rows( mcp ), rows( cli )
    if not any( r.startswith( "<pair" ) for r in cr ):
        print( "  %s: CLI premise: no <pair> rows" % d ); bad = 1
    elif mr != cr:
        print( "  %s: MCP rows %r vs CLI %r" % ( d, mr[:4], cr[:4] ) ); bad = 1
    m = re.search( r'pairs_reaching="(\d+)"', mcp ); c = re.search( r'pairs_reaching="(\d+)"', cli )
    if not m or not c or m.group( 1 ) != c.group( 1 ):
        print( "  %s: pairs_reaching= differs MCP vs CLI" % d ); bad = 1
    for k in ( "from_test", "to_test", "next" ):   # ZM: the test-twin disclosure, both transports
        m = re.search( r'<path [^>]*\b%s="([^"]*)"' % k, mcp ); c = re.search( r'<path [^>]*\b%s="([^"]*)"' % k, cli )
        if ( m.group( 1 ) if m else None ) != ( c.group( 1 ) if c else None ):
            print( "  %s: root %s= differs MCP %r vs CLI %r" % ( d, k, m and m.group( 1 ), c and c.group( 1 ) ) ); bad = 1
sys.exit( bad )
PY
mrc=$?
if [ "$mrc" -eq 0 ]; then ok "(M) path_between pair rows, pairs_reaching=, from_test=/to_test=/next= equal the CLI's on A B C J Z Q"; else no "(M) MCP path_between disagrees with the CLI (rc=$mrc, details above)"; fi

if [ "$fail" -eq 0 ]; then echo "pathpaircheck: PASS"; exit 0; fi
echo "pathpaircheck: FAIL"; exit 1
