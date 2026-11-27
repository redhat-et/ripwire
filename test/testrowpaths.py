#!/usr/bin/env python3
"""testrowpaths.py — THE tests_to_run row reader every gate shares.

WHY THIS FILE EXISTS. Seven gates read the PATHS out of the tests_to_run row family — affectedcheck,
impactpartitioncheck, receiptpostcheck, rootrelemitcheck, selectorchaincheck, testgatecheck, testrowruncheck
— and each one had grown its own reader: `grep -oE '<t p="[^"]*"'`, `sed -n 's/.*<test p="\\([^"]*\\)".*/\\1/p'`,
`grep -oE '"tests_to_run":\\[[^]]*\\]'`, `awk '{print $1}'`. Every one of them was written when a row was
one path, and E1 (2026-09-12) made a row possibly be SEVERAL — `<g n="3" p="a,b,c"/>` in XML, a `"p"`
ARRAY in JSON, `[hops=2] (3): a, b, c` in the text dialect. The private readers did not fail; they went
QUIET or, worse, wrong:

  * `grep -oE '"tests_to_run":\\[[^]]*\\]'` stops at the first `]`, which is now the end of the FIRST
    group's path array — three gate arms asserted over two and a half rows and passed vacuously;
  * `sed -n 's/^test p=//'` and friends saw the singles and silently skipped every group row;
  * the text reader took `$1` of the line, which on a group line is `[hops=1]`, not a path.

The invariant all six actually want is THE FILES NAMED, in emitted order. That is one question, so it is
answered in one place, for every dialect, and a gate that adds a new assertion gets the group shapes for
free instead of re-deriving them. Three further gates read these rows and are NOT converted, because none
asks for the paths: test/listingpagingcheck.sh sums `n=` over the <g> rows to prove the family never pages,
test/w3fixlegendcheck.sh counts path occurrences on a --situ line, and test/testgatepagecheck.sh adds the
singles to the groups' `n=` to check shown_tests=. All three were made group-aware in place (E1) and stay
that way — routing a COUNT through a path reader would only add a dialect hop.

THE CLAIM ABOVE WAS ONCE HALF TRUE, WHICH IS WHY THE CENSUS IS RECORDED HERE. The review of #214 found TWO
path readers still private: affectedcheck's own tset() (in the file this docstring already named — it split
EVERY row's p= on ',', including a single row's, so a comma-bearing path became two names that name nothing)
and testgatecheck's tset() (matched `<t p=` singles only and returned the EMPTY set on a two-runner-less-test
fixture where this reader returns both paths). Both are converted. The rest of test/ was swept for the same
four shapes — a `tr ',' '\\n'` over a p=, a `grep -oE '<test p='`, a `'"tests_to_run":\\[[^]]*\\]'`, an `awk
'{print $1}'` on a --situ line — and every other hit either COUNTS rows (the three above) or pins one exact
row's spelling with a regex that fails loudly rather than going quiet (flipcheck's <t> pin, handoffcheck's
run= check). deeptailcheck's `<t p=` rows are --for's TAIL listing, a different element that shares the tag.

    python3 test/testrowpaths.py paths xml|json|text  [FILE]   # one path per line, emitted order
    python3 test/testrowpaths.py jsonlist             [FILE]   # the balanced "tests_to_run":[...] slice
    python3 test/testrowpaths.py commands xml|json|text [FILE] # path<TAB>command per FILE, emitted order

FILE defaults to stdin. Exit 0 even when nothing matches: "no rows" is an answer a gate may be asserting,
and an empty stdout says it. Exit 2 only on a malformed document the reader cannot parse at all.

DIALECTS, and what counts as a row in each — the shapes testmap.h's seam emits, and nothing else:
  xml   <t p="…"/> and <test p="…"/> singles, <g … p="a,b,c" …/> groups. Comments are stripped FIRST, so
        the legend's own `<g n= p=a,b,c>` definition is never read as a row.
  json  every object inside the balanced "tests_to_run":[…] list whose "p" (or "test") key is a string or
        an array of strings. The list is sliced by bracket depth, not by the first `]`.
  text  --situ's `        path [hops=N]   (run: …)` singles and its
        `        [hops=N] (n): a, b, c   (run: not derivable)` group lines.

COMMANDS (affected-group-unjam, 2026-11-17). A row with a derivable runner used to be a single row always,
because run= embeds the row's own path and so no two rows were ever equal. Rows whose command is EXACTLY
"<head> <their own path>" now ride a group too, the head said once as a template:
  xml   <g … n="3" p="a,b,c" run_each="pytest {p}"/>
  json  {"p":["a","b","c"],…,"n":3,"run_each":"pytest {p}"}
  text  [hops=2] (3): a, b, c   (run each: pytest {p})
A member's command is the template with its ONE trailing {p} replaced by that member's path — expand_run_each
below, the only place a gate may do it. `commands` (and the *_rows functions) return every file's command
already expanded, None where the row says run_unknown, so a gate asserting "the command for X is Y" reads
singles and groups alike. A tests_to_run <g> is therefore qualified by run_unknown="1" OR run_each=.

A path is emitted VERBATIM, exactly as the document spelled it, except that XML entity references are
decoded (`&amp;` `&lt;` `&gt;` `&quot;` `&#NN;`) — a gate compares paths against the file names it created,
which are unescaped. Note that a path containing ',' is never grouped (testmap.h refuses to), so splitting
a group's p= on ',' cannot split a path in half.

THE FOLDED LIST (PATH-FOLD, 2026-11-18). On --affected, --test-gate and --situ a group row may carry its paths folded:
  xml   <g … n="3" pf="dir/{a,b}.py,c.py" …/>          text  [hops=2] (3 folded): dir/{a,b}.py, c.py   (run: …)
PRE{A,B}SUF stands for PREASUF,PREBSUF (braces nest); a row that says p= / "(n):" is verbatim as before. The readers
below expand a folded row through test/lib/pathfold.py — the one place a gate may do it — so every gate that asks for
the files named gets the same full paths, in the same order, whichever form the row took. A malformed folded list is
a raise (exit 2), never a best-effort split.
"""

