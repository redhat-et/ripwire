#!/usr/bin/env bash
# readabilitycheck.sh — the golden gate for `--readability` (the Posnett/Hindle/Devanbu MSR 2011 lens).
#
# WHY A GOLDEN AND NOT A RE-IMPLEMENTATION. A ranking, a token count and a closed-form score all look
# plausible whether or not they are correct (CLAUDE.md non-negotiable #1). A python mirror of the same
# tokenizer inside this gate would reproduce the C++ tokenizer's bugs verbatim and pass on both, so the
# expected numbers below are HAND-DERIVED from the fixture, token by token, and written out here in full.
# Anyone changing the tokenizer has to re-derive them by hand too — that is the point of the derivation
# comment, not decoration.
#
# THE DERIVATION (span = the whole definition [sigStartByte, endByte); L = the definition's line span).
#
#   int add( int a, int b )            tokens, in order:
#   {                                    int add ( int a , int b ) { return a + b ; }
#       return a + b;                  N (toks)  = 16
#   }                                  operators = int ( int , int ) { return + ; }        -> 11   (ops=)
#                                      operands  = add a b a b                             ->  5
#                                      distinct  = int add ( a , b ) { return + ; }        -> 12   (vocab=)
#                                      V = 16 * log2(12)  = 16 * 3.5849625 = 57.359400
#                                      freqs: int 3 | a 2 | b 2 | 9 singletons
#                                      E = 3/16*log2(16/3) + 2*(2/16*3) + 9*(1/16*4) = 3.452820 bits
#                                      L = 4 lines
#                                      z = 8.87 - 0.033*57.3594 + 0.40*4 - 1.5*3.4528195 = 3.397911
#                                      P = sigmoid(z) = 0.967643
#
#   int mix( int a, int b, int c )     N (toks)  = 49   (12 signature + 1 brace + 35 return-stmt + 1 brace)
#   {                                  operands  = mix + a*4 + b*4 + c*3 + 1*2 + 3 + 2         -> 16
#       return ( a * b + c ) / ...     operators = 49 - 16                                     -> 33   (ops=)
#   }                                  distinct  = 22   (vocab=)  [<< and >> are ONE token each: maximal munch]
#                                      V = 49 * log2(22) = 49 * 4.4594316 = 218.512149
#                                      freqs: ( 6 | ) 6 | int 4 | a 4 | b 4 | c 3 | + 3
#                                             | , 2 | * 2 | - 2 | 1 2 | 11 singletons
#                                      E = log2(49) - (sum f*log2 f)/49 = 5.6147098 - 72.529325/49 = 4.134418
#                                      L = 4 lines
#                                      z = 8.87 - 0.033*218.5121 + 0.40*4 - 1.5*4.1344175 = -2.942522
#                                      P = sigmoid(z) = 0.050091
#
# FLOATS ARE ASSERTED AS A TOLERANCE BAND, never bit-exactly (CONTRIBUTING.md §3, "Tests"). The band is
# half of the last PRINTED digit plus a margin — vol prints 1 decimal (band 0.06), ent 2 (band 0.006),
# posnett 3 (band 0.0006). The INTEGER columns (lines/toks/ops/vocab) have no tolerance band and are
# compared exactly; so is the RANK ORDER, which a band cannot express either.
#
# Arms:
#   (A) determinism  — two --no-cache runs are byte-identical
#   (B) golden       — every column of both functions, against the hand-derivation above
#   (C) order        — the report is LEAST readable first (mix before add)
#   (D) mutation     — the SAME assertions run against a mutated fixture must go RED, proving (B) can see
#                      a wrong number at all
#   (E) paging       — limit=1 discloses shown/capped/total/has_more/next_offset per pageview.h
#   (F) additive     — `--readability` changes nothing about the flagless map (G5)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
MUTANT="$TMP/mutant"
mkdir -p "$FIXTURE" "$MUTANT"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "readabilitycheck: BIN=$BIN"

cat >"$FIXTURE/read.c" <<'CPP'
int add( int a, int b )
{
    return a + b;
}

int mix( int a, int b, int c )
{
    return ( a * b + c ) / ( a - b + 1 ) * ( c % 3 ) + ( a << 2 ) - ( b >> 1 );
}
CPP

# The mutant differs from the fixture in ONE function body — `add` gains a local and a line, so its
# lines/toks/vocab/vol/ent/posnett all move. Arm (D) reruns arm (B)'s expectations against it.
cat >"$MUTANT/read.c" <<'CPP'
int add( int a, int b )
{
    int t = a + b;
    return t;
}

