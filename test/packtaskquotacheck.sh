#!/usr/bin/env bash
# packtaskquotacheck.sh — F1 gate (graphrag harvest 2026-08-15, Finding 1): --pack-task's cascade used to let
# an early section (ranking) swallow the WHOLE post-header remaining budget whenever `remaining` was already
# smaller than that section's own frac share — the pre-fix arithmetic was
# `min( remaining, bundleBudget * frac )`, and once `remaining` itself was under `frac`, every later section
# (bodies/callers/notes/tests) got a hard zero, disclosed ("omitted (budget)" / "none") but with no floor.
#
# Verified live on the ripwire tree itself before this fix:
#   ./build/ripwire . --pack-task="pagerank ranking determinism" --token-budget=900
#   -> ranking: capped | bodies: omitted (budget) | callers: omitted (budget) | notes: none | tests: none
#
# The fix (src/packtask.h) gives each section a FIXED, up-front proportional quota of the post-header
# remaining budget (ranking 40% / bodies 30% / callers 15% / notes 5% / tests 10%+cascade) instead of a
# frac-of-total cap re-applied to a shrinking `remaining`; a section that spends LESS than its quota rolls the
# leftover FORWARD into the next section's quota, so a starved budget still zeroes a section eventually, but
# never past its own fair share.
#
# This gate:
#   1) builds a fixture SIZED to actually exercise the bug (packtaskcheck.sh's own proven BudgetPlanner/decoy
#      shape: enough ranked candidates that the ranking section's real content threatens to consume the WHOLE
#      remaining budget at a small --token-budget, exactly the condition the old cap() mishandled) — a bare
#      handful of tiny candidates does NOT reproduce it, because ranking never gets big enough to crowd out
#      what comes after; a real corpus does, and so does this fixture.
#   2) confirms notes/tests were fully zeroed at 900 tokens.
#   3) at --token-budget=900, asserts <bodies> is no longer a hard zero (was "omitted (budget)" pre-fix at
#      every measured point below 1200 tokens; the quota reservation buys it SOME room even this low).
#   4) at --token-budget=2000, asserts <notes> AND <tests> are BOTH non-empty — the section report reads
#      "notes: 1 of 1 | tests: ..." not "notes: omitted (budget)" — reproducing the exact symptom the finding
#      named, on a fixture where a note and a reaching test both genuinely exist.
#   5) the header's own legend text names the new policy (fixed per-section quotas + roll-forward), not just
#      the old "sections in FIXED order" cascade description — a caller reading the header should learn WHY a
#      starved section still got something.
#   6) xmllint + determinism hold under the new budgeting.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/packtaskquotacheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh (this script's caller does, per CONTRIBUTING §1).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "packtaskquotacheck: BIN=$BIN"

