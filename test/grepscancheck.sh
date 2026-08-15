#!/usr/bin/env bash
# grepscancheck.sh — gate for the P3/P5 --grep rewrite (src/search.h): the throwaway whole-repo trigram
# INDEX is gone; every ingested file is now read and scanned DIRECTLY, in parallel, and every hit carries
# the MATCHED LINE it found.
#
# Two things changed and both are pinned here:
#   (P3) the scan is PARALLEL — so the determinism law is now a threading claim, not a bookkeeping one.
#        Which hits survive the `--top-n × 4` budget truncation must be a pure function of the corpus,
#        never of which worker finished first. A budget-saturating pattern over the repo's own src/ is
#        the stress case (thousands of hits, dozens of files, truncation guaranteed).
#   (P5) every <hit> now carries <m><![CDATA[the matched line]]></m> — before this, --grep printed WHERE
#        the pattern was but never WHAT it matched, and --grep-context printed the lines AROUND the hit
#        while skipping the hit's own line. So in either mode the agent never saw the text it searched for.
#
# Asserts:
#   (1) EVERY hit has exactly one <m> child, with or without context flags, and <hit> is never self-closing
#   (2) the <m> text is EXACTLY the file's line at p="FILE:LINE" — checked against the file on disk, for
#       every hit of a multi-file run (this is what makes <m> trustworthy rather than plausible)
#   (3) child ORDER is <b> → <m> → <a> (reading order) when context flags are on
#   (4) DETERMINISM ×5 on a budget-saturating parallel scan over src/, byte-identical
#   (5) DETERMINISM ×3 of the same scan under heavy background CPU load (a thread-order bug shows up as a
#       different truncation set / a different sort tie-break, which only reproduces under contention)
#   (6) PARALLEL == SERIAL: a one-file corpus takes the workerCount<=1 branch; its hits (line + enclosing +
#       matched text) must equal the same file's hits from the parallel multi-file scan
#   (7) EXTERNAL ORACLE: the (file,line) set ripwire reports equals what `grep -n -F` reports for the same
#       literal on the same fixture — an oracle that cannot be biased by ripwire's own verifier
#   (8) a >512 B minified line is CAPPED (kGrepMatchedLineMaxBytes) and never splits a UTF-8 codepoint;
#       output stays well-formed XML and valid UTF-8
#   (9) the regex path also emits <m>, and --regex == --regex --no-prefilter (the per-file trigram reject
#       that replaced the posting lists is still SOUND)
#
# Usage:
#   bash test/grepscancheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire bash test/grepscancheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "grepscancheck: BIN=$BIN"

FIX="$ROOT/test/fixture"

# ── (1)+(2) every hit has an <m>, and its text is exactly the line on disk ────────────────────────────
"$BIN" "$FIX" --no-cache --grep=perimeter >"$TMP/lit" 2>/dev/null

# G1 (2026-08-15): hits GROUP by file under <f p="…">; a <hit> now carries only l="LINE" (+ in=, + n= when
# a byte-identical match at another site in this file folded into it). Walk <f>…</f> blocks to pair each
# <hit> with its file, same as the pre-G1 combined p="FILE:LINE" gave for free.
# G1: p= is root-relative to the CRAWL root ($FIX, what was passed to $BIN), not to $ROOT (the repo root)
# — pass $FIX so the verifier resolves each hit's path against the same root ripwire used.
python3 - "$TMP/lit" "$FIX" >"$TMP/verify1" 2>&1 <<'PY'
import re, sys
xml  = open( sys.argv[1], encoding = 'utf-8', errors = 'replace' ).read().split( '-->', 1 )[ -1 ]
root = sys.argv[2]
hits = []   # (path, line, body) — one per <hit> (a folded row's own text still applies to its own l=)
for fm in re.finditer( r'<f p="([^"]*)">(.*?)</f>', xml, re.S ):
    path = fm.group( 1 )
    for hm in re.finditer( r'<hit l="(\d+)"[^>]*>(.*?)</hit>', fm.group( 2 ), re.S ):
        hits.append( ( path, hm.group( 1 ), hm.group( 2 ) ) )
