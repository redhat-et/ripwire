#!/usr/bin/env bash
# contextratiocheck.sh — the golden gate for `--context-ratio` (the LOCAL-REASONING lens).
#
# WHY A GOLDEN AND NOT A RE-IMPLEMENTATION. A count of "entities you must resolve", a file split and a
# token weight all look plausible whether or not they are correct (CLAUDE.md non-negotiable #1). A python
# mirror of the same resolver inside this gate would reproduce the C++ resolver's bugs verbatim and pass on
# both, so every number below is HAND-DERIVED from a three-file fixture and written out here in full.
# Anyone changing the reference scan, the resolver or the token rate has to re-derive them by hand too.
#
# ── THE FIXTURE ────────────────────────────────────────────────────────────────────────────────────────
#   local.cpp   class Shared {};                      (16 bytes of definition)
#               int helperOne( int a )  { return a + 1; }
#               int helperTwo( int a )  { return a * 2; }
#               int allLocal( int x )   { return helperTwo( helperOne( x ) ); }
#   remote.cpp  int siblingHere( int a ) { ...nine lines of t arithmetic... }
#               int mostlyRemote( int x ) { return helperOne(x) + helperTwo(x) + siblingHere(x); }
#   holder.cpp  class Holder : public Shared { Shared m_a; };
#
# ── THE DERIVATION, part 1: DEFINITION SPANS (what a reader must actually READ) ────────────────────────
# The span is the whole definition [sigStartByte, endByte) — byte-for-byte what `--expand` prints. Tokens
# are serialize.h's ONE body conversion, tokensForEmittedBytes( bytes, kBytesPerTokenBody=3.80 ), rounded
# to nearest. Counted by hand off the fixture text below, character by character:
#
#   Shared        "class Shared" 12 +NL, "{" 1 +NL, "}" 1                       =  16 B -> round(4.21) =  4
#   helperOne     "int helperOne( int a )" 22 +NL, "{" +NL, "    return a + 1;" 17 +NL, "}"
#                                                                               =  44 B -> round(11.58)= 12
#   helperTwo     same shape as helperOne                                        =  44 B ->             = 12
#   allLocal      22+1 + 1+1 + 39+1 + 1                                          =  65 B -> round(17.11)= 17
#   siblingHere   24+1 + 1+1 + 14+1 + 8*(14+1) + 13+1 + 1                        = 177 B -> round(46.58)= 47
#   mostlyRemote  25+1 + 1+1 + 62+1 + 1                                          =  92 B -> round(24.21)= 24
#   Holder        28+1 + 1+1 + 15+1 + 1                                          =  48 B -> round(12.63)= 13
#
# ── THE DERIVATION, part 2: REFERENCE SITES (what the lens scans) ──────────────────────────────────────
# Every outgoing reference attributed to the symbol, in ANY role — call, read, write, import, extends, and
# the HAS-A member-type edge. Local variables and parameters produce read/write sites that resolve to no
# indexed definition; they land in ext= and are excluded from every ratio, which is why ext= is NOT a
# dependency count. Sites, by hand:
#   helperOne     read a                                                          -> sites  1, ext {a}
#   helperTwo     read a                                                          -> sites  1, ext {a}
#   allLocal      call helperOne, call helperTwo, read x                          -> sites  3, ext {x}
#   siblingHere   read a, 9x read t, 8x write t                                   -> sites 18, ext {a,t}
#   mostlyRemote  3 calls, 3x read x                                              -> sites  6, ext {x}
#   Holder        extends Shared, member-type Shared                              -> sites  2, ext {}
#   Shared        nothing                                                         -> sites  0, ext {}
#
# ── THE DERIVATION, part 3: THE ROWS ───────────────────────────────────────────────────────────────────
#   allLocal      ents {helperOne,helperTwo} both IN local.cpp
#                 ents=2 ents_out=0 ent_ratio=0.000 files=1 files_out=0
#                 rtok=12+12=24 rtok_out=0 read_ratio=0.000            <- THE ratio-0 pole: all context in-file
#   mostlyRemote  ents {helperOne,helperTwo}@local.cpp + {siblingHere}@remote.cpp
#                 ents=3 ents_out=2 ent_ratio=2/3=0.667 files=2 files_out=1
#                 rtok=12+12+47=71 rtok_out=24 read_ratio=24/71=0.338  <- THE POINT OF THE LENS: the
#                 edge-count ratio says 0.667 and the reader-weighted ratio says 0.338, because the one
#                 entity that is IN the file is by far the biggest thing to read. Arm (D) pins the gap.
#   Holder        ents {Shared}@local.cpp, reached with ZERO calls (extends + member type)
#                 ents=1 ents_out=1 ent_ratio=1.000 files=1 files_out=1
#                 rtok=4 rtok_out=4 read_ratio=1.000                   <- THE mostly-elsewhere pole
#   siblingHere / helperOne / helperTwo / Shared  resolve nothing: ents=0, both ratios 0.000, rtok=0
#
#   ORDER (rtok_out desc, ents_out desc, rtok desc, id asc; ids follow sorted crawl order holder<local<remote):
#     mostlyRemote, Holder, allLocal, Shared, helperOne, helperTwo, siblingHere
#
# ── THE DERIVATION, part 4: THE FILE ROLLUP ────────────────────────────────────────────────────────────
# A file row is the union over every reference site IN that file, which is NOT the sum of its symbol rows:
# local.cpp's ext= is 2 ({a,x}) while its only entity-bearing symbol allLocal has ext=1. Arm (E) pins that.
#   local.cpp   sites=5  ents=2 ents_out=0 ent_ratio=0.000 files=1 files_out=0 rtok=24 rtok_out=0  rr=0.000 ext=2
#   remote.cpp  sites=24 ents=3 ents_out=2 ent_ratio=0.667 files=2 files_out=1 rtok=71 rtok_out=24 rr=0.338 ext=3
#   holder.cpp  sites=2  ents=1 ents_out=1 ent_ratio=1.000 files=1 files_out=1 rtok=4  rtok_out=4  rr=1.000 ext=0
#   file order (rtok_out desc, ents_out desc, path asc): remote.cpp, holder.cpp, local.cpp
#
# EVERY COLUMN IS AN INTEGER OR A RATIO OF INTEGERS, so there is no tolerance band anywhere in this gate:
# the two ratios are printed %.3f from an exact integer quotient and are compared exactly as strings.
#
# Arms:
#   (A) determinism   — two --no-cache runs are byte-identical
#   (B) golden        — every column of all seven symbol rows, against the hand-derivation above
#   (C) the two poles — allLocal is ratio 0.000 WITH entities; Holder is 1.000
#   (D) reader weight — mostlyRemote's ent_ratio and read_ratio DIFFER (0.667 vs 0.338). Without this the
#                       reader weighting could be a rename of the edge ratio and no other arm would notice
#   (E) file rollup   — the three file rows, and that a file row is a UNION, not a sum of its symbol rows
#   (F) non-call roles— Holder reaches its entity through extends + member-type only, zero calls
#   (G) mutation      — the same audit against a fixture with helperTwo MOVED to remote.cpp must go RED
#   (H) paging        — limit=1 discloses the primary listing per pageview.h's noun-prefixed rule
#   (I) additive      — `--context-ratio` changes nothing about the flagless map (G5)
#   (J) attribution   — the legend NAMES Beck & Diehl (FSE 2011) and Martin's instability as the prior art
#                       for the ratio itself, and claims novelty only for the reader weighting and the
#                       a-priori "entities to visit" quantity. The readability-metrics design note (8c.3) makes that
#                       attribution binding, so it is gated, not left to a comment someone can edit away
#
# Usage:  bash test/contextratiocheck.sh      [RIPWIRE_BIN=path/to/binary]
# Exit:   0 = clean · 1 = at least one arm failed · 2 = usage / missing prerequisite

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

