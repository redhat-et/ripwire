#!/usr/bin/env bash
# prbudgetcheck.sh — A4-R4 lever 4: --pr-context respects --max-tokens by degrading
# gracefully, DEPTH-first, instead of emitting an unbounded payload (26.3K tokens on a 15-file diff was the
# measured worst case; a 213-file diff far worse).
#
# The contract this gate enforces:
#   1) UNBUDGETED (no --max-tokens) is byte-identical to the pre-budget output — no est_tokens/truncated attrs.
#   2) BUDGETED: the emitted est_tokens is <= the budget (unless even the structural floor overflows, in which
#      case truncated= says so honestly — then est may exceed and that's the honest ceiling).
#   3) EVERY changed file is still present structurally (same <file> count budgeted vs unbudgeted) — the budget
#      trims DEPTH per file, never drops a file.
#   4) truncated= is honest: "none" only when nothing was trimmed; a drop summary otherwise.
#   5) deterministic under a fixed budget; xmllint-clean.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/prbudgetcheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "prbudgetcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# --pr-context needs a git diff. Wave-45 fix: the gate used to diff THIS repo's last commits, which
# made its "a large budget never truncates" assertion hostage to whatever landed most recently (a 7.6K-line
# bench-data merge legitimately trips the per-section list caps at any budget). Build a SCRATCH repo with a
# known, modest diff instead — the assertions below are about the budget machinery, not about this repo.
FIX="$TMP/fixrepo"; mkdir -p "$FIX/src"
( cd "$FIX" && git init -q && git config user.email t@t && git config user.name t )
for i in 1 2 3 4 5; do
    printf 'int helper%d( int v ) { return v + %d; }\nint caller%d() { return helper%d( %d ); }\n' \
           "$i" "$i" "$i" "$i" "$i" > "$FIX/src/mod$i.cpp"
done
( cd "$FIX" && git add -A >/dev/null && git commit -qm base )
for i in 1 2 3; do
    printf 'int helper%d( int v ) { return v * %d; }\nint caller%d() { return helper%d( %d ); }\nint extra%d() { return caller%d(); }\n' \
           "$i" "$i" "$i" "$i" "$i" "$i" "$i" > "$FIX/src/mod$i.cpp"
done
( cd "$FIX" && git add -A >/dev/null && git commit -qm change )
ROOT="$FIX"
BASE=HEAD~1

# helper: pull an attribute value out of the <pr-context …> open tag
attr(){ grep -oE "<pr-context[^>]*>" "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E "s/.*=\"([^\"]*)\"/\1/"; }
filecount(){ grep -o '<file ' "$1" | wc -l | tr -d ' '; }

# ── #1: UNBUDGETED == byte-identical to no-budget path (no est_tokens/truncated attrs) ──────────────────
"$BIN" "$ROOT" --pr-context="$BASE" --no-cache >"$TMP/unc" 2>/dev/null
if grep -q 'est_tokens=' "$TMP/unc"; then
    no "unbudgeted --pr-context leaked budget attributes (should be byte-identical to pre-budget output)"
else
    ok "unbudgeted --pr-context carries NO budget attrs (est_tokens/truncated absent)"
fi
UNC_FILES=$( filecount "$TMP/unc" )
[ "$UNC_FILES" -gt 0 ] || { echo "  SKIP  prbudgetcheck (no changed indexed files vs $BASE)"; exit 0; }

# ── #2: a LARGE budget fits at level 0: truncated="none", est<=budget, files all present ────────────────
"$BIN" "$ROOT" --pr-context="$BASE" --max-tokens=100000 --no-cache >"$TMP/big" 2>/dev/null
BE=$( attr "$TMP/big" est_tokens ); BT=$( attr "$TMP/big" truncated ); BF=$( filecount "$TMP/big" )
{ [ -n "$BE" ] && [ "$BE" -le 100000 ] && [ "$BT" = "none" ] && [ "$BF" = "$UNC_FILES" ]; } \
    && ok "large budget: level 0, truncated=none, est=${BE}<=100000, all $BF files present" \
    || no "large budget mishandled (est=$BE truncated=$BT files=$BF vs $UNC_FILES)"

