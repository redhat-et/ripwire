#!/usr/bin/env bash
# recallwindowcheck.sh — HTML-CUT gate (DOCS-XS, 2026-11-05): a recalled document with NO section units (an
# HTML page's converted text, a heading-less note) that must be cut to its water-fill share serves the best
# query-term WINDOW of that share's size, not its head, and says so on the separator line.
#
# The defect this pins: the whole-doc path in buildRecall (src/recall.h) cut such a body with a PREFIX, so an
# HTML page served its nav list and contents block and the paragraph the query matched sat past the cut
# (reports/docs-quick-s0.md: 6 dev anchors on the docs set were lost this way). Same bytes, better bytes.
#
# ARMS
#   (a) HTML: a page whose head is a long nav list and whose matching paragraph sits deep in the page.
#       Under a ceiling that forces a cut, the paragraph is PRINTED, the marker reads
#       "served bytes LO-HI, best query-term window", the body opens with a "…" line, and the
#       nav head is NOT printed. Base binaries print the head: red there.
#   (b) Heading-less markdown, where the served text IS the file: bytes LO..LO+K of the file on disk equal the
#       printed body (minus the "…" lead and the trailing "…"), so the disclosed range is exact, and K matches
#       the marker's kept count.
#   (c) Positive twin of the head cut: when the query's terms sit in the head, the marker is the plain
#       "[truncated: K of N bytes]" with no window clause and no "…" lead (byte shape unchanged from before).
#   (d) Tie-break: two identical matching paragraphs, far apart — the window serves the EARLIER one.
#   (e) A window that starts inside a fence stays inside it (moving back to the opener spends the window on
#       the fence's head; the old whole-or-nothing rule then dropped the fence: an empty body), the opener line
#       is repeated above the served lines (fence_reopened), the matching code line is printed, fences balance.
#   (e2) A sweep of fence lengths around the window size, one match inside the fence and one after it: every
#       run prints a match and balanced fences, never an empty body, and the sweep must hit a fence the window
#       ends inside (fence_closed: the cut keeps the window's own last line instead of retreating behind the
#       match to an earlier sentence end or the fence's start).
#   (f) Budget: every run stays under its --max-tokens ceiling (no over_ceiling=1), and runs are
#       deterministic (byte-identical twice).
#   (g) Every run's exit code is checked; a crashed or empty run is a FAIL, never a quiet pass.
#
# Usage:  test/recallwindowcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/recallwindowcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "recallwindowcheck: BIN=$BIN"

# Short fixed-depth roots: the separator line's path length competes with the body for the same budget.
R="$( mktemp -d "/tmp/rwwinXXXXXX" )"; trap 'rm -rf "$R"' EXIT
mkdir -p "$R/h" "$R/m" "$R/c" "$R/t" "$R/f"
python3 - "$R" <<'PY'
import sys
r = sys.argv[1]
nav = "".join( '<li><a href="/p%03d.html">Navigation entry %03d of the site contents</a></li>\n' % ( i, i ) for i in range( 160 ) )
filler = "".join( "<p>Unrelated paragraph %03d about installation steps and general setup notes.</p>\n" % i for i in range( 40 ) )
target = "<p>The zorblax quantum flux capacitor reroutes the frobnicate pipeline when the zorblax limit trips.</p>\n"
open( r + "/h/page.html", "w" ).write(
    "<html><head><title>Guide</title></head><body>\n<nav><ul>\n" + nav + "</ul></nav>\n<main>\n" + filler + target
    + filler.replace( "Unrelated", "Trailing" ) + "</main></body></html>\n" )
# (b) heading-less markdown: plain lines, the matching line deep inside
plain = "".join( "Plain line %04d says nothing in particular about the setup.\n" % i for i in range( 300 ) )
open( r + "/m/notes.md", "w" ).write( plain + "The zorblax quantum flux capacitor reroutes the frobnicate pipeline.\n" + plain.replace( "Plain", "Later" ) )
# (c) the terms in the head
open( r + "/c/notes.md", "w" ).write( "The zorblax quantum flux capacitor reroutes the frobnicate pipeline.\n" + plain )
# (d) two identical matches, far apart
open( r + "/t/notes.md", "w" ).write( plain + "Zorblax frobnicate pipeline FIRST copy.\n" + plain.replace( "Plain", "Middle" )
                                     + "Zorblax frobnicate pipeline FIRST copy.\n" + plain.replace( "Plain", "Later" ) )
# (e) the matching line inside a long fenced block, whose opening sits well before it
fence = "```\n" + "".join( "code line %03d of the example listing\n" % i for i in range( 30 ) ) + "zorblax frobnicate pipeline call\n" + "".join( "code line %03d tail\n" % i for i in range( 5 ) ) + "```\n"
open( r + "/f/notes.md", "w" ).write( plain + fence + plain.replace( "Plain", "Later" ) )
PY