selfclosing = re.findall( r'<hit [^>]*/>', xml )
print( "HITS:%d" % len( hits ) )
print( "SELFCLOSING:%d" % len( selfclosing ) )
bad = 0
for path, line, body in hits:
    ms = re.findall( r'<m><!\[CDATA\[(.*?)\]\]></m>', body, re.S )
    if len( ms ) != 1:
        print( "NO_M:%s:%s" % ( path, line ) ); bad += 1; continue
    src = open( path if path.startswith( '/' ) else root + '/' + path, encoding = 'utf-8', errors = 'replace' ).read().split( '\n' )
    want = src[ int( line ) - 1 ]
    if ms[0] != want:
        print( "MISMATCH:%s:%s\n  got  =%r\n  want =%r" % ( path, line, ms[0], want ) ); bad += 1
print( "BAD:%d" % bad )
PY
cat "$TMP/verify1" | grep -E '^(NO_M|MISMATCH|  )' | head -8
H1="$( grep -o '^HITS:[0-9]*'        "$TMP/verify1" | cut -d: -f2 )"
S1="$( grep -o '^SELFCLOSING:[0-9]*' "$TMP/verify1" | cut -d: -f2 )"
B1="$( grep -o '^BAD:[0-9]*'         "$TMP/verify1" | cut -d: -f2 )"
{ [ "${H1:-0}" -gt 0 ] && [ "${S1:-1}" -eq 0 ]; } \
    && ok "(1) $H1 hits, none self-closing — every hit carries its matched line" \
    || no "(1) hits=$H1 selfclosing=$S1 (expected >0 hits and 0 self-closing)"
{ [ "${B1:-1}" -eq 0 ] && [ "${H1:-0}" -gt 0 ]; } \
    && ok "(2) every <m> text equals the file's own line at p=FILE:LINE" \
    || no "(2) $B1 hit(s) whose <m> text does not match the source line"

# same, with context flags on (the <m> must be there in BOTH modes — that was the P5 bug)
"$BIN" "$ROOT/test/grepcontextfix" --no-cache --grep=NEEDLE_MID_ONCE --grep-context=2 >"$TMP/ctx" 2>/dev/null
grep -q '<m><!\[CDATA\[    int hitline = NEEDLE_MID_ONCE;\]\]></m>' "$TMP/ctx" \
    && ok "(1b) --grep-context=2 also emits the matched line itself" \
    || { no "(1b) --grep-context=2 still hides the matched line"; cat "$TMP/ctx"; }

# ── (3) child order is before → matched → after ──────────────────────────────────────────────────────
perl -0777 -ne 'exit( /<hit [^>]*>\s*<b>.*?<\/b><m>.*?<\/m><a>.*?<\/a><\/hit>/s ? 0 : 1 )' "$TMP/ctx" \
    && ok "(3) child order is <b> → <m> → <a> (reading order)" \
    || { no "(3) context children are out of order"; cat "$TMP/ctx"; }

xmllint --noout "$TMP/ctx" 2>/dev/null && ok "(3b) context+matched-line output is well-formed XML" || no "(3b) malformed XML with context + <m>"

# ── (4) determinism ×5 on a budget-saturating PARALLEL scan (truncation must not depend on thread order) ──
# --pack-top-n is what caps --grep (cap × 4 = the raw budget the scan truncates at), so a common token
# over src/ truncates hard: the surviving set is exactly the one the truncation order decides.
det(){ "$BIN" "$ROOT/src" --no-cache --grep="$1" --pack-top-n="${2:-100}" ; }
det 'const' 100 >"$TMP/d1" 2>/dev/null
for i in 2 3 4 5; do det 'const' 100 >"$TMP/d$i" 2>/dev/null; done
same=1
for i in 2 3 4 5; do diff -q "$TMP/d1" "$TMP/d$i" >/dev/null || same=0; done
HITS_D="$( grep -o 'hits="[0-9]*"' "$TMP/d1" | head -1 )"
NHIT_D="$( grep -c '<hit ' "$TMP/d1" )"
{ [ "$same" -eq 1 ] && [ -s "$TMP/d1" ] && [ "$NHIT_D" -gt 0 ]; } \
    && ok "(4) determinism x5 on the parallel budget-saturating scan over src/ ($HITS_D, truncated set)" \
    || no "(4) --grep output differs run-to-run (thread-order leak) or produced nothing (hits=$NHIT_D)"

