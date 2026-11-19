#!/usr/bin/env bash
# packcallersharecheck.sh — --pack-task's <callers> section is the KEY BODY's own callers, and nothing else.
#
# WHAT THIS GATE USED TO ASSERT, AND WHY IT CHANGED (PB1, PT1 design D1, 2026-11-19). The section used to hold the
# 1-hop neighbours of SIX body anchors in BOTH directions, sorted by how many anchors corroborated each row
# (shared="N", omitted at 1) — graphrag-recon.md idea #1, landed 2026-08-21. D1 serves ONE body, so there is exactly
# one anchor: of_top= is always 1, every row's shared= would be 1, and corroboration is not a property the tool has
# any more. A gate asserting it could only ever fail, and a gate that cannot pass measures nothing. What replaced it
# is a narrower contract, and this file now gates THAT — red-first against any change that widens the section back:
#   (1) of_top="1": one anchor, the key body
#   (2) every row is rel="caller" — the key body's CALLEES ride its own <calls> listing, never here (a callee row
#       in this section is the old two-direction walk coming back)
#   (3) shared= appears on no row and in no dialect: with one anchor it could only ever read 1, and a count that
#       can only take one value is bytes with no information in them
#   (4) the rows are the callers of the SERVED body (the <b> row's n=), not of some other candidate
#   (5) determinism x3, byte-identical, and xmllint-clean (G4)
#   (6) a tight, genuinely capped budget keeps shown=/total=/capped= consistent and the section non-empty-or-honest
#
# Usage:  RIPWIRE_BIN=build/ripwire test/packcallersharecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/…
# Exits non-zero on any failure. Listed in test/regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "packcallersharecheck: BIN=$BIN"

# ── the fixture: one task-named symbol with TWO callees and ONE caller, plus a second ranked function that has
#    its own private callee. The old two-direction walk over several anchors would pull helperOne/helperTwo and
#    otherOnly into this section; the key body's own callers are exactly { callerOfSolo }.
WORK="$TMP/keycallers"; mkdir -p "$WORK"
cat > "$WORK/lib.py" <<'EOF'
def anchorSolo():
    """anchorSolo calls helperOne and helperTwo."""
    helperOne()
    helperTwo()

def helperOne():
    """helperOne only reachable from anchorSolo."""
    pass

def helperTwo():
    """helperTwo only reachable from anchorSolo."""
    pass

def callerOfSolo():
    """the one caller of anchorSolo."""
    anchorSolo()

def otherRanked():
    """another ranked anchorSolo-adjacent function."""
    otherOnly()

def otherOnly():
    """private to otherRanked."""
    pass
EOF
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
run(){ ( cd "$WORK" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

TASK='fix `anchorSolo` and otherRanked'
run --pack-task="$TASK" --token-budget=6000 --legend=full > "$TMP/a.xml"

python3 - "$TMP/a.xml" <<'PY' > "$TMP/v.txt"
import re, sys, xml.etree.ElementTree as ET
raw  = open( sys.argv[1], encoding = 'utf-8' ).read()
root = ET.fromstring( raw )
c    = root.find( 'callers' )
b    = root.find( 'bodies' )
served = [ e.get( 'n' ) for e in ( b if b is not None else [] ) if e.tag == 'b' ]
rows   = list( c ) if c is not None else []
print( 'OFTOP', ( c.get( 'of_top' ) if c is not None else '' ) )
print( 'RELS', ','.join( sorted( { ( r.get( 'rel' ) or '' ) for r in rows } ) ) or 'none' )
print( 'SHARED', 'present' if re.search( r'\sshared="', raw ) else 'absent' )
print( 'SERVED', served[0] if served else '' )
print( 'NAMES', ','.join( sorted( ( r.get( 'n' ) or '' ) for r in rows ) ) or 'none' )
print( 'TAG', 'ok' if c is not None and all( k in c.attrib for k in ( 'shown', 'total', 'capped' ) )
       and ( c.get( 'capped' ) == '1' ) == ( int( c.get( 'shown' ) ) < int( c.get( 'total' ) ) ) else 'bad' )
PY
sed 's/^/        /' "$TMP/v.txt"

grep -q '^OFTOP 1$'   "$TMP/v.txt" && ok "(1) of_top=\"1\": one anchor, the key body" || no "(1) of_top is not 1 — the section has more than one anchor again"
grep -q '^RELS caller$' "$TMP/v.txt" && ok "(2) every row is rel=\"caller\" (the callees ride the body's own <calls>)" || no "(2) <callers> carries a non-caller row — the two-direction walk is back"
grep -q '^SHARED absent$' "$TMP/v.txt" && ok "(3) shared= appears nowhere: with one anchor it could only read 1" || no "(3) shared= is still emitted — bytes with no information in them"
grep -q '^NAMES callerOfSolo$' "$TMP/v.txt" && ok "(4) the rows are the SERVED body's callers, and only those" || no "(4) the rows are not exactly the served body's callers"
grep -q '^SERVED anchorSolo$' "$TMP/v.txt" && ok "(4b) fixture armed: the served body is the task-named symbol" || no "(4b) fixture never armed: the served body is not anchorSolo, so arm (4) proves nothing"
grep -q '^TAG ok$'    "$TMP/v.txt" && ok "(6) the section's shown=/total=/capped= agree" || no "(6) the section's shown=/total=/capped= contradict each other"

# arm (5) — determinism x3, byte-identical, then G4.
D1="$( run --pack-task="$TASK" --token-budget=6000 )"
D2="$( run --pack-task="$TASK" --token-budget=6000 )"
D3="$( run --pack-task="$TASK" --token-budget=6000 )"
[ "$D1" = "$D2" ] && [ "$D2" = "$D3" ] && ok "(5) the bundle is deterministic (byte-identical x3)" || no "(5) the bundle is NOT deterministic across 3 runs"
printf '%s' "$D1" | xmllint --noout - 2>/dev/null && ok "(5b) the bundle is xmllint-clean (G4)" || no "(5b) the bundle is NOT well-formed XML"

# arm (6b) — the same consistency at a TIGHT budget, where the section is the first thing the cascade starves.
run --pack-task="$TASK" --token-budget=900 --legend=full > "$TMP/t.xml"
python3 - "$TMP/t.xml" <<'PY' > "$TMP/t.txt"
import sys, xml.etree.ElementTree as ET
root = ET.parse( sys.argv[1] ).getroot()
c = root.find( 'callers' )
if c is None:
    print( 'TIGHT absent' )
else:
    s, t = int( c.get( 'shown' ) or 0 ), int( c.get( 'total' ) or 0 )
    print( 'TIGHT', 'ok' if ( c.get( 'capped' ) == '1' ) == ( s < t ) and s <= t else 'bad' )
PY
cat "$TMP/t.txt" | sed 's/^/        /'
grep -qE '^TIGHT (ok|absent)$' "$TMP/t.txt" && ok "(6b) at a tight budget the section is either absent or self-consistent" || no "(6b) at a tight budget the section contradicts itself"

[ $fail -eq 0 ] && { echo "packcallersharecheck: PASS"; exit 0; }
echo "packcallersharecheck: FAIL"; exit 1
