#!/usr/bin/env bash
# abiarchretirecheck.sh — the gate for lane abiarch-retire-register (2026-11-17): --arch names its root and prints paths
# relative to it, five derivable attributes and one attribute-borne legend are RETIRED from --abi and --arch, and every
# attribute that survives is defined in the compact legend.
#
#   test/abiarchretirecheck.sh                 |   test/abiarchretirecheck.sh asan/ripwire
#
# WHAT WAS RETIRED, and the rule each arm reconstructs it by (the emitter comments carry the same derivations):
#   abi@head            the first nine characters of at=                          (it still rides where at= cannot be stamped)
#   abi@rows ref@rows   the sum of the element's kind counters (drift unknown absent rename spelling stub head-moved)
#   abi@excluded ref@excluded   the sum of the unlisted ones (rename spelling stub head-moved)
#   struct@size_differs size_delta is not 0
#   arch@new_violations the <v> rows without baselined="1"                         (in a normal run AND in both baseline modes)
#   metrics@note        the definitions it carried are legend now (constant text; the zone_unknown clause beside zone_unknown=)
#   <v from= to=>, <m path=>   root-relative under the new arch@root; the old spelling was root + "/" + the relative one
# NOT retired, on purpose: capped= on <abi> and <ref>. It is exactly dropped > 0 (and "a <more> child exists"), but
# src/pageview.h's truncation vocabulary, rule 3, puts the bit beside every shown= tool-wide and test/truncvocabcheck.sh
# (A)/(D) gate it; arm (K) keeps that visible here.
#
# THE EVIDENCE IS BYTE-FOR-BYTE. test/abiarchretirefix/*.xml are the answers of the binary built from origin/main 5139f7840,
# unedited, over the corpora test/lib/abiarchfixture.sh builds. Each (D) arm rebuilds the OLD payload from the NEW one by the
# rules above and requires the goldens' bytes; nothing is compared by "looks equivalent". A golden is re-recorded only by a
# binary that still emits the retired attributes (RIPWIRE_ABIARCH_RECORD=DIR refuses any other), so a later lane that changes
# these rows on purpose edits the goldens by hand, in the same commit, with the reason.
#
# Arms:
#   (N) NON-VACUITY     the corpora carry every shape the arms read: <v> and <m> rows, a root-level module, all five reachable
#                       kinds, a same-size drift, a capped ref, an excluded-only ref
#   (R) ROOT            <arch root=> is the root as typed; every from=/to=/path= names a real file/directory UNDER it and is
#                       neither absolute nor ./-prefixed; the rows are byte-identical under five spellings of one root;
#                       a multi-root run names no root. MUTATION: one absolute path restored -> red.
#   (D) DERIVATIONS     old payload rebuilt from the new == golden, for 2 abi views and 7 arch runs (three modes, two root
#                       spellings, both note variants); the retired attributes are gone from the new answer.
#                       MUTATION, one per retirement: perturb the surviving source of the derivation -> the rebuilt value moves.
#   (L) LEGEND          every element@attr a default (compact) answer carries is defined in that answer's legend;
#                       CONTROL: delete any one clause of that legend and at least one attribute goes undefined.
#   (K) the capped= bit still rides beside every shown= (the refusal above).
#
# ELEMENT-BLIND, like legendcoveragecheck: (L) asks whether the legend spells `name=`, not on which element.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/abiarchretirefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "abiarchretirecheck: git unavailable — skipping"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "abiarchretirecheck: python3 not found"; exit 2; }
echo "abiarchretirecheck: BIN=$BIN"

# hermetic: no caller HOME, a private cache dir, fixed identities and dates (the shas below are content-addressed)
export HOME="$TMP/home" TMPDIR="$TMP/cache"; mkdir -p "$HOME" "$TMPDIR"
export GIT_AUTHOR_NAME=ripwire GIT_AUTHOR_EMAIL=ripwire@example.invalid
export GIT_COMMITTER_NAME=ripwire GIT_COMMITTER_EMAIL=ripwire@example.invalid
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
. "$ROOT/test/lib/abiarchfixture.sh"