# run DIR QUERY TOKENS -> stdout; exit code in $RC
run(){ OUT="$( cd "$R/$1" && perl -e 'alarm 30; exec @ARGV' "$BIN" "$R/$1" --recall="$2" --no-cache --max-tokens="$3" 2>/dev/null )"; RC=$?; }
sepline(){ printf '%s\n' "$OUT" | grep -m1 '^━━ '; }
body(){ printf '%s\n' "$OUT" | awk 'f&&/^━━ /{exit} /^━━ /{f=1;next} f'; }
checkrun(){   # (g) every run read: exit 0 and a separator line, or the arm is red
    if [ "$RC" = 0 ] && [ -n "$( sepline )" ]; then return 0; fi
    no "$1: exit $RC, separator line '$( sepline )' — the run crashed or printed no document"; return 1
}
overceil(){ printf '%s\n' "$OUT" | head -1 | grep -q 'over_ceiling=1'; }

echo; echo "=== (a) HTML page: the matching paragraph, not the nav head ==="
run h "zorblax flux capacitor frobnicate" 700
if checkrun "(a)"; then
    S="$( sepline )"
    printf '%s' "$S" | grep -qE '\[truncated: [0-9]+ of [0-9]+ bytes; served bytes [0-9]+-[0-9]+, best query-term window\]' \
        && ok "(a) marker names the served window: $( printf '%s' "$S" | grep -oE '\[truncated[^]]*\]' )" \
        || no "(a) no window marker on the separator: $S"
    body | grep -q 'zorblax quantum flux capacitor' \
        && ok "(a) the matching paragraph is printed" \
        || no "(a) the matching paragraph is NOT printed (head served?) — first body line: $( body | head -1 )"
    body | grep -q 'Navigation entry 000' \
        && no "(a) the nav head (entry 000) is still printed" \
        || ok "(a) the nav head is skipped"
    [ "$( body | head -1 )" = "…" ] \
        && ok "(a) the body opens with a '…' line (text skipped above)" \
        || no "(a) the body does not open with the '…' lead: '$( body | head -1 )'"
    overceil && no "(a) over_ceiling=1 under --max-tokens=700" || ok "(a) within the 700-token ceiling"
    A1="$OUT"; run h "zorblax flux capacitor frobnicate" 700
    [ "$OUT" = "$A1" ] && ok "(a) deterministic (byte-identical twice)" || no "(a) two runs differ"
fi

echo; echo "=== (b) heading-less markdown: the disclosed byte range is exact ==="
run m "zorblax flux capacitor frobnicate" 700
if checkrun "(b)"; then
    S="$( sepline )"
    LO="$( printf '%s' "$S" | grep -oE 'served bytes [0-9]+-[0-9]+' | grep -oE '[0-9]+' | sed -n 1p )"
    HI="$( printf '%s' "$S" | grep -oE 'served bytes [0-9]+-[0-9]+' | grep -oE '[0-9]+' | sed -n 2p )"
    K="$( printf '%s' "$S" | grep -oE '\[truncated: [0-9]+' | grep -oE '[0-9]+' )"
    if [ -n "$LO" ] && [ -n "$HI" ] && [ -n "$K" ]; then
        [ $(( HI - LO )) = "$K" ] && ok "(b) HI-LO ($HI-$LO) = kept $K" || no "(b) HI-LO = $(( HI - LO )) but the marker kept $K"
        body > "$R/b.body"
        python3 - "$R/m/notes.md" "$R/b.body" "$LO" "$HI" <<'PY' && ok "(b) bytes LO..HI of the file on disk are exactly the printed body" || no "(b) the printed body is not bytes LO..HI of the file"
import sys
src = open( sys.argv[1], "rb" ).read(); got = open( sys.argv[2], "rb" ).read()
lo, hi = int( sys.argv[3] ), int( sys.argv[4] )
lead = "…\n".encode(); ell = "…".encode()
assert got.startswith( lead ), "no lead"
got = got[ len( lead ): ].rstrip( b"\n" )
if got.endswith( ell ): got = got[ : -len( ell ) ]
got = got.rstrip( b"\n" )
want = src[ lo:hi ].rstrip( b"\n" )
sys.exit( 0 if got == want else 1 )
PY
        body | grep -q 'zorblax quantum flux capacitor' && ok "(b) the matching line is printed" || no "(b) the matching line is not printed"
    else
        no "(b) no 'served bytes LO-HI' / kept count on the separator: $S"
    fi
    overceil && no "(b) over_ceiling=1" || ok "(b) within the ceiling"
fi

echo; echo "=== (c) terms in the head: the plain head cut, unchanged shape ==="
run c "zorblax flux capacitor frobnicate" 700
if checkrun "(c)"; then
    S="$( sepline )"
    printf '%s' "$S" | grep -qE '\[truncated: [0-9]+ of [0-9]+ bytes\]$' \
        && ok "(c) plain head marker: $( printf '%s' "$S" | grep -oE '\[truncated[^]]*\]' )" \
        || no "(c) expected the plain '[truncated: K of N bytes]' marker: $S"
    [ "$( body | head -1 )" = "The zorblax quantum flux capacitor reroutes the frobnicate pipeline." ] \
        && ok "(c) the body starts at the head, no '…' lead" || no "(c) the body does not start at the head: '$( body | head -1 )'"