# ── (5) determinism ×3 under heavy background CPU load ────────────────────────────────────────────────
for i in 1 2 3 4 5 6 7 8; do ( while :; do :; done ) & done
LOADPIDS="$( jobs -p )"
det 'const' 100 >"$TMP/l1" 2>/dev/null
det 'const' 100 >"$TMP/l2" 2>/dev/null
det 'const' 100 >"$TMP/l3" 2>/dev/null
kill $LOADPIDS 2>/dev/null; wait 2>/dev/null
{ diff -q "$TMP/d1" "$TMP/l1" >/dev/null && diff -q "$TMP/l1" "$TMP/l2" >/dev/null && diff -q "$TMP/l2" "$TMP/l3" >/dev/null; } \
    && ok "(5) determinism x3 under 8-way background CPU load (same bytes as the unloaded run)" \
    || no "(5) output changed under CPU contention — the parallel scan leaks thread order"

# ── (6) PARALLEL == SERIAL: a one-file corpus takes the single-worker branch ──────────────────────────
mkdir -p "$TMP/solo"
cp "$FIX/geometry.cpp" "$TMP/solo/geometry.cpp"
"$BIN" "$TMP/solo" --no-cache --grep=perimeter >"$TMP/solo.xml" 2>/dev/null
# G1: a <hit> no longer carries its own path (it lives on the wrapping <f p="…">) — pair each <hit> with
# its file the same way test/grepcheck.sh's hitpaths() does. Self-comparison only (solo.rows vs par.rows,
# both produced by this SAME function), so the exact row spelling need not match any external format.
rows(){
    python3 -c '
import re, sys
xml = open( sys.argv[1] ).read().split( "-->", 1 )[ -1 ]
for fm in re.finditer( r"<f p=\"([^\"]*)\">(.*?)</f>", xml, re.S ):
    path = fm.group( 1 )
    for hm in re.finditer( r"<hit l=\"(\d+)\"(?: in=\"([^\"]*)\")?", fm.group( 2 ) ):
        inattr = hm.group( 2 ) or ""
        print( path + ":" + hm.group( 1 ) + " in=\"" + inattr + "\"" )
' "$1"
}
mrows(){ sed 's/></>\n</g' "$1" | grep -oE '<m><!\[CDATA\[.*'; }
rows     "$TMP/solo.xml" >"$TMP/solo.rows"
rows     "$TMP/lit"      | grep 'geometry.cpp' >"$TMP/par.rows"
{ [ -s "$TMP/solo.rows" ] && diff -q "$TMP/solo.rows" "$TMP/par.rows" >/dev/null; } \
    && ok "(6) single-worker (1-file corpus) hits identical to the parallel multi-file scan" \
    || { no "(6) serial and parallel scans disagree"; diff "$TMP/solo.rows" "$TMP/par.rows" | head -6; }

