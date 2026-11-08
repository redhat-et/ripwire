#!/usr/bin/env bash
# deeptailcheck.sh — the DEEP-TAIL serving contract (rank-order preservation + the file-grain tail).
#
# WHY THIS GATE EXISTS. Two measured losses on budgeted consumers of the ranked bundles (registered in
# docs/EVALS.md, "Deep-tail serving"):
#   d1  the served JSON/XML groups symbols by FILE and sorts by LINE inside the group, so a consumer that
#       truncates at a budget reads document order, not ranker order — the true per-symbol rank was
#       unrecoverable from the default bundle. Every lens-ranked signature row now carries its 1-based
#       global rank (XML ` r="N"`, JSON `"r":N`), rank-consistent with the flat --format=candidates export.
#   d2  the lens serves ranked symbol HEADS concentrated in few files, while file-grain consumers need
#       recall 20+ deep — the bundle now ends its signature-shaped sections with a FILE-GRAIN TAIL: the
#       remaining candidate files (positive lens score, not already in the head) as paths only, in the
#       best-symbol projection of the same ranking, disclosed as total=/shown=/capped= and labelled
#       weaker-than-head evidence in the legend.
#
# FOLD C (forbudget-soft round C, owner decision 2026-10-14; rule 4): the <tail> now lists the RANK rows above (paths only,
# `<t p=…/>`, the files outside the shown head, files of trimmed rows first) and THEN page 0 of `--for=TASK --limit=40`
# minus the files already listed, each with sym= (`<t p=… sym=…/>`). total= counts every positive-score file (the page's
# total=), so the old "total = files outside the head" denominator is a by-design break: the arms below read the rank rows
# where they used to read the whole tail, and pin the page rows against the page itself.
# TAIL-SYM (train 30): a rank row now carries sym= too (the file's top lens symbols, the page row's own names), so sym=
# no longer tells the two kinds apart. The reader below splits the tail structurally instead: tail = R + (page 0 minus R),
# R = the SHORTEST prefix for which the rest is exactly the --limit=40 page's rows not in R, in page order (a cut tail:
# a prefix of them). No split → the reader prints SPLIT-FAIL and the arm reading it fails. Arm 1t pins the new sym=.
# R-DEDUP (2026-11-07): a page row of a file the head shows no longer repeats the names its <d> rows print: its sym= is the
# file's next positive-score symbols in lens order (at most 3), p= only when every one is shown. The page-row arms read the
# expected names off the corpus (every score ties, so lens order = definition order); arm 1d pins it, with a positive twin.
#
# RED-FIRST: every d1/d2 assertion below FAILS against the prebuilt d8e257d baseline (which emits neither
# surface); each fuses presence with content bytes so a bare-exit arm cannot pass green-while-inert.
#
# Usage:  test/deeptailcheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/deeptailcheck.sh
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "deeptailcheck: BIN=$BIN"

# ── fixture: 12 one-symbol files, every one matching the query, so the head/tail split is exact ─────────
# --pack-top-n=4 keeps a 4-symbol head (4 files); the remaining 8 files are the expected tail, in id
# (= path) order because every score ties — deterministic by the (score desc, id asc) contract.
# 12 files x 5 defs = 60 symbols, every one matching the query: --pack-top-n=4 keeps a one-file head
# (11 tail files); the DEFAULT head (40) keeps files w01..w08, leaving exactly w09..w12 as the tail.
CORPUS="$TMP/corpus"
mkdir -p "$CORPUS"
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
    { for j in a b c d e; do
        printf 'def widget_frobnicate_%s_%s():\n    """widget frobnicate helper %s %s"""\n    return 1\n' "$i" "$j" "$i" "$j"
    done; } > "$CORPUS/w$i.py"
done
Q="widget frobnicate helper"

# L1 (2026-09-19): the CLI default legend is compact; arm 8 reads the FULL legend's prose off $XML, so it asks for it.
XML="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 --legend=full 2>/dev/null )"
printf '%s' "$XML" > "$TMP/for.xml"
# R-DEDUP: <syms> has priority over a head file's tail row (src/forfilesyms.h tailRowsWithoutPicks cuts the names it prints), so
# the tail walk's own rows (FOLD C, 1d) read the block-off twin; (1s) pins the cut on $XML.
RIPWIRE_NO_FILE_SYMS=1 "$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 --legend=full > "$TMP/for_nosyms.xml" 2>/dev/null

