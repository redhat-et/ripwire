#!/usr/bin/env bash
# affectedgroupcheck.sh — a tests_to_run row with a runner may ride a <g> group, and NO command is lost.
#
# THE DEFECT WAS A REDUNDANCY THAT DISABLED AN OPTIMISATION THAT ALREADY EXISTED. E1 (2026-09-12) serves
# rows with equal attributes as ONE `<g n= p="a,b,c">` row — but only runner-less rows, because a row with a
# runner carries `run="<verb> <its own path>"`, and an attribute that embeds p= makes every row distinct. On
# koa every one of 46 rows has the signature hops|p|run and one verb, and not one of them grouped; `run=`
# was 2,424 B of a 6,189 B answer, spelling 46 paths a second time.
#
# THE RULE (src/testmap.h, groupRunHead). A row whose command is EXACTLY "<head> <its own p=>" — decided per
# row, at emit time, by string comparison, never by trusting how often that holds — may share a group with
# its contiguous neighbours of equal attributes AND equal head; the group says the head once, as a TEMPLATE:
#     <g hops="1" n="3" p="a,b,c" run_each="pytest {p}"/>
# and a member's command is the template with its one trailing {p} replaced by that member's path. A template,
# not a bare verb: an unexpanded `python3 {p}` errors visibly, an unexpanded bare `pytest` runs the whole suite.
#
# THE HOLD-OUTS. Every row whose command is NOT that shape stays a single row with its full run=, because the
# naive "verb + p" reading is quietly WRONG for it:
#   STEM / MENTION   p="test/h.cpp" run="bash test/drive_all.sh"      (the runner is another file)
#   cd-subshell      run="(cd pkg && npx jest '__tests__/u1\.test\.js')"  (package-relative, regex-escaped)
#   quoted / `--`    run="python3 -- 'tests/test_a2 sp.py'"
#   multi-root       the command is a disk path, p= a label (the corpus mode below covers it by comparison)
# and rows of two different verbs never share a group (python3 beside pytest: the verb is information).
#
# THE CENTRAL ARM reconstructs every file's command from the grouped answer — through test/testrowpaths.py's
# expand_run_each, THE one reader — and compares it, in order, against an oracle that grouping cannot have
# touched: in the suite, the commands written out by hand below for a fixture built here; in CORPUS MODE, the
# flat answer of a pre-change binary on real repositories, byte for byte.
#
# MUTATION CONTROLS, each of which must go RED or the arm above proves nothing: a group's harness corrupted;
# a member path dropped (with and without n= repaired); two rows whose commands differ merged into one group;
# and the flat (pre-change) answer fed in as if it were the new one.
#
# Usage:  test/affectedgroupcheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/affectedgroupcheck.sh
# Corpus mode (opt-in, never part of the suite — the corpora and the pre-change binary are not in the tree):
#         AFFG_FLAT_BIN=/path/to/pre-change/ripwire AFFG_CORPORA=/dir/of/checkouts test/affectedgroupcheck.sh
#         AFFG_CASES="repo:selector repo:selector …" overrides the built-in case list.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "affectedgroupcheck: BIN=$BIN"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
export PYTHONDONTWRITEBYTECODE=1

