#!/usr/bin/env bash
# affectedfoldcheck.sh — PATH-FOLD (2026-11-18): a tests_to_run group row on --affected, --test-gate and --situ may say
# its paths FOLDED, and the fold is LOSSLESS.
#
# WHAT THIS GUARDS. A <g> row lists n test files that share their evidence and their command template. Measured on 408
# --affected answers over 27 repositories those lists are 48.3% of the verb's bytes, no path repeats inside an answer
# (so a path table has nothing to index), and what does repeat is the DIRECTORY and the EXTENSION of sibling files.
# src/testmap.h now writes a row's list as
#
#     <g hops="2" n="4" pf="src/{a/{x,y}.test.ts,b.ts},README" run_each="node {p}"/>          XML
#     [hops=2] (4 folded): src/{a/{x,y}.test.ts,b.ts}, README   (run each: node {p})           --situ text
#
# where PRE{A,B}SUF stands for PREASUF,PREBSUF and braces nest (bash brace expansion over comma lists). The owner
# directive of 2026-11-18 approves a lossless form even where it reverses E1's "every path verbatim"; the bar this gate
# holds is therefore not the byte saving. It is that the answer, expanded by the stated rule and nothing else, is byte
# for byte what the binary printed before the change — same paths, same order, same n=, same commands, same counts.
#
# THREE INDEPENDENT REFERENCES, never one:
#   1. GOLDENS captured from the binary before the change (994f0021f) on the fixtures test/affectedfoldfix/build.sh
#      writes, committed under test/affectedfoldfix/golden/ (test/affectedfoldfix/capture.sh is the call list).
#      MIXED PROVENANCE, stated so nobody reads the directory as one capture: the files arms B/C/D compare against
#      are the 994f0021f bytes and must stay there — re-taking them would make "unfold(new) == the pre-fold answer"
#      compare the new answer with itself, and arm (A) refuses a golden that already carries the folded form. The
#      five files arms B/C/D never read — big/brace/odd/small.pack-task.xml and small.situ.txt, pure byte-identity
#      anchors for arm (E) — were re-taken at train/m5-1126-4 (2026-11-27) after #786 and #796 moved them on
#      purpose; the per-file deltas were diffed against the pre-train binary first (see arm (E)).
#   2. test/lib/pathfold.py — a reader and a writer written from the RULE, sharing no line with the C++. Its reader
#      unfolds the new answer (arm B/C); its writer must produce the very bytes the binary printed (arm D).
#   3. bash itself: each folded item is handed to the shell's own brace expansion (arm H) — the rule the legend states
#      is the one a reader without ripwire or this repository already has.
#
# ARMS
#   (A)  the fixtures are the bytes the goldens were captured on, and the goldens hold the rows the arms read (no pf=)
#   (B)  XML, --affected and --test-gate, compact and --legend=full: unfold(new) == golden outside the legend, and the
#        legend differs by ONE inserted run that defines pf= (LOSSLESS + DISCLOSED)
#   (C)  --situ text: same line count, and every moved line is its golden line plus ONE insertion the TEXT_CLAUSES
#        table names (the fold's own clause, which must be there; #796's floor= / floor_tail= on the [3] heading)
#   (D)  second reference: every pf= is pathfold.py's fold of the golden row, every p= row is one the rule leaves flat,
#        and the document-level decision is the rule's
#   (E)  what must not move: the under-the-bar fixture (every verb), --json, and the verbs that share the row seam but
#        do not fold (--exercises, --pack-task); a row holding a literal '{' keeps p= beside rows that fold.
#        The bar is byte-identity to a COMMITTED capture, so a deliberate disclosure elsewhere reds it (the same
#        contract test/printf_parity.manifest carries) and the remedy is the same: re-take the file and review the
#        diff against the previous binary, byte by byte, before committing it. Done once here, 2026-11-27 on
#        train/m5-1126-4: #786 put partners_none="no_git" plus its legend clause (and the est_tokens recount the
#        longer document earns) in all four pack-task answers, #796 put floor=/floor_tail= on small.situ.txt's [3]
#        heading, and nothing else in the fixture corpus moved at all.
#   (F)  counts and commands: tests=, shown_tests=, run_first=, every n=, every exit code (--test-gate's 4), and every
#        file's path and command through the shared reader, in order
#   (G)  mutation controls, each of which MUST go red
#   (H)  bash brace expansion of every folded item == the golden paths
#   (L)  the legend defines pf= exactly where a row carries it
#   (N)  determinism and well-formedness
#   (S)  at scale, when a pre-change binary and corpora are handed in (RIPWIRE_FOLD_REF, RIPWIRE_FOLD_CORPORA)
set -u
BIN="${RIPWIRE_BIN:-${1:-./build/ripwire}}"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; fi
case "$BIN" in /*) ;; *) BIN="$( cd "$( dirname "$BIN" )" && pwd )/$( basename "$BIN" )" ;; esac
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
FIXSRC="$ROOT/test/affectedfoldfix"
GOLD="$FIXSRC/golden"
export PYTHONDONTWRITEBYTECODE=1
export LC_ALL=C

fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── the checker: one python file, every arm a subcommand that prints "PASS …"/"FAIL …" lines and exits 0/1.
cat > "$TMP/chk.py" <<'PY'
import os, re, subprocess, sys
ROOT, GOLD, NEW = sys.argv[2], sys.argv[3], sys.argv[4]
sys.path.insert( 0, os.path.join( ROOT, "test", "lib" ) ); sys.path.insert( 0, os.path.join( ROOT, "test" ) )
import pathfold, testrowpaths
bad = 0
def ok( s ): print( "  PASS  " + s )
def no( s ):
    global bad
    bad = 1; print( "  FAIL  " + s )
def rd( d, name ): return open( os.path.join( d, name ), encoding = "utf-8", newline = "" ).read()
def split_legend( doc ):
    m = re.match( r"<!--.*?-->", doc, flags = re.S )
    return ( m.group( 0 ), doc[ m.end(): ] ) if m else ( "", doc )
def one_insertion( old, new ):
    """new == old with ONE contiguous run inserted: returns that run, or None."""
    i = 0
    while i < min( len( old ), len( new ) ) and old[i] == new[i]: i += 1
    j = 0
    while j < len( old ) - i and old[ len( old ) - 1 - j ] == new[ len( new ) - 1 - j ]: j += 1
    return new[ i:len( new ) - j ] if i + j == len( old ) and len( new ) > len( old ) else None
G_ROW = re.compile( r'<g\b[^>]*?\b(pf?)="([^"]*)"[^>]*/>' )
def g_rows( body ):
    return [ ( m.group( 1 ), m.group( 2 ), m.group( 0 ) ) for m in G_ROW.finditer( body ) if 'run_unknown="1"' in m.group( 0 ) or "run_each=" in m.group( 0 ) ]