# capture OUT [LEGEND]: every answer the arms read, into OUT. Each arch tree is fresh, because the baseline modes write a sidecar
# in the working directory. Exit codes go to OUT/rc so an answer that silently became a refusal cannot pass as an empty document.
capture(){
    local O="$1" L="${2:-full}"
    local W="$TMP/w.$L"
    mkdir -p "$O" "$W"; : > "$O/rc"
    cap(){ local name="$1"; shift; "$@" >"$O/$name.xml" 2>"$O/$name.err"; echo "$name $?" >> "$O/rc"; }
    aaf_abi_repo "$W/abi"
    ( cd "$W/abi" && cap abi        "$BIN" . --stray-content --abi --no-cache --legend="$L"
                     cap abi_detail "$BIN" . --stray-content --abi --detail=1 --no-cache --legend="$L" )
    aaf_arch_tree "$W/arch" go
    ( cd "$W"      && cap arch_rel  "$BIN" arch --arch=arch/rules.txt --no-cache --legend="$L" )
    ( cd "$W/arch" && cap arch_n1   "$BIN" . --arch=rules.txt --no-cache --legend="$L"
                      cap arch_b    "$BIN" . --arch=rules.txt --baseline --no-cache            # a writing mode refuses an explicit --legend: it answers at the default
                      cap arch_n2   "$BIN" . --arch=rules.txt --no-cache --legend="$L"
                      printf '#include "../render/shader.h"\nint third() { return 3; }\n' > test/third.cpp
                      cap arch_n3   "$BIN" . --arch=rules.txt --no-cache --legend="$L"
                      cap arch_u    "$BIN" . --arch=rules.txt --baseline-update --no-cache )
    aaf_arch_tree "$W/plain"
    ( cd "$W/plain" && cap arch_plain "$BIN" . --arch=rules.txt --no-cache --legend="$L" )
}

