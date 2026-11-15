#!/usr/bin/env bash
# nextaposcheck.sh — NEXT-APOS-RAW (2026-11-15): a next= hint pastes into a shell as written.
#
# nextAttrXml (src/nextverb.h) writes every next= / *_next= attribute double-quoted, and nextFlag quotes a value a
# shell would split with apostrophes. The escaper used to turn those apostrophes into &apos;, so a hint copied out of
# a raw answer (a captured document, a terminal, anything not decoded by an XML parser) handed the shell
# `--for=&apos;x y&apos;`: a literal entity, and an `&` that backgrounds the command. Inside a "-delimited
# attribute a raw `'` is legal XML, so the escaper now leaves it raw; `"`, `&`, `<` and `>` stay escaped.
#
#   (a) a --for / --grep hint that carries a quoted argument prints a raw ' and no &apos; (RIPWIRE_BASE_BIN, when
#       set, must print &apos; on the same calls: the red side)
#   (b) every next-family value, read by an XML parser, equals the raw text between its quotes once the four kept
#       entities are decoded — XML readers see the same value as before; every output is well-formed
#   (c) every next-family hint that starts with `--`, pasted RAW into bash, runs with rc=0 and a non-empty answer
#   (d) calls whose hints carry no quote: no ' and no &apos; in any hint; with RIPWIRE_BASE_BIN, stdout, stderr and
#       rc are byte-identical to it, and the quote-carrying calls differ from it ONLY by &apos; -> ' inside
#       next-family attributes (and grep's <suggest> --for=&quot;PAT&quot; -> nextFlag's --for='PAT'), plus an
#       est_tokens= that may fall (it prices the emitted bytes) and never rises
#   (e) EVERY next= EMITTER (NEXT-APOS-FINISH: one escaper, nextverb.h appendNextValueXml): one call per emitter that
#       used to write its value through serialize.h escapeXml — the dead-code filter hint, the file page, value refs
#       (<vrs> and a slot <vs>), the body cut (<b truncated>), a cut <calls> listing, the owner hop cut (<hops>),
#       declined sites (dc_next=), defs (to_next=), the fold <skip>, the skipped body slot (<bodies>), grep's zero-hit
#       <suggest> — each must print its hint, with no &apos; in it, and the hint must RUN: rc=0 and a non-empty answer.
#       Pasted RAW into bash when the value carries no entity; the hints that must carry one (a `"` the attribute
#       cannot hold raw — the file page's --graph-query literals — or a `>` in a slot's `->` regex) run as an XML
#       reader decodes them, counted apart and named. Quote-carrying fixtures (a path with a space, a phrase) make the
#       dead-code, declined-site, body-slot and suggest hints print a raw '; with RIPWIRE_BASE_BIN those same calls
#       must spell the quote as an entity there (&apos;, or grep's &quot;: the red side).
# Every arm counts its premise and FAILS on zero.
#
# grep's <suggest> used to spell its shell quoting with `"`, which this "-delimited attribute can only hold as &quot;:
# it is now nextFlag's apostrophes (`--for='total area computation'`; a one-word pattern bare), so it pastes too.
#
# Usage:  bash test/nextaposcheck.sh [BIN]      (or RIPWIRE_BIN=…; optional RIPWIRE_BASE_BIN=<main binary>)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
BASE="${RIPWIRE_BASE_BIN:-}"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found"; exit 2; }
if [ -n "$BASE" ]; then [ -x "$BASE" ] || { echo "RIPWIRE_BASE_BIN=$BASE is not executable"; exit 2; }; fi
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/home"; cp -R "$ROOT/test/fixture"/. "$TMP/repo"/

RW_TEST_DIR="$ROOT/test" python3 - "$BIN" "$BASE" "$TMP/repo" "$TMP/home" <<'PY'
import os, re, subprocess, sys
import xml.parsers.expat
binp, base, repo, home = sys.argv[1:5]
env = { k: v for k, v in os.environ.items() if not k.startswith( "RIPWIRE_" ) }
env.update( HOME = home, TMPDIR = home + "/" )
fail = 0
def ok( m ): print( "  PASS  " + m )
def no( m ):
    global fail; fail = 1; print( "  FAIL  " + m )