XML  = [ "affected.xml", "affected.full.xml", "test-gate.xml", "test-gate.full.xml" ]
FOLD = [ "big", "brace", "odd" ]

def lossless_xml( name, new, gold, quiet = False ):
    """the kill bar for one XML document; returns a failure string or None"""
    nl, nb = split_legend( new ); gl, gb = split_legend( gold )
    if " pf=\"" not in nb: return "no pf= row — the fold did not fire"
    try: un = pathfold.unfold_xml( nb )
    except ValueError as e: return "the folded list is malformed: %s" % e
    if un != gb:
        k = next( ( i for i in range( min( len( un ), len( gb ) ) ) if un[i] != gb[i] ), min( len( un ), len( gb ) ) )
        return "unfolded body != golden body at byte %d: …%r vs …%r" % ( k, un[ max( 0, k - 30 ):k + 30 ], gb[ max( 0, k - 30 ):k + 30 ] )
    for attr, text, row in g_rows( nb ):
        n = int( re.search( r' n="(\d+)"', row ).group( 1 ) )
        got = len( pathfold.expand( text ) ) if attr == "pf" else len( text.split( "," ) )
        if got != n: return "a row's n=%d but its list holds %d paths" % ( n, got )
    ins = one_insertion( gl, nl )
    if ins is None: return "the legend is not the golden legend plus one inserted run"
    if "pf=" not in ins or "{" not in ins: return "the inserted legend run does not define pf=: %r" % ins
    return None

def arm_A():
    n = 0
    for fx in FOLD + [ "small" ]:
        for x in XML + [ "situ.txt", "test-gate.json", "exercises.xml", "pack-task.xml" ]:
            d = rd( GOLD, fx + "." + x ); n += 1
            if " pf=" in split_legend( d )[1] or " folded): " in d: no( "(A) golden %s.%s already carries the folded form" % ( fx, x ) )
    files = { fx: len( testrowpaths.xml_paths( rd( GOLD, fx + ".affected.xml" ) ) ) for fx in FOLD + [ "small" ] }
    if files != { "big": 45, "brace": 30, "odd": 12, "small": 3 }: no( "(A) the goldens do not name the fixture's test files: %r" % files )
    else: ok( "(A) %d goldens, none folded; they name big 45 / brace 30 / odd 12 / small 3 test files" % n )

