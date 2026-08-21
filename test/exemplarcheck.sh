#!/usr/bin/env bash
# exemplarcheck.sh — the Wave-Q Q7 --exemplar verb gate.
#
#   test/exemplarcheck.sh                       # uses build/ripwire on test/exemplarfix
#   RIPWIRE_BIN=asan/ripwire test/exemplarcheck.sh
#
# --exemplar=KIND|TASK returns the repo's BEST-IN-CLASS instance of what the agent is about to write,
# selected by ROLE (kind + tested/fan-in/ccx composite, id tie-break) — NEVER by text similarity. This gate:
#   * picks the high-fan-in / low-ccx / tested sibling over a worse one on the crafted test/exemplarfix corpus.
#   * a TASK argument resolves to the top-match's kind, then the SAME role-selection (not the lexical winner).
#   * tested= participates: exercised in a scratch project OUTSIDE test/ (a test/ path is itself a test-path).
#   * determinism (run twice → byte-identical), well-formed XML.
#   * a no-candidate kind degrades cleanly (clear message, nonzero exit, no crash/hang).
# Mutation-tested: the "picks goodHelper" assertion is checked to actually FAIL on the wrong expected name.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/exemplarfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "exemplarcheck: BIN=$BIN  CORPUS=$CORPUS"

exemhdr(){ printf '%s' "$1" | grep -o '<exemplar[^>]*>' | head -1; }   # the <exemplar …> element from an output

# ── 1) KIND token → best-in-class by ROLE ─────────────────────────────────────────────────────────────
# exemplarfix has two free-function siblings: goodHelper (fan-in 5, ccx 0) and messyHelper (fan-in 0,
# ccx 10), plus four thin callers. --exemplar=fn must pick goodHelper (highest fan-in, lowest ccx).
FN1="$( "$BIN" "$CORPUS" --no-cache --exemplar=fn 2>/dev/null )"
HDR="$( exemhdr "$FN1" )"
printf '%s' "$HDR" | grep -q 'n="goodHelper"' \
    && ok "exemplar=fn picks the high-fan-in/low-ccx sibling (goodHelper): $HDR" \
    || no "exemplar=fn picked the wrong instance: $HDR"
# it must NOT pick the messy sibling.
printf '%s' "$HDR" | grep -q 'n="messyHelper"' && no "exemplar=fn wrongly picked messyHelper" || ok "exemplar=fn avoids the worse sibling (messyHelper)"
# the winner's BODY is emitted (packBodies) so the agent has an imitation target, not just a pointer.
printf '%s' "$FN1" | grep -q '<b t="fn"[^>]*n="goodHelper"' && ok "exemplar emits the winner's full body (<b>)" || no "exemplar body missing"

# ── 2) TASK argument → resolves to a KIND, then role-selection (not the lexical winner) ────────────────
# "helper function" isn't a kind token → the top lexical match's kind (fn) is used, then goodHelper wins
# by ROLE. Proves selection is by role, not by string similarity to the task words.
TASK1="$( "$BIN" "$CORPUS" --no-cache --exemplar="helper function" 2>/dev/null )"
THDR="$( exemhdr "$TASK1" )"
printf '%s' "$THDR" | grep -q 'kind="fn"' && printf '%s' "$THDR" | grep -q 'n="goodHelper"' \
    && ok "exemplar=TASK resolves kind then picks by ROLE (goodHelper): $THDR" \
    || no "exemplar=TASK role-selection wrong: $THDR"

# ── 3) determinism (byte-identical run-to-run) + well-formed XML ──────────────────────────────────────
"$BIN" "$CORPUS" --no-cache --exemplar=fn >"$TMP/e1" 2>/dev/null
"$BIN" "$CORPUS" --no-cache --exemplar=fn >"$TMP/e2" 2>/dev/null
diff -q "$TMP/e1" "$TMP/e2" >/dev/null && ok "determinism (--exemplar byte-identical run-to-run)" || no "non-deterministic --exemplar output"
command -v xmllint >/dev/null 2>&1 && { printf '%s' "$FN1" | xmllint --noout - 2>/dev/null && ok "xml well-formed (--exemplar)" || no "xml malformed (--exemplar)"; } || ok "xml well-formed (xmllint absent — skipped)"

# ── 4) tested= PARTICIPATES — exercised OUTSIDE test/ (a test/ path is itself a test-path) ─────────────
# Two same-kind siblings where the LOWER-fan-in one is TESTED and the higher-fan-in one is not — tested
# ranks FIRST in the composite, so the tested sibling must win. Proves tested= is the primary sort key.
SC="$TMP/proj"; mkdir -p "$SC/tests"
cat >"$SC/lib.py" <<'PY'
def safe(x):
    return x
def risky(x):
    return x
def u1(x): return risky(x)
def u2(x): return risky(x)
def u3(x): return risky(x)
PY
# safe() has fan-in 0 but IS tested; risky() has fan-in 3 but is NOT tested → tested wins the composite.
cat >"$SC/tests/test_lib.py" <<'PY'
from lib import safe
def test_it():
    assert safe(1) == 1
PY
SCOUT="$( "$BIN" "$SC" --no-cache --exemplar=fn 2>/dev/null )"
SCHDR="$( exemhdr "$SCOUT" )"
printf '%s' "$SCHDR" | grep -q 'n="safe"' && printf '%s' "$SCHDR" | grep -q 'tested="1"' \
    && ok "tested= is the primary role key (tested safe beats higher-fan-in untested risky): $SCHDR" \
    || no "tested= did not win the composite: $SCHDR"