# ── THE FIXTURES ───────────────────────────────────────────────────────────────────────────────────────
# F  (main): python3 rows at two hop depths, one of them interrupted by a path that needs quoting; C++ harnesses with a
#            STEM runner, a MENTION runner and no runner at all; a jest package BELOW the root (the cd-subshell).
# M  (mixed): a pytest project where files alternate between having a main guard (python3) and not (pytest),
#            followed by a run of three pytest files — so ONE answer carries two verbs.
F="$WORK/main"; M="$WORK/mixed"
mkdir -p "$F/lib" "$F/tests" "$F/src" "$F/test" "$F/pkg/src" "$F/pkg/__tests__" "$M/lib" "$M/tests"
pytest_file(){   # pytest_file FILE IMPORT CALL GUARD(0|1)
    printf 'from lib.%s import %s\n\n\ndef test_it():\n    assert %s( 1 ) > 0\n' "$2" "$3" "$3" > "$1"
    if [ "$4" = 1 ]; then printf '\n\nif __name__ == "__main__":\n    test_it()\n' >> "$1"; fi
}
printf 'def core( x ):\n    return x + 1\n' > "$F/lib/core.py"
printf 'from lib.core import core\n\n\ndef mid( x ):\n    return core( x ) + 1\n' > "$F/lib/mid.py"
for n in a0 a1 a2 a3 a4; do pytest_file "$F/tests/test_$n.py" core core 1; done
pytest_file "$F/tests/test_a2 sp.py" core core 1          # ' ' sorts before '.', so this sits BETWEEN a1 and a2
for n in b0 b1 b2; do pytest_file "$F/tests/test_$n.py" mid mid 1; done
printf 'int leaf( int x )\n{\n    return x + 1;\n}\n' > "$F/src/leaf.cpp"
for n in h_stem h_ment h_none1 h_none2; do printf 'int leaf( int x );\nint test_%s( void )\n{\n    return leaf( 1 );\n}\n' "$n" > "$F/test/$n.cpp"; done
printf '#!/usr/bin/env bash\necho stem\n' > "$F/test/h_stem.sh"
printf '#!/usr/bin/env bash\n# drives h_ment.cpp\necho ment\n' > "$F/test/drive_all.sh"
printf '{ "name": "pkg", "devDependencies": { "jest": "^29.0.0" }, "scripts": { "test": "jest" } }\n' > "$F/pkg/package.json"
printf 'function util( x )\n{\n    return x + 1;\n}\nmodule.exports = { util };\n' > "$F/pkg/src/util.js"
for n in u1 u2 u3; do printf "const { util } = require( '../src/util.js' );\ntest( '%s', () => { expect( util( 1 ) ).toBe( 2 ); } );\n" "$n" > "$F/pkg/__tests__/$n.test.js"; done

printf '[pytest]\n' > "$M/pytest.ini"
printf 'def core( x ):\n    return x + 1\n' > "$M/lib/core.py"
pytest_file "$M/tests/test_m1.py" core core 1; pytest_file "$M/tests/test_m2.py" core core 0
pytest_file "$M/tests/test_m3.py" core core 1; pytest_file "$M/tests/test_m4.py" core core 0
for n in m5 m6 m7; do pytest_file "$M/tests/test_$n.py" core core 0; done
for d in "$F" "$M"; do ( cd "$d" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 ); done

FSEL="lib/core.py,src/leaf.cpp,pkg/src/util.js"
MSEL="lib/core.py"
rwf(){ ( cd "$F" && "$BIN" . "$@" --no-cache 2>"$WORK/stderr" ); }
rwm(){ ( cd "$M" && "$BIN" . "$@" --no-cache 2>"$WORK/stderr" ); }
rwf --affected="$FSEL"                  > "$WORK/f.xml"      || no "(setup) --affected on the main fixture exited $?: $( head -c 300 "$WORK/stderr" )"
rwf --affected="$FSEL"                  > "$WORK/f2.xml"
rwf --affected="$FSEL" --legend=compact > "$WORK/fc.xml"
rwf --affected=src/leaf.cpp --legend=compact > "$WORK/fleaf.xml"
rwf --test-gate="$FSEL"                 > "$WORK/f.tg.xml"
rwf --test-gate="$FSEL" --json          > "$WORK/f.tg.json"
rwf --situ="$FSEL"                      > "$WORK/f.situ.txt"
rwm --affected="$MSEL"                  > "$WORK/m.xml"      || no "(setup) --affected on the mixed fixture exited $?: $( head -c 300 "$WORK/stderr" )"
# the fixture's own test files, read off the DISK — arm 0 holds the handwritten expectation to this listing
( cd "$F" && find tests test pkg/__tests__ -type f \( -name '*.py' -o -name '*.cpp' -o -name '*.js' \) | LC_ALL=C sort ) > "$WORK/f.disk"
( cd "$M" && find tests -type f -name '*.py' | LC_ALL=C sort ) > "$WORK/m.disk"

# ── ARM D — determinism: the grouped answer is byte-identical run to run (member order included) ──────
if cmp -s "$WORK/f.xml" "$WORK/f2.xml" && [ -s "$WORK/f.xml" ]; then ok "(D) two runs of the grouped --affected answer are byte-identical ($( wc -c < "$WORK/f.xml" | tr -d ' ' ) B)"
else no "(D) two runs of --affected differ, or the answer is empty"; fi

