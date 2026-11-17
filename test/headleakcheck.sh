#!/usr/bin/env bash
# headleakcheck.sh — a compact legend documents an attribute IF AND ONLY IF the answer carries it.
#
# WHAT THIS GUARDS. The compact layer decides which term rows a legend spells by asking whether the answer's HEAD
# (compactDocHead: the root's open tag through its first child's open tag) carries ` attr="`. That span keeps the
# comments between the two tags, and at the moment the question is asked those comments are the FULL-dialect legend
# prose — which defines attributes by spelling them: `scrubbed="1" = a ]]> was split`, `run_unknown="1" means none is
# derivable`. A substring test over the span therefore read the DEFINITION as the attribute, and every bundle-mode
# --expand documented scrubbed= and redacted= (166 B) with neither in the answer; --pack-task documented run_unknown=
# (61 B) beside a <tests> block of runnable rows. Worse than the bytes: --legend-have= rebuilds the legend from the
# COMPACTED answer, whose head comment no longer spells them, so the two disagreed and the handshake refused exactly
# those answers ("compact legend differs from its recomputed parts").
#
# WHY THE ARMS ARE SHAPED THIS WAY.
#   (N) non-vacuity reads the SAME captures the red arms read, and asserts the trap is ARMED on them: the full
#       dialect really spells the quoted form in a head comment, and the payload really lacks the attribute. If the
#       emitter's prose stops spelling it, (N) fails loudly instead of letting (R) pass for the wrong reason.
#   (R) the leak itself: absent attribute, no clause.
#   (P) the other direction: an attribute that IS in the answer keeps its clause. Without (P) the cheapest "fix" is
#       deleting the term rows, and this gate would call it green. Fewer clauses is not the bar; EXACT clauses is.
#   (C) lego/skipped/notes put their facts on the FIRST CHILD, inside the same head span. A fix that narrowed the span
#       to the root tag would silence their clauses — worse than the defect. (C) asserts each clause AND that the
#       attribute it reads sits on the child, not the root, so the arm cannot pass by reading the wrong tag.
#   (H) --legend-have= reaches the answers it used to refuse, and the bodies it serves are unchanged.
#   (S) the detectors themselves, fed doctored legends in both directions — a checker that cannot fail proves nothing.
#   (D) determinism: every capture twice, byte-identical.
#
# Usage:  bash test/headleakcheck.sh [BIN]      (or RIPWIRE_BIN=…)
set -u
BIN="${RIPWIRE_BIN:-${1:-./build/ripwire}}"
[ -x "$BIN" ] || { echo "headleakcheck: no binary at $BIN — build first (cmake --build build -j)"; exit 2; }
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

PYTHONDONTWRITEBYTECODE=1 python3 - "$BIN" "$WORK" <<'PY'
import os, re, subprocess, sys
BIN, WORK = sys.argv[1], sys.argv[2]
failed = 0
def ok( m ):
    print( "  PASS  " + m )
def no( m ):
    global failed
    failed += 1
    print( "  FAIL  " + m )
def check( cond, m, detail = "" ):
    ok( m ) if cond else no( m + ( " -- " + detail if detail else "" ) )