def arm_B():
    n = rows = saved = 0
    for fx in FOLD:
        for x in XML:
            new, gold = rd( NEW, fx + "." + x ), rd( GOLD, fx + "." + x )
            why = lossless_xml( fx + "." + x, new, gold )
            if why: no( "(B) %s.%s: %s" % ( fx, x, why ) ); continue
            n += 1; rows += new.count( ' pf="' ); saved += len( gold ) - len( new )
            if len( new ) >= len( gold ): no( "(B) %s.%s folded and did not shrink (%d -> %d B)" % ( fx, x, len( gold ), len( new ) ) )
    if n == len( FOLD ) * len( XML ): ok( "(B) %d XML answers: unfold(new) == golden byte for byte outside the legend; %d pf= rows, %d B smaller with the legend term paid" % ( n, rows, saved ) )

# EVERY heading clause a --situ answer is allowed to have gained since the goldens were captured, as
# ( name, the golden heading it must ride on, a matcher for the WHOLE inserted run ). The comparison is
# LINE-SCOPED (same line count, same order, each moved line its golden line plus ONE insertion) and an
# insertion this table does not name is a FAIL that prints the bytes — so the arm stays a kill bar for
# collateral damage instead of degrading into "the heading got longer, probably fine".
#   fold:  the clause the fold itself defines, loose on purpose (its wording is the legend's to choose).
#   floor: #796, 2026-11-26. kCoSupportFloor rides on every [3] heading now, and floor_tail= names the
#          corroborated 2-commit tail a ONE-seed question also takes — so a one-file diff carries both
#          and a two-file diff carries only floor=. Matched EXACTLY: a third attribute goes red here.
TEXT_CLAUSES = ( ( "the fold's own definition", "[2] tests to run",
                   lambda s: "folded" in s and "{" in s ),
                 ( "#796's co-change support floor", "[3] co-change",
                   lambda s: re.fullmatch( r' floor="\d+"(?: floor_tail="corroborated")?', s ) is not None ) )

def lossless_text( new, gold ):
    if " folded): " not in new: return "no '(n folded):' line — the fold did not fire"
    try: un = pathfold.unfold_text( new )
    except ValueError as e: return "the folded list is malformed: %s" % e
    gl, nl = gold.split( "\n" ), un.split( "\n" )
    if len( gl ) != len( nl ): return "unfolded --situ text has %d lines, the golden %d" % ( len( nl ), len( gl ) )
    seen = {}
    for k in range( len( gl ) ):
        if gl[k] == nl[k]: continue
        ins = one_insertion( gl[k], nl[k] )
        if ins is None: return "line %d is not its golden line plus one inserted clause:\n      golden %r\n      new    %r" % ( k + 1, gl[k], nl[k] )
        name = next( ( nm for nm, anchor, fits in TEXT_CLAUSES if anchor in gl[k] and fits( ins ) ), None )
        if name is None: return "line %d carries an insertion this gate does not name: %r" % ( k + 1, ins )
        if name in seen: return "%s was inserted on two lines (%d and %d)" % ( name, seen[ name ], k + 1 )
        seen[ name ] = k + 1
    if "the fold's own definition" not in seen: return "unfolded --situ text is not the golden plus one inserted heading clause"
    if testrowpaths.text_rows( new ) != testrowpaths.text_rows( gold ): return "the shared reader names different files or commands"
    return None

def arm_C():
    n = 0
    for fx in FOLD:
        why = lossless_text( rd( NEW, fx + ".situ.txt" ), rd( GOLD, fx + ".situ.txt" ) )
        if why: no( "(C) %s.situ.txt: %s" % ( fx, why ) )
        else: n += 1
    if n == len( FOLD ): ok( "(C) %d --situ answers: unfold(new) == golden line for line but for the %d named heading clauses; same files and commands in order" % ( n, len( TEXT_CLAUSES ) ) )

