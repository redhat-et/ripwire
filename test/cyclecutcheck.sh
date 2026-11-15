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
# (f) #479 item 2: a cycle lists at most 12 member files, and a cut member list says so. A 14-file ring prints size=14 with
#     12 <f> rows and members_capped="1"; a 12-file ring prints all 12 and no members_capped (no cut to disclose). The
#     attribute is defined in the answer's own compact legend.
mkring(){ # $1 dir  $2 files in one include ring r0.h -> r1.h -> ... -> r(N-1).h -> r0.h
    mkdir -p "$1"; local i=0
    while [ "$i" -lt "$2" ]; do printf '#include "r%d.h"\nint r%d(void);\n' $(( ( i + 1 ) % $2 )) "$i" > "$1/r$i.h"; i=$(( i + 1 )); done
}
mkring "$SH/ring14" 14; mkring "$SH/ring12" 12
deps "$SH/ring14" --legend=compact; C14="$DOUT"; R14=$DRC
deps "$SH/ring12" --legend=compact; C12="$DOUT"; R12=$DRC
CY14="$( printf '%s' "$C14" | grep -oE '<cycle [^>]*>.*</cycle>' )"
CY12="$( printf '%s' "$C12" | grep -oE '<cycle [^>]*>.*</cycle>' )"
if [ "$R14" = 0 ] && printf '%s' "$CY14" | grep -qE '^<cycle size="14" [^>]*members_capped="1"' \
   && [ "$( printf '%s' "$CY14" | grep -oE '<f p=' | wc -l | tr -d ' ' )" = 12 ]; then
    ok "cycles (f): a 14-file cycle lists 12 members under <cycle size=14 … members_capped=1>"
else no "cycles (f) rc=$R14: $( printf '%s' "$CY14" | grep -oE '^<cycle [^>]*>' ) members=$( printf '%s' "$CY14" | grep -oE '<f p=' | wc -l | tr -d ' ' )"; fi
if [ "$R12" = 0 ] && printf '%s' "$CY12" | grep -qE '^<cycle size="12" ' && ! printf '%s' "$CY12" | grep -q 'members_capped' \
   && [ "$( printf '%s' "$CY12" | grep -oE '<f p=' | wc -l | tr -d ' ' )" = 12 ]; then
    ok "cycles (f) twin: a 12-file cycle lists all 12 members, no members_capped"
else no "cycles (f) twin rc=$R12: $( printf '%s' "$CY12" | grep -oE '^<cycle [^>]*>' )"; fi
if [ "$R14" = 0 ] && printf '%s' "$C14" | grep -q 'members_capped=1:'; then
    ok "cycles (f) legend: the compact legend defines members_capped="
else no "cycles (f) legend: no members_capped= definition in the answer's compact legend"; fi
if [ "$R14" = 0 ] && printf '%s' "$C14" | grep -q 'members_capped=1:[^.]*first in SCC order, not ranked'; then
    ok "cycles (f) legend order: the compact legend says which 12 rows are listed"
else no "cycles (f) legend order: the compact members_capped= reading does not say the rows are first in SCC order, not ranked"; fi
# (f) boundary + full legend (#541 review): a 13-file ring is the first size the cap cuts; --legend=full defines the
#     attribute exactly when a shown cycle is cut, and the uncut 12-file twin's full legend does not mention it.
mkring "$SH/ring13" 13
deps "$SH/ring13" --legend=compact; C13="$DOUT"; R13=$DRC
CY13="$( printf '%s' "$C13" | grep -oE '<cycle [^>]*>.*</cycle>' )"
if [ "$R13" = 0 ] && printf '%s' "$CY13" | grep -qE '^<cycle size="13" [^>]*members_capped="1"' \
   && [ "$( printf '%s' "$CY13" | grep -oE '<f p=' | wc -l | tr -d ' ' )" = 12 ]; then
    ok "cycles (f) boundary: a 13-file cycle lists 12 members under members_capped=1"
