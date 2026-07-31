#!/usr/bin/env bash
# ordercheck.sh — L5 (AUDIT5) surface-consolidation gate: --order=stable|important-first|important-last
# is now the canonical emit-order flag; --stable/--most-important-last/--no-auto-order are hidden aliases
# (still fully functional, dropped from --help, each prints a ONE-LINE stderr deprecation the first time
# used in a run). Nothing is removed (PLAN_audit5Public2026.md "Hard parts — decided" / "L5 surface
# dispositions"). This gate asserts:
#   (a) ALIAS EQUIVALENCE — --order=stable == --stable, --order=important-last == --most-important-last,
#       --order=important-first == --no-auto-order, byte-identical stdout on both a small (never-auto-
#       flips) and a large (crosses kFillOrderThreshold) input.
#   (b) DEPRECATION LINES — each old spelling prints exactly one stderr line naming --order= the first
#       time it's used in a run; --order= itself prints nothing; combining multiple old spellings in ONE
#       run still prints only ONE line total (not one per flag).
#   (c) --order rejects an unknown value, loudly, exit nonzero.
#   (d) --help lists --order= and no longer lists the three old spellings (--no-stable is untouched and
#       stays); a stale binary without the L5 change would fail this.
#   (e) determinism + xmllint-clean on the --order= path.
#
# Usage:  test/ordercheck.sh   |   RIPWIRE_BIN=asan/ripwire test/ordercheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "ordercheck: BIN=$BIN"

# ── (a) ALIAS EQUIVALENCE — small fixture (est_tokens well under kFillOrderThreshold=16000, so the
#    explicit flags are the only thing deciding order; auto-flip never engages here) ──────────────────
STABLE_NEW="$(  "$BIN" test/fixture --no-cache --order=stable            2>/dev/null )"
STABLE_OLD="$(  "$BIN" test/fixture --no-cache --stable                  2>/dev/null )"
[ -n "$STABLE_NEW" ] && [ "$STABLE_NEW" = "$STABLE_OLD" ] \
    && ok "--order=stable byte-identical to --stable (small fixture)" \
    || no "--order=stable diverged from --stable"

LAST_NEW="$( "$BIN" test/fixture --no-cache --order=important-last       2>/dev/null )"
LAST_OLD="$( "$BIN" test/fixture --no-cache --most-important-last        2>/dev/null )"
[ -n "$LAST_NEW" ] && [ "$LAST_NEW" = "$LAST_OLD" ] \
    && ok "--order=important-last byte-identical to --most-important-last (small fixture)" \
    || no "--order=important-last diverged from --most-important-last"

# ── (a2) --order=important-first vs --no-auto-order — meaningful only past kFillOrderThreshold, so use
#    src/ --top-k=100000 (the same large input fillordercheck.sh uses to exercise T3's auto-flip) ──────
FIRST_NEW="$( "$BIN" src --no-cache --top-k=100000 --order=important-first  2>/dev/null )"
FIRST_OLD="$( "$BIN" src --no-cache --top-k=100000 --no-auto-order          2>/dev/null )"
DEFAULT_BIG="$( "$BIN" src --no-cache --top-k=100000                        2>/dev/null )"
[ -n "$FIRST_NEW" ] && [ "$FIRST_NEW" = "$FIRST_OLD" ] \
    && ok "--order=important-first byte-identical to --no-auto-order (large input, past threshold)" \
    || no "--order=important-first diverged from --no-auto-order"
[ -n "$DEFAULT_BIG" ] && [ "$FIRST_NEW" != "$DEFAULT_BIG" ] \
    && ok "--order=important-first differs from the unflagged default on a large input (proves the alias actually suppresses T3 auto-flip, not a no-op)" \
    || no "--order=important-first did not differ from the default — the auto-flip-suppression isn't wired"

