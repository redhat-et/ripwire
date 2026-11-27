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
#       "served bytes LO-HI, best query-term window", the body opens with the page's title (the converted
#       text's first line) and then a "…" line, and the nav head is NOT printed. Base binaries print the head:
#       red there.
#   (a2) A first line too long to be a title (> 120 bytes) is not repeated: the body opens with the "…" line.
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
#   (h) The window's LAST line is the line it was chosen for (the earliest-start tie-break puts the scoring line
#       at the tail), so the cut must keep it. A page end with NO trailing newline (every converted HTML page:
#       extractHtml trims; also a .md file, a CRLF file, a multibyte last line) prints the last line and
#       discloses a HI equal to the document size; the same files WITH a final newline are the positive twin.
#   (i) The repeated fence opener is paid for by the window's HEAD, never its tail: a sweep of fence line lengths
#       (backtick with an info string, `~~~`, an indented fence) prints the in-fence match in EVERY run, whatever
#       the spare bytes after the window; the sweep must reach fence_reopened.
#   (j) A window that starts inside a PIPE TABLE whose rows begin with a backtick is not a fence: no row is
#       copied above it as an "opener" and no fence_reopened is said (the range knows its kind).
#   (k) The window is scored AFTER the repeated opener is charged: a sweep of gaps between a rare-term line and a
#       common-term line, inside a fence with a long opener, prints the rare-term line in EVERY run (the old
#       head-drop shed it when the pair exactly filled the window).
#   (l) An oversized fence opener (a 5000-byte info word, a 100-byte info string) is repeated in a bare form of at
#       most 64 bytes, never as a copy that takes the window: the in-fence match is printed within the ceiling.
#   (m) The window must beat the head AS SERVED: a match that ends exactly at the head cut (so the title/lead-sized
#       head misses it) and an equal match far below tie, and the head wins the tie (plain marker, no window).
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
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "recallwindowcheck: BIN=$BIN"

# Short fixed-depth roots: the separator line's path length competes with the body for the same budget.
R="$( mktemp -d "/tmp/rwwinXXXXXX" )"; trap 'rm -rf "$R"' EXIT
mkdir -p "$R/h" "$R/m" "$R/c" "$R/t" "$R/f"
python3 - "$R" <<'PY'
import os, sys
r = sys.argv[1]
nav = "".join( '<li><a href="/p%03d.html">Navigation entry %03d of the site contents</a></li>\n' % ( i, i ) for i in range( 160 ) )
filler = "".join( "<p>Unrelated paragraph %03d about installation steps and general setup notes.</p>\n" % i for i in range( 40 ) )
target = "<p>The zorblax quantum flux capacitor reroutes the frobnicate pipeline when the zorblax limit trips.</p>\n"
open( r + "/h/page.html", "w" ).write(
    "<html><head><title>Guide</title></head><body>\n<nav><ul>\n" + nav + "</ul></nav>\n<main>\n" + filler + target
    + filler.replace( "Unrelated", "Trailing" ) + "</main></body></html>\n" )
