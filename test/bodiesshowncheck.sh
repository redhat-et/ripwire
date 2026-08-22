#!/usr/bin/env bash
# bodiesshowncheck.sh — gate for W3-S item 2 (R9): <bodies> must be PRESENT with shown="0" when compose
# wins the budget and zero bodies are inlined, never ABSENT — "a zero means none found, never none exists"
# (CONTRIBUTING.md #3) applies to elements too, not only counts.
#
# E6 / the wave-2 growth round reproduced this on four of five --token-budget=3000 --for queries across
# four corpora (memgraph/plotly/ugrep/etcd, routing note R9 / exp-e6.md A5): "<bodies> ABSENT ENTIRELY"
# whenever a budget-constrained run's auto-body selection kept zero candidates, or had zero candidates to
# begin with. Two emitters had this bug independently:
#   - src/main.cpp buildForAutoBodies (the --for / MCP `for` T3 auto-bundle path): both its
#     autoBodyIds.empty() branch and its autoEmitted.kept.empty() branch discarded an already-rendered (or
#     never-rendered) section instead of keeping/emitting the honest shown="0" shell.
#   - src/packtask.h packTaskBundleText's bodiesStr (the --pack-task / MCP pack_task,explore path): the
#     `else` of `if (!bodyIds.empty() && bodiesBudget >= kPackTaskSectionFloor)` left bodiesStr empty.
# packtask.h's own packTaskListSection (backing <callers>/<far>/<notes>/<tests>) has the identical defect
# and is DELIBERATELY OUT OF SCOPE here — a separate, larger fix (see the spawned follow-up task); this
# gate covers <bodies> only, per the wave-3 item's own scope.
#
# Usage:
#   test/bodiesshowncheck.sh                      # uses build/ripwire
#   test/bodiesshowncheck.sh asan/ripwire
#   RIPWIRE_BIN=build_base/ripwire test/bodiesshowncheck.sh   # red-first: arms 1-4 MUST fail here — a
#     pre-fix binary drops the <bodies> element whole in all four scenarios below.
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "bodiesshowncheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "bodiesshowncheck: xmllint is required"; exit 2; }
cd "$ROOT"
echo "bodiesshowncheck: BIN=$BIN"

run(){ "$BIN" "$@" 2>/dev/null; }

# shownzero FILE LABEL: asserts <bodies shown="0" total="N" capped="C"> is present (N a real number, C 0|1
# consistent with N), rather than the element being absent from the document entirely.
# The optional third argument names the ELEMENT, so the same R9 contract ("a zero means none found, never
# none exists" applies to elements, not only to counts) can be asserted on the compact route's <hops>
# section as well as on <bodies>. Defaults to bodies, so every pre-existing call site is unchanged.
shownzero(){
    local f="$1" label="$2" el="${3:-bodies}"
    local tag; tag="$( grep -o "<$el shown=\"0\"[^>]*>" "$f" | head -1 )"
    if [ -z "$tag" ]; then
        no "$label: no <$el shown=\"0\" ...> tag found — the element is ABSENT (the exact R9 bug)"
        return
    fi
    local total capped
    total="$(  printf '%s' "$tag" | sed -n 's/.*total="\([0-9]*\)".*/\1/p' )"
    capped="$( printf '%s' "$tag" | sed -n 's/.*capped="\([01]\)".*/\1/p' )"
    if [ -z "$total" ] || [ -z "$capped" ]; then
        no "$label: <$el shown=\"0\"> is missing total=/capped= ($tag)"
    elif [ "$total" = "0" ] && [ "$capped" != "0" ]; then
        no "$label: total=0 but capped=\"$capped\" (want 0 — nothing was requested, nothing was dropped)"
    elif [ "$total" != "0" ] && [ "$capped" != "1" ]; then
        no "$label: total=$total but capped=\"$capped\" (want 1 — shown=0 < total means something WAS dropped)"
    else
        ok "$label: <$el shown=\"0\" total=\"$total\" capped=\"$capped\"> present and arithmetic"
    fi
}

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── arm 1: --for auto-bundle, candidates exist but none fits whole (autoEmitted.kept.empty()) ──────────
# pageRankDouble is a name-exact hit whose top-ranked auto-body candidates are real function bodies; a
# --pack-budget-bytes=64 floor is too tight for any of them (packBodies' own oversized-first-and-skip path).
run src --for="pageRankDouble" --pack-budget-bytes=64 --no-cache > "$TMP/for_budget.xml"
shownzero "$TMP/for_budget.xml" "arm1 (--for, candidates exist, budget too tight)"
grep -q 'bundle="auto" bodies="0" reason="budget"' "$TMP/for_budget.xml" \
    && ok "arm1: <ctx> still carries bundle=\"auto\" bodies=\"0\" reason=\"budget\" (unchanged, additive)" \
    || no "arm1: <ctx> lost its bundle=/reason= attribute"

