#!/usr/bin/env bash
# R-E (2026-08-17 harvest, root-relative paths for ALL verbs): --deps' cut=/p= is now relative to $FIX
# itself — the fixture directory's own name never appears in a path — so every literal expectation below
# was re-pinned from "$FIX/name" to bare "name".
# cyclecutcheck.sh — WEAKEST-LINK CUT SUGGESTION gate for `--deps` cycle output (packDeps in
# src/serialize.h). Each <cycle> now carries cut="src -> dst" cutrefs="N": the cheapest edge to
# remove to break the cycle, picked by MIN occurrence-count within the cycle's own edges (adj is
# un-deduped — a repeated #include of the same target pushes a duplicate entry, so occurrence
# count is an honest, already-available proxy for "how load-bearing is this dependency"). Ties
# broken lexicographically by (srcPath,dstPath) for determinism.
#
# Fixture: test/cyclecutfix (two independent cycles in one corpus — distinct basenames, so
# resolveIncludeAdj's basename-match keeps them from cross-pollinating):
#   3-cycle: a.h -[x3]-> b.h -[x1]-> c.h -[x1]-> a.h   (a->b is thick=3, b->c and c->a are thin=1;
#            tie broken lexicographically: "b.h" < "c.h" as the src of the two thin edges, so the
#            expected cut is b.h -> c.h, cutrefs=1)
#   2-cycle: two/x.h -[x1]-> two/y.h -[x1]-> two/x.h   (equal weight both ways; lexicographic
#            tie-break picks x.h -> y.h, cutrefs=1)
#
# Every expected value below is hand-computed from the fixture's #include counts, not
# observed-and-frozen.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/cyclecutcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success. Does NOT edit
# regression.sh or any other file — self-contained gate + fixture.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/cyclecutfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/cyclecutfix dir — fixture missing"; exit 2; }
cd "$ROOT"
echo "cyclecutcheck: BIN=$BIN  CORPUS=test/cyclecutfix"

run(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --deps --no-cache "$@" 2>/dev/null; }

# one <cycle ...> opening tag per cycle, in emission order
cycletags(){ printf '%s' "$1" | grep -oE '<cycle [^>]*>'; }
# the cycle tag whose member <f p="..."/> list contains NEEDLE (search the whole blob for the
# <cycle>...</cycle> block containing it)
cycle_containing(){ printf '%s' "$1" | tr '\n' ' ' | grep -oE '<cycle [^>]*>(<f[^>]*/>)*</cycle>' | grep -F "$2"; }
attr_of(){ printf '%s' "$1" | grep -oE "$2=\"[^\"]*\""| head -1 | sed "s/^$2=\"//;s/\"\$//"; }
# XML-unescape just what escapeXml can produce, so expectations can be written in plain text
unesc(){ printf '%s' "$1" | sed 's/&gt;/>/g; s/&lt;/</g; s/&quot;/"/g; s/&apos;/'"'"'/g; s/&amp;/\&/g'; }

D="$( run )"

# ── 1) the 3-cycle: thin edge (weight 1) wins over the thick a->b (weight 3) ──────────────────────
C3="$( cycle_containing "$D" 'p="a.h"' )"
CUT3="$( unesc "$( attr_of "$C3" cut )" )"
REF3="$( attr_of "$C3" cutrefs )"
{ [ "$CUT3" = "b.h -> c.h" ] && [ "$REF3" = 1 ]; } \
    && ok "3-cycle: cut=b.h -> c.h (weight 1, beats thick a->b weight 3), cutrefs=1" \
    || no "3-cycle cut wrong: cut='$CUT3' cutrefs='$REF3' (want 'b.h -> c.h' / 1)"

# ── 2) the cut edge is genuinely a member of the 3-cycle (src AND dst both in the cycle's file list) ──
{ printf '%s' "$C3" | grep -qF "<f p=\"b.h\"/>" && printf '%s' "$C3" | grep -qF "<f p=\"c.h\"/>"; } \
    && ok "3-cycle: cut endpoints (b.h,c.h) are both real members of the cycle" \
    || no "3-cycle: cut names a file NOT in the cycle's member list — $C3"

# ── 3) size/cost sanity on the 3-cycle (size=3, cost=size²=9) unaffected by the new attr ──────────
{ [ "$( attr_of "$C3" size )" = 3 ] && [ "$( attr_of "$C3" cost )" = 9 ]; } \
    && ok "3-cycle: size=3 cost=9 (Lakos k² unaffected by cut attr)" \
    || no "3-cycle size/cost wrong: size=$( attr_of "$C3" size ) cost=$( attr_of "$C3" cost )"

