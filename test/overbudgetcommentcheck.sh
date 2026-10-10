#!/usr/bin/env bash
# overbudgetcommentcheck.sh — A4-F9 gate: a symbol NAME containing "--" must never break the XML when it
# lands on the packBodies over-budget OMISSION path.
#
# packBodies, when a def does not fit the remaining --pack-budget-bytes AND something was already emitted,
# skips the whole def and leaves a visible marker:  <!-- body omitted (over budget): NAME -->.  A NAME with
# a "--" run (C++ operator--, a markdown "-- heading") is ill-formed inside an XML comment and xmllint
# rejects the whole document (the G4 gate). The fix collapses every '-' run to a single '-' before splicing.
#
# This gate feeds test/overbudgetfix/ (a struct with a big `bump()` method + an `operator--`), forces the
# omission path with a tiny budget, and asserts:
#   - the output passes xmllint --noout (would FAIL pre-fix: the raw "operator--" in the comment)
#   - the omission marker for operator-- is present but with the '--' run collapsed (contains "operator-",
#     never a raw "operator--")
#
# THE REST OF THE OVER-BUDGET CONTRACT (lane/cutfix-bodies, 2026-09-23; arms B1-B5, generated fixture):
#   (B1) RANK FIRST: packBodies walks the budget in the CALLER'S order and groups only the survivors by file.
#        It used to regroup by file BEFORE the budget, so --expand=alpha,gamma,beta (alpha and beta sharing a
#        file) shipped beta and dropped gamma, the second thing asked for. RED on 60b65f02.
#   (B2) NEVER SILENT: every body the budget drops is named, including those met after the budget was
#        spent (the old `break`s named none of them) — those in ONE `<!-- bodies omitted (budget spent): a, b -->`
#        list. Names == total - shown. RED on 60b65f02.
#   (B3) A TRUNCATED FIRST BODY says so outside its CDATA: <bodies capped="1">, <b lines="lo-hi/T"
#        truncated="1" next=…>, no `<!-- truncated -->` inside the CDATA, and following next= at the same
#        budget reassembles the whole body byte for byte. RED on 60b65f02 (capped="0", marker in the CDATA).
#   (B4) determinism and well-formedness of every B-arm document.
#   (B5) WHOLE LINES, AND next= ALWAYS ADVANCES (review M1): on a body whose FIRST line exceeds the budget, one whose
#        LAST line does, and a 70 KB line at the DEFAULT budget, follow next= with a strict-progress assertion (each
#        call's first line is past the previous call's, the chain ends, and it reassembles the body). A line that
#        alone exceeds the budget is served WHOLE with over_ceiling="1". RED on d4395e7e (next= served itself).
#   (B6) no sub-line fragment: formaxtokenscheck's own fixture (--for --detail=30 --token-budget=800) cut its top
#        body to ONE BYTE under lines="1-1/7"; every truncated body's CDATA must now be exactly the whole lines its
#        lines= names, re-derived from an uncut --expand of the same definition. RED on d4395e7e.
#   (B8) --pack-top-n's cut (serialize.h packSource), the same defect on raw files: a bare `<!-- truncated -->` inside
#        the last file's CDATA was the only trace, files the budget never reached vanished, and the loop kept serving
#        fragments after the cut. Now the first file that does not fit closes the answer, cut at a line end with
#        <src truncated="1" lines="1-K/T">, and <src_cut shown= total= capped="1" budget_bytes=> counts what was not
#        served, both defined by one comment in that document. An uncut answer carries none of it. RED before.
#
# Usage:  test/overbudgetcommentcheck.sh   [ RIPWIRE_BIN=path/to/ripwire ]
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/overbudgetfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }
echo "overbudgetcommentcheck: BIN=$BIN  FIX=$FIX"

# fixture sanity: operator-- is actually captured as a symbol with a "--" in its name
"$BIN" "$FIX" --no-cache 2>/dev/null | grep -q 'n="operator--"' \
    && ok "fixture sanity: operator-- captured as a symbol name" \
    || no "fixture sanity: operator-- not captured (name check)"

# force the omission path: expand bump (fills the budget) then operator-- (over budget → omitted)
OUT="$TMP/out.xml"
"$BIN" "$FIX" --expand=bump,operator-- --pack-budget-bytes=60 --no-cache >"$OUT" 2>/dev/null

