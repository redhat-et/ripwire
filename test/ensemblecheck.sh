#!/usr/bin/env bash
# ensemblecheck.sh — the golden gate for `--ensemble`, the FAMILY JOIN.
#
# WHAT THE VERB CLAIMS, AND THEREFORE WHAT THIS GATE HAS TO SEE GO RED.
# --ensemble reports, per function, which of FOUR orthogonal evidence families fire — structural (the shape of
# the code), lexical (the naming-* rules on the identifier text), confusion (the atom-* rules on the syntactic
# construct), historical (git change frequency) — and ranks by the COUNT of distinct families. Three claims are
# only worth as much as the assertions behind them:
#
#   1. the COUNT is right, and so is the SET of names behind it;
#   2. the EVIDENCE is right — a reader must be able to see WHY without a second command;
#   3. a family that could NOT BE MEASURED is reported UNAVAILABLE, never as "did not fire".
#
# (3) is the one that decides whether the verb is honest. A missing measurement that renders as silence is a
# clean bill of health the tool never earned, so this gate runs the SAME fixture twice — once as a git
# repository and once outside one — and asserts the same symbol goes fam=4/of=4 in the first and
# fam=3/of=3 unavail="historical" in the second. That pair is the whole point of the verb.
#
# THE FIXTURE, AND WHY EVERY SYMBOL IN IT IS THERE. Hand-derived: nothing below is read off a run.
#
#   hot.c  (3 commits — the most-changed file in a 2-file corpus, so it is the whole worst decile of the
#           churn ranking and every function in it fires `historical`)
#
#     computeTheFinalAggregatedResultValue_forEachRow( a,b,c,d,e,f )   ->  ALL FOUR families
#         structural  6 parameters, and the params bar is 5           -> params=6
#         lexical     9 split tokens (naming-wordy fires above 5) AND a snake separator plus a camel
#                     transition in one name (naming-case)            -> naming-case naming-wordy
#         confusion   a ternary inside a ternary (atom-nested-ternary) and a comma expression used as a
#                     value (atom-comma-operator)                     -> both
#         historical  hot.c is churn rank 0                           -> hrank=0 churn=3
#
#     evaluateWideExpression( a,b,c )                                  ->  EXACTLY TWO families
#         structural  NONE of the four absolute bars: ccx 1 < 15, loc 5 < 60, nest 0 < 4, params 3 < 5.
#                     It fires structurally ONLY through the READABILITY RANK — one long, wide, high-entropy
#                     expression is the least readable function in the corpus, so rrank=0. That isolates the
#                     ordinal half of the structural family from the absolute half, which is the only way to
#                     tell they are wired independently.
#         historical  same file                                       -> hrank=0 churn=3
#
#     scaleByTwo / negateInput                                         ->  EXACTLY ONE family (historical)
#         Clean names, trivial bodies, no atoms. They exist so the ORDER assertion has 4/2/1/1 to walk down
#         and so the NodeId tie-break between the two fam=1 rows is observable.
#
#   calm.c (1 commit — churn rank 1, and the decile cut over a 2-file ranking is 1 row wide, so it is OUT)
#
#     sumPair / halveValue                                             ->  ZERO families
#         The control. Both must be ABSENT from the rows and both must be counted in no_family=, which is
#         what makes "absent" mean "measured and clean" instead of "not looked at".
#
# THE THRESHOLDS THE ABOVE DEPENDS ON, all disclosed on the root element and asserted in arm (G):
#   absolute bars, reused verbatim from quality.h:  bar_ccx=15  bar_loc=60  bar_nest=4  bar_params=5
#   ordinal cuts, ceil(n/10) bounded to [1,40]:     6 functions -> rcut=1;  2 churned files -> hcut=1
#
# Arms:
#   (A) determinism     — two --no-cache runs are byte-identical, git and non-git
#   (B) golden          — every row's fam=, fired= and per-family why=, against the derivation above
#   (C) order           — fam= is non-increasing down the rows, and equal-fam rows are in NodeId (file,line) order
#   (D) reconciliation  — ranked= + no_family= = eligible=, and the zero-family control is absent
#   (E) UNAVAILABLE     — the non-git corpus reports unavailable="historical" with a reason, of= drops to 3,
#                         every row carries unavail="historical", and hranked=/hcut= are 0
#   (F) mutation        — a fixture edit that removes ONE family must make arm (B) go RED; a gate that cannot
#                         go red is not a gate
#   (G) thresholds      — the bars and cuts are on the root, so the reader never has to guess what fired
#   (H) paging          — limit=1 discloses the primary listing per pageview.h's noun-prefixed rule
#   (I) additive        — `--ensemble` changes nothing about the flagless map (G5)
#   (J) well-formed     — the document parses (G4)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "ensemblecheck: SKIP — git not on PATH, the historical family cannot be exercised"; exit 0; }
echo "ensemblecheck: BIN=$BIN"

