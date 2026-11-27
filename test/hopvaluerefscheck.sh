#!/usr/bin/env bash
# hopvaluerefscheck.sh — a --for hop row says "this function is bound as a value; a call through that slot is not an edge".
#
# THE GAP. `<hops>` prints a ranked function as <h l= p= n=> and its callees. A function that is only ever stored or passed
# (a handler table, a registered callback) has no caller edge, so its hop row reads exactly like one whose callers are all
# resolved. `--callers` already says value_refs=N for it; the hop row did not. Call edges are name-based, so a callback or a
# slot call can be missing; a reader cannot tell "no caller exists" from "the caller is a slot the graph cannot follow".
#
# THE CONTRACT (the three tokens, never collapsed).
#   VALUE        <h … value_refs="N">  the row's function is used as a value N times (what --callers=SYM counts as value_refs=N).
#   ABSENT       no value_refs= on the row: NONE FOUND for a language whose value uses are read — never "none exist".
#   UNREAD       <hops … value_refs_unread_for_lang="java"> : a printed row is in a language that reads no value use at all,
#                so its absence of value_refs= is unknown, not zero. (lego's implementors_unread_for_lang= is the precedent.)
#   The callee set, the row order, total=, shown=, noedge= and capped= do not move.
#
# TRUTH IS NOT THE ROW. The expected N is read from `--callers=SYM` (another verb, another emitter) on the same fixture.
#
# ARMS
#   (F) non-vacuity: the truth verb reports value_refs>=1 for on_timer_tick and on_connection_close, none for plain_connection_check;
#       the answer prints an <h> row for each of the three.
#   (A) a bound function's <h> row carries value_refs= equal to the truth verb's count.
#   (E) an unbound function's <h> row carries NO value_refs=; and no row of a C-only answer says unread.
#   (U) a mixed answer whose printed rows include a Java method carries value_refs_unread_for_lang="java" on <hops>, the Java row
#       carries no value_refs=, and no C row is named in the unread list.
#   (T) total=, shown=, capped=, noedge= and the <c> rows of every <h> are exactly the base binary's (RIPWIRE_BASE_BIN, when set).
#   (L) an answer that prints value_refs= or the unread attribute defines it in a comment; one that prints neither carries neither.
#   (D) two runs are byte-identical and every answer parses as XML.
#
# Usage: test/hopvaluerefscheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
# θ5 (src/forpages.h): this gate reads the FULL page-1 legend of a default --for answer (or pins its bytes/rows); the default's
# core legend is pinned by test/corelegendcheck.sh, so the full legend is switched back on here.
export RIPWIRE_NO_CORE_LEGEND=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "hopvaluerefscheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"

mkdir -p "$TMP/fx/c" "$TMP/fx/j" "$TMP/cfx/c" "$TMP/nfx"
cat > "$TMP/fx/c/events.c" <<'EOF'
#include "events.h"

static void note_event(int code)
{
    record_event(code);
}

void on_connection_open(int fd)
{
    note_event(fd);
    flush_queue(fd);
}

void on_connection_close(int fd)
{
    note_event(fd);
    flush_queue(fd);
}

void plain_connection_check(int fd)
{
    note_event(fd);
    flush_queue(fd);
}

static const struct event_ops connection_handlers = {
    .open = on_connection_open,
    .close = on_connection_close,
};

void dispatch_connection_event(int which, int fd)
{
    if( which == 0 )
    {
        connection_handlers.open(fd);
    }
    else
    {
        connection_handlers.close(fd);
    }
}
EOF
cat > "$TMP/fx/c/events.h" <<'EOF'
struct event_ops
{
    void (*open)(int);
    void (*close)(int);
};
void record_event(int code);
void flush_queue(int fd);
EOF
cat > "$TMP/fx/c/queue.c" <<'EOF'
#include "events.h"

void record_event(int code)
{
    (void)code;
}

void flush_queue(int fd)
{
    record_event(fd);
}
EOF
cat > "$TMP/fx/c/timer.c" <<'EOF'
#include "events.h"

void register_callback(void (*cb)(int));

void on_timer_tick(int fd)
{
    record_event(fd);
    flush_queue(fd);
}

void start_timer(void)
{
    register_callback(on_timer_tick);
}
EOF
cat > "$TMP/fx/j/Hub.java" <<'EOF'
public class Hub
{
    void onConnectionOpen(int fd)
    {
        noteEvent(fd);
        flushQueue(fd);
    }