# The record mode: only a binary that still emits what this lane retired may write goldens.
if [ -n "${RIPWIRE_ABIARCH_RECORD:-}" ]; then
    capture "$TMP/rec" full
    if grep -q ' new_violations="' "$TMP/rec/arch_n1.xml" && grep -q ' size_differs="' "$TMP/rec/abi.xml"; then
        mkdir -p "$RIPWIRE_ABIARCH_RECORD" && cp "$TMP/rec"/*.xml "$TMP/rec/rc" "$RIPWIRE_ABIARCH_RECORD/" && echo "recorded $( ls "$TMP/rec"/*.xml | wc -l | tr -d ' ' ) goldens into $RIPWIRE_ABIARCH_RECORD"; exit 0
    fi
    echo "abiarchretirecheck: $BIN no longer emits new_violations=/size_differs=, so its answers are not the pre-retirement goldens — refusing to record"; exit 2
fi

capture "$TMP/full" full
capture "$TMP/dflt" compact
"$BIN" --legend-dict >"$TMP/dict.txt" 2>/dev/null

# the five spellings of ONE root, and a two-root run, for (R)
RT="$TMP/roots"; mkdir -p "$RT/cwd"; aaf_arch_tree "$RT/arch" go
( cd "$RT/arch" && "$BIN" .         --arch=rules.txt      --no-cache --legend=full >"$RT/dot.xml"   2>/dev/null )
( cd "$RT"      && "$BIN" arch      --arch=arch/rules.txt --no-cache --legend=full >"$RT/rel.xml"   2>/dev/null )
( cd "$RT"      && "$BIN" ./arch    --arch=arch/rules.txt --no-cache --legend=full >"$RT/dotrel.xml" 2>/dev/null )
( cd "$RT"      && "$BIN" arch/     --arch=arch/rules.txt --no-cache --legend=full >"$RT/slash.xml" 2>/dev/null )
( cd "$RT/cwd"  && "$BIN" "$RT/arch" --arch="$RT/arch/rules.txt" --no-cache --legend=full >"$RT/abs.xml" 2>/dev/null )
aaf_arch_tree "$RT/second"
( cd "$RT"      && "$BIN" arch second --arch=arch/rules.txt --no-cache --legend=full >"$RT/multi.xml" 2>"$RT/multi.err" ); multiRc=$?
if [ "$multiRc" -eq 2 ]; then ok "(R) the two-root run exits 2 (its violations are still found)"; else no "(R) the two-root run exited $multiRc, want 2"; fi

python3 - "$FIX" "$TMP/full" "$TMP/dflt" "$RT" "$TMP/dict.txt" >"$TMP/verdicts" <<'PY'
import os, re, sys
FIX, FULL, DFLT, RT, DICT = sys.argv[1:6]
KINDS    = ( "drift", "unknown", "absent", "rename", "spelling", "stub", "head-moved" )   # abicheck.h kKindPolicy, in its order
UNLISTED = ( "rename", "spelling", "stub", "head-moved" )
NOTE = ( 'Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — '
         'directory-level estimate from name-based deps; zone_na = types=0 modules excluded from zone_pain/zone_useless (no meaningful abstractness '
         'score); zone_ok = typed modules in neither corner (the main-sequence middle); zone_pain+zone_useless+zone_ok+zone_na%s = modules, the full '
         'partition; propagation_cost = density of the file-dep transitive closure (MacCormack, validated coupling form) — fraction of files reachable '
         'from an average file%s' )
NOTE_UNKNOWN = ( '; zone_unknown = modules holding a file in a language this build draws no file edges for (no_file_edges=): zone and coupling '
                 'unknown, not zero, and part of the partition' )
out = []
def ok( m ): out.append( "OK " + m )
def no( m ): out.append( "NO " + m )
def check( cond, good, bad = None ): ( ok if cond else no )( good if cond or bad is None else bad ); return cond
def read( *p ):
    try: return open( os.path.join( *p ), encoding = "utf-8" ).read()
    except OSError: return ""
def payload( doc ): return re.sub( r"<!--.*?-->", "", doc, flags = re.S )
def legend( doc ):  return " ".join( re.findall( r"<!--(.*?)-->", doc, re.S ) )
TAG = re.compile( r'<([A-Za-z][\w:.-]*)((?: [\w:.-]+="[^"]*")*)(\s*/?)>' )
def attrs( text ): return re.findall( r' ([\w:.-]+)="([^"]*)"', text )
def tag( name, al, close ): return "<" + name + "".join( ' %s="%s"' % kv for kv in al ) + close + ">"
def rewrite( doc, fn ):   # fn( name, [ ( attr, value ) ] ) -> the new attribute list, or None to leave the tag as it is
    def one( m ):
        al = fn( m.group( 1 ), attrs( m.group( 2 ) ) )
        return m.group( 0 ) if al is None else tag( m.group( 1 ), al, m.group( 3 ) )
    return TAG.sub( one, doc )
def put( al, after, key, value ):   # insert ( key, value ) after attribute `after` (None: first)
    i = 0 if after is None else [ k for k, _ in al ].index( after ) + 1
    return al[ :i ] + [ ( key, value ) ] + al[ i: ]
def kindsum( al, names ): return str( sum( int( v ) for k, v in al if k in names ) )

# ── the two reconstructions: the OLD payload from the NEW one ───────────────────────────────────────────────────────────
def old_abi( new ):
    def fn( name, al ):
        d = dict( al )
        if name == "abi":
            if "head" not in d: al = put( al, None, "head", d.get( "at", "" ).split( "+" )[ 0 ][ :9 ] )
            al = put( al, "blobs", "rows", kindsum( al, KINDS ) )
            return put( al, "dropped", "excluded", kindsum( al, UNLISTED ) )
        if name == "ref":
            al = put( al, "date", "rows", kindsum( al, KINDS ) )
            return put( al, "capped", "excluded", kindsum( al, UNLISTED ) )
        if name == "struct" and "size_delta" in d:
            return put( al, "ref_size", "size_differs", "0" if d[ "size_delta" ] == "0" else "1" )
        return None
    return rewrite( new, fn )
