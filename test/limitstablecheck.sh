#!/usr/bin/env bash
# limitstablecheck.sh — docs/LIMITS.md is a BUILD PRODUCT of src/, and this gate says so.
#
# WHY. A cap is a routing decision: it decides what an agent can and cannot find. Before 2026-09-09
# nothing listed them together, so kMaxExpandSibs could sit
# at 8, fire on 68.5% of bodies and hide 89.3% of every sibling name, justified by a cost ("~3.5 KB per
# --pack-task bundle") that was not reproducible, because --pack-task emits no sibs= at all. Nobody was
# wrong on purpose; the caps were simply never visible next to each other.
#
# A hand-kept table of 120 constants rots. The same round found a published figure that had been stale
# for four days because one number lived in SIX artifacts and only FOUR were wired together. So the table
# is generated and this gate fails when it drifts.
#
# ARMS
#   (A) the generator exists and parses a non-zero number of caps (its own shape-change guard).
#   (B) THE GATE: docs/LIMITS.md matches what the generator produces from src/ right now.
#   (C) CAN-GO-RED, on the REAL mechanism: a synthetic tree with one EXTRA cap must make --check fail.
#       It runs against --root on a temp tree, never against src/ — dropping a probe file into src/ would
#       perturb the crawl other gates measure (see test/README notes on probe-copy artifacts).
#   (D) the generator refuses a tree it cannot parse instead of writing an empty table.
#   (E) ANCHOR INTEGRITY. The parameter table carries an `anchor` column read from each constant's own
#       trailing comment. A row saying **unsourced** is honest; a row citing a docs/EVALS.md section
#       that does not exist is a dangling promise wearing a citation, and is worse than either. This arm
#       proves BOTH directions on a synthetic tree: a real anchor is accepted, a fabricated one refuses.
#   (F) THE SIDECAR IS LIVE. Every name in docs/limits_classes.tsv must be a cap that still exists in
#       src/. A sidecar keyed by name rots exactly this way, and a stale row is a classification applied
#       silently to nothing. Control: a fabricated row in a COPY of the sidecar must be refused.
#   (H) THE DECLARATION SHAPE. `inline constexpr … = N;` on ONE line was never the shape of the
#       population, only of one habit: `inline` is optional at namespace scope and forbidden on a class
#       member. A plain `constexpr`, a `static constexpr` member and a wrapped initializer are each
#       planted alone in a synthetic --root tree and required to appear, with a non-cap beside them
#       required NOT to. Control: the same arm proves the NAME filter now admits `*PerFile`.
#   (G) THE COLUMN MATCHES THE SIDECAR. Every INDEXING/OUTPUT cell is read back out of the RENDERED
#       document and compared against the sidecar, so a classification cannot be right in the file and
#       wrong on the page. Control: flipping a class in a copy must move the rendered cell.
#   (I) PINNED BY WHAT A CAP IS, NEVER BY ITS LINE. (B) again, on a scratch copy of the REAL src/, under
#       mutation. Lines inserted above a cap, a blank line deleted above it, and every file shifted down
#       two lines must each leave --check GREEN; the cap's value changed, its declaration deleted, a
#       disclosure attribute renamed away and a class flipped must each turn it RED as STALE. Every
#       mutation is asserted to have taken before its outcome is read, and the restored copy must be
#       green again.
#   (J) ONE NAME DECLARED TWICE IN ONE FILE. With no line to tell them apart, identical declarations
#       render as ONE row marked ×2 (beside a separate row for a different value), and deleting one of
#       them must still make --check fail: a multiplicity is part of the cap set, not a duplicate to drop.
#   (K) THE CAP TABLES ARE NOT FILED UNDER "NOT CAPS". Read from the RENDERED outline — what GitHub's TOC
#       and --grep's enclosing-section attribution both read — every per-file `### `src/…`` table must have
#       a `##` above it, the same one for all, and it must not be the parameter section (found by the table
#       only that section carries, not by its title). Control: deleting that `##` from a copy must turn the
#       identical reading RED. It does not assert which heading it is.
#
# WHY (E)-(G) LIVE HERE. The 2026-09-10 round split this table in two — caps that truncate, parameters
# that weight — because they need different instruments: a cap is judged by what it cuts and
# gated by shown/total, a parameter by the eval that chose it. The split is only worth having if the
# document cannot claim a source it does not have, and cannot claim a class the sidecar never gave it.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
GEN="$ROOT/docs/limits_build.py"
DOC="$ROOT/docs/LIMITS.md"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$GEN" ] || { echo "limitstablecheck: no docs/limits_build.py"; exit 2; }
[ -f "$DOC" ] || { echo "limitstablecheck: no docs/LIMITS.md — run: python3 docs/limits_build.py"; exit 2; }