# ── 1) d2: the file-grain tail — present, complete; its rank rows disjoint from the head ───────────────
# a python reader of the tail (XML, or the --json twin's "tail" object): "rank" rows and "page" rows (p, sym), in order,
# split against the file page argv[3] (the same corpus+task at --limit=40); "ranksym" = rank rows with their sym=
cat > "$TMP/tail.py" <<'PY'
import json, re, sys, html
s = open( sys.argv[ 1 ] ).read()
if s.lstrip().startswith( "{" ):
    t = json.loads( s ).get( "tail", {} )
    rows = list( zip( t.get( "files", [] ), t.get( "sym", [] ) ) )
    capped = t.get( "shown", 0 ) < t.get( "total", 0 )
else:
    m = re.search( r"<tail\b([^>]*)>(.*?)</tail>", s, re.S )
    rows = [ ( html.unescape( p ), html.unescape( y ) ) for p, _h, y in re.findall( r'<t p="([^"]*)"( sym="([^"]*)")?/>', m.group( 2 ) if m else "" ) ]
    capped = bool( m ) and ' capped="1"' in m.group( 1 )
page = [ html.unescape( p ) for p in re.findall( r'<f p="([^"]*)"', open( sys.argv[ 3 ] ).read() ) ]
paths = [ p for p, _ in rows ]
def split():
    for k in range( len( paths ) + 1 ):
        seen = set( paths[ :k ] )
        rem = [ p for p in page if p not in seen ]
        if paths[ k: ] == ( rem[ :len( paths ) - k ] if capped else rem ):
            return k
    return -1
k = split()
mode = sys.argv[ 2 ]
if k < 0:
    print( "SPLIT-FAIL" ); sys.exit( 0 )
for i, ( p, sym ) in enumerate( rows ):
    if mode == "rank" and i < k: print( p )
    if mode == "ranksym" and i < k: print( p + "\t" + sym )
    if mode == "page" and i >= k: print( p + "\t" + sym )
    if mode == "all": print( p + "\t" + sym )
PY
# the page rows a tail must carry: page 0 of the file page, minus the rank rows, in page order
"$BIN" "$CORPUS" --no-cache --for="$Q" --limit=40 2>/dev/null > "$TMP/page40.xml"
# R-DEDUP: a file the answer's head shows ($2, the answer) names its first 3 symbols NOT among those <d> rows, in definition order
pagerows(){ python3 -c '
import re, sys, html
rank = set( open( sys.argv[ 1 ] ).read().split( "\n" ) )
shown = {}
for n, f in re.findall( r"<d [^>]*?\bn=\"([^\"]*)\" p=\"([^\"]*)\"", open( sys.argv[ 2 ] ).read() ):
    shown.setdefault( html.unescape( f ), set() ).add( html.unescape( n ) )
for p, sym in re.findall( r"<f p=\"([^\"]*)\"[^>]*? sym=\"([^\"]*)\"", sys.stdin.read() ):
    p = html.unescape( p )
    if p in shown:
        defs = re.findall( r"^def (\w+)", open( sys.argv[ 3 ] + "/" + p ).read(), re.M )
        sym = ",".join( [ n for n in defs if n not in shown[ p ] ][ :3 ] )
    else:
        sym = html.unescape( sym )
    if p not in rank: print( p + "\t" + sym )
' "$1" "$2" "$CORPUS" < "$TMP/page40.xml"; }
TAILTAG="$( printf '%s' "$XML" | grep -o '<tail [^>]*>' | head -1 )"
case "$TAILTAG" in
    *'total="12"'*'shown="12"'*'capped="0"'*) ok "tail element: every positive-score file (12), all shown: $TAILTAG" ;;
    '') no "no <tail> element in the --for bundle (d2 missing)" ;;
    *)  no "tail element has wrong counts: $TAILTAG (expected total=12 shown=12 capped=0)" ;;