os.makedirs( r + "/h2" )
open( r + "/h2/page.html", "w" ).write(
    "<html><head><title>" + "Very long title " * 12 + "</title></head><body>\n<nav><ul>\n" + nav + "</ul></nav>\n<main>\n" + filler + target
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
# (h) page ends with the matching line and NO trailing newline: md, md+newline twin, CRLF, multibyte, HTML
last = "The zorblax frobnicate pipeline is the last line"
for d, text in ( ( "n1", plain + last ), ( "n2", plain + last + "\n" ),
                 ( "n3", plain.replace( "\n", "\r\n" ) + last ),
                 ( "n4", plain + "Der zorblax frobnicate pipeline ist die letzte Zeile \u2014 sch\u00f6n" ) ):
    os.makedirs( "%s/%s" % ( r, d ) )
    open( "%s/%s/notes.md" % ( r, d ), "w", newline="", encoding="utf-8" ).write( text )
os.makedirs( r + "/n5" )
open( r + "/n5/page.html", "w" ).write(
    "<html><head><title>Guide</title></head><body>\n<nav><ul>\n" + nav + "</ul></nav>\n<main>\n" + filler
    + "<p>The zorblax frobnicate pipeline honours the output.input-404 setting.</p>\n</main></body></html>\n" )
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
    if printf '%s' "$S" | grep -qE '\[truncated: [0-9]+ of [0-9]+ bytes; served bytes [0-9]+-[0-9]+, best query-term window\]'; then
        ok "(a) marker names the served window: $( printf '%s' "$S" | grep -oE '\[truncated[^]]*\]' )"
    else
        no "(a) no window marker on the separator: $S"
    fi
    if body | grep -q 'zorblax quantum flux capacitor'; then
        ok "(a) the matching paragraph is printed"
    else
        no "(a) the matching paragraph is NOT printed (head served?) — first body line: $( body | head -1 )"
    fi
    if body | grep -q 'Navigation entry 000'; then
        no "(a) the nav head (entry 000) is still printed"
    else
        ok "(a) the nav head is skipped"
    fi
    if [ "$( body | head -1 )" = "Guide" ] && [ "$( body | sed -n 2p )" = "…" ]; then
        ok "(a) the page title ('Guide') sits above the '…' line (text skipped below it)"
    else
        no "(a) the body does not open with the title and the '…' lead: '$( body | head -2 | tr '\n' '|' )'"
    fi
    if overceil; then no "(a) over_ceiling=1 under --max-tokens=700"; else ok "(a) within the 700-token ceiling"; fi
    A1="$OUT"; run h "zorblax flux capacitor frobnicate" 700
    if [ "$OUT" = "$A1" ]; then ok "(a) deterministic (byte-identical twice)"; else no "(a) two runs differ"; fi
fi

echo; echo "=== (a2) a first line too long to be a title is not repeated ==="
run h2 "zorblax flux capacitor frobnicate" 700
if checkrun "(a2)"; then
    if [ "$( body | head -1 )" = "…" ]; then ok "(a2) the body opens with the '…' line, no title"; else no "(a2) expected no title line: '$( body | head -1 | cut -c1-60 )'"; fi
    if body | grep -q 'zorblax quantum flux capacitor'; then ok "(a2) the matching paragraph is printed"; else no "(a2) the matching paragraph is NOT printed"; fi
fi

echo; echo "=== (b) heading-less markdown: the disclosed byte range is exact ==="
run m "zorblax flux capacitor frobnicate" 700
if checkrun "(b)"; then
    S="$( sepline )"
    LO="$( printf '%s' "$S" | grep -oE 'served bytes [0-9]+-[0-9]+' | grep -oE '[0-9]+' | sed -n 1p )"
    HI="$( printf '%s' "$S" | grep -oE 'served bytes [0-9]+-[0-9]+' | grep -oE '[0-9]+' | sed -n 2p )"
    K="$( printf '%s' "$S" | grep -oE '\[truncated: [0-9]+' | grep -oE '[0-9]+' )"
    if [ -n "$LO" ] && [ -n "$HI" ] && [ -n "$K" ]; then
        if [ $(( HI - LO )) = "$K" ]; then ok "(b) HI-LO ($HI-$LO) = kept $K"; else no "(b) HI-LO = $(( HI - LO )) but the marker kept $K"; fi
        body > "$R/b.body"
        if python3 - "$R/m/notes.md" "$R/b.body" "$LO" "$HI" <<'PY'
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
        then
            ok "(b) bytes LO..HI of the file on disk are exactly the printed body"
        else
            no "(b) the printed body is not bytes LO..HI of the file"
        fi
        if body | grep -q 'zorblax quantum flux capacitor'; then ok "(b) the matching line is printed"; else no "(b) the matching line is not printed"; fi
    else
        no "(b) no 'served bytes LO-HI' / kept count on the separator: $S"
    fi
    if overceil; then no "(b) over_ceiling=1"; else ok "(b) within the ceiling"; fi
fi

echo; echo "=== (c) terms in the head: the plain head cut, unchanged shape ==="
run c "zorblax flux capacitor frobnicate" 700
if checkrun "(c)"; then
    S="$( sepline )"
    if printf '%s' "$S" | grep -qE '\[truncated: [0-9]+ of [0-9]+ bytes\]$'; then
        ok "(c) plain head marker: $( printf '%s' "$S" | grep -oE '\[truncated[^]]*\]' )"
    else
        no "(c) expected the plain '[truncated: K of N bytes]' marker: $S"
    fi
    if [ "$( body | head -1 )" = "The zorblax quantum flux capacitor reroutes the frobnicate pipeline." ]; then
        ok "(c) the body starts at the head, no '…' lead"
    else
        no "(c) the body does not start at the head: '$( body | head -1 )'"
    fi
fi

echo; echo "=== (d) tie-break: the earlier of two equal windows ==="
run t "zorblax frobnicate pipeline" 700
if checkrun "(d)"; then
    LO="$( sepline | grep -oE 'served bytes [0-9]+-' | grep -oE '[0-9]+' )"
    FIRST="$( python3 -c 'import sys; print(open(sys.argv[1],"rb").read().find(b"Zorblax frobnicate"))' "$R/t/notes.md" )"
    SECOND="$( python3 -c 'import sys; print(open(sys.argv[1],"rb").read().rfind(b"Zorblax frobnicate"))' "$R/t/notes.md" )"
    HI="$( sepline | grep -oE 'served bytes [0-9]+-[0-9]+' | grep -oE '[0-9]+' | sed -n 2p )"
    FIRSTEND=$(( FIRST + $( printf '%s' 'Zorblax frobnicate pipeline FIRST copy.' | wc -c | tr -d ' ' ) ))
    if [ -n "$LO" ] && [ -n "$HI" ] && [ "$LO" -le "$FIRST" ] && [ "$HI" -ge "$FIRSTEND" ] && [ "$SECOND" -gt $(( FIRST + 3000 )) ]; then
        ok "(d) window $LO-$HI covers the first copy ($FIRST-$FIRSTEND; the second is at $SECOND)"
    else
        no "(d) window '${LO:-<none>}-${HI:-<none>}' does not cover the earlier copy (first $FIRST-$FIRSTEND, second $SECOND)"
    fi
    if body | grep -q 'FIRST copy'; then ok "(d) the first copy is printed"; else no "(d) the first copy is not printed"; fi
fi

echo; echo "=== (e) a window landing inside a fence too big for it: stays inside, fence reopened ==="
run f "zorblax frobnicate pipeline" 700
if checkrun "(e)"; then
    S="$( sepline )"
    LO="$( printf '%s' "$S" | grep -oE 'served bytes [0-9]+-' | grep -oE '[0-9]+' )"
    FENCE="$( python3 -c 'import sys; print(open(sys.argv[1],"rb").read().find(b"```"))' "$R/f/notes.md" )"
    FENCEEND="$( python3 -c 'import sys; d=open(sys.argv[1],"rb").read(); print(d.find(b"```\n", d.find(b"```")+3)+4)' "$R/f/notes.md" )"
    HI="$( printf '%s' "$S" | grep -oE 'served bytes [0-9]+-[0-9]+' | grep -oE '[0-9]+' | sed -n 2p )"
    if [ -n "$LO" ] && [ -n "$HI" ] && [ "$LO" -gt "$FENCE" ] && [ "$LO" -lt "$FENCEEND" ] && [ "$HI" -gt "$LO" ]; then
        ok "(e) window $LO-$HI starts inside the fence (opener at $FENCE, closer ends at $FENCEEND)"
    else
        no "(e) window start '${LO:-<none>}' is not inside the fence ($FENCE-$FENCEEND): $S"
    fi
    body > "$R/e.body"
    if python3 - "$R/f/notes.md" "$R/e.body" "$LO" "$HI" "$S" <<'PY'
import sys
src = open( sys.argv[1], "rb" ).read(); got = open( sys.argv[2], "rb" ).read()
lo, hi, marker = int( sys.argv[3] ), int( sys.argv[4] ), sys.argv[5]
lead = "…\n".encode(); ell = "…".encode()
assert got.startswith( lead ), "no lead"
got = got[ len( lead ): ]
if "fence_reopened" in marker:
    got = got.split( b"\n", 1 )[ 1 ]          # the repeated opener is the function's copy, not source
got = got.rstrip( b"\n" )
if "fence_closed" in marker:
    got = got.rsplit( b"\n", 1 )[ 0 ].rstrip( b"\n" )   # the repair closer, after the ellipsis
if got.endswith( ell ): got = got[ : -len( ell ) ]
sys.exit( 0 if got.rstrip( b"\n" ) == src[ lo:hi ].rstrip( b"\n" ) else 1 )
PY
    then ok "(e) bytes LO..HI of the file are exactly the printed body (less the opener copy and the repair)"; else no "(e) the printed body is not bytes LO..HI of the file"; fi
    if printf '%s' "$S" | grep -q 'fence_reopened'; then ok "(e) marker says fence_reopened"; else no "(e) no fence_reopened on: $S"; fi
    if [ "$( body | sed -n 2p )" = '```' ]; then
        ok "(e) the opener is repeated right under the '…' lead"
    else
        no "(e) line 2 is '$( body | sed -n 2p )', not the fence opener"
    fi
    N="$( body | grep -c '^```' )"
    if [ $(( N % 2 )) = 0 ] && [ "$N" -gt 0 ]; then ok "(e) fences balance ($N fence lines)"; else no "(e) unbalanced fences ($N)"; fi
    if body | grep -q 'zorblax frobnicate pipeline call'; then ok "(e) the matching code line is printed"; else no "(e) the matching code line is not printed"; fi
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
    if overceil; then no "(e2) n=$n: over_ceiling=1"; BAD=$(( BAD + 1 )); continue; fi
    S="$( sepline )"
    N="$( body | grep -c '^```' )"
    if ! body | grep -qiE 'zorblax frobnicate pipeline (call|again)' || [ $(( N % 2 )) != 0 ]; then
        no "(e2) n=$n: no match printed or fences unbalanced ($N): $S"; BAD=$(( BAD + 1 )); continue
    fi
    printf '%s' "$S" | grep -q 'fence_closed' && CLOSED=$(( CLOSED + 1 ))
    printf '%s' "$S" | grep -q 'fence_reopened' && REOPEN=$(( REOPEN + 1 ))
done
if [ "$BAD" = 0 ]; then ok "(e2) every sweep run prints a match with balanced fences"; else no "(e2) $BAD sweep runs failed"; fi
if [ "$CLOSED" -gt 0 ]; then
    ok "(e2) $CLOSED sweep runs cut inside a fence the window ends in (fence_closed)"
else
    no "(e2) no sweep run cut inside a trailing fence"
fi
ok "(e2) $REOPEN sweep runs started inside a fence (fence_reopened; arm (e) pins that branch)"

echo; echo "=== (h) the window's last line survives a page end with no trailing newline ==="
for d in n1 n2 n3 n4 n5; do
    run "$d" "zorblax frobnicate pipeline" 700
    if checkrun "(h) $d"; then
        if overceil; then no "(h) $d: over_ceiling=1"; fi
        S="$( sepline )"
        case "$d" in
            n1) WANT='is the last line' ;;
            n2) WANT='is the last line' ;;
            n3) WANT='is the last line' ;;
            n4) WANT='letzte Zeile' ;;
            n5) WANT='output.input-404' ;;
        esac
        if body | grep -q "$WANT"; then
            ok "(h) $d: the page's last line is printed"
        else
            no "(h) $d: the last line ('$WANT') is NOT printed — marker: $S"
        fi
        if printf '%s' "$S" | grep -q 'best query-term window'; then
            ok "(h) $d: a window was served"
        else
            no "(h) $d: expected a windowed cut (the arm would pin nothing): $S"
        fi
        if [ "$d" != n5 ]; then
            F="$( wc -c < "$R/$d/notes.md" | tr -d ' ' )"
            HI="$( printf '%s' "$S" | grep -oE 'served bytes [0-9]+-[0-9]+' | grep -oE '[0-9]+' | sed -n 2p )"
            if [ "$HI" = "$F" ]; then ok "(h) $d: served range ends at the document end ($HI)"; else no "(h) $d: HI '$HI' is not the document size $F"; fi
        fi
        if printf '%s' "$OUT" | python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8")'; then
            ok "(h) $d: output is valid UTF-8"
        else
            no "(h) $d: output is not valid UTF-8"
        fi
    fi