# ── (A) the generator runs and finds caps ───────────────────────────────────────────────────────────
n="$( python3 "$GEN" --out "$TMP/a.md" 2>&1 | grep -oE '[0-9]+ caps' | head -1 )"
if [ -n "$n" ]; then ok "(A) generator parsed $n from src/"; else no "(A) generator produced no cap count"; fi

# ── (B) the committed table matches src/ ────────────────────────────────────────────────────────────
if out="$( python3 "$GEN" --check 2>&1 )"; then
    ok "(B) docs/LIMITS.md matches src/ — ${out#*: }"
else
    no "(B) docs/LIMITS.md is STALE: $out — run: python3 docs/limits_build.py"
fi

# ── (C) CAN-GO-RED on a real source change, in a synthetic tree ─────────────────────────────────────
mkdir -p "$TMP/synth/src" "$TMP/synth/docs"
cp "$GEN" "$TMP/synth/docs/limits_build.py"
printf 'inline constexpr std::size_t kSynthRowCap = 7;\n' > "$TMP/synth/src/synth.h"
python3 "$TMP/synth/docs/limits_build.py" --root "$TMP/synth" --out "$TMP/synth/docs/LIMITS.md" >/dev/null 2>&1
printf 'inline constexpr std::size_t kSynthOtherCap = 9;\n' >> "$TMP/synth/src/synth.h"
if python3 "$TMP/synth/docs/limits_build.py" --root "$TMP/synth" --out "$TMP/synth/docs/LIMITS.md" --check >/dev/null 2>&1; then
    no "(C) mutation control: an ADDED cap did not make --check fail — this gate cannot go red"
else
    python3 "$TMP/synth/docs/limits_build.py" --root "$TMP/synth" --out "$TMP/synth/docs/LIMITS.md" >/dev/null 2>&1
    if python3 "$TMP/synth/docs/limits_build.py" --root "$TMP/synth" --out "$TMP/synth/docs/LIMITS.md" --check >/dev/null 2>&1; then
        ok "(C) mutation control: an added cap goes RED, and regenerating clears it"
    else
        no "(C) mutation control: regenerating the synthetic table did not clear the failure"
    fi
fi

# ── (I) pinned by what a cap IS, never by the line it sits on — (B) under mutation, on the real tree ──
# WHY. docs/LIMITS.md used to carry each cap's LINE, so an edit that only added or removed lines ABOVE a
# cap — a rewritten comment, a deleted helper — turned (B) red while no claim in the document had
# changed. On 2026-09-10 PRs #115, #116 and #117 were all red on this gate; each of #117's six failed CI
# jobs was `fail=1 limitstablecheck.sh`, caused only by kPrDefaultBudgetTokens moving from line 452 of
# src/prcontext.h to 431 after an unrelated deletion. Every src/ PR cut from one main pins the same
# lines, so each landing re-staled the next. The document is now keyed by what a cap IS, and this arm
# holds both halves of that: a line move must stay GREEN, and each real claim — value, the cap set,
# disclosure, class — must still go RED. Either half alone is a gate that is noisy or a gate that is blind.
#
# The mutations edit a scratch COPY of src/, never src/ itself: gates run in parallel, and a probe edit
# in the live tree perturbs every crawl beside this one. The target cap is chosen from the copy by rule —
# declared once, unclassified (so deleting it reads as STALE, not as a sidecar refusal), one row in the
# rendered document, a blank line somewhere above it — so a rename in src/ moves the probe, never blinds it.
python3 - "$ROOT" "$TMP" <<'PINNED' || fail=1
import collections, os, re, shutil, subprocess, sys
ROOT, TMP = sys.argv[ 1 ], sys.argv[ 2 ]
bad = []
def ok( m ): print( "  PASS  %s" % m )
def no( m ): print( "  FAIL  %s" % m ); bad.append( m )
def read( p ):
    with open( p, encoding="utf-8", errors="surrogateescape", newline="" ) as fh:
        return fh.read()