esac
python3 "$TMP/tail.py" "$TMP/for.xml" rank "$TMP/page40.xml" > "$TMP/rank1.txt"
TROWS="$( grep -vc SPLIT-FAIL "$TMP/rank1.txt" )"
if [ "$TROWS" = "11" ]; then ok "tail serves 11 rank rows (the tail's prefix before page 0's remainder): the files outside the one-file head"; else no "tail rank rows: $TROWS (expected 11; $( head -1 "$TMP/rank1.txt" ))"; fi
# 1t) TAIL-SYM (train 30): every rank row carries sym=, the SAME names the file page's row for that file prints
#     (the page row's top[] reused, never recomputed); a rank row without sym= is the base behaviour (red there)
#     (the fixture's 12 files all fit the 40-row page; forsoftbudgetcheck C1t reads a real corpus off the whole page)
RS="$( python3 - "$TMP/for.xml" "$TMP/page40.xml" "$TMP/tail.py" <<'PY'
import html, re, subprocess, sys
want = { html.unescape( p ): html.unescape( y ) for p, y in re.findall( r'<f p="([^"]*)"[^>]*? sym="([^"]*)"', open( sys.argv[ 2 ] ).read() ) }
got = subprocess.run( [ "python3", sys.argv[ 3 ], sys.argv[ 1 ], "ranksym", sys.argv[ 2 ] ], capture_output=True, text=True ).stdout.splitlines()
rows = [ l.split( "\t" ) for l in got if "\t" in l ]
bad = [ p for p, y in rows if not y or want.get( p ) != y ]
print( "%d %d %s" % ( len( rows ), len( bad ), ",".join( bad[ :3 ] ) ) )
PY
)"
case "$RS" in
    "11 0 ") ok "(1t) tail-sym: all 11 rank rows carry sym= equal to the file page's sym= for that file" ;;
    *)       no "(1t) tail-sym: rank rows / rows with a missing or different sym= = $RS (expected 11 0)" ;;
esac
# disjoint: no rank row may also be a head row's p= (P7: the head is flat <d … p=> rows, no <f> wrapper)
DUP="$( python3 - "$TMP/for.xml" "$TMP/rank1.txt" <<'PY'
import re, sys
s = open( sys.argv[ 1 ] ).read()
head = set( re.findall( r"<d [^>]*?\bp=\"([^\"]*)\"", s ) )
print( sum( 1 for t in open( sys.argv[ 2 ] ).read().split() if t in head ) )
PY
)"
if [ "$DUP" = "0" ]; then ok "tail rank rows are disjoint from the head's files"; else no "$DUP tail rank row(s) duplicate a head file"; fi
# FOLD C: the page rows ARE the file page's first 40 rows not listed above, in page order, sym= included
python3 "$TMP/tail.py" "$TMP/for_nosyms.xml" page "$TMP/page40.xml" > "$TMP/page1.txt"
pagerows "$TMP/rank1.txt" "$TMP/for_nosyms.xml" > "$TMP/page1_want.txt"
if [ -s "$TMP/page1_want.txt" ] && cmp -s "$TMP/page1.txt" "$TMP/page1_want.txt"; then
    ok "FOLD C: the tail's page rows are the --limit=40 page's rows not listed above ($( grep -c . "$TMP/page1.txt" ), sym= equal)"
else
    no "FOLD C: tail page rows differ from the file page's ($( grep -c . "$TMP/page1.txt" ) vs $( grep -c . "$TMP/page1_want.txt" ))"
fi
# (1d) R-DEDUP: no tail row repeats a name its file's <d> rows print, and the head file w01 (a..d shown) refills from the next
#      lens rank (e). Positive twin: every row of a file outside the head keeps its 3 names. Reads the tail rows ("all"); an
#      empty or unsplittable tail fails both halves.
python3 "$TMP/tail.py" "$TMP/for_nosyms.xml" all "$TMP/page40.xml" > "$TMP/all1.txt"
DD="$( python3 - "$TMP/for_nosyms.xml" "$TMP/all1.txt" <<'PY'
import re, sys, html
shown = {}
for n, f in re.findall( r'<d [^>]*?\bn="([^"]*)" p="([^"]*)"', open( sys.argv[ 1 ] ).read() ):
    shown.setdefault( html.unescape( f ), set() ).add( html.unescape( n ) )
rows = [ l.rstrip( "\n" ).split( "\t" ) for l in open( sys.argv[ 2 ] ) if "\t" in l ]
rep = sum( 1 for p, y in rows if set( y.split( "," ) ) & shown.get( p, set() ) )
w01 = [ y for p, y in rows if p == "w01.py" ]
full = sum( 1 for p, y in rows if p not in shown and len( y.split( "," ) ) == 3 )
print( rep, "|".join( w01 ), full, len( rows ) )
PY
)"
case "$DD" in
    "0 widget_frobnicate_01_e 11 12") ok "(1d) R-DEDUP: no tail sym= repeats a <d> name of its file; head file w01 refills from rank 5 (e); 11 non-head rows keep 3 names" ;;
    *) no "(1d) R-DEDUP: repeats / w01 sym= / non-head rows with 3 names / rows = $DD (expected 0 widget_frobnicate_01_e 11 12)" ;;
