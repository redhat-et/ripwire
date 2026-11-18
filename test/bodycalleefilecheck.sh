#!/usr/bin/env bash
# bodycalleefilecheck.sh — BAND BC (docs/EVALS.md, amendment 12): a callee signature row under a served <b> body names its FILE.
#
# THE DEFECT. `<b p= l= n=>` bodies carry `<calls><c n= l=>sig</c>` rows (--expand, --pack-task, and any other verb serving bodies): the
# callee's definition LINE and no file. BAND CF fixed the same gap on the hop rows (<h><calls><c n= l=/>) with one helper,
# calleeRowPath; this arm of the surface reuses it and writes no second one.
#
# THE CONTRACT. A signature <c> prints p="<file>" when the callee is not in its <b> row's own file; a row with no p= is in the
# <b> row's file. The callee set, the row order, total=/shown= do not move. Truth is NOT the row: every (name, file, line) is read
# from --callees of the same body (another verb, another emitter) and then from the fixture's SOURCE TEXT.
#
# ARMS
#   (F) non-vacuity: the --callees truth of the fixture bodies holds a cross-file callee and a same-file callee.
#   (A) every cross-file signature row names its file, and it is the file --callees gives for that (name, line).
#   (E) no row prints its <b> row's own file; every same-file row has none.
#   (W) every row's (name, line) is spelled by the file the row resolves to (p=, else the <b> file).
#   (P) each served surface (--expand, --pack-task) printed at least one <c p=> row: the arms above measured something.
#   (L) the answer that prints a body <c p=> defines it in its own legend, and the dictionary has a row for it.
#   (B) under an explicit budget the rows that survive still obey (A)(E)(W).
#   (D) two runs are byte-identical and every answer parses as XML.
#
# Usage: test/bodycalleefilecheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "bodycalleefilecheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"

mkdir -p "$TMP/py/svc" "$TMP/py/store" "$TMP/py/auth" "$TMP/ts/src/ui" "$TMP/ts/src/app"
cat > "$TMP/py/svc/handler.py" <<'EOF'
# filler line 00: keeps this file larger than the bundle --expand would serve for its function
# filler line 01: keeps this file larger than the bundle --expand would serve for its function
# filler line 02: keeps this file larger than the bundle --expand would serve for its function
# filler line 03: keeps this file larger than the bundle --expand would serve for its function
# filler line 04: keeps this file larger than the bundle --expand would serve for its function
# filler line 05: keeps this file larger than the bundle --expand would serve for its function
# filler line 06: keeps this file larger than the bundle --expand would serve for its function
# filler line 07: keeps this file larger than the bundle --expand would serve for its function
# filler line 08: keeps this file larger than the bundle --expand would serve for its function
# filler line 09: keeps this file larger than the bundle --expand would serve for its function
# filler line 10: keeps this file larger than the bundle --expand would serve for its function
# filler line 11: keeps this file larger than the bundle --expand would serve for its function
# filler line 12: keeps this file larger than the bundle --expand would serve for its function
# filler line 13: keeps this file larger than the bundle --expand would serve for its function
# filler line 14: keeps this file larger than the bundle --expand would serve for its function
# filler line 15: keeps this file larger than the bundle --expand would serve for its function
# filler line 16: keeps this file larger than the bundle --expand would serve for its function
# filler line 17: keeps this file larger than the bundle --expand would serve for its function
# filler line 18: keeps this file larger than the bundle --expand would serve for its function
# filler line 19: keeps this file larger than the bundle --expand would serve for its function
# filler line 20: keeps this file larger than the bundle --expand would serve for its function
# filler line 21: keeps this file larger than the bundle --expand would serve for its function
# filler line 22: keeps this file larger than the bundle --expand would serve for its function
# filler line 23: keeps this file larger than the bundle --expand would serve for its function
# filler line 24: keeps this file larger than the bundle --expand would serve for its function
# filler line 25: keeps this file larger than the bundle --expand would serve for its function
# filler line 26: keeps this file larger than the bundle --expand would serve for its function
# filler line 27: keeps this file larger than the bundle --expand would serve for its function
# filler line 28: keeps this file larger than the bundle --expand would serve for its function
# filler line 29: keeps this file larger than the bundle --expand would serve for its function
# filler line 30: keeps this file larger than the bundle --expand would serve for its function
# filler line 31: keeps this file larger than the bundle --expand would serve for its function
# filler line 32: keeps this file larger than the bundle --expand would serve for its function
# filler line 33: keeps this file larger than the bundle --expand would serve for its function
# filler line 34: keeps this file larger than the bundle --expand would serve for its function
# filler line 35: keeps this file larger than the bundle --expand would serve for its function
# filler line 36: keeps this file larger than the bundle --expand would serve for its function
# filler line 37: keeps this file larger than the bundle --expand would serve for its function
# filler line 38: keeps this file larger than the bundle --expand would serve for its function
# filler line 39: keeps this file larger than the bundle --expand would serve for its function
from store.config import load_settings
from store.audit import record_event
from auth.backends import BaseBackend


