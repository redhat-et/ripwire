#!/usr/bin/env bash
# snapdeterminismcheck.sh — one build, one tree, one configuration: the warm snapshot (src/warmsnap.h) it records must
# be the same bytes however the parse pool was scheduled. DET-INCLUDES: the per-thread merge
# (ingest_parsepool.h mergeThreadFacts) concatenates each worker's rows, and the order in which workers drew FILES is
# the work-stealing schedule's. The model-build tail re-sorts most families, but includes, Ruby constant opens and
# construct hits were moved into the IngestResult as merged, so their order — and the MODEL section's bytes — changed
# from run to run (8/8 ga-repos trees, measured by C1-KEYFIX #751). C1's record-first index needs a
# `cmp` between a one-worker run and an every-core run; this gate is that cmp.
#
# The corpus is every test/*fix directory copied into one tree (C, C++, Python, JS/TS, Ruby, Go, ...: ~3000 files, so
# several workers interleave many files). The knob is RIPWIRE_PARSE_THREADS=<n> (ingest_parsepool.h parsePoolWorkers),
# which the cache-stats line echoes as parse_threads=<n>; it is an observer in the snapshot's options key
# (warmsnap.h optionsKeyOf), so a one-worker recording and an every-core one name and key the same snapshot.
#
# Each configuration records in a FRESH cache directory at ONE path (the path is part of the options key, so two
# directories could never compare equal): run 1 parses and records (RECORD-FIRST, warm snapshot v12: the model and the
# graph, and the tree when its signatures are past the racy window), run 2 adds what the racy window held back. The 8-byte write stamp (header offset 40) and the header digest that covers it
# (offset 128, warm snapshot v12) are masked; nothing else is — the section digests are a function of the bytes alone.
#
# ARMS
#   P   premise: the recording runs reported parse_threads=1 and parse_threads=8 (a binary without the knob runs every
#       core both times, and the D1 pair would not compare what it says it compares), and each run saved a snapshot.
#   D1  RIPWIRE_PARSE_THREADS=1 vs =8: the MODEL sections are cmp-equal.
#   D2  two default (every-core) runs: the MODEL sections are cmp-equal. Needs no knob, so it is also the arm that
#       shows the defect on a binary that predates it.
#   D3  RIPWIRE_PARSE_THREADS=1 vs default: the WHOLE snapshot files are cmp-equal (header, tree, model, graph).
#   F   the decoded side families (includes, constant opens, construct hits) are in fileId order, with a count of the
#       rows read: zero include rows is a FAIL (a corpus that records no include proves nothing about their order).
#   Q   construct hits are recorded only by a --quality-delta ingest (ingest.h WantConstructHits), so the corpus is
#       committed to a git repo and recorded under --quality-delta with RIPWIRE_PARSE_THREADS=1 and =8: the MODEL
#       sections are cmp-equal, and zero decoded construct hits is a FAIL.
#
#   RIPWIRE_BIN=./build/ripwire bash test/snapdeterminismcheck.sh
#
# Exits non-zero on any failure. Prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )" && [ -n "$TMP" ] && [ -d "$TMP" ] || { echo "snapdeterminismcheck: mktemp -d failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required (masking and decoding the snapshot)"; exit 2; }
echo "snapdeterminismcheck: BIN=$BIN  TMP=$TMP"
unset RIPWIRE_PARSE_THREADS

