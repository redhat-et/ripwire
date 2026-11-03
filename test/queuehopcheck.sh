#!/usr/bin/env bash
# queuehopcheck.sh — QUEUE-HOP (src/backhops.h QueueHops, src/pathgaps.h BridgeVia::Queue): a producer that puts onto a queue
# field of its own object hands off to the function that takes from it, and both hedged walks follow that hand-off.
#
# THE DEFECT. A message pump (textual's MessagePump: post_message -> self._message_queue.put_nowait(m); _process_messages_loop
# -> self._get_message() -> self._message_queue.get(); then _dispatch_message) has no call edge from the producer to the
# consumer: --path=post_message,_dispatch_message found no path and no bridge, and --impact of the consumer named no producer.
#
# THE CONTRACT. A put site `self.X.put( v )` / `self.X.put_nowait( v )` (one positional argument) pairs with a get site
# `self.X.get()` / `self.X.get_nowait()` (none) of the SAME attribute in the same class or a base/subclass of it (never a
# sibling, never another class of the same spelling). The readers are the function holding the get and its proven callers in
# that family (one level). Every queue hop is HEDGED: reaches= / reachable= / hops= / proven= never move. The --impact ring
# lists a queue hop as a d=1 row (`<rh … via="queue" … d="1" cands=K/>`), counts it, and composes it like any hop within 16
# producers; the --path bridge crosses it (`<s … via="queue" cands=K/>`).
# A user `put( k, v )` / `get( k )` (a cache, a dict), a queue handed to a worker as an argument, and a local alias are no hop.
# Floor (disclosed in the changelog): Python only; a call with any keyword other than timeout= / block= is read as no queue operation.
# This is its own gate (not composedhopscheck): a hand-off is a new FAMILY of hop with its own pairing rule (attribute +
# class family + arity) and its own negatives; the walks it rides are composedhopscheck's and unchanged.
#
# ARMS
#   (Q1) same class: --impact=_get lists Pump.post via="queue" d="1" cands="2" (readers _get and loop); reaches= unchanged.
#   (Q2) bridge: --path=post,handle crosses post -> loop via="queue", then proven loop -> dispatch -> handle; reachable="0".
#   (Q3) subclass producer: Child.poke (Child(Pump)) is a producer of Pump's queue; base producer into subclass reader too.
#   (N1) another class with the same attribute spelling (Other._q.put) is no producer of Pump._q.
#   (N2) a sibling class (Left(Base) puts, Right(Base) gets, X not in Base) is no pair.
#   (N3) a user put(k, v) / get(k) (Cache) is no queue: no hop, no reaches_hedged.
#   (N4) escape: a queue passed to a worker function as an argument — the worker is no reader; a local alias put is no producer.
#   (W1) width: 16 producers compose their 16 proven callers (32); 17 are counted (17) but compose nothing.
#   (T1) a reader that re-puts onto its own queue terminates, and is not its own producer.
#   (T2) the same with 16 producers: the sink's own put is no hop, so the 16 compose (reaches_hedged=32); it widens to 17 and composes
#        nothing if the self-exclusion is dropped (mutant: delete `&& m_sites[ p.put ].fn != sink` in QueueHops::backHops).
#   (N5) the class family is the RESOLVED class (graph.h's Proven base edges: a same-file declaration or an import), never the base
#        name across files: an unrelated same-named Base in another file is no hop; a subclass through a proven import is.
#   (K1-K3) timeout= / block= are the queue signature's own keywords (no argument); any other keyword, a second positional argument
#        or a *args / **kw list is no queue operation.
#   (J1) JSON twin spells via/d/cands; (M1) MCP impact + path_between twins equal the CLI; (L1) the queue clause rides only
#        when a queue row is present and the answers parse as XML.
#
# Usage: test/queuehopcheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "queuehopcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/pump" "$TMP/sib" "$TMP/cache" "$TMP/esc" "$TMP/w16" "$TMP/w17" "$TMP/req" "$TMP/ns" "$TMP/nsimp" "$TMP/m4" "$TMP/kw2" "$TMP/kw3" "$TMP/kwo"
cat > "$TMP/pump/pump.py" <<'EOF'
import queue


def handle(m):
    return m


class Pump:
    def __init__(self):
        self._q = queue.Queue()

    def post(self, m):
        self._q.put_nowait(m)

    def push_alias(self, m):
        q = self._q
        q.put(m)

    def _get(self):
        return self._q.get()

    def loop(self):
        while True:
            m = self._get()
            self.dispatch(m)

    def dispatch(self, m):
        handle(m)


class Child(Pump):
    def poke(self):
        self._q.put(2)


