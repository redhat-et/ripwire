#!/usr/bin/env bash
# dmmcheck.sh — the hand-derived golden gate for `--dmm` (the Delta Maintainability Model scalar).
#
# WHY A HAND-CONSTRUCTED REPO AND NOT THIS REPO'S OWN HISTORY. DMM is a ratio of two integer sums, and a
# ratio looks plausible whether or not it is correct (CLAUDE.md non-negotiable #1). So every arm below is a
# commit built ON PURPOSE so that the answer is derivable with a pencil, and the derivation is written out
# here. A re-implementation of the model inside this gate would reproduce the C++ model's bugs verbatim and
# pass on both.
#
# THE MODEL, as implemented (di Biase/Rastogi/Bruntink/van Deursen, TechDebt 2019; the arithmetic and the
# thresholds are PyDriller's deltamaintainability reference implementation, pydriller/domain/commit.py):
#
#   A UNIT is an indexed function/method DEFINITION WITH A BODY. Its VOLUME is its line span (loc).
#   Per property, a unit is LOW risk iff   size: loc <= 15   complexity: cx <= 5   interfacing: params <= 2
#   A side's RISK PROFILE is the pair (sum of volume over low units, sum of volume over high units).
#   delta_low  = low_target  - low_base       delta_high = high_target - high_base
#   good = max(delta_low, 0) + max(-delta_high, 0)     <- added low-risk code, or removed high-risk code
#   bad  = max(-delta_low, 0) + max( delta_high, 0)    <- removed low-risk code, or added high-risk code
#   DMM  = good / (good + bad),  and UNAVAILABLE (never 0.0, never 1.0) when good + bad == 0.
#   The COMBINED score is ripwire's own pooling: (sum of good over the three) / (sum of good + sum of bad).
#
# THE FIXTURE'S MEASURED FACTS (re-measured with `--metrics` on this exact source, not assumed):
#
#   tiny   ( int a )                       loc  4  cx 1  params 1   -> LOW  / LOW  / LOW
#   god    ( int a, int b, int c, int d )  loc 29  cx 7  params 4   -> HIGH / HIGH / HIGH
#   edge15 ( int a )                       loc 15  cx 1  params 1   -> LOW  / LOW  / LOW   (size boundary, inclusive)
#   edge16 ( int a )                       loc 16  cx 1  params 1   -> HIGH / LOW  / LOW   (size boundary, first high)
#   cx5    ( int a )                       loc  9  cx 5  params 1   -> LOW  / LOW  / LOW   (cx boundary, inclusive)
#   cx6    ( int a )                       loc 10  cx 6  params 1   -> LOW  / HIGH / LOW   (cx boundary, first high)
#   p2     ( int a, int b )                loc  4  cx 1  params 2   -> LOW  / LOW  / LOW   (param boundary, inclusive)
#   p3     ( int a, int b, int c )         loc  4  cx 1  params 3   -> LOW  / LOW  / HIGH  (param boundary, first high)
#
# Arms — each names the commit it scores and the pencil derivation of its expected numbers:
#   (A) DELETE-ONLY-HIGH-RISK   c3: `god` (volume 37, high on all three) removed, nothing else moves.
#                               delta_low 0, delta_high -37 -> good 37, bad 0 -> 1.000 on all three.
#   (B) ADD-ONLY-TO-A-GOD-UNIT  c1: 4 lines appended inside `god` (29 -> 33, still high on all three).
#                               delta_low 0, delta_high +4 -> good 0, bad 4 -> 0.000 on all three.
#   (C) MIXED                   c2: `tiny2` added (volume 4, low on all three) AND `god` grown by 4 (33 -> 37).
#                               delta_low +4, delta_high +4 -> good 4, bad 4 -> 0.500 on all three;
#                               combined pools to 12 / (12 + 12) = 0.500.
#   (D) NO RISK-PROFILE CHANGE  c4: one literal edited inside `tiny` (`a + 1` -> `a + 2`). No unit's loc, cx
#                               or params moves -> good + bad == 0 -> UNAVAILABLE, which is the whole point:
#                               a commit that moved nothing is NOT a perfect commit and NOT a terrible one.
#   (E) THE THREE THRESHOLDS    c5..c10 add one unit each and pin both sides of every boundary:
#                               +edge15 -> 1.000/1.000/1.000, combined 1.000     (15 is LOW)
#                               +edge16 -> 0.000/1.000/1.000, combined (0+16+16)/48   = 0.667  (16 is HIGH)
#                               +cx5    -> 1.000/1.000/1.000, combined 1.000     (5 is LOW)
#                               +cx6    -> 1.000/0.000/1.000, combined (10+0+10)/30   = 0.667  (6 is HIGH)
#                               +p2     -> 1.000/1.000/1.000, combined 1.000     (2 is LOW)
#                               +p3     -> 1.000/1.000/0.000, combined (4+4+0)/12     = 0.667  (3 is HIGH)
#   (F) PER-PROPERTY UNAVAILABLE  c11: `tiny( int a )` becomes `tiny( int a, int b, int c )` on the SAME line,
#                               body untouched. loc and cx do not move -> size and complexity are each
#                               UNAVAILABLE, while the unit crosses the interfacing threshold:
#                               delta_low -4, delta_high +4 -> good 0, bad 8 -> interfacing 0.000, combined 0.000.
#   (G) SINGLE-REV FORM         `--dmm=REV` must equal `--dmm=REV~1..REV` (the per-commit scalar).
#   (H) WORKING-TREE DEFAULT    with no value, the target is the UNCOMMITTED tree: an uncommitted low-risk
#                               function must score 1.000 without any commit being made.
#   (I) ROOT COMMIT             `--dmm=<the first commit>` has no parent to diff against -> UNAVAILABLE with a
#                               stated reason and exit 0, never a fabricated 1.000 and never a crash.
#   (J) NON-GIT ROOT            a plain directory -> available="0" with a reason, exit 0.
#   (K) REFUSALS                an unresolvable rev and an empty value are exit-1 refusals that NAME the flag.
#   (L) DETERMINISM             two runs of the same invocation are byte-identical.
#   (M) WELL-FORMED             the report parses as XML (G4).
#   (N) LEGEND HONESTY          every attribute name the report emits is defined in the legend.
#   (O) ADDITIVE                `--dmm` changes nothing about the flagless map (G5).
#
# Usage:  bash test/dmmcheck.sh      [RIPWIRE_BIN=path/to/binary]
# Exit:   0 = clean · 1 = at least one arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FX="$TMP/repo"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "dmmcheck: git missing (gate cannot run)"; exit 2; }
echo "dmmcheck: BIN=$BIN"