# ── ARM W — well-formed, and the grouped document still parses as XML ──────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    w=0; for d in f.xml fc.xml m.xml f.tg.xml; do xmllint --noout "$WORK/$d" 2>/dev/null || { w=1; no "(W) $d is not well-formed XML"; }; done
    [ "$w" = 0 ] && ok "(W) the grouped answers pass xmllint --noout (affected full + compact, mixed, test-gate)"
else
    no "(W) xmllint missing — the well-formedness arm cannot run"
fi

ROOT="$ROOT" WORK="$WORK" python3 - <<'PY' || fail=1
import os, re, sys
sys.path.insert( 0, os.path.join( os.environ[ "ROOT" ], "test" ) )
import testrowpaths as trp                      # THE shared reader: singles, run_unknown groups and run_each groups

W = os.environ[ "WORK" ]
def rd( n ): return open( os.path.join( W, n ), encoding = "utf-8" ).read()
bad = 0
def ok( m ):
    print( "  PASS  " + m )
def no( m ):
    global bad
    bad = 1
    print( "  FAIL  " + m )

# ── THE ORACLE, written by hand from the fixture — nothing here is read from the binary under test ─────
# ( path, command or None for run_unknown, must it ride a group? ), in EVIDENCE order: hops asc, then path.
PY3 = "python3 "
MAIN = (
    [ ( "pkg/__tests__/u%d.test.js" % i, "(cd pkg && npx jest '__tests__/u%d\\.test\\.js')" % i, False ) for i in ( 1, 2, 3 ) ] +   # cd-subshell
    [ ( "test/h_ment.cpp",  "bash test/drive_all.sh", False ),                                                                   # MENTION
      ( "test/h_none1.cpp", None, True ), ( "test/h_none2.cpp", None, True ),                                                    # runner-less: E1's group
      ( "test/h_stem.cpp",  "bash test/h_stem.sh", False ),                                                                      # STEM
      ( "tests/test_a0.py", PY3 + "tests/test_a0.py", True ), ( "tests/test_a1.py", PY3 + "tests/test_a1.py", True ),
      ( "tests/test_a2 sp.py", "python3 -- 'tests/test_a2 sp.py'", False ),                                                      # quoted + `--`
      ( "tests/test_a2.py", PY3 + "tests/test_a2.py", True ), ( "tests/test_a3.py", PY3 + "tests/test_a3.py", True ),
      ( "tests/test_a4.py", PY3 + "tests/test_a4.py", True ) ] +
    [ ( "tests/test_b%d.py" % i, PY3 + "tests/test_b%d.py" % i, True ) for i in ( 0, 1, 2 ) ]                                    # hops=2
)
MIXED = [ ( "tests/test_m1.py", "python3 tests/test_m1.py", False ), ( "tests/test_m2.py", "pytest tests/test_m2.py", False ),
          ( "tests/test_m3.py", "python3 tests/test_m3.py", False ), ( "tests/test_m4.py", "pytest tests/test_m4.py", True ),
          ( "tests/test_m5.py", "pytest tests/test_m5.py", True ),  ( "tests/test_m6.py", "pytest tests/test_m6.py", True ),
          ( "tests/test_m7.py", "pytest tests/test_m7.py", True ) ]
HOLDOUTS = { "cd-subshell": "pkg/__tests__/u2.test.js", "MENTION": "test/h_ment.cpp", "STEM": "test/h_stem.cpp", "quoted/--": "tests/test_a2 sp.py" }

def body_of( doc ):
    return trp.strip_comments( doc )

def group_rows( doc ):
    """every tests_to_run <g> row of an XML document, as ( attrs dict, raw row )"""
    out = []
    for m in re.finditer( r'<g\b[^>]*/>', body_of( doc ) ):
        at = dict( re.findall( r'\s([A-Za-z_]+)="([^"]*)"', m.group( 0 ) ) )
        if "run_each" in at or at.get( "run_unknown" ) == "1":
            out.append( ( at, m.group( 0 ) ) )
    return out