class Other:
    def __init__(self):
        self._q = queue.Queue()

    def send(self, m):
        self._q.put(m)


def main():
    p = Pump()
    p.post(1)
EOF
cat > "$TMP/sib/sib.py" <<'EOF'
import queue


class Base:
    def __init__(self):
        self.ready = True


class Left(Base):
    def give(self, m):
        self._inbox.put(m)


class Right(Base):
    def take(self):
        return self._inbox.get()
EOF
cat > "$TMP/cache/cache.py" <<'EOF'
class Cache:
    def store(self, k, v):
        self._d.put(k, v)

    def fetch(self, k):
        return self._d.get(k)
EOF
cat > "$TMP/esc/esc.py" <<'EOF'
import queue
import threading


def worker(q):
    item = q.get()
    return item


class Esc:
    def __init__(self):
        self._q = queue.Queue()

    def start(self):
        threading.Thread(target=worker, args=(self._q,)).start()

    def push(self, m):
        self._q.put(m)
EOF
for n in 16 17; do
    {
        printf 'import queue\n\n\nclass Hub:\n    def __init__(self):\n        self._q = queue.Queue()\n\n    def drain(self):\n        return self._q.get()\n'
        for i in $( seq 1 "$n" ); do printf '\n    def p%s(self):\n        self._q.put(%s)\n' "$i" "$i"; done
        for i in $( seq 1 "$n" ); do printf '\n\ndef c%s(h):\n    h.p%s()\n' "$i" "$i"; done
    } > "$TMP/w$n/hub.py"
done
cat > "$TMP/req/req.py" <<'EOF'
import queue


class Loop:
    def __init__(self):
        self._r = queue.Queue()

    def feed(self, m):
        self._r.put(m)

    def requeue(self):
        m = self._r.get()
        self._r.put(m)
EOF

# (N5) an unrelated same-named Base in another file: X(Base).produce puts, the OTHER Base.consume gets — two classes, no hop.
cat > "$TMP/ns/a.py" <<'EOF'
class Base:
    pass


class X(Base):
    def produce(self, v):
        self.q.put(v)
EOF
cat > "$TMP/ns/b.py" <<'EOF'
class Base:
    def consume(self):
        return self.q.get()
EOF
# (N5) …and the real cross-file subclass: Sub(Base) imports Base from a.py, so it IS a subclass of the Base that reads.
cat > "$TMP/nsimp/a.py" <<'EOF'
class Base:
    def consume(self):
        return self.q.get()
EOF
cat > "$TMP/nsimp/b.py" <<'EOF'
from a import Base


class Sub(Base):
    def produce(self, v):
        self.q.put(v)
EOF
cat > "$TMP/nsimp/c.py" <<'EOF'
class Base:
    pass


class Lone(Base):
    def produce2(self, v):
        self.q.put(v)
EOF
# (T2) the self-exclusion: 16 producers with one proven caller each, and a reader that re-puts. The reader's own put is no way in
# (QueueHops::backHops drops the sink's own put), so the producer hop stays 16 wide and composes its 16 callers: reaches_hedged=32.
{
    printf 'class P:\n'
    for i in $( seq 1 16 ); do printf '    def p%s(self, v):\n        self.q.put(v)\n' "$i"; done
    printf '    def r(self):\n        m = self.q.get()\n        self.q.put(m)\n'
    for i in $( seq 1 16 ); do printf 'def c%s(o):\n    o.p%s(1)\n' "$i" "$i"; done
} > "$TMP/m4/m.py"
# (K) keyword arguments: timeout= / block= are the queue signature's own, so they are no argument; any other keyword is no queue op.
cat > "$TMP/kw2/m.py" <<'EOF'
class P:
    def a(self, v):
        self.q.put(v)

    def r(self):
        return self.q.get(timeout=2)

    def r2(self):
        return self.q.get(block=False)

    def r3(self):
        return self.q.get_nowait()
EOF
cat > "$TMP/kw3/m.py" <<'EOF'
class P:
    def a(self, v):
        self.q.put(v, timeout=1)

    def b(self, v):
        self.q.put(v, block=False)

    def c(self, v):
        self.q.put_nowait(v)

    def r(self):
        return self.q.get()
EOF
cat > "$TMP/kwo/m.py" <<'EOF'
class P:
    def a(self, v):
        self.q.put(v, priority=1)

    def b(self, v):
        self.q.put(item=v)

    def c(self, *v):
        self.q.put(*v)

    def d(self, v):
        self.q.put(v, True)

    def r(self):
        return self.q.get(default=0)

    def r2(self):
        return self.q.get(True)

    def r3(self):
        return self.q.get(timeout=1, default=0)


