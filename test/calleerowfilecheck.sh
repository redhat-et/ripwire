#!/usr/bin/env bash
# calleerowfilecheck.sh — BAND CF (docs/EVALS.md, amendment 11b): a --for hop-callee row names the FILE its line is in.
#
# THE DEFECT. `<hops>` listed a ranked symbol as <h l= p= n=> and each callee as <c n= l=/>: the callee's definition LINE and
# no file, so the row could not be opened, and nothing said so. The same edge on --callees prints p="file:line".
# And the row merged same-named callees by NAME alone, so one l= joined lines of different files (`<c n="render" l="3,9"/>`
# for html.ts:3 and text.ts:9) — unlocatable then, and WRONG the moment a single file is printed beside it.
#
# THE CONTRACT. A <c> row inside <hops> prints p="<file>" when the callee is not in its <h> row's own file; a row with no p=
# is in the <h> row's file. Same-named callees merge only within one file, so every line of one l= is a line of that row's
# file. The callee set, the row order, total= and shown= do not move. A via="name" row keeps via="name"; its p= is the file
# of the definition whose line it already printed.
#
# TRUTH IS NOT THE ROW. The expected (name, file, line) set is read from --callees of the same owner (another verb, another
# emitter), and every file:line of both is then checked against the fixture's SOURCE TEXT: the line must spell the name.
#
# ARMS
#   (F) non-vacuity, tracking the fixture: the truth set holds a cross-file callee, a same-file callee, a by-name pair in one
#       OTHER file, and one name defined in TWO other files; every truth row is spelled by its source line. A fixture edit that
#       loses one of these shapes fails here, not silently in the arms below.
#   (A) every cross-file callee has a row with its name, p= its file, and its line in l=.          (mutant M3: no p= at all)
#   (E) every same-file callee has a row with NO p=; no row prints its <h> row's own file.          (mutant M4: p= everywhere)
#   (W) THE READER'S ARM: every line of every <c> row is spelled by the file the row names.         (mutants M1, M2)
#   (C) the rows are the truth set, no more and no fewer, when the listing is not cut; shown= counts callees.
#   (O) the owner-row path (<h … qword=>) obeys the same rules.
#   (L) the answer that prints a <c p=> row defines it in its own legend, and so does the dictionary. (mutant M5)
#   (B) under an explicit budget the rows that survive still obey (W), and shown= still counts them. The path bytes are
#       charged, so a tight budget can drop the hop section sooner than it did; that cut is disclosed (capped=1 next=).
#   (D) two runs are byte-identical and every answer parses as XML.
#   (M) the MCP `for` twin is the signatures-only surface: it prints no <hops>, so it has no such row to get wrong. If it
#       ever gains one this arm fails and the twin must be gated here.
#
# Usage: test/calleerowfilecheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "calleerowfilecheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"

mkdir -p "$TMP/py/svc" "$TMP/py/store" "$TMP/py/auth" "$TMP/ts/src/ui" "$TMP/ts/src/app"
cat > "$TMP/py/svc/handler.py" <<'EOF'
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
import { HtmlView } from "../ui/html";
import { TextView } from "../ui/text";

export function paintPage( req: string ): string {
    const h: HtmlView = new HtmlView();
    const t: TextView = new TextView();
    return h.render( req ) + t.render( req );
}
EOF

python3 - "$BIN" "$TMP" <<'PY'
import sys, re, json, subprocess, html, os

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

def hops_of( xml ):
    """[( h attrs, calls attrs, [ c attrs ] )] of the <hops> section, legend comments removed"""
    body = re.sub( r'<!--.*?-->', '', xml, flags = re.S )
    m = re.search( r'<hops[^>]*>(.*?)</hops>', body, flags = re.S )
    out = []
    if not m:
        return out
    for hm in re.finditer( r'<h( [^>]*)>(.*?)</h>', m.group( 1 ), flags = re.S ):
        cm = re.search( r'<calls( [^>]*)>', hm.group( 2 ) )
        out.append( ( attrs( hm.group( 1 ) ), attrs( cm.group( 1 ) ) if cm else {}, [ attrs( c ) for c in re.findall( r'<c( [^>]*?)/>', hm.group( 2 ) ) ] ) )
    return out

def truth_of( d, hfile, hline ):
    """{ ( leaf name, file, line ) : via } from --callees of the owner: another verb, another emitter"""
    rc, out, err = run( d, "--callees=@%s:%s" % ( hfile, hline ), "--legend=dict", "--limit=400" )
    t = {}
    if rc != 0 or "<callees " not in out:
        return None
    for s in re.findall( r'<s( [^>]*?)/>', out ):
        a = attrs( s )
        f, _, l = a[ "p" ].rpartition( ":" )
        t[ ( leaf( a[ "n" ] ), f, int( l ) ) ] = a.get( "via", "" )
    return t

