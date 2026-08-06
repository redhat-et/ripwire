#!/usr/bin/env bash
# nonlocalstatecheck.sh — the golden gate for `--nonlocal-state` (the non-local mutable state lens).
#
# WHY A GOLDEN AND NOT A RE-IMPLEMENTATION. A reachability set, a read/write split and a transitive
# closure all look plausible whether or not they are correct (CLAUDE.md non-negotiable #1). A python
# mirror of the same closure inside this gate would reproduce the C++ closure's bugs verbatim and pass
# on both, so the expected sets below are HAND-DERIVED from the fixture, cell by cell, and written out
# here in full. Anyone changing the analysis has to re-derive them by hand too.
#
# THE DERIVATION.
#
#   state.cpp
#     1  static int g_counter = 0;     CELL  scope=file   (static ⇒ internal linkage ⇒ same-file matching)
#     2  int g_shared = 1;             CELL  scope=global (no `static` ⇒ external linkage ⇒ repo-wide)
#     3  const int kMax = 99;          NOT A CELL — the declaration prefix carries `const`
#     5  void bump()             direct: g_counter WRITE (lhs) + g_counter READ (rhs)
#    10  int peek()              direct: g_shared READ    (kMax is not a cell, so it contributes nothing)
#    15  void outer()            direct: g_shared WRITE; calls bump ⇒ inherits {g_counter r, g_counter w}
#
#   state.py
#     1  COUNTER = 0                   CELL  scope=file   (a module global; Python has no immutable binding)
#     4  def bump_py()                 direct: COUNTER WRITE (lhs) + COUNTER READ (rhs, and the `global` stmt)
#     9  def peek_py()                 direct: COUNTER READ
#
#   The transitive closure (union over the callee closure, direction preserved):
#     outer   writes {g_shared, g_counter} = 2   reads {g_counter}  = 1    direct_writes 1  direct_reads 0
#     bump    writes {g_counter}          = 1   reads {g_counter}  = 1    direct_writes 1  direct_reads 1
#     bump_py writes {COUNTER}            = 1   reads {COUNTER}    = 1    direct_writes 1  direct_reads 1
#     peek    writes {}                   = 0   reads {g_shared}   = 1    direct_writes 0  direct_reads 1
#     peek_py writes {}                   = 0   reads {COUNTER}    = 1    direct_writes 0  direct_reads 1
#
#   cells = 3 (g_counter, g_shared, COUNTER).  functions = 5.
#   Row order is writes DESC, then reads DESC, then path ASC, then line ASC — so state.cpp precedes state.py
#   on every tie, which is what pins bump before bump_py and peek before peek_py.
#
# Arms:
#   (A) determinism  — two --no-cache runs are byte-identical
#   (B) golden       — every count of all five functions, plus cells=/functions=, against the derivation
#   (C) direction    — reads and writes are DISTINGUISHED: peek/peek_py write nothing, and every emitted
#                      cell child carries dir=r|w|rw consistent with its row's counts
#   (D) mutation     — the SAME assertions run against a mutated fixture (`g_shared` made const) must go
#                      RED, proving (B) can see a wrong number at all
#   (E) paging       — limit=1 discloses shown/capped/total/has_more/next_offset per pageview.h
#   (F) additive     — `--nonlocal-state` changes nothing about the flagless map (G5)
#   (G) immutability — `kMax` is never emitted as a cell anywhere in the report
#   (H) provenance   — a transitively-reached cell names the callee it came through (via=), a directly
#                      touched one names its use site (at=); the two are never both present on one cell
#   (I) honesty      — the root carries counts_floor="1" and the legend discloses the unsound cases

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
MUTANT="$TMP/mutant"
mkdir -p "$FIXTURE" "$MUTANT"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "nonlocalstatecheck: BIN=$BIN"

writeFixture()
{
    dst="$1"; sharedQualifier="$2"
    cat >"$dst/state.cpp" <<CPP
static int g_counter = 0;
${sharedQualifier}int g_shared = 1;
const int kMax = 99;

void bump()
{
    g_counter = g_counter + 1;
}

int peek()
{
    return g_shared + kMax;
}

void outer()
{
    bump();
    g_shared = 2;
}
CPP
    cat >"$dst/state.py" <<'PY'
COUNTER = 0


def bump_py():
    global COUNTER
    COUNTER = COUNTER + 1


def peek_py():
    return COUNTER
PY
}

writeFixture "$FIXTURE" ""
# The mutant differs in ONE token: `g_shared` becomes const, so it stops being a cell entirely and every
# row that reached it must move. Arm (D) reruns arm (B)'s expectations against it.
writeFixture "$MUTANT" "const "

# ── (A) determinism ────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIXTURE" --nonlocal-state --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIXTURE" --nonlocal-state --no-cache >"$TMP/b" 2>/dev/null
if [ ! -s "$TMP/a" ]; then
    no "(A) --nonlocal-state produced NO output on the fixture — an empty baseline is not a passing determinism run"