def write( p, t ):
    with open( p, "w", encoding="utf-8", errors="surrogateescape", newline="" ) as fh:
        fh.write( t )

MUT = os.path.join( TMP, "pinned" )
shutil.copytree( os.path.join( ROOT, "src" ), os.path.join( MUT, "src" ) )
os.makedirs( os.path.join( MUT, "docs" ) )
for f in ( "limits_build.py", "LIMITS.md", "limits_classes.tsv", "EVALS.md" ):
    if os.path.exists( os.path.join( ROOT, "docs", f ) ):
        shutil.copy( os.path.join( ROOT, "docs", f ), os.path.join( MUT, "docs", f ) )
GEN, DOC, TSV = ( os.path.join( MUT, "docs", f ) for f in ( "limits_build.py", "LIMITS.md", "limits_classes.tsv" ) )

def check( *extra ):
    r = subprocess.run( [ sys.executable, GEN, "--root", MUT, "--out", DOC, "--check", *extra ], capture_output=True, text=True )
    return r.returncode == 0, ( r.stderr.strip() or r.stdout.strip() ).split( "\n" )[ 0 ]

green, why = check()
if not green:
    no( "(I) precondition: the UNMUTATED scratch copy is already red (%s) — every control below would read that" % why )
    sys.exit( 1 )

# The probe target, chosen by rule. This regex is the gate's own, deliberately not the generator's: an
# arm that picked its target with the code under test would go blind exactly when that code breaks.
doc     = read( DOC )
sidecar = { l.split( "\t" )[ 0 ].strip() for l in read( TSV ).splitlines() if l.strip() and not l.lstrip().startswith( "#" ) }
DECL    = re.compile( r'^[ \t]*(?:static[ \t]+)?(?:inline[ \t]+)?constexpr\b[^=;\n]*\b(k[A-Z][A-Za-z0-9_]*)[ \t]*=[ \t]*([0-9]+)[ \t]*;', re.M )
files   = sorted( os.path.relpath( os.path.join( d, f ), MUT ) for d, _, fs in os.walk( os.path.join( MUT, "src" ) )
                  for f in fs if f.endswith( ( ".h", ".cpp" ) ) )
texts   = { p: read( os.path.join( MUT, p ) ) for p in files }
decls   = collections.Counter( m.group( 1 ) for t in texts.values() for m in DECL.finditer( t ) )
def decl_at( text, n ):
    return next( ( m for m in DECL.finditer( text ) if m.group( 1 ) == n ), None )
def line_of( text, n ):
    m = decl_at( text, n )
    return text[ : m.start() ].count( "\n" ) + 1 if m else None
def value_of( text, n ):
    m = decl_at( text, n )
    return m.group( 2 ) if m else None

target = None
for p in files:
    for m in DECL.finditer( texts[ p ] ):
        n = m.group( 1 )
        if decls[ n ] == 1 and n not in sidecar and len( re.findall( r'^\| `%s`' % n, doc, re.M ) ) == 1 and "\n\n" in texts[ p ][ : m.start() ]:
            target = ( p, n, m.group( 2 ) )
            break
    if target:
        break
if target is None:
    no( "(I) no probe target: no cap in src/ is declared once, unclassified, one row in docs/LIMITS.md and below a blank line" )
    sys.exit( 1 )
rel, name, val = target
orig = texts[ rel ]
here = os.path.join( MUT, rel )
at   = decl_at( orig, name ).start()
L    = line_of( orig, name )

def mutate( label, edits, took, want_green, extra=() ):
    """Write the mutation, prove it TOOK by reading the files back, and only then read --check. Always restore."""
    for p, t in edits.items():
        write( os.path.join( MUT, p ), t )
    try:
        if not took():
            no( "(I) %s: the mutation did not take — this control would measure nothing" % label )
            return
        green, why = check( *extra )
        if want_green and not green:
            no( "(I) %s, yet --check went RED: %s" % ( label, why ) )
        elif not want_green and green:
            no( "(I) %s, yet --check stayed GREEN — that claim is no longer gated" % label )
        elif not want_green and "is STALE" not in why:
            no( "(I) %s: --check went red for a different reason: %s" % ( label, why ) )
        else:
            ok( "(I) %s: --check %s" % ( label, "stays green" if want_green else "goes RED (STALE)" ) )
    finally:
        for p in edits:
            write( os.path.join( MUT, p ), texts[ p ] )

