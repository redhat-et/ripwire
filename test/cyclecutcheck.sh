#!/usr/bin/env bash
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
# Usage:  CTXPACK_BIN=build/ctxpack bash test/cyclecutcheck.sh   |   CTXPACK_BIN=asan/ctxpack bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success. Does NOT edit
# regression.sh or any other file — self-contained gate + fixture.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/cyclecutfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
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
C3="$( cycle_containing "$D" 'cyclecutfix/a.h' )"
CUT3="$( unesc "$( attr_of "$C3" cut )" )"
REF3="$( attr_of "$C3" cutrefs )"
{ [ "$CUT3" = "$FIX/b.h -> $FIX/c.h" ] && [ "$REF3" = 1 ]; } \
    && ok "3-cycle: cut=b.h -> c.h (weight 1, beats thick a->b weight 3), cutrefs=1" \
    || no "3-cycle cut wrong: cut='$CUT3' cutrefs='$REF3' (want '$FIX/b.h -> $FIX/c.h' / 1)"

# ── 2) the cut edge is genuinely a member of the 3-cycle (src AND dst both in the cycle's file list) ──
{ printf '%s' "$C3" | grep -qF "<f p=\"$FIX/b.h\"/>" && printf '%s' "$C3" | grep -qF "<f p=\"$FIX/c.h\"/>"; } \
    && ok "3-cycle: cut endpoints (b.h,c.h) are both real members of the cycle" \
    || no "3-cycle: cut names a file NOT in the cycle's member list — $C3"

# ── 3) size/cost sanity on the 3-cycle (size=3, cost=size²=9) unaffected by the new attr ──────────
{ [ "$( attr_of "$C3" size )" = 3 ] && [ "$( attr_of "$C3" cost )" = 9 ]; } \
    && ok "3-cycle: size=3 cost=9 (Lakos k² unaffected by cut attr)" \
    || no "3-cycle size/cost wrong: size=$( attr_of "$C3" size ) cost=$( attr_of "$C3" cost )"

# ── 4) the 2-cycle: equal weights (1,1) → lexicographic tie-break picks x.h -> y.h ────────────────
C2="$( cycle_containing "$D" 'cyclecutfix/two/x.h' )"
CUT2="$( unesc "$( attr_of "$C2" cut )" )"
REF2="$( attr_of "$C2" cutrefs )"
{ [ "$CUT2" = "$FIX/two/x.h -> $FIX/two/y.h" ] && [ "$REF2" = 1 ]; } \
    && ok "2-cycle: equal-weight tie broken lexicographically → cut=x.h -> y.h, cutrefs=1" \
    || no "2-cycle cut wrong: cut='$CUT2' cutrefs='$REF2' (want '$FIX/two/x.h -> $FIX/two/y.h' / 1)"

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
    FD="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$FX" --deps --no-cache 2>/dev/null )"
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

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