mkdir -p "$FX"
git -C "$FX" init -q
git -C "$FX" config user.email "gate@example.invalid"
git -C "$FX" config user.name  "dmm gate"
git -C "$FX" config commit.gpgsign false

commit(){ git -C "$FX" add -A >/dev/null 2>&1; git -C "$FX" commit -q -m "$1" >/dev/null 2>&1; git -C "$FX" rev-parse HEAD; }

# ── the fixture source, built commit by commit ────────────────────────────────────────────────────────────
# c0 — the base tree: one low-risk unit and one god unit.
{
  printf 'int tiny( int a )\n{\n    return a + 1;\n}\n\n'
  printf 'int god( int a, int b, int c, int d )\n{\n    int r = 0;\n'
  for i in 1 2 3 4 5 6; do printf '    if( a > %d )\n    {\n        r += %d;\n    }\n' "$i" "$i"; done
  printf '    return r;\n}\n'
} > "$FX/a.c"
C0="$( commit c0 )"

# c1 — four plain statement lines appended inside `god` (29 -> 33 lines; cx and params untouched).
grow_god(){
    python3 - "$FX/a.c" "$1" <<'PY'
import sys
path, tag = sys.argv[1], sys.argv[2]
src = open( path ).read().rstrip( "\n" ).split( "\n" )
assert src[-1] == "}", src[-1]
assert src[-2].strip() == "return r;", src[-2]
extra = [ "    r += %s%d;" % ( tag, k ) for k in range( 1, 5 ) ]
open( path, "w" ).write( "\n".join( src[:-2] + extra + src[-2:] ) + "\n" )
PY
}
grow_god 10
C1="$( commit c1 )"

# c2 — the mixed commit: a new low-risk unit AND another four lines inside `god` (33 -> 37).
grow_god 20
printf '\nint tiny2( int a )\n{\n    return a + 3;\n}\n' >> "$FX/a.c"
C2="$( commit c2 )"