# ── 4) the 2-cycle: equal weights (1,1) → lexicographic tie-break picks x.h -> y.h ────────────────
C2="$( cycle_containing "$D" 'p="two/x.h"' )"
CUT2="$( unesc "$( attr_of "$C2" cut )" )"
REF2="$( attr_of "$C2" cutrefs )"
{ [ "$CUT2" = "two/x.h -> two/y.h" ] && [ "$REF2" = 1 ]; } \
    && ok "2-cycle: equal-weight tie broken lexicographically → cut=x.h -> y.h, cutrefs=1" \
    || no "2-cycle cut wrong: cut='$CUT2' cutrefs='$REF2' (want 'two/x.h -> two/y.h' / 1)"

# ── 5) determinism: cut/cutrefs (and the whole cycles block) identical across repeated runs ───────
D2="$( run )"
[ "$D" = "$D2" ] \
    && ok "determinism: --deps cycles block (incl. cut/cutrefs) byte-identical run-to-run" \
    || no "--deps cycles block non-deterministic across runs"

# ── 6) xml well-formed ─────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$D" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (--deps with cycle cut attrs)" \
        || no "xml malformed in --deps cycle output"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── 7) golden neutrality: the DEFAULT map (no --deps) over test/fixture (which has NO cycles) is
#        untouched by this feature — packDeps only runs on the --deps branch, and the fixture
#        corpus used by test/regression.sh's golden has no include cycles at all. Spot-check here
#        that --deps on test/fixture emits NO <cycles> block (nothing to be neutral about going wrong).
FX="$ROOT/test/fixture"
if [ -d "$FX" ]; then
    # L1 (2026-09-19): the CLI default legend is compact and names <cycles> inside its comment; this arm looks for a real block, so it asks for the full legend.
    FD="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$FX" --deps --no-cache --legend=full 2>/dev/null )"
    if printf '%s' "$FD" | grep -q '<cycles>'; then
        no "test/fixture unexpectedly has a <cycles> block — golden-neutrality assumption invalid, recheck regression.sh golden"
    else
        ok "golden neutrality: test/fixture (the regression.sh golden corpus) has no cycles → cut feature is inert there"
    fi
else
    printf '  SKIP  golden neutrality check (no test/fixture dir)\n'
fi

# ── 8) MUTATION-TEST hook (documented, not auto-run): breaking the min-selection in packDeps (e.g.
#        flipping `w_ < bestW` to `w_ > bestW`, i.e. picking the THICKEST edge instead of the
#        thinnest) must flip check #1 above from PASS to FAIL, since a.h->b.h (weight 3) would then
#        be reported instead of b.h->c.h (weight 1). Verified manually during development:
#        `w_ < bestW` → `w_ > bestW` in src/serialize.h made check #1 fail as expected (cut became
#        "a.h -> b.h" cutrefs=3); reverted before landing.

# ── 9) DEPS-SHAPE-HONEST: <health shape=> reads the CYCLES, not nccd alone ──────────────────────────────────────────
# nccd passes 2 on any deep graph with no cycle at all (GRAPH-SCALE: true-edge Envoy 0.09 "horizontal" to 15.20
# "tangled" with 3 small cycles in 7,786 files). tangled now needs cyclic_files= to be at least 1 in 20 of dep_files=.
# Fixtures are written at runtime (SAFETY (f)(6)); every arm reads the exit code, so a crash or an empty answer is red.
SH="$( mktemp -d )"; trap 'rm -rf "$SH"' EXIT
deps(){ # $1 root, rest: extra flags. Sets DOUT and DRC.
    DOUT="$( cd "$1" && perl -e 'alarm 30; exec @ARGV' "$BIN" "$1" --deps --no-cache "${@:2}" 2>/dev/null )"; DRC=$?
}
health(){ printf '%s' "$DOUT" | grep -oE '<health [^>]*>' | head -1; }
mkchain(){ # $1 dir  $2 files in an acyclic include chain c0.h -> c1.h -> ... (a deep graph, no cycle)
    mkdir -p "$1"; local i=0
    while [ "$i" -lt "$2" ]; do
        if [ "$i" -lt $(( $2 - 1 )) ]; then printf '#include "c%d.h"\nint f%d(void);\n' $(( i + 1 )) "$i" > "$1/c$i.h"
        else printf 'int f%d(void);\n' "$i" > "$1/c$i.h"; fi
        i=$(( i + 1 ))
    done
}
mkpair(){ # $1 dir  $2 name: a 2-cycle p_<name>.h <-> q_<name>.h
    printf '#include "q_%s.h"\nint p_%s(void);\n' "$2" "$2" > "$1/p_$2.h"
    printf '#include "p_%s.h"\nint q_%s(void);\n' "$2" "$2" > "$1/q_$2.h"
}
# (a) a 40-deep chain, no cycle: nccd 4.56, so the old verdict said tangled
mkchain "$SH/deep" 40
deps "$SH/deep"; H="$( health )"
if [ "$DRC" = 0 ] && [ -n "$H" ] && printf '%s' "$H" | grep -q 'shape="vertical"' && ! printf '%s' "$H" | grep -q 'cyclic_files='; then
    ok "shape (a): a 40-deep acyclic chain reads vertical with no cyclic_files= (nccd above 2 is depth, not a tangle)"