class InlineView:
    def render(self, req):
        return req


def tidy_request(req):
    return req


def handle_request(req, backend, view):
    settings = load_settings(req)
    record_event(req)
    tidy_request(req)
    backend.authenticate(req)
    view.render(req)
    return settings
EOF
cat > "$TMP/py/store/config.py" <<'EOF'
# settings live here


def load_settings(req):
    return dict(req)
EOF
cat > "$TMP/py/store/audit.py" <<'EOF'
# audit trail
# kept small


LOG = []


def record_event(req):
    LOG.append(req)
EOF
cat > "$TMP/py/auth/backends.py" <<'EOF'
class BaseBackend:
    def authenticate(self, req):
        return None


class TokenBackend:
    # token check
    def authenticate(self, req):
        return req
EOF
cat > "$TMP/ts/src/ui/html.ts" <<'EOF'
export class HtmlView {
    // html
    render( req: string ): string {
        return "<p>" + req;
    }
}
EOF
cat > "$TMP/ts/src/ui/text.ts" <<'EOF'
// plain text view
//
//
//
//
export class TextView {
    // text
    //
    render( req: string ): string {
        return req;
    }
}
EOF
cat > "$TMP/ts/src/app/page.ts" <<'EOF'
// filler line 00: keeps this file larger than the bundle --expand would serve for its function
// filler line 01: keeps this file larger than the bundle --expand would serve for its function
// filler line 02: keeps this file larger than the bundle --expand would serve for its function
// filler line 03: keeps this file larger than the bundle --expand would serve for its function
// filler line 04: keeps this file larger than the bundle --expand would serve for its function
// filler line 05: keeps this file larger than the bundle --expand would serve for its function
// filler line 06: keeps this file larger than the bundle --expand would serve for its function
// filler line 07: keeps this file larger than the bundle --expand would serve for its function
// filler line 08: keeps this file larger than the bundle --expand would serve for its function
// filler line 09: keeps this file larger than the bundle --expand would serve for its function
// filler line 10: keeps this file larger than the bundle --expand would serve for its function
// filler line 11: keeps this file larger than the bundle --expand would serve for its function
// filler line 12: keeps this file larger than the bundle --expand would serve for its function
// filler line 13: keeps this file larger than the bundle --expand would serve for its function
// filler line 14: keeps this file larger than the bundle --expand would serve for its function
// filler line 15: keeps this file larger than the bundle --expand would serve for its function
// filler line 16: keeps this file larger than the bundle --expand would serve for its function
// filler line 17: keeps this file larger than the bundle --expand would serve for its function
// filler line 18: keeps this file larger than the bundle --expand would serve for its function
// filler line 19: keeps this file larger than the bundle --expand would serve for its function
// filler line 20: keeps this file larger than the bundle --expand would serve for its function
// filler line 21: keeps this file larger than the bundle --expand would serve for its function
// filler line 22: keeps this file larger than the bundle --expand would serve for its function
// filler line 23: keeps this file larger than the bundle --expand would serve for its function
// filler line 24: keeps this file larger than the bundle --expand would serve for its function
// filler line 25: keeps this file larger than the bundle --expand would serve for its function
// filler line 26: keeps this file larger than the bundle --expand would serve for its function
// filler line 27: keeps this file larger than the bundle --expand would serve for its function
// filler line 28: keeps this file larger than the bundle --expand would serve for its function
// filler line 29: keeps this file larger than the bundle --expand would serve for its function
// filler line 30: keeps this file larger than the bundle --expand would serve for its function
// filler line 31: keeps this file larger than the bundle --expand would serve for its function
// filler line 32: keeps this file larger than the bundle --expand would serve for its function
// filler line 33: keeps this file larger than the bundle --expand would serve for its function
// filler line 34: keeps this file larger than the bundle --expand would serve for its function
// filler line 35: keeps this file larger than the bundle --expand would serve for its function
// filler line 36: keeps this file larger than the bundle --expand would serve for its function
// filler line 37: keeps this file larger than the bundle --expand would serve for its function
// filler line 38: keeps this file larger than the bundle --expand would serve for its function
// filler line 39: keeps this file larger than the bundle --expand would serve for its function
import { HtmlView } from "../ui/html";
import { TextView } from "../ui/text";