import json
import os
import re
import sys

sys.path.insert( 0, os.path.join( os.path.dirname( os.path.abspath( __file__ ) ), "lib" ) )
import pathfold   # noqa: E402 — the folded-list reference (expand, expand_text_list)

_ENT = { "amp": "&", "lt": "<", "gt": ">", "quot": '"', "apos": "'" }


def xml_unescape( s ):
    def one( m ):
        body = m.group( 1 )
        if body.startswith( "#" ):
            try:
                return chr( int( body[2:], 16 ) if body[1:2].lower() == "x" else int( body[1:], 10 ) )
            except ValueError:
                return m.group( 0 )
        return _ENT.get( body, m.group( 0 ) )
    return re.sub( r"&([#0-9A-Za-z]+);", one, s )


def strip_comments( doc ):
    """Drop every <!-- … --> run. The legends define the row shapes they describe, so a reader that keeps
    comments reads the DEFINITION of <g n= p=a,b,c> as a row with the paths 'a', 'b' and 'c'."""
    return re.sub( r"<!--.*?-->", "", doc, flags = re.S )


RUN_EACH_SLOT = "{p}"


def expand_run_each( template, path ):
    """A group member's command: the template's ONE slot, which is its tail, replaced by the member's path.

    Anything else is not a template this family emits (testmap.h groupRunHead builds "<head> {p}" and refuses a
    head or a path that holds the slot itself), so it is a raise, never a best-effort substitution: a reader
    that expanded a malformed template would hand a gate a command the document does not carry."""
    if template.count( RUN_EACH_SLOT ) != 1 or not template.endswith( " " + RUN_EACH_SLOT ) or RUN_EACH_SLOT in path:
        raise TestRowParseError( "run_each template %r is not '<head> {p}' with exactly one slot (member %r)" % ( template, path ) )
    return template[ :-len( RUN_EACH_SLOT ) ] + path


def _attrs( row ):
    return dict( re.findall( r'\s([A-Za-z_]+)="([^"]*)"', row ) )


def _unfolded_pf( row, raw ):
    """A <g> row's pf= list as the comma-joined p= list it stands for (PATH-FOLD). XML escapes never produce ',', '{'
    or '}', so the escaped list expands as it stands."""
    if not row.startswith( "<g " ):
        raise TestRowParseError( "pf= on a row that is not a <g> group: %r" % row[:120] )
    try:
        return ",".join( pathfold.expand( raw ) )
    except ValueError as e:
        raise TestRowParseError( "malformed pf= list: %s" % e )