# ── (7) EXTERNAL ORACLE: ripwire's (file,line) set == `grep -n -F`'s, on the same literal ─────────────
# G1: $FIX is passed as the crawl ROOT, so p= is now root-relative TO $FIX (rw::sarif::rootRelativeUri) —
# a bare "geometry.cpp", not "test/fixture/geometry.cpp". `grep -F` below is run from inside $FIX for the
# same reason, so both sides compare the SAME root-relative spelling.
PAT='perimeter'
"$BIN" "$FIX" --no-cache --grep="$PAT" 2>/dev/null >"$TMP/cx.xml"
python3 -c '
import re, sys
xml = open( sys.argv[1] ).read().split( "-->", 1 )[ -1 ]
for fm in re.finditer( r"<f p=\"([^\"]*)\">(.*?)</f>", xml, re.S ):
    path = fm.group( 1 )
    for hm in re.finditer( r"<hit l=\"(\d+)\"", fm.group( 2 ) ):
        print( path + ":" + hm.group( 1 ) )
' "$TMP/cx.xml" | sort >"$TMP/cx.loc"
( cd "$FIX" && grep -rn -F "$PAT" . 2>/dev/null | sed 's|^\./||' | awk -F: '{print $1":"$2}' ) | sort -u >"$TMP/gr.loc"
if diff -q "$TMP/cx.loc" "$TMP/gr.loc" >/dev/null; then
    ok "(7) external oracle: ripwire's hit locations == grep -n -F's ($( wc -l <"$TMP/cx.loc" | tr -d ' ' ) lines)"
else
    no "(7) ripwire's hit locations differ from grep -n -F's"; diff "$TMP/cx.loc" "$TMP/gr.loc" | head -6
fi

# ── (8) long-line cap + UTF-8 safety on a generated hostile corpus ────────────────────────────────────
mkdir -p "$TMP/long"
{ printf 'int minified(){'; for i in $( seq 1 200 ); do printf 'int café%d = LONGNEEDLE + %d; ' "$i" "$i"; done; printf '}\n'; } >"$TMP/long/min.cpp"
"$BIN" "$TMP/long" --no-cache --grep=LONGNEEDLE >"$TMP/long.xml" 2>/dev/null
python3 - "$TMP/long.xml" >"$TMP/longv" 2>&1 <<'PY'
import re, sys
xml = open( sys.argv[1], 'rb' ).read().decode( 'utf-8', errors = 'strict' )   # strict: a split codepoint raises
ms  = re.findall( r'<m><!\[CDATA\[(.*?)\]\]></m>', xml, re.S )
print( "M:%d MAXBYTES:%d" % ( len( ms ), max( [ len( m.encode() ) for m in ms ] or [ 0 ] ) ) )
PY
cat "$TMP/longv"
MAXB="$( grep -o 'MAXBYTES:[0-9]*' "$TMP/longv" | cut -d: -f2 )"
{ [ -n "${MAXB:-}" ] && [ "$MAXB" -le 512 ] && [ "$MAXB" -gt 0 ]; } \
    && ok "(8) minified line capped at $MAXB bytes (<= 512) and decodes as strict UTF-8" \
    || { no "(8) matched-line cap broken (max bytes=$MAXB) or invalid UTF-8"; cat "$TMP/longv"; }
xmllint --noout "$TMP/long.xml" 2>/dev/null && ok "(8b) capped long-line output is well-formed XML" || no "(8b) capped long-line output is malformed XML"

# ── (9) the regex path emits <m> too, and the per-file trigram reject is still sound ──────────────────
"$BIN" "$ROOT/test/regexfix" --no-cache --regex='comp.te'                 >"$TMP/rx.pf" 2>/dev/null
"$BIN" "$ROOT/test/regexfix" --no-cache --regex='comp.te' --no-prefilter  >"$TMP/rx.fs" 2>/dev/null
grep -q '<m><!\[CDATA\[' "$TMP/rx.pf" \
    && ok "(9) --regex hits carry their matched line" \
    || { no "(9) --regex hits have no <m>"; head -3 "$TMP/rx.pf"; }
diff -q "$TMP/rx.pf" "$TMP/rx.fs" >/dev/null \
    && ok "(9b) per-file trigram prefilter == full-scan oracle (sound after the index removal)" \
    || { no "(9b) prefiltered output != --no-prefilter output (the reject dropped a match)"; diff "$TMP/rx.fs" "$TMP/rx.pf" | head -6; }

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
