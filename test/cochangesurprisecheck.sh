#!/usr/bin/env bash
# cochangesurprisecheck.sh — §P9.1 gate: --cochange's repo-wide surprising="1" flag must use the SAME
# transitive #include-closure predicate as the per-file path, not a 1-hop-only check.
#
# The repo-wide path's static-dependency predicate (src/main.cpp, --cochange pair scan) was a 1-HOP
# neighbour test, while the header comment promises "no TRANSITIVE static dependency" and the per-file
# path (src/gitmine.h cochangePartners, A4-F22) already computed the correct forward+reverse transitive
# closure. Result: a genuinely coupled pair like ingest.cpp -> ingest.h -> model.h (one hop indirect)
# shipped as `surprising="1"` — a confident FALSE POSITIVE on the tool's own architecturally-actionable
# rows (both src<->src rows in the emitted top-30 were wrong: ingest.cpp<->model.h, main.cpp<->notes.h).
#
# Fix: ONE shared predicate — src/gitmine.h::StaticIncludeCoupling, built once from resolveIncludeAdj(ing)
# and used by BOTH cochangePartners (per-file) and the repo-wide pair scan in src/main.cpp.
#
# This gate:
#   (1) NEGATIVE  — a pair with a real transitive #include path (ingest.cpp/model.h, main.cpp/notes.h)
#                   must NOT carry surprising="1", if present in the top-N at all.
#   (2) POSITIVE  — a genuinely uncoupled DEPENDENCY-CAPABLE pair (src<->src, no transitive #include)
#                   must STILL carry surprising="1": the fix must not suppress the signal wholesale.
#   (2b) §A9.3    — a pair with a DEP-INCAPABLE side (.sh/.md/.pdf/.pptx/.json) must carry dep_capable="0"
#                   and never surprising="1".
#   (3) DETERMINISM — two runs are byte-identical.
#
# §A9.3 AMENDMENT (2026-07-28) — arm (2)'s control INVERTED, on purpose. It used to require that a
# src<->test/*.sh pair still carry surprising="1", on the reasoning "a shell script can never be
# #included by C++, so the flag must survive". That reasoning is exactly the §A9 finding: surprising=
# claims "these change together yet NO static dependency explains it", and for a pair that could not
# carry a static dependency AT ALL the claim is vacuously true, not evidence of hidden coupling. ~22 of
# the first 30 repo-wide rows were such pairs (a .pdf<->.pptx build-artifact pair read as hidden
# architectural debt). So the shell-script pair is now the NEGATIVE control for dep_capable="0", and the
# "signal survives" duty moved to a real src<->src surprising row, which is what the flag is FOR.
#
#   CTXPACK_BIN=build/ctxpack      bash test/cochangesurprisecheck.sh
#   CTXPACK_BIN=build_base/ctxpack bash test/cochangesurprisecheck.sh   # must FAIL (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
command -v git >/dev/null || { echo "cochangesurprisecheck: git not on PATH"; exit 2; }
echo "cochangesurprisecheck: BIN=$BIN  ROOT=$ROOT"

"$BIN" "$ROOT" --cochange >"$TMP/out" 2>"$TMP/err"
rc=$?
[ "$rc" -eq 0 ] && ok "--cochange exits 0" || { no "--cochange exits $rc"; cat "$TMP/err"; }
[ -s "$TMP/out" ] || { echo "cochangesurprisecheck: empty output, cannot proceed"; exit 2; }

# --pack-top-n raises the cap so the two specific rows checked below aren't hidden by the default 30-row
# truncation (surprising=0 pairs sort AFTER surprising=1 ones, so a fixed cap alone could make a false
# positive silently "pass" by dropping out of the top-N instead of by being correctly unflagged).
"$BIN" "$ROOT" --cochange --pack-top-n=1000 >"$TMP/full" 2>/dev/null

# pull out one <pair .../> element mentioning BOTH basenames, regardless of a=/b= order — read from the
# uncapped run so a genuine pass means "present, correctly unflagged", not "truncated out of the top-N"
pairRow(){
    local needle1="$1" needle2="$2"
    grep -oE '<pair [^>]*/>' "$TMP/full" \
        | grep -F "$needle1" \
        | grep -F "$needle2" \
        | head -n1
}

# ── 1. NEGATIVE — transitively-coupled src<->src pairs must never carry surprising="1"
checkNotSurprising(){
    local n1="$1" n2="$2"
    local row; row="$( pairRow "$n1" "$n2" )"
    if [ -z "$row" ]; then
        no "$n1 <-> $n2: pair not found even with --pack-top-n=1000 (fixture drifted — cannot assert)"
        return
    fi
    if echo "$row" | grep -q 'surprising="1"'; then
        no "$n1 <-> $n2: FALSE POSITIVE — carries surprising=\"1\" despite a transitive #include path: $row"
    else
        ok "$n1 <-> $n2: present, no surprising=\"1\" (transitive #include coupling correctly recognised): $row"
    fi
}
checkNotSurprising "ingest.cpp" "model.h"
checkNotSurprising "main.cpp" "notes.h"