def old_arch( new ):
    root = dict( attrs( ( re.search( r"<arch[^>]*>", new ) or [ "" ] )[ 0 ] ) ).get( "root" )
    fresh = sum( 1 for m in re.finditer( r"<v [^>]*>", new ) if ' baselined="1"' not in m.group( 0 ) )
    under = lambda rel: rel if root is None else root.rstrip( "/" ) + "/" + rel
    def fn( name, al ):
        d = dict( al )
        if name == "arch":
            return put( [ kv for kv in al if kv[ 0 ] != "root" ], "baselined", "new_violations", str( fresh ) )
        if name == "v":
            return [ ( k, under( v ) if k in ( "from", "to" ) else v ) for k, v in al ]
        if name == "m":
            return [ ( k, ( root.rstrip( "/" ) if v == "." and root is not None else under( v ) ) if k == "path" else v ) for k, v in al ]
        if name == "metrics":
            unknown = "zone_unknown" in d
            return al + [ ( "note", NOTE % ( "+zone_unknown" if unknown else "", NOTE_UNKNOWN if unknown else "" ) ) ]
        return None
    return rewrite( new, fn )
def values( doc, element, attr ): return [ dict( attrs( m.group( 2 ) ) ).get( attr ) for m in TAG.finditer( doc ) if m.group( 1 ) == element ]

ABI  = ( "abi", "abi_detail" )
ARCH = ( "arch_n1", "arch_rel", "arch_b", "arch_n2", "arch_n3", "arch_u", "arch_plain" )
new  = { n: payload( read( FULL, n + ".xml" ) ) for n in ABI + ARCH }
gold = { n: payload( read( FIX,  n + ".xml" ) ) for n in ABI + ARCH }
rcN  = dict( l.split() for l in read( FULL, "rc" ).splitlines() ); rcG = dict( l.split() for l in read( FIX, "rc" ).splitlines() )

# ── (N) non-vacuity ─────────────────────────────────────────────────────────────────────────────────────────────────────
check( all( gold[ n ] and new[ n ] for n in ABI + ARCH ), "(N) all %d goldens and all %d answers are non-empty" % ( len( gold ), len( new ) ),
       "(N) empty: goldens %s, answers %s" % ( [ n for n in gold if not gold[ n ] ], [ n for n in new if not new[ n ] ] ) )
check( rcN == rcG and len( rcN ) == len( ABI + ARCH ), "(N) the nine exit codes are the goldens' (%s)" % " ".join( "%s=%s" % kv for kv in sorted( rcN.items() ) ),
       "(N) exit codes moved: now %s, golden %s" % ( sorted( rcN.items() ), sorted( rcG.items() ) ) )
a, ad = new[ "abi" ], new[ "abi_detail" ]
kindsSeen = sorted( { v for v in values( ad, "struct", "kind" ) } )
check( kindsSeen == [ "absent", "drift", "head-moved", "rename", "unknown" ], "(N) abi: the detail view lists five kinds (%s)" % " ".join( kindsSeen ), "(N) abi kinds seen: %s" % kindsSeen )
check( values( a, "struct", "size_delta" ).count( "0" ) >= 1 and "4" in values( a, "struct", "size_delta" ), "(N) abi: a same-size drift (size_delta=0) and a resized one are both listed" )
check( "<more structs=\"2\"/>" in a and values( a, "abi", "dropped" ) == [ "2" ], "(N) abi: one ref is past the display cap (dropped=2, <more structs=2>)" )
check( values( a, "abi", "excluded_refs" ) == [ "2" ] and len( values( a, "ref", "name" ) ) == 6 and len( values( ad, "ref", "name" ) ) == 8, "(N) abi: 6 refs listed, 2 more whose rows are all excluded kinds" )
n1 = new[ "arch_n1" ]
check( len( values( n1, "v", "from" ) ) == 2 and len( values( n1, "m", "path" ) ) == 4, "(N) arch: 2 <v> rows and 4 <m> rows carry paths", "(N) arch rows: %d <v>, %d <m>" % ( len( values( n1, "v", "from" ) ), len( values( n1, "m", "path" ) ) ) )
check( len( values( new[ "arch_n3" ], "v", "baselined" ) ) == 3 and values( new[ "arch_n3" ], "v", "baselined" ).count( "1" ) == 2, "(N) arch: the mixed run has 2 baselined rows and 1 new one" )
check( values( n1, "metrics", "zone_unknown" ) == [ "1" ] and values( new[ "arch_plain" ], "metrics", "zone_unknown" ) == [ None ], "(N) arch: one run carries zone_unknown=, one does not (both note variants)" )

