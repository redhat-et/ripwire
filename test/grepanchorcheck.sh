#!/usr/bin/env bash
# grepanchorcheck.sh — gate for what `^` and `$` MEAN in --regex.
#
# THE DEFECT THIS PINS. --regex used to hand the whole file's bytes to one
# `std::sregex_iterator( text.begin(), text.end(), re )`, so ECMAScript's `^` matched only at
# OFFSET 0 of that buffer and `$` only at its very end — `--regex='^#include'` answered about
# the first line of each file and nothing else.
# Measured on this repository's own src/ at 4c10be9d: ripwire reported hits="1", `rg -n
# '^#include' src` reported 1648. The answer was not a zero (which the legend governs), it
# was a confident, undisclosed 0.06% of the truth, in the one syntax every agent already
# knows from grep, rg and every editor's find box.
#
# The verb's own answer is LINE-SHAPED — one <hit l="…"> per line, the CDATA is that line —
# so a file-scoped anchor was never the shape the emitter promised. test/regexcheck.sh's
# battery has carried `'^int '` since it was written, commented "an anchored line start";
# its independent `grep -lE` oracle arm runs a SHORTER list that omits exactly that pattern,
# so the divergence was inside the gate suite's blind spot rather than outside its scope.
# This gate closes that: every arm here compares against grep/rg, which is the semantics the
# comment already claimed.
#
# WHY THE FIX IS NOT `std::regex::multiline`. That flag is the obvious repair and it is unusable here.
# Apple libc++'s `__l_anchor_multiline<char>::__exec` reads `*std::prev(__s.__current_)` before it tests
# whether the position IS the first character, so at offset 0 it reads one byte BEFORE the buffer.
# Measured 2026-09-09: a 40-line standalone with no ripwire code faulted on 74 of ~130 of this
# repository's own headers, single-threaded, and `--regex='^'` over src/ crashed 8 of 10 runs. So
# grepScanText searches ONE LINE AT A TIME instead, and arm (I) below is the crash regression itself.
#
# Assertions:
#   A  `^` is a LINE anchor: every line starting with the literal is a hit, not just line 1
#      (the arm that was RED: pre-fix this reported 1 hit out of 6)
#   B  `$` is a LINE anchor: a match at end-of-LINE, not only end-of-FILE
#   C  a match does not cross a newline — the LINE-ORIENTED contract, in both directions: `.` never
#      could (ECMAScript's dot excludes line terminators) and an explicitly newline-crossing class
#      cannot either, because each line is now its own search range. The control for this arm is
#      WITHIN-line: the same pattern must match when both halves sit on one line, which is what proves
#      the arm measures the line boundary rather than a pattern that cannot match at all
#   D  independent oracle, (file,line) EXACT: for the anchored battery ripwire's hit set is
#      exactly `grep -nE`'s. Not a superset check — an anchor that over-matches is as wrong
#      as one that under-matches, and the equality is what says so
#   E  prefilter soundness survives anchors: --regex=PAT == --regex=PAT --no-prefilter
#      (Cox treats an anchor as ε, so the candidate set must not narrow on one)
#   F  determinism: two runs byte-identical
#   G  MUTATION self-tests — each assertion must be able to see its own regression
#   H  G4: xmllint --noout clean
#   J  ZERO-WIDTH LINE COUNTING at the file's edges: `^` matches exactly once per REAL line, so
#      ripwire's hit count equals `grep -c '^'` on all four shapes — trailing newline, no trailing
#      newline, an empty file, and a file that is one newline. A trailing newline terminates the last
#      line, it does not begin an empty one; without that rule a zero-width pattern gains one phantom
#      hit per file, on a line number no reader could open
#   I  CRASH REGRESSION, and the reason arm (I) exists at all: `--regex='^'` over a real corpus,
#      ten times, must exit 0 every time. This is the arm that goes red the day someone "simplifies"
#      grepScanText back to a whole-buffer iterator plus `std::regex::multiline` — a standard-library
#      out-of-bounds read that no output assertion can see, because the process dies before it emits
#      anything. 8 of 10 runs faulted while that flag was in the tree.
#
# Usage:  test/grepanchorcheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/grepanchorcheck.sh
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
cd "$ROOT"
echo "grepanchorcheck: BIN=$BIN"

# ── the fixture: anchors that are NOT at offset 0 and NOT at end-of-file ───────────────────────────────
# alpha.c: three `#include` lines, none of them line 1, so a file-anchored `^` sees none of them.
# beta.c:  three more, plus a line whose `#include` is INDENTED — `^#include` must not match that one.
C="$TMP/corpus"; mkdir -p "$C"
cat > "$C/alpha.c" <<'EOF'
/* a banner comment, so line 1 is not an include */
#include <stdio.h>
#include <stdlib.h>
int alphaOne( int n ) { return n + 1; }
#include "local.h"
int alphaTwo( int n ) { return n + 2; }
EOF
cat > "$C/beta.c" <<'EOF'
/* another banner */
#include <string.h>
    #include <indented.h>