def verify( doc, oracle, want_groups = True, reader = None ):
    """The claim, as a list of failure strings (empty = holds). `oracle` rows are ( path, cmd, grouped )."""
    fails = []
    try:
        rows = ( reader or trp.xml_rows )( doc )
    except Exception as e:                       # a template the reader refuses is a failure of the document
        return [ "unreadable: %s" % e ]
    got  = [ ( p, c ) for p, c, _g in rows ]
    want = [ ( p, c ) for p, c, _g in oracle ]
    if got != want:
        miss = [ r for r in want if r not in got ]
        xtra = [ r for r in got if r not in want ]
        fails.append( "RECONSTRUCTION: the commands read back are not the oracle's, in order — missing %r, unexpected %r%s"
                      % ( miss[:3], xtra[:3], "" if miss or xtra else " (same rows, ORDER differs)" ) )
    if reader is None:
        for at, raw in group_rows( doc ):
            n = len( [ p for p in at.get( "p", "" ).split( "," ) if p ] )
            if str( n ) != at.get( "n" ):
                fails.append( "COUNT: a group says n=%s and lists %d paths: %s" % ( at.get( "n" ), n, raw[:120] ) )
            if ( "run_each" in at ) == ( at.get( "run_unknown" ) == "1" ):
                fails.append( "DISCLOSURE: a group carries both or neither of run_each=/run_unknown=: %s" % raw[:120] )
        tests = re.findall( r'<affected\b[^>]*?\btests="(\d+)"', body_of( doc ) )
        if tests and tests[0] != str( len( oracle ) ):
            fails.append( "COUNT: the root says tests=%s for %d files" % ( tests[0], len( oracle ) ) )
    if want_groups:
        grouped_got  = sorted( p for p, _c, g in rows if g )
        grouped_want = sorted( p for p, _c, g in oracle if g )
        if grouped_got != grouped_want:
            fails.append( "GROUPING: the files riding a <g> row are %r, expected %r" % ( grouped_got, grouped_want ) )
    return fails

def must_hold( label, doc, oracle, **kw ):
    f = verify( doc, oracle, **kw )
    if f:
        no( "%s: %s" % ( label, " | ".join( f ) ) )
    else:
        ok( label )
    return not f

def must_red( label, doc, oracle, needle, **kw ):
    """a mutation control: verify() must FAIL, and for the stated reason (a red for another reason is not this control)"""
    f = verify( doc, oracle, **kw )
    hit = [ x for x in f if x.startswith( needle ) ]
    if hit:
        ok( "%s goes RED (%s)" % ( label, hit[0][:110] ) )
    else:
        no( "%s did NOT go red on %s — the arm it controls cannot catch this (failures seen: %r)" % ( label, needle, f ) )

def mutate( label, doc, old, new, count = 1 ):
    """str.replace that refuses to be a no-op: a control whose mutation did not apply passes for the wrong reason"""
    if doc.count( old ) < 1:
        no( "%s: the mutation target %r is not in the document — the control is vacuous" % ( label, old ) )
        return None
    return doc.replace( old, new, count )

f, fc, m = rd( "f.xml" ), rd( "fc.xml" ), rd( "m.xml" )

# ── ARM 0 — NON-VACUITY: the oracle tracks the fixture, and the fixture produces every shape ──────────
# The handwritten rows are held to the files actually on DISK (a fixture edited without its oracle, or the
# reverse, fails here instead of letting the arms below agree with a stale list), and each shape the later
# arms assert over is counted off the oracle itself.
disk_f = rd( "f.disk" ).split( "\n" )[:-1]
disk_m = rd( "m.disk" ).split( "\n" )[:-1]
if sorted( p for p, _c, _g in MAIN ) != sorted( disk_f ):
    no( "(0) the main oracle no longer names the fixture's test files: oracle-only %r, disk-only %r"
        % ( sorted( set( p for p, _c, _g in MAIN ) - set( disk_f ) ), sorted( set( disk_f ) - set( p for p, _c, _g in MAIN ) ) ) )
elif sorted( p for p, _c, _g in MIXED ) != sorted( disk_m ):
    no( "(0) the mixed oracle no longer names its fixture's test files" )