def verdict( cond, good, bad ):
    if cond: ok( good )
    else: no( bad )

# quote-carrying calls (Q): each has at least one hint nextFlag quotes; no-quote calls (N): none does
Q = [ [ "--for=how is the triangle area computed" ], [ "--for=it's the perimeter" ], [ "--grep=total area" ] ]
N = [ [ "--for=area" ], [ "--callers=distance" ], [ "--impact=distance" ] ]

def run( b, argv ):
    p = subprocess.run( [ b, ".", "--no-cache" ] + argv, cwd = repo, env = env, capture_output = True, stdin = subprocess.DEVNULL )
    return p.stdout, p.stderr, p.returncode

NEXT = re.compile( r"^[a-z_]*next$" )
def hints( out ):
    """(element, attr, parsed value, raw value) for every next-family attribute, raw read from the start tag's bytes."""
    rows = []; p = xml.parsers.expat.ParserCreate( "UTF-8" )
    def start( tag, attrs ):
        off = p.CurrentByteIndex; end = out.index( b">", off ); raw = out[ off:end ].decode( "utf-8" )
        for k, v in attrs.items():
            if NEXT.match( k ):
                m = re.search( r"\s" + re.escape( k ) + r'="([^"]*)"', raw )
                rows.append( ( tag, k, v, m.group( 1 ) if m else None ) )
    p.StartElementHandler = start; p.ordered_attributes = False
    p.Parse( out, True )
    return rows

def unesc( s ):
    s = re.sub( r"&#(\d+);", lambda m: chr( int( m.group( 1 ) ) ), s )
    return s.replace( "&quot;", '"' ).replace( "&lt;", "<" ).replace( "&gt;", ">" ).replace( "&apos;", "'" ).replace( "&amp;", "&" )

lane = { tuple( a ): run( binp, a ) for a in Q + N }
parsed = {}
for a, ( o, e, rc ) in lane.items():
    if rc != 0 or not o.strip(): no( f"setup: {list( a )} rc={rc} bytes={len( o )}" ); continue
    try: parsed[ a ] = hints( o )
    except Exception as ex: no( f"(b) {list( a )} output is not well-formed XML: {ex}" ); parsed[ a ] = []

# (a) raw ' in quote-carrying hints, no &apos; anywhere in a next-family value
na = 0
for a in map( tuple, Q ):
    for tag, k, v, raw in parsed.get( a, [] ):
        if raw is None: no( f"(a) {list( a )} <{tag} {k}=> has no raw text" ); continue
        if "&apos;" in raw: no( f"(a) {list( a )} <{tag} {k}=\"{raw}\"> still escapes the apostrophe" )
        elif "'" in raw: na += 1
verdict( na, f"(a) {na} quote-carrying hints print a raw ' and none prints &apos;", "(a) premise: no hint carried a quote (0 counted)" )
if base:
    nb = sum( run( base, list( a ) )[ 0 ].count( b"&apos;" ) for a in map( tuple, Q ) )
    verdict( nb, f"(a) base binary prints &apos; {nb}x on the same calls (the red side)", "(a) premise: the base binary printed no &apos; on the quote-carrying calls" )
else:
    print( "  SKIP  (a) base side: RIPWIRE_BASE_BIN unset" )

# (b) XML value == raw text decoded, on every next-family attribute of every output
nb = nq = 0
for a, rows in parsed.items():
    for tag, k, v, raw in rows:
        nb += 1; nq += "'" in v
        if raw is None or unesc( raw ) != v: no( f"(b) {list( a )} <{tag} {k}=>: parsed {v!r} != raw {raw!r}" )
verdict( ( nb and nq ), f"(b) {nb} next-family values parse to their raw text ({nq} carry a ')", f"(b) premise: {nb} values, {nq} with a quote" )