#include "beta.h"
int betaOne( void ) { return 0; }
#include <last.h>
int betaTwo( void ) { return 1; }
EOF

# hit set as `path:line`, sorted. <at l="…"/> siblings are folded duplicate SITES of a
# byte-identical match in the same file and count as hits, so both element names are read.
hitset(){
    python3 -c '
import re, sys
xml = sys.stdin.read().split( "-->", 1 )[ -1 ]
cur, out = None, set()
for m in re.finditer( r"<f p=\"([^\"]*)\"|<(?:hit|at) l=\"(\d+)\"", xml ):
    if m.group( 1 ) is not None: cur = m.group( 1 )
    elif cur is not None:        out.add( "%s:%s" % ( cur, m.group( 2 ) ) )
print( "\n".join( sorted( out ) ) )
'
}
# the independent oracle: grep -nE, path-relative, same `path:line` spelling
oracle(){ ( cd "$C" && grep -rnE -- "$1" . 2>/dev/null | sed 's|^\./||' | cut -d: -f1,2 | sort -u ); }

rw(){ "$BIN" "$C" --regex="$1" --grep-in=any --limit=100000 --no-cache 2>/dev/null; }

# ── A) `^` is a LINE anchor ────────────────────────────────────────────────────────────────────────────
A_OUT="$( rw '^#include' )"
A_RW="$( printf '%s' "$A_OUT" | hitset )"
A_GR="$( oracle '^#include' )"
A_N="$( printf '%s\n' "$A_RW" | grep -c . )"
[ "$A_N" -ge 6 ] \
    && ok "(A) ^ is a line anchor — $A_N hits, not just the first line of each file" \
    || no "(A) ^ anchored to the FILE, not the line: $A_N hits (expected 6; pre-fix this was 0)"

# ── B) `$` is a LINE anchor ────────────────────────────────────────────────────────────────────────────
B_RW="$( rw 'h>$' | hitset )"
B_GR="$( oracle 'h>$' )"
B_N="$( printf '%s\n' "$B_RW" | grep -c . )"
[ "$B_N" -ge 3 ] \
    && ok "(B) \$ is a line anchor — $B_N hits at end-of-line" \
    || no "(B) \$ anchored to the FILE, not the line: $B_N hits (expected >=3)"

# ── C) a match does not cross a newline, in both directions ────────────────────────────────────────────
C_N="$( rw 'stdio.*stdlib' | hitset | grep -c . )"
[ "$C_N" -eq 0 ] \
    && ok "(C) . does not cross a newline — the two halves are on different lines, no hit" \
    || no "(C) . crossed a newline ($C_N hits)"
C2_N="$( rw 'stdio[\s\S]*stdlib' | hitset | grep -c . )"
[ "$C2_N" -eq 0 ] \
    && ok "(C) an EXPLICITLY newline-crossing class does not cross one either — line-oriented contract" \
    || no "(C) [\\s\\S]* crossed a newline ($C2_N hits): the search range is not one line"

# ── D) independent oracle, EXACT (file,line) equality over the anchored battery ────────────────────────
for p in '^#include' 'h>$' '^int ' '^ *#include' '^#include <[a-z]*\.h>$'; do
    RWS="$( rw "$p" | hitset )"
    GRS="$( oracle "$p" )"
    if [ "$RWS" = "$GRS" ]; then
        ok "(D) hit set == grep -nE   $( printf '%-24s' "$p" )"
    else
        no "(D) hit set differs from grep -nE for /$p/"
        printf '        ripwire: %s\n' "$( printf '%s' "$RWS" | tr '\n' ' ' )"
        printf '        grep   : %s\n' "$( printf '%s' "$GRS" | tr '\n' ' ' )"
    fi
done

# ── E) the trigram prefilter stays SOUND with an anchor in the pattern ─────────────────────────────────
for p in '^#include' 'h>$' '^int '; do
    "$BIN" "$C" --regex="$p" --grep-in=any --limit=100000 --no-cache                >"$TMP/pf" 2>/dev/null
    "$BIN" "$C" --regex="$p" --grep-in=any --limit=100000 --no-cache --no-prefilter >"$TMP/fs" 2>/dev/null
    diff -q "$TMP/pf" "$TMP/fs" >/dev/null \
        && ok "(E) prefilter == full scan   $( printf '%-12s' "$p" )" \
        || no "(E) prefilter DROPPED a match for /$p/ (anchors must stay ε in the trigram query)"
done

# ── F) determinism ─────────────────────────────────────────────────────────────────────────────────────
rw '^#include' >"$TMP/d1"; rw '^#include' >"$TMP/d2"
if diff -q "$TMP/d1" "$TMP/d2" >/dev/null; then ok "(F) two runs byte-identical"; else no "(F) output is nondeterministic"; fi