# the omission marker for operator-- must be present (proves we hit the over-budget path)
grep -q 'body omitted (over budget): operator-' "$OUT" \
    && ok "over-budget omission marker for operator-- is present" \
    || no "expected over-budget omission marker for operator-- (did the path trigger?)"

# G4: the whole document must be well-formed — the crux of A4-F9 (pre-fix: xmllint rejects the raw '--')
xmllint --noout "$OUT" 2>"$TMP/lint.err" \
    && ok "over-budget comment: passes xmllint --noout (no ill-formed '--' in the comment)" \
    || no "over-budget comment: xmllint FAILED: $( cat "$TMP/lint.err" )"

# the omission COMMENT must carry the collapsed 'operator-', never the raw 'operator--' ('--' is only
# legal elsewhere — e.g. the map's id="…::operator--" attribute, which xmllint already accepted above).
if grep -qF 'body omitted (over budget): operator--' "$OUT"; then
    no "raw 'operator--' ('--' run) survived into the XML comment — collapse did not apply"
else
    ok "omission comment carries the collapsed 'operator-' (no ill-formed '--' run in a comment)"
fi

# ── B arms: a generated fixture (three files) so no committed tree's counts move ─────────────────────────────
BFX="$TMP/bfx"; mkdir -p "$BFX/src"
{
    echo 'int alpha_head( int v )'; echo '{'; echo '    return v + 1;'; echo '}'
    echo 'int beta_tail( int v )'; echo '{'; echo '    int t = 0;'
    for r in 1 2 3 4; do printf '    t += v * %s1; t += v * %s2; t += v * %s3; t += v * %s4; t += v * %s5; t += v * %s6; t += v * %s7;\n' $r $r $r $r $r $r $r; done
    echo '    return t;'; echo '}'
} > "$BFX/src/a_first.cpp"
{
    echo 'int gamma_mid( int v )'; echo '{'; echo '    int t = 0;'
    for r in 1 2 3 4; do printf '    t -= v * %s1; t -= v * %s2; t -= v * %s3; t -= v * %s4; t -= v * %s5; t -= v * %s6; t -= v * %s7;\n' $r $r $r $r $r $r $r; done
    echo '    return t;'; echo '}'
} > "$BFX/src/b_second.cpp"
{
    echo 'int delta_wide( int alpha_parameter_one, int alpha_parameter_two, int alpha_parameter_three, int alpha_parameter_four, int alpha_parameter_five )'
    echo '{'; echo '    return alpha_parameter_one + alpha_parameter_two + alpha_parameter_three;'; echo '}'
} > "$BFX/src/c_long.cpp"
cat > "$TMP/bodies.py" <<'PY'
import sys, re, xml.etree.ElementTree as ET
doc = sys.stdin.read()
root = ET.fromstring( doc )
bs = next( root.iter( "bodies" ), None )
if bs is None:
    print( "NOBODIES" ); sys.exit( 0 )
mode = sys.argv[1]
if mode == "summary":
    names = [ b.attrib["n"] for b in bs.findall( "b" ) ]
    omitted = re.findall( r"<!-- body omitted \(over budget\): (.*?) -->", doc )          # skipped while budget remained
    for tail in re.findall( r"<!-- bodies omitted \(budget spent\): (.*?) -->", doc ):   # met after it was spent, one list
        omitted += tail.split( ", " )
    print( "shown=%s total=%s capped=%s names=%s omitted=%s" % ( bs.attrib.get( "shown" ), bs.attrib.get( "total" ), bs.attrib.get( "capped" ),
           ",".join( names ), ",".join( omitted ) ) )
elif mode == "body":            # the first <b>: its attributes a line each, then its CDATA text
    b = bs.find( "b" )
    for k in ( "lines", "truncated", "next" ):
        print( "%s=%s" % ( k, b.attrib.get( k, "" ) ) )
    sys.stdout.write( "TEXT=" + ( b.text or "" ) )
PY
bsum(){ "$BIN" "$BFX" --no-cache --top-k=0 --legend=full "$@" 2>/dev/null | python3 "$TMP/bodies.py" summary; }