fi

echo; echo "=== (d) tie-break: the earlier of two equal windows ==="
run t "zorblax frobnicate pipeline" 700
if checkrun "(d)"; then
    LO="$( sepline | grep -oE 'served bytes [0-9]+-' | grep -oE '[0-9]+' )"
    FIRST="$( python3 -c 'import sys; print(open(sys.argv[1],"rb").read().find(b"Zorblax frobnicate"))' "$R/t/notes.md" )"
    SECOND="$( python3 -c 'import sys; print(open(sys.argv[1],"rb").read().rfind(b"Zorblax frobnicate"))' "$R/t/notes.md" )"
    if [ -n "$LO" ] && [ "$LO" -le "$FIRST" ] && [ "$SECOND" -gt $(( FIRST + 3000 )) ]; then
        ok "(d) window starts at $LO, at or before the first copy ($FIRST; the second is at $SECOND)"
    else
        no "(d) window start '${LO:-<none>}' is not the earlier copy (first $FIRST, second $SECOND)"
    fi
fi

echo; echo "=== (e) a window landing inside a fence too big for it: stays inside, fence reopened ==="
run f "zorblax frobnicate pipeline" 700
if checkrun "(e)"; then
    S="$( sepline )"
    LO="$( printf '%s' "$S" | grep -oE 'served bytes [0-9]+-' | grep -oE '[0-9]+' )"
    FENCE="$( python3 -c 'import sys; print(open(sys.argv[1],"rb").read().find(b"```"))' "$R/f/notes.md" )"
    [ -n "$LO" ] && [ "$LO" -gt "$FENCE" ] && ok "(e) window starts inside the fence (byte $LO > opener $FENCE)" \
        || no "(e) window start '${LO:-<none>}' is not inside the fence opened at $FENCE: $S"
    printf '%s' "$S" | grep -q 'fence_reopened' && ok "(e) marker says fence_reopened" || no "(e) no fence_reopened on: $S"
    [ "$( body | sed -n 2p )" = '```' ] && ok "(e) the opener is repeated right under the '…' lead" || no "(e) line 2 is '$( body | sed -n 2p )', not the fence opener"
    N="$( body | grep -c '^```' )"
    [ $(( N % 2 )) = 0 ] && [ "$N" -gt 0 ] && ok "(e) fences balance ($N fence lines)" || no "(e) unbalanced fences ($N)"
    body | grep -q 'zorblax frobnicate pipeline call' && ok "(e) the matching code line is printed" || no "(e) the matching code line is not printed"
fi

echo; echo "=== (e2) fence-length sweep: never an empty body, fences torn only with disclosure ==="
python3 - "$R" <<'PY'
import os, sys
r = sys.argv[1]
plain = "".join( "Plain line %04d says nothing in particular about the setup.\n" % i for i in range( 300 ) )
for n in range( 760, 1000, 8 ):
    pad = n - len( "```\n" ) - len( "zorblax frobnicate pipeline call\n" ) - len( "```\n" )
    code = "".join( "x" * 59 + "\n" for _ in range( pad // 60 ) ) + "y" * ( pad % 60 - 1 ) + "\n" if pad % 60 else "".join( "x" * 59 + "\n" for _ in range( pad // 60 ) )
    fence = "```\n" + "zorblax frobnicate pipeline call\n" + code + "```\n"
    assert len( fence ) == n, ( n, len( fence ) )
    os.makedirs( "%s/s%d" % ( r, n ) )
    open( "%s/s%d/notes.md" % ( r, n ), "w" ).write( plain + fence + "Zorblax frobnicate pipeline again.\n" + plain.replace( "Plain", "Later" ) )
PY
CLOSED=0; REOPEN=0; BAD=0
for d in "$R"/s*; do
    n="${d##*/s}"
    run "s$n" "zorblax frobnicate pipeline" 700
    if [ "$RC" != 0 ] || [ -z "$( sepline )" ]; then no "(e2) n=$n: exit $RC / no document"; BAD=$(( BAD + 1 )); continue; fi
    S="$( sepline )"
    N="$( body | grep -c '^```' )"
    if ! body | grep -qiE 'zorblax frobnicate pipeline (call|again)' || [ $(( N % 2 )) != 0 ]; then
        no "(e2) n=$n: no match printed or fences unbalanced ($N): $S"; BAD=$(( BAD + 1 )); continue
    fi
    printf '%s' "$S" | grep -q 'fence_closed' && CLOSED=$(( CLOSED + 1 ))
    printf '%s' "$S" | grep -q 'fence_reopened' && REOPEN=$(( REOPEN + 1 ))
done
[ "$BAD" = 0 ] && ok "(e2) every sweep run prints a match with balanced fences" || no "(e2) $BAD sweep runs failed"
[ "$CLOSED" -gt 0 ] && ok "(e2) $CLOSED sweep runs cut inside a fence the window ends in (fence_closed)" || no "(e2) no sweep run cut inside a trailing fence"
ok "(e2) $REOPEN sweep runs started inside a fence (fence_reopened; arm (e) pins that branch)"

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