    void noteEvent(int code)
    {
        flushQueue(code);
    }

    void flushQueue(int fd)
    {
    }
}
EOF
cp "$TMP/fx/c/"* "$TMP/cfx/c/"
# a corpus where nothing is stored or passed as a value: every function is only ever called
cp "$TMP/fx/c/queue.c" "$TMP/fx/c/events.h" "$TMP/nfx/"
cat > "$TMP/nfx/plain.c" <<'EOF'
#include "events.h"

void plain_connection_check(int fd)
{
    record_event(fd);
    flush_queue(fd);
}
EOF

python3 - "$BIN" "$TMP" "${RIPWIRE_BASE_BIN:-}" <<'PY'
import sys, re, subprocess, html, os
import xml.dom.minidom as minidom

binp, tmp, basebin = sys.argv[1], sys.argv[2], sys.argv[3]
fails = 0
def ok( m ): print( "  ok    " + m )
def no( m ):
    global fails
    fails += 1
    print( "  FAIL  " + m )

def run( b, d, *args ):
    p = subprocess.run( [ b, ".", "--no-cache", *args ], cwd = d, capture_output = True, text = True, timeout = 120 )
    return p.returncode, p.stdout

def attrs( tag ):
    return { k: html.unescape( v ) for k, v in re.findall( r' ([a-z_]+)="([^"]*)"', tag ) }

def strip( xml ):
    return re.sub( r'<!--.*?-->', '', xml, flags = re.S )

def hops_of( xml ):
    """( <hops> attrs, [ ( h attrs, raw inner ) ] ), comments removed first: the legend spells row schemas in prose"""
    body = strip( xml )
    m = re.search( r'<hops( [^>]*)>(.*?)</hops>', body, flags = re.S )
    if not m:
        return {}, []
    return attrs( m.group( 1 ) ), [ ( attrs( h.group( 1 ) ), h.group( 2 ) ) for h in re.finditer( r'<h( [^>]*)>(.*?)</h>', m.group( 2 ), flags = re.S ) ]

def truth( d, name ):
    rc, out = run( binp, d, "--callers=" + name, "--legend=dict" )
    m = re.search( r'<callers [^>]*?\bvalue_refs="(\d+)"', out )
    return int( m.group( 1 ) ) if m else 0

fx  = os.path.join( tmp, "fx" )
cfx = os.path.join( tmp, "cfx" )
QC = "how are connection open and close events and the timer tick dispatched to handlers, and what does plain connection check do"
QJ = "how does the Hub connection open handler note events and flush the queue, and what does plain connection check do"

rc, c1 = run( binp, fx, "--for=" + QC )
rc2, c2 = run( binp, fx, "--for=" + QC )
rcj, j1 = run( binp, fx, "--for=" + QJ )
rcc, k1 = run( binp, cfx, "--for=" + QC )

# (D)
if rc == 0 and c1 == c2 and "<ctx " in c1:
    ok( "(D) two runs are byte-identical" )
else:
    no( "(D) two runs differ or the answer is missing (rc=%d)" % rc )
for tag, x in ( ( "C+Java", c1 ), ( "Java", j1 ), ( "C-only", k1 ) ):
    try:
        minidom.parseString( x )
    except Exception as e:
        no( "(D) the %s answer is not well-formed XML: %s" % ( tag, e ) )
    else:
        ok( "(D) the %s answer parses as XML" % tag )

hops, rows = hops_of( c1 )
by = { h.get( "n" ): h for h, _ in rows }

# (F)
tb = { n: truth( fx, n ) for n in ( "on_timer_tick", "on_connection_close", "plain_connection_check" ) }
if tb[ "on_timer_tick" ] >= 1 and tb[ "on_connection_close" ] >= 1 and tb[ "plain_connection_check" ] == 0:
    ok( "(F) --callers truth: on_timer_tick=%d on_connection_close=%d plain_connection_check=0" % ( tb[ "on_timer_tick" ], tb[ "on_connection_close" ] ) )
else:
    no( "(F) the fixture lost a shape: truth %r" % tb )
missing = [ n for n in tb if n not in by ]
if missing:
    no( "(F) no <h> row for %s — the arms below measure nothing" % ", ".join( missing ) )
else:
    ok( "(F) the answer prints an <h> row for all three" )