# (B1) rank first: the caller asked for alpha, gamma, beta — in that order
B1="$( bsum --expand=alpha_head,gamma_mid,beta_tail --pack-budget-bytes=500 )"
case "$B1" in
    *"names=alpha_head,gamma_mid omitted=beta_tail"*) ok "(B1) rank first: the budget kept alpha+gamma and named beta ($B1)" ;;
    *) no "(B1) the budget did not follow the caller's order — want alpha_head,gamma_mid kept, beta_tail omitted: $B1" ;;
esac
# presence guard: at a budget holding all three, all three ship (so B1's drop is the budget's, not a resolve miss)
case "$( bsum --expand=alpha_head,gamma_mid,beta_tail --pack-budget-bytes=4000 )" in
    *"shown=3 total=3 capped=0"*) ok "(B1) guard: all three bodies ship when the budget holds them" ;;
    *) no "(B1) guard: the fixture's three bodies do not all ship at 4000 B — B1 measured a resolve miss" ;;
esac

# (B2) never silent: delta's first line alone overruns 100 B, so the cut spends the WHOLE budget
B2="$( bsum --expand=delta_wide,alpha_head --pack-budget-bytes=100 )"
case "$B2" in
    *"shown=1 total=2 capped=1 names=delta_wide omitted=alpha_head") ok "(B2) the body met after the budget was spent is named ($B2)" ;;
    *) no "(B2) a body dropped after the budget was spent is not named (names must equal total - shown): $B2" ;;
esac

# (B3) the truncated body: capped="1", the cut stated outside the CDATA, and next= reassembles it
T1="$( "$BIN" "$BFX" --no-cache --top-k=0 --legend=full --expand=beta_tail --pack-budget-bytes=150 2>/dev/null )"
case "$( printf '%s' "$T1" | python3 "$TMP/bodies.py" summary )" in
    *"shown=1 total=1 capped=1"*) ok "(B3) a truncated body's <bodies> says capped=\"1\"" ;;
    *) no "(B3) a truncated body's <bodies> does not say capped=\"1\": $( printf '%s' "$T1" | grep -o '<bodies [^>]*>' | tail -1 )" ;;
esac
printf '%s' "$T1" | grep -o '<b [^>]*truncated="1"[^>]*>' | grep -q 'lines="1-[0-9]*/[0-9]*".*next="--expand=' \
    && ok "(B3) the <b> carries lines= truncated=\"1\" next= outside the CDATA" \
    || no "(B3) the truncated <b> lacks lines=/truncated=/next= attributes"
printf '%s' "$T1" | grep -qF '<!-- truncated -->' \
    && no "(B3) a '<!-- truncated -->' marker is still written INSIDE the CDATA (paste-back carries it)" \
    || ok "(B3) nothing is appended inside the CDATA"
WHOLE="$( "$BIN" "$BFX" --no-cache --top-k=0 --legend=full --expand=beta_tail 2>/dev/null | python3 "$TMP/bodies.py" body | sed -n '/^TEXT=/,$p' )"
ACC=""; NEXT="--expand=beta_tail"; hops=0
while [ -n "$NEXT" ] && [ "$hops" -lt 20 ]; do
    OUTB="$( "$BIN" "$BFX" --no-cache --top-k=0 --legend=full "$NEXT" --pack-budget-bytes=150 2>/dev/null | python3 "$TMP/bodies.py" body )"
    PART="$( printf '%s\n' "$OUTB" | sed -n '/^TEXT=/,$p' | sed '1s/^TEXT=//' )"
    ACC="${ACC:+$ACC
}$PART"
    NEXT="$( printf '%s\n' "$OUTB" | sed -n 's/^next=//p' )"
    hops=$(( hops + 1 ))
done
if [ "$hops" -lt 2 ]; then
    no "(B3) the 150 B budget did not cut beta_tail at all — the reassembly arm measured nothing"
elif [ "TEXT=$ACC" = "$WHOLE" ]; then
    ok "(B3) following next= at the same budget reassembles the whole body byte for byte ($hops calls)"
else
    no "(B3) the next= chain does not reassemble the body ($hops calls)"
fi