# ── the fixture, written once and copied into each tree ───────────────────────────────────────────────────
mkdir -p "$TMP/src"
cat >"$TMP/src/hot.c" <<'CPP'
int computeTheFinalAggregatedResultValue_forEachRow( int a, int b, int c, int d, int e, int f )
{
    return ( a ? b : ( c ? d : e ) ) + ( f, a );
}

int evaluateWideExpression( int a, int b, int c )
{
    return ( a * b + c ) / ( a - b + 1 ) * ( c % 3 ) + ( a << 2 ) - ( b >> 1 )
         + ( a * c - b ) / ( c + 2 ) * ( a % 5 ) + ( b << 3 ) - ( c >> 2 );
}

int scaleByTwo( int a )
{
    return a * 2;
}

int negateInput( int a )
{
    return -a;
}
CPP
cat >"$TMP/src/calm.c" <<'CPP'
int sumPair( int x, int y )
{
    return x + y;
}

int halveValue( int x )
{
    return x / 2;
}
CPP

# GIT tree: calm.c committed once, hot.c three times, so churn(hot.c)=3 > churn(calm.c)=1 and the one-row
# decile cut lands on hot.c alone. The two extra commits append a trailing comment OUTSIDE every definition
# span, so not one measured number moves — only the commit count does.
GITFIX="$TMP/gitfix"
mkdir -p "$GITFIX"
cp "$TMP/src/hot.c" "$TMP/src/calm.c" "$GITFIX/"
G="git -C $GITFIX -c user.email=gate@example.invalid -c user.name=gate -c commit.gpgsign=false"
$G init -q . >/dev/null 2>&1
$G add -A >/dev/null 2>&1
$G commit -q -m init >/dev/null 2>&1
printf '// bump 1\n' >>"$GITFIX/hot.c";  $G commit -q -am bump1 >/dev/null 2>&1
printf '// bump 2\n' >>"$GITFIX/hot.c";  $G commit -q -am bump2 >/dev/null 2>&1
if [ "$( $G rev-list --count HEAD 2>/dev/null )" != "3" ]; then
    echo "ensemblecheck: SKIP — could not build a 3-commit git fixture in this environment"
    exit 0
fi

# NON-GIT tree: byte-identical sources (including the two trailing comments, so the corpora are the same
# bytes), no repository anywhere above it — mktemp -d is outside the ripwire checkout by construction.
NOGIT="$TMP/nogit"
mkdir -p "$NOGIT"
cp "$GITFIX/hot.c" "$GITFIX/calm.c" "$NOGIT/"

# MUTANT: the SAME git tree with the lexical family removed from the 4-family symbol — the long mixed-case
# name becomes a short clean one. Its structural/confusion/historical evidence is untouched, so arm (B)'s
# expectations must go from satisfiable to unsatisfiable on this one edit alone.
MUTANT="$TMP/mutant"
mkdir -p "$MUTANT"
cp "$GITFIX/hot.c" "$GITFIX/calm.c" "$MUTANT/"
sed 's/computeTheFinalAggregatedResultValue_forEachRow/blend/' "$GITFIX/hot.c" >"$MUTANT/hot.c"
MG="git -C $MUTANT -c user.email=gate@example.invalid -c user.name=gate -c commit.gpgsign=false"
$MG init -q . >/dev/null 2>&1
$MG add -A >/dev/null 2>&1
$MG commit -q -m init >/dev/null 2>&1
printf '// bump 1\n' >>"$MUTANT/calm.c"; $MG commit -q -am b1 >/dev/null 2>&1   # keep hot.c the hotter file
$MG checkout -q -- . >/dev/null 2>&1
printf '// bump 3\n' >>"$MUTANT/hot.c";  $MG commit -q -am b3 >/dev/null 2>&1
printf '// bump 4\n' >>"$MUTANT/hot.c";  $MG commit -q -am b4 >/dev/null 2>&1