W="$TMP/w"; mkdir -p "$W"
for d in "$ROOT"/test/*fix; do cp -R "$d" "$W/" 2>/dev/null; done
echo "snapdeterminismcheck: corpus $( find "$W" -type f | wc -l | tr -d ' ' ) files"
# The racy rule (warmsnap.h kRacySlackNs): no tree is recorded while any file, directory or the git index is younger
# than two seconds before the recording crawl began, by mtime OR ctime. The corpus was just written, so wait it out
# (ctime cannot be backdated). A fast runner otherwise records no snapshot in the first configuration (CI, #760).
sleep 3

# record TAG [VAR=value...] — two runs of `"$BIN" . "${VERB[@]}"` in a fresh cache dir at ONE path ($TMP/home); the
# masked snapshot lands at $TMP/TAG.snap, both runs' stderr at $TMP/TAG.err
H="$TMP/home"
record()
{
    local tag="$1"; shift
    rm -rf "$H"; mkdir -p "$H/tmp" "$H/xdg"
    local k s; : >"$TMP/$tag.err"
    for k in 1 2 3; do   # run 1 parses and records (RECORD-FIRST), run 2 is served; run 3 only when a racy window held a section back
        ( cd "$W" && env "$@" HOME="$H" TMPDIR="$H/tmp/" XDG_CACHE_HOME="$H/xdg" RIPWIRE_CACHE_STATS=1 RIPWIRE_SNAPSHOT_STATS=1 \
            "$BIN" . ${VERB[@]+"${VERB[@]}"} >"$TMP/$tag.out$k" 2>"$TMP/$tag.err$k" </dev/null )
        cat "$TMP/$tag.err$k" >>"$TMP/$tag.err"
        s="$( find "$H" -name 'ripwire-warmsnap-*.bin' 2>/dev/null | head -1 )"
        [ -n "$s" ] && [ -s "$( section "$s" 0 >"$TMP/$tag.probe"; echo "$TMP/$tag.probe" )" ] \
            && [ -s "$( section "$s" 1 >"$TMP/$tag.probe"; echo "$TMP/$tag.probe" )" ] && break   # the tree AND the model: D3 compares whole files
    done
    if [ -n "$s" ]; then
        python3 -I -c 'import sys; b = bytearray( open( sys.argv[ 1 ], "rb" ).read() ); b[ 40:48 ] = bytes( 8 ); b[ 128:136 ] = bytes( 8 ); sys.stdout.buffer.write( b )' "$s" >"$TMP/$tag.snap"
    else
        : >"$TMP/$tag.snap"
    fi
    rm -rf "$H"
}
# section SNAP INDEX — the bytes of section INDEX (0 tree, 1 model, 2 graph) of a snapshot, from the header's spans
section()
{
    python3 -I -c 'import struct, sys
b = open( sys.argv[ 1 ], "rb" ).read()
if len( b ) < 136: raise SystemExit( 0 )
o, n = struct.unpack_from( "<QQ", b, 56 + 24 * int( sys.argv[ 2 ] ) ); sys.stdout.buffer.write( b[ o:o + n ] )' "$1" "$2"
}
# the worker counts of the runs that PARSED (reparsed>0); a served run replays its facts and reports parse_threads=0
threads(){ grep 'cache-stats reparsed=[1-9]' "$TMP/$1.err" | grep -o 'parse_threads=[0-9]*' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

VERB=()
record one  RIPWIRE_PARSE_THREADS=1
record many RIPWIRE_PARSE_THREADS=8
record defA
record defB

# ── P: the premise ────────────────────────────────────────────────────────────────────────────────
for t in one many defA defB; do
    if [ -s "$TMP/$t.snap" ]; then ok "P  $t: a snapshot was recorded ($( wc -c <"$TMP/$t.snap" | tr -d ' ' ) B)"
    else no "P  $t: no snapshot was recorded ($( grep -h 'snapshot-stats' "$TMP/$t.err" | tail -1 ))"; fi
done
[ "$( threads one )" = "parse_threads=1" ] && ok "P  the RIPWIRE_PARSE_THREADS=1 runs parsed with one worker ($( threads one ))" \
    || no "P  the RIPWIRE_PARSE_THREADS=1 runs did not report parse_threads=1 (got '$( threads one )'): the knob is not in this binary"
[ "$( threads many )" = "parse_threads=8" ] && ok "P  the RIPWIRE_PARSE_THREADS=8 runs parsed with eight workers ($( threads many ))" \
    || no "P  the RIPWIRE_PARSE_THREADS=8 runs did not report parse_threads=8 (got '$( threads many )')"

# ── D: the byte identities ────────────────────────────────────────────────────────────────────────
same_model()
{
    local label="$1" a="$2" b="$3"
    section "$TMP/$a.snap" 1 >"$TMP/$a.model"; section "$TMP/$b.snap" 1 >"$TMP/$b.model"
    if [ ! -s "$TMP/$a.model" ] || [ ! -s "$TMP/$b.model" ]; then no "$label — a MODEL section is empty or missing, nothing was compared"; return; fi
    if cmp -s "$TMP/$a.model" "$TMP/$b.model"; then ok "$label — MODEL sections cmp-equal ($( wc -c <"$TMP/$a.model" | tr -d ' ' ) B compared)"
    else no "$label — MODEL sections differ ($( cmp "$TMP/$a.model" "$TMP/$b.model" 2>&1 | head -1 | sed 's/.* differ: //' )): $( python3 -I "$TMP/fam.py" "$TMP/$a.snap" "$TMP/$b.snap" | tr '\n' ';' )"; fi
}
cat >"$TMP/fam.py" <<'PYFAM'
# fam.py SNAP [SNAP2] — decode the MODEL section's side families (warmsnap_model.h writeSideFamilies: includes, constant
# opens, construct hits, FFI aliases, route defs, route uses). They are found by scanning for the one offset at which
# all six parse as well-formed rows whose fileId is below the file count; the streams before them are not decoded.
# One SNAP: per family, its row count and whether it is in fileId order. Two: per family, EQUAL / PERMUTATION / VALUES.
import struct, sys
def model( p ):
    b = open( p, 'rb' ).read(); o, n = struct.unpack_from( '<QQ', b, 80 ); return b[ o:o + n ]
def file_count( m ):
    at = 16; nb, = struct.unpack_from( '<Q', m, at ); at += 8
    for _ in range( nb ):
        l, = struct.unpack_from( '<I', m, at ); at += 4 + l
    return struct.unpack_from( '<Q', m, at )[ 0 ]
class Rd:
    def __init__( s, m, at ): s.m, s.at = m, at
    def u( s, f ):
        v = struct.unpack_from( f, s.m, s.at ); s.at += struct.calcsize( f ); return v
    def str( s ):
        l, = s.u( '<I' )
        if l > 1 << 16 or s.at + l > len( s.m ): raise ValueError
        v = s.m[ s.at:s.at + l ]; s.at += l; return v.decode( 'utf-8' )
def fam( r, F, row ):
    n, = r.u( '<Q' )
    if n > 1 << 24: raise ValueError
    out = []
    for _ in range( n ):
        x = row( r )
        if x[ 0 ] >= F: raise ValueError
        out.append( x )
    return out
def inc( r ):
    f, b, fl = r.u( '<IIB' ); t = r.str()
    if fl >= 16: raise ValueError
    return ( f, b, fl, t )
def cop( r ):
    f, s, e, ns = r.u( '<IIIB' ); t = r.str()
    if ns > 1 or s > e: raise ValueError
    return ( f, s, e, ns, t )
def con( r ):  return r.u( '<IIIB' )
def ffi( r ):
    f, k, lc = r.u( '<IBB' ); return ( f, k, lc, r.str(), r.str(), r.str() )
def rdef( r ):
    f, l, me = r.u( '<IIB' ); return ( f, l, me, r.str(), r.str() )
def ruse( r ):
    f, l, fr, me = r.u( '<IIIB' ); return ( f, l, fr, me, r.str() )
NAMES = ( 'includes', 'constOpens', 'constructHits', 'bindingAliases', 'routeDefs', 'routeUses' )
def decode( p ):
    m = model( p ); F = file_count( m )
    for at in range( len( m ) - 8, 0, -1 ):
        try:
            r = Rd( m, at ); fs = [ fam( r, F, inc ), fam( r, F, cop ), fam( r, F, con ) ]
            flag, = r.u( '<B' )
            if flag > 1: raise ValueError
            fs += [ fam( r, F, ffi ), fam( r, F, rdef ), fam( r, F, ruse ) ]
        except ( ValueError, struct.error, UnicodeDecodeError ):
            continue
        if fs[ 0 ]: return fs
    return None
A = decode( sys.argv[ 1 ] )
if A is None: print( 'side families not found' ); raise SystemExit( 0 )
if len( sys.argv ) == 2:
    for n, x in zip( NAMES, A ):
        print( n, len( x ), 'sorted' if all( x[ i ][ 0 ] <= x[ i + 1 ][ 0 ] for i in range( len( x ) - 1 ) ) else 'UNSORTED' )
    raise SystemExit( 0 )
B = decode( sys.argv[ 2 ] ) or [ [] ] * 6
for n, x, y in zip( NAMES, A, B ):
    if x != y: print( f'{n}: {len( x )} vs {len( y )} rows, ' + ( 'PERMUTATION' if sorted( x ) == sorted( y ) else 'VALUES' ) )
PYFAM

same_model "D1 RIPWIRE_PARSE_THREADS=1 vs =8" one many
same_model "D2 two every-core runs" defA defB
if [ -s "$TMP/one.snap" ] && cmp -s "$TMP/one.snap" "$TMP/defA.snap"; then ok "D3 RIPWIRE_PARSE_THREADS=1 vs every core — the WHOLE snapshot files are cmp-equal ($( wc -c <"$TMP/one.snap" | tr -d ' ' ) B, stamp and header digest masked)"
else no "D3 RIPWIRE_PARSE_THREADS=1 vs every core — the snapshot files differ ($( cmp "$TMP/one.snap" "$TMP/defA.snap" 2>&1 | head -1 | sed 's/.* differ: //' ))"; fi

# ── F: the families the merge orders, decoded ─────────────────────────────────────────────────────
python3 -I "$TMP/fam.py" "$TMP/defA.snap" >"$TMP/fam.txt"
nincs="$( awk '$1 == "includes" { print $2 }' "$TMP/fam.txt" )"
nopen="$( awk '$1 == "constOpens" { print $2 }' "$TMP/fam.txt" )"
if [ "${nincs:-0}" -gt 0 ]; then ok "F  the corpus recorded ${nincs} include rows and ${nopen:-0} constant opens (the rows whose order is under test)"
else no "F  VACUOUS: no include rows decoded from the snapshot ($( tr '\n' ' ' <"$TMP/fam.txt" ))"; fi
[ "${nopen:-0}" -gt 0 ] || no "F  VACUOUS: no Ruby constant opens decoded from the snapshot — the corpus lost its Ruby fixtures"
for f in includes constOpens constructHits; do
    line="$( awk -v f="$f" '$1 == f' "$TMP/fam.txt" )"
    case "$line" in
        *UNSORTED*) no "F  $f are not in fileId order ($line)";;
        *sorted*)   ok "F  $f in fileId order ($line)";;
        *)          no "F  $f not decoded ($( tr '\n' ' ' <"$TMP/fam.txt" ))";;
    esac
done

# ── Q: the construct hits, under --quality-delta ──────────────────────────────────────────────────
( cd "$W" && git init -q && git add -A && git -c user.name=gate -c user.email=gate@example.invalid -c commit.gpgsign=false commit -qm corpus ) \
    || no "Q  could not commit the corpus to a git repo"
sleep 3   # the racy rule again: git init and the commit made the root directory and the index young
VERB=( --quality-delta )
record qdone  RIPWIRE_PARSE_THREADS=1
record qdmany RIPWIRE_PARSE_THREADS=8
same_model "Q  --quality-delta, RIPWIRE_PARSE_THREADS=1 vs =8" qdone qdmany
python3 -I "$TMP/fam.py" "$TMP/qdmany.snap" >"$TMP/qfam.txt"
qline="$( awk '$1 == "constructHits"' "$TMP/qfam.txt" )"
ncon="$( awk '$1 == "constructHits" { print $2 }' "$TMP/qfam.txt" )"
if [ "${ncon:-0}" -gt 0 ]; then
    case "$qline" in
        *UNSORTED*) no "Q  construct hits are not in fileId order ($qline)";;
        *)          ok "Q  ${ncon} construct hits decoded from the --quality-delta snapshot, in fileId order";;
    esac
else no "Q  VACUOUS: the --quality-delta snapshot holds no construct hits ($( tr '\n' ' ' <"$TMP/qfam.txt" ))"; fi

if [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAILURES above"; exit 1