int mix( int a, int b, int c )
{
    return ( a * b + c ) / ( a - b + 1 ) * ( c % 3 ) + ( a << 2 ) - ( b >> 1 );
}
CPP

# ── (A) determinism ────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIXTURE" --readability --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIXTURE" --readability --no-cache >"$TMP/b" 2>/dev/null
if [ ! -s "$TMP/a" ]; then
    no "(A) --readability produced NO output on the fixture — an empty baseline is not a passing determinism run"
elif cmp -s "$TMP/a" "$TMP/b"; then
    ok "(A) two --no-cache runs are byte-identical"
else
    no "(A) --readability is not deterministic across two identical runs"
fi

"$BIN" "$MUTANT" --readability --no-cache >"$TMP/m" 2>/dev/null

# ── (B) + (C) + (D) the golden, its order, and its mutation control ───────────────────────────────────
python3 - "$TMP/a" "$TMP/m" <<'PY'
import sys, xml.etree.ElementTree as ET

# HAND-DERIVED — see the derivation block at the top of this file before touching a number here.
GOLD = {
    "add": dict( lines = 4, toks = 16, ops = 11, vocab = 12, vol = 57.359400, ent = 3.452820, posnett = 0.967643 ),
    "mix": dict( lines = 4, toks = 49, ops = 33, vocab = 22, vol = 218.512149, ent = 4.134418, posnett = 0.050091 ),
}
# half the last printed digit, plus margin: vol prints %.1f, ent %.2f, posnett %.3f
BAND = { "vol": 0.06, "ent": 0.006, "posnett": 0.0006 }
INTS = ( "lines", "toks", "ops", "vocab" )

def rowsOf( path ):
    root = ET.parse( path ).getroot()
    return root, [ node for node in root.findall( "fn" ) ]

def audit( path, label ):
    """Returns the list of complaints; empty == the golden holds."""
    root, rows = rowsOf( path )
    bad = []
    byName = { node.get( "n" ): node for node in rows }
    if sorted( byName ) != sorted( GOLD ):
        bad.append( f"{label}: expected functions {sorted(GOLD)}, got {sorted(byName)}" )
        return bad, root, rows
    for name, want in GOLD.items():
        node = byName[ name ]
        for key in INTS:
            got = node.get( key )
            if got is None or int( got ) != want[ key ]:
                bad.append( f"{label}: {name}@{key} expected {want[key]}, got {got}" )
        for key, band in BAND.items():
            got = node.get( key )
            if got is None or abs( float( got ) - want[ key ] ) > band:
                bad.append( f"{label}: {name}@{key} expected {want[key]:.6f} +/- {band}, got {got}" )
    return bad, root, rows

bad, root, rows = audit( sys.argv[1], "golden" )
for line in bad:
    print( "  FAIL  (B) " + line )
if not bad:
    print( "  PASS  (B) every column of add/mix matches the hand-derivation (ints exact, floats in band)" )

# (C) least readable FIRST — mix (P=0.050) must precede add (P=0.968), and the printed order must be
#     monotone non-decreasing in posnett for every adjacent pair.
order = [ node.get( "n" ) for node in rows ]
scores = [ float( node.get( "posnett" ) ) for node in rows ]
if order != [ "mix", "add" ]:
    print( f"  FAIL  (C) expected least-readable-first order ['mix', 'add'], got {order}" )
    bad.append( "order" )
elif any( scores[i] > scores[i + 1] + 1e-12 for i in range( len( scores ) - 1 ) ):
    print( f"  FAIL  (C) posnett is not non-decreasing down the rows: {scores}" )
    bad.append( "order" )
else:
    print( "  PASS  (C) rows are ranked least readable first (mix before add)" )

# root honesty: functions= is the measured total and matches the rows on an uncapped run
if root.get( "functions" ) != str( len( rows ) ):
    print( f"  FAIL  (B) root functions={root.get('functions')} disagrees with {len(rows)} emitted rows" )
    bad.append( "functions" )

# (D) MUTATION CONTROL — the identical audit against the mutated fixture MUST fail, or arm (B) is
#     asserting nothing. A gate that cannot go red is not a gate.
mutantBad, _, _ = audit( sys.argv[2], "mutant" )
if mutantBad:
    print( f"  PASS  (D) mutation control: the same expectations go RED on a one-line body edit ({len(mutantBad)} mismatch(es))" )