# ---- fixtures -------------------------------------------------------------------------------------------------------
# ABSENT: one small function in a file large enough that the bundle beats the whole file (so --expand serves
# mode="bundle"), nothing that needs scrubbing or redacting, and a test a runner IS derivable for (so pack-task has no runner-less row).
# PRESENT: the same tree plus a body that spells ]]> (scrubbed), a credential shape (redacted) and a test no runner is
# derivable for (run_unknown). The AWS id is the vendor's documented example value, as test/redactcheck.sh uses.
def writeTree( root, present ):
    os.makedirs( root )
    src = [ "class Shape:\n    def area( self ):\n        return 0\n\n",
            "class Square( Shape ):\n    def area( self ):\n        return target( 2 )\n\n",
            "def target( x ):\n    return x + 1\n\n" ]
    if present:
        src.append( "def marked( x ):\n    tail = ']]>'\n    key = 'AKIAIOSFODNN7EXAMPLE'\n    return target( x ), tail, key\n\n" )
    for i in range( 60 ):
        src.append( "def filler_%03d( x ):\n    y = x * %d\n    return target( y ) + %d\n\n" % ( i, i + 2, i ) )
    with open( os.path.join( root, "big.py" ), "w" ) as f:
        f.write( "".join( src ) )
    with open( os.path.join( root, "use.py" ), "w" ) as f:
        f.write( "from big import target\n\ndef top():\n    return target( 3 )\n" )
    # A test row either way, because pack-task's run=/run_unknown= prose is rows-gated. The ABSENT tree's test has a main
    # guard, the evidence a runner is derived from (run="python3 …"); the PRESENT tree's has none, so its row can only
    # say run_unknown="1".
    with open( os.path.join( root, "test_big.py" ), "w" ) as f:
        f.write( "from big import target\n\ndef test_target():\n    assert target( 1 ) == 2\n" )
        if not present:
            f.write( "\nif __name__ == \"__main__\":\n    test_target()\n" )
ABSENT, PRESENT = os.path.join( WORK, "absent" ), os.path.join( WORK, "present" )
writeTree( ABSENT, False )
writeTree( PRESENT, True )

ENV = dict( os.environ, PYTHONDONTWRITEBYTECODE = "1" )
def run( tree, *args ):
    p = subprocess.run( [ BIN, ".", *args ], cwd = tree, env = ENV, capture_output = True )
    return p.returncode, p.stdout.decode( "utf-8", "replace" ), p.stderr.decode( "utf-8", "replace" )

# ---- readers --------------------------------------------------------------------------------------------------------
def spans( doc ):
    """The answer as ( kind, text ) spans — 'tag', 'comment', 'cdata' or 'text' — walked the way compactlegend.h's
    payloadHasAnyAttr walks it. A regex cannot do this: the legend prose itself spells `]]>` and `<![CDATA[` inside a
    comment, and a body can spell `<!--`, so whichever region OPENS first owns everything up to its own close."""
    out, i = [], 0
    while i < len( doc ):
        if doc.startswith( "<![CDATA[", i ):
            j = doc.find( "]]>", i );  j = len( doc ) if j < 0 else j + 3
            out.append( ( "cdata", doc[ i:j ] ) )
        elif doc.startswith( "<!--", i ):
            j = doc.find( "-->", i );  j = len( doc ) if j < 0 else j + 3
            out.append( ( "comment", doc[ i:j ] ) )
        elif doc[ i ] == "<":
            j = doc.find( ">", i );  j = len( doc ) if j < 0 else j + 1
            out.append( ( "tag", doc[ i:j ] ) )
        else:
            j = doc.find( "<", i );  j = len( doc ) if j < 0 else j
            out.append( ( "text", doc[ i:j ] ) )
        i = j
    return out
def tags( doc ):
    return [ t for k, t in spans( doc ) if k == "tag" ]
def carries( doc, attr ):
    return any( ' %s="' % attr in t for t in tags( doc ) )
def legendOf( doc ):
    for k, t in spans( doc ):
        if k == "comment" and t.startswith( "<!-- ripwire " ):
            return t
    return ""
def documents( legend, clause ):
    return clause in legend
def headComments( doc ):
    """The comments between the root's open tag and its first child's — the region the old predicate searched."""
    out, seenRoot = [], False
    for k, t in spans( doc ):
        if k == "tag":
            if seenRoot:
                break
            seenRoot = True
        elif k == "comment" and seenRoot:
            out.append( t )
    return "".join( out )
def tagAt( doc, name ):
    for t in tags( doc ):
        if re.match( r"<" + re.escape( name ) + r"[\s/>]", t ):
            return t
    return ""
def rootTag( doc ):
    t = tags( doc )
    return t[ 0 ] if t else ""
def bodies( doc ):
    return [ t for k, t in spans( doc ) if k == "cdata" ]

# The leaked terms: (verb args, attribute, the clause opener the dictionary row spells for it).
LEAKS = [ ( ( "--expand=target", ),             "scrubbed",    "scrubbed=1:" ),
          ( ( "--expand=target", ),             "redacted",    "redacted=1:" ),
          ( ( "--pack-task=target adds one", ), "run_unknown", "run_unknown=1:" ) ]