else:
    templ    = sum( 1 for p, c, g in MAIN if g and c is not None )
    unknown  = sum( 1 for p, c, g in MAIN if g and c is None )
    held     = sum( 1 for p, c, g in MAIN if not g and c is not None )
    verbs_m  = sorted( set( c.split( " " )[0] for _p, c, _g in MIXED ) )
    if templ < 5 or unknown < 2 or held < 6 or verbs_m != [ "pytest", "python3" ] or any( HOLDOUTS[k] not in [ p for p, _c, g in MAIN if not g ] for k in HOLDOUTS ):
        no( "(0) the oracle lost a shape: %d template-group files, %d runner-less group files, %d held-out singles, mixed verbs %r" % ( templ, unknown, held, verbs_m ) )
    else:
        ok( "(0) oracle == fixture on disk (%d + %d files): %d template-group files, %d runner-less group files, %d held-out singles, mixed verbs %s"
            % ( len( MAIN ), len( MIXED ), templ, unknown, held, "+".join( verbs_m ) ) )

# ── ARM 1 — THE CENTRAL ARM: every command reconstructs exactly, in order, and the grouping FIRES ─────
main_ok  = must_hold( "(1a) main fixture: all %d commands reconstruct from the grouped answer, in evidence order, and the expected files ride groups" % len( MAIN ), f, MAIN )
must_hold( "(1b) mixed-verb fixture: all %d commands reconstruct; python3 and pytest never share a group" % len( MIXED ), m, MIXED )
must_hold( "(1c) --legend=compact carries the same rows", fc, MAIN )

# ── ARM 2 — the hold-outs: each stays a SINGLE row carrying its full run= ─────────────────────────────
rows_by_path = { p: ( c, g ) for p, c, g in trp.xml_rows( f ) }
want_by_path = { p: c for p, c, _g in MAIN }
for kind, path in sorted( HOLDOUTS.items() ):
    c, g = rows_by_path.get( path, ( "<absent>", None ) )
    single = re.search( r'<test p="%s"[^>]*\brun="[^"]+"[^>]*/>' % re.escape( path ), body_of( f ) )
    if g is False and single and c == want_by_path[ path ]:
        ok( "(2) %s hold-out %s is a single row with its full run= (%s)" % ( kind, path, c ) )
    else:
        no( "(2) %s hold-out %s: grouped=%r command=%r, single-row-with-run=%r" % ( kind, path, g, c, bool( single ) ) )
alt = [ ( p, g ) for p, _c, g in trp.xml_rows( m ) if p in ( "tests/test_m1.py", "tests/test_m2.py", "tests/test_m3.py" ) ]
if [ g for _p, g in alt ] == [ False, False, False ]:
    ok( "(2) mixed verbs: the alternating python3/pytest rows m1,m2,m3 each stay single with a full run=" )
else:
    no( "(2) mixed verbs: m1..m3 alternate python3/pytest and must not group: %r" % alt )
templates = sorted( at[ "run_each" ] for at, _r in group_rows( f ) + group_rows( m ) if "run_each" in at )
if templates and all( t.endswith( " {p}" ) and t.count( "{p}" ) == 1 for t in templates ):
    ok( "(2) every group harness is a TEMPLATE ending in its one {p} slot, never a bare verb: %r" % sorted( set( templates ) ) )
else:
    no( "(2) expected run_each templates of the form '<head> {p}', got %r" % templates )

# ── ARM 3 — MUTATION CONTROLS: each must go RED, for its own reason ───────────────────────────────────
x = mutate( "(3a)", f, 'run_each="python3 {p}"', 'run_each="pytest {p}"' )
if x: must_red( "(3a) a group's harness corrupted (python3 -> pytest)", x, MAIN, "RECONSTRUCTION" )
x = mutate( "(3b)", f, "tests/test_a3.py,", "" )
if x: must_red( "(3b) a member path dropped from a group", x, MAIN, "RECONSTRUCTION" )
if x: must_red( "(3b') the same drop is also caught by n=", x, MAIN, "COUNT" )
x = mutate( "(3c)", f, "tests/test_a3.py,", "" )
x = x and mutate( "(3c)", x, 'n="3" p="tests/test_a2.py', 'n="2" p="tests/test_a2.py' )
if x: must_red( "(3c) a member dropped AND n= repaired to match", x, MAIN, "RECONSTRUCTION" )
one = '<test p="tests/test_m1.py" hops="1" run="python3 tests/test_m1.py"/><test p="tests/test_m2.py" hops="1" run="pytest tests/test_m2.py"/>'
x = mutate( "(3d)", m, one, '<g hops="1" n="2" p="tests/test_m1.py,tests/test_m2.py" run_each="python3 {p}"/>' )
if x: must_red( "(3d) two rows whose commands genuinely differ merged under one harness", x, MIXED, "RECONSTRUCTION" )
x = mutate( "(3e)", f, 'run_each="python3 {p}"', 'run_each="python3"' )
if x: must_red( "(3e) a bare verb in place of the template (the reader refuses to expand it)", x, MAIN, "unreadable" )
# (3f) the FLAT answer — what the pre-change binary serves: every runner row a single row — fed in as if new.
# Built from the oracle, not from the answer under test: the root and legend are kept, the rows re-rendered flat.
def flat_doc( doc, oracle ):
    body_at = doc.index( "<affected " )
    head_end = doc.index( ">", body_at ) + 1
    hops = { p: "2" if p.startswith( "tests/test_b" ) else "1" for p, _c, _g in oracle }
    esc = lambda s: s.replace( "&", "&amp;" ).replace( "'", "&apos;" )
    rows = "".join( '<test p="%s" hops="%s"%s/>' % ( p, hops[p], ' run="%s"' % esc( c ) if c is not None else ' run_unknown="1"' ) for p, c, _g in oracle )
    return doc[ :head_end ] + rows + "</affected>"