elif cmp -s "$TMP/a" "$TMP/b"; then
    ok "(A) two --no-cache runs are byte-identical"
else
    no "(A) --nonlocal-state is not deterministic across two identical runs"
fi

"$BIN" "$MUTANT" --nonlocal-state --no-cache >"$TMP/m" 2>/dev/null

# ── (B) + (C) + (D) + (G) + (H) + (I) the golden, its controls, and the honesty attributes ────────────
python3 - "$TMP/a" "$TMP/m" <<'PY'
import sys, xml.etree.ElementTree as ET

# HAND-DERIVED — see the derivation block at the top of this file before touching a number here.
GOLD = {
    "outer":   dict( writes = 2, reads = 1, direct_writes = 1, direct_reads = 0 ),
    "bump":    dict( writes = 1, reads = 1, direct_writes = 1, direct_reads = 1 ),
    "bump_py": dict( writes = 1, reads = 1, direct_writes = 1, direct_reads = 1 ),
    "peek":    dict( writes = 0, reads = 1, direct_writes = 0, direct_reads = 1 ),
    "peek_py": dict( writes = 0, reads = 1, direct_writes = 0, direct_reads = 1 ),
}
ORDER  = [ "outer", "bump", "bump_py", "peek", "peek_py" ]
KEYS   = ( "writes", "reads", "direct_writes", "direct_reads" )
CELLS  = 3

def audit( path, label ):
    """Returns (complaints, root, rows); empty complaints == the golden holds."""
    root = ET.parse( path ).getroot()
    rows = root.findall( "fn" )
    bad  = []
    byName = { node.get( "n" ): node for node in rows }
    if sorted( byName ) != sorted( GOLD ):
        bad.append( f"{label}: expected functions {sorted(GOLD)}, got {sorted(byName)}" )
        return bad, root, rows
    for name, want in GOLD.items():
        node = byName[ name ]
        for key in KEYS:
            got = node.get( key )
            if got is None or int( got ) != want[ key ]:
                bad.append( f"{label}: {name}@{key} expected {want[key]}, got {got}" )
    if root.get( "cells" ) != str( CELLS ):
        bad.append( f"{label}: root cells= expected {CELLS}, got {root.get('cells')}" )
    if root.get( "functions" ) != str( len( GOLD ) ):
        bad.append( f"{label}: root functions= expected {len(GOLD)}, got {root.get('functions')}" )
    return bad, root, rows

bad, root, rows = audit( sys.argv[1], "golden" )
for line in bad:
    print( "  FAIL  (B) " + line )
if not bad:
    print( "  PASS  (B) every count of all five functions matches the hand-derivation, and so do cells=/functions=" )

# (C) DIRECTION IS THE POINT OF THE VERB — reads and writes must not collapse into one number.
order = [ node.get( "n" ) for node in rows ]
if order != ORDER:
    print( f"  FAIL  (C) expected row order {ORDER}, got {order}" )
    bad.append( "order" )
else:
    print( "  PASS  (C1) rows are ranked most-writes-first, ties broken by reads then path then line" )

dirBad = []
for node in rows:
    name  = node.get( "n" )
    cells = node.findall( "cell" )
    dirs  = [ c.get( "dir" ) for c in cells ]
    if any( d not in ( "r", "w", "rw" ) for d in dirs ):
        dirBad.append( f"{name}: a cell carries a dir= outside r|w|rw: {dirs}" )
    # at_dir= is what the OWN BODY does and must be a SUBSET of dir= (which folds in the callee closure).
    # A superset would mean the row under-reports what this function itself provably does.
    for c in cells:
        atDir = c.get( "at_dir" )
        if atDir is None:
            continue
        if not set( atDir ) <= set( c.get( "dir" ) ):
            dirBad.append( f"{name}/{c.get('n')}: at_dir={atDir} is not a subset of dir={c.get('dir')}" )
    wrote = sum( 1 for d in dirs if d in ( "w", "rw" ) )
    read  = sum( 1 for d in dirs if d in ( "r", "rw" ) )
    # the children are capped independently of the counts; on this fixture nothing is capped, so the
    # per-row cell children must add up to the row's own numbers exactly.
    if node.get( "cells_capped" ) is None:
        if wrote != int( node.get( "writes" ) ):
            dirBad.append( f"{name}: {wrote} cell(s) marked written, row says writes={node.get('writes')}" )
        if read != int( node.get( "reads" ) ):
            dirBad.append( f"{name}: {read} cell(s) marked read, row says reads={node.get('reads')}" )
if dirBad:
    for line in dirBad:
        print( "  FAIL  (C2) " + line )
    bad.append( "dir" )
else:
    print( "  PASS  (C2) every cell child carries dir=r|w|rw and the children reconcile with the row counts" )

# (G) the immutability filter — a `const` declaration is not mutable state and must appear NOWHERE.
if any( c.get( "n" ) == "kMax" for node in rows for c in node.findall( "cell" ) ):
    print( "  FAIL  (G) `kMax` (a const declaration) was emitted as a mutable state cell" )
    bad.append( "const" )