# (A) (E)
for n in ( "on_timer_tick", "on_connection_close" ):
    h = by.get( n )
    if h is None:
        continue
    got = h.get( "value_refs" )
    if got is not None and int( got ) == tb[ n ]:
        ok( "(A) <h %s> value_refs=%s equals --callers" % ( n, got ) )
    else:
        no( "(A) <h %s> value_refs=%r, --callers says %d" % ( n, got, tb[ n ] ) )
h = by.get( "plain_connection_check" )
if h is not None:
    if "value_refs" in h:
        no( "(E) the unbound plain_connection_check row claims value_refs=%s" % h[ "value_refs" ] )
    else:
        ok( "(E) the unbound row carries no value_refs=" )
khops, krows = hops_of( k1 )
if not krows:
    no( "(E) the C-only answer has no <h> row — the arm measured nothing" )
elif "value_refs_unread_for_lang" in khops:
    no( "(E) a C-only answer says unread: %s" % khops[ "value_refs_unread_for_lang" ] )
else:
    ok( "(E) a C-only answer names no unread language" )

# (U)
jh, jr = hops_of( j1 )
hub = [ h for h, _ in jr if h.get( "p", "" ).endswith( ".java" ) ]
if not hub:
    no( "(U) no Java <h> row — the arm measured nothing" )
else:
    langs = jh.get( "value_refs_unread_for_lang", "" ).split( "," )
    if "java" not in langs:
        no( "(U) a Java row is printed and <hops> says value_refs_unread_for_lang=%r" % jh.get( "value_refs_unread_for_lang" ) )
    elif any( l not in ( "java", ) for l in langs ):
        no( "(U) the unread list names a language this build reads: %r" % langs )
    else:
        ok( "(U) value_refs_unread_for_lang=\"java\" on <hops>, no armed language named" )
    if any( "value_refs" in h for h in hub ):
        no( "(U) a Java row prints value_refs=: this build reads none for Java" )
    else:
        ok( "(U) the Java row prints no value_refs= (unknown, not zero)" )

# (T)
if basebin:
    for tag, d, q in ( ( "C+Java", fx, QC ), ( "Java", fx, QJ ) ):
        _, new = run( binp, d, "--for=" + q )
        _, old = run( basebin, d, "--for=" + q )
        nh, nr = hops_of( new )
        oh, orow = hops_of( old )
        keys = ( "total", "shown", "capped", "noedge" )
        same = all( nh.get( k ) == oh.get( k ) for k in keys ) and [ ( a.get( "n" ), re.sub( r' value_refs="\d+"', '', b ) ) for a, b in nr ] == [ ( a.get( "n" ), b ) for a, b in orow ]
        if same:
            ok( "(T) %s: total/shown/capped/noedge and every <calls> body equal the base" % tag )
        else:
            no( "(T) %s: the hop section moved beyond the new attributes" % tag )
else:
    ok( "(T) skipped: no RIPWIRE_BASE_BIN" )

# (L)
def clause_present( x ):
    return bool( re.search( r'<!--[^>]*value_refs[^>]*-->', x, flags = re.S ) )
for tag, x, want in ( ( "C+Java", c1, True ), ( "Java", j1, True ), ( "C-only no bound row", None, False ) ):
    if x is None:
        continue
    printed = bool( re.search( r'<h [^>]*value_refs=', strip( x ) ) ) or "value_refs_unread_for_lang" in strip( x )
    if printed and not clause_present( x ):
        no( "(L) the %s answer prints a value_refs attribute and defines it nowhere" % tag )
    elif not printed and clause_present( x ):
        no( "(L) the %s answer carries the clause with no attribute to define" % tag )
    else:
        ok( "(L) %s: the clause rides exactly when an attribute does" % tag )
# a question whose hop rows bind nothing and carry no Java
rc3, n1 = run( binp, os.path.join( tmp, "nfx" ), "--for=what does plain connection check do and how does flush queue record an event" )
if "<hops" in n1 and "value_refs" not in strip( n1 ) and not clause_present( n1 ):
    ok( "(L) an answer with no bound row carries neither the attribute nor the clause" )
elif "<hops" not in n1:
    no( "(L) the no-bound-row question printed no <hops> — the arm measured nothing" )
else:
    no( "(L) an answer with no bound row carries value_refs or its clause" )

print( "hopvaluerefscheck: %s" % ( "PASS" if fails == 0 else "%d FAIL" % fails ) )
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