# (c) each `--` hint pasted RAW into bash runs: rc 0, non-empty answer
seen = set(); nc = ncq = 0
for a, rows in parsed.items():
    for tag, k, v, raw in rows:
        if raw is None or not raw.startswith( "--" ) or raw in seen: continue
        seen.add( raw )
        if "&" in raw: no( f"(c) <{tag} {k}=\"{raw}\"> carries an entity: a shell cannot paste it" ); continue
        p = subprocess.run( [ "bash", "-c", f'"$RWBIN" . --no-cache {raw}' ], cwd = repo, env = dict( env, RWBIN = binp ),
                            capture_output = True, stdin = subprocess.DEVNULL )
        nc += 1; ncq += "'" in raw
        if p.returncode != 0 or not p.stdout.strip(): no( f"(c) pasted `{raw}`: rc={p.returncode} bytes={len( p.stdout )} {p.stderr[:200]!r}" )
verdict( ( nc and ncq ), f"(c) {nc} distinct hints pasted raw into bash ran rc=0 with an answer ({ncq} quoted)", f"(c) premise: {nc} hints run, {ncq} quoted" )

# (d) no-quote calls: no ' / &apos; in any hint; with a base binary, byte-identical, and Q differs only by the entity
nd = 0
for a in map( tuple, N ):
    for tag, k, v, raw in parsed.get( a, [] ):
        nd += 1
        if raw is None or "'" in raw or "&apos;" in raw: no( f"(d) {list( a )} <{tag} {k}=\"{raw}\"> carries a quote" )
verdict( nd, f"(d) {nd} hints on the no-quote calls carry neither ' nor &apos;", "(d) premise: the no-quote calls printed no hint" )
if base:
    same = 0
    for a in map( tuple, N ):
        if run( base, list( a ) ) == lane[ a ]: same += 1
        else: no( f"(d) {list( a )} differs from the base binary (stdout, stderr or rc)" )
    verdict( same, f"(d) {same}/{len( N )} no-quote calls byte-identical to the base binary (stdout+stderr+rc)", "(d) premise: 0 no-quote calls compared" )
    attr = re.compile( rb'( [a-z_]*next=")([^"]*)(")' ); est = re.compile( rb' est_tokens="(\d+)"' )
    sugg = re.compile( rb' next="--for=&quot;([^"&]*)&quot;"' )
    nq = 0
    for a in map( tuple, Q ):
        bo, be, brc = run( base, list( a ) ); lo, le, lrc = lane[ a ]
        fixed = attr.sub( lambda m: m.group( 1 ) + m.group( 2 ).replace( b"&apos;", b"'" ) + m.group( 3 ), bo )
        # grep's zero-hit <suggest>: --for=&quot;PAT&quot; became nextFlag's spelling (a word-like PAT: quoted only with a space)
        fixed = sugg.sub( lambda m: b' next="--for=' + ( b"'" + m.group( 1 ) + b"'" if b" " in m.group( 1 ) else m.group( 1 ) ) + b'"', fixed )
        # est_tokens= prices the emitted bytes, so 5 fewer bytes an entity may lower it: masked here, and it must not RISE
        bt, lt = [ [ int( x ) for x in est.findall( o ) ] for o in ( bo, lo ) ]
        if est.sub( b"", fixed ) == est.sub( b"", lo ) and ( be, brc ) == ( le, lrc ) and bo != lo and len( bt ) == len( lt ) and all( y <= x for x, y in zip( bt, lt ) ):
            nq += 1
        else: no( f"(d) {list( a )}: the base answer with &apos; -> ' in next-family values (est_tokens= masked, lane <= base) is not the lane answer" )
    verdict( nq, f"(d) {nq}/{len( Q )} quote-carrying calls differ from base ONLY by &apos; -> ' inside next-family values (grep's <suggest> &quot; -> nextFlag's quoting; an est_tokens= that fell)",
             "(d) premise: 0 quote-carrying calls compared" )
else:
    print( "  SKIP  (d) base byte-identity: RIPWIRE_BASE_BIN unset" )