else no "cycles (f) boundary rc=$R13: $( printf '%s' "$CY13" | grep -oE '^<cycle [^>]*>' )"; fi
deps "$SH/ring14" --legend=full; F14="$DOUT"; RF14=$DRC
deps "$SH/ring12" --legend=full; F12="$DOUT"; RF12=$DRC
if [ "$RF14" = 0 ] && printf '%s' "$F14" | grep -q 'cycle members_capped=1:'; then
    ok "cycles (f) full legend: --legend=full defines members_capped= when a cycle is cut"
else no "cycles (f) full legend rc=$RF14: no members_capped= definition in the full --deps legend"; fi
if [ "$RF12" = 0 ] && ! printf '%s' "$F12" | grep -q 'members_capped'; then
    ok "cycles (f) full legend twin: an uncut cycle's full legend does not mention members_capped="
else no "cycles (f) full legend twin rc=$RF12: members_capped appears with no cut"; fi

# ── 10) RUST-MOD-DECL: a `mod x;` parent-to-child pair is containment, not a cycle ──────────────────────────────────
# Rust: the parent declares `mod x;`, the child `use super::…`/`use crate::…` back: every pair reads as a 2-cycle
# (GRAPH-SCALE nushell: largest cycle 235 with these pairs, 19 without). They leave cycles/ccd/transitive= and stay in
# afferent=; <health containment_edges=> counts them. A cycle between two SIBLINGS is real and must stay.
RS="$SH/rs"; mkdir -p "$RS/src/net" "$RS/pkg"
printf 'mod net;\nmod util;\nmod store;\npub fn root_fn() {}\n' > "$RS/src/lib.rs"
printf 'mod wire;\nuse crate::util;\npub fn net_fn() { util::helper(); }\n' > "$RS/src/net/mod.rs"
printf 'use crate::net;\npub fn wire_fn() { net::net_fn(); }\n' > "$RS/src/net/wire.rs"
printf 'use crate::store;\npub fn helper() { store::keep(); }\n' > "$RS/src/util.rs"
printf 'use crate::util;\npub fn keep() { util::helper(); }\n' > "$RS/src/store.rs"
# polyglot: a Python package whose __init__ imports its child and the child imports the package — a real import
# cycle Python executes, so it is NOT containment and must stay a cycle
printf 'from .mod_a import a\n' > "$RS/pkg/__init__.py"
printf 'from pkg import thing\ndef a(): pass\n' > "$RS/pkg/mod_a.py"
deps "$RS" --legend=full; H="$( health )"; RD="$DOUT"; RRC=$DRC
cyc(){ printf '%s' "$RD" | tr '\n' ' ' | grep -oE '<cycle [^>]*>(<f[^>]*/>)*</cycle>'; }
if [ "$RRC" = 0 ] && [ -n "$H" ] && printf '%s' "$H" | grep -qE 'containment_edges="[1-9][0-9]*"'; then
    ok "rust mod (a): <health containment_edges=$( printf '%s' "$H" | grep -oE 'containment_edges="[0-9]+"' | grep -oE '[0-9]+' )> printed"
else no "rust mod (a) rc=$RRC: $H"; fi
if [ "$RRC" = 0 ] && [ -n "$RD" ] && ! cyc | grep -q 'net/wire.rs' && ! cyc | grep -q 'src/lib.rs'; then
    ok "rust mod (b): no cycle through a mod-declared pair (lib.rs, net/mod.rs <-> net/wire.rs)"
else no "rust mod (b): a containment pair still reads as a cycle: $( cyc )"; fi
if cyc | grep -q 'src/util.rs' && cyc | grep -q 'src/store.rs'; then
    ok "rust mod (c): the sibling cycle util.rs <-> store.rs stays (a real use cycle, not containment)"
else no "rust mod (c): the sibling cycle is gone: $( cyc )"; fi
if cyc | grep -q 'pkg/__init__.py' && cyc | grep -q 'pkg/mod_a.py'; then
    ok "rust mod (d) polyglot: the Python package cycle __init__.py <-> mod_a.py stays (only Rust mod pairs are containment)"