# ── (b) DEPRECATION LINES ────────────────────────────────────────────────────────────────────────────
ERR1="$( "$BIN" test/fixture --no-cache --stable                  2>&1 >/dev/null )"
printf '%s\n' "$ERR1" | grep -qE 'deprecated.*--order=stable' \
    && ok "--stable prints a one-line deprecation pointing at --order=stable" \
    || no "--stable deprecation message missing/wrong (got: $ERR1)"

ERR2="$( "$BIN" test/fixture --no-cache --most-important-last     2>&1 >/dev/null )"
printf '%s\n' "$ERR2" | grep -qE 'deprecated.*--order=important-last' \
    && ok "--most-important-last prints a one-line deprecation pointing at --order=important-last" \
    || no "--most-important-last deprecation message missing/wrong (got: $ERR2)"

ERR3="$( "$BIN" src --no-cache --top-k=1 --no-auto-order           2>&1 >/dev/null )"
printf '%s\n' "$ERR3" | grep -qE 'deprecated.*--order=important-first' \
    && ok "--no-auto-order prints a one-line deprecation pointing at --order=important-first" \
    || no "--no-auto-order deprecation message missing/wrong (got: $ERR3)"

ERR_NEW="$( "$BIN" test/fixture --no-cache --order=stable         2>&1 >/dev/null )"
printf '%s\n' "$ERR_NEW" | grep -qi 'deprecated' \
    && no "--order= itself must never print a deprecation line (got: $ERR_NEW)" \
    || ok "--order= prints no deprecation line"

# multiple old spellings in ONE run → only ONE deprecation line total, not one per flag
ERR_COMBO="$( "$BIN" src --no-cache --top-k=1 --stable --no-auto-order  2>&1 >/dev/null )"
comboCount="$( printf '%s\n' "$ERR_COMBO" | grep -c 'is deprecated' )"
[ "$comboCount" -eq 1 ] \
    && ok "combining two old spellings in one run prints exactly ONE deprecation line (first-use-in-a-run rule)" \
    || no "combining old spellings printed $comboCount deprecation lines (expected 1)"

# ── (c) --order rejects an unknown value ─────────────────────────────────────────────────────────────
BADOUT="$( "$BIN" test/fixture --no-cache --order=bogus 2>&1 >/dev/null )"
"$BIN" test/fixture --no-cache --order=bogus >/dev/null 2>/dev/null
BADRC=$?
[ "$BADRC" -ne 0 ] && printf '%s\n' "$BADOUT" | grep -qi 'order' \
    && ok "--order=bogus refuses loudly (exit $BADRC, message names --order)" \
    || no "--order=bogus did not refuse loudly (exit $BADRC)"

# ── (d) --help surface ───────────────────────────────────────────────────────────────────────────────
HELP="$( "$BIN" --help 2>&1 )"
printf '%s\n' "$HELP" | grep -q -- '--order=' \
    && ok "--help lists --order=" || no "--help is missing --order="
printf '%s\n' "$HELP" | grep -q -- '--no-stable' \
    && ok "--help still lists --no-stable (unrelated to --order, not deprecated)" || no "--help lost --no-stable"
if printf '%s\n' "$HELP" | grep -qF -- '--most-important-last' \
   || printf '%s\n' "$HELP" | grep -qF -- '--no-auto-order' \
   || printf '%s\n' "$HELP" | grep -qF -- '--stable'; then
    no "--help still advertises a deprecated old spelling (--most-important-last / --stable / --no-auto-order)"
else
    ok "--help no longer advertises --most-important-last / --stable / --no-auto-order"
fi

# ── (e) determinism + xmllint on the --order= path ──────────────────────────────────────────────────
"$BIN" test/fixture --no-cache --order=stable >"$TMP/d1.xml" 2>/dev/null
"$BIN" test/fixture --no-cache --order=stable >"$TMP/d2.xml" 2>/dev/null
diff -q "$TMP/d1.xml" "$TMP/d2.xml" >/dev/null \
    && ok "determinism (--order=stable byte-identical run-to-run)" \
    || no "non-deterministic --order=stable output"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/d1.xml" 2>/dev/null && ok "xml well-formed (--order=stable)" || no "xml malformed (--order=stable)"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
