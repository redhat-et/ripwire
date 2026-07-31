#!/usr/bin/env bash
# depsprecisecheck.sh — P3 gate: the FILE→FILE dependency graph (--deps/--arch/cycles/god-files) is
# PATH-PRECISE, not basename. graph.h::resolveIncludeAdj now resolves each quote `#include "x.h"` LEXICALLY
# relative-to-includer (resolve.h::buildPreciseIncludeAdj, the same sound machinery the call-graph
# SameInclude tier uses) instead of matching by basename. This closes the last silent-wrong-edge surface:
# a cross-directory basename collision could make --deps/--arch show a WRONG file→file edge.
#
# Fixture test/depsprecisefix has the exact collision the basename resolver could not tell apart:
#   dirA/x.h  and  dirB/x.h        BOTH exist, SAME basename `x.h`, DIFFERENT directories
#   consumer.cpp   #include "dirA/x.h"   (quote, by PATH)   → the ONE real dep
#   consumer.cpp   #include <dirB/x.h>   (angle, in-repo)   → external form → NO edge (never basename-matched)
#
# The old basename resolver reduced `dirA/x.h` to basename `x.h` and linked BOTH dirA/x.h and dirB/x.h
# (a phantom edge to the file the source never includes). Precise resolution:
#   - the edge lands on dirA/x.h ONLY  (afferent=1)                         ← path, not basename
#   - dirB/x.h gets NO incoming edge   (never appears as a resolved node)   ← the decoy is dropped
#   - the angle <dirB/x.h> contributes nothing                             ← angle → unresolved, honest
# MONOTONICITY: precise resolution can only REMOVE or REDIRECT a wrong edge, never MANUFACTURE one.
#
# Usage:  test/depsprecisecheck.sh   |   CTXPACK_BIN=asan/ctxpack test/depsprecisecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/depsprecisefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "depsprecisecheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

# --deps: emit the file→file graph, one XML tag per line for grep-able node/edge assertions.
"$BIN" "$FIX" --deps --pack-top-n=1000 --no-cache 2>/dev/null | sed 's/</\n</g' >"$TMP/deps"

# ── the real dep resolves to dirA/x.h (afferent=1) — path, not basename ────────────────────────────
if grep -qE 'p="[^"]*dirA/x\.h"[^>]*afferent="1"' "$TMP/deps"; then
    ok "dirA/x.h has afferent=1 — the quote include \"dirA/x.h\" resolved by PATH to the right file"
else
    no "dirA/x.h afferent!=1 — the real edge was lost or mis-resolved"; grep -E 'dirA/x\.h' "$TMP/deps"
fi

# ── the decoy dirB/x.h gets NO incoming edge — it never appears as a RESOLVED node ─────────────────
# (a node line carries afferent="…"; an `<inc t="dirB/x.h">` DISPLAY line does not — assert on afferent).
if grep -qE 'p="[^"]*dirB/x\.h"[^>]*afferent="[1-9]' "$TMP/deps"; then
    no "dirB/x.h has a phantom incoming edge — basename collision leaked a WRONG file→file edge"
    grep -E 'dirB/x\.h' "$TMP/deps"
else
    ok "dirB/x.h has NO incoming edge — the same-basename decoy was NOT basename-matched (the fix)"
fi

# ── the angle include <dirB/x.h> of an in-repo file contributes NO edge (external form → unresolved) ─
# Proven by the above: consumer.cpp's ONLY quote include is dirA/x.h; the angle <dirB/x.h> is the only
# other route to dirB, and dirB has afferent 0 → the angle include added nothing. Assert it directly too:
# consumer.cpp's transitive cone is exactly 2 (self + dirA/x.h; Lakos counts self). Were the angle
# <dirB/x.h> resolved (basename-matched) it would be 3 — so transitive=2 proves the angle added no edge.
if grep -qE 'p="[^"]*consumer\.cpp"[^>]*transitive="2"' "$TMP/deps"; then
    ok "consumer.cpp cone=2 (self + dirA/x.h only) — angle <dirB/x.h> added NO edge (Lakos counts self)"