def _text_group_members( listed, folded ):
    """The paths a text group line names: split on ',' as before, or — "(n folded):" — expanded (PATH-FOLD)."""
    if not folded:
        return listed.split( "," )
    try:
        return pathfold.expand_text_list( listed )
    except ValueError as e:
        raise TestRowParseError( "malformed '(n folded):' list: %s" % e )


def xml_rows( doc ):
    """Every test FILE an XML document names, in emitted order, as ( path, command, grouped ): command is the
    row's run= (a group member's is expanded from run_each=), None where the row says run_unknown="1", and
    the string "<neither>" where a row carries no disclosure at all — testrowruncheck's subject, kept visible
    here rather than read as a runner-less row.

    `<g` is NOT a tests_to_run element on its own: --flags spells a gate row `<g n="NAME" … p="src/x.h"/>`
    with the same opener. A tests_to_run group is qualified by run_unknown="1" or run_each=, one of which every
    group row carries by construction (a group exists only where no runner is derivable or where every member's
    command is the one template) — the same qualification the compact legend uses to keep the readings apart."""
    # `<t` IS NOT A tests_to_run ROW OUTSIDE <tests> (PB1, 2026-11-19). --for's file-grain tail — which
    # --pack-task now carries too — spells its rows `<t p= sym= r=/>`, the same opener this reader took as a
    # test file: on a pack-task bundle it returned src/mid.cpp and src/leaf.cpp as "test files this fixture
    # does not have" (testrowruncheck arm 12). The short tag is the ambiguous one, so it is read only inside
    # the <tests> element that declares what it means; `<test` and a qualified `<g` stay document-wide,
    # because no other section spells either.
    body = strip_comments( doc )
    # The exclusion is scoped to the <tail> ELEMENT, not to an inclusion inside <tests>. Admitting only the
    # <t> rows inside <tests> looked equivalent and was not: --test-gate spells tests_to_run rows that are not
    # wrapped in a <tests> element at all, so the inclusive form silently dropped them and turned
    # selectorchaincheck (d2) red. Excluding exactly the rows inside the one element that spells the other
    # meaning cannot drop a row from a document that has no tail.
    tl, tle = body.find( "<tail" ), body.find( "</tail>" )
    tail    = ( tl, tle + len( "</tail>" ) ) if tl != -1 and tle > tl else ( -1, -1 )
    out = []
    for m in re.finditer( r'<(?:t|test|g)\b[^>]*?\b(pf?)="([^"]*)"[^>]*/>', body ):
        if m.group( 0 ).startswith( "<t " ) and tail[0] <= m.start() < tail[1]:
            continue          # a file-tail row, not a tests_to_run row — see the note above
        row = m.group( 0 )
        raw = m.group( 2 )
        at  = _attrs( row )
        if m.group( 1 ) == "pf":
            raw = _unfolded_pf( row, raw )
        if row.startswith( "<g " ):
            if at.get( "run_unknown" ) != "1" and "run_each" not in at:
                continue                                        # --flags' own <g> gate row, not a test group
            # a group's p= is a comma-separated list; a path containing ',' is never grouped (testmap.h
            # refuses to), so splitting on ',' cannot split a path in half.
            for p in raw.split( "," ):
                if p == "":
                    continue
                path = xml_unescape( p )
                out.append( ( path, expand_run_each( xml_unescape( at[ "run_each" ] ), path ) if "run_each" in at else None, True ) )
        else:
            cmd = xml_unescape( at[ "run" ] ) if "run" in at else ( None if at.get( "run_unknown" ) == "1" else "<neither>" )
            out.append( ( xml_unescape( raw ), cmd, False ) )
    return out


def xml_paths( doc ):
    """The test FILES an XML document names, in emitted order (xml_rows, the paths alone)."""
    return [ r[0] for r in xml_rows( doc ) ]


class TestRowParseError( Exception ):
    """A document that NAMES a tests_to_run list this reader cannot read to its end.

    CodeRabbit on #214: this was not distinguished from the field being absent. Both returned None, json_paths
    turned None into [], and the caller got an empty answer and exit 0 — so a TRUNCATED document (a gate that
    captured a killed run, a byte cap that cut mid-array) asserted over zero rows and passed vacuously. That is
    the very failure this file was written to end. The two cases are not the same claim: no `tests_to_run` field
    is an ANSWER ("this document serves no such list", None -> []), while a field whose array never closes is a
    document this reader cannot read at all, and the only honest thing to return is an error. Exit 2, as the
    module header promises for exactly this."""