# ── arm 2: --for auto-bundle, zero candidates from the start (autoBodyIds.empty()) ──────────────────────
# a query with no positive-score ranked surface at all — weak="1" fires for the same reason. `zzqqxx` is a
# single nonsense word, which the router sends to subtoken+body, so since the compact round it needs
# --auto-bodies to reach the auto BODY path this arm is about; arm 2b below asserts the same R9 contract
# on the shape the same query gets by default.
run src --for="zzqqxx" --auto-bodies --no-cache > "$TMP/for_none.xml"
shownzero "$TMP/for_none.xml" "arm2 (--for, no candidates at all)"
grep -q 'bundle="auto" bodies="0" reason="no_candidates"' "$TMP/for_none.xml" \
    && ok "arm2: <ctx> still carries bundle=\"auto\" bodies=\"0\" reason=\"no_candidates\" (unchanged, additive)" \
    || no "arm2: <ctx> lost its bundle=/reason= attribute"

# ── arm 2b: the COMPACT twin of arm 2 — same query, default posture (docs/EVALS.md, the T3
# route-narrowing round). The <hops> section is a budgeted section element like <bodies>, so it inherits
# the same rule: when there is nothing to show it must still SAY so, element and counts both.
run src --for="zzqqxx" --no-cache > "$TMP/for_none_compact.xml"
shownzero "$TMP/for_none_compact.xml" "arm2b (--for compact, no candidates at all)" hops
grep -q 'bundle="compact" bodies="0" reason="no_candidates"' "$TMP/for_none_compact.xml" \
    && ok "arm2b: <ctx> carries bundle=\"compact\" bodies=\"0\" reason=\"no_candidates\"" \
    || no "arm2b: <ctx> lost its compact bundle=/reason= attribute"

# ── arm 3: --pack-task, candidates exist but the section never clears its own floor ─────────────────────
run src --no-cache --pack-task="serialize signatures budget" --token-budget=50 > "$TMP/task_budget.xml"
shownzero "$TMP/task_budget.xml" "arm3 (--pack-task, candidates exist, budget too tight for the section)"

# ── arm 4: --pack-task, zero candidates (a nonsense task the ranker cannot match to anything) ────────────
run src --no-cache --pack-task="zzzzznonexistentconceptxyz1234" --token-budget=6000 > "$TMP/task_none.xml"
shownzero "$TMP/task_none.xml" "arm4 (--pack-task, no candidates at all)"

# ── arm 5 (decisive-arm sanity): the OPPOSITE case — bodies actually fitting — must still say shown=N,
#    N==total, capped="0", proving this gate is not accepting an ALWAYS-"shown=0" tag as a false pass.
run src --for="pageRankDouble" --no-cache > "$TMP/for_fits.xml"
FITS_TAG="$( grep -o '<bodies shown="[0-9]*"[^>]*>' "$TMP/for_fits.xml" | head -1 )"
FITS_SHOWN="$(  printf '%s' "$FITS_TAG" | sed -n 's/.*shown="\([0-9]*\)".*/\1/p' )"
case "$FITS_SHOWN" in
    0|"") no "arm5: default --for=\"pageRankDouble\" reports shown=\"${FITS_SHOWN:-?}\" (want >0 — the fit case must differ from the empty case)" ;;
    *)    ok "arm5: default --for=\"pageRankDouble\" reports shown=\"$FITS_SHOWN\" (the non-empty case is genuinely different)" ;;
esac

# ── arm 6: well-formed + deterministic across every shape this gate exercised ────────────────────────────
allok=1
for f in "$TMP/for_budget.xml" "$TMP/for_none.xml" "$TMP/task_budget.xml" "$TMP/task_none.xml"; do
    xmllint --noout "$f" 2>/dev/null || { no "arm6: $( basename "$f" ) is not well-formed XML"; allok=0; }
done
[ "$allok" = 1 ] && ok "arm6: every shape this gate exercised is xmllint-clean (G4)"
if [ "$( run src --for="pageRankDouble" --pack-budget-bytes=64 --no-cache )" = "$( run src --for="pageRankDouble" --pack-budget-bytes=64 --no-cache )" ]; then
    ok "arm6: arm1's shape is byte-identical run-to-run"
else
    no "arm6: arm1's shape is not deterministic"
fi

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1