def arm_D():
    n = folded = flat = 0
    for fx in FOLD + [ "small" ]:
        for x in XML:
            nb = split_legend( rd( NEW, fx + "." + x ) )[1]; gb = split_legend( rd( GOLD, fx + "." + x ) )[1]
            grows = [ testrowpaths.xml_unescape( t ).split( "," ) for _a, t, _r in g_rows( gb ) ]
            nrows = g_rows( nb )
            want_doc = pathfold.document_folds( grows )
            if want_doc != ( ' pf="' in nb ): no( "(D) %s.%s: the rule says the document %s, the binary did the other" % ( fx, x, "folds" if want_doc else "stays flat" ) ); continue
            if len( nrows ) != len( grows ): no( "(D) %s.%s: %d group rows, golden has %d" % ( fx, x, len( nrows ), len( grows ) ) ); continue
            for ( attr, text, _row ), paths in zip( nrows, grows ):
                want = pathfold.fold_row( paths ) if want_doc else None
                got  = testrowpaths.xml_unescape( text )
                if want is None and ( attr != "p" or got != ",".join( paths ) ): no( "(D) %s.%s: a row the rule leaves flat is not verbatim p=" % ( fx, x ) )
                elif want is not None and ( attr != "pf" or got != want ): no( "(D) %s.%s: pf= is not the reference fold:\n      binary    %s\n      reference %s" % ( fx, x, got[:200], want[:200] ) )
                else: folded += want is not None; flat += want is None
            n += 1
    if not bad: ok( "(D) %d XML answers: %d rows are byte-equal to pathfold.py's fold, %d rows flat exactly where the rule says" % ( n, folded, flat ) )

def arm_E():
    same = 0
    for name in sorted( os.listdir( GOLD ) ):
        fx = name.split( "." )[0]
        must = fx == "small" or name.endswith( ( ".json", ".exercises.xml", ".pack-task.xml", ".err" ) ) or name == "rc.txt"
        if not must: continue
        if not os.path.exists( os.path.join( NEW, name ) ) or rd( NEW, name ) != rd( GOLD, name ): no( "(E) %s moved; it must be byte-identical to the pre-change binary's" % name )
        else: same += 1
    extra = sorted( set( os.listdir( NEW ) ) - set( os.listdir( GOLD ) ) )
    if extra: no( "(E) the binary wrote output the golden run did not: %r" % extra )
    b = split_legend( rd( NEW, "brace.affected.xml" ) )[1]
    lit = [ ( a, t ) for a, t, _r in g_rows( b ) if "{{tpl}}" in t ]
    if len( lit ) != 1 or lit[0][0] != "p" or lit[0][1].count( "," ) != 5: no( "(E) the row holding a literal '{{tpl}}' directory must stay ONE verbatim p= row of 6: %r" % lit )
    elif not any( a == "pf" for a, _t, _r in g_rows( b ) ): no( "(E) brace: no other row folded beside the literal-brace row" )
    elif not bad: ok( "(E) %d outputs byte-identical (small fixture, --json, --exercises, --pack-task, exit codes); a literal-brace row keeps p= beside a pf= row" % same )

def arm_F():
    n = 0
    for fx in FOLD:
        for x in XML:
            new, gold = rd( NEW, fx + "." + x ), rd( GOLD, fx + "." + x )
            for a in ( "tests", "shown_tests", "run_first", "tests_capped", "untested", "reached" ):
                va, vb = re.search( r' %s="(\d+)"' % a, new ), re.search( r' %s="(\d+)"' % a, gold )
                if ( va and va.group( 1 ) ) != ( vb and vb.group( 1 ) ): no( "(F) %s.%s: %s= moved" % ( fx, x, a ) )
            if testrowpaths.xml_rows( new ) != testrowpaths.xml_rows( gold ): no( "(F) %s.%s: the shared reader names different files or commands" % ( fx, x ) )
            tests = int( re.search( r' tests="(\d+)"', new ).group( 1 ) )
            if len( testrowpaths.xml_rows( new ) ) != tests: no( "(F) %s.%s: tests=%d but the rows name %d files" % ( fx, x, tests, len( testrowpaths.xml_rows( new ) ) ) )
            n += 1
    cmds = [ ( p, c ) for p, c, g in testrowpaths.xml_rows( rd( NEW, "big.affected.xml" ) ) if g and c ]
    if len( cmds ) != 32 or not all( c == "pytest " + p for p, c in cmds ): no( "(F) big: run_each= must expand to one full command per folded member (32): %r" % cmds[:3] )
    if rd( NEW, "rc.txt" ) != rd( GOLD, "rc.txt" ): no( "(F) an exit code moved" )
    elif "test-gate.xml 4" not in rd( NEW, "rc.txt" ): no( "(F) --test-gate no longer exits 4 on a non-empty obligation" )
    if not bad: ok( "(F) %d answers: tests=/shown_tests=/run_first=/n= and every file's path and command equal the golden's, in order; exit codes equal (--test-gate 4)" % n )