done

echo; echo "=== (i) the fence opener is paid for by the window head, never the tail ==="
python3 - "$R" <<'PY'
import os, sys
r = sys.argv[1]
plain = "".join( "Plain line %04d says nothing in particular about the setup.\n" % i for i in range( 300 ) )
call = "zorblax frobnicate pipeline call\n"
def fx( kind, n ):
    ind = "    " if kind == "ind" else ""
    opener = { "bt": "```python\n", "tl": "~~~text\n", "ind": "    ```python\n" }[kind]
    closer = ind + ( "~~~\n" if kind == "tl" else "```\n" )
    code = ( ind + "x" * ( n - 1 - len( ind ) ) + "\n" ) * 60
    pre = "- item\n\n" if kind == "ind" else ""
    return plain + pre + opener + code + ind + call + code + closer + plain.replace( "Plain", "Later" )
for kind, step in ( ( "bt", 2 ), ( "tl", 3 ), ( "ind", 3 ) ):
    for n in range( 21, 80, step ):
        d = "%s/o%s%d" % ( r, kind, n )
        os.makedirs( d )
        open( d + "/notes.md", "w" ).write( fx( kind, n ) )
PY
for kind in bt tl ind; do
    BAD=0; REO=0; RUNS=0
    for d in "$R"/o"$kind"[0-9]*; do
        n="${d##*/o}"
        run "o$n" "zorblax frobnicate pipeline" 700
        RUNS=$(( RUNS + 1 ))
        if [ "$RC" != 0 ] || [ -z "$( sepline )" ]; then no "(i) $n: exit $RC / no document"; BAD=$(( BAD + 1 )); continue; fi
        if overceil; then no "(i) $n: over_ceiling=1"; BAD=$(( BAD + 1 )); continue; fi
        S="$( sepline )"
        if ! body | grep -q 'zorblax frobnicate pipeline call'; then
            no "(i) $n: the in-fence match is NOT printed: $S"; BAD=$(( BAD + 1 )); continue
        fi
        if printf '%s' "$S" | grep -q 'fence_reopened'; then REO=$(( REO + 1 )); fi
    done
    if [ "$BAD" = 0 ]; then ok "(i) $kind: all $RUNS sweep runs print the in-fence match ($REO reopened the fence)"; else no "(i) $kind: $BAD of $RUNS sweep runs lost the match"; fi
    if [ "$REO" -gt 0 ]; then ok "(i) $kind: the sweep reaches fence_reopened ($REO runs)"; else no "(i) $kind: no sweep run reopened the fence — the arm pins nothing"; fi