# c3 — `god` deleted outright (volume 37, high on all three).
python3 - "$FX/a.c" <<'PY'
import re, sys
path = sys.argv[1]
src  = open( path ).read()
start = src.index( "int god(" )
end   = src.index( "int tiny2(" )
open( path, "w" ).write( src[:start] + src[end:] )
PY
C3="$( commit c3 )"

# c4 — a literal-only edit: no unit's loc, cx or params moves.
python3 - "$FX/a.c" <<'PY'
import sys
path = sys.argv[1]
src  = open( path ).read()
open( path, "w" ).write( src.replace( "return a + 1;", "return a + 2;", 1 ) )
PY
C4="$( commit c4 )"

# c5..c10 — one boundary unit per commit.
add_edge15(){ { printf '\nint edge15( int a )\n{\n    int r = a;\n'; for k in 1 2 3 4 5 6 7 8 9 10; do printf '    r += %d;\n' "$k"; done; printf '    return r;\n}\n'; } >> "$FX/a.c"; }
add_edge16(){ { printf '\nint edge16( int a )\n{\n    int r = a;\n'; for k in 1 2 3 4 5 6 7 8 9 10 11; do printf '    r += %d;\n' "$k"; done; printf '    return r;\n}\n'; } >> "$FX/a.c"; }
add_cx(){ { printf '\nint cx%s( int a )\n{\n    int r = a;\n' "$1"; shift; for k in "$@"; do printf '    if( a > %d ) { r += %d; }\n' "$k" "$k"; done; printf '    return r;\n}\n'; } >> "$FX/a.c"; }

add_edge15; C5="$( commit c5 )"
add_edge16; C6="$( commit c6 )"
add_cx 5 1 2 3 4;    C7="$( commit c7 )"
add_cx 6 1 2 3 4 5;  C8="$( commit c8 )"
printf '\nint p2( int a, int b )\n{\n    return a + b;\n}\n'        >> "$FX/a.c"; C9="$(  commit c9  )"
printf '\nint p3( int a, int b, int c )\n{\n    return a + b + c;\n}\n' >> "$FX/a.c"; C10="$( commit c10 )"

# c11 — `tiny` gains two parameters on the SAME line; loc and cx do not move.
python3 - "$FX/a.c" <<'PY'
import sys
path = sys.argv[1]
src  = open( path ).read()
open( path, "w" ).write( src.replace( "int tiny( int a )", "int tiny( int a, int b, int c )", 1 ) )
PY
C11="$( commit c11 )"

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────
# The root element only — the <p> children carry their own dmm=, so an unanchored grep would find theirs.
rootOf(){ printf '%s' "$1" | sed 's/<p k=.*//'; }
# The <p k="NAME" .../> child, isolated.
propOf(){ printf '%s' "$1" | tr '<' '\n' | grep "^p k=\"$2\"" | head -1; }
attr(){ printf '%s' "$2" | grep -o " $1=\"[^\"]*\"" | head -1 | sed 's/^.*="//; s/"$//'; }

# expect NAME EXPECTED_COMBINED EXPECTED_SIZE EXPECTED_CX EXPECTED_IFACE  -- runs `--dmm=RANGE` and checks all four.
expect(){
    local label="$1" range="$2" ec="$3" es="$4" ex="$5" ei="$6"
    local out ac as ax ai
    out="$( "$BIN" "$FX" "--dmm=$range" 2>"$TMP/err" )"
    if [ -z "$out" ]; then no "$label: --dmm=$range produced no output ($( head -1 "$TMP/err" ))"; return; fi
    ac="$( attr dmm "$( rootOf "$out" )" )"
    as="$( attr dmm "$( propOf "$out" size )" )"
    ax="$( attr dmm "$( propOf "$out" complexity )" )"
    ai="$( attr dmm "$( propOf "$out" interfacing )" )"
    if [ "$ac" = "$ec" ] && [ "$as" = "$es" ] && [ "$ax" = "$ex" ] && [ "$ai" = "$ei" ]
    then ok "$label: combined=$ac size=$as complexity=$ax interfacing=$ai"
    else no "$label: expected combined=$ec size=$es complexity=$ex interfacing=$ei — got combined=$ac size=$as complexity=$ax interfacing=$ai"
    fi
}

