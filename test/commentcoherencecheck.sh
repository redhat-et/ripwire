#!/usr/bin/env bash
# commentcoherencecheck.sh — the golden gate for `--comment-coherence` (Steidl c_coeff, ICPC 2013 +
# Scalabrino CIC, ICPC 2016/JSEP 2018).
#
# WHY A GOLDEN AND NOT A RE-IMPLEMENTATION. A fraction, a Jaccard ratio and a term count all look
# plausible whether or not they are correct (CLAUDE.md non-negotiable #1). The expected numbers below
# are HAND-DERIVED from the fixture, token by token, against the SAME substrate the binary uses
# (naminglens::splitIdentifier's case/digit-boundary split, its bounded Levenshtein, and this file's own
# fixed stopword list) — written out in full so anyone changing the tokenizer or the stopword list has to
# re-derive them by hand too.
#
# THE DERIVATION.
#
#   // compute total                    name computeTotal -> split -> [compute, total]
#   int computeTotal( int a, int b )    comment "compute total" -> split -> [compute, total]  (words=2)
#   { return a + b; }                   BOTH comment words match a name word (distance 0)     -> restate=2
#                                        c_coeff = 2/2 = 1.000                                  <<< restates the name
#                                        comment terms (stopword-drop+dedupe): {compute, total}          -> c_terms=2
#                                        id terms: identifiers in [sig,end) are computeTotal,a,b,a,b;
#                                          split+lower -> compute,total,a,b (x2); "a" is a stopword (drop);
#                                          dedupe -> {b, compute, total}                                 -> i_terms=3
#                                        shared = {compute, total}                                       -> shared=2
#                                        cic = shared/(c_terms+i_terms-shared) = 2/(2+3-2) = 2/3 = 0.667
#
#   // clamps value into configured     name computeTotal2 -> split -> [compute, total, 2]
#   // range                            comment "clamps value into configured range" -> split ->
#   int computeTotal2( int a, int b )     [clamps, value, into, configured, range]              (words=5)
#   { return a + b; }                   NONE is within edit-distance<2 of compute/total/2       -> restate=0
#                                        c_coeff = 0/5 = 0.000                                    <<< adds real info
#                                        comment terms: "into" is a stopword, drop it ->
#                                          {clamps, configured, range, value}                            -> c_terms=4
#                                        id terms: computeTotal2,a,b,a,b -> split+lower -> compute,total,2,a,b;
#                                          drop stopword "a"; dedupe -> {2, b, compute, total}            -> i_terms=4
#                                        shared = {} (no overlap)                                         -> shared=0
#                                        cic = 0/(4+4-0) = 0.000
#
#   int noComment( int a, int b )       NO doc comment directly above the definition -> UNAVAILABLE,
#   { return a + b; }                   never scored, never emitted as a row; counted in no_comment=
#
# FLOATS ARE ASSERTED AS A TOLERANCE BAND (CONTRIBUTING.md §3): both print %.3f, band 0.0006. Integer
# columns (words/restate/c_terms/i_terms/shared) are exact. So is documented=/no_comment=/the rank order.
#
# Arms:
#   (A) determinism  — two --no-cache runs are byte-identical
#   (B) golden       — every column of both documented functions, against the hand-derivation above
#   (C) UNAVAILABLE  — noComment (no doc comment) never appears as a row, and no_comment>=1
#   (D) order        — MOST NAME-RESTATING FIRST (computeTotal before computeTotal2)
#   (E) mutation     — the SAME assertions run against a mutated fixture must go RED
#   (F) paging       — limit=1 discloses shown/capped/total/has_more/next_offset per pageview.h
#   (G) additive     — `--comment-coherence` changes nothing about the flagless map (G5)

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
echo "commentcoherencecheck: BIN=$BIN"

cat >"$FIXTURE/cc.c" <<'CPP'
// compute total
int computeTotal( int a, int b )
{
    return a + b;
}

// clamps value into configured range
int computeTotal2( int a, int b )
{
    return a + b;
}

int noComment( int a, int b )
{
    return a + b;
}
CPP

# The mutant differs from the fixture in ONE comment — computeTotal gains a THIRD comment word ("value")
# that does not match either name word, so words/restate/c_coeff all move but computeTotal2 and
# noComment are untouched. Arm (E) reruns arm (B)'s expectations against it.
cat >"$MUTANT/cc.c" <<'CPP'
// compute total value
int computeTotal( int a, int b )
{
    return a + b;
}

// clamps value into configured range
int computeTotal2( int a, int b )
{
    return a + b;
}

int noComment( int a, int b )
{
    return a + b;
}
CPP

# ── (A) determinism ────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIXTURE" --comment-coherence --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIXTURE" --comment-coherence --no-cache >"$TMP/b" 2>/dev/null
if [ ! -s "$TMP/a" ]; then
    no "(A) --comment-coherence produced NO output on the fixture — an empty baseline is not a passing determinism run"
elif cmp -s "$TMP/a" "$TMP/b"; then
    ok "(A) two --no-cache runs are byte-identical"
else
    no "(A) --comment-coherence is not deterministic across two identical runs"
fi

"$BIN" "$MUTANT" --comment-coherence --no-cache >"$TMP/m" 2>/dev/null

# ── (B) + (C) + (D) + (E) the golden, UNAVAILABLE, order, and the mutation control ───────────────────
python3 - "$TMP/a" "$TMP/m" <<'PY'
import sys, xml.etree.ElementTree as ET