# (B4) determinism + well-formedness of the B documents
for a in "--expand=alpha_head,gamma_mid,beta_tail --pack-budget-bytes=500" "--expand=delta_wide,alpha_head --pack-budget-bytes=100" "--expand=beta_tail --pack-budget-bytes=150"; do
    # shellcheck disable=SC2086
    X1="$( "$BIN" "$BFX" --no-cache --top-k=0 $a 2>/dev/null )"; X2="$( "$BIN" "$BFX" --no-cache --top-k=0 $a 2>/dev/null )"
    [ "$X1" = "$X2" ] || no "(B4) not byte-identical across two runs: $a"
    printf '%s' "$X1" | xmllint --noout - 2>/dev/null || no "(B4) not well-formed: $a"
done
ok "(B4) the B documents are deterministic and well-formed (a failure above names the one that is not)"

# ── B5 / B6 (review M1) ──────────────────────────────────────────────────────────────────────────────────────
LFX="$TMP/lfx"; mkdir -p "$LFX/src"
python3 - "$LFX/src" <<'PY'
import os, sys
d = sys.argv[1]
w = lambda n, t: open( os.path.join( d, n ), "w" ).write( t )
# first line (the signature, a long default argument) 2.6 KB, then 40 short lines
w( "firstlong.c", "int first_long( int a, const char* s = \"" + "x" * 2600 + "\" )\n{\n" + "".join( "    a += %d;\n" % i for i in range( 40 ) ) + "    return a;\n}\n" )
# 30 short lines, then one 1.8 KB line, then the close
w( "lastlong.c", "int last_long( int a )\n{\n" + "".join( "    a += %d;\n" % i for i in range( 30 ) ) + "    const char* t = \"" + "y" * 1800 + "\";\n    return a;\n}\n" )
# a 70 KB line inside a four-line function: it alone exceeds the DEFAULT 64 KB budget
w( "big.js", "function big_table() {\n  const t = [" + ",".join( str( i % 10 ) for i in range( 35000 ) ) + "];\n  return t;\n}\n" )
PY
cat > "$TMP/chain.py" <<'PY'
import re, subprocess, sys, html
BIN, ROOT, SEL, BUDGET = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
def run( sel, budget ):
    a = [ BIN, ROOT, "--no-cache", "--top-k=0", "--legend=full", "--expand=" + sel ] + ( [ "--pack-budget-bytes=" + budget ] if budget else [] )
    out = subprocess.run( a, capture_output=True, timeout=300 ).stdout
    m = re.findall( rb'<b ([^>]*)><!\[CDATA\[(.*?)\]\]>(?:<calls|<note|</b>)', out, re.S )
    if len( m ) != 1:
        print( "FAIL %s: %d bodies" % ( sel, len( m ) ) ); sys.exit( 1 )
    at = dict( ( k.decode(), html.unescape( v.decode() ) ) for k, v in re.findall( rb'(\w+)="([^"]*)"', m[0][0] ) )
    return m[0][1].replace( b']]]]><![CDATA[>', b']]>' ).decode( "utf-8" ), at
whole, wa = run( SEL, "100000000" )
if wa.get( "truncated" ):
    print( "FAIL the uncut reference is itself truncated" ); sys.exit( 1 )
lines = whole.split( "\n" )
parts, sel, prevLo, calls, over = [], SEL, 0, 0, 0
while True:
    calls += 1
    if calls > 40:
        print( "FAIL no progress after 40 calls (last %s)" % sel ); sys.exit( 1 )
    text, at = run( sel, BUDGET )
    over += at.get( "over_ceiling" ) == "1"
    if "lines" in at:
        lo, hi = map( int, at["lines"].split( "/" )[0].split( "-" ) )
        if lo <= prevLo:
            print( "FAIL next= did not advance: lines=%s after a call starting at line %d" % ( at["lines"], prevLo ) ); sys.exit( 1 )
        if text != "\n".join( lines[ lo - 1 : hi ] ):
            print( "FAIL lines=%s but the CDATA is not exactly those whole lines (%d B)" % ( at["lines"], len( text ) ) ); sys.exit( 1 )
        prevLo = lo
    parts.append( text )
    if at.get( "truncated" ) != "1":
        break
    sel = at["next"][ len( "--expand=" ): ]