done

echo; echo "=== (j) a window starting inside a backtick-row pipe table is not a fence ==="
python3 - "$R" <<'PY'
import os, sys
r = sys.argv[1]
os.makedirs( r + "/j" )
rows = "".join( "`opt_%03d` | description of option number %03d in the table\n" % ( i, i ) for i in range( 160 ) )
rows = rows.replace( "`opt_100` | description of option number 100 in the table", "`zorblax_flag` | the zorblax frobnicate pipeline switch" )
plain = "".join( "Plain line %04d says nothing in particular about the setup.\n" % i for i in range( 30 ) )
open( r + "/j/notes.md", "w" ).write( "Option reference.\n" + rows + plain )
PY
run j "zorblax frobnicate pipeline" 700
if checkrun "(j)"; then
    S="$( sepline )"
    if printf '%s' "$S" | grep -q 'best query-term window'; then ok "(j) a window was served"; else no "(j) expected a windowed cut (the arm would pin nothing): $S"; fi
    if body | grep -q 'zorblax_flag'; then ok "(j) the matching table row is printed"; else no "(j) the matching table row is not printed"; fi
    if printf '%s' "$S" | grep -q 'fence_reopened'; then no "(j) a table row was taken for a fence opener (fence_reopened): $S"; else ok "(j) no fence_reopened on a table window"; fi
    if body | grep -q 'opt_000'; then no "(j) the table's first row was copied above the window as an opener"; else ok "(j) no table row is copied above the window"; fi
    if overceil; then no "(j) over_ceiling=1"; else ok "(j) within the ceiling"; fi