else no "shape (a) rc=$DRC: $H"; fi
nc="$( printf '%s' "$H" | grep -oE 'nccd="[0-9.]+"' | grep -oE '[0-9.]+' )"
if awk -v n="${nc:-0}" 'BEGIN{exit !(n > 2)}'; then ok "shape (a) positive twin: the same chain's nccd=$nc is above 2"; else no "shape (a) nccd=$nc not above 2: the fixture no longer tests the old rule"; fi
# (b) 38 chain files + one 2-cycle: 2 of 40 = exactly 1 in 20, so tangled (the boundary is >=)
mkchain "$SH/edge" 38; mkpair "$SH/edge" a
deps "$SH/edge"; H="$( health )"
if [ "$DRC" = 0 ] && printf '%s' "$H" | grep -q 'shape="tangled" cyclic_files="2"' && printf '%s' "$H" | grep -q 'dep_files="40"'; then
    ok "shape (b): 2 cyclic files of 40 (1 in 20) read tangled, cyclic_files=2"
else no "shape (b) rc=$DRC: $H"; fi
# (c) the neighbour below the line: one more chain file makes it 2 of 41, under 1 in 20 -> not tangled
mkchain "$SH/below" 39; mkpair "$SH/below" a
deps "$SH/below"; H="$( health )"
if [ "$DRC" = 0 ] && printf '%s' "$H" | grep -q 'cyclic_files="2"' && ! printf '%s' "$H" | grep -q 'shape="tangled"' && printf '%s' "$H" | grep -q ' shape='; then
    ok "shape (c): 2 cyclic files of 41 stay below the line (not tangled), cyclic_files=2 still printed"
else no "shape (c) rc=$DRC: $H"; fi
# (d) a shallow tree with no cycle stays horizontal, no cyclic_files=
mkdir -p "$SH/flat"; for k in 1 2 3 4 5 6; do printf 'int g%d(void);\n' "$k" > "$SH/flat/l$k.h"; done
printf '#include "l1.h"\n#include "l2.h"\n' > "$SH/flat/top.h"
deps "$SH/flat"; H="$( health )"
if [ "$DRC" = 0 ] && printf '%s' "$H" | grep -q 'shape="horizontal"' && ! printf '%s' "$H" | grep -q 'cyclic_files='; then
    ok "shape (d): a flat tree stays horizontal, no cyclic_files="
else no "shape (d) rc=$DRC: $H"; fi
# (e) the cycle list discloses its 20-row cut: 21 pairs print total=21 shown=20 capped=1; 20 pairs print a bare <cycles>
mkdir -p "$SH/many21" "$SH/many20"; for k in $( seq 1 21 ); do mkpair "$SH/many21" "n$k"; done; for k in $( seq 1 20 ); do mkpair "$SH/many20" "n$k"; done
deps "$SH/many21" --legend=full; C21="$DOUT"; R21=$DRC
deps "$SH/many20" --legend=full; C20="$DOUT"; R20=$DRC
if [ "$R21" = 0 ] && printf '%s' "$C21" | grep -q '<cycles total="21" shown="20" capped="1">' && [ "$( printf '%s' "$C21" | grep -oE '<cycle size=' | wc -l | tr -d ' ' )" = 20 ]; then
    ok "cycles (e): 21 cycles list 20 under <cycles total=21 shown=20 capped=1>"
else no "cycles (e) rc=$R21: $( printf '%s' "$C21" | grep -oE '<cycles[^>]*>' )"; fi
if [ "$R20" = 0 ] && printf '%s' "$C20" | grep -q '<cycles>' && [ "$( printf '%s' "$C20" | grep -oE '<cycle size=' | wc -l | tr -d ' ' )" = 20 ]; then
    ok "cycles (e) twin: 20 cycles, all listed, a bare <cycles> (no cut to disclose)"
else no "cycles (e) twin rc=$R20: $( printf '%s' "$C20" | grep -oE '<cycles[^>]*>' )"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