command -v python3 >/dev/null 2>&1 || { printf 'contextratiocheck: python3 missing (gate cannot run)\n'; exit 2; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "contextratiocheck: BIN=$BIN"

cat >"$FIXTURE/local.cpp" <<'CPP'
class Shared
{
};

int helperOne( int a )
{
    return a + 1;
}

int helperTwo( int a )
{
    return a * 2;
}

int allLocal( int x )
{
    return helperTwo( helperOne( x ) );
}
CPP

cat >"$FIXTURE/remote.cpp" <<'CPP'
int siblingHere( int a )
{
    int t = a;
    t = t + 1;
    t = t + 2;
    t = t + 3;
    t = t + 4;
    t = t + 5;
    t = t + 6;
    t = t + 7;
    t = t + 8;
    return t;
}

int mostlyRemote( int x )
{
    return helperOne( x ) + helperTwo( x ) + siblingHere( x );
}
CPP

cat >"$FIXTURE/holder.cpp" <<'CPP'
class Holder : public Shared
{
    Shared m_a;
};
CPP

# The MUTANT moves helperTwo out of local.cpp and into remote.cpp. Nothing else changes — same seven
# symbols, same bodies, same call sites — so allLocal stops being self-contained (ent_ratio 0.000 -> 0.500)
# and mostlyRemote gains an in-file entity. Arm (G) reruns arm (B)'s expectations against it.
cat >"$MUTANT/local.cpp" <<'CPP'
class Shared
{
};

int helperOne( int a )
{
    return a + 1;
}

int allLocal( int x )
{
    return helperTwo( helperOne( x ) );
}
CPP

cat >"$MUTANT/remote.cpp" <<'CPP'
int helperTwo( int a )
{
    return a * 2;
}

int siblingHere( int a )
{
    int t = a;
    t = t + 1;
    t = t + 2;
    t = t + 3;
    t = t + 4;
    t = t + 5;
    t = t + 6;
    t = t + 7;
    t = t + 8;
    return t;
}

int mostlyRemote( int x )
{
    return helperOne( x ) + helperTwo( x ) + siblingHere( x );
}
CPP

cp "$FIXTURE/holder.cpp" "$MUTANT/holder.cpp"

# ── (A) determinism ────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIXTURE" --context-ratio --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIXTURE" --context-ratio --no-cache >"$TMP/b" 2>/dev/null
if [ ! -s "$TMP/a" ]; then
    no "(A) --context-ratio produced NO output on the fixture — an empty baseline is not a passing determinism run"
elif cmp -s "$TMP/a" "$TMP/b"; then
    ok "(A) two --no-cache runs are byte-identical"
else
    no "(A) --context-ratio is not deterministic across two identical runs"
fi

"$BIN" "$MUTANT" --context-ratio --no-cache >"$TMP/m" 2>/dev/null

# ── (B)..(G) the golden, the poles, the weighting, the rollup, the roles, the mutation control ─────────
python3 - "$TMP/a" "$TMP/m" <<'PY'
import sys, xml.etree.ElementTree as ET

# HAND-DERIVED — see the derivation block at the top of this file before touching a number here.
GOLD = {
    "mostlyRemote": dict( sites= 6, ents=3, ents_out=2, ent_ratio="0.667", files=2, files_out=1,
                          rtok=71, rtok_out=24, read_ratio="0.338", ext=1, amb=0 ),
    "Holder":       dict( sites= 2, ents=1, ents_out=1, ent_ratio="1.000", files=1, files_out=1,
                          rtok= 4, rtok_out= 4, read_ratio="1.000", ext=0, amb=0 ),
    "allLocal":     dict( sites= 3, ents=2, ents_out=0, ent_ratio="0.000", files=1, files_out=0,
                          rtok=24, rtok_out= 0, read_ratio="0.000", ext=1, amb=0 ),
    "Shared":       dict( sites= 0, ents=0, ents_out=0, ent_ratio="0.000", files=0, files_out=0,
                          rtok= 0, rtok_out= 0, read_ratio="0.000", ext=0, amb=0 ),
    "helperOne":    dict( sites= 1, ents=0, ents_out=0, ent_ratio="0.000", files=0, files_out=0,
                          rtok= 0, rtok_out= 0, read_ratio="0.000", ext=1, amb=0 ),
    "helperTwo":    dict( sites= 1, ents=0, ents_out=0, ent_ratio="0.000", files=0, files_out=0,
                          rtok= 0, rtok_out= 0, read_ratio="0.000", ext=1, amb=0 ),
    "siblingHere":  dict( sites=18, ents=0, ents_out=0, ent_ratio="0.000", files=0, files_out=0,
                          rtok= 0, rtok_out= 0, read_ratio="0.000", ext=2, amb=0 ),
}
ORDER = [ "mostlyRemote", "Holder", "allLocal", "Shared", "helperOne", "helperTwo", "siblingHere" ]
INTS  = ( "sites", "ents", "ents_out", "files", "files_out", "rtok", "rtok_out", "ext", "amb" )
STRS  = ( "ent_ratio", "read_ratio" )

FILEGOLD = {
    "remote.cpp": dict( sites=24, ents=3, ents_out=2, ent_ratio="0.667", files=2, files_out=1,
                        rtok=71, rtok_out=24, read_ratio="0.338", ext=3, amb=0 ),
    "holder.cpp": dict( sites= 2, ents=1, ents_out=1, ent_ratio="1.000", files=1, files_out=1,
                        rtok= 4, rtok_out= 4, read_ratio="1.000", ext=0, amb=0 ),
    "local.cpp":  dict( sites= 5, ents=2, ents_out=0, ent_ratio="0.000", files=1, files_out=0,
                        rtok=24, rtok_out= 0, read_ratio="0.000", ext=2, amb=0 ),
}
FILEORDER = [ "remote.cpp", "holder.cpp", "local.cpp" ]

def audit( path, label ):
    """Returns (complaints, root, symbol rows, file rows); empty complaints == the golden holds."""
    root  = ET.parse( path ).getroot()
    syms  = root.findall( "s" )
    files = root.findall( "f" )
    bad   = []
    byName = { node.get( "n" ): node for node in syms }
    if sorted( byName ) != sorted( GOLD ):
        bad.append( f"{label}: expected symbols {sorted(GOLD)}, got {sorted(byName)}" )
        return bad, root, syms, files
    for name, want in GOLD.items():
        node = byName[ name ]
        for key in INTS:
            got = node.get( key )
            if got is None or int( got ) != want[ key ]:
                bad.append( f"{label}: {name}@{key} expected {want[key]}, got {got}" )
        for key in STRS:
            got = node.get( key )
            if got != want[ key ]:
                bad.append( f"{label}: {name}@{key} expected {want[key]}, got {got}" )
    return bad, root, syms, files

bad, root, syms, files = audit( sys.argv[1], "golden" )
for line in bad:
    print( "  FAIL  (B) " + line )
if not bad:
    print( "  PASS  (B) every column of all seven symbol rows matches the hand-derivation" )

# root honesty: units= is the measured total and matches the rows on an uncapped run
if root.get( "units" ) != str( len( syms ) ):
    print( f"  FAIL  (B) root units={root.get('units')} disagrees with {len(syms)} emitted symbol rows" )
    bad.append( "units" )
if root.get( "file_units" ) != str( len( files ) ):
    print( f"  FAIL  (B) root file_units={root.get('file_units')} disagrees with {len(files)} emitted file rows" )
    bad.append( "file_units" )

order = [ node.get( "n" ) for node in syms ]
if order != ORDER:
    print( f"  FAIL  (B) expected row order {ORDER}, got {order}" )
    bad.append( "order" )
else:
    print( "  PASS  (B) rows are ranked most-outside-reading-first (rtok_out desc, then the stated tiebreaks)" )

# ── (C) the two poles ─────────────────────────────────────────────────────────────────────────────────
byName = { node.get( "n" ): node for node in syms }
local  = byName.get( "allLocal" )
remote = byName.get( "Holder" )
if local is None or remote is None:
    print( "  FAIL  (C) the two pole symbols are missing from the report" ); bad.append( "poles" )
elif local.get( "read_ratio" ) == "0.000" and local.get( "ent_ratio" ) == "0.000" and int( local.get( "ents" ) ) > 0 \
     and remote.get( "read_ratio" ) == "1.000" and int( remote.get( "ents_out" ) ) == int( remote.get( "ents" ) ):
    print( "  PASS  (C) allLocal is ratio 0.000 WITH entities (whole context in-file); Holder is 1.000 (entirely elsewhere)" )
else:
    print( f"  FAIL  (C) poles wrong: allLocal ents={local.get('ents')} read_ratio={local.get('read_ratio')}, "
           f"Holder ents={remote.get('ents')} ents_out={remote.get('ents_out')} read_ratio={remote.get('read_ratio')}" )
    bad.append( "poles" )

# ── (D) the reader weighting is REAL, not a rename of the edge ratio ──────────────────────────────────
mr = byName.get( "mostlyRemote" )
if mr is None:
    print( "  FAIL  (D) mostlyRemote is missing" ); bad.append( "weight" )
elif mr.get( "ent_ratio" ) == "0.667" and mr.get( "read_ratio" ) == "0.338":
    print( "  PASS  (D) reader weighting diverges from the edge count on the same symbol (0.667 edges vs 0.338 tokens)" )
else:
    print( f"  FAIL  (D) expected ent_ratio=0.667 read_ratio=0.338 on mostlyRemote, "
           f"got {mr.get('ent_ratio')} / {mr.get('read_ratio')}" )
    bad.append( "weight" )

# ── (E) the file rollup, and that it is a UNION and not a sum of its symbol rows ──────────────────────
byFile = { node.get( "p" ).split( "/" )[-1]: node for node in files }
if sorted( byFile ) != sorted( FILEGOLD ):
    print( f"  FAIL  (E) expected file rows {sorted(FILEGOLD)}, got {sorted(byFile)}" ); bad.append( "files" )
else:
    fbad = []
    for name, want in FILEGOLD.items():
        node = byFile[ name ]
        for key in INTS:
            got = node.get( key )
            if got is None or int( got ) != want[ key ]:
                fbad.append( f"{name}@{key} expected {want[key]}, got {got}" )
        for key in STRS:
            if node.get( key ) != want[ key ]:
                fbad.append( f"{name}@{key} expected {want[key]}, got {node.get(key)}" )
    forder = [ node.get( "p" ).split( "/" )[-1] for node in files ]
    if forder != FILEORDER:
        fbad.append( f"file row order expected {FILEORDER}, got {forder}" )
    # the UNION property: local.cpp's ext= (2: a and x) exceeds the ext= of its only entity-bearing
    # symbol (allLocal, 1: x), which a per-symbol SUM could not produce from the shown rows alone.
    if int( byFile[ "local.cpp" ].get( "ext" ) ) <= int( byName[ "allLocal" ].get( "ext" ) ):
        fbad.append( "local.cpp ext= does not exceed allLocal's — the rollup is not covering file-wide sites" )
    for line in fbad:
        print( "  FAIL  (E) " + line )
    if not fbad:
        print( "  PASS  (E) all three file rows match, in order, and the rollup is a file-wide UNION not a row sum" )
    bad += fbad

# ── (F) non-call roles carry the lens ─────────────────────────────────────────────────────────────────
# Holder has NO call sites at all: its two sites are the base-class edge and the member-variable type.
# If the scan silently degraded to the call graph, ents would be 0 here and this arm is the only one
# that says so in one sentence.
if remote is not None and int( remote.get( "sites" ) ) == 2 and int( remote.get( "ents" ) ) == 1:
    print( "  PASS  (F) a symbol with zero call sites still resolves its context (extends + member type)" )
else:
    print( "  FAIL  (F) Holder should reach 1 entity over 2 non-call sites; "
           f"got sites={remote.get('sites') if remote is not None else None} ents={remote.get('ents') if remote is not None else None}" )
    bad.append( "roles" )

# ── (G) MUTATION CONTROL — moving ONE function to another file must break the golden ─────────────────
mutantBad, _, _, _ = audit( sys.argv[2], "mutant" )
if mutantBad:
    print( f"  PASS  (G) mutation control: moving helperTwo to another file turns the golden RED ({len(mutantBad)} mismatch(es))" )
else:
    print( "  FAIL  (G) mutation control: the mutated fixture still satisfies the golden — arm (B) proves nothing" )
    bad.append( "mutation" )

raise SystemExit( 1 if bad else 0 )
PY
[ $? -eq 0 ] || fail=1

# ── (H) paging disclosure (src/pageview.h) — TWO independent listings, so the noun-prefixed pair ───────
page="$( "$BIN" "$FIXTURE" --context-ratio --limit=1 --no-cache 2>/dev/null | grep -o '<contextratio [^>]*>' | head -1 )"
pageRows="$( "$BIN" "$FIXTURE" --context-ratio --limit=1 --no-cache 2>/dev/null | grep -c '<s ' )"
wantAttrs='shown_syms="1" syms_capped="1"'
if [ "$pageRows" != "1" ]; then
    no "(H) limit=1 emitted $pageRows symbol row(s), expected 1"
elif ! printf '%s' "$page" | grep -q "$wantAttrs"; then
    no "(H) limit=1 root element lacks '$wantAttrs': $page"
elif ! printf '%s' "$page" | grep -q 'total="7" has_more="1" next_offset="1"'; then
    no "(H) limit=1 root element lacks total=\"7\" has_more=\"1\" next_offset=\"1\": $page"
elif printf '%s' "$page" | grep -qE '(^|[^_])shown="'; then
    no "(H) a two-listing verb emitted a BARE shown= — pageview.h rule 1 requires the noun-prefixed form: $page"
else
    ok "(H) limit=1 discloses $wantAttrs plus total/has_more/next_offset, and no bare shown="
fi

# ── (I) purely additive (G5): the flagless map is untouched by the new code path ───────────────────────
"$BIN" "$FIXTURE" --no-cache >"$TMP/map1" 2>/dev/null
"$BIN" "$FIXTURE" --context-ratio --no-cache >/dev/null 2>&1
"$BIN" "$FIXTURE" --no-cache >"$TMP/map2" 2>/dev/null
if cmp -s "$TMP/map1" "$TMP/map2" && ! grep -q 'read_ratio=' "$TMP/map1"; then
    ok "(I) the flagless map is unchanged and carries no context-ratio attribute"
else
    no "(I) the flagless map is not additive-clean (differs across runs, or leaks read_ratio=)"
fi

# ── (J) ATTRIBUTION — the prior-art credit is a shipped contract, not a source comment ────────────────
# The readability-metrics design note is binding at its 8c.3 (cited by SECTION, not by name: it is not a
# tracked file, and test/ripwirepubliccheck.sh arm 8 refuses a path that does not exist in the repo —
# src/ensemble.h cites the same note the same way). The inside-its-own-boundary share of a unit's coupling is
# Beck & Diehl's per-class congruence (FSE 2011) and Martin's instability is its crude ancestor. Shipping
# it unattributed reads as a rename of a published metric. This arm pins the credit where the READER meets
# it — the legend — and pins that the novelty claim stays narrow.
legend="$( "$BIN" "$FIXTURE" --context-ratio --no-cache 2>/dev/null | head -c 6000 )"
help="$( "$BIN" --help 2>&1 )"
# `grep -c` and not `grep -q`: the short-circuiting form closes the pipe under the writer and the SIGPIPE
# noise lands in the middle of this gate's own output (seen under the sanitizer build, where the writer is
# slow enough to still be writing). Counting reads the whole input and says nothing.
saysIt(){ [ "$( printf '%s' "$2" | grep -ci -- "$1" )" != "0" ]; }
missing=""
for phrase in "Beck" "Diehl" "instability" "Martin"; do
    saysIt "$phrase" "$legend" || missing="$missing $phrase"
done
if [ -n "$missing" ]; then
    no "(J) the legend does not credit the prior art for the ratio itself — missing:$missing"
elif ! saysIt "refinement" "$legend"; then
    no "(J) the legend does not say the ratio is a REFINEMENT of a published metric"
elif ! saysIt "Beck" "$help"; then
    no "(J) --help does not carry the same attribution the legend does"
else
    ok "(J) legend and --help both credit Beck & Diehl / Martin and frame the ratio as a refinement"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "contextratiocheck: FAILURES ABOVE"
exit "$fail"