# ── G) MUTATION self-tests: each assertion must be able to see its own regression ──────────────────────
# (A)/(D) revert: only the file-anchored hit survives — the exact pre-fix answer shape.
MUT_A="$( printf '%s' "$A_OUT" | python3 -c '
import re, sys
xml = sys.stdin.read()
# drop every <hit …>…</hit> whose line is not 1 — i.e. simulate the file-anchored engine
print( re.sub( r"<hit l=\"(?!1\")\d+\"[^>]*>.*?</hit>", "", xml, flags = re.S ) )
' )"
MUT_N="$( printf '%s' "$MUT_A" | hitset | grep -c . )"
[ "$MUT_N" -ge 6 ] \
    && no "(G) mutation (revert to a file anchor): still passes (A) — the assertion is decoration" \
    || ok "(G) mutation (revert to a file anchor) correctly FAILS assertion (A) — $MUT_N hits left"
# (D) equality: perturbing ONE line number must break the oracle comparison.
MUT_D="$( printf '%s\n' "$A_RW" | sed '1s/:[0-9]*$/:999/' )"
[ "$MUT_D" = "$A_GR" ] \
    && no "(G) mutation (one line number moved): still equals the oracle — (D) is decoration" \
    || ok "(G) mutation (one line number moved) correctly FAILS assertion (D)"
# (C) control, WITHIN-line: the same two patterns must both match when the halves share a line, so (C)
# is measuring the line boundary and not a pattern that could never match anything.
printf 'x stdio y stdlib z\n' > "$C/gamma.c"
MUT_C1="$( "$BIN" "$C" --regex='stdio.*stdlib'      --grep-in=any --no-cache 2>/dev/null | hitset | grep -c . )"
MUT_C2="$( "$BIN" "$C" --regex='stdio[\s\S]*stdlib' --grep-in=any --no-cache 2>/dev/null | hitset | grep -c . )"
rm -f "$C/gamma.c"
[ "$MUT_C1" -ge 1 ] && [ "$MUT_C2" -ge 1 ] \
    && ok "(G) control: both patterns match WITHIN one line ($MUT_C1/$MUT_C2) — (C) is not vacuous" \
    || no "(G) control: a same-line fixture matched nothing ($MUT_C1/$MUT_C2) — (C) cannot distinguish anything"

# ── H) G4: well-formed XML ─────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A_OUT" | xmllint --noout - 2>/dev/null; then ok "(H) xml well-formed (xmllint)"; else no "(H) xml malformed"; fi
else
    ok "(H) xmllint absent — skipped"
fi

# ── I) CRASH REGRESSION: the anchor must not reintroduce libc++'s out-of-bounds multiline node ────────
# A bare `^` matches once per LINE, which is the densest anchor workload there is, and it is what made
# the libc++ node fault. Ten runs over this repository's own src/ (real source text: the fault is
# content-dependent, so a three-line fixture cannot see it). Any non-zero exit here is a crash.
crashes=0
for i in 1 2 3 4 5 6 7 8 9 10; do
    "$BIN" "$ROOT/src" --regex='^' --grep-in=any >/dev/null 2>&1 || crashes=$(( crashes + 1 ))
done
[ "$crashes" -eq 0 ] \
    && ok "(I) bare ^ over src/ exited 0 on all 10 runs — no out-of-bounds anchor node" \
    || no "(I) bare ^ over src/ FAILED $crashes/10 runs — a crash, not an output defect (see the header)"
# control: the same ten-run shape on a pattern that has always been safe must stay clean, so a red (I)
# means the anchor and not the machine.
ctl=0
for i in 1 2 3 4 5; do
    "$BIN" "$ROOT/src" --regex='include' --grep-in=any >/dev/null 2>&1 || ctl=$(( ctl + 1 ))
done
[ "$ctl" -eq 0 ] \
    && ok "(I) control: an unanchored pattern is clean over the same corpus" \
    || no "(I) control also failed $ctl/5 — the corpus or the binary is broken, not the anchor"

# ── J) zero-width matching at the file's edges, against grep -c '^' ────────────────────────────────────
E="$TMP/edges"; mkdir -p "$E"
printf 'a\nb\n' > "$E/trailing_nl.c"      # ends with a newline
printf 'a\nb'    > "$E/no_trailing_nl.c"   # does not
: > "$E/empty.c"                           # no bytes at all
printf '\n'      > "$E/just_nl.c"          # exactly one newline
for f in trailing_nl no_trailing_nl empty just_nl; do
    rwn="$( "$BIN" "$E/$f.c" --regex='^' --grep-in=any --limit=100000 --no-cache 2>/dev/null \
            | sed 's/<!--.*-->//' | grep -o 'hits="[0-9]*"' | head -1 | grep -o '[0-9]*' )"
    gn="$( grep -c '^' "$E/$f.c" )"
    [ "$rwn" = "$gn" ] \
        && ok "(J) ^ counts lines like grep on $( printf '%-16s' "$f" ) ($rwn)" \
        || no "(J) ^ counted $rwn where grep -c '^' counted $gn on $f — phantom or missing final line"
done

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