captures = {}
def capture( tree, args ):
    k = ( tree, args )
    if k not in captures:
        captures[ k ] = ( run( tree, *args ), run( tree, *args ), run( tree, *args, "--legend=full" ) )
    return captures[ k ]

# ---- (N) non-vacuity, (R) the leak, (D) determinism — all three over ONE capture per term ----------------------------------
for args, attr, clause in LEAKS:
    ( rc, doc, err ), ( rc2, doc2, _ ), ( rcF, full, _ ) = capture( ABSENT, args )
    tag = "%s %s=" % ( args[ 0 ].split( "=" )[ 0 ], attr )
    check( rc == 0 and rcF == 0 and doc.startswith( "<ctx " ), "(N1) %s: the fixture answers (rc=%d, %d B)" % ( tag, rc, len( doc ) ), err[ :200 ] )
    if args[ 0 ].startswith( "--expand" ):
        check( ' mode="bundle"' in rootTag( doc ) and "<bodies " in doc, "(N2) %s: the answer is the BUNDLE shape (mode=\"bundle\", a <bodies> child)" % tag, rootTag( doc ) )
    check( ' %s="' % attr in headComments( full ),
           "(N3) %s: the trap is ARMED — the full dialect spells ` %s=\"` in a comment between the root and its first child" % ( tag, attr ),
           "the prose no longer spells the quoted form, so (R) below cannot fail on this term; point it at a term that still does" )
    check( not carries( doc, attr ) and not carries( full, attr ), "(N4) %s: no tag of the answer carries the attribute" % tag )
    check( not documents( legendOf( doc ), clause ), "(R)  %s: ABSENT from the answer, so the compact legend must not spell `%s`" % ( tag, clause ),
           "the legend documents an attribute the answer does not carry" )
    check( doc == doc2 and rc == rc2, "(D)  %s: two runs byte-identical" % tag )

# ---- (P) the other direction: PRESENT keeps its clause ---------------------------------------------------------------
for args, attr, clause in LEAKS:
    pargs = ( "--expand=marked", ) if args[ 0 ].startswith( "--expand" ) else args
    ( rc, doc, err ), ( rc2, doc2, _ ), _ = capture( PRESENT, pargs )
    tag = "%s %s=" % ( pargs[ 0 ].split( "=" )[ 0 ], attr )
    check( rc == 0 and carries( doc, attr ), "(P0) %s: the PRESENT fixture really carries the attribute on a tag" % tag, err[ :200 ] )
    check( documents( legendOf( doc ), clause ), "(P)  %s: PRESENT in the answer, so the compact legend must spell `%s`" % ( tag, clause ) )
    check( doc == doc2, "(D)  %s (present): two runs byte-identical" % tag )

# ---- (C) lego / skipped / notes: facts on the FIRST CHILD must still reach the legend --------------------------------
CONTROLS = [ ( ( "--lego=Shape", ), "lego",    [ ( "counts_floor", "counts_floor=1:" ), ( "graph_ambiguous", "graph_ambiguous=/graph_unresolved=:" ) ] ),
             ( ( "--skipped", ),    "skipped", [ ( "indexed", "indexed=N:" ), ( "oversize", "oversize=N:" ), ( "unsupported_ext", "unsupported_ext=N:" ) ] ) ]
for args, child, terms in CONTROLS:
    ( rc, doc, err ), ( rc2, doc2, _ ), _ = capture( PRESENT, args )
    for attr, clause in terms:
        onChild = ' %s="' % attr in tagAt( doc, child )
        onRoot  = ' %s="' % attr in rootTag( doc )
        check( rc == 0 and onChild and not onRoot, "(C0) %s: %s= sits on the first child <%s>, not on the root" % ( args[ 0 ], attr, child ), err[ :200 ] )
        check( documents( legendOf( doc ), clause ), "(C)  %s: the legend still spells `%s`" % ( args[ 0 ], clause ),
               "a first-child fact lost its clause — the head span was narrowed, or the tag walk skips the child" )
    check( doc == doc2, "(D)  %s: two runs byte-identical" % args[ 0 ] )