# (e) every next= emitter: its hint prints (no &apos;), and runs — raw when it carries no entity, else as an XML reader decodes it
fx = os.path.join( os.path.dirname( repo ), "fx" ); T = os.environ[ "RW_TEST_DIR" ]
def w( rel, text ):
    os.makedirs( os.path.dirname( os.path.join( fx, rel ) ), exist_ok = True ); open( os.path.join( fx, rel ), "w" ).write( text )
w( "dead/pkg/util.py", "def really_dead():\n    return 1\ndef live_fn():\n    return 2\n" )
w( "dead/main.py", "from pkg.util import live_fn\ndef main():\n    live_fn()\n" )
w( "vr/big.c", "\n".join( [ "static int hot(int x) { return x; }", "static int (*many[])(int) = {" ] + [ "    hot," ] * 300
                          + [ "};", "int use_many(int i) { return many[i](i); }" ] ) + "\n" )
w( "slot/s.c", "\n".join( [ "struct ops { int (*run)(int); };" ] + [ "static int h%d(int x) { return x + %d; }" % ( k, k ) for k in range( 20 ) ]
                          + [ "static struct ops o%d = { h%d };" % ( k, k ) for k in range( 20 ) ] + [ "int drive(struct ops *p, int x) { return p->run(x); }" ] ) + "\n" )
w( "slotd/s.c", "\n".join( [ "struct ops { int (*run)(int); };" ] + [ "static int h%d(int x) { return x + %d; }" % ( k, k ) for k in range( 20 ) ]
                           + [ "static struct ops o%d = { .run = h%d };" % ( k, k ) for k in range( 20 ) ] + [ "int drive(struct ops *p, int x) { return p->run(x); }" ] ) + "\n" )
w( "dc/alpha dir/a.py", "class A:\n    def poll(self):\n        return 1\n" )
w( "dc/beta/b.py", "class B:\n    def poll(self):\n        return 2\n" )
for f in range( 3 ):
    w( "dc/callers/f%d.py" % f, "".join( "def use_%d_%d(x):\n    return x.poll()\n\n\n" % ( f, k ) for k in range( 12 ) ) )
w( "dc/big/big.py", "def big(x):\n" + "".join( "    x.poll()\n" for _ in range( 40 ) ) + "    return x\n" )
w( "alias/alias.h", "namespace lib { struct Real { void run(); }; }\nusing RealAlias = lib::Real;\n" )
import shutil
shutil.copytree( os.path.join( T, "forbodyslotfix" ), os.path.join( fx, "slotspc" ) )
os.rename( os.path.join( fx, "slotspc/src/middleware/jwt" ), os.path.join( fx, "slotspc/src/middleware/j wt" ) )
# (emitter, root, argv, element, attr, a ' must print raw)
E = [ ( "dead-code filter",   fx + "/dead",   [ "--dead-code=pkg/util.py" ],                                   "dead-code",  "next",    True ),
      ( "file page",          fx + "/dead",   [ "--for=pkg/util.py" ],                                         "named-file", "next",    True ),
      ( "value refs <vrs>",   fx + "/vr",     [ "--callers=hot" ],                                             "vrs",        "next",    False ),
      ( "slot <vs> (uses)",   fx + "/slot",   [ "--callees=drive" ],                                           "vs",         "next",    False ),
      ( "slot <vs> (regex)",  fx + "/slotd",  [ "--callees=drive" ],                                           "vs",         "next",    True ),
      ( "body cut <b>",       T + "/forbodyslotfix", [ "--for=How does render_screen draw the screen?" ],      "b",          "next",    False ),
      ( "cut <calls>",        T + "/forbodyfoldfix/web", [ "--for=How is a request dispatched?" ],             "calls",      "next",    False ),
      ( "owner hop cut",      T + "/ownerhopfix/py", [ "--for=How do invoke_watcher, schedule_refresh, record_signal and notify work?" ], "hops", "next", False ),
      ( "declined dc_next",   fx + "/dc",     [ "--callers=alpha dir/a.py:poll" ],                             "callers",    "dc_next", True ),
      ( "defs to_next",       fx + "/alias",  [ "--defs=RealAlias" ],                                          "d",          "to_next", False ),
      ( "fold <skip>",        T + "/forbodyfoldfix/web", [ "--for=How does the application send the response body to the client?" ], "skip", "next", False ),
      ( "body slot <bodies>", fx + "/slotspc", [ "--for=How does the JWT middleware verify a token?", "--token-budget=400" ], "bodies", "next", True ),
      ( "grep <suggest>",     repo,           [ "--grep=total area computation" ],                             "suggest",    "next",    True ) ]