fi

echo; echo "=== (k) the window is scored after the repeated opener is charged ==="
python3 - "$R" <<'PY'
import os, sys
r = sys.argv[1]
def line( text ): return ( text + " " * 59 )[ :59 ] + "\n"
pre = [ line( "Preface line %04d about setup" % i ) for i in range( 100 ) ]
for i in ( 10, 45, 80 ): pre[ i ] = line( "Preface quuxify note %04d" % i )   # the common term: df 4 with the one in the fence
for g in range( 8, 24 ):
    code = [ line( "code line %04d of the listing" % i ) for i in range( 90 ) ]
    code[ 20 ] = line( "zorblax marker line" )
    code[ 20 + g ] = line( "quuxify marker line" )
    d = "%s/k%d" % ( r, g ); os.makedirs( d )
    open( d + "/notes.md", "w" ).write( "".join( pre ) + "```some-language-with-a-long-info-string-x\n" + "".join( code ) + "```\n"
                                       + "".join( line( "Later line %04d" % i ) for i in range( 60 ) ) )
PY
BAD=0; REO=0; RUNS=0
for d in "$R"/k[0-9]*; do
    n="${d##*/k}"
    run "k$n" "zorblax quuxify" 700
    RUNS=$(( RUNS + 1 ))
    if [ "$RC" != 0 ] || [ -z "$( sepline )" ]; then no "(k) gap $n: exit $RC / no document"; BAD=$(( BAD + 1 )); continue; fi
    if overceil; then no "(k) gap $n: over_ceiling=1"; BAD=$(( BAD + 1 )); continue; fi
    S="$( sepline )"
    if ! body | grep -q 'zorblax marker line'; then no "(k) gap $n: the rare-term line was shed: $S"; BAD=$(( BAD + 1 )); continue; fi
    printf '%s' "$S" | grep -q 'fence_reopened' && REO=$(( REO + 1 ))