else:
    print( "  PASS  (G) the const declaration `kMax` is not a cell" )

# (H) provenance: a direct touch names its use site, a transitive one names the callee it came through.
provBad = []
for node in rows:
    for c in node.findall( "cell" ):
        at, via = c.get( "at" ), c.get( "via" )
        if ( at is None ) == ( via is None ):
            provBad.append( f"{node.get('n')}/{c.get('n')}: expected exactly one of at= / via=, got at={at} via={via}" )
# outer reaches g_counter ONLY through bump — that cell must carry via="bump", never at=.
outerCells = { c.get( "n" ): c for c in rows[0].findall( "cell" ) } if rows else {}
if "g_counter" not in outerCells:
    provBad.append( "outer does not report g_counter at all — the transitive closure did not run" )
elif outerCells[ "g_counter" ].get( "via" ) != "bump":
    provBad.append( f"outer/g_counter expected via=\"bump\", got via={outerCells['g_counter'].get('via')}" )
if provBad:
    for line in provBad:
        print( "  FAIL  (H) " + line )
    bad.append( "prov" )
else:
    print( "  PASS  (H) direct cells carry at=, transitive cells carry via=, and outer reaches g_counter via bump" )

# (I) honesty — the counts are a FLOOR and the root says so.
if root.get( "counts_floor" ) != "1":
    print( "  FAIL  (I) the root does not carry counts_floor=\"1\" — an unsound count presented as exact" )
    bad.append( "floor" )
else:
    print( "  PASS  (I) the root carries counts_floor=\"1\"" )

# (D) MUTATION CONTROL — the identical audit against the mutated fixture MUST fail, or arm (B) is
#     asserting nothing. A gate that cannot go red is not a gate.
mutantBad, _, _ = audit( sys.argv[2], "mutant" )
if mutantBad:
    print( f"  PASS  (D) mutation control: the same expectations go RED when g_shared becomes const ({len(mutantBad)} mismatch(es))" )
else:
    print( "  FAIL  (D) mutation control: the mutated fixture still satisfies the golden — arm (B) proves nothing" )
    bad.append( "mutation" )

raise SystemExit( 1 if bad else 0 )
PY
[ $? -eq 0 ] || fail=1

# ── (I cont.) the legend must NAME the unsound cases rather than let the reader assume soundness ───────
legend="$( "$BIN" "$FIXTURE" --nonlocal-state --no-cache 2>/dev/null | head -c 4000 )"
missing=""
for phrase in "indirect" "alias" "shadow"; do
    printf '%s' "$legend" | grep -qi -- "$phrase" || missing="$missing $phrase"
done
if [ -z "$missing" ]; then
    ok "(I) the legend discloses the analysis blind spots (indirect calls, aliasing, shadowing)"
else
    no "(I) the legend never mentions:$missing — an unsound number presented as exact"
fi

# ── (E) paging disclosure (src/pageview.h, THE TRUNCATION VOCABULARY) ─────────────────────────────────
page="$( "$BIN" "$FIXTURE" --nonlocal-state --limit=1 --no-cache 2>/dev/null | grep -o '<nonlocal_state [^>]*>' | head -1 )"
pageRows="$( "$BIN" "$FIXTURE" --nonlocal-state --limit=1 --no-cache 2>/dev/null | grep -c '<fn ' )"
wantAttrs='shown="1" capped="1" total="5" has_more="1" next_offset="1"'
if [ "$pageRows" != "1" ]; then
    no "(E) limit=1 emitted $pageRows row(s), expected 1"
elif printf '%s' "$page" | grep -q "$wantAttrs"; then
    ok "(E) limit=1 discloses $wantAttrs"
else
    no "(E) limit=1 root element lacks '$wantAttrs': $page"
fi

# ── (F) purely additive (G5): the flagless map is untouched by the new code path ───────────────────────
"$BIN" "$FIXTURE" --no-cache >"$TMP/map1" 2>/dev/null
"$BIN" "$FIXTURE" --nonlocal-state --no-cache >/dev/null 2>&1
"$BIN" "$FIXTURE" --no-cache >"$TMP/map2" 2>/dev/null
if cmp -s "$TMP/map1" "$TMP/map2" && ! grep -q 'direct_writes=' "$TMP/map1"; then
    ok "(F) the flagless map is unchanged and carries no nonlocal-state attribute"
else
    no "(F) the flagless map is not additive-clean (differs across runs, or leaks direct_writes=)"
fi

# ── well-formedness (G4): the report must pipe clean through an XML parser ────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if "$BIN" "$FIXTURE" --nonlocal-state --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null; then
        ok "(G4) the report is well-formed XML"
    else
        no "(G4) the report does not parse as XML"
    fi
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "nonlocalstatecheck: FAILURES ABOVE"
exit "$fail"