# ── (R) root= and the paths under it ────────────────────────────────────────────────────────────────────────────────────
def root_problems( doc, typed, disk ):
    p = []
    rootAttr = values( doc, "arch", "root" )
    if rootAttr != [ typed ]: p.append( "root= is %s, typed %r" % ( rootAttr, typed ) )
    paths = [ ( "file", v ) for v in values( doc, "v", "from" ) + values( doc, "v", "to" ) ] + [ ( "dir", v ) for v in values( doc, "m", "path" ) ]
    if not paths: p.append( "no path attribute at all" )
    for kind, v in paths:
        if v is None or v.startswith( "/" ) or v.startswith( "./" ) or disk in v: p.append( "%s is not root-relative" % v )
        elif not ( os.path.isfile if kind == "file" else os.path.isdir )( os.path.join( disk, v ) ): p.append( "%s names no %s under the root" % ( v, kind ) )
    return p
disk = os.path.join( RT, "arch" )
spell = { "dot": ".", "rel": "arch", "dotrel": "./arch", "slash": "arch/", "abs": disk }
docs = { k: payload( read( RT, k + ".xml" ) ) for k in spell }
bad = { k: root_problems( docs[ k ], spell[ k ], disk ) for k in spell }
check( not any( bad.values() ), "(R) <arch root=> is the root as typed and every from=/to=/path= names a real file or directory under it, under %d spellings (%s)" % ( len( spell ), " ".join( spell.values() ) ),
       "(R) " + "; ".join( "%s: %s" % ( spell[ k ], ", ".join( v[ :3 ] ) ) for k, v in bad.items() if v ) )
noroot = { k: re.sub( r' root="[^"]*"', "", d, count = 1 ) for k, d in docs.items() }
check( docs[ "dot" ] and len( set( noroot.values() ) ) == 1, "(R) the rows are byte-identical under all %d spellings: only root= differs" % len( spell ),
       "(R) the rows move with the root's spelling: %s" % sorted( ( k, len( v ) ) for k, v in noroot.items() ) )
check( "." in values( docs[ "abs" ], "m", "path" ), "(R) the root's own directory is path=\".\" under an absolute root", "(R) no path=\".\" under an absolute root: %s" % values( docs[ "abs" ], "m", "path" ) )
mut = docs[ "abs" ].replace( '<v from="', '<v from="' + disk + "/", 1 )
check( mut != docs[ "abs" ] and root_problems( mut, disk, disk ), "(R) MUTATION: one absolute from= restored -> the path arm goes red (%s)" % ( root_problems( mut, disk, disk ) or [ "" ] )[ 0 ].replace( disk, "$ROOT" ),
       "(R) MUTATION: an absolute path restored into from= was NOT caught" )
multi = payload( read( RT, "multi.xml" ) )
check( "<arch " in multi and values( multi, "arch", "root" ) == [ None ] and any( v.startswith( "arch/" ) for v in values( multi, "v", "from" ) ),
       "(R) a two-root run names no root= and keeps the labelled spelling", "(R) two-root run: root=%s from=%s" % ( values( multi, "arch", "root" ), values( multi, "v", "from" )[ :2 ] ) )

# ── (D) every retirement, rebuilt byte-for-byte ─────────────────────────────────────────────────────────────────────────
RETIRED = ( ( "abi", ( "abi", "rows" ) ), ( "abi", ( "abi", "excluded" ) ), ( "abi", ( "ref", "rows" ) ), ( "abi", ( "ref", "excluded" ) ), ( "abi", ( "struct", "size_differs" ) ),
            ( "abi", ( "abi", "head" ) ), ( "arch_n3", ( "arch", "new_violations" ) ), ( "arch_n3", ( "metrics", "note" ) ) )