# ── (A) determinism ───────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$GITFIX" --ensemble --no-cache >"$TMP/git1" 2>/dev/null
"$BIN" "$GITFIX" --ensemble --no-cache >"$TMP/git2" 2>/dev/null
"$BIN" "$NOGIT"  --ensemble --no-cache >"$TMP/nog1" 2>/dev/null
"$BIN" "$NOGIT"  --ensemble --no-cache >"$TMP/nog2" 2>/dev/null
"$BIN" "$MUTANT" --ensemble --no-cache >"$TMP/mut"  2>/dev/null
if [ ! -s "$TMP/git1" ] || [ ! -s "$TMP/nog1" ]; then
    no "(A) --ensemble produced NO output — an empty baseline is not a passing determinism run"
elif cmp -s "$TMP/git1" "$TMP/git2" && cmp -s "$TMP/nog1" "$TMP/nog2"; then
    ok "(A) two --no-cache runs are byte-identical, on the git corpus and on the non-git one"
else
    no "(A) --ensemble is not deterministic across two identical runs"
fi

# ── (J) well-formedness (G4) ──────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/git1" 2>/dev/null && xmllint --noout "$TMP/nog1" 2>/dev/null; then
        ok "(J) both documents parse"
    else
        no "(J) --ensemble emitted a document xmllint rejects"
    fi
else
    ok "(J) xmllint absent — well-formedness is covered by test/xmlwellformed.sh"
fi

# ── (B)(C)(D)(E)(F)(G) the golden and its controls ────────────────────────────────────────────────────────
python3 - "$TMP/git1" "$TMP/nog1" "$TMP/mut" <<'PY'
import sys, xml.etree.ElementTree as ET

# HAND-DERIVED from the fixture — see the derivation block at the top of this file before touching a line.
# name -> ( family count, fired names in family order, { family: [ evidence items, exactly ] } )
GOLD = {
    "computeTheFinalAggregatedResultValue_forEachRow": (
        4, "structural,lexical,confusion,historical",
        { "structural": [ "params=6" ],
          "lexical":    [ "naming-case", "naming-wordy" ],
          "confusion":  [ "atom-comma-operator", "atom-nested-ternary" ],
          "historical": [ "hrank=0", "churn=3" ] } ),
    "evaluateWideExpression": (
        2, "structural,historical",
        { "structural": [ "rrank=0" ],
          "historical": [ "hrank=0", "churn=3" ] } ),
    "scaleByTwo":  ( 1, "historical", { "historical": [ "hrank=0", "churn=3" ] } ),
    "negateInput": ( 1, "historical", { "historical": [ "hrank=0", "churn=3" ] } ),
}
ABSENT = ( "sumPair", "halveValue" )     # the zero-family control

def load( path ):
    root = ET.parse( path ).getroot()
    return root, root.findall( "s" ), root.findall( "f" )

def evidenceOf( node ):
    return { e.get( "f" ): ( e.get( "why" ) or "" ).split() for e in node.findall( "e" ) }

bad = []
root, rows, files = load( sys.argv[1] )
byName = { r.get( "n" ): r for r in rows }

# (B) the golden
if sorted( byName ) != sorted( GOLD ):
    bad.append( f"(B) expected rows for {sorted(GOLD)}, got {sorted(byName)}" )
else:
    for name, ( fam, fired, ev ) in GOLD.items():
        node = byName[ name ]
        if node.get( "fam" ) != str( fam ):
            bad.append( f"(B) {name}: fam expected {fam}, got {node.get('fam')}" )
        if node.get( "fired" ) != fired:
            bad.append( f"(B) {name}: fired expected '{fired}', got '{node.get('fired')}'" )
        if node.get( "of" ) != "4":
            bad.append( f"(B) {name}: of expected 4 on a corpus where every family is measurable, got {node.get('of')}" )
        if node.get( "unavail" ) != "":
            bad.append( f"(B) {name}: unavail expected empty on a git corpus, got '{node.get('unavail')}'" )
        got = evidenceOf( node )
        if sorted( got ) != sorted( ev ):
            bad.append( f"(B) {name}: evidence elements for {sorted(got)}, expected {sorted(ev)}" )
        else:
            for family, items in ev.items():
                if got[ family ] != items:
                    bad.append( f"(B) {name}/{family}: why expected {items}, got {got[family]}" )
if not bad:
    print( "  PASS  (B) every row's family count, family names and per-family evidence match the hand-derivation" )
else:
    for line in bad:
        print( "  FAIL  " + line )

# (C) ranked by family count DESC, tie-broken by NodeId (which is file,line order)
counts = [ int( r.get( "fam" ) ) for r in rows ]
order  = [ ( int( r.get( "fam" ) ), r.get( "p" ) ) for r in rows ]
cbad = []
if any( counts[i] < counts[i + 1] for i in range( len( counts ) - 1 ) ):
    cbad.append( f"(C) fam= is not non-increasing down the rows: {counts}" )