def arm_G():
    name = "big.affected.xml"; new, gold = rd( NEW, name ), rd( GOLD, name )
    if lossless_xml( name, new, gold ): no( "(G) the unmutated answer is not green, so no mutation below proves anything" ); return
    legend, body = split_legend( new )   # every mutation is made in the ROWS: the legend spells the form too
    def must_red( label, doc ):
        doc = doc if doc.startswith( "<!--" ) else legend + doc
        if doc == new: no( "(G) %s: the mutation did not change the document" % label ); return
        why = lossless_xml( name, doc, gold )
        if why: ok( "(G) %s -> red (%s)" % ( label, why[:90] ) )
        else: no( "(G) %s was NOT caught" % label )
    must_red( "an alternative dropped from a brace group", body.replace( "test_a02,", "", 1 ) )
    must_red( "the same, with n= repaired", body.replace( "test_a02,", "", 1 ).replace( ' n="18"', ' n="17"', 1 ) )
    must_red( "two alternatives swapped", body.replace( "test_a01,test_a02", "test_a02,test_a01", 1 ) )
    must_red( "a directory renamed", body.replace( "alpha/{", "alpha2/{", 1 ) )
    must_red( "a suffix dropped", body.replace( "}.py", "}", 1 ) )
    must_red( "a closing brace removed", body.replace( "}", "", 1 ) )
    must_red( "the legend's pf= definition removed", gold[ :len( split_legend( gold )[0] ) ] + body )
    must_red( "the golden fed in as new output", gold )
    must_red( "pf= renamed p= without unfolding", body.replace( ' pf="', ' p="' ) )
    t, tg = rd( NEW, "big.situ.txt" ), rd( GOLD, "big.situ.txt" )
    if lossless_text( t, tg ): no( "(G) the unmutated --situ answer is not green" ); return
    for label, doc in ( ( "--situ: an alternative dropped", t.replace( "test_a02,", "", 1 ) ), ( "--situ: the golden fed in as new", tg ),
                        ( "--situ: the folded marker removed", t.replace( " folded): ", "): " ) ) ):
        why = lossless_text( doc, tg ) if doc != t else None
        if why: ok( "(G) %s -> red (%s)" % ( label, why[:90] ) )
        else: no( "(G) %s was NOT caught" % label )

def arm_H():
    n = items = 0
    for fx in FOLD:
        nb = split_legend( rd( NEW, fx + ".affected.xml" ) )[1]; gb = split_legend( rd( GOLD, fx + ".affected.xml" ) )[1]
        want = [ testrowpaths.xml_unescape( t ).split( "," ) for _a, t, _r in g_rows( gb ) ]
        for ( attr, text, _row ), paths in zip( g_rows( nb ), want ):
            if attr != "pf": continue
            got = []
            for item in pathfold.split_top( testrowpaths.xml_unescape( text ) ):
                # quote everything bash would read as syntax, leaving the braces and their commas bare
                q = re.sub( r"([^A-Za-z0-9_./{},-])", r"\\\1", item )
                out = subprocess.run( [ "bash", "-c", "printf '%s\\n' " + q ], capture_output = True, text = True )
                got += out.stdout.split( "\n" )[:-1]; items += 1
            if got != paths: no( "(H) %s: bash expands a pf= row to something else: %r" % ( fx, got[:4] ) )
            n += 1
    if n >= 4 and not bad: ok( "(H) %d pf= rows, %d items: bash's own brace expansion gives the golden paths, in order" % ( n, items ) )
    elif not bad: no( "(H) only %d pf= rows reached bash" % n )

def arm_L():
    n = 0
    for name in sorted( os.listdir( NEW ) ):
        if not name.endswith( ".xml" ): continue
        legend, body = split_legend( rd( NEW, name ) )
        has, defined = ' pf="' in body, "pf=" in legend
        if has != defined: no( "(L) %s: pf= %s but its legend %s it" % ( name, "rides a row" if has else "rides no row", "defines" if defined else "does not define" ) )
        n += 1
    for fx in FOLD + [ "small" ]:
        t = rd( NEW, fx + ".situ.txt" )
        if ( " folded): " in t ) != ( "(n folded)" in t.split( "[2] tests to run" )[1].split( "\n" )[0] if "[2] tests to run" in t else False ):
            no( "(L) %s.situ.txt: the heading defines the folded line exactly when one is printed — not here" % fx )
    if not bad: ok( "(L) %d XML answers and 4 --situ answers: the fold is defined exactly where a row carries it" % n )