def check( tag, d, xml, want_complete = True ):
    """arms (A) (E) (W) (C) over every <h> row of one answer; returns the truth sets it read, by owner"""
    hs = hops_of( xml )
    if not hs:
        no( "%s no <h> row in the answer — every arm below measured nothing" % tag )
        return {}
    truths = {}
    nrows = nlines = 0
    for h, calls, rows in hs:
        owner = "%s:%s %s" % ( h[ "p" ], h[ "l" ], h[ "n" ] )
        truth = truth_of( d, h[ "p" ], h[ "l" ] )
        if truth is None:
            no( "%s --callees of %s did not answer — no truth to hold the rows to" % ( tag, owner ) )
            continue
        truths[ owner ] = ( h, truth )
        got = set()
        for c in rows:
            nrows += 1
            f = c.get( "p", h[ "p" ] )
            if "p" in c and c[ "p" ] == h[ "p" ]:
                no( "%s (E) %s: row %s prints its <h> row's own file" % ( tag, owner, c ) )
            for l in c[ "l" ].split( "," ):
                nlines += 1
                got.add( ( c[ "n" ], f, int( l ) ) )
                if not spelled( d, f, int( l ), c[ "n" ] ):
                    no( "%s (W) %s: row %s — %s:%s does not spell %s: a file the tool did not resolve for that line" % ( tag, owner, c, f, l, c[ "n" ] ) )
        cut = "capped" in calls
        for ( n, f, l ), via in sorted( truth.items() ):
            if ( n, f, l ) in got:
                continue
            if cut:
                continue                      # a disclosed cut may drop a callee; (C) below still refuses an invented one
            if f != h[ "p" ]:
                no( "%s (A) %s: cross-file callee %s at %s:%s has no row naming that file" % ( tag, owner, n, f, l ) )
            else:
                no( "%s (E) %s: same-file callee %s at line %s has no p=-less row" % ( tag, owner, n, l ) )
        extra = got - set( truth )
        if extra:
            no( "%s (C) %s: rows --callees does not list: %s" % ( tag, owner, sorted( extra ) ) )
        if want_complete and cut:
            no( "%s (C) %s: the listing is cut (%s) on a fixture it should fit whole" % ( tag, owner, calls ) )
        shown = int( calls.get( "shown", calls.get( "total", "-1" ) ) )
        if shown != len( got ):
            no( "%s (C) %s: shown/total says %d callees, the rows list %d" % ( tag, owner, shown, len( got ) ) )
    if nrows == 0:
        no( "%s no <c> row at all — (W) measured nothing" % tag )
    return truths

py, ts = tmp + "/py", tmp + "/ts"
QPY = "how does handle request load settings then authenticate and render the view"
QTS = "how does paint page render the html view and the text view"
QOWN = "where does the page get its render output when paintpage runs for a view"

rc, apy, err = run( py, "--for=" + QPY )
rc2, ats, err2 = run( ts, "--for=" + QTS )
rc3, aown, err3 = run( ts, "--for=" + QOWN )
if rc != 0 or rc2 != 0 or rc3 != 0 or "<hops" not in apy or "<hops" not in ats or "<hops" not in aown:
    no( "a fixture answer did not run or carries no <hops>: rc=%d,%d,%d" % ( rc, rc2, rc3 ) )
    sys.exit( 1 )

f0 = fails
tpy = check( "[py]", py, apy )
tts = check( "[ts]", ts, ats )
town = check( "[ts owner]", ts, aown )
if fails == f0:
    ok( "(A)(E)(W)(C) every hop-callee row names the file its line is in; same-file rows carry none; rows = the --callees set" )

# (F) the truth tracks the fixture: the shapes the arms above depend on are present, and the source spells every truth row
shape = { "cross": 0, "same": 0, "byname_pair_one_other_file": 0, "one_name_two_other_files": 0 }
for d, truths in ( ( py, tpy ), ( ts, tts ) ):
    for owner, ( h, truth ) in truths.items():
        byname = {}
        files_of = {}
        for ( n, f, l ), via in truth.items():
            if not spelled( d, f, l, n ):
                no( "(F) truth row %s %s:%s is not spelled by the fixture source — the fixture or --callees drifted" % ( n, f, l ) )
            shape[ "cross" if f != h[ "p" ] else "same" ] += 1
            if f != h[ "p" ]:
                files_of.setdefault( n, set() ).add( f )
                if via == "name":
                    byname.setdefault( ( n, f ), [] ).append( l )
        shape[ "byname_pair_one_other_file" ] += sum( 1 for v in byname.values() if len( v ) >= 2 )
        shape[ "one_name_two_other_files" ] += sum( 1 for v in files_of.values() if len( v ) >= 2 )