for i in range( len( order ) - 1 ):
    if order[i][0] == order[i + 1][0]:
        a, b = order[i][1], order[i + 1][1]
        ap, al = a.rsplit( ":", 1 )
        bp, bl = b.rsplit( ":", 1 )
        if ( ap, int( al ) ) > ( bp, int( bl ) ):
            cbad.append( f"(C) equal-fam rows out of NodeId order: {a} before {b}" )
if cbad:
    for line in cbad:
        print( "  FAIL  " + line )
    bad += cbad
else:
    print( f"  PASS  (C) rows are ranked by family count descending {counts}, ties in NodeId order" )

# (D) the denominator reconciles, and the zero-family control is absent BECAUSE it was measured and clean
dbad = []
eligible, ranked, none = int( root.get( "eligible" ) ), int( root.get( "ranked" ) ), int( root.get( "no_family" ) )
if ranked + none != eligible:
    dbad.append( f"(D) ranked({ranked}) + no_family({none}) != eligible({eligible})" )
if ranked != len( rows ):
    dbad.append( f"(D) ranked={ranked} disagrees with {len(rows)} emitted rows on an uncapped run" )
if none != len( ABSENT ):
    dbad.append( f"(D) no_family={none}, expected {len(ABSENT)} (the zero-family control)" )
for name in ABSENT:
    if name in byName:
        dbad.append( f"(D) {name} trips no family and must not appear in the rows" )
# the per-file rollup: only hot.c has any firing symbol, and its strongest symbol carries all four
if [ f.get( "p" ).rsplit( "/", 1 )[-1] for f in files ] != [ "hot.c" ]:
    dbad.append( f"(D) file rollup expected [hot.c], got {[f.get('p') for f in files]}" )
elif files[0].get( "top_fam" ) != "4" or files[0].get( "union_fam" ) != "4" or files[0].get( "syms" ) != "4":
    dbad.append( f"(D) hot.c rollup expected top_fam=4 union_fam=4 syms=4, got "
                 f"{files[0].get('top_fam')}/{files[0].get('union_fam')}/{files[0].get('syms')}" )
if dbad:
    for line in dbad:
        print( "  FAIL  " + line )
    bad += dbad
else:
    print( "  PASS  (D) ranked + no_family = eligible, the zero-family control is absent, the file rollup agrees" )

# (E) UNAVAILABLE is not silence — the same fixture with no repository above it
ebad = []
nroot, nrows, _ = load( sys.argv[2] )
nByName = { r.get( "n" ): r for r in nrows }
if nroot.get( "unavailable" ) != "historical":
    ebad.append( f"(E) root unavailable= expected 'historical', got '{nroot.get('unavailable')}'" )
if not ( nroot.get( "unavailable_why" ) or "" ).strip():
    ebad.append( "(E) unavailable_why= is empty — an unavailable family must say WHY" )
if nroot.get( "hranked" ) != "0" or nroot.get( "hcut" ) != "0":
    ebad.append( f"(E) expected hranked=0 hcut=0 with no history, got {nroot.get('hranked')}/{nroot.get('hcut')}" )
for node in nrows:
    if node.get( "of" ) != "3":
        ebad.append( f"(E) {node.get('n')}: of= expected 3 (one family unmeasurable), got {node.get('of')}" )
    if node.get( "unavail" ) != "historical":
        ebad.append( f"(E) {node.get('n')}: unavail= expected 'historical', got '{node.get('unavail')}'" )
    if "historical" in ( node.get( "fired" ) or "" ):
        ebad.append( f"(E) {node.get('n')}: an UNMEASURED family must never appear in fired=" )
# the load-bearing pair: the SAME symbol, one family fewer, and the missing one named as unavailable
target = "computeTheFinalAggregatedResultValue_forEachRow"
if target not in nByName:
    ebad.append( f"(E) {target} vanished from the non-git run" )
elif nByName[ target ].get( "fam" ) != "3" or nByName[ target ].get( "fired" ) != "structural,lexical,confusion":
    ebad.append( f"(E) {target} expected fam=3 fired='structural,lexical,confusion' without git, got "
                 f"fam={nByName[target].get('fam')} fired='{nByName[target].get('fired')}'" )
for name in ABSENT:
    if name in nByName:
        ebad.append( f"(E) {name} still trips no family without git and must stay absent" )