done
if [ "$BAD" = 0 ]; then ok "(k) all $RUNS gap runs print the rare-term line ($REO reopened the fence)"; else no "(k) $BAD of $RUNS gap runs lost the rare-term line"; fi
if [ "$REO" -gt 0 ]; then ok "(k) the sweep reaches fence_reopened ($REO runs)"; else no "(k) no sweep run reopened the fence — the arm pins nothing"; fi

echo; echo "=== (l) an oversized fence opener is repeated bare, never as a copy that takes the window ==="
python3 - "$R" <<'PY'
import os, sys
r = sys.argv[1]
plain = "".join( "Plain line %04d says nothing in particular about the setup.\n" % i for i in range( 300 ) )
code = "".join( "code line %03d of the example listing\n" % i for i in range( 40 ) )
tail = "".join( "code line %03d tail\n" % i for i in range( 40 ) )
for name, opener, closer in ( ( "l1", "```" + "x" * 5000 + "\n", "```\n" ),            # one 5000-byte info word
                              ( "l2", "```python " + "info words " * 10 + "\n", "```\n" ),   # a 100-byte info string
                              ( "l3", "~" * 90 + "\n", "~" * 90 + "\n" ) ):        # a fence run over the cap: not repeated
    os.makedirs( "%s/%s" % ( r, name ) )
    open( "%s/%s/notes.md" % ( r, name ), "w" ).write( plain + opener + code + "zorblax frobnicate pipeline call\n" + tail + closer )