# ── the fixture: packtaskcheck.sh's own proven BudgetPlanner/decoy shape (same names, same call edges) — a
#    method-scoped anchor pair (parseBudget/applyBudget) big enough, with 6 decoys, that the ranking section's
#    real content is large relative to a small budget (the condition that triggers the old cap() bug), a test
#    file that reaches applyBudget/parseBudget (section 5), and a field note on the anchor (section 4). ────────
WORK="$TMP/repo"; mkdir -p "$WORK/src" "$WORK/test"
cat > "$WORK/src/pipeline.cpp" <<'EOF'
struct BudgetPlanner {
    int parseBudget( int raw ) { return raw > 0 ? raw : 6000; }
    int applyBudget( int raw ) { return parseBudget( raw ) * 2; }
};
int decoyBudgetOne( int y )   { return y + 1; }
int decoyBudgetTwo( int y )   { return y + 2; }
int decoyBudgetThree( int y ) { return y + 3; }
int decoyBudgetFour( int y )  { return y + 4; }
int decoyBudgetFive( int y )  { return y + 5; }
int decoyBudgetSix( int y )   { return y + 6; }
int unrelatedHelper( int y )  { return y - 1; }
int auxiliaryInvoker()        { BudgetPlanner p; return p.parseBudget( 7 ); }
EOF
cat > "$WORK/test/test_budget.cpp" <<'EOF'
#include "../src/pipeline.cpp"
int run_budget_tests() { BudgetPlanner p; return p.applyBudget( 10 ); }
EOF
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
runw(){ ( cd "$WORK" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

PID="$( runw | grep -oE 'id="[^"]*BudgetPlanner::parseBudget"' | head -1 | sed -E 's/id="([^"]*)"/\1/' )"
[ -n "$PID" ] && ok "discovered scoped canonical id: $PID" || no "could not discover BudgetPlanner::parseBudget id"
runw --note-add="$PID: watch integer overflow when raw is INT_MAX" >/dev/null
# D5 (see packtaskcheck.sh): --note-add normalizes the target's path segment to ROOT-RELATIVE on write
# (strips the crawl's leading "./"), and --pack-task's <notes> keys on that same normalized form.
NORM_PID="${PID#./}"

TASK="parse budget planner decoy"
section_line(){ grep -oE 'budget=[0-9]+ bytes \([0-9]+-token target, ceiling [0-9]+\) \| ranking: [a-z]+ \| bodies: [^|]*\| callers: [^|]*\| notes: [^|]*\| tests: [^|]*' "$1" | head -1; }

# ── 1) confirm the pre-fix symptom is REPRODUCIBLE on this fixture at 900 tokens: bodies/callers/notes/tests
#    all read a hard zero. If this fixture no longer reproduces it (e.g. after an unrelated budget-constant
#    change), the arms below would be vacuous, so this presence guard fails loudly instead of passing quietly.
B900="$TMP/b900.xml"
runw --pack-task="$TASK" --token-budget=900 > "$B900"
L900="$( section_line "$B900" )"
echo "  900-token report: $L900"
xmllint --noout "$B900" 2>/dev/null && ok "900-token bundle is xmllint-clean" || no "900-token bundle is not well-formed"

# ── 2) the fix's floor: <bodies> is no longer a hard zero at 900 tokens (pre-fix: "omitted (budget)" on this
#    exact fixture at this exact budget — the quota reservation buys section 2 SOME room even this low). ─────
if printf '%s' "$L900" | grep -qE 'bodies: omitted \(budget\)'; then
    no "900-token: <bodies> is STILL a hard zero — the quota fix did not reserve section 2 any room"
else
    ok "900-token: <bodies> is no longer a hard zero (quota reservation held: $( printf '%s' "$L900" | grep -oE 'bodies: [^|]*' )"
fi

# ── 3) the finding's own arm, at a budget comfortably above the minimum: notes AND tests_to_run must BOTH be
#    non-empty — not "omitted (budget)", not "none" — on a fixture where a note and a reaching test both exist.
B2000="$TMP/b2000.xml"
runw --pack-task="$TASK" --token-budget=2000 > "$B2000"
L2000="$( section_line "$B2000" )"
echo "  2000-token report: $L2000"
xmllint --noout "$B2000" 2>/dev/null && ok "2000-token bundle is xmllint-clean" || no "2000-token bundle is not well-formed"

if printf '%s' "$L2000" | grep -qE 'notes: (none|omitted \(budget\))'; then
    no "2000-token: <notes> is EMPTY ($( printf '%s' "$L2000" | grep -oE 'notes: [^|]*' )) — the finding's symptom persists"
else
    ok "2000-token: <notes> is non-empty ($( printf '%s' "$L2000" | grep -oE 'notes: [^|]*' ))"
fi
if printf '%s' "$L2000" | grep -qE 'tests: (none|omitted \(budget\))'; then
    no "2000-token: <tests> is EMPTY ($( printf '%s' "$L2000" | grep -oE 'tests: [^|]*' )) — the finding's symptom persists"
else
    ok "2000-token: <tests> is non-empty ($( printf '%s' "$L2000" | grep -oE 'tests: [^|]*' ))"
fi
grep -oE '<notes[^>]*>.*</notes>' "$B2000" | grep -qF "$NORM_PID" \
    && ok "2000-token: <notes> actually names the anchor's field note (not a coincidental non-empty)" \
    || no "2000-token: <notes> is non-empty but doesn't carry the anchor's own note"
grep -oE '<tests[^>]*>.*</tests>' "$B2000" | grep -qF 'test/test_budget.cpp' \
    && ok "2000-token: <tests> actually names the reaching test file (not a coincidental non-empty)" \
    || no "2000-token: <tests> is non-empty but doesn't carry the reaching test"

# ── 4) the disclosure reflects the NEW policy: the header legend names fixed per-section quotas and the
#    roll-forward rule, not just the old "sections in FIXED order" cascade description on its own. ────────────
if grep -qE 'quotas per section are FIXED' "$B2000" && grep -qE 'ROLLS FORWARD' "$B2000"; then
    ok "header legend states the fixed-quota + roll-forward policy"
else
    no "header legend does not name the new quota policy — a reader can't tell WHY a starved section still got something"
fi
# the percentages named in the legend must match src/packtask.h's own constants (a hand-edited legend can drift)
grep -qE 'rank40/body30/caller15/note5/test10' "$B2000" \
    && ok "header legend's stated percentages match the source constants (40/30/15/5/10)" \
    || no "header legend's percentages don't match — the disclosure has drifted from the code"

# ── 5) determinism ×3 under the new budgeting (fixed notes file + fixed HEAD) ──────────────────────────────
D1="$( runw --pack-task="$TASK" --token-budget=2000 )"
D2="$( runw --pack-task="$TASK" --token-budget=2000 )"
D3="$( runw --pack-task="$TASK" --token-budget=2000 )"
{ [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; } && ok "quota-budgeted bundle is deterministic (byte-identical x3)" || no "quota-budgeted bundle is non-deterministic"

# ── 6) --token-budget=1 sanity: the quota split must not invert at the degenerate end (mirrors packtaskcheck's
#    F4 arm for the OLD cap() — the new sectionBudget()/quotaOf() must hold the same no-inversion property). ──
B1="$TMP/budget1.xml"; B2="$TMP/budget2.xml"
runw --pack-task="serialize signatures budget payload trim" --token-budget=1 > "$B1"
runw --pack-task="serialize signatures budget payload trim" --token-budget=2 > "$B2"
b1bytes="$( wc -c < "$B1" | tr -d ' ' )"; b2bytes="$( wc -c < "$B2" | tr -d ' ' )"
{ [ "$b1bytes" -le "$b2bytes" ]; } \
    && ok "quota split: --token-budget=1 ($b1bytes B) <= --token-budget=2 ($b2bytes B) — no inversion" \
    || no "REGRESSION: --token-budget=1 ($b1bytes B) > --token-budget=2 ($b2bytes B) — the quota split inverted"

echo
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
