#!/usr/bin/env python3
"""invnest_reader.py — the arms of test/invnestcheck.sh that need a parser.

Kept beside the gate rather than inlined in it because the flattening and the three planted mutations are
the substance of Band A, and a quoted heredoc makes them unreadable and unrunnable on their own.

Reads the default map's XML and the --json twin of the SAME binary and index, flattens the nested <ls> rows
back to absolute paths, and compares the result against the JSON "ls" array, which stays flat on purpose.
"""
import json
import re
import sys

NEST_DEPTH = 2          # Band E: pinned here AND read from the header below; the two must agree


def rows_from_xml( xml ):
    """Flatten <inv>'s rows. Returns ( rows, maxDepth, groups ).

    rows   : [ ( path, n, ( f names ) ) ] in DOCUMENT order, with each <ls p=> re-joined to its ancestors'
             <d p=> segments, so a row reads as the absolute directory it did before the encoding.
    groups : [ ( segment, depth, childRowCount ) ] — what (C1) prices.

    Hand-rolled rather than fed to an XML parser so the arm sees exactly the bytes the agent is charged for,
    including the self-closing shape; the well-formedness of the document is another gate's subject.
    """
    inv = re.search( r'<inv\b[^>]*>(.*?)</inv>', xml, re.S )
    if inv is None:
        return [], 0, []
    body = inv.group( 1 )
    rows, groups, stack = [], [], []
    maxDepth = 0
    for tok in re.finditer( r'<d\s+p="([^"]*)"\s*>|</d>|<ls\b([^>]*)/>', body ):
        if tok.group( 0 ).startswith( '<d' ):
            stack.append( [ tok.group( 1 ), 0 ] )
            maxDepth = max( maxDepth, len( stack ) )
        elif tok.group( 0 ) == '</d>':
            seg, kids = stack.pop()
            groups.append( ( seg, len( stack ) + 1, kids ) )
        else:
            attrs = tok.group( 2 )
            p = re.search( r'\bp="([^"]*)"', attrs )
            n = re.search( r'\bn="(\d+)"', attrs )
            f = re.search( r'\bf="([^"]*)"', attrs )
            own = p.group( 1 ) if p else ''
            full = '/'.join( [ s[ 0 ] for s in stack ] + ( [ own ] if own else [] ) )
            rows.append( ( full, n.group( 1 ) if n else None, tuple( f.group( 1 ).split( ',' ) ) if f else () ) )
            for s in stack:
                s[ 1 ] += 1
    return rows, maxDepth, groups


def rows_from_json( txt ):
    """The same rows out of the flat JSON twin: the oracle. Absent "ls" is distinguished from an empty one."""
    doc = json.loads( txt )
    inv = doc.get( 'inv' )
    if inv is None:
        return None
    out = []
    for d in inv.get( 'ls', [] ):
        out.append( ( d[ 'p' ], str( d[ 'n' ] ), tuple( d.get( 'f', [] ) ) ) )
    return out


def diff( a, b ):
    """A readable difference between two row lists, compared as MULTISETS (order is (D1)'s subject, not (A1)'s)."""
    from collections import Counter
    ca, cb = Counter( a ), Counter( b )
    only_a = sorted( ( ca - cb ).elements() )
    only_b = sorted( ( cb - ca ).elements() )
    return only_a, only_b