# GREEN — the cap moves and nothing about it changes. The three shapes a real edit takes: lines added
# directly above one cap, a line deleted above it (the #117 shape), and a shift under every cap at once.
note  = "// limitstablecheck (I): a comment added above a cap is not a change to the cap\n"
mutate( "3 lines inserted above %s (%s line %d -> %d)" % ( name, rel, L, L + 3 ),
        { rel: orig[ : at ] + "\n\n" + note + orig[ at : ] },
        lambda: line_of( read( here ), name ) == L + 3, True )
cut   = orig.rfind( "\n\n", 0, at )
mutate( "a blank line deleted above %s (%s line %d -> %d)" % ( name, rel, L, L - 1 ),
        { rel: orig[ : cut + 1 ] + orig[ cut + 2 : ] },
        lambda: line_of( read( here ), name ) == L - 1, True )
shift = "// limitstablecheck (I): every line below moved down two\n\n"
mutate( "all %d files under src/ shifted down 2 lines" % len( files ),
        { p: shift + texts[ p ] for p in files },
        lambda: line_of( read( here ), name ) == L + 2 and all( read( os.path.join( MUT, p ) ).startswith( shift ) for p in files ), True )

# RED — every real claim the document makes about a cap.
bumped = str( int( val ) + 1 )
vm     = decl_at( orig, name )
mutate( "%s's value changed %s -> %s" % ( name, val, bumped ),
        { rel: orig[ : vm.start( 2 ) ] + bumped + orig[ vm.end( 2 ) : ] },
        lambda: value_of( read( here ), name ) == bumped, False )
eol = orig.find( "\n", at )
eol = len( orig ) if eol < 0 else eol + 1
mutate( "%s's declaration deleted from %s" % ( name, rel ),
        { rel: orig[ : at ] + orig[ eol : ] },
        lambda: decl_at( read( here ), name ) is None, False )
CAPPED = re.compile( r'([a-z_]+)_capped' )
disc   = next( ( p for p in files if CAPPED.search( texts[ p ] ) and "### `%s`" % p in doc ), None )
if disc is None:
    no( "(I) no probe target: no file with a rendered table discloses a `*_capped` attribute" )
else:
    attr = sorted( set( CAPPED.findall( texts[ disc ] ) ) )[ 0 ]
    mutate( "`%s_capped` renamed away in %s" % ( attr, disc ),
            { disc: texts[ disc ].replace( attr + "_capped", attr + "_cap_ped" ) },
            lambda: attr not in set( CAPPED.findall( read( os.path.join( MUT, disc ) ) ) ), False )
tsv = read( TSV )
row = next( ( l for l in tsv.splitlines() if l.strip() and not l.lstrip().startswith( "#" ) ), None )
if row is None:
    no( "(I) no probe target: docs/limits_classes.tsv has no row to flip" )
else:
    cname, cls = [ s.strip() for s in row.split( "\t" ) ]
    other      = "INDEXING" if cls == "OUTPUT" else "OUTPUT"
    flipped    = os.path.join( TMP, "pinned-flip.tsv" )
    write( flipped, tsv.replace( row, "%s\t%s" % ( cname, other ), 1 ) )
    mutate( "%s's class flipped %s -> %s in a sidecar copy" % ( cname, cls, other ),
            {}, lambda: read( flipped ) != tsv, False, ( "--classes", flipped ) )

green, why = check()
if green:
    ok( "(I) the restored copy is green again — no mutation leaked into the next one's reading" )
else:
    no( "(I) a mutation leaked: the restored copy is still red (%s)" % why )
sys.exit( 1 if bad else 0 )
PINNED