flat = flat_doc( f, MAIN )
must_hold( "(3f) control of the control: the flat rendering reconstructs to the same commands (it is the reference)", flat, MAIN, want_groups = False )
must_red( "(3f) the flat pre-change answer fed in as the new one", flat, MAIN, "GROUPING" )

# ── ARM 4 — the same rows through the other dialects of the ONE seam ──────────────────────────────────
want_map = { p: c for p, c, _g in MAIN }
for label, name, reader in ( ( "--test-gate XML", "f.tg.xml", trp.xml_rows ), ( "--test-gate --json", "f.tg.json", trp.json_rows ), ( "--situ text", "f.situ.txt", trp.text_rows ) ):
    try:
        rows = reader( rd( name ) )
    except Exception as e:
        no( "(4) %s unreadable: %s" % ( label, e ) )
        continue
    got_map = { p: c for p, c, _g in rows }
    grouped = sorted( p for p, c, g in rows if g and c is not None )
    if got_map != want_map or len( rows ) != len( MAIN ):
        diff = sorted( k for k in set( got_map ) | set( want_map ) if got_map.get( k, "<absent>" ) != want_map.get( k, "<absent>" ) )
        no( "(4) %s: commands differ from the oracle on %r" % ( label, diff[:4] ) )
    elif grouped != sorted( p for p, c, g in MAIN if g and c is not None ):
        no( "(4) %s: the template groups cover %r" % ( label, grouped ) )
    else:
        ok( "(4) %s: all %d commands reconstruct, %d of them from run_each groups" % ( label, len( rows ), len( grouped ) ) )

# ── ARM 5 — DISCLOSURE PRESERVATION: grouping removes repeats, never a disclosure ─────────────────────
root = re.search( r"<affected\b[^>]*>", body_of( f ) ).group( 0 )
need = [ 'tests="%d"' % len( MAIN ), 'counts_floor="1"', "graph_unresolved=", "script_gates_unmodelled=", 'order="evidence"', "run_first=" ]
lost = [ a for a in need if a not in root ]
if lost:
    no( "(5a) the grouped answer's root lost %r: %s" % ( lost, root ) )
else:
    ok( "(5a) the root still carries tests=/counts_floor=/graph_unresolved=/script_gates_unmodelled=/order=/run_first=" )
rf = int( re.search( r'run_first="(\d+)"', root ).group( 1 ) ) if "run_first=" in root else -1
hops1 = sum( 1 for p, _c, _g in MAIN if not p.startswith( "tests/test_b" ) )
cut = 0
seen = 0
for mrow in re.finditer( r'<(?:test|g)\b[^>]*/>', body_of( f ) ):
    at = dict( re.findall( r'\s([A-Za-z_]+)="([^"]*)"', mrow.group( 0 ) ) )
    if seen == rf:
        cut = 1
    seen += int( at[ "n" ] ) if mrow.group( 0 ).startswith( "<g " ) else 1
if rf == hops1 and cut == 1:
    ok( "(5b) run_first=%d counts FILES and still falls on a row boundary: no group straddles the run-first head" % rf )