export function paintPage( req: string ): string {
    const h: HtmlView = new HtmlView();
    const t: TextView = new TextView();
    return h.render( req ) + t.render( req );
}
EOF

python3 - "$BIN" "$TMP" <<'PY'
import sys, re, subprocess, html, os

binp, tmp = sys.argv[1], sys.argv[2]
fails = 0
def ok( m ): print( "  ok    " + m )
def no( m ):
    global fails
    fails += 1
    print( "  FAIL  " + m )

def run( d, *args ):
    p = subprocess.run( [ binp, ".", "--no-cache", *args ], cwd = d, capture_output = True, text = True, timeout = 120 )
    return p.returncode, p.stdout, p.stderr

def attrs( tag ):
    return { k: html.unescape( v ) for k, v in re.findall( r' ([a-z_]+)="([^"]*)"', tag ) }

def leaf( n ):
    return re.split( r'::|\.', n )[ -1 ]

def spelled( d, f, line, name ):
    try:
        src = open( os.path.join( d, f ), encoding = "utf-8" ).read().split( "\n" )
    except OSError:
        return False
    return any( re.search( r'(?<![A-Za-z0-9_])' + re.escape( name ) + r'(?![A-Za-z0-9_])', s ) for s in src[ line - 1 : line + 3 ] )

def strip( xml ):
    return re.sub( r'<!--.*?-->', '', xml, flags = re.S )

def bodies_of( xml ):
    """[( b attrs, [ c attrs ] )]: a served body and its SIGNATURE callee rows (<c ...>sig</c>), legend comments removed"""
    out = []
    for bm in re.finditer( r'<b( [^>]*)><!\[CDATA\[.*?\]\]>(.*?)</b>', strip( xml ), flags = re.S ):
        cm = re.search( r'<calls[^>]*>(.*?)</calls>', bm.group( 2 ), flags = re.S )
        if cm:
            out.append( ( attrs( bm.group( 1 ) ), [ attrs( c ) for c in re.findall( r'<c( [^>]*)>[^<]*</c>', cm.group( 1 ) ) ] ) )
    return out

def truth_of( d, bfile, bline ):
    rc, out, err = run( d, "--callees=@%s:%s" % ( bfile, bline ), "--legend=dict", "--limit=400" )
    if rc != 0 or "<callees " not in out:
        return None
    t = {}
    for s in re.findall( r'<s( [^>]*?)/>', out ):
        a = attrs( s )
        f, _, l = a[ "p" ].rpartition( ":" )
        t.setdefault( ( leaf( a[ "n" ] ), int( l ) ), set() ).add( f )
    return t

shape = { "cross": 0, "same": 0 }
def check( tag, d, xml ):
    """arms (A) (E) (W) over every body of one answer; returns the number of p= rows"""
    bs = bodies_of( xml )
    if not bs:
        no( "%s no <b> body with <calls> — every arm below measured nothing" % tag )
        return 0
    npr = 0
    nrows = 0
    for b, rows in bs:
        owner = "%s:%s %s" % ( b[ "p" ], b[ "l" ], b[ "n" ] )
        truth = truth_of( d, b[ "p" ], b[ "l" ] )
        if truth is None:
            no( "%s --callees of %s did not answer — no truth to hold the rows to" % ( tag, owner ) )
            continue
        for c in rows:
            nrows += 1
            f = c.get( "p", b[ "p" ] )
            if "p" in c:
                npr += 1
            if "p" in c and c[ "p" ] == b[ "p" ]:
                no( "%s (E) %s: row %s prints its <b> row's own file" % ( tag, owner, c ) )
            files = truth.get( ( c[ "n" ], int( c[ "l" ] ) ) )
            if files is None:
                no( "%s (A) %s: row %s is no --callees row of the body" % ( tag, owner, c ) )
                continue
            if f not in files:
                no( "%s (A) %s: row %s resolves to %s, --callees says %s" % ( tag, owner, c, f, sorted( files ) ) )
            if f != b[ "p" ]:
                shape[ "cross" ] += 1
                if "p" not in c:
                    no( "%s (A) %s: cross-file callee %s has no p=" % ( tag, owner, c ) )
            else:
                shape[ "same" ] += 1
            if not spelled( d, f, int( c[ "l" ] ), c[ "n" ] ):
                no( "%s (W) %s: row %s — %s:%s does not spell %s" % ( tag, owner, c, f, c[ "l" ], c[ "n" ] ) )
    if nrows == 0:
        no( "%s no signature <c> row at all — (A)(E)(W) measured nothing" % tag )
    return npr

