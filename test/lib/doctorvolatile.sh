#!/usr/bin/env bash
# test/lib/doctorvolatile.sh — F6 (terminality round A, 2026-09-05).
#
# THE ONE PLACE the --doctor determinism comparisons strip machine-dependent fields, and the only place a
# reader has to look to know what is stripped.
#
# WHY. `--doctor`'s cache-dir check scans `$TMPDIR/ripwire`, a per-USER directory every ripwire process on
# the machine writes into. Two back-to-back runs of a perfectly deterministic binary therefore legitimately
# disagree about blobs=/bytes=, and about many=/blobs_floor=/truncated=, which are DERIVED from that same
# live scan. Three rounds recorded this as a determinism failure of the binary: capture-audit lane-L7
# ("shapingflagcheck (F) --doctor --token-budget=1 … stdout CHANGED" and "gitstampcheck determinism
# (--doctor)", both green when run alone), merge-wave2 §4, and the 2026-09-04 close. Reproduced here on a
# quiet machine in 6 consecutive runs: bytes= moved every time and blobs_floor=/truncated= flipped in 3 of 6.
#
# WHY A SHARED HELPER, AND WHY IT READS THE LIST OUT OF THE DOCUMENT. gitstampcheck had a private sed with
# a hard-coded, ORDER-DEPENDENT list — `blobs="N" bytes="N" many="N" truncated="N"` as one contiguous
# pattern. When the scan cap fires, the row is `blobs="…" blobs_floor="1" bytes="…" …`, the pattern does not
# match, NOTHING is scrubbed, and the arm reports a determinism failure. That is the residual flake, and it
# is a second copy of a list drifting from the emitter. So: the emitter DECLARES which of its own attributes
# are a live reading (`volatile="blobs,blobs_floor,bytes,many,truncated"` on the row), this helper strips
# exactly the attributes the document names, per row, order-independently, and both gates call this. A new
# volatile field is then covered by adding it to the emitter's declaration — there is no second list.
#
#   stripDoctorVolatile FILE   → FILE's content on stdout with every attribute named by its own row's
#                                volatile= list removed from that row. volatile= itself STAYS (it is a
#                                stable declaration, not a measurement), so the comparison still proves the
#                                declaration did not move. Rows with no volatile= are untouched, which is
#                                what keeps the comparison strict everywhere else.

stripDoctorVolatile(){
    python3 - "$1" <<'PYEOF'
import re, sys

doc = open( sys.argv[ 1 ], encoding = "utf-8", errors = "replace" ).read()


def scrubRow( m ):
    row = m.group( 0 )
    declared = re.search( r'\svolatile="([^"]*)"', row )
    if not declared:
        return row
    for name in [ n for n in declared.group( 1 ).split( "," ) if n ]:
        row = re.sub( r'\s%s="[^"]*"' % re.escape( name ), "", row )
    return row


sys.stdout.write( re.sub( r"<c\b[^>]*>", scrubRow, doc ) )
PYEOF
}
