#!/usr/bin/env bash
# limitstablecheck.sh — docs/LIMITS.md is a BUILD PRODUCT of src/, and this gate says so.
#
# WHY. A cap is a routing decision: it decides what an agent can and cannot find. This tree has 114 of
# them across 50 files — plus 6 ranking parameters partitioned out of the same census on 2026-09-10,
# which is why "120 constants" and "114 caps" are both right — and before 2026-09-09 nothing listed them
# together, so kMaxExpandSibs could sit
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
#   (G) THE COLUMN MATCHES THE SIDECAR. Every INDEXING/OUTPUT cell is read back out of the RENDERED
#       document and compared against the sidecar, so a classification cannot be right in the file and
#       wrong on the page. Control: flipping a class in a copy must move the rendered cell.
#
# WHY (E)-(G) LIVE HERE. The 2026-09-10 round split this table in two — 114 caps that truncate, 6
# parameters that weight — because they need different instruments: a cap is judged by what it cuts and
# gated by shown/total, a parameter by the eval that chose it. The split is only worth having if the
# document cannot claim a source it does not have, and cannot claim a class the sidecar never gave it.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
GEN="$ROOT/docs/limits_build.py"
DOC="$ROOT/docs/LIMITS.md"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
row = re.compile( r'^\| `(k[A-Za-z0-9_]*)` \| `[^`]*` \| \d+ \| (INDEXING|OUTPUT|—) \|' )
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
if re.search( r'^\| `%s` \| `[^`]*` \| \d+ \| %s \|' % ( re.escape( name ), cls ), after, re.M ):
    no( "(G) mutation control: flipping %s in the sidecar did NOT change the rendered column" % name )
ok( "(G) mutation control: flipping a sidecar row moves the rendered class, so (G) is not inert" )
CLASSCOL

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