PY
for d in l1 l2 l3; do
    run "$d" "zorblax frobnicate pipeline" 700
    if checkrun "(l) $d"; then
        S="$( sepline )"
        if body | grep -q 'zorblax frobnicate pipeline call'; then ok "(l) $d: the in-fence match is printed"; else no "(l) $d: the in-fence match is NOT printed: $S"; fi
        if overceil; then no "(l) $d: over_ceiling=1"; else ok "(l) $d: within the ceiling"; fi
        EST="$( printf '%s\n' "$OUT" | head -1 | grep -oE 'est_tokens=[0-9]+' | grep -oE '[0-9]+' )"
        if [ -n "$EST" ] && [ "$EST" -le 700 ]; then ok "(l) $d: est_tokens $EST <= 700"; else no "(l) $d: est_tokens '${EST:-<none>}' is over the 700 ceiling"; fi
        L2="$( body | sed -n 2p )"
        if printf '%s' "$S" | grep -q 'fence_reopened'; then
            if [ "${#L2}" -le 64 ] && [ "${L2#\`\`\`}" != "$L2" -o "${L2#\~\~\~}" != "$L2" ]; then ok "(l) $d: the repeated opener is bare (${#L2} bytes)"; else no "(l) $d: line 2 is not a bare opener: '$( printf '%s' "$L2" | cut -c1-80 )'"; fi
        fi
        N="$( body | grep -cE '^(```|~~~)' )"
        if [ $(( N % 2 )) = 0 ]; then ok "(l) $d: fences balance ($N fence lines)"; else no "(l) $d: unbalanced fences ($N)"; fi
    fi
done

echo; echo "=== (m) the window must beat the head as served: a tie keeps the head ==="
python3 - "$R" <<'PY'
import os, sys
r = sys.argv[1]
os.makedirs( r + "/mc" )
mline = "Zorblax frobnicate pipeline is named here.\n"      # a match line, 42 bytes
filler = "ab.\n"                                            # 4-byte lines: the head cut lands within 3 bytes of the allowance
open( r + "/mc/notes.md", "w" ).write( mline + filler * 6000 )
PY
run mc "zorblax frobnicate pipeline" 700
if checkrun "(m) calibration"; then
    K="$( sepline | grep -oE '\[truncated: [0-9]+ of' | grep -oE '[0-9]+' )"
    if [ -n "$K" ] && ! sepline | grep -q 'best query-term window'; then
        ok "(m) calibration: the head cut keeps $K bytes"
        python3 - "$R" "$K" <<'PY'
import os, sys
r, k = sys.argv[1], int( sys.argv[2] )
os.makedirs( r + "/mh" )
mline = "Zorblax frobnicate pipeline is named here.\n"
filler = "ab.\n"
pre = ( k - len( mline ) ) // 4
assert pre * 4 + len( mline ) == k, ( k, len( mline ) )
doc = filler * pre + mline + filler * 5000 + mline + filler * 400
open( r + "/mh/notes.md", "w" ).write( doc )
PY
        run mh "zorblax frobnicate pipeline" 700
        if checkrun "(m)"; then
            S="$( sepline )"
            if printf '%s' "$S" | grep -qE '\[truncated: [0-9]+ of [0-9]+ bytes\]$'; then ok "(m) the head is kept on a tie: $( printf '%s' "$S" | grep -oE '\[truncated[^]]*\]' )"; else no "(m) a later window replaced a head that holds the same match: $S"; fi
            if body | grep -q 'Zorblax frobnicate pipeline is named here'; then ok "(m) the head's match line is printed"; else no "(m) the head's match line is not printed"; fi
        fi
    else
        no "(m) calibration run did not give a plain head cut: $( sepline )"
    fi
fi

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