esac
# (1s) R-DEDUP: <syms> has priority. With the block on, it prints widget_frobnicate_01_e (w01.py, a head file), so w01's tail row
#      drops it (no name left: p= only); no head file's tail row names a <syms> row; every other byte is the block-off twin's.
#      Positive twin: the block-off answer's w01 row names it (1d).
SS="$( python3 - "$TMP/for.xml" "$TMP/for_nosyms.xml" <<'PY'
import re, sys
on, off = open( sys.argv[ 1 ] ).read(), open( sys.argv[ 2 ] ).read()
at = on.find( "<syms" )
lo, hi = ( on.rfind( "<!--", 0, at ), on.find( "</syms>", at ) + 7 ) if at >= 0 else ( 0, 0 )   # the block and its legend comment
picked = set( re.findall( r'<y [^>]*\bn="([^"]*)"', on[ at:hi ] ) ) if at >= 0 else set()
heads = set( re.findall( r'<d [^>]*?\bp="([^"]*)"', on ) )
tail = re.findall( r'<t p="([^"]*)"( sym="([^"]*)")?', on )
w01 = [ y for p, _, y in tail if p == "w01.py" ]
rep = sum( 1 for p, _, y in tail if p in heads and set( y.split( "," ) ) & picked )
rest = on[ :lo ] + on[ hi: ]
cut = off.replace( '<t p="w01.py" sym="widget_frobnicate_01_e"', '<t p="w01.py"' )
mask = lambda t: re.sub( r' at="[^"]*"| est_tokens="\d+"', '', t )
print( int( "widget_frobnicate_01_e" in picked ), "|".join( w01 ) or "-", rep, int( mask( rest ) == mask( cut ) ) )
PY
)"
case "$SS" in
    "1 - 0 1") ok "(1s) R-DEDUP: <syms> prints widget_frobnicate_01_e, w01's tail row drops it (p= only), no head tail row names a <syms> row, rest = block-off twin" ;;
    *) no "(1s) R-DEDUP: picked / w01 sym= / head rows naming a <syms> row / rest==twin = $SS (expected 1 - 0 1)" ;;
esac

# ── 2) d1: r= on every ranked row, exactly the ranks 1..K ──────────────────────────────────────────────
RSEQ="$( printf '%s' "$XML" | grep -o '<d l="[^>]*>' | grep -o ' r="[0-9]*"' | grep -o '[0-9]*' | sort -n | tr '\n' ' ' )"
if [ "$RSEQ" = "1 2 3 4 " ]; then ok "every <d> row carries r=, ranks exactly 1..4"; else no "XML r= sequence wrong: '$RSEQ' (expected '1 2 3 4 ')"; fi

# ── 3) d1 cross-surface: r=1 names the same symbol the flat candidates export ranks first ──────────────
TOPD="$( printf '%s' "$XML" | grep -o '<d l="[^>]*r="1"[^>]*>' | head -1 | grep -o 'n="[^"]*"' | head -1 )"
TOPC="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --format=candidates --top-k=1 2>/dev/null | grep -o '<cand r="1" [^>]*>' | grep -o 'n="[^"]*"' | head -1 )"
if [ -n "$TOPD" ] && [ "$TOPD" = "$TOPC" ]; then ok "r=1 row and <cand r=1> name the same symbol ($TOPD)"
else no "rank surfaces disagree: bundle r=1 is '$TOPD', candidates r=1 is '$TOPC'"; fi

# ── 4) the JSON dialect: per-row "r" + the always-present tail object, matching the XML tail ───────────
# The JSON arm runs at the DEFAULT head (--pack-top-n has no --json dialect): 40 symbols = files w01..w08,
# so the expected tail is exactly w09..w12 — compared file-for-file against the default XML run's tail.
"$BIN" "$CORPUS" --no-cache --for="$Q" --json 2>/dev/null > "$TMP/for.json"
"$BIN" "$CORPUS" --no-cache --for="$Q" 2>/dev/null > "$TMP/for_default.xml"
JRANK="$( python3 "$TMP/tail.py" "$TMP/for.json" rank "$TMP/page40.xml" | tr '\n' ',' )"
JV="$( python3 - "$TMP/for.json" "$TMP/for_default.xml" "$JRANK" <<'EOF'
import json, re, sys
d = json.load( open( sys.argv[1] ) )
xml = open( sys.argv[2] ).read()
rs = sorted( s.get( "r", 0 ) for s in d.get( "sigs", [] ) )   # P7: flat sigs array
tail = d.get( "tail" )
import html
xrows = [ ( html.unescape( p ), html.unescape( y ) ) for p, _, y in re.findall( r"<t p=\"([^\"]*)\"( sym=\"([^\"]*)\")?/>", xml ) ]
xrows = [ ( p, y ) for p, _h, y in [ ( r[0], None, r[1] ) for r in xrows ] ]
checks = [
    bool( rs ) and rs == list( range( 1, len( rs ) + 1 ) ),
    tail is not None and tail.get( "total" ) == 12 and tail.get( "shown" ) == 12
        and sys.argv[ 3 ] == "w09.py,w10.py,w11.py,w12.py,"
        # R-DEDUP: w01..w08 are wholly shown (5 of 5 rows each), so their page rows print p= only; w09..w12 keep sym=
        and [ f for f, y in zip( tail.get( "files", [] ), tail.get( "sym", [] ) ) if y ] == [ "w09.py", "w10.py", "w11.py", "w12.py" ],
    tail is not None and list( zip( tail.get( "files", [] ), tail.get( "sym", [] ) ) ) == xrows,
]
print( " ".join( "Y" if c else "N" for c in checks ) )
EOF
)"
case "$JV" in
    "Y Y Y") ok "JSON: r keys are contiguous 1..K; tail total/shown=12/12, rank rows w09..w12; files+sym match the XML tail exactly" ;;
    *)       no "JSON dialect wrong (r-seq / tail-counts / xml-parity = $JV)" ;;