missing = [ k for k, v in shape.items() if v == 0 ]
if missing:
    no( "(F) the fixture no longer holds: %s — the arms above pass on nothing for it (shapes: %s)" % ( ", ".join( missing ), shape ) )
else:
    ok( "(F) fixture shapes present and source-spelled: %s" % shape )

# (O) the owner-row path
if any( "qword" in h for h, _c, _r in hops_of( aown ) ):
    ok( "(O) an <h … qword=> owner row was served and held to the same arms" )
else:
    no( "(O) the owner query served no qword= row — the owner path was not measured" )

# (L) the row is defined where it is printed
legend = " ".join( re.findall( r'<!--(.*?)-->', ats, flags = re.S ) )
if re.search( r'<c [^>]* p="', re.sub( r'<!--.*?-->', '', ats, flags = re.S ) ) is None:
    no( "(L) the ts answer prints no <c p=> row — nothing for the legend to define" )
elif "c p=" not in legend and "c n= l= p=" not in legend:   # the full dialect's spelling, the compact one's
    no( "(L) the answer prints a <c p=> row and its own legend never defines c p=" )
else:
    ok( "(L) the answer's legend defines c p=" )
dp = subprocess.run( [ binp, "--legend-dict" ], capture_output = True, text = True, timeout = 120 )
if dp.returncode != 0 or not dp.stdout.strip():
    no( "(L) the legend dictionary did not print (rc=%d)" % dp.returncode )
elif re.search( r'c p=[^\n]*hop|hop[^\n]*c p=|h row[^\n]*c p=|c p=[^\n]*h row', dp.stdout ) is None:
    no( "(L) the legend dictionary has no row for the hop callee's p=" )
else:
    ok( "(L) the dictionary defines the hop callee's p=" )

# (B) an explicit budget: what survives still obeys, and a cut is disclosed with a count that matches
nb = 0
fb = fails
for budget in ( "1200", "2500", "6000" ):
    rcb, ab, errb = run( ts, "--for=" + QTS, "--token-budget=" + budget )
    if rcb != 0:
        no( "(B) --token-budget=%s rc=%d" % ( budget, rcb ) )
        continue
    if hops_of( ab ):
        nb += 1
        check( "[ts budget %s]" % budget, ts, ab, want_complete = False )
if nb == 0:
    no( "(B) no budgeted answer carried an <h> row — the arm measured nothing" )
elif fails == fb:
    ok( "(B) %d budgeted answers with hop rows obey (W)/(C)" % nb )

# (D) determinism and well-formedness
fd = fails
for d, q, first in ( ( py, QPY, apy ), ( ts, QTS, ats ), ( ts, QOWN, aown ) ):
    rcx, again, _e = run( d, "--for=" + q )
    if again != first:
        no( "(D) two runs differ for: " + q )
    x = subprocess.run( [ "xmllint", "--noout", "-" ], input = first, capture_output = True, text = True )
    if x.returncode != 0:
        no( "(D) not well-formed: " + q + " — " + x.stderr[ :200 ] )
if fails == fd:
    ok( "(D) byte-identical twice, well-formed" )

# (M) the MCP twin
req = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n' + json.dumps( { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "for", "arguments": { "task": QTS } } } ) + "\n"
mp = subprocess.run( [ binp, "--mcp", ts, "--no-cache" ], cwd = ts, input = req, capture_output = True, text = True, timeout = 120 )
text = ""
for line in mp.stdout.split( "\n" ):
    try:
        j = json.loads( line )
    except ValueError:
        continue
    if j.get( "id" ) == 2 and "result" in j:
        text = j[ "result" ][ "content" ][ 0 ][ "text" ]
if "<ctx " not in text:
    no( "(M) the MCP for twin did not answer — the arm measured nothing" )
elif "<hops" in text:
    f2 = fails
    check( "[mcp]", ts, text )
    if fails == f2:
        ok( "(M) the MCP for twin prints <hops> and its rows obey the same arms" )
else:
    ok( "(M) the MCP for twin is the signatures-only surface: no <hops>, no hop-callee row" )

print( "calleerowfilecheck: %s" % ( "PASS" if fails == 0 else "%d FAIL" % fails ) )
sys.exit( 1 if fails else 0 )
PY
rc=$?   # the harness's own status, read immediately: 0 every arm passed, 1 an arm failed, anything else a crash
fail=0
if [ "$rc" -ne 0 ]; then
    printf '  FAIL  the arm harness exited %s (an arm failed above, or the harness crashed)\n' "$rc"
    fail=1
fi
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