py, ts = tmp + "/py", tmp + "/ts"
QPY = "how does handle request load settings then authenticate and render the view"
QTS = "how does paint page render the html view and the text view"
surfaces = [
    ( "[py expand]", py, [ "--expand=handle_request" ] ),
    ( "[ts expand]", ts, [ "--expand=paintPage" ] ),
    ( "[py pack-task]", py, [ "--pack-task=" + QPY ] ),
    ( "[ts pack-task]", ts, [ "--pack-task=" + QTS ] ),
]
answers = {}
f0 = fails
for tag, d, args in surfaces:
    rc, out, err = run( d, *args )
    if rc != 0:
        no( "%s rc=%d" % ( tag, rc ) )
        continue
    answers[ tag ] = ( d, args, out )
    n = check( tag, d, out )
    if n == 0:
        no( "(P) %s printed no <c p=> row: the cross-file arm saw nothing" % tag )
if fails == f0:
    ok( "(A)(E)(W)(P) every body callee row names the file its line is in; same-file rows carry none, on --expand and --pack-task" )
if shape[ "cross" ] == 0 or shape[ "same" ] == 0:
    no( "(F) the fixture no longer holds a cross-file and a same-file callee: %s" % shape )
else:
    ok( "(F) fixture shapes present: %s" % shape )

# (L) the row is defined where it is printed, and the dictionary has it
fl = fails
for tag, ( d, args, out ) in answers.items():
    if "<c " not in strip( out ) or re.search( r'<c [^>]* p="', strip( out ) ) is None:
        continue
    legend = " ".join( re.findall( r'<!--(.*?)-->', out, flags = re.S ) )
    if not re.search( r'c n= l= p=|c p=', legend ):
        no( "(L) %s prints a body <c p=> row and its own legend never defines it" % tag )
    rc2, outc, _e = run( d, *args, "--legend=compact" )
    lc = " ".join( re.findall( r'<!--(.*?)-->', outc, flags = re.S ) )
    if not re.search( r'c n= l= p=|c p=', lc ):
        no( "(L) %s: the compact legend never defines the body <c p=>" % tag )
dp = subprocess.run( [ binp, "--legend-dict" ], capture_output = True, text = True, timeout = 120 )
if dp.returncode != 0 or not dp.stdout.strip():
    no( "(L) the legend dictionary did not print (rc=%d)" % dp.returncode )
if fails == fl:
    ok( "(L) every answer that prints a body <c p=> defines it, full and compact" )

# (B) explicit budgets
fb = fails
nb = 0
for budget in ( "1500", "3000", "6000" ):
    rcb, ab, errb = run( ts, "--pack-task=" + QTS, "--token-budget=" + budget )
    if rcb == 0 and bodies_of( ab ):
        nb += 1
        check( "[ts pack-task budget %s]" % budget, ts, ab )
if nb == 0:
    no( "(B) no budgeted answer carried a body with <calls> — the arm measured nothing" )
elif fails == fb:
    ok( "(B) %d budgeted answers obey (A)(E)(W)" % nb )

# (D) determinism and well-formedness
fd = fails
for tag, ( d, args, first ) in answers.items():
    rcx, again, _e = run( d, *args )
    if again != first:
        no( "(D) two runs differ: " + tag )
    x = subprocess.run( [ "xmllint", "--noout", "-" ], input = first, capture_output = True, text = True )
    if x.returncode != 0:
        no( "(D) not well-formed: " + tag + " — " + x.stderr[ :200 ] )
if fails == fd:
    ok( "(D) byte-identical twice, well-formed" )

print( "bodycalleefilecheck: %s" % ( "PASS" if fails == 0 else "%d FAIL" % fails ) )
sys.exit( 1 if fails else 0 )
PY
rc=$?
fail=0
if [ "$rc" -ne 0 ]; then
    printf '  FAIL  the arm harness exited %s (an arm failed above, or the harness crashed)\n' "$rc"
    fail=1
fi
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