else:
    no( "(5b) run_first=%d (expected %d files at hops=1), on a row boundary: %s" % ( rf, hops1, bool( cut ) ) )
neither = [ p for p, c, _g in trp.xml_rows( f ) + trp.xml_rows( m ) if c == "<neither>" ]
unk = [ at for at, _r in group_rows( f ) if at.get( "run_unknown" ) == "1" ]
if neither or len( unk ) != 1 or unk[0].get( "p" ) != "test/h_none1.cpp,test/h_none2.cpp":
    no( "(5c) rows with no run disclosure %r; runner-less groups %r" % ( neither, unk ) )
else:
    ok( "(5c) every row says run=, run_each= or run_unknown= — and the runner-less pair is still ONE group saying run_unknown=\"1\"" )

# ── ARM 6 — the legend: run_each= is DEFINED wherever it is carried, and charged only there ───────────
def legend_of( doc ):
    return "".join( re.findall( r"<!--.*?-->", doc, flags = re.S ) )
leaf = rd( "fleaf.xml" )
if "run_each" not in legend_of( f ) or "{p}" not in legend_of( f ):
    no( "(6a) the full legend of a document carrying run_each= does not define it (and its {p} slot)" )
elif "run_each" not in legend_of( fc ) or "{p}" not in legend_of( fc ):
    no( "(6a) the COMPACT legend of a document carrying run_each= does not define it — the attribute ships undocumented" )
else:
    ok( "(6a) run_each= and its {p} slot are defined in the full and the compact legend of a document that carries one" )
if "run_each=" in body_of( leaf ):
    no( "(6b) the control document (--affected=src/leaf.cpp) was expected to carry no run_each= row" )
elif "run_each" in legend_of( leaf ):
    no( "(6b) a compact document with NO run_each= row still pays for its definition" )
else:
    ok( "(6b) a compact document with no run_each= row pays nothing for the term" )

# ── ARM 7 — the point of it: the grouped answer is SMALLER than the flat one it replaces ──────────────
gb, fb = len( body_of( f ).encode() ), len( body_of( flat ).encode() )
if main_ok and gb < fb:
    ok( "(7) rows+root: %d B grouped vs %d B flat on the main fixture (-%d B, %d rows -> %d)" % ( gb, fb, fb - gb, len( MAIN ), len( re.findall( r'<(?:test|g)\b[^>]*/>', body_of( f ) ) ) ) )
else:
    no( "(7) the grouped body (%d B) is not smaller than the flat one (%d B)" % ( gb, fb ) )
sys.exit( bad )
PY

# ── CORPUS MODE (opt-in) — every command on real repositories, against a PRE-CHANGE binary ────────────
# Not part of the suite: neither the corpora nor a pre-change binary is in the tree. What it proves is the
# fixture arms' claim at scale — the flat answer and the grouped one name the same files, in the same order,
# with byte-identical commands; the root tag and everything that is not a test row is byte-identical (no
# disclosure moved); and every row the naive "verb + p" rule gets wrong is still a single row, byte for byte.
if [ -n "${AFFG_FLAT_BIN:-}" ] && [ -n "${AFFG_CORPORA:-}" ]; then
    [ -x "$AFFG_FLAT_BIN" ] || no "(C) AFFG_FLAT_BIN=$AFFG_FLAT_BIN is not executable"
    CASES="${AFFG_CASES:-koa:lib/application.js flake8:src/flake8/style_guide.py starlette:starlette/routing.py pydantic:pydantic/fields.py django:django/utils/functional.py nest:packages/common/utils/shared.utils.ts cpython:Lib/json/decoder.py terraform:internal/addrs/module.go envoy:source/common/http/header_map_impl.cc vscode:src/vs/base/common/arrays.ts}"
    CACHE="${AFFG_CACHE_DIR:-$WORK/cache}"; mkdir -p "$CACHE"
    for case in $CASES; do
        repo="${case%%:*}"; sel="${case#*:}"; tagf="$( printf '%s' "$case" | tr -c 'A-Za-z0-9' '_' )"
        [ -d "$AFFG_CORPORA/$repo" ] || { no "(C) $repo: no checkout under $AFFG_CORPORA"; continue; }
        ( cd "$AFFG_CORPORA" && "$AFFG_FLAT_BIN" "$repo" --cache="$CACHE/$repo.flat.rwc" --affected="$sel" 2>/dev/null ) > "$WORK/c.$tagf.flat.xml"
        ( cd "$AFFG_CORPORA" && "$BIN"           "$repo" --cache="$CACHE/$repo.new.rwc"  --affected="$sel" 2>/dev/null ) > "$WORK/c.$tagf.new.xml"
        ( cd "$AFFG_CORPORA" && "$BIN"           "$repo" --cache="$CACHE/$repo.new.rwc"  --affected="$sel" 2>/dev/null ) > "$WORK/c.$tagf.new2.xml"
        ROOT="$ROOT" python3 - "$case" "$WORK/c.$tagf.flat.xml" "$WORK/c.$tagf.new.xml" "$WORK/c.$tagf.new2.xml" <<'PYC' || fail=1