def arms( rows, maxDepth, groups, oracle, xml, root, ok, no ):
    """Every arm that needs the parsed document. Split out of main() so neither is past the project's own
    complexity and LOC bars — a gate held to a lower standard than the code it guards is the wrong way round."""
    # ── (A0) the subject is not vacuous ──────────────────────────────────────────────────────────────
    if oracle is None:
        no( '(A0) the --json map has no "inv" object at all, so the tier did not run on this subject and no arm below can be evidence' )
        return 1
    if not rows:
        no( '(A0) the XML map has an <inv> tier with no <ls> row, so every arm below would pass by vacuity' )
        return 1
    if not groups:
        no( '(A0) no <d> group was emitted on this subject (%d rows): either the encoding is not in this binary, '
            'or no prefix paid for itself here — in both cases (A1)/(C1)/(D1) prove nothing about nesting' % len( rows ) )
        return 1
    ok( '(A0) subject produced %d <ls> row(s) in %d <d> group(s), max nesting depth %d — the arms below have something to read'
        % ( len( rows ), len( groups ), maxDepth ) )

    # ── (A1) Band A: set identity against the flat JSON twin ─────────────────────────────────────────
    onlyX, onlyJ = diff( rows, oracle )
    if len( rows ) != len( oracle ):
        no( '(A1) Band A: %d flattened XML row(s) against %d JSON row(s) — the encoding added or lost a row' % ( len( rows ), len( oracle ) ) )
    elif onlyX or onlyJ:
        no( '(A1) Band A: the flattened rows are not the JSON rows. only in XML: %s ... only in JSON: %s'
            % ( onlyX[ :3 ], onlyJ[ :3 ] ) )
    else:
        named = sum( 1 for r in rows if r[ 2 ] )
        ok( '(A1) Band A: all %d flattened row(s) match the flat JSON twin exactly — same paths, same n=, same f= membership '
            '(%d row(s) carry names)' % ( len( rows ), named ) )

    # ── (A2) control: the comparison can fail ────────────────────────────────────────────────────────
    #   A planted mutation must be DETECTED. Without this, (A1) could be comparing a value against itself.
    mutations = [
        ( 'a dropped row',       rows[ :-1 ] ),
        ( 'a changed n=',        [ ( rows[ 0 ][ 0 ], str( int( rows[ 0 ][ 1 ] ) + 1 ), rows[ 0 ][ 2 ] ) ] + rows[ 1: ] ),
    ]
    withNames = next( ( i for i, r in enumerate( rows ) if len( r[ 2 ] ) > 1 ), None )
    if withNames is not None:
        r = rows[ withNames ]
        mutations.append( ( 'a dropped f= name',
                            rows[ :withNames ] + [ ( r[ 0 ], r[ 1 ], r[ 2 ][ :-1 ] ) ] + rows[ withNames + 1: ] ) )
    missed = [ nameOf for nameOf, mut in mutations if not any( diff( mut, oracle ) ) ]
    if missed:
        no( '(A2) control: %s went UNDETECTED by the same comparison (A1) uses, so (A1) is not evidence' % ', '.join( missed ) )
    else:
        ok( '(A2) control: %d planted mutation(s) (%s) are each detected — (A1) can fail'
            % ( len( mutations ), ', '.join( m[ 0 ] for m in mutations ) ) )

    # ── (C1) every group pays, and the document is no larger than the same rows flat ─────────────────
    #   The model is the emitter's own: a <d p="SEG"> wrapper costs len(SEG)+12 bytes ( `<d p="` + SEG + `">`
    #   + `</d>` ) and saves len(SEG)+1 on each row it covers (the segment and its separator).
    unpaid = [ ( seg, depth, kids, kids * ( len( seg ) + 1 ) - ( len( seg ) + 12 ) )
               for seg, depth, kids in groups if kids * ( len( seg ) + 1 ) <= len( seg ) + 12 ]
    if unpaid:
        no( '(C1) %d group(s) cost more bytes than they save, so the encoding made the document BIGGER there: %s'
            % ( len( unpaid ), unpaid[ :3 ] ) )
    else:
        saved = sum( kids * ( len( seg ) + 1 ) - ( len( seg ) + 12 ) for seg, depth, kids in groups )
        ok( '(C1) every one of the %d group(s) pays for its wrapper; net saving on this subject %d B' % ( len( groups ), saved ) )

    # ── (C2) the document is NEVER larger than its flat self ────────────────────────────────────────
    #   A per-group decision is not enough: a document where one prefix barely pays still carries the whole
    #   <d p=> legend clause. tmux saved 5 B of rows and textual 54 B against a ~560 B clause, so both GREW
    #   by ~700 B until mapinventory.h took the decision at document level. This arm reads that back out of
    #   the shipped bytes: either there are no wrappers at all, or the rows they save out-pay the clause.
    clause = re.search( r'<!--\s*d p=SEG:.*?-->', xml, re.S )
    clauseLen = len( clause.group( 0 ) ) if clause else 0
    rowSaving = sum( kids * ( len( seg ) + 1 ) - ( len( seg ) + 12 ) for seg, _d, kids in groups )
    if clauseLen == 0:
        no( '(C2) the document carries %d <d> wrapper(s) but no <d p=SEG> legend clause — the vocabulary is '
            'undocumented in the answer that uses it' % len( groups ) )
    elif rowSaving <= clauseLen:
        no( '(C2) the wrappers save %d B of rows against a %d B legend clause, so this document is LARGER than its '
            'flat self — the document-level threshold in inventoryNestPlan did not fire' % ( rowSaving, clauseLen ) )
    else:
        ok( '(C2) rows save %d B against the %d B legend clause this document has to carry, so it is %d B smaller '
            'than its flat self' % ( rowSaving, clauseLen, rowSaving - clauseLen ) )

    # ── (D1) Band D: the order is the stated rule, not merely "some order" ───────────────────────────
    #   The rule: the JSON order, with each group's rows made contiguous at the position of the FIRST row of
    #   that group. Re-derive it from the oracle and require equality with what the document actually did.
    #   The emitter's grouping is HIERARCHICAL: depth-1 wrappers first, then depth-2 wrappers INSIDE them. A
    #   single-level re-derivation gets the wrong answer on every repo where both levels fire — it was this
    #   arm's first version, and it failed on 5 of 7 corpora while the emitter was correct, which is worth
    #   recording: a FAIL here means "the gate's model and the document disagree", and the model is as likely
    #   to be wrong as the document. So mirror the emitter: group at each level in turn, over the rows that
    #   actually joined a wrapper at that level.
    emitted = { ( seg, depth ) for seg, depth, _ in groups }

    def stable_group( seq, depth ):
        """Stable group-by on the depth-th segment, over the wrappers that were actually emitted. Each group's
        rows become contiguous at the position of the first of them; everything else keeps its place."""
        buckets, order = {}, []
        for r in seq:
            parts = [ s for s in r[ 0 ].split( '/' ) if s ]
            key = tuple( parts[ :depth ] ) if ( len( parts ) > depth and ( parts[ depth - 1 ], depth ) in emitted ) else None
            if key is None:
                order.append( ( None, r ) )
            elif key in buckets:
                buckets[ key ].append( r )
            else:
                buckets[ key ] = [ r ]
                order.append( ( key, None ) )
        out = []
        for key, r in order:
            if key is None:
                out.append( r )
            else:
                inner = buckets[ key ]
                out.extend( stable_group( inner, depth + 1 ) if depth < NEST_DEPTH else inner )
        return out

    expected = stable_group( oracle, 1 )
    if expected == rows:
        ok( '(D1) Band D: the document order is exactly the JSON order with each group made contiguous at its first row '
            '— the one reordering the legend clause describes' )
    else:
        firstBad = next( ( i for i, ( a, b ) in enumerate( zip( expected, rows ) ) if a != b ), min( len( expected ), len( rows ) ) )
        no( '(D1) Band D: the order is not the stated rule; first difference at row %d — expected %r, document has %r'
            % ( firstBad, expected[ firstBad ] if firstBad < len( expected ) else None,
                rows[ firstBad ] if firstBad < len( rows ) else None ) )

    # ── (E1) Band E: depth is the named constant, and it is 2 ───────────────────────────────────────
    src = open( root + '/src/mapinventory.h', encoding = 'utf-8' ).read()
    m = re.search( r'kInventoryNestDepth\s*=\s*(\d+)', src )
    if m is None:
        no( '(E1) Band E: src/mapinventory.h declares no kInventoryNestDepth — the depth is not a named constant, '
            'so nothing pins the shipped default at 2' )
    elif m.group( 1 ) != str( NEST_DEPTH ):
        no( '(E1) Band E: kInventoryNestDepth is %s, and the registration fixes the shipped default at %d' % ( m.group( 1 ), NEST_DEPTH ) )
    elif maxDepth > NEST_DEPTH:
        no( '(E1) Band E: the document nests <d> %d deep, past kInventoryNestDepth = %d' % ( maxDepth, NEST_DEPTH ) )
    else:
        ok( '(E1) Band E: kInventoryNestDepth = %d, declared in src/mapinventory.h, and the document nests at most %d deep'
            % ( NEST_DEPTH, maxDepth ) )

    # ── (E2) and it is reachable from the published limits ──────────────────────────────────────────
    try:
        limits = open( root + '/docs/LIMITS.md', encoding = 'utf-8' ).read()
    except OSError as e:
        no( '(E2) could not read docs/LIMITS.md (%s), so the constant\'s reachability is NOT-ESTABLISHED rather than proven' % e )
    else:
        if 'kInventoryNestDepth' in limits:
            ok( '(E2) kInventoryNestDepth is published in docs/LIMITS.md, as Band E requires of a shipped default' )
        else:
            no( '(E2) kInventoryNestDepth is not in docs/LIMITS.md — Band E requires the constant be reachable from the published limits' )

    return 0


def main():
    xmlPath, jsonPath, root = sys.argv[ 1 ], sys.argv[ 2 ], sys.argv[ 3 ]
    xml = open( xmlPath, encoding = 'utf-8' ).read()
    rows, maxDepth, groups = rows_from_xml( xml )
    oracle = rows_from_json( open( jsonPath, encoding = 'utf-8' ).read() )
    fail = [ False ]

    def ok( m ):  print( '  PASS  %s' % m )
    def no( m ):  print( '  FAIL  %s' % m ); fail[ 0 ] = True

    rc = arms( rows, maxDepth, groups, oracle, xml, root, ok, no )
    return 1 if ( fail[ 0 ] or rc ) else 0


if __name__ == '__main__':
    sys.exit( main() )