# ── (J) one name declared twice in one file: ONE row marked ×2, and the multiplicity is still gated ────
# With no line column, two identical declarations — the same name, value and note in one file, legal in
# two namespaces or two function bodies — would render as two indistinguishable rows, which reads as a
# generator bug. They render as one row marked ×2. The tempting alternative, dropping the duplicate, is
# the defect this arm exists for: deleting one of the two would then leave --check green, and a change to
# the cap set would pass unseen. A different VALUE under the same name stays a row of its own.
mkdir -p "$TMP/dup/src" "$TMP/dup/docs"
cp "$GEN" "$TMP/dup/docs/limits_build.py"
dupdecl(){ printf 'namespace %s\n{\ninline constexpr std::size_t kSynthRowCap = %s;\n}\n' "$1" "$2"; }
{ dupdecl a 7; dupdecl b 7; dupdecl c 9; } > "$TMP/dup/src/dup.h"
python3 "$TMP/dup/docs/limits_build.py" --root "$TMP/dup" --out "$TMP/dup/docs/LIMITS.md" >/dev/null 2>&1
duprows="$( grep -c '^| `kSynthRowCap`' "$TMP/dup/docs/LIMITS.md" 2>/dev/null )"
twice="$( grep -c '^| `kSynthRowCap` ×2 | `7` |' "$TMP/dup/docs/LIMITS.md" 2>/dev/null )"
once="$( grep -c '^| `kSynthRowCap` | `9` |' "$TMP/dup/docs/LIMITS.md" 2>/dev/null )"
if [ "$duprows" != 2 ] || [ "$twice" != 1 ] || [ "$once" != 1 ]; then
    no "(J) kSynthRowCap declared 7, 7 and 9 in one file rendered ${duprows:-no} row(s), not one ×2 row for 7 plus one row for 9"
else
    { dupdecl a 7; dupdecl c 9; } > "$TMP/dup/src/dup.h"
    if [ "$( grep -c 'kSynthRowCap = 7' "$TMP/dup/src/dup.h" )" != 1 ]; then
        no "(J) mutation control: the second declaration of 7 was not removed — the control would measure nothing"
    elif jout="$( python3 "$TMP/dup/docs/limits_build.py" --root "$TMP/dup" --out "$TMP/dup/docs/LIMITS.md" --check 2>&1 )"; then
        no "(J) deleting one of two identical declarations left --check GREEN — the ×2 row hid a change to the cap set"
    elif ! printf '%s' "$jout" | grep -q 'is STALE'; then
        no "(J) deleting one of two identical declarations went red for a different reason: $jout"
    else
        ok "(J) a name declared twice renders as one ×2 row, and deleting one of the two still goes RED"
    fi
fi

# ── (K) the per-file cap tables are not filed under "Not caps" ────────────────────────────────────────
# WHY. render() emitted every per-file `### `src/…`` table with no `##` of its own, so in the document's
# outline all 50 of them were children of the last `##` written before them: "Not caps — ranking and
# apportionment parameters". (B) could not see it — the committed document matched its generator exactly.
# A READER of the outline could: GitHub's TOC, and `ripwire . --grep=kPrDefaultBudgetTokens`, which
# attributed its docs/LIMITS.md hit to in="Not caps — ranking and apportionment parameters::`src/prcontext.h`".
# A cap an agent is told is not a cap is a claim this document makes, so it is gated where the claim is
# made: the RENDERED outline, read the way (G) reads the rendered cells.
#
# The parameter section is found by the table only it carries, never by its title, so a retitle cannot
# blind the arm, and a document with no such table fails as blind instead of passing on nothing. The arm
# does not assert WHICH `##` parents the tables — naming it is render()'s job — only that there is one, it
# is shared by all of them, and it is not the section that says its contents are not caps.
python3 - "$DOC" "$TMP" <<'OUTLINE' || fail=1
import os, re, sys
DOC, TMP = sys.argv[ 1 ], sys.argv[ 2 ]
bad = []
def ok( m ): print( "  PASS  %s" % m )
def no( m ): print( "  FAIL  %s" % m ); bad.append( m )
def read( p ):
    with open( p, encoding="utf-8" ) as fh:
        return fh.read().split( "\n" )

HEAD  = re.compile( r'^(#{1,6})[ \t]+(.+?)[ \t]*$' )
PARAM = re.compile( r'^\| constant \| value \| site \| anchor \| note \|' )
def title( line ):
    return HEAD.match( line ).group( 2 )
def outline( lines ):
    """Each per-file `### `src/…`` heading with the index of its nearest `##` above (None: none), and the index
    of the `##` whose body carries the parameter table (None: no such table)."""
    tables, h2, param = [], None, None
    for i, line in enumerate( lines ):
        m = HEAD.match( line )
        if m and len( m.group( 1 ) ) <= 2:
            h2 = i if len( m.group( 1 ) ) == 2 else None
        elif m and len( m.group( 1 ) ) == 3 and m.group( 2 ).startswith( "`src/" ):
            tables.append( ( m.group( 2 ).strip( "`" ), h2 ) )
        elif h2 is not None and PARAM.match( line ):
            param = h2
    return tables, param