( rc, doc, err ), ( rc2, doc2, _ ), _ = capture( PRESENT, ( "--notes", ) )
check( rc == 0 and "<!-- ripwire notes schema=ripwire.notes/v1: field notes by target:" in doc, "(C)  --notes: the legend's purpose line is still spelled", doc[ :200 ] + err[ :200 ] )
check( re.search( r"<!-- notes=\d+ targets=\d+ dangling=\d+ -->", headComments( doc ) ) is not None,
       "(C)  --notes: the kept count comment still rides between the root and <notes>", headComments( doc )[ -200: ] )
check( doc == doc2, "(D)  --notes: two runs byte-identical" )

# ---- (H) --legend-have= reaches the answers it refused ---------------------------------------------------------------
rc, dictOut, _ = run( ABSENT, "--legend-dict" )
m = re.search( r"dictv=([0-9a-f]{8,})", dictOut.split( "\n", 1 )[ 0 ] )
DV = m.group( 1 ) if m else ""
check( DV != "", "(H0) --legend-dict names a dictionary version (%s)" % DV )
for args in ( ( "--expand=target", ), ( "--pack-task=target adds one", ) ):
    ( _, inline, _ ), _, _ = capture( ABSENT, args )
    rc, ref, err = run( ABSENT, *args, "--legend-have=" + DV )
    rc2, ref2, _ = run( ABSENT, *args, "--legend-have=" + DV )
    verb = args[ 0 ].split( "=" )[ 0 ]
    check( rc == 0 and not carries( inline, "run_unknown" ) and "differs from its recomputed parts" not in err, "(H1) %s --legend-have=: the legend recomputes to what was written — no refusal" % verb, err[ :300 ] )
    check( any( ' legend="ref"' in t for t in tags( ref ) ) and len( ref ) < len( inline ),
           "(H2) %s --legend-have=: the ref posture APPLIES (%d B inline -> %d B)" % ( verb, len( inline ), len( ref ) ), "legend=\"ref\" absent or no smaller" )
    check( bodies( ref ) == bodies( inline ) and len( bodies( inline ) ) > 0, "(H3) %s --legend-have=: every CDATA body is byte-identical to the inline answer's (%d of them)" % ( verb, len( bodies( inline ) ) ) )
    check( ref == ref2, "(D)  %s --legend-have=: two runs byte-identical" % verb )

# ---- (S) the detectors can fail, in BOTH directions ------------------------------------------------------------------
( _, absentDoc, _ ), _, _ = capture( ABSENT, ( "--expand=target", ) )
( _, presentDoc, _ ), _, _ = capture( PRESENT, ( "--expand=marked", ) )
leaked = absentDoc.replace( " -->", " scrubbed=1: this CDATA is not the bytes. -->", 1 )
check( documents( legendOf( leaked ), "scrubbed=1:" ) and not carries( leaked, "scrubbed" ), "(S1) a legend doctored to spell an ABSENT term is seen as a leak — (R) can go red" )
dropped = presentDoc.replace( "scrubbed=1:", "", 1 )
check( carries( dropped, "scrubbed" ) and not documents( legendOf( dropped ), "scrubbed=1:" ), "(S2) a legend doctored to DROP a present term is seen as a loss — (P) can go red" )
quoted = '<ctx a="1"><!-- prose scrubbed="1" --><b><![CDATA[ <x scrubbed="1"> ]]></b></ctx>'
check( not carries( quoted, "scrubbed" ) and ' scrubbed="' in headComments( quoted ), "(S3) the reader ignores an attribute spelled only in a comment or a CDATA body, and (N3)'s reader finds it there" )

print( "headleakcheck: FAILED=%d" % failed )
sys.exit( 1 if failed else 0 )
PY
rc=$?
[ "$rc" -eq 0 ] && { echo "headleakcheck: ALL PASS"; exit 0; }
echo "headleakcheck: FAIL"; exit 1