else
    no "consumer.cpp transitive cone != 2 — an angle include or decoy leaked an edge"
    grep -E 'consumer\.cpp' "$TMP/deps"
fi

# ── determinism: byte-identical run-to-run + warm == cold ─────────────────────────────────────────
"$BIN" "$FIX" --deps --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --deps --no-cache >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" && ok "deterministic (two --deps --no-cache runs identical)" || no "non-deterministic"
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
cmp -s "$TMP/cold" "$TMP/warm" && ok "warm == cold (precise adjacency order-stable through cache)" || no "warm != cold"

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

# ── §P9.2: <f instab=> and <stabledeps gap=> must be the SAME Martin instability I=Ce/(Ca+Ce), so a ────
# `<stabledeps>` gap must equal (consumer's printed instab − provider's printed instab) within 0.01, from
# the document alone. Pre-fix, <f instab=> counted Ce over EVERY #include statement (system+third-party
# included) while <stabledeps gap=> counted Ce over the project-only resolved graph — two different numbers
# sharing one attribute name. Run against ctxpack's OWN source (self-hosting): it is where the plan's
# worked example lives (src/mcp.h -> src/mcpverbs.h, claimed instab=0.52ish vs recomputed 0.25ish
# pre-fix) — the small depsprecisefix fixture has no stabledeps violations to check.
if command -v python3 >/dev/null 2>&1; then
    "$BIN" "$ROOT" --deps --pack-top-n=1000 --no-cache >"$TMP/deps_self.xml" 2>/dev/null
    if python3 - "$TMP/deps_self.xml" <<'PYEOF'
import re, sys
xml = open( sys.argv[1] ).read()
instab = {}
for m in re.finditer( r'<f p="([^"]*)"[^>]*\binstab="([0-9.]+)"', xml ):
    instab[ m.group(1) ] = float( m.group(2) )
checked, bad = 0, []
for m in re.finditer( r'<v from="([^"]*)" to="([^"]*)"[^>]*\bgap="([0-9.]+)"', xml ):
    frm, to, gap = m.group(1), m.group(2), float( m.group(3) )
    if frm not in instab or to not in instab:
        continue   # outside the --pack-top-n=1000 <f> window — not asserted, not a failure
    checked += 1
    recomputed = instab[to] - instab[frm]
    # tolerance is 0.01 (two independently-rounded %.2f values can compound to that much) + a tiny epsilon
    # so IEEE-754 binary representation of the decimal strings (e.g. 0.33-0.28 == 0.04999999999999999 in
    # float64) never fails a genuinely-reconciling row by 1e-16 of pure floating-point noise.
    if abs( recomputed - gap ) > 0.01 + 1e-9:
        bad.append( ( frm, to, gap, round( recomputed, 4 ) ) )
if checked == 0:
    print( "no <stabledeps> row had both endpoints in the <f> window — nothing checked" )
    sys.exit(1)
if bad:
    print( f"{len(bad)}/{checked} rows do NOT reconcile (from, to, printed_gap, recomputed_from_instab):" )
    for b in bad: print( "  ", b )
    sys.exit(1)
print( f"all {checked} <stabledeps> rows reconcile with printed <f instab=> within 0.01" )
PYEOF
    then ok "P9.2: every <stabledeps gap=> recomputes from printed <f instab=> within 0.01"
    else no "P9.2: <stabledeps gap=> does not reconcile with <f instab=> (two instability numbers under one name)"
    fi
else
    ok "P9.2 skipped (python3 absent)"
fi

# §A10.11: --deps emits three files=-family counts (root files=, <health files=>, <health dep_files=>)
# under one attribute name in two different places — the legend must name all three denominators, the
# same disclosure --owners already carries for its own files= DEPTH collision.
DOUT="$( "$BIN" "$FIX" --deps --no-cache 2>/dev/null )"
printf '%s' "$DOUT" | grep -q 'health dep_files= = the dependency-CAPABLE subset' \
    && ok "--deps legend names all three files=-family denominators (§A10.11)" \
    || no "--deps legend does not disclose the three files=-family denominators"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