lines         = read( DOC )
tables, param = outline( lines )
parents       = sorted( { p for _, p in tables if p is not None } )
if not tables:
    no( "(K) parsed ZERO per-file `### `src/…`` headings out of docs/LIMITS.md — the heading shape changed and this arm is blind" )
elif param is None:
    no( "(K) no `##` section of docs/LIMITS.md carries the parameter table — the section this arm guards against is gone, so it is blind" )
else:
    orphan = [ f for f, p in tables if p is None ]
    under  = [ f for f, p in tables if p == param ]
    if orphan:
        no( "(K) %d of %d per-file cap tables have no `##` above them, e.g. `%s`" % ( len( orphan ), len( tables ), orphan[ 0 ] ) )
    if under:
        no( "(K) %d of %d per-file cap tables are filed under the parameter section \"%s\" (line %d), e.g. `%s` — the outline tells a reader they are not caps"
            % ( len( under ), len( tables ), title( lines[ param ] ), param + 1, under[ 0 ] ) )
    if len( parents ) > 1:
        no( "(K) the per-file cap tables are split across %d `##` sections: %s" % ( len( parents ), "; ".join( title( lines[ p ] ) for p in parents ) ) )

if not bad:
    ok( "(K) all %d per-file cap tables sit under one `##`, \"%s\", which is not the parameter section" % ( len( tables ), title( lines[ parents[ 0 ] ] ) ) )
    # CONTROL: delete that `##` from a COPY and re-read it with the identical extraction. The tables must fall
    # back under the parameter section and the reading must go RED, or this arm has never seen the nesting
    # it exists for.
    cut = parents[ 0 ]
    mut = os.path.join( TMP, "outline.md" )
    with open( mut, "w", encoding="utf-8" ) as fh:
        fh.write( "\n".join( lines[ : cut ] + lines[ cut + 1 : ] ) )
    back = read( mut )
    if back.count( lines[ cut ] ) != lines.count( lines[ cut ] ) - 1:
        no( "(K) mutation control: \"%s\" was not removed from the copy — the control would measure nothing" % title( lines[ cut ] ) )
    else:
        t2, p2 = outline( back )
        if p2 is None or not [ f for f, p in t2 if p == p2 ]:
            no( "(K) mutation control: with \"%s\" deleted, no per-file table read as filed under the parameter section — this arm cannot go red" % title( lines[ cut ] ) )
        else:
            ok( "(K) mutation control: deleting that `##` files the tables under the parameter section again, and the reading goes RED" )
sys.exit( 1 if bad else 0 )
OUTLINE

# ── (D) a tree with no caps is a refusal, not an empty table ────────────────────────────────────────
mkdir -p "$TMP/empty/src" "$TMP/empty/docs"
cp "$GEN" "$TMP/empty/docs/limits_build.py"
printf '// no caps here\n' > "$TMP/empty/src/none.h"
if python3 "$TMP/empty/docs/limits_build.py" --root "$TMP/empty" --out "$TMP/empty/docs/LIMITS.md" >/dev/null 2>&1; then
    no "(D) generator wrote a table for a tree with ZERO caps instead of refusing"
else
    ok "(D) generator refuses a tree it parses no caps from"
fi

# ── (E) anchor integrity, both directions, on a synthetic tree ──────────────────────────────────────
mkdir -p "$TMP/anch/src" "$TMP/anch/docs"
cp "$GEN" "$TMP/anch/docs/limits_build.py"
printf '# Evals\n\n## §9.9 the synthetic anchor\n\nbody\n' > "$TMP/anch/docs/EVALS.md"
# The names matter: KEY admits a constant to the census, WEIGHT_NAME then routes it to the parameter
# table. A fixture name matching only one of the two is scanned-but-not-a-parameter (or not scanned at
# all), and the arm would assert nothing. kSynthBudgetShare matches both, kSynthRowCap only KEY.
printf 'inline constexpr std::size_t kSynthRowCap = 7;\n' > "$TMP/anch/src/s.h"
printf 'inline constexpr double kSynthBudgetShare = 0.25;  // chosen in EVALS.md §9.9\n' >> "$TMP/anch/src/s.h"
if ! python3 "$TMP/anch/docs/limits_build.py" --root "$TMP/anch" --out "$TMP/anch/docs/LIMITS.md" >/dev/null 2>&1; then
    no "(E) a parameter citing a REAL docs/EVALS.md section was refused — the check rejects everything"