else no "rust mod (d): the Python cycle is gone: $( cyc )"; fi
wrow="$( printf '%s' "$RD" | grep -oE '<f p="src/net/wire.rs"[^>]*>' | head -1 )"
if printf '%s' "$RD" | grep -oE '<f p="src/net/mod.rs"[^>]*>' | grep -q 'afferent="[1-9]'; then
    ok "rust mod (e): Ca kept: net/mod.rs keeps its afferent= from the parent and the child"
else no "rust mod (e): net/mod.rs row: $( printf '%s' "$RD" | grep -oE '<f p="src/net/mod.rs"[^>]*>' )"; fi
if printf '%s' "$RD" | grep -q 'health containment_edges=N'; then ok "rust mod (f): the legend defines containment_edges= beside it"; else no "rust mod (f): legend sentence missing"; fi
# (i) allowlist (SAFETY (d)(1)): only the module-file rule's own location is containment. src/store.rs's `mod cache;` names
# src/store/cache.rs in Rust 2018; the edge this build draws to src/cache.rs (resolve.h probes the includer's own
# directory) is not that pair, so it is NOT cut and its cycle with cache.rs's `use crate::store;` stays counted.
mkdir -p "$SH/rs2/src"; printf 'mod store;\nmod cache;\n' > "$SH/rs2/src/lib.rs"
printf 'mod cache;\npub fn keep() {}\n' > "$SH/rs2/src/store.rs"
printf 'use crate::store;\npub fn get() { store::keep(); }\n' > "$SH/rs2/src/cache.rs"
deps "$SH/rs2" --legend=full
if [ "$DRC" = 0 ] && printf '%s' "$DOUT" | tr '\n' ' ' | grep -oE '<cycle [^>]*>(<f[^>]*/>)*</cycle>' | grep -q 'src/cache.rs' \
   && printf '%s' "$DOUT" | grep -oE '<health [^>]*>' | grep -q 'containment_edges="2"'; then
    ok "rust mod (i): a mod name resolved outside the module-file location is not containment (cycle kept; only lib.rs's 2 pairs cut)"
else no "rust mod (i) rc=$DRC: $( printf '%s' "$DOUT" | grep -oE '<health [^>]*>|<cycle [^>]*>' )"; fi
# (j) a crate root that is not lib.rs/main.rs (an integration test, a [[bin]], a [lib] path): no `mod it;` declares
# tests/it.rs, so it is a root and its `mod common;` child is tests/common/mod.rs; common's `use super::it` points back.
mkdir -p "$SH/rs3/tests/common"; printf 'mod common;\npub fn it_fn() {}\n' > "$SH/rs3/tests/it.rs"
printf 'use super::it;\npub fn setup() {}\n' > "$SH/rs3/tests/common/mod.rs"
deps "$SH/rs3" --legend=full
if [ "$DRC" = 0 ] && [ -n "$DOUT" ] && ! printf '%s' "$DOUT" | grep -q '<cycle ' && printf '%s' "$DOUT" | grep -oE '<health [^>]*>' | grep -q 'containment_edges="1"'; then
    ok "rust mod (j): tests/it.rs (declared by no mod, so a crate root) contains tests/common/mod.rs: no cycle, containment_edges=1"
else no "rust mod (j) rc=$DRC: $( printf '%s' "$DOUT" | grep -oE '<health [^>]*>|<cycle [^>]*>' )"; fi
# (k)-(o) truth-fixes fix 1 (M1, coordinator ruling: a `use` across a mod pair is a dependency): a parent-to-child pair is
# cut only when the `mod x;` declaration is the edge's only reason. A parent that also uses its child keeps the edge, so a
# cycle through it stays. (k) fx r1m: a/mod.rs uses inner.rs, inner.rs uses b.rs, b.rs uses a/mod.rs: the 3-cycle stays.
mkdir -p "$SH/r1m/src/a"; printf 'mod a;\nmod b;\n' > "$SH/r1m/src/lib.rs"
printf 'mod inner;\npub use self::inner::Thing;\npub fn a_fn() { inner::go(); }\n' > "$SH/r1m/src/a/mod.rs"
printf 'use crate::b;\npub struct Thing;\npub fn go() { b::b_fn(); }\n' > "$SH/r1m/src/a/inner.rs"
printf 'use crate::a;\npub fn b_fn() { a::a_fn(); }\n' > "$SH/r1m/src/b.rs"
deps "$SH/r1m" --legend=full
if [ "$DRC" = 0 ] && printf '%s' "$DOUT" | tr '\n' ' ' | grep -oE '<cycle size="3"[^>]*>(<f[^>]*/>)*</cycle>' | grep -q 'src/a/inner.rs' \
   && printf '%s' "$DOUT" | grep -oE '<health [^>]*>' | grep -q 'containment_edges="2"'; then
    ok "rust mod (k): a cycle through a parent that uses its child stays (r1m 3-cycle; only lib.rs's 2 declaration-only pairs cut)"