def json_list_slice( doc ):
    """The "tests_to_run":[…] value, sliced by BRACKET DEPTH (a group row's "p" is itself an array, so the
    first ']' is not the end of the list) and string-aware (a ']' inside a path is not a bracket).

    Returns None when the document has no "tests_to_run" field at all. Raises TestRowParseError when it has
    one that this reader cannot slice — see that class for why the two are not the same answer.

    The value is read ADJACENTLY. `doc.find( "[", i )` was an unbounded forward scan, so a document spelling
    `"tests_to_run":null` was not read as "not a list": the scan walked past the value and sliced the NEXT
    '[' anywhere in the document. `{"tests_to_run":null,"other":[{"p":"ghost.cpp"}]}` returned ghost.cpp at
    exit 0 — a foreign field's paths served as this field's answer, which is the hole of arm 16's own species
    one step worse, because the caller is handed rows instead of silence. Past the key, a ':', optional
    whitespace, and the very next character must be '['; anything else is the raise the docstring promised."""
    i = doc.find( '"tests_to_run"' )
    if i < 0:
        return None
    j = i + len( '"tests_to_run"' )
    while j < len( doc ) and doc[j].isspace():                  # JSON allows whitespace on both sides of ':'
        j += 1
    if j >= len( doc ) or doc[j] != ":":
        raise TestRowParseError( '"tests_to_run" is present but is followed by no ":" — not a field at all' )
    j += 1
    while j < len( doc ) and doc[j].isspace():
        j += 1
    if j >= len( doc ) or doc[j] != "[":
        got = doc[ j:j + 12 ] if j < len( doc ) else "end of document"
        raise TestRowParseError( '"tests_to_run" is present but its value does not open with "[" — not a list '
                                 'at all (value begins %r)' % got )
    i = j
    depth = 0
    instr = False
    esc = False
    for k in range( i, len( doc ) ):
        c = doc[k]
        if instr:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                instr = False
            continue
        if c == '"':
            instr = True
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                return doc[i:k + 1]
    raise TestRowParseError( '"tests_to_run" list is never closed: %d bracket(s) still open at end of document '
                             '(%d bytes read from the field)' % ( depth, len( doc ) - i ) )


def json_rows( doc ):
    """json twin of xml_rows: ( path, command, grouped ) per file — "run", "run_each" (expanded) or run_unknown."""
    sl = json_list_slice( doc )
    if sl is None:
        return []
    out = []
    for r in json.loads( sl ):
        if not isinstance( r, dict ):
            continue
        p = r.get( "p", r.get( "test" ) )
        if isinstance( p, list ):
            for x in p:
                out.append( ( str( x ), expand_run_each( r[ "run_each" ], str( x ) ) if "run_each" in r else None, True ) )
        elif isinstance( p, str ):
            out.append( ( p, r[ "run" ] if "run" in r else ( None if r.get( "run_unknown" ) is True else "<neither>" ), False ) )
    return out


def json_paths( doc ):
    return [ r[0] for r in json_rows( doc ) ]


# The text dialect's row grammar, spelled from the RENDERER rather than guessed at (testmap.h: the Text arm
# of testRowEvidence, and runSuffixTextDisclosed). A row is
#
#     <indent><path>[ [changed]][ [partner]][ [hops=N]]   (run: <cmd>|not derivable)
#
# and a GROUP row replaces <path> with "<attrs> (n): a, b, c", its attrs leading, and closes with
# "(run: not derivable)" or — where every member's command is one template — "(run each: <head> {p})". The three evidence
# attributes are optional, but they are emitted in THAT ORDER and no other, and the run suffix always opens
# with exactly three spaces. So the whole tail of a row is a closed, known shape.
#
# CodeRabbit on #214: the single-row reader took `(\S+)`, which stops at the first space — a test path
# holding a space was reported TRUNCATED, silently, as a path that does not exist. A generic bracket matcher
# would have the mirror-image bug (a path holding "[...]" would lose it), which is why this is pinned to the
# renderer's own sequence instead: everything before the known attribute tail is the path, spaces included.
# The one ambiguity left is the dialect's, not the reader's — text carries NO escaping, so a path containing
# the literal three-space "(run: " opener cannot be told from the suffix. XML and JSON are exact; a gate that
# needs a path that adversarial should assert in one of those.
_TEXT_RUN_OPEN  = "   (run: "
_TEXT_EACH_OPEN = "   (run each: "
_TEXT_ATTR_TAIL = re.compile( r"(?: \[changed\])?(?: \[partner\])?(?: \[hops=\d+\])?$" )
_TEXT_GROUP = re.compile( r"^\s*(?:\[[^\]]*\]\s*)*\((\d+)( folded)?\):\s*(.*?)\s{2,}\(run(?: each)?: " )
_TEXT_NOT_DERIVABLE = "not derivable"