still = [ "%s@%s" % ea for n, ea in RETIRED for d in ( [ new[ m ] for m in ( ABI if n == "abi" else ARCH ) ] ) if any( v is not None for v in values( d, *ea ) ) ]
check( not still, "(D) the retired attributes are absent from all nine answers (%s)" % " ".join( sorted( { "%s@%s" % ea for _, ea in RETIRED } ) ), "(D) still emitted: %s" % " ".join( sorted( set( still ) ) ) )
for names, fn in ( ( ABI, old_abi ), ( ARCH, old_arch ) ):
    for n in names:
        rebuilt = fn( new[ n ] )
        if rebuilt == gold[ n ] and gold[ n ]: ok( "(D) %s: the origin/main payload rebuilt from the new one, byte-identical (%d B -> %d B)" % ( n, len( gold[ n ].encode() ), len( new[ n ].encode() ) ) )
        else:
            at = next( ( i for i, ( x, y ) in enumerate( zip( rebuilt, gold[ n ] ) ) if x != y ), min( len( rebuilt ), len( gold[ n ] ) ) )
            no( "(D) %s: rebuilt payload differs from the golden at byte %d: rebuilt [%s] golden [%s]" % ( n, at, rebuilt[ max( 0, at - 40 ):at + 60 ], gold[ n ][ max( 0, at - 40 ):at + 60 ] ) )
# one mutation per retirement: perturb the surviving SOURCE in the new answer; the rebuilt value of the retired attribute must move
def moved( n, fn, element, attr, before, after ):
    src = new[ n ]; mutated = src.replace( before, after, 1 )
    was, now = values( gold[ n ], element, attr ), values( fn( mutated ), element, attr )
    return mutated != src and was != now and len( was ) == len( now )
MUT = ( ( "abi@head from at=",                     "abi",        old_abi,  "abi",     "head",           ' at="',                 ' at="0' ),
        ( "abi@rows from a kind counter",          "abi",        old_abi,  "abi",     "rows",           ' drift="17"',           ' drift="16"' ),
        ( "abi@excluded from an unlisted counter", "abi",        old_abi,  "abi",     "excluded",       ' head-moved="1"',       ' head-moved="2"' ),
        ( "ref@rows from its kind counter",        "abi",        old_abi,  "ref",     "rows",           ' head_only="1" drift="14"', ' head_only="1" drift="13"' ),
        ( "ref@excluded from its unlisted counter","abi_detail", old_abi,  "ref",     "excluded",       ' head_only="0" head-moved="1"', ' head_only="0" head-moved="2"' ),
        ( "struct@size_differs from size_delta=",  "abi",        old_abi,  "struct",  "size_differs",   ' size_delta="8"',       ' size_delta="0"' ),
        ( "arch@new_violations from the <v> rows", "arch_n3",    old_arch, "arch",    "new_violations", '.cpp" fromLayer="test" to="render/shader.h" toLayer="render"/>', '.cpp" fromLayer="test" to="render/shader.h" toLayer="render" baselined="1"/>' ),
        ( "v@from from root=",                     "arch_rel",   old_arch, "v",       "from",           ' root="arch"',          ' root="other"' ),
        ( "m@path from root=",                     "arch_rel",   old_arch, "m",       "path",           ' root="arch"',          ' root="other"' ),
        ( "metrics@note from zone_unknown=",       "arch_n1",    old_arch, "metrics", "note",           ' zone_unknown="1"',     '' ) )
for label, n, fn, element, attr, before, after in MUT:
    check( moved( n, fn, element, attr, before, after ), "(D) MUTATION %s: perturbing the source moves the rebuilt value off the golden" % label,
           "(D) MUTATION %s: the rebuilt value did NOT move (the derivation does not read its source, or the fixture lacks %r)" % ( label, before ) )

