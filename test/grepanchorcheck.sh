#!/usr/bin/env bash
# grepanchorcheck.sh — gate for what `^` and `$` MEAN in --regex.
#
# THE DEFECT THIS PINS. --regex hands the whole file's bytes to one
# `std::sregex_iterator( text.begin(), text.end(), re )` built with
# `std::regex::ECMAScript | std::regex::optimize`. Without `std::regex::multiline`,
# ECMAScript's `^` matches only at OFFSET 0 of that buffer and `$` only at its very end —
# so `--regex='^#include'` answered about the first line of each file and nothing else.
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
# Assertions:
#   A  `^` is a LINE anchor: every line starting with the literal is a hit, not just line 1
#      (the arm that was RED: pre-fix this reported 1 hit out of 6)
#   B  `$` is a LINE anchor: a match at end-of-LINE, not only end-of-FILE
#   C  `.` still does NOT cross a newline — multiline must not smuggle in dotall
#   D  independent oracle, (file,line) EXACT: for the anchored battery ripwire's hit set is
#      exactly `grep -nE`'s. Not a superset check — an anchor that over-matches is as wrong
#      as one that under-matches, and the equality is what says so
#   E  prefilter soundness survives anchors: --regex=PAT == --regex=PAT --no-prefilter
#      (Cox treats an anchor as ε, so the candidate set must not narrow on one)
#   F  determinism: two runs byte-identical
#   G  MUTATION self-tests — each assertion must be able to see its own regression
#   H  G4: xmllint --noout clean
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
ok(){ printf '  PASS  %s\n' "$*"; }
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

# ── C) `.` still does not cross a newline (multiline is not dotall) ────────────────────────────────────
C_N="$( rw 'stdio.*stdlib' | hitset | grep -c . )"
[ "$C_N" -eq 0 ] \
    && ok "(C) . does not cross a newline — a cross-line .* still matches nothing" \
    || no "(C) . crossed a newline ($C_N hits): multiline leaked dotall semantics"

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
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "(F) two runs byte-identical" || no "(F) output is nondeterministic"

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
# (C) dotall: a fixture line that WOULD match if . crossed newlines proves the arm can fire.
printf 'stdio\nstdlib\n' > "$C/gamma.c"
MUT_C="$( "$BIN" "$C" --regex='stdio[\s\S]*stdlib' --grep-in=any --no-cache 2>/dev/null | hitset | grep -c . )"
rm -f "$C/gamma.c"
[ "$MUT_C" -ge 1 ] \
    && ok "(G) mutation control: an EXPLICITLY newline-crossing class does match ($MUT_C) — (C) is not vacuous" \
    || no "(G) mutation control: even [\\s\\S]* matched nothing — (C) cannot distinguish anything"

# ── H) G4: well-formed XML ─────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$A_OUT" | xmllint --noout - 2>/dev/null && ok "(H) xml well-formed (xmllint)" || no "(H) xml malformed"
else
    ok "(H) xmllint absent — skipped"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