esac

# ── 5) pack-task: both dialects carry the rank fact ────────────────────────────────────────────────────
PT="$( "$BIN" "$CORPUS" --no-cache --pack-task="$Q" 2>/dev/null )"
if printf '%s' "$PT" | grep -q '<d l="[^>]*r="1"'; then ok "pack-task XML ranking rows carry r="; else no "pack-task XML rows carry no r="; fi
PTJ="$( "$BIN" "$CORPUS" --no-cache --pack-task="$Q" --json 2>/dev/null | python3 -c '
import json, sys
d = json.load( sys.stdin )
rs = [ s.get( "r", 0 ) for s in d.get( "ranking", [] ) ]   # P7: flat ranking array
print( "Y" if rs and all( r > 0 for r in rs ) else "N" )
' )"
if [ "$PTJ" = "Y" ]; then ok "pack-task JSON ranking rows carry r"; else no "pack-task JSON ranking rows carry no r"; fi

# ── 6) hard ceiling: the tail funds LAST and its disclosure survives a spent budget ────────────────────
TB="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 --token-budget=220 2>/dev/null )"
TBTAG="$( printf '%s' "$TB" | grep -o '<tail [^>]*>' | head -1 )"
case "$TBTAG" in
    *'total="12"'*) ok "tight --token-budget keeps the tail disclosure: $TBTAG" ;;
    '') no "tight --token-budget dropped the <tail> element entirely (disclosure lost)" ;;
    *)  no "tight-budget tail lost its denominator: $TBTAG" ;;
esac
TBSHOWN="$( printf '%s' "$TBTAG" | grep -o 'shown="[0-9]*"' | grep -o '[0-9]*' )"
TBCAP="$(   printf '%s' "$TBTAG" | grep -o 'capped="[0-9]"' | grep -o '[0-9]' )"
if [ -n "$TBSHOWN" ] && [ "$TBSHOWN" -lt 12 ] && [ "$TBCAP" = "1" ] && printf '%s' "$TBTAG" | grep -q ' next="'; then
    ok "tight budget trimmed tail rows (shown=$TBSHOWN), disclosed capped=1 and named next="
else
    no "tight budget did not trim/disclose honestly (shown=$TBSHOWN capped=$TBCAP)"
fi
if printf '%s' "$TB" | xmllint --noout - 2>/dev/null; then ok "tight-budget bundle stays well-formed"; else no "tight-budget bundle fails xmllint"; fi