# ── (L) every surviving attribute is defined where it is met ────────────────────────────────────────────────────────────
def keys( doc ):
    seen = []
    for m in TAG.finditer( payload( doc ) ):
        for k, _ in attrs( m.group( 2 ) ):
            if k != "schema" and ( m.group( 1 ), k ) not in seen: seen.append( ( m.group( 1 ), k ) )
    return seen
def gaps( doc, leg = None ):
    leg = legend( doc ) if leg is None else leg
    return [ "%s@%s" % ea for ea in keys( doc ) if re.search( r"(?<![\w:.-])" + re.escape( ea[ 1 ] ) + r"\s*=", leg ) is None ]
entries = sorted( { re.sub( r"^ripwire\.[\w-]+/v1 <[\w-]+>: ", "", l ) for l in read( DICT ).splitlines()[ 1: ] if len( l ) > 8 }, key = len, reverse = True )
# One tool-wide term is exempt from the control, by name: unmeasured_files= and masked_files= ride every answer no_file_edges= rides and
# both spell its name, so cutting its own clause leaves the NAME spelled. That is this predicate's element- and clause-blindness, not a
# definition: the three are one disclosure (graphlegend.h noFileEdgesRootAttrXml).
SHADOWED = ( "no_file_edges=LANGS: ", )
total = cut = 0; undef = []; inert = []
for n in ABI + ARCH:
    doc = read( DFLT, n + ".xml" ); leg = legend( doc ); total += len( keys( doc ) )
    undef += [ "%s: %s" % ( n, g ) for g in gaps( doc ) ]
    for e in entries:
        if e in leg:
            cut += 1
            if not gaps( doc, leg.replace( e, "", 1 ) ) and not e.startswith( SHADOWED ): inert.append( "%s: [%s...]" % ( n, e[ :48 ] ) )
check( total >= 300 and not undef, "(L) every attribute the nine DEFAULT answers carry is defined in its own legend (%d element@attr keys)" % total,
       "(L) undefined in the default answer (%d keys read): %s" % ( total, "; ".join( undef[ :12 ] ) ) )
check( cut >= 80 and not inert, "(L) CONTROL: each of the %d legend clauses those answers carry, deleted alone, leaves an attribute undefined" % cut,
       "(L) CONTROL: %d clauses cut; deleting these left nothing undefined, so the arm cannot see them go: %s" % ( cut, "; ".join( inert[ :8 ] ) ) )

# ── (K) the bit this lane did NOT retire ────────────────────────────────────────────────────────────────────────────────
shown = [ m for n in ABI for m in TAG.finditer( new[ n ] ) if ' shown="' in m.group( 2 ) ]
check( len( shown ) >= 16 and all( re.search( r' capped="[01]"', m.group( 2 ) ) for m in shown ), "(K) capped= still rides beside every shown= on <abi> and <ref> (%d elements; pageview.h rule 3)" % len( shown ),
       "(K) a shown= without its capped= bit on --abi (%d elements read)" % len( shown ) )
print( "\n".join( out ) )
PY
pyrc=$?
nverdicts=0
while IFS= read -r line; do
    case "$line" in
        "OK "*) ok "${line#OK }"; nverdicts=$(( nverdicts + 1 )) ;;
        "NO "*) no "${line#NO }"; nverdicts=$(( nverdicts + 1 )) ;;
        *)      [ -z "$line" ] || no "unreadable verdict line: $line" ;;
    esac
done < "$TMP/verdicts"
[ "$pyrc" -eq 0 ] && [ "$nverdicts" -ge 30 ] || no "the checker exited $pyrc after $nverdicts verdicts (want 0 and at least 30) — an arm did not run"

if command -v xmllint >/dev/null 2>&1; then
    badxml=""
    for f in "$TMP/full"/*.xml "$TMP/dflt"/*.xml; do xmllint --noout "$f" >/dev/null 2>&1 || badxml="$badxml ${f#"$TMP"/}"; done
    if [ -z "$badxml" ]; then ok "(X) all 18 answers are well-formed XML"; else no "(X) malformed:$badxml"; fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS (abiarchretirecheck)"; else echo "SOME FAILED (abiarchretirecheck)"; fi
exit "$fail"