ok = "\n".join( parts ) == whole
# Every B5 fixture holds one line larger than its budget, so a passing chain needs all three: it reassembles, it
# took more than one call, AND some call served that line whole under over_ceiling="1". Without the last term a
# binary that stopped disclosing the over-ceiling line (or cut it) but still chained would print OK.
print( "%s calls=%d over_ceiling=%d reassembled=%s" % ( "OK" if ok and calls > 1 and over > 0 else "FAIL", calls, over, ok ) )
PY
for spec in "first_long 1000" "last_long 500" "big_table "; do
    set -- $spec
    R="$( python3 "$TMP/chain.py" "$BIN" "$LFX" "$1" "${2:-}" 2>&1 )"
    case "$R" in
        OK*) ok "(B5) $1 @${2:-default} budget: next= strictly advances, whole lines only, reassembles ($R)" ;;
        *)   no "(B5) $1 @${2:-default} budget: $R" ;;
    esac
done
FMX="$TMP/fmx"; mkdir -p "$FMX/src"
for i in $( seq -w 1 30 ); do
    printf '// Process one entry: trim the raw input and normalise it for lane %s.\nexport function processEntry%s( input: string ): string {\n    const trimmed = input.trim();\n    if( trimmed.length === 0 ) {\n        return "";\n    }\n    return trimmed.toLowerCase();\n}\n' "$i" "$i" > "$FMX/src/entry$i.ts"
done
# RE-ANCHORED (lane/lego-charge fix round 4, reported under PROCESS rule 4): at 800 tokens the first --detail body is now
# reserved a floor out of the sig claim and ships WHOLE (a 7-line body under a quarter of the budget), so the 800 run no
# longer cuts anything and this arm measured nothing there. The property is unchanged — every truncated body is exactly
# its whole lines — and is asserted at 300 tokens, where the floor (a quarter of the budget) is below the body and cuts
# it; the 800 run is kept as a twin below asserting its first body is served whole, byte for byte.
"$BIN" "$FMX" --no-cache --for="processEntry input trim" --detail=30 --token-budget=300 --legend=full > "$TMP/fmx.xml" 2>/dev/null
"$BIN" "$FMX" --no-cache --for="processEntry input trim" --detail=30 --token-budget=800 --legend=full > "$TMP/fmx800.xml" 2>/dev/null
B6="$( python3 - "$TMP/fmx.xml" "$BIN" "$FMX" <<'PY'
import re, subprocess, sys, html
doc = open( sys.argv[1], "rb" ).read()
cut = [ ( dict( ( k.decode(), html.unescape( v.decode() ) ) for k, v in re.findall( rb'(\w+)="([^"]*)"', a ) ), t.decode() )
        for a, t in re.findall( rb'<b ([^>]*truncated="1"[^>]*)><!\[CDATA\[(.*?)\]\]>', doc, re.S ) ]
if not cut:
    print( "FAIL no truncated body — the arm measures nothing" ); sys.exit( 0 )
for at, text in cut:
    out = subprocess.run( [ sys.argv[2], sys.argv[3], "--no-cache", "--top-k=0", "--legend=full", "--expand=%s:%s:%s" % ( at["p"], at["l"], at["n"] ) ],
                          capture_output=True, timeout=300 ).stdout
    # anchored on the <b> element: the full legend itself quotes the literal "<![CDATA[" (the ]]> split rule)
    whole = re.search( rb'<b [^>]*><!\[CDATA\[(.*?)\]\]>(?:<calls|<note|</b>)', out, re.S ).group( 1 ).replace( b']]]]><![CDATA[>', b']]>' ).decode()
    lo, hi = map( int, at["lines"].split( "/" )[0].split( "-" ) )
    if text != "\n".join( whole.split( "\n" )[ lo - 1 : hi ] ):
        print( "FAIL %s lines=%s serves %d B, not those whole lines" % ( at["n"], at["lines"], len( text ) ) ); sys.exit( 0 )