{ "A": arm_A, "B": arm_B, "C": arm_C, "D": arm_D, "E": arm_E, "F": arm_F, "G": arm_G, "H": arm_H, "L": arm_L }[ sys.argv[1] ]()
sys.exit( bad )
PY
chk(){ python3 "$TMP/chk.py" "$1" "$ROOT" "$GOLD" "$TMP/new" || fail=1; }

echo "=== A: fixtures and goldens ==="
bash "$FIXSRC/build.sh" "$TMP/fx" || { no "(A) the fixture builder failed"; exit 1; }
if [ "$( find "$TMP/fx" -type f | wc -l | tr -d ' ' )" -ge 100 ]; then ok "(A) four fixtures written ($( find "$TMP/fx" -type f | wc -l | tr -d ' ' ) files)"; else no "(A) the fixtures are short of files"; fi
bash "$FIXSRC/capture.sh" "$BIN" "$TMP/fx" "$TMP/new"
chk A
echo "=== B: XML — unfold(new) == golden ==="
chk B
echo "=== C: --situ text — unfold(new) == golden ==="
chk C
echo "=== D: second reference — the binary's fold is pathfold.py's ==="
chk D
echo "=== E: what must not move ==="
chk E
echo "=== F: counts, commands, exit codes ==="
chk F
echo "=== G: mutation controls ==="
chk G
echo "=== H: bash brace expansion ==="
chk H
echo "=== L: legend ==="
chk L

echo "=== N: determinism and well-formedness ==="
bash "$FIXSRC/capture.sh" "$BIN" "$TMP/fx" "$TMP/new2"
if diff -r "$TMP/new" "$TMP/new2" > /dev/null; then ok "(N) two runs of every call are byte-identical"; else no "(N) two runs differ: $( diff -rq "$TMP/new" "$TMP/new2" | head -3 )"; fi
if command -v xmllint > /dev/null 2>&1; then
    bad=0; n=0
    for f in "$TMP"/new/*.xml; do [ -s "$f" ] || continue; n=$((n+1)); xmllint --noout "$f" 2> /dev/null || { bad=1; no "(N) not well-formed: $( basename "$f" )"; }; done
    [ "$bad" = 0 ] && ok "(N) $n XML answers pass xmllint"
else
    ok "(N) xmllint not installed — well-formedness not checked here (xmlwellformedcheck owns it)"
fi

# ── (S) at scale. RIPWIRE_FOLD_REF = a binary built before the fold; RIPWIRE_FOLD_CORPORA = "dir=files[;dir=files…]".
echo "=== S: at scale ==="
if [ -n "${RIPWIRE_FOLD_REF:-}" ] && [ -n "${RIPWIRE_FOLD_CORPORA:-}" ]; then
    n=0; fired=0
    IFS=';' read -r -a CELLS <<< "$RIPWIRE_FOLD_CORPORA"
    for cell in "${CELLS[@]}"; do
        dir="${cell%%=*}"; files="${cell#*=}"
        for v in affected test-gate; do
            "$RIPWIRE_FOLD_REF" "$dir" "--$v=$files" > "$TMP/s.ref" 2> /dev/null; rr=$?
            "$BIN" "$dir" "--$v=$files" > "$TMP/s.new" 2> /dev/null; rn=$?
            n=$((n+1))
            [ "$rr" = "$rn" ] || no "(S) $dir --$v=$files: exit $rn, reference $rr"
            if cmp -s "$TMP/s.ref" "$TMP/s.new"; then continue; fi
            fired=$((fired+1))
            python3 "$ROOT/test/lib/pathfold.py" unfold xml "$TMP/s.new" | sed 's/^<!--.*-->//' > "$TMP/s.un"
            sed 's/^<!--.*-->//' "$TMP/s.ref" > "$TMP/s.refbody"
            cmp -s "$TMP/s.un" "$TMP/s.refbody" || no "(S) $dir --$v=$files: unfold(new) != the reference binary's body"
        done
    done
    [ "$fail" = 0 ] && ok "(S) $n calls against the reference binary: $fired folded, each unfolds to the reference bytes; the rest byte-identical"
else
    ok "(S) not requested (RIPWIRE_FOLD_REF + RIPWIRE_FOLD_CORPORA)"
fi

if [ "$fail" = 0 ]; then echo "affectedfoldcheck: ALL PASS"; exit 0; fi
echo "affectedfoldcheck: FAILED"; exit 1