else no "rust mod (k) rc=$DRC: $( printf '%s' "$DOUT" | grep -oE '<health [^>]*>|<cycle [^>]*>' )"; fi
REP="$( cd "$SH/r1m" && perl -e 'alarm 30; exec @ARGV' "$BIN" "$SH/r1m" --report --no-cache 2>/dev/null )"; REPRC=$?
if [ "$REPRC" = 0 ] && printf '%s' "$REP" | grep -q '^- `src/a/mod.rs` ↔' && ! printf '%s' "$REP" | grep -q 'acyclic'; then
    ok "rust mod (k): --report lists the r1m cycle and never says acyclic"
else no "rust mod (k) report rc=$REPRC: $( printf '%s' "$REP" | grep -A1 'Dependency cycles' )"; fi
# (l) the sibling shapes of "uses its child": a path call alone (`common::setup()`), a relative `pub use x::*;` that resolves
# to no file, and `use self::x::T;`. Each keeps its 2-cycle with the child's `use crate::p;`.
for shape in 'pub fn f() { kid::k(); }' 'pub use kid::*;' 'use self::kid::K;'; do
    rm -rf "$SH/rsl"; mkdir -p "$SH/rsl/src/p"
    printf 'mod p;\n' > "$SH/rsl/src/lib.rs"
    printf 'mod kid;\n%s\npub fn pf() {}\n' "$shape" > "$SH/rsl/src/p/mod.rs"
    printf 'use crate::p;\npub struct K;\npub fn k() { p::pf(); }\n' > "$SH/rsl/src/p/kid.rs"
    deps "$SH/rsl" --legend=full
    if [ "$DRC" = 0 ] && printf '%s' "$DOUT" | tr '\n' ' ' | grep -oE '<cycle [^>]*>(<f[^>]*/>)*</cycle>' | grep -q 'src/p/kid.rs' \
       && printf '%s' "$DOUT" | grep -oE '<health [^>]*>' | grep -q 'containment_edges="1"'; then
        ok "rust mod (l): '$shape' in the parent keeps the p/mod.rs <-> p/kid.rs cycle (only lib.rs -> p cut)"
    else no "rust mod (l) '$shape' rc=$DRC: $( printf '%s' "$DOUT" | grep -oE '<health [^>]*>|<cycle [^>]*>' )"; fi
done
# (m) negative twin of (l): the parent declares the child twice under #[cfg] and names it nowhere else: cut, no cycle
rm -rf "$SH/rsl"; mkdir -p "$SH/rsl/src/p"; printf 'mod p;\n' > "$SH/rsl/src/lib.rs"
printf '#[cfg(unix)]\nmod kid;\n#[cfg(not(unix))]\nmod kid;\npub fn pf() {}\n' > "$SH/rsl/src/p/mod.rs"
printf 'use crate::p;\npub fn k() { p::pf(); }\n' > "$SH/rsl/src/p/kid.rs"
deps "$SH/rsl" --legend=full
if [ "$DRC" = 0 ] && [ -n "$DOUT" ] && ! printf '%s' "$DOUT" | grep -q '<cycle ' && printf '%s' "$DOUT" | grep -oE '<health [^>]*>' | grep -q 'containment_edges="2"'; then
    ok "rust mod (m): a declaration-only pair (declared twice under #[cfg]) is cut: no cycle, containment_edges=2"