print( "OK %d truncated body(ies), each exactly its whole lines%s" % ( len( cut ), " (over_ceiling)" if any( a.get( "over_ceiling" ) == "1" for a, _ in cut ) else "" ) )
PY
)"
case "$B6" in OK*) ok "(B6) formaxtokens fixture @300: $B6" ;; *) no "(B6) formaxtokens fixture @300: $B6" ;; esac
# (B6 twin @800) the old operating point: the first body is served whole (no truncated=, no over_ceiling=), byte-identical
# to an uncut --expand of the same definition.
B6W="$( python3 - "$TMP/fmx800.xml" "$BIN" "$FMX" <<'PY'
import re, subprocess, sys, html
doc = open( sys.argv[1], "rb" ).read()
m = re.search( rb'<b ([^>]*)><!\[CDATA\[(.*?)\]\]>', doc, re.S )
if not m:
    print( "FAIL no body at all" ); sys.exit( 0 )
at = dict( ( k.decode(), html.unescape( v.decode() ) ) for k, v in re.findall( rb'(\w+)="([^"]*)"', m.group( 1 ) ) )
if "truncated" in at or "over_ceiling" in at:
    print( "FAIL first body cut: %s" % m.group( 1 ).decode() ); sys.exit( 0 )
out = subprocess.run( [ sys.argv[2], sys.argv[3], "--no-cache", "--top-k=0", "--legend=full", "--expand=%s:%s:%s" % ( at["p"], at["l"], at["n"] ) ],
                      capture_output=True, timeout=300 ).stdout
whole = re.search( rb'<b [^>]*><!\[CDATA\[(.*?)\]\]>(?:<calls|<note|</b>)', out, re.S ).group( 1 )
print( "OK %s served whole (%d B)" % ( at["n"], len( whole ) ) if m.group( 2 ) == whole else "FAIL %s differs from its --expand" % at["n"] )
PY
)"
case "$B6W" in OK*) ok "(B6 twin @800) $B6W" ;; *) no "(B6 twin @800) $B6W" ;; esac
if xmllint --noout "$TMP/fmx.xml" 2>/dev/null; then
    ok "(B6) the document is well-formed"
else
    no "(B6) the document is not well-formed"
fi

# ── (B7) lane B review N5 (cut-fix E): a multi-line body exactly budget+1 bytes whose last byte is its closing newline
# fits once that terminator goes, so it is served whole and inside the budget, with no over_ceiling="1" (whose reading
# is "its first line alone exceeds the budget", false here: the first line is `## Alpha`). RED on 9936ba4e.
N5="$TMP/n5"; mkdir -p "$N5"
python3 - "$N5" <<'PY'
import os, sys
lines = [ "## Alpha" ] + [ "line %02d of the alpha section text" % i for i in range( 1, 33 ) ]
open( os.path.join( sys.argv[1], "doc.md" ), "w" ).write( "\n".join( lines ) + "\n" )
PY
N5SZ="$( wc -c <"$N5/doc.md" | tr -d ' ' )"
"$BIN" "$N5" --expand=Alpha --top-k=0 --pack-budget-bytes=$(( N5SZ - 1 )) --no-cache >"$TMP/n5.xml" 2>/dev/null
N5B="$( grep -o '<b t="sec"[^>]*>' "$TMP/n5.xml" )"
# "served whole" is checked on the BODY, not only on the tag: the section's CDATA must be the file's text less its
# closing newline, so an answer that drops the last lines without saying so fails even with a clean tag.
N5W="$( python3 - "$TMP/n5.xml" "$N5/doc.md" <<'PY'
import re, sys
doc = open( sys.argv[1], "rb" ).read()
m = re.search( rb'<b t="sec"[^>]*><!\[CDATA\[(.*?)\]\]></b>', doc, re.S )
want = open( sys.argv[2], "rb" ).read()
if m is None:
    print( "FAIL no <b t=\"sec\"> body" ); sys.exit( 0 )
got = m.group( 1 ).replace( b']]]]><![CDATA[>', b']]>' )
print( "OK" if got == want[ :-1 ] else "FAIL body is %d B, want the whole %d B less its newline; ends %r" % ( len( got ), len( want ) - 1, got[ -40: ] ) )
PY
)"
case "$N5B" in
    *over_ceiling*|*truncated*|'') no "(B7) a $N5SZ-byte section at budget $(( N5SZ - 1 )) reads over_ceiling/truncated: $N5B" ;;
    *) case "$N5W" in
           OK) ok "(B7) a $N5SZ-byte section ending in its newline at budget $(( N5SZ - 1 )) is served whole (body = the file less its newline), no over_ceiling=" ;;
           *)  no "(B7) the $N5SZ-byte section's tag is clean but its body is not the whole section: $N5W" ;;
       esac ;;