elif ! grep -q 'EVALS.md §9.9' "$TMP/anch/docs/LIMITS.md"; then
    no "(E) a real anchor was accepted but never reached the rendered anchor column"
else
    printf 'inline constexpr double kSynthBudgetTolerance = 0.5;  // chosen in EVALS.md §44.44\n' >> "$TMP/anch/src/s.h"
    if python3 "$TMP/anch/docs/limits_build.py" --root "$TMP/anch" --out "$TMP/anch/docs/LIMITS.md" >/dev/null 2>&1; then
        no "(E) a parameter citing a docs/EVALS.md section that does NOT exist was accepted"
    else
        ok "(E) anchor column accepts a real EVALS.md citation and refuses one pointing at nothing"
    fi
fi

# ── (F) the sidecar names live caps only ────────────────────────────────────────────────────────────
TSV="$ROOT/docs/limits_classes.tsv"
if [ ! -f "$TSV" ]; then
    no "(F) docs/limits_classes.tsv is missing — the class column has no source"
else
    rows="$( grep -v '^[[:space:]]*#' "$TSV" | grep -c '[^[:space:]]' )"
    if [ "$rows" -lt 1 ]; then
        no "(F) docs/limits_classes.tsv has no rows — an empty sidecar agrees with everything"
    else
        cp "$TSV" "$TMP/classes.tsv"
        printf 'kNoSuchCapEverExisted\tINDEXING\n' >> "$TMP/classes.tsv"
        if python3 "$GEN" --classes "$TMP/classes.tsv" --out "$TMP/f.md" >/dev/null 2>&1; then
            no "(F) a sidecar row naming a cap that does NOT exist was accepted — stale rows rot silently"
        else
            ok "(F) sidecar has $rows live row(s) and a fabricated name is refused"
        fi
    fi
fi

# ── (G) the rendered class column IS the sidecar ────────────────────────────────────────────────────
python3 - "$ROOT" "$TMP" <<'CLASSCOL' || fail=1
import os, re, subprocess, sys
ROOT, TMP = sys.argv[1], sys.argv[2]
def ok( m ): print( "  PASS  %s" % m )
def no( m ): print( "  FAIL  %s" % m ); sys.exit( 1 )

want = {}
for line in open( os.path.join( ROOT, "docs", "limits_classes.tsv" ), encoding="utf-8" ):
    if line.strip() and not line.lstrip().startswith( "#" ):
        n, c = line.rstrip( "\n" ).split( "\t" )
        want[ n.strip() ] = c.strip()

# The class cell is read back out of the RENDERED markdown, not out of the generator's own data
# structures. Reading the artifact is the whole point: a column that is correct in memory and wrong on
# the page is exactly the drift this arm exists for.
row = re.compile( r'^\| `(k[A-Za-z0-9_]*)`(?: ×\d+)? \| `[^`]*` \| (INDEXING|OUTPUT|BOUNDARY|—) \|' )
got = {}
for line in open( os.path.join( ROOT, "docs", "LIMITS.md" ), encoding="utf-8" ):
    m = row.match( line )
    if m:
        got[ m.group( 1 ) ] = m.group( 2 )
if not got:
    no( "(G) parsed ZERO class cells out of docs/LIMITS.md — the row shape changed and this arm is blind" )
wrong = sorted( n for n, c in want.items() if got.get( n ) != c )
extra = sorted( n for n, c in got.items() if c != "—" and want.get( n ) != c )
if wrong or extra:
    no( "(G) rendered class column disagrees with the sidecar: %s" % ", ".join( sorted( set( wrong + extra ) ) ) )
ok( "(G) all %d sidecar classifications appear verbatim in docs/LIMITS.md, and no others do" % len( want ) )

# CONTROL: flip one class in a COPY and require the rendered document to change with it. Without this
# the arm above compares a generated file to the file that generated it and is green forever.
src  = open( os.path.join( ROOT, "docs", "limits_classes.tsv" ), encoding="utf-8" ).read()
name, cls = sorted( want.items() )[ 0 ]
flip = src.replace( "%s\t%s" % ( name, cls ), "%s\t%s" % ( name, "OUTPUT" if cls == "INDEXING" else "INDEXING" ) )
if flip == src:
    no( "(G) mutation control could not flip a row — the sidecar shape changed" )