class Q:
    def a(self, v):
        self.q.put(v)

    def r(self):
        return self.q.get(**opts)
EOF

python3 - "$BIN" "$TMP" <<'PY'
import json, re, shutil, subprocess, sys
binp, tmp = sys.argv[1], sys.argv[2]
fail = 0
def ok( m ): print( "  PASS  " + m )
def no( m ):
    global fail
    fail = 1
    print( "  FAIL  " + m )
def run( d, *args ):
    """One answer, read only off a run that succeeded and printed a root (checklist 14)."""
    p = subprocess.run( [ binp, d, "--no-cache", *args ], cwd = d, capture_output = True, text = True, timeout = 120 )
    if p.returncode != 0 or not re.search( r'<(path|impact) |^\{"', p.stdout ):
        return None
    return p.stdout
def body( t ):
    return re.sub( r'<!--.*?-->', '', t or "", flags = re.S )
def root( t, tag ):
    m = re.search( r'<' + tag + r' [^>]*>', body( t ) )
    return m.group( 0 ) if m else ""
def bridge( t ):
    m = re.search( r'<bridge .*?</bridge>', body( t ) )
    return m.group( 0 ) if m else ""
def ring( t ):
    m = re.search( r'<ring .*?</ring>', body( t ) )
    return m.group( 0 ) if m else ""
def rows( t ):
    return re.findall( r'<rh [^>]*/>', ring( t ) )
def attr( el, name ):
    m = re.search( r'\s' + name + r'="([^"]*)"', el or "" )
    return m.group( 1 ) if m else None
def check( label, cond, detail = "" ):
    ( ok if cond else no )( label + ( "" if cond else " — " + detail ) )
def qrow( t, by, calls ):
    """The queue d=1 row whose called_by ends in `by` and whose calls= ends in `calls`, or ""."""
    for r in rows( t ):
        if attr( r, "via" ) == "queue" and ( attr( r, "called_by" ) or "" ).split( "." )[ -1 ] == by and ( attr( r, "calls" ) or "" ).split( "." )[ -1 ] == calls:
            return r
    return ""
P = tmp + "/pump"

# ── Q: the hand-off ─────────────────────────────────────────────────────────────────────────────────────────────────
t1 = run( P, "--impact=_get" ); r1 = root( t1, "impact" ); q1 = qrow( t1, "post", "_get" )
check( "(Q1) --impact=_get lists post as a queue hop: via=\"queue\" d=\"1\" cands=\"2\" (readers _get + loop)",
       q1 != "" and attr( q1, "d" ) == "1" and attr( q1, "cands" ) == "2" and ( attr( q1, "called_at" ) or "" ).endswith( "pump.py:13" ), repr( ring( t1 ) or r1 )[:500] )
check( "(Q1) reaches= is the proven count alone (loop, 1); the hand-off is reaches_hedged=",
       attr( r1, "reaches" ) == "1" and int( attr( r1, "reaches_hedged" ) or 0 ) >= 3, r1[:300] )
t1b = run( P, "--impact=loop" ); q1b = qrow( t1b, "post", "loop" )
check( "(Q1) the reader's same-class caller (loop) is a reader too: --impact=loop lists post via=queue", q1b != "", repr( ring( t1b ) )[:400] )
t2 = run( P, "--path=post,handle" ); r2 = root( t2, "path" ); b2 = bridge( t2 )
check( "(Q2) --path=post,handle: a hedged bridge post -> loop via=\"queue\" -> dispatch -> handle, crossings=1, reachable=0",
       attr( r2, "reachable" ) == "0" and attr( b2, "proven" ) == "0" and attr( b2, "crossings" ) == "1"
       and re.search( r'<s [^>]*n="[^"]*loop"[^>]*via="queue" cands="2"', b2 ) is not None and re.search( r'n="[^"]*handle"', b2 ) is not None, repr( b2 or r2 )[:500] )
check( "(Q3) a subclass producer (Child.poke) puts onto the base class's queue: a hop into _get", qrow( t1, "poke", "_get" ) != "", repr( ring( t1 ) )[:400] )

# ── N: what is not a hand-off ───────────────────────────────────────────────────────────────────────────────────────
check( "(N1) another class's same-spelled attribute (Other.send -> Other._q) is no producer of Pump._q", qrow( t1, "send", "_get" ) == "", repr( ring( t1 ) )[:400] )
check( "(N4) a put through a local alias (q = self._q; q.put) is no producer", qrow( t1, "push_alias", "_get" ) == "", repr( ring( t1 ) )[:400] )
t3 = run( tmp + "/sib", "--impact=take" ); r3 = root( t3, "impact" )
check( "(N2) a sibling class's put (Left.give) is no producer for Right.take: no queue row, no reaches_hedged",
       r3 != "" and qrow( t3, "give", "take" ) == "" and attr( r3, "reaches_hedged" ) is None, r3[:300] )