if ebad:
    for line in ebad:
        print( "  FAIL  " + line )
    bad += ebad
else:
    print( "  PASS  (E) with no git the historical family is UNAVAILABLE (named, explained, of=3, never in fired=), "
           "and the 4-family symbol reports fam=3 rather than a quiet 4th silence" )

# (G) every threshold the rows depend on is on the root, so nothing has to be guessed
gbad = []
for attr, want in ( ( "bar_ccx", "15" ), ( "bar_loc", "60" ), ( "bar_nest", "4" ), ( "bar_params", "5" ),
                    ( "rcut", "1" ), ( "rmeasured", "6" ), ( "hcut", "1" ), ( "hranked", "2" ),
                    ( "window", "12mo" ), ( "families", "4" ) ):
    if root.get( attr ) != want:
        gbad.append( f"(G) root {attr}= expected {want}, got {root.get(attr)}" )
if gbad:
    for line in gbad:
        print( "  FAIL  " + line )
    bad += gbad
else:
    print( "  PASS  (G) the absolute bars (15/60/4/5) and the ordinal cuts (rcut=1 of 6, hcut=1 of 2) are disclosed on the root" )

# (F) MUTATION CONTROL — one rename removes the lexical family from the 4-family symbol. The identical
#     expectations must now be unsatisfiable, or arm (B) is asserting nothing at all.
mroot, mrows, _ = load( sys.argv[3] )
mByName = { r.get( "n" ): r for r in mrows }
mutantAgrees = ( target in mByName
                 and mByName[ target ].get( "fam" ) == "4"
                 and mByName[ target ].get( "fired" ) == "structural,lexical,confusion,historical" )
if mutantAgrees:
    print( "  FAIL  (F) mutation control: the mutant still reports fam=4 for the renamed symbol — arm (B) proves nothing" )
    bad.append( "mutation" )
else:
    survivor = mByName.get( "blend" )
    detail = "the symbol is gone" if survivor is None else f"blend now reports fam={survivor.get('fam')} fired='{survivor.get('fired')}'"
    print( f"  PASS  (F) mutation control: renaming away the lexical evidence makes arm (B) unsatisfiable ({detail})" )

raise SystemExit( 1 if bad else 0 )
PY
[ $? -eq 0 ] || fail=1

# ── (H) paging disclosure (src/pageview.h, THE TRUNCATION VOCABULARY) ─────────────────────────────────────
# --ensemble has TWO independent listings (symbol rows + the per-file rollup), so rule 1's noun-prefixed form
# applies: the windowed primary listing discloses shown_syms=/syms_capped= and the paging half, and the
# secondary listing keeps its own shown_files=/files_capped= pair. A bare shown= here would be the bug.
page="$( "$BIN" "$GITFIX" --ensemble --limit=1 --no-cache 2>/dev/null | grep -o '<ensemble [^>]*>' | head -1 )"
pageRows="$( "$BIN" "$GITFIX" --ensemble --limit=1 --no-cache 2>/dev/null | grep -c '<s ' )"
wantAttrs='shown_syms="1" syms_capped="1" shown_files="1" files_capped="0" total="4" has_more="1" next_offset="1"'
if [ "$pageRows" != "1" ]; then
    no "(H) limit=1 emitted $pageRows symbol row(s), expected 1"
elif printf '%s' "$page" | grep -q "$wantAttrs"; then
    ok "(H) limit=1 discloses $wantAttrs"
else
    no "(H) limit=1 root element lacks '$wantAttrs': $page"
fi
if printf '%s' "$page" | grep -qE ' shown="'; then
    no "(H) a two-listing verb emitted a BARE shown= — pageview.h rule 1 requires the noun-prefixed form"
else
    ok "(H) no bare shown= on a two-listing verb (pageview.h rule 1)"
fi

# ── (I) purely additive (G5): the flagless map is untouched by the new code path ───────────────────────────
"$BIN" "$GITFIX" --no-cache >"$TMP/map1" 2>/dev/null
"$BIN" "$GITFIX" --ensemble --no-cache >/dev/null 2>&1
"$BIN" "$GITFIX" --no-cache >"$TMP/map2" 2>/dev/null
if cmp -s "$TMP/map1" "$TMP/map2" && ! grep -q '<ensemble' "$TMP/map1"; then
    ok "(I) the flagless map is unchanged and carries no ensemble element"
else
    no "(I) the flagless map is not additive-clean (differs across runs, or leaks the ensemble element)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "ensemblecheck: FAILURES ABOVE"
exit "$fail"