esac

# ── (B8) --pack-top-n: the cut is stated, and nothing is served after it ─────────────────────────────────────
PT="$TMP/packtop"; mkdir -p "$PT"
for f in a b c d; do
    { printf 'int %s_entry( int x )\n{\n    return %s_helper( x );\n}\n' "$f" "$f"
      i=0; while [ $i -lt 40 ]; do printf 'int %s_helper%d( int x ) { return x + %d; }\n' "$f" $i $i; i=$(( i + 1 )); done
      printf 'int %s_helper( int x ) { return x; }\n' "$f"; } >"$PT/$f.c"
done
FSZ="$( wc -c <"$PT/a.c" | tr -d ' ' )"
PB=$(( FSZ + FSZ / 2 ))                                   # one whole file and half of the next
"$BIN" "$PT" --pack-top-n=4 --pack-budget-bytes=$PB --no-cache >"$TMP/pt.xml" 2>/dev/null
"$BIN" "$PT" --pack-top-n=4 --no-cache >"$TMP/pt_whole.xml" 2>/dev/null
PT_SRC="$( grep -oE '<src p="[^"]*"[^>]*>' "$TMP/pt.xml" )"
PT_N="$( printf '%s\n' "$PT_SRC" | grep -c '<src ' )"
grep -qF '<!-- truncated -->' "$TMP/pt.xml" \
    && no "(B8) a '<!-- truncated -->' marker is still written inside a --pack-top-n CDATA" \
    || ok "(B8) no '<!-- truncated -->' marker inside the --pack-top-n CDATA"
[ "$PT_N" = 2 ] && printf '%s\n' "$PT_SRC" | tail -1 | grep -qE ' truncated="1" lines="1-[0-9]+/[0-9]+"' \
    && ok "(B8) two files served, the second cut at a line end: $( printf '%s\n' "$PT_SRC" | tail -1 )" \
    || no "(B8) want 2 <src>, the last with truncated=\"1\" lines=\"1-K/T\"; got $PT_N: $PT_SRC"
grep -qE '<src_cut shown="2" total="4" capped="1" budget_bytes="'"$PB"'"/>' "$TMP/pt.xml" \
    && ok "(B8) <src_cut shown=\"2\" total=\"4\" capped=\"1\" budget_bytes=\"$PB\"/> counts the two files not served" \
    || no "(B8) no <src_cut shown=\"2\" total=\"4\" capped=\"1\"> disclosure: $( grep -oE '<src_cut[^>]*>' "$TMP/pt.xml" )"
"$BIN" "$PT" --pack-top-n=4 --pack-budget-bytes=$PB --no-cache --legend=full >"$TMP/pt_full.xml" 2>/dev/null
grep -qE '<!-- src_cut: shown= [^>]*budget_bytes=[^>]*truncated=[^>]*lines=' "$TMP/pt_full.xml" \
    && ok "(B8) full dialect: one comment in the document defines shown=/total=/capped=/budget_bytes=/truncated=/lines=" \
    || no "(B8) full dialect: the cut's attributes ride with no definition in the document"
LEAD="$( sed -E 's/(-->)<[^!].*/\1/' "$TMP/pt.xml" | head -c 20000 )"
printf '%s' "$LEAD" | grep -q 'src truncated=1 lines=1-K/T' && printf '%s' "$LEAD" | grep -q 'budget_bytes=' \
    && ok "(B8) default (compact) dialect: the leading legend defines truncated=/lines= and src_cut's budget_bytes=" \
    || no "(B8) default dialect: the leading legend does not define the cut's attributes"
if xmllint --noout "$TMP/pt.xml" 2>/dev/null; then ok "(B8) the cut document is well-formed"; else no "(B8) the cut document is not well-formed"; fi
if grep -qE 'src_cut|truncated=' "$TMP/pt_whole.xml"; then no "(B8) an uncut --pack-top-n answer carries cut disclosure"
else ok "(B8) an uncut --pack-top-n answer carries no cut disclosure (4 whole files: $( grep -c '<src ' "$TMP/pt_whole.xml" | tr -d ' ' ) <src>)"; fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