t4 = run( tmp + "/cache", "--impact=fetch" ); r4 = root( t4, "impact" )
check( "(N3) a user put(k, v) / get(k) is no queue: no hop, no reaches_hedged", r4 != "" and attr( r4, "reaches_hedged" ) is None and ring( t4 ) == "", r4[:300] )
t5 = run( tmp + "/esc", "--impact=worker" ); r5 = root( t5, "impact" )
check( "(N4) a queue handed to a worker as an argument: the worker is no reader (no queue row)", r5 != "" and 'via="queue"' not in body( t5 ), r5[:300] )

# ── W: width ────────────────────────────────────────────────────────────────────────────────────────────────────────
t6 = run( tmp + "/w16", "--impact=drain" ); r6 = root( t6, "impact" )
check( "(W1) 16 producers compose: reaches_hedged=32 (16 producers + their 16 proven callers)", attr( r6, "reaches_hedged" ) == "32", r6[:300] )
t7 = run( tmp + "/w17", "--impact=drain" ); r7 = root( t7, "impact" )
check( "(W1) 17 producers are counted but compose nothing: reaches_hedged=17", attr( r7, "reaches_hedged" ) == "17", r7[:300] )
check( "(W1) the d=1 rows are capped at 16 shown with total=17, next= present",
       attr( ring( t7 ), "total" ) == "17" and attr( ring( t7 ), "shown" ) == "16"
       and ( attr( ring( t7 ), "next" ) == "--callers=Hub.drain" or ( attr( ring( t7 ), "next" ) or "" ).endswith( "drain" ) ), ring( t7 )[:200] )

# ── T: recursion ────────────────────────────────────────────────────────────────────────────────────────────────────
t8 = run( tmp + "/req", "--impact=requeue" ); r8 = root( t8, "impact" )
check( "(T1) a reader that re-puts onto its own queue terminates; feed is its one producer, itself is not",
       r8 != "" and qrow( t8, "feed", "requeue" ) != "" and qrow( t8, "requeue", "requeue" ) == "" and attr( r8, "reaches_hedged" ) == "1", r8[:300] )

# ── N5 / T2 / K: the family is the resolved class; the self-exclusion; keyword arguments ──────────────────────────────
t9 = run( tmp + "/ns", "--impact=consume" ); r9 = root( t9, "impact" )
check( "(N5) an unrelated same-named Base in another file is no family: --impact=consume has no queue row, no reaches_hedged",
       r9 != "" and qrow( t9, "produce", "consume" ) == "" and attr( r9, "reaches_hedged" ) is None, repr( ring( t9 ) or r9 )[:400] )
t10 = run( tmp + "/nsimp", "--impact=consume" ); r10 = root( t10, "impact" )
check( "(N5) a real cross-file subclass through a proven import (Sub(Base) with `from a import Base`) is a producer: a queue row produce -> consume",
       qrow( t10, "produce", "consume" ) != "", repr( ring( t10 ) or r10 )[:400] )
check( "(N5) …but Lone(Base) in c.py, whose Base is its own file's, is no producer of a.py's Base queue",
       qrow( t10, "produce2", "consume" ) == "", repr( ring( t10 ) )[:400] )
t11 = run( tmp + "/m4", "--impact=r" ); r11 = root( t11, "impact" )
check( "(T2) 16 producers and a re-putting reader: the sink's own put is not a hop, so the 16 compose: reaches_hedged=32 and no row called_by r",
       attr( r11, "reaches_hedged" ) == "32" and not any( ( attr( x, "called_by" ) or "" ).split( "." )[ -1 ] == "r" for x in rows( t11 ) ), r11[:300] )
t12 = run( tmp + "/kw2", "--impact=r" ); r12 = root( t12, "impact" )
check( "(K1) put( v ) + get( timeout=2 ): a hop a -> r (and a -> r2 for get( block=False ), a -> r3 for get_nowait())",
       qrow( t12, "a", "r" ) != "" and qrow( run( tmp + "/kw2", "--impact=r2" ), "a", "r2" ) != "" and qrow( run( tmp + "/kw2", "--impact=r3" ), "a", "r3" ) != "", repr( ring( t12 ) or r12 )[:400] )