# ── 1b. NEGATIVE (§P9.1 residue, 2026-07-28) — a CROSS-DIRECTORY `-I` include is a plain `#include` that
#      the path-precise resolver structurally cannot see: bench/bench_convergence.cpp:26 is literally
#      `#include "svector.h"`, resolved through `-Isrc`, so resolveIncludeAdj finds no edge and the pair
#      shipped as surprising="1". A repo-wide sweep found this was the ONLY leaked pair, so the fix is a
#      narrow bare-name fallback in StaticIncludeCoupling (it can only ever SUPPRESS the flag).
#      Conditional on the pair being present at all — git history ages and the pair can fall below the
#      3-commit support floor; what must NEVER happen is it coming back FLAGGED.
residueRow="$( pairRow "bench_convergence.cpp" "svector.h" )"
if [ -z "$residueRow" ]; then
    ok "-I residue: bench_convergence.cpp <-> svector.h no longer co-changes above the support floor (nothing to assert)"
elif echo "$residueRow" | grep -q 'surprising="1"'; then
    no "-I residue: FALSE POSITIVE — cross-directory -I include (\`#include \"svector.h\"\` via -Isrc) still reads as hidden coupling: $residueRow"
else
    ok "-I residue: present, no surprising=\"1\" (bare-name fallback recognised the -I include): $residueRow"
fi

# ── 2. POSITIVE control — the signal must still FIRE where it means something: a src<->src pair (both
#      sides dependency-capable) with no transitive #include between them. Picked dynamically from the
#      live top-30 so no single pair is hardcoded as git history ages.
posRow="$( grep -oE '<pair [^>]*/>' "$TMP/out" | grep 'surprising="1"' \
           | grep -E 'a="[^"]*/src/[^"]*\.(h|cpp)"' | grep -E 'b="[^"]*/src/[^"]*\.(h|cpp)"' | head -n1 )"
if [ -z "$posRow" ]; then
    no "positive control: no src<->src surprising=\"1\" pair in --cochange's first screen (the signal may have been suppressed wholesale)"
else
    ok "positive control still fires on a dependency-capable pair: $posRow"
fi

# ── 2b. §A9.3 — every row with a DEP-INCAPABLE side must carry dep_capable="0" and must NOT carry
#      surprising="1". Swept over the UNCAPPED run: one leaked row is the whole defect (a .pdf<->.pptx
#      pair rendered as hidden coupling), so a sampled check would not be a gate.
badRows="$( grep -oE '<pair [^>]*/>' "$TMP/full" | grep 'surprising="1"' \
            | grep -E '(a|b)="[^"]*\.(sh|md|pdf|pptx|json|rb|txt)"' | head -n3 )"
if [ -n "$badRows" ]; then
    no "§A9.3: a dependency-INCAPABLE pair still claims surprising=\"1\" (vacuously true, reads as hidden coupling):"
    printf '        %s\n' "$badRows"
else
    ok "§A9.3: no .sh/.md/.pdf/.pptx/.json-sided pair carries surprising=\"1\" (uncapped sweep)"
fi

depRow="$( grep -oE '<pair [^>]*/>' "$TMP/full" | grep -E '(a|b)="[^"]*\.sh"' | head -n1 )"
if [ -z "$depRow" ]; then
    no "§A9.3: no .sh-sided pair in the uncapped output at all — cannot verify the dep_capable=\"0\" tell"
elif echo "$depRow" | grep -q 'dep_capable="0"'; then
    ok "§A9.3: a .sh-sided pair keeps its row and carries the dep_capable=\"0\" tell: $depRow"
else
    no "§A9.3: a .sh-sided pair carries neither surprising= nor dep_capable=\"0\" — the row is silent about why: $depRow"
fi

# ── 2c. §A9.3 — the per-file path must speak the SAME vocabulary as the repo-wide one (§P9.1's rule,
#      one flag over): src/quality.h co-changes with test/regression.sh in this repo's history.
"$BIN" "$ROOT" --cochange=src/quality.h --pack-top-n=1000 >"$TMP/perfile" 2>/dev/null
perFileRow="$( grep -oE '<f [^>]*/>' "$TMP/perfile" | grep -E 'p="[^"]*\.sh"' | head -n1 )"
if [ -z "$perFileRow" ]; then
    ok "§A9.3 per-file: no .sh partner above the support floor (nothing to assert)"
elif echo "$perFileRow" | grep -q 'surprising="1"'; then
    no "§A9.3 per-file: a .sh partner still claims surprising=\"1\" — the two paths disagree again: $perFileRow"
elif echo "$perFileRow" | grep -q 'dep_capable="0"'; then
    ok "§A9.3 per-file: a .sh partner carries dep_capable=\"0\", same vocabulary as the repo-wide path: $perFileRow"
else
    no "§A9.3 per-file: a .sh partner is silent (no surprising=, no dep_capable=): $perFileRow"
fi

# ── 3. determinism
"$BIN" "$ROOT" --cochange >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT" --cochange >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "deterministic (byte-identical run-to-run)" || no "non-deterministic --cochange output"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