else no "rust mod (m) rc=$DRC: $( printf '%s' "$DOUT" | grep -oE '<health [^>]*>|<cycle [^>]*>' )"; fi
# (n) (j)'s positive twin: tests/it.rs calls its child (`common::setup()`), so the pair is a use and the 2-cycle stays
printf 'mod common;\npub fn it_fn() { common::setup(); }\n' > "$SH/rs3/tests/it.rs"
deps "$SH/rs3" --legend=full
if [ "$DRC" = 0 ] && printf '%s' "$DOUT" | grep -q '<cycle size="2"' && ! printf '%s' "$DOUT" | grep -q 'containment_edges='; then
    ok "rust mod (n): a root that calls its child keeps the cycle (no containment_edges=)"
else no "rust mod (n) rc=$DRC: $( printf '%s' "$DOUT" | grep -oE '<health [^>]*>|<cycle [^>]*>' )"; fi
# (o) --report over a tree whose only would-be cycles are containment says "acyclic without the containment pairs", never bare
REP="$( cd "$SH/rs3" && printf 'mod common;\npub fn it_fn() {}\n' > tests/it.rs && perl -e 'alarm 30; exec @ARGV' "$BIN" "$SH/rs3" --report --no-cache 2>/dev/null )"; REPRC=$?
if [ "$REPRC" = 0 ] && printf '%s' "$REP" | grep -q '^- none (acyclic without the containment pairs)' && ! printf '%s' "$REP" | grep -q '^- none (acyclic)'; then
    ok "rust mod (o): --report's empty cycle list qualifies acyclic by the containment pairs"
else no "rust mod (o) rc=$REPRC: $( printf '%s' "$REP" | grep -A1 'Dependency cycles' )"; fi
# (p) S1: twenty-one 2-cycles and one 4-cycle: the 20-row cap keeps the 4-cycle (largest first); --limit=30 lists all 22
mkdir -p "$SH/m21"; for k in $( seq 1 21 ); do mkpair "$SH/m21" "n$k"; done
printf '#include "w2.h"\n' > "$SH/m21/w1.h"; printf '#include "w3.h"\n' > "$SH/m21/w2.h"; printf '#include "w4.h"\n' > "$SH/m21/w3.h"; printf '#include "w1.h"\n' > "$SH/m21/w4.h"
deps "$SH/m21" --legend=full
if [ "$DRC" = 0 ] && printf '%s' "$DOUT" | grep -q '<cycles total="22" shown="20" capped="1"><cycle size="4"'; then
    ok "cycles (p): the cut list keeps the largest: the 4-cycle is first of the 20 shown"
else no "cycles (p) rc=$DRC: $( printf '%s' "$DOUT" | grep -oE '<cycles[^>]*><cycle [^>]*>' )"; fi
deps "$SH/m21" --legend=full --limit=30
if [ "$DRC" = 0 ] && printf '%s' "$DOUT" | grep -q '<cycles><cycle size="4"' && [ "$( printf '%s' "$DOUT" | grep -oE '<cycle size=' | wc -l | tr -d ' ' )" = 22 ]; then
    ok "cycles (p) twin: --limit=30 raises the cap: all 22 listed, a bare <cycles>"
else no "cycles (p) twin rc=$DRC: $( printf '%s' "$DOUT" | grep -oE '<cycles[^>]*>' )"; fi
# (g) negative twin: a C tree with no Rust never prints containment_edges=
deps "$SH/edge"; if [ "$DRC" = 0 ] && [ -n "$DOUT" ] && ! printf '%s' "$DOUT" | grep -q 'containment_edges'; then ok "rust mod (g): no Rust file, no containment_edges="; else no "rust mod (g) rc=$DRC"; fi
# (h) --report's cycle heading says what it left out
REP="$( cd "$RS" && perl -e 'alarm 30; exec @ARGV' "$BIN" "$RS" --report --no-cache 2>/dev/null )"; REPRC=$?
if [ "$REPRC" = 0 ] && printf '%s' "$REP" | grep -q '## Dependency cycles .*Rust mod-declaration pairs left out as containment'; then
    ok "rust mod (h): --report's cycle heading names the containment pairs it left out"
else no "rust mod (h) rc=$REPRC: $( printf '%s' "$REP" | grep 'Dependency cycles' )"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