# HAND-DERIVED — see the derivation block at the top of this file before touching a number here.
GOLD = {
    "computeTotal":  dict( c_coeff = 1.000, words = 2, restate = 2, cic = 0.667, c_terms = 2, i_terms = 3, shared = 2 ),
    "computeTotal2": dict( c_coeff = 0.000, words = 5, restate = 0, cic = 0.000, c_terms = 4, i_terms = 4, shared = 0 ),
}
BAND = { "c_coeff": 0.0006, "cic": 0.0006 }
INTS = ( "words", "restate", "c_terms", "i_terms", "shared" )

def rowsOf( path ):
    root = ET.parse( path ).getroot()
    return root, [ node for node in root.findall( "fn" ) ]

def audit( path, label ):
    """Returns the list of complaints; empty == the golden holds."""
    root, rows = rowsOf( path )
    bad = []
    byName = { node.get( "n" ): node for node in rows }
    # (C) UNAVAILABLE — noComment must NEVER appear as a row.
    if "noComment" in byName:
        bad.append( f"{label}: noComment (no doc comment) was emitted as a row — must be UNAVAILABLE" )
    if sorted( byName ) != sorted( GOLD ):
        bad.append( f"{label}: expected documented functions {sorted(GOLD)}, got {sorted(byName)}" )
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
    print( "  FAIL  (B)/(C) " + line )
if not bad:
    print( "  PASS  (B) every column of computeTotal/computeTotal2 matches the hand-derivation (ints exact, floats in band)" )
    print( "  PASS  (C) noComment never appears as a row (UNAVAILABLE, not scored)" )

# root honesty: documented= is the measured total and matches the rows; no_comment>=1 (noComment itself)
if root.get( "documented" ) != str( len( rows ) ):
    print( f"  FAIL  (B) root documented={root.get('documented')} disagrees with {len(rows)} emitted rows" )
    bad.append( "documented" )
noComment = int( root.get( "no_comment", "-1" ) )
if noComment < 1:
    print( f"  FAIL  (C) root no_comment={root.get('no_comment')} — expected >=1 (noComment has no doc comment)" )
    bad.append( "no_comment" )
else:
    print( f"  PASS  (C) root discloses no_comment={noComment} (>=1, covers the undocumented symbol)" )

# (D) MOST NAME-RESTATING FIRST — computeTotal (c_coeff=1.000) must precede computeTotal2 (c_coeff=0.000).
order = [ node.get( "n" ) for node in rows ]
coeffs = [ float( node.get( "c_coeff" ) ) for node in rows ]
if order != [ "computeTotal", "computeTotal2" ]:
    print( f"  FAIL  (D) expected most-name-restating-first order ['computeTotal', 'computeTotal2'], got {order}" )
    bad.append( "order" )
elif any( coeffs[i] < coeffs[i + 1] - 1e-12 for i in range( len( coeffs ) - 1 ) ):
    print( f"  FAIL  (D) c_coeff is not non-increasing down the rows: {coeffs}" )
    bad.append( "order" )
else:
    print( "  PASS  (D) rows are ranked most-name-restating first (computeTotal before computeTotal2)" )

# (E) MUTATION CONTROL — the identical audit against the mutated fixture MUST fail on computeTotal's
#     numbers (words/restate/c_coeff all move when "value" is added to its comment), or arm (B) is
#     asserting nothing. A gate that cannot go red is not a gate.
mutantBad, _, _ = audit( sys.argv[2], "mutant" )
if mutantBad:
    print( f"  PASS  (E) mutation control: the same expectations go RED on a one-word comment edit ({len(mutantBad)} mismatch(es))" )
else:
    print( "  FAIL  (E) mutation control: the mutated fixture still satisfies the golden — arm (B) proves nothing" )
    bad.append( "mutation" )

raise SystemExit( 1 if bad else 0 )
PY
[ $? -eq 0 ] || fail=1

# ── (F) paging disclosure (src/pageview.h, THE TRUNCATION VOCABULARY) ─────────────────────────────────
page="$( "$BIN" "$FIXTURE" --comment-coherence --limit=1 --no-cache 2>/dev/null | grep -o '<comment_coherence [^>]*>' | head -1 )"
pageRows="$( "$BIN" "$FIXTURE" --comment-coherence --limit=1 --no-cache 2>/dev/null | grep -c '<fn ' )"
wantAttrs='shown="1" capped="1" total="2" has_more="1" next_offset="1"'
if [ "$pageRows" != "1" ]; then
    no "(F) limit=1 emitted $pageRows row(s), expected 1"
elif printf '%s' "$page" | grep -q "$wantAttrs"; then
    ok "(F) limit=1 discloses $wantAttrs"
else
    no "(F) limit=1 root element lacks '$wantAttrs': $page"
fi

# ── (G) purely additive (G5): the flagless map is untouched by the new code path ──────────────────────
"$BIN" "$FIXTURE" --no-cache >"$TMP/map1" 2>/dev/null
"$BIN" "$FIXTURE" --comment-coherence --no-cache >/dev/null 2>&1
"$BIN" "$FIXTURE" --no-cache >"$TMP/map2" 2>/dev/null
if cmp -s "$TMP/map1" "$TMP/map2" && ! grep -q 'c_coeff=' "$TMP/map1"; then
    ok "(G) the flagless map is unchanged and carries no comment-coherence attribute"
else
    no "(G) the flagless map is not additive-clean (differs across runs, or leaks c_coeff=)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "commentcoherencecheck: FAILURES ABOVE"
exit "$fail"