import os, re, sys
sys.path.insert( 0, os.path.join( os.environ[ "ROOT" ], "test" ) )
import testrowpaths as trp
case, flat_p, new_p, new2_p = sys.argv[1:5]
flat, new, new2 = ( open( p, encoding = "utf-8" ).read() for p in ( flat_p, new_p, new2_p ) )
fails = []
if not flat or "<affected " not in flat:
    fails.append( "the pre-change binary produced no <affected> answer" )
else:
    fr, nr = trp.xml_rows( flat ), trp.xml_rows( new )
    if any( g and c is not None for _p, c, g in fr ):
        fails.append( "AFFG_FLAT_BIN already groups runner rows — it is not a pre-change binary" )
    if [ ( p, c ) for p, c, _g in fr ] != [ ( p, c ) for p, c, _g in nr ]:
        d = [ ( a, b ) for a, b in zip( fr, nr ) if a[:2] != b[:2] ][:2]
        fails.append( "RECONSTRUCTION: %d flat rows vs %d reconstructed; first differences %r" % ( len( fr ), len( nr ), d ) )
    strip_rows = lambda d: re.sub( r'<(?:test|g)\b(?![^>]*\bvia=)[^>]*/>', "", trp.strip_comments( d ) )
    if strip_rows( flat ) != strip_rows( new ):
        fails.append( "DISCLOSURE: the root tag or a non-row element (the class-new group, capped=/next=) differs once the test rows are removed" )
    # the hold-outs: a flat row whose command is not "<head> <p>" must be in the new answer byte for byte
    body_new = trp.strip_comments( new )
    held = 0
    for mrow in re.finditer( r'<test\b[^>]*/>', trp.strip_comments( flat ) ):
        at = dict( re.findall( r'\s([A-Za-z_]+)="([^"]*)"', mrow.group( 0 ) ) )
        if "run" in at and not trp.xml_unescape( at[ "run" ] ).endswith( " " + trp.xml_unescape( at[ "p" ] ) ):
            held += 1
            if mrow.group( 0 ) not in body_new:
                fails.append( "HOLD-OUT lost its single row: %s" % mrow.group( 0 )[:160] )
                break
    if new != new2:
        fails.append( "DETERMINISM: two runs of the new binary differ" )
    count = lambda d: len( re.findall( r'<(?:test|g)\b(?![^>]*\bvia=)[^>]*/>', trp.strip_comments( d ) ) )
    groups = sum( 1 for m in re.finditer( r'<g\b[^>]*\brun_each=', trp.strip_comments( new ) ) )
    stat = "files=%d hold-outs=%d rows %d -> %d (run_each groups %d) bytes %d -> %d (%+d, %.1f%%)" % (
           len( fr ), held, count( flat ), count( new ), groups, len( flat.encode() ), len( new.encode() ), len( new.encode() ) - len( flat.encode() ),
           100.0 * ( len( new.encode() ) - len( flat.encode() ) ) / max( 1, len( flat.encode() ) ) )
if fails:
    print( "  FAIL  (C) %s: %s" % ( case, " | ".join( fails ) ) )
    sys.exit( 1 )
print( "  PASS  (C) %s: every command identical to the pre-change answer, in order; non-row bytes identical; %s" % ( case, stat ) )
PYC
    done
else
    echo "  NOTE  corpus mode not requested (AFFG_FLAT_BIN + AFFG_CORPORA): the fixture arms above are the suite's proof"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
