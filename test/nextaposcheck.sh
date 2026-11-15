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
#       next-family attributes, plus an est_tokens= that may fall (it prices the emitted bytes) and never rises
# Every arm counts its premise and FAILS on zero.
#
# Out of scope (not nextAttrXml, listed so a reader does not mistake them for misses): --grep's zero-hit
# <suggest next="--for=&quot;PAT&quot;"> (verbs_grep.h emitGrepSuggest) and the next= values written through
# serialize.h escapeXml (--dead-code's filter next=, forfilepage, valuerefs, declinedsites dc_next=, defslookup to_next=).
# Arms (b) and (c) skip the <suggest> element by name.
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

python3 - "$BIN" "$BASE" "$TMP/repo" "$TMP/home" <<'PY'
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
        if tag == "suggest": continue
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
        if tag == "suggest": continue
        nb += 1; nq += "'" in v
        if raw is None or unesc( raw ) != v: no( f"(b) {list( a )} <{tag} {k}=>: parsed {v!r} != raw {raw!r}" )
verdict( ( nb and nq ), f"(b) {nb} next-family values parse to their raw text ({nq} carry a ')", f"(b) premise: {nb} values, {nq} with a quote" )

# (c) each `--` hint pasted RAW into bash runs: rc 0, non-empty answer
seen = set(); nc = ncq = 0
for a, rows in parsed.items():
    for tag, k, v, raw in rows:
        if tag == "suggest" or raw is None or not raw.startswith( "--" ) or raw in seen: continue
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
    nq = 0
    for a in map( tuple, Q ):
        bo, be, brc = run( base, list( a ) ); lo, le, lrc = lane[ a ]
        fixed = attr.sub( lambda m: m.group( 1 ) + m.group( 2 ).replace( b"&apos;", b"'" ) + m.group( 3 ), bo )
        # est_tokens= prices the emitted bytes, so 5 fewer bytes an entity may lower it: masked here, and it must not RISE
        bt, lt = [ [ int( x ) for x in est.findall( o ) ] for o in ( bo, lo ) ]
        if est.sub( b"", fixed ) == est.sub( b"", lo ) and ( be, brc ) == ( le, lrc ) and bo != lo and len( bt ) == len( lt ) and all( y <= x for x, y in zip( bt, lt ) ):
            nq += 1
        else: no( f"(d) {list( a )}: the base answer with &apos; -> ' in next-family values (est_tokens= masked, lane <= base) is not the lane answer" )
    verdict( nq, f"(d) {nq}/{len( Q )} quote-carrying calls differ from base ONLY by &apos; -> ' inside next-family values (and an est_tokens= that fell)",
             "(d) premise: 0 quote-carrying calls compared" )
else:
    print( "  SKIP  (d) base byte-identity: RIPWIRE_BASE_BIN unset" )
sys.exit( fail )
PY
rc=$?
[ "$rc" -eq 0 ] && { echo "nextaposcheck: ALL PASS"; exit 0; }
echo "nextaposcheck: FAIL"; exit 1