else:
    print( "  FAIL  (D) mutation control: the mutated fixture still satisfies the golden — arm (B) proves nothing" )
    bad.append( "mutation" )

raise SystemExit( 1 if bad else 0 )
PY
[ $? -eq 0 ] || fail=1

# ── (E) paging disclosure (src/pageview.h, THE TRUNCATION VOCABULARY) ─────────────────────────────────
page="$( "$BIN" "$FIXTURE" --readability --limit=1 --no-cache 2>/dev/null | grep -o '<readability [^>]*>' | head -1 )"
pageRows="$( "$BIN" "$FIXTURE" --readability --limit=1 --no-cache 2>/dev/null | grep -c '<fn ' )"
wantAttrs='shown="1" capped="1" total="2" has_more="1" next_offset="1"'
if [ "$pageRows" != "1" ]; then
    no "(E) limit=1 emitted $pageRows row(s), expected 1"
elif printf '%s' "$page" | grep -q "$wantAttrs"; then
    ok "(E) limit=1 discloses $wantAttrs"
else
    no "(E) limit=1 root element lacks '$wantAttrs': $page"
fi

# ── (F) purely additive (G5): the flagless map is untouched by the new code path ───────────────────────
"$BIN" "$FIXTURE" --no-cache >"$TMP/map1" 2>/dev/null
"$BIN" "$FIXTURE" --readability --no-cache >/dev/null 2>&1
"$BIN" "$FIXTURE" --no-cache >"$TMP/map2" 2>/dev/null
if cmp -s "$TMP/map1" "$TMP/map2" && ! grep -q 'posnett=' "$TMP/map1"; then
    ok "(F) the flagless map is unchanged and carries no readability attribute"
else
    no "(F) the flagless map is not additive-clean (differs across runs, or leaks posnett=)"
fi

# ── §L10: the SATURATION disclosure — on a real, large corpus (this repo's own source), several of the
# least-readable head rows genuinely print posnett="0.000" alike (the sigmoid has run out of visible
# precision at 3 decimals for a high-volume function). The legend must say so, AND the ORDER must still be
# real: among the saturated rows, vol= (the documented tie-break) must be non-increasing — proof the ranking
# did not collapse into an arbitrary/ID-order tie just because P itself is illegible.
REAL_OUT="$( "$BIN" "$ROOT" --readability --limit=10 --no-cache 2>/dev/null )"
printf '%s' "$REAL_OUT" | grep -q 'sigmoid SATURATES at the least-readable extreme' \
    && ok "(G) legend discloses sigmoid saturation at the least-readable extreme" \
    || no "(G) legend does not disclose sigmoid saturation"
printf '%s' "$REAL_OUT" | grep -q 'ties (and every tie) break by vol= descending' \
    && ok "(G) legend states the tie-break (vol= descending)" \
    || no "(G) legend does not state the tie-break"
# One <fn ...> tag per line (minified single-line XML otherwise), so each saturated row's own vol= can be
# read in the SAME order the tool emitted the rows — exactly the technique test/mergescoutcheck.sh uses to
# isolate one element's own attributes from its neighbours on the same line.
FN_LINES="$( printf '%s' "$REAL_OUT" | sed 's/<fn /\n<fn /g' | grep '^<fn ' )"
ZERO_LINES="$( printf '%s\n' "$FN_LINES" | grep 'posnett="0\.000"' )"
ZERO_ROWS="$( printf '%s\n' "$ZERO_LINES" | grep -c '^<fn ' )"
if [ "$ZERO_ROWS" -ge 2 ]; then
    ok "(G) reproduced the saturation on this repo's own corpus: $ZERO_ROWS head rows read posnett=\"0.000\""
    VOLS="$( printf '%s\n' "$ZERO_LINES" | grep -oE 'vol="[0-9.]+"' | grep -oE '[0-9.]+' )"
    SORTED_DESC="$( printf '%s\n' "$VOLS" | sort -rn )"
    [ "$VOLS" = "$SORTED_DESC" ] \
        && ok "(G) among the saturated (posnett=\"0.000\") rows, vol= is still non-increasing — the order is real" \
        || no "(G) among the saturated rows, vol= is NOT non-increasing: got [$( printf '%s' "$VOLS" | tr '\n' ' ' )], want [$( printf '%s' "$SORTED_DESC" | tr '\n' ' ' )]"
else
    ok "(G) fewer than 2 saturated rows in this run (SKIP — the corpus/build moved; not this gate's contract to pin the exact count)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "readabilitycheck: FAILURES ABOVE"
exit "$fail"