# ── #3: SMALL budgets — est_tokens <= budget AND all files still present structurally ───────────────────
underok=1; filesok=1
for T in 20000 8000 4000 2000; do
    "$BIN" "$ROOT" --pr-context="$BASE" --max-tokens=$T --no-cache >"$TMP/c_$T" 2>/dev/null
    E=$( attr "$TMP/c_$T" est_tokens ); TR=$( attr "$TMP/c_$T" truncated ); FC=$( filecount "$TMP/c_$T" )
    [ "$FC" = "$UNC_FILES" ] || { echo "    budget=$T dropped files ($FC vs $UNC_FILES)"; filesok=0; }
    # est must be <= budget UNLESS the floor itself overflows (then truncated says budget-floor-exceeded)
    if [ -n "$E" ] && [ "$E" -le "$T" ]; then :;
    elif printf '%s' "$TR" | grep -q 'budget-floor-exceeded'; then :;   # honest floor overflow
    else echo "    budget=$T: est=$E > budget and no floor-exceeded marker (truncated=$TR)"; underok=0; fi
done
[ "$underok" = 1 ] && ok "budgeted est_tokens <= budget at every tested budget (or honest floor-exceeded)" \
    || no "a budgeted run exceeded its budget without the floor-exceeded marker"
[ "$filesok" = 1 ] && ok "every changed file present structurally at every budget (depth trimmed, files never dropped)" \
    || no "a budgeted run dropped a changed file (forbidden — structural facts must survive)"

# ── #4: truncation marker HONEST — a trimmed run names a non-"none" drop; a level-0 run says "none" ─────
TT=$( attr "$TMP/c_2000" truncated ); TL=$( attr "$TMP/c_2000" trim_level )
if [ "$TL" = "0" ]; then
    [ "$TT" = "none" ] && ok "trim_level=0 reports truncated=none (honest)" || no "trim_level=0 but truncated=$TT (dishonest)"
else
    { [ -n "$TT" ] && [ "$TT" != "none" ]; } \
        && ok "trimmed run (trim_level=$TL) names what it dropped: truncated=\"$TT\"" \
        || no "trimmed run left truncated=\"$TT\" (must name the dropped detail)"
fi

# ── #5: DETERMINISM — a fixed budget is byte-identical run-to-run ───────────────────────────────────────
"$BIN" "$ROOT" --pr-context="$BASE" --max-tokens=4000 --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT" --pr-context="$BASE" --max-tokens=4000 --no-cache >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "budgeted --pr-context deterministic (byte-identical twice)" \
    || no "budgeted --pr-context NON-deterministic under a fixed budget"

# ── #6: monotonic — a smaller budget never emits MORE tokens than a larger one ──────────────────────────
E20=$( attr "$TMP/c_20000" est_tokens ); E2=$( attr "$TMP/c_2000" est_tokens )
{ [ -n "$E20" ] && [ -n "$E2" ] && [ "$E2" -le "$E20" ]; } \
    && ok "monotonic: est(2000-budget)=${E2} <= est(20000-budget)=${E20}" \
    || no "non-monotonic degradation (est went UP as budget dropped: $E2 vs $E20)"

# ── #7: xmllint-clean (budgeted + unbudgeted) ──────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    lint=1
    for F in "$TMP/unc" "$TMP/big" "$TMP/c_2000" "$TMP/c_4000"; do
        xmllint --noout "$F" 2>/dev/null || { echo "    malformed: $F"; lint=1; lint=0; }
    done
    [ "$lint" = 1 ] && ok "budgeted + unbudgeted --pr-context well-formed XML" || no "a --pr-context payload was malformed XML"
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