open( os.path.join( TMP, "flip.tsv" ), "w", encoding="utf-8" ).write( flip )
subprocess.run( [ sys.executable, os.path.join( ROOT, "docs", "limits_build.py" ),
                  "--classes", os.path.join( TMP, "flip.tsv" ), "--out", os.path.join( TMP, "g.md" ) ],
                check=True, capture_output=True )
after = open( os.path.join( TMP, "g.md" ), encoding="utf-8" ).read()
if re.search( r'^\| `%s`(?: ×\d+)? \| `[^`]*` \| %s \|' % ( re.escape( name ), cls ), after, re.M ):
    no( "(G) mutation control: flipping %s in the sidecar did NOT change the rendered column" % name )
ok( "(G) mutation control: flipping a sidecar row moves the rendered class, so (G) is not inert" )
CLASSCOL

# ── (H) THE DECLARATION SHAPE: a plain `constexpr` and a wrapped initializer are caps too ───────────
# The register's first line says "Every compile-time cap in src/". It used to require the literal
# `inline constexpr` with the value on the SAME line, and 92 declarations — 81 distinct names — were
# outside it, among them kType3MaxBucket (bounds clone DETECTION), kSkillScanFindingCap (bounds a
# SECURITY verdict) and kChaConeCap. `inline` is optional at namespace scope and FORBIDDEN on a class
# member, so "inline constexpr" was never the shape of the population; it was the shape of one habit.
#
# Three fixtures, three ways a real cap is spelled, each planted alone in a synthetic --root tree and
# each required to appear in the generated table. A NON-cap name in the same file must NOT appear, or
# the arm would pass on a generator that admits everything.
for shape in plain static wrapped; do
    d="$TMP/decl-$shape"
    mkdir -p "$d/src" "$d/docs"
    cp "$GEN" "$d/docs/limits_build.py"
    case "$shape" in
        plain)   printf 'constexpr std::size_t kProbeRowCap = 3;\n' > "$d/src/probe.h" ;;
        static)  printf 'struct S\n{\n    static constexpr std::size_t kProbeRowCap = 3;\n};\n' > "$d/src/probe.h" ;;
        wrapped) printf 'inline constexpr std::size_t kProbeRowCap =\n    3;\n' > "$d/src/probe.h" ;;
    esac
    printf 'inline constexpr double kProbePlainConstant = 3.5;\n' >> "$d/src/probe.h"
    if ! python3 "$d/docs/limits_build.py" --root "$d" --out "$d/docs/LIMITS.md" >/dev/null 2>&1; then
        no "(H) $shape: the generator refused a tree whose only cap is spelled that way"
    elif ! grep -Fq '`kProbeRowCap`' "$d/docs/LIMITS.md"; then
        no "(H) $shape: a cap declared as \`$shape constexpr\` is INVISIBLE to the register"
    elif grep -Fq '`kProbePlainConstant`' "$d/docs/LIMITS.md"; then
        no "(H) $shape: a NON-cap constant was admitted — the census is too greedy to mean anything"
    else
        ok "(H) $shape: a cap spelled that way is found, and a non-cap beside it is not"
    fi
done
# and the control that (H) is measuring the DECL regex and not the KEY one: a cap-shaped name the KEY
# vocabulary does not know must still be missed, or "the register found it" says nothing about how.
mkdir -p "$TMP/decl-key/src" "$TMP/decl-key/docs"
cp "$GEN" "$TMP/decl-key/docs/limits_build.py"
printf 'constexpr std::size_t kProbeRowCap = 3;\nconstexpr std::size_t kProbeSymbolsPerFile = 4;\n' \
    > "$TMP/decl-key/src/probe.h"
python3 "$TMP/decl-key/docs/limits_build.py" --root "$TMP/decl-key" --out "$TMP/decl-key/docs/LIMITS.md" >/dev/null 2>&1
if grep -Fq '`kProbeSymbolsPerFile`' "$TMP/decl-key/docs/LIMITS.md"; then
    ok "(H) control: the NAME filter admits PerFile too — kHandoffSymbolsPerFile is no longer invisible"
else
    no "(H) control: a *PerFile cap is still outside the NAME filter, which is how kHandoffSymbolsPerFile"
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