def runat( b, root, argv ):
    p = subprocess.run( [ b, ".", "--no-cache" ] + argv, cwd = root, env = env, capture_output = True, stdin = subprocess.DEVNULL )
    return p.stdout, p.returncode
ne = nraw = ndec = nquote = nred = 0; dec = []
for name, root, argv, tag, attr, quoted in E:
    o, rc = runat( binp, root, argv )
    try: rows = [ r for r in hints( o ) if r[ 0 ] == tag and r[ 1 ] == attr ] if rc == 0 else []
    except Exception as ex: no( f"(e) {name}: output is not well-formed XML: {ex}" ); continue
    if not rows: no( f"(e) premise: {name}: rc={rc}, no <{tag} {attr}=> in {argv}" ); continue
    _, _, v, raw = rows[ 0 ]
    if raw is None or "&apos;" in raw: no( f"(e) {name}: {attr}=\"{raw}\" escapes the apostrophe" ); continue
    if unesc( raw ) != v: no( f"(e) {name}: parsed {v!r} != raw {raw!r}" ); continue
    ne += 1
    if quoted:
        if "'" not in raw: no( f"(e) premise: {name}: the fixture's hint carries no quote: {raw}" )
        else: nquote += 1
        if base:
            bo, _ = runat( base, root, argv )   # the same emitter's hint on the base binary spells the quote as an entity
            braw = [ r[ 3 ] or "" for r in hints( bo ) if r[ 0 ] == tag and r[ 1 ] == attr ]
            nred += bool( braw ) and ( "&apos;" in braw[ 0 ] or "&quot;" in braw[ 0 ] ) and "'" not in braw[ 0 ]
    ent = "&" in raw
    cmd = v if ent else raw
    p = subprocess.run( [ "bash", "-c", f'"$RWBIN" . --no-cache {cmd}' ], cwd = root, env = dict( env, RWBIN = binp ), capture_output = True, stdin = subprocess.DEVNULL )
    if p.returncode != 0 or not p.stdout.strip(): no( f"(e) {name}: `{cmd}` rc={p.returncode} bytes={len( p.stdout )} {p.stderr[:200]!r}" ); continue
    if ent: ndec += 1; dec.append( name )
    else: nraw += 1
    print( f"        {name:20} {'decoded' if ent else 'raw    '} {attr}=\"{raw[:110]}\"" )
verdict( ne == len( E ), f"(e) {ne}/{len( E )} emitters print a next-family hint with no &apos;", f"(e) premise: {ne}/{len( E )} emitters printed their hint" )
verdict( nraw + ndec == len( E ) and nraw, f"(e) {nraw + ndec}/{len( E )} hints ran rc=0 with an answer: {nraw} pasted raw, {ndec} XML-decoded (an entity they must carry: {', '.join( dec ) or 'none'})",
         f"(e) {nraw} raw + {ndec} decoded of {len( E )} ran" )
nq_want = sum( 1 for e in E if e[ 5 ] )
verdict( nquote == nq_want, f"(e) {nquote}/{nq_want} quote-carrying hints print a raw '", f"(e) premise: {nquote}/{nq_want} quote-carrying hints" )
if base:
    verdict( nred == nq_want, f"(e) base binary spells the quote as an entity on {nred}/{nq_want} of those hints (the red side)", f"(e) red side: base used an entity on {nred}/{nq_want}" )
else:
    print( "  SKIP  (e) base side: RIPWIRE_BASE_BIN unset" )
sys.exit( fail )
PY
rc=$?
[ "$rc" -eq 0 ] && { echo "nextaposcheck: ALL PASS"; exit 0; }
echo "nextaposcheck: FAIL"; exit 1