# ── 5) MUTATION self-test — a WRONG expected name must be detected as a failure (assertion is live) ────
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        h="$( exemhdr "$FN1" )"
        if printf '%s' "$h" | grep -q 'n="messyHelper"'; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (asserting the WRONG winner is correctly detected)" \
                       || no "mutation self-test broke — a wrong winner did NOT fail (assertion unsound)"

# ── 6) no-candidate kind degrades cleanly (clear message, nonzero exit, no crash) ─────────────────────
# exemplarfix has no interface → --exemplar=iface must exit nonzero with a message, not crash/hang.
ERR="$( "$BIN" "$CORPUS" --no-cache --exemplar=iface 2>&1 >/dev/null )"; RC=$?
{ [ "$RC" -ne 0 ] && printf '%s' "$ERR" | grep -qi 'no iface'; } \
    && ok "no-candidate kind degrades cleanly (nonzero exit + message)" \
    || no "no-candidate case did not degrade cleanly (rc=$RC err=$ERR)"

# ── 7) A3-F5 CONTRACT — the ccx ceiling + fixture penalty + task→kind floor, on THIS repo ──────────────
# Regression guards for the two reproduced betrayals: whole-repo --exemplar=fn returned `ingest` (ccx=294 —
# the single most complex fn in the tree) as the shape to imitate; a "test gate shell script" task mapped to
# kind=cls and returned a 3-line synthetic TEST FIXTURE. The fix binds ccx hard, de-prioritizes fixture paths,
# and falls back to fn on a weak task match. These assertions run against the ripwire repo itself.
SELF="$ROOT"
CEIL=60   # kExemplarCcxCeiling = 4 × kCcxBar(15); see src/exemplar.h. A repo-root pick must be at/under it.

# (1) repo-root --exemplar=fn: winner ccx must be under the ceiling AND must NOT be `ingest` (the ccx=294 blob).
SELFFN="$( "$BIN" "$SELF" --no-cache --exemplar=fn 2>/dev/null )"
SHDR="$( exemhdr "$SELFFN" )"
SCCX="$( printf '%s' "$SHDR" | grep -o 'ccx="[0-9]*"' | head -1 | grep -o '[0-9]*' )"
{ [ -n "$SCCX" ] && [ "$SCCX" -le "$CEIL" ]; } \
    && ok "repo-root exemplar=fn winner ccx ($SCCX) <= ceiling ($CEIL): $SHDR" \
    || no "repo-root exemplar=fn winner ccx ($SCCX) exceeds ceiling ($CEIL): $SHDR"
printf '%s' "$SHDR" | grep -q 'n="ingest"' \
    && no "repo-root exemplar=fn STILL returns the ccx=294 blob ingest: $SHDR" \
    || ok "repo-root exemplar=fn no longer returns the ingest blob"

# (2) repo-root --exemplar=fn must NOT win from a test/*fix* fixture path (fixtures are trivially low-ccx stubs).
SPATH="$( printf '%s' "$SHDR" | grep -o 'p="[^"]*"' | head -1 )"
printf '%s' "$SPATH" | grep -qE 'p="[^"]*/test/[^"]*fix' \
    && no "repo-root exemplar=fn winner is under a test fixture path: $SPATH" \
    || ok "repo-root exemplar=fn winner is NOT a test fixture ($SPATH)"

# (3) src-only --exemplar=fn still returns a sane pick (getIndex here, or an equal-quality clean fn).
SRCFN="$( "$BIN" "$SELF/src" --no-cache --exemplar=fn 2>/dev/null )"
SRCHDR="$( exemhdr "$SRCFN" )"
SRCCCX="$( printf '%s' "$SRCHDR" | grep -o 'ccx="[0-9]*"' | head -1 | grep -o '[0-9]*' )"
{ [ -n "$SRCCCX" ] && [ "$SRCCCX" -le "$CEIL" ] && ! printf '%s' "$SRCHDR" | grep -q 'over_ccx_bar'; } \
    && ok "src-only exemplar=fn is a sane clean pick (ccx $SRCCCX <= $CEIL): $SRCHDR" \
    || no "src-only exemplar=fn regressed: $SRCHDR"

# (4) weak task→kind: a non-code task with no real name match falls back to kind=fn + low_confidence=1
#     (must NOT confidently return a fixture class, the original Failure 2).
# NOTE: the probe phrase must contain NO repo vocabulary or it stops being weak — the original
# "test gate ... CLI flag" phrase rotted when --test-gate/testgatecheck.sh shipped.
WEAK="$( "$BIN" "$SELF" --no-cache --exemplar="quarterly payroll tax withholding reconciler" 2>/dev/null )"
WHDR="$( exemhdr "$WEAK" )"
{ printf '%s' "$WHDR" | grep -q 'kind="fn"' && printf '%s' "$WHDR" | grep -q 'low_confidence="1"'; } \
    && ok "weak task match falls back to kind=fn with low_confidence=1: $WHDR" \
    || no "weak task match did not degrade honestly: $WHDR"
printf '%s' "$WHDR" | grep -qE 'p="[^"]*/test/[^"]*fix' \
    && no "weak task match STILL returns a test-fixture pick: $WHDR" \
    || ok "weak task match does not return a fixture pick"

# (5) determinism on THIS repo (the fix must stay byte-stable run-to-run at repo scale).
"$BIN" "$SELF" --no-cache --exemplar=fn >"$TMP/s1" 2>/dev/null
"$BIN" "$SELF" --no-cache --exemplar=fn >"$TMP/s2" 2>/dev/null
diff -q "$TMP/s1" "$TMP/s2" >/dev/null && ok "repo-root exemplar=fn byte-identical run-to-run" || no "repo-root exemplar=fn non-deterministic"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