t13 = run( tmp + "/kw3", "--impact=r" ); r13 = root( t13, "impact" )
check( "(K2) put( v, timeout=1 ), put( v, block=False ) and put_nowait( v ) + get(): all three produce a hop into r",
       all( qrow( t13, n, "r" ) != "" for n in ( "a", "b", "c" ) ) and attr( r13, "reaches_hedged" ) == "3", repr( ring( t13 ) or r13 )[:400] )
ro = [ run( tmp + "/kwo", "--impact=" + n ) for n in ( "r", "r2", "r3" ) ] + [ run( tmp + "/kwo", "--impact=Q.r" ) ]
check( "(K3) any OTHER keyword (priority=, item=, default=), a positional second argument, a *args/**opts list: no queue hop",
       all( t is not None and 'via="queue"' not in body( t ) and attr( root( t, "impact" ), "reaches_hedged" ) is None for t in ro ), repr( [ ring( t ) for t in ro ] )[:500] )

# ── J / M / L: twins and legends ────────────────────────────────────────────────────────────────────────────────────
tj = run( P, "--impact=_get", "--json" ) or "{}"
try:
    j = json.loads( tj )
except ValueError:
    j = {}
jrows = [ r for r in j.get( "ring", {} ).get( "rows", [] ) if r.get( "via" ) == "queue" and r.get( "called_by", "" ).split( "." )[ -1 ] == "post" ]
check( "(J1) the JSON twin spells via/d/cands with the XML names (d:1, cands:2) and no XML spelling",
       len( jrows ) == 1 and jrows[ 0 ].get( "d" ) == 1 and jrows[ 0 ].get( "cands" ) == 2 and 'cands="' not in tj, repr( tj[:400] ) )
reqs = [ { "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "g", "version": "1" } } },
         { "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": { "name": "impact", "arguments": { "path": P, "symbol": "_get" } } },
         { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "path_between", "arguments": { "path": P, "from": "post", "to": "handle" } } } ]
p = subprocess.run( [ binp, "--mcp", "--mcp-legend=inline" ], input = "".join( json.dumps( x ) + "\n" for x in reqs ), capture_output = True, text = True, timeout = 120 )
resp = {}
for line in p.stdout.splitlines():
    try:
        o = json.loads( line )
    except ValueError:
        continue
    if isinstance( o.get( "id" ), int ) and o[ "id" ] > 0:
        resp[ o[ "id" ] ] = "".join( c.get( "text", "" ) for c in o.get( "result", {} ).get( "content", [] ) )
check( "(M1) MCP impact: the same <ring> with the queue row as the CLI", ring( resp.get( 1, "" ) ) != "" and ring( resp.get( 1, "" ) ) == ring( t1 ), repr( resp.get( 1, "" )[-300:] ) )
check( "(M1) MCP path_between: the same queue <bridge> as the CLI", bridge( resp.get( 2, "" ) ) != "" and bridge( resp.get( 2, "" ) ) == bridge( t2 ), repr( resp.get( 2, "" )[-300:] ) )
imf = run( P, "--impact=_get", "--legend=full" ) or ""; pf = run( P, "--path=post,handle", "--legend=full" ) or ""
check( "(L1) the queue clause rides on a queue ring and a queue bridge (full legend)", "HAND-OFF" in imf and "HAND-OFF" in pf, imf[:200] )
check( "(L1) a queue-only <ring d=1> is defined: the full legend says what the root d=1 means (CodeRabbit 4387143955)",
       attr( ring( imf ), "d" ) == "1" and "<ring d=1" in imf and "only queue hand-offs" in imf, ring( imf )[:200] )
check( "(L1) the queue clause is present-only: an answer with no queue row lacks it", run( tmp + "/cache", "--impact=fetch", "--legend=full" ) is not None
       and "HAND-OFF" not in ( run( tmp + "/cache", "--impact=fetch", "--legend=full" ) or "" ), "" )
if shutil.which( "xmllint" ):
    for label, doc in ( ( "impact full", imf ), ( "path full", pf ) ):
        x = subprocess.run( [ "xmllint", "--noout", "-" ], input = doc, capture_output = True, text = True )
        check( "(L1) the %s answer with the queue clause parses as XML (checklist 25)" % label, x.returncode == 0 and doc != "", x.stderr[:300] )
else:
    print( "  SKIP  (L1) xmllint not installed: the well-formedness arm needs it" )
sys.exit( fail )
PY
rc=$?   # the harness's own status, read immediately (checklist 14): 0 every arm passed, 1 an arm failed, anything else a crash
fail=0
if [ "$rc" -ne 0 ]; then
    printf '  FAIL  the arm harness exited %s (an arm failed above, or the harness crashed)\n' "$rc"
    fail=1
fi
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