# ── 7) zero-tail honesty: a head that covers every file leaves NO rank row (0 = none remain); the page rows still
#       list every positive-score file (FOLD C), so total= = the 3 files and nothing is cut ─────────────────────────
MINI="$TMP/mini"
mkdir -p "$MINI"
for i in 1 2 3; do
    printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper %s"""\n    return 1\n' "$i" "$i" > "$MINI/m$i.py"
done
"$BIN" "$MINI" --no-cache --for="$Q" 2>/dev/null > "$TMP/mini.xml"
"$BIN" "$MINI" --no-cache --for="$Q" --limit=40 2>/dev/null > "$TMP/mini_page.xml"
Z="$( grep -o '<tail [^>]*>' "$TMP/mini.xml" | head -1 )"
ZR="$( python3 "$TMP/tail.py" "$TMP/mini.xml" rank "$TMP/mini_page.xml" | grep -c . )"
case "$Z" in
    *'total="3"'*'shown="3"'*'capped="0"'*)
        if [ "$ZR" = "0" ]; then ok "all-files-in-head bundle: 0 rank rows (none remain), the 3 files as page rows, nothing cut ($Z)"
        else no "all-files-in-head bundle lists $ZR rank row(s) — a head file served as 'outside the head'"; fi ;;
    *) no "zero-tail bundle wrong/missing: '$Z'" ;;
esac

# ── 7s) TAIL-SYM near-miss: a rank-row file with fewer than 3 positive-score symbols names only those (no padding,
#        no empty slot, no neighbour's name); the file with 5 names its first 3 in lens order ──────────────────────
FEW="$TMP/few"
mkdir -p "$FEW"
for j in a b c d e; do printf 'def widget_frobnicate_five_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$j"; done > "$FEW/f5.py"
for j in a b; do printf 'def widget_frobnicate_two_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$j"; done > "$FEW/f2.py"
printf 'def widget_frobnicate_one():\n    """widget frobnicate helper"""\n    return 1\n' > "$FEW/f1.py"
printf 'def widget_frobnicate_head():\n    """widget frobnicate helper widget frobnicate helper"""\n    return 1\n' > "$FEW/f0.py"
"$BIN" "$FEW" --no-cache --for="$Q" --pack-top-n=1 2>/dev/null > "$TMP/few.xml"
"$BIN" "$FEW" --no-cache --for="$Q" --limit=40 2>/dev/null > "$TMP/few_page.xml"
FS="$( python3 "$TMP/tail.py" "$TMP/few.xml" ranksym "$TMP/few_page.xml" | sort | tr '\n' '|' )"
FHEAD="$( grep -o '<d [^>]*p="[^"]*"' "$TMP/few.xml" | grep -o 'p="[^"]*"' | sort -u | tr '\n' ' ' )"
python3 - "$FS" <<'PY' > "$TMP/few.verdict"
import sys
rows = dict( r.split( "\t" ) for r in sys.argv[ 1 ].split( "|" ) if "\t" in r )
n = { p: len( y.split( "," ) ) for p, y in rows.items() }
ok = n.get( "f1.py" ) == 1 and n.get( "f2.py" ) == 2 and n.get( "f5.py" ) == 3 \
     and all( "widget_frobnicate_two_" in x for x in rows.get( "f2.py", "" ).split( "," ) ) \
     and rows.get( "f1.py" ) == "widget_frobnicate_one"
print( "Y" if ok else "N " + repr( rows ) )
PY
case "$( cat "$TMP/few.verdict" )" in
    Y) ok "(7s) tail-sym: rank rows of 1-, 2- and 5-symbol files name 1, 2 and 3 of their OWN symbols (head: $FHEAD)" ;;
    *) no "(7s) tail-sym: short-file rank rows wrong: $( cat "$TMP/few.verdict" ) (head: $FHEAD)" ;;
esac

# ── 9) H2H-Graft lane 2 (2026-09-07): a row the byte ladder TRIMS lands in the tail, never nowhere ─────
# The tail used to exclude every file of the 40-candidate SURFACE, so a sigs row cut by the budget (rank 5..40)
# appeared in neither section. On rocksdb three single-file answers at candidate rank 5/10/5 were served nowhere.
# Contract: tail total = files with a positive score MINUS the files of the sigs rows actually shown; the trimmed
# rows' files come first, in rank order; the JSON twin agrees file-for-file at the same budget.
T9="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --token-budget=900 2>/dev/null )"
T9_SIGS="$( printf '%s' "$T9" | grep -o '<sigs [^>]*>' | head -1 )"
T9_SHOWN_FILES="$( printf '%s' "$T9" | grep -o '<d [^>]*p="[^"]*"' | grep -o 'p="[^"]*"' | sed 's/p="//;s/"//' | sort -u )"
T9_NSHOWN="$( printf '%s\n' "$T9_SHOWN_FILES" | grep -c . )"
T9_TAG="$( printf '%s' "$T9" | grep -o '<tail [^>]*>' | head -1 )"
T9_TOTAL="$( printf '%s' "$T9_TAG" | grep -oE 'total="[0-9]+"' | grep -oE '[0-9]+' )"
case "$T9_SIGS" in *'capped="1"'*) ok "(9) fixture guard: the 900-token budget trims sigs rows ($T9_SIGS; $T9_NSHOWN file(s) shown)" ;;
                   *) no "(9) fixture guard: expected the ladder to trim at --token-budget=900, got '$T9_SIGS'" ;; esac
printf '%s' "$T9" > "$TMP/t9.xml"
T9_RANKOUT="$( python3 "$TMP/tail.py" "$TMP/t9.xml" rank "$TMP/page40.xml" )"   # SPLIT-FAIL stays a failure: never read as zero rank rows
T9_RANK="$( printf '%s\n' "$T9_RANKOUT" | grep -c . )"
T9_SHOWNROWS="$( printf '%s' "$T9_TAG" | grep -oE 'shown="[0-9]+"' | grep -oE '[0-9]+' )"
# every file outside the shown rows is a rank row (12 - shown files), or the cut tail stops short of them and says so (next=)
if [ "$T9_RANKOUT" = "SPLIT-FAIL" ]; then
    no "(9a) the tail does not split into rank rows + the file page's rows (SPLIT-FAIL): $T9_TAG"
elif [ "$T9_TOTAL" = "12" ] && { [ "$T9_RANK" = "$(( 12 - T9_NSHOWN ))" ] || { [ "$T9_SHOWNROWS" -lt "$(( 12 - T9_NSHOWN ))" ] && printf '%s' "$T9_TAG" | grep -q ' next="'; }; }; then
    ok "(9a) tail total=12; rank rows $T9_RANK = 12 files minus the $T9_NSHOWN shown, or a cut tail naming next= (trimmed rows land IN the tail)"
else
    no "(9a) tail total=$T9_TOTAL, $T9_RANK rank row(s) but $T9_NSHOWN file(s) shown — a ranked file served nowhere ($T9_TAG)"
fi
T9_EXPECT_FIRST="$( for i in 01 02 03 04 05 06 07 08 09 10 11 12; do printf '%s\n' "w$i.py"; done | grep -vxF -f <( printf '%s\n' "$T9_SHOWN_FILES" ) | head -1 )"
T9_FIRST="$( python3 "$TMP/tail.py" "$TMP/t9.xml" rank "$TMP/page40.xml" | head -1 )"
if [ -n "$T9_FIRST" ]; then
    [ "$T9_FIRST" = "$T9_EXPECT_FIRST" ] && ok "(9b) first tail row is the best trimmed file ($T9_FIRST)" \
                                          || no "(9b) first tail row '$T9_FIRST', expected the best trimmed file '$T9_EXPECT_FIRST'"
else
    printf '  SKIP  (9b) the 900-token budget left the tail no rows (total disclosed above)\n'
fi
# The JSON twin runs its OWN ladder (its rows cost different bytes), so it may trim one row more or less at the
# same budget; the contract is per dialect — its tail total = 12 minus the files ITS sigs rows show.
"$BIN" "$CORPUS" --no-cache --for="$Q" --token-budget=900 --json 2>/dev/null > "$TMP/t9.json"
T9JV="$( python3 -c '
import json, subprocess, sys
d = json.load( open( sys.argv[ 1 ] ) ); t = d.get( "tail", {} )
shown = { s.get( "p" ) for s in d.get( "sigs", [] ) }
rank = subprocess.run( [ "python3", sys.argv[ 2 ], sys.argv[ 1 ], "rank", sys.argv[ 3 ] ], capture_output=True, text=True ).stdout.split()
if "SPLIT-FAIL" in rank:   # no split is a failure, never an empty rank list a cut tail could pass with
    print( "N SPLIT-FAIL" ); sys.exit( 0 )
cut_ok = t.get( "shown", 0 ) < 12 - len( shown ) and "next" in t
print( "%s %d %d %d" % ( "Y" if t.get( "total" ) == 12 and ( len( rank ) == 12 - len( shown ) or cut_ok ) and not ( set( rank ) & shown ) else "N",
                         t.get( "total", -1 ), len( rank ), len( shown ) ) )' "$TMP/t9.json" "$TMP/tail.py" "$TMP/page40.xml" )"
case "$T9JV" in
    Y*) ok "(9c) JSON twin: tail total=12, rank rows = 12 minus its own shown files, none a shown file ($T9JV)" ;;
    *)  no "(9c) JSON twin: tail wrong (ok total rank shown = $T9JV)" ;;
esac

# ── 8) the legend defines both new surfaces where the reader meets them ────────────────────────────────
HDR="$( printf '%s' "$XML" | sed 's/-->.*//' )"
if printf '%s' "$HDR" | grep -q 'tail: file-grain rows, WEAKER evidence' && printf '%s' "$HDR" | grep -q 'sym= its top symbols'; then ok "legend defines the tail (file-grain, weaker evidence; rank rows, then page rows with sym=)"; else no "legend does not define the tail"; fi
if printf '%s' "$HDR" | grep -q 'cover); sym= its top symbols by lens rank, minus names a sigs row or the syms block shows (a pointer, not the answer); total='; then ok "legend: sym= on either tail row kind is the file's top lens symbols, a pointer, not the answer (tail-sym)"; else no "legend does not say what sym= on a rank row means"; fi
CL="$( "$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 2>/dev/null | sed 's/-->.*//' )"
if printf '%s' "$CL" | grep -q 't sym= its top symbols not in sigs/syms (a pointer, not the answer)'; then ok "compact legend: t sym= is the file's top symbols, a pointer (tail-sym)"; else no "compact legend does not define t sym= for every tail row"; fi
if printf '%s' "$HDR" | grep -q 'r= on a ranked row'; then ok "legend defines r= (true ranker order)"; else no "legend does not define r="; fi

# ── 9) determinism + well-formedness ───────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 2>/dev/null > "$TMP/d1.xml"
"$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 2>/dev/null > "$TMP/d2.xml"
"$BIN" "$CORPUS" --no-cache --for="$Q" --pack-top-n=4 2>/dev/null > "$TMP/d3.xml"
if cmp -s "$TMP/d1.xml" "$TMP/d2.xml" && cmp -s "$TMP/d2.xml" "$TMP/d3.xml"; then
    ok "deterministic: three runs byte-identical"
else
    no "runs differ byte-wise (determinism broken)"
fi
if xmllint --noout "$TMP/d1.xml" 2>/dev/null; then ok "bundle is well-formed XML"; else no "bundle fails xmllint"; fi

# ── 10) MCP parity: the `for` verb serves the same two surfaces ────────────────────────────────────────
MCP_INNER="$( printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$CORPUS"'","task":"'"$Q"'"}}}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import json, sys
r = json.load( sys.stdin )
print( "" if "error" in r else r["result"]["content"][0]["text"] )
' )"
if printf '%s' "$MCP_INNER" | grep -q '<tail total=' && printf '%s' "$MCP_INNER" | grep -q '<t p="[^"]*" sym="'; then ok "MCP for verb serves the file-grain tail, page rows included (sym=)"; else no "MCP for verb has no <tail> or no page rows"; fi
MCP_BARE="$( printf '%s' "$MCP_INNER" | grep -o '<t p="[^"]*"/>' | grep -c . )"
MCP_SYM="$( printf '%s' "$MCP_INNER" | grep -o '<t p="[^"]*" sym="[^"]*"/>' | grep -c . )"
# R-DEDUP: the default head shows w01..w08 whole, so exactly those 8 page rows print p= only; the other 4 keep sym=
MCP_BAREF="$( printf '%s' "$MCP_INNER" | grep -o '<t p="[^"]*"/>' | tr '\n' ',' )"
if [ "$MCP_BAREF" = '<t p="w01.py"/>,<t p="w02.py"/>,<t p="w03.py"/>,<t p="w04.py"/>,<t p="w05.py"/>,<t p="w06.py"/>,<t p="w07.py"/>,<t p="w08.py"/>,' ] && [ "$MCP_SYM" = "4" ]; then ok "(10t) MCP for twin: the 4 rows outside the head carry sym=, the 8 wholly shown head files p= only (R-DEDUP)"; else no "(10t) MCP for twin: $MCP_BARE tail row(s) without sym= ($MCP_SYM with; bare: $MCP_BAREF)"; fi
if printf '%s' "$MCP_INNER" | grep -q '<d l="[^>]*r="1"'; then ok "MCP for verb rows carry r="; else no "MCP for verb rows carry no r="; fi

echo
if [ "$fail" = "0" ]; then echo "deeptailcheck: ALL PASS"; else echo "deeptailcheck: FAILURES ABOVE"; fi
exit "$fail"