# ── (A) delete-only-high-risk ─────────────────────────────────────────────────────────────────────────────
expect "(A) delete-only-high-risk (c3)" "$C2..$C3" 1.000 1.000 1.000 1.000

# ── (B) add-only-to-a-god-unit ────────────────────────────────────────────────────────────────────────────
expect "(B) add-only-to-a-god-unit (c1)" "$C0..$C1" 0.000 0.000 0.000 0.000

# ── (C) mixed ─────────────────────────────────────────────────────────────────────────────────────────────
expect "(C) mixed, 4 good lines vs 4 bad (c2)" "$C1..$C2" 0.500 0.500 0.500 0.500

# ── (D) no risk-profile change at all ─────────────────────────────────────────────────────────────────────
expect "(D) literal-only edit is UNAVAILABLE, not 1.000 (c4)" "$C3..$C4" UNAVAILABLE UNAVAILABLE UNAVAILABLE UNAVAILABLE

# ── (E) the three thresholds, both sides ──────────────────────────────────────────────────────────────────
expect "(E) size 15 is LOW (c5)"          "$C4..$C5"  1.000 1.000 1.000 1.000
expect "(E) size 16 is HIGH (c6)"         "$C5..$C6"  0.667 0.000 1.000 1.000
expect "(E) complexity 5 is LOW (c7)"     "$C6..$C7"  1.000 1.000 1.000 1.000
expect "(E) complexity 6 is HIGH (c8)"    "$C7..$C8"  0.667 1.000 0.000 1.000
expect "(E) interfacing 2 is LOW (c9)"    "$C8..$C9"  1.000 1.000 1.000 1.000
expect "(E) interfacing 3 is HIGH (c10)"  "$C9..$C10" 0.667 1.000 1.000 0.000

# ── (F) a per-property UNAVAILABLE alongside a measured one ───────────────────────────────────────────────
expect "(F) params-only change (c11)" "$C10..$C11" 0.000 UNAVAILABLE UNAVAILABLE 0.000

# the integers behind (F) must be visible, not just the ratio
f_out="$( "$BIN" "$FX" "--dmm=$C10..$C11" 2>/dev/null )"
f_if="$( propOf "$f_out" interfacing )"
if [ "$( attr d_low "$f_if" )" = "-4" ] && [ "$( attr d_high "$f_if" )" = "4" ] \
   && [ "$( attr good "$f_if" )" = "0" ] && [ "$( attr bad "$f_if" )" = "8" ]
then ok "(F) interfacing deltas are auditable: d_low=-4 d_high=4 good=0 bad=8"
else no "(F) interfacing deltas wrong: $f_if"
fi

# ── (G) the single-rev form is REV~1..REV ─────────────────────────────────────────────────────────────────
g_one="$( "$BIN" "$FX" "--dmm=$C6" 2>/dev/null )"
g_two="$( "$BIN" "$FX" "--dmm=$C5..$C6" 2>/dev/null )"
if [ -n "$g_one" ] && [ "$g_one" = "$g_two" ]
then ok "(G) --dmm=REV is byte-identical to --dmm=REV~1..REV"
else no "(G) --dmm=REV disagreed with --dmm=REV~1..REV"
fi

# ── (I) the root commit has no parent ─────────────────────────────────────────────────────────────────────
i_out="$( "$BIN" "$FX" "--dmm=$C0" 2>/dev/null )"; i_rc=$?
i_root="$( rootOf "$i_out" )"
if [ $i_rc -eq 0 ] && [ "$( attr available "$i_root" )" = "0" ] && [ "$( attr dmm "$i_root" )" = "UNAVAILABLE" ] \
   && [ -n "$( attr reason "$i_root" )" ]
then ok "(I) root commit: available=0 dmm=UNAVAILABLE with a reason, exit 0"
else no "(I) root commit mishandled (rc=$i_rc): $i_root"
fi