def text_rows( doc ):
    """text twin of xml_rows: ( path, command, grouped ) per file."""
    out = []
    for line in doc.split( "\n" ):
        line = line.rstrip( "\r" )
        each = _TEXT_EACH_OPEN in line
        if not ( each or _TEXT_RUN_OPEN in line ) or not line.endswith( ")" ):
            continue
        opener = _TEXT_EACH_OPEN if each else _TEXT_RUN_OPEN
        tail   = line[ line.rindex( opener ) + len( opener ):-1 ]
        g = _TEXT_GROUP.match( line )
        if g:
            for p in _text_group_members( g.group( 3 ), g.group( 2 ) ):
                p = p.strip()
                if p:
                    out.append( ( p, expand_run_each( tail, p ) if each else None, True ) )
            continue
        if each:
            raise TestRowParseError( "a '(run each: …)' suffix on a line that is not a group row: %r" % line )
        # a SINGLE row: cut the run suffix, then the known attribute tail; what is left of the indent is the
        # path, verbatim — spaces and all.
        head = line[ :line.index( _TEXT_RUN_OPEN ) ]
        head = _TEXT_ATTR_TAIL.sub( "", head )
        path = head.strip()
        if path:
            cmd = line[ line.index( _TEXT_RUN_OPEN ) + len( _TEXT_RUN_OPEN ):-1 ]
            out.append( ( path, None if cmd == _TEXT_NOT_DERIVABLE else cmd, False ) )
    return out


def text_paths( doc ):
    return [ r[0] for r in text_rows( doc ) ]


def main( argv ):
    if len( argv ) < 2:
        sys.stderr.write( __doc__ )
        return 2
    mode = argv[1]
    if mode == "jsonlist":
        src = argv[2] if len( argv ) > 2 else None
        doc = open( src ).read() if src else sys.stdin.read()
        try:                                                    # an unbalanced list is exit 2 here too, not ""
            sl = json_list_slice( doc )
        except TestRowParseError as e:
            sys.stderr.write( "testrowpaths: json dialect unreadable: %s\n" % e )
            return 2
        sys.stdout.write( sl if sl else "" )
        return 0
    if mode not in ( "paths", "commands" ) or len( argv ) < 3:
        sys.stderr.write( __doc__ )
        return 2
    dialect = argv[2]
    src = argv[3] if len( argv ) > 3 else None
    doc = open( src ).read() if src else sys.stdin.read()
    # `paths` goes through the *_paths functions the gates import, `commands` through the *_rows ones beneath them
    readers = ( { "xml": xml_rows, "json": json_rows, "text": text_rows } if mode == "commands"
                else { "xml": xml_paths, "json": json_paths, "text": text_paths } )
    if dialect not in readers:
        sys.stderr.write( "testrowpaths: unknown dialect %r (xml|json|text)\n" % dialect )
        return 2
    try:
        rows = readers[ dialect ]( doc )
    except Exception as e:                                      # a document this reader cannot parse at all
        sys.stderr.write( "testrowpaths: %s dialect unreadable: %s\n" % ( dialect, e ) )
        return 2
    for row in rows:
        # `commands`: path<TAB>command; a runner-less file prints an EMPTY command field — the TAB is always
        # there, so a path with no command is never mistaken for a `paths` line
        sys.stdout.write( ( row if mode == "paths" else row[0] + "\t" + ( row[1] or "" ) ) + "\n" )
    return 0


if __name__ == "__main__":
    sys.exit( main( sys.argv ) )