# ── (H) the working-tree default ──────────────────────────────────────────────────────────────────────────
printf '\nint tiny3( int a )\n{\n    return a + 9;\n}\n' >> "$FX/a.c"
h_out="$( "$BIN" "$FX" --dmm 2>/dev/null )"; h_rc=$?
h_root="$( rootOf "$h_out" )"
if [ $h_rc -eq 0 ] && [ "$( attr dmm "$h_root" )" = "1.000" ] && [ "$( attr target "$h_root" )" = "working-tree" ]
then ok "(H) working-tree default scores the uncommitted tree against HEAD: 1.000"
else no "(H) working-tree default wrong (rc=$h_rc): $h_root"
fi
git -C "$FX" checkout -q -- a.c

# ── (L) determinism ───────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FX" "--dmm=$C1..$C2" >"$TMP/d1" 2>/dev/null
"$BIN" "$FX" "--dmm=$C1..$C2" >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/d1" "$TMP/d2"; then ok "(L) two runs are byte-identical"; else no "(L) output is not deterministic"; fi

# ── (M) well-formedness ───────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/d1" 2>/dev/null; then ok "(M) report is well-formed XML"; else no "(M) report does not parse as XML"; fi
    if [ "$( tr -d '\n' < "$TMP/d1" | wc -c )" -eq "$( wc -c < "$TMP/d1" )" ]; then
        ok "(M) no newline outside CDATA (G4)"
    else
        no "(M) the report contains a newline (G4 minification)"
    fi
else
    ok "(M) xmllint absent — well-formedness arm skipped (not a silent pass: the suite's xmlwellformed gate also covers it)"
fi

# ── (N) legend honesty — every emitted attribute name is defined in the legend ─────────────────────────────
legend="$( sed 's/-->.*//' "$TMP/d1" )"
body="$(   sed 's/^.*-->//' "$TMP/d1" )"
missing=""
for a in $( printf '%s' "$body" | grep -o '[a-z_]*="' | sed 's/="$//' | sort -u ); do
    printf '%s' "$legend" | grep -q "$a=" || missing="$missing $a"
done
if [ -z "$missing" ]; then ok "(N) every emitted attribute is defined in the legend"
else no "(N) attributes emitted but undefined in the legend:$missing"; fi

# ── (J) a non-git root degrades, it does not crash or lie ─────────────────────────────────────────────────
mkdir -p "$TMP/plain"
cp "$FX/a.c" "$TMP/plain/a.c"
j_out="$( "$BIN" "$TMP/plain" --dmm 2>/dev/null )"; j_rc=$?
j_root="$( rootOf "$j_out" )"
if [ $j_rc -eq 0 ] && [ "$( attr available "$j_root" )" = "0" ] && [ -n "$( attr reason "$j_root" )" ]
then ok "(J) non-git root: available=0 with a reason, exit 0"
else no "(J) non-git root mishandled (rc=$j_rc): $j_root"
fi

# ── (K) refusals name the flag ────────────────────────────────────────────────────────────────────────────
k1="$( "$BIN" "$FX" --dmm=nosuchrev 2>&1 >/dev/null )"; k1rc=$?
if [ $k1rc -ne 0 ] && printf '%s' "$k1" | grep -q -- "-dmm"; then ok "(K) an unresolvable rev is refused, and the message names the flag"
else no "(K) --dmm=nosuchrev should refuse (rc=$k1rc): $k1"; fi

k2="$( "$BIN" "$FX" --dmm= 2>&1 >/dev/null )"; k2rc=$?
if [ $k2rc -ne 0 ] && printf '%s' "$k2" | grep -q -- "-dmm"; then ok "(K) an empty value is refused, and the message names the flag"
else no "(K) --dmm= should refuse (rc=$k2rc): $k2"; fi

# ── (O) additivity — the flagless map is untouched ────────────────────────────────────────────────────────
"$BIN" "$FX" --no-cache >"$TMP/plain1" 2>/dev/null
"$BIN" "$FX" --dmm      >/dev/null 2>&1
"$BIN" "$FX" --no-cache >"$TMP/plain2" 2>/dev/null
if cmp -s "$TMP/plain1" "$TMP/plain2"; then ok "(O) --dmm leaves the flagless map byte-identical (G5)"
else no "(O) --dmm changed the flagless map"; fi

if [ "$fail" -ne 0 ]; then printf 'dmmcheck: FAILURES ABOVE\n'; exit 1; fi
printf 'dmmcheck: all arms green\n'
exit 0
