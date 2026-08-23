#!/usr/bin/env bash
# expandsibscheck.sh — V1 gate (octocode F2, 2026-08-15 harvest): --expand's <b> body now carries sibs=/inc=,
# a per-file context summary — the OTHER symbols defined in the same file (names only) and the file's own
# #include/import targets — so an agent reading one body no longer needs a second --outline call just to
# learn what else lives there. Built ONCE per packBodies call from a per-file table (src/serialize.h
# FileExpandContext / buildFileExpandContexts), not per body.
#
# THE CONTRACT:
#   - sibs="a,b,c" sibs_total="N" [sibs_capped="1"]  — every OTHER def in the file (self excluded), capped
#     at kMaxExpandSibs=40, sibs_total is the TRUE count (never affected by the cap).
#   - inc="x.h,y.h" inc_total="N" [inc_capped="1"]    — the file's own #include/import targets, capped at
#     kMaxExpandIncludes=24, inc_total the TRUE count.
#   - BOTH absent when the count is 0 — a documented zero (model.h's skippedOversize convention: absence
#     means "checked, found none", never "not computed").
#   - withFileContext is opt-in on packBodies (default false): every OTHER caller (--for auto-body,
#     --pack-task, --detail, --around, MCP `exemplar`) stays byte-identical — arm (D) pins that.
#
# Fixtures (test/expandsibsfix/): basic.c (2 siblings, 2 includes — no cap), lonely.c (0 of either — the
# absence case), manyfn.c (44 siblings / 30 includes — one over each cap, by construction).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/expandsibscheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/expandsibsfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ]  || { echo "no test/expandsibsfix directory"; exit 2; }
cd "$ROOT"
echo "expandsibscheck: BIN=$BIN  FIX=$FIX"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── (A) basic.c: 2 siblings, 2 includes — present, exact, no cap disclosure ────────────────────────────
"$BIN" "$FIX" --expand=alphaFn --top-k=0 --no-cache >"$TMP/basic.xml" 2>/dev/null
BTAG="$( grep -oE '<b [^>]*>' "$TMP/basic.xml" | head -1 )"
printf '%s' "$BTAG" | grep -q 'sibs="betaFn,gammaFn"' \
    && ok "(A) alphaFn's sibs= lists betaFn,gammaFn in source order" \
    || no "(A) alphaFn's sibs= wrong or missing: $BTAG"
printf '%s' "$BTAG" | grep -q 'sibs_total="2"' \
    && ok "(A) sibs_total=\"2\" (exact, self excluded)" || no "(A) sibs_total missing/wrong: $BTAG"
printf '%s' "$BTAG" | grep -q 'sibs_capped=' \
    && no "(A) sibs_capped= present but the list is NOT truncated (2 <= cap)" \
    || ok "(A) no sibs_capped= — the uncapped case stays undecorated"
printf '%s' "$BTAG" | grep -q 'inc="foo.h,bar.h"' \
    && ok "(A) inc= lists foo.h,bar.h in source order" || no "(A) inc= wrong or missing: $BTAG"
printf '%s' "$BTAG" | grep -q 'inc_total="2"' \
    && ok "(A) inc_total=\"2\"" || no "(A) inc_total missing/wrong: $BTAG"
printf '%s' "$BTAG" | grep -q 'inc_capped=' \
    && no "(A) inc_capped= present but the list is NOT truncated (2 <= cap)" \
    || ok "(A) no inc_capped= — the uncapped case stays undecorated"

# ── (B) lonely.c: zero siblings, zero includes — BOTH attributes absent (a documented zero) ────────────
"$BIN" "$FIX" --expand=lonelyFn --top-k=0 --no-cache >"$TMP/lonely.xml" 2>/dev/null
if grep -q 'sibs=' "$TMP/lonely.xml"; then
    no "(B) lonelyFn (the only def in its file) still carries sibs= — should be absent"
else
    ok "(B) lonelyFn: no sibs= (zero siblings, documented by absence)"
fi
if grep -q ' inc=' "$TMP/lonely.xml"; then
    no "(B) lonely.c (no #include) still carries inc= — should be absent"
else
    ok "(B) lonely.c: no inc= (zero includes, documented by absence)"
fi

# ── (C) manyfn.c: 44 siblings (cap 40) / 30 includes (cap 24) — BOTH capped, BOTH totals true ───────────
"$BIN" "$FIX" --expand=manyFn000 --top-k=0 --no-cache >"$TMP/many.xml" 2>/dev/null
MTAG="$( grep -oE '<b [^>]*>' "$TMP/many.xml" | head -1 )"
printf '%s' "$MTAG" | grep -q 'sibs_total="44"' \
    && ok "(C) sibs_total=\"44\" — the TRUE count, unaffected by the cap" || no "(C) sibs_total wrong: $MTAG"
printf '%s' "$MTAG" | grep -q 'sibs_capped="1"' \
    && ok "(C) sibs_capped=\"1\" discloses the truncation" || no "(C) sibs_capped=\"1\" missing: $MTAG"
SIBS_SHOWN="$( printf '%s' "$MTAG" | grep -oE 'sibs="[^"]*"' | tr ',' '\n' | grep -c . )"
[ "$SIBS_SHOWN" = 40 ] && ok "(C) exactly 40 sibling names shown (kMaxExpandSibs)" \
                       || no "(C) sibs= shows $SIBS_SHOWN names, want exactly 40"
SIBS_VALUE="$( printf '%s' "$MTAG" | grep -oE 'sibs="[^"]*"' )"
printf '%s' "$SIBS_VALUE" | grep -qE '(^|,)manyFn000(,|$)' \
    && no "(C) manyFn000 lists ITSELF as a sibling (self-exclusion broken): $SIBS_VALUE" \
    || ok "(C) manyFn000 does not list itself as a sibling"
printf '%s' "$MTAG" | grep -q 'inc_total="30"' \
    && ok "(C) inc_total=\"30\" — the TRUE count, unaffected by the cap" || no "(C) inc_total wrong: $MTAG"
printf '%s' "$MTAG" | grep -q 'inc_capped="1"' \
    && ok "(C) inc_capped=\"1\" discloses the truncation" || no "(C) inc_capped=\"1\" missing: $MTAG"
INC_SHOWN="$( printf '%s' "$MTAG" | grep -oE ' inc="[^"]*"' | tr ',' '\n' | grep -c . )"
[ "$INC_SHOWN" = 24 ] && ok "(C) exactly 24 include targets shown (kMaxExpandIncludes)" \
                      || no "(C) inc= shows $INC_SHOWN targets, want exactly 24"

# ── (D) opt-in: every OTHER packBodies caller stays byte-identical (withFileContext defaults false) ─────
# --for's auto rank-1 body and --pack-task both route through packBodies WITHOUT withFileContext; probing
# them on this fixture must show NEITHER sibs= nor inc= anywhere in the output.
#
# RE-ARMED 2026-08-23 (the --for-family serving-shape sweep). The original probes spelled the task
# UNQUOTED (--for=compute a value): the shell split it, ripwire refused the nonexistent root 'a' (rc=1,
# empty stdout), and both negatives grepped an EMPTY string — green while observing nothing. And even
# quoted, "compute a value" routes CONCEPTUAL, which now serves the COMPACT bundle (zero bodies) — a
# shape that cannot leak a body attribute in the first place. Both probes are now name-anchored so each
# serves >= 1 real <b> body — asserted by a presence guard per CONTRIBUTING §2's "a gate that cannot
# observe what it asserts" rule — and the negatives bind on the body-bearing shape the contract is about.
# Re-proved red-capable at re-arm: the presence guard fires on a body-free (compact) serving, and the
# negative's grep detects sibs=/inc= when fed arm (A)'s --expand output.
FOR_XML="$( "$BIN" "$FIX" --for=alphaFn --no-cache 2>/dev/null )"
printf '%s' "$FOR_XML" | grep -q '<b t=' \
    && ok "(D) presence: --for=alphaFn serves a real auto body (the packBodies shape the opt-in is about)" \
    || no "(D) presence: --for=alphaFn served NO body — the sibs=/inc= negative below would pass on nothing"
if printf '%s' "$FOR_XML" | grep -qE 'sibs=|inc="'; then
    no "(D) --for's auto-body leaked sibs=/inc= — withFileContext must default false for non-expand callers"
else
    ok "(D) --for's auto-body carries no sibs=/inc= (opt-in default holds)"
fi
PT_XML="$( "$BIN" "$FIX" --pack-task=alphaFn --no-cache 2>/dev/null )"
printf '%s' "$PT_XML" | grep -q '<b t=' \
    && ok "(D) presence: --pack-task=alphaFn serves a real body" \
    || no "(D) presence: --pack-task=alphaFn served NO body — the sibs=/inc= negative below would pass on nothing"
if printf '%s' "$PT_XML" | grep -qE 'sibs=|inc="'; then
    no "(D) --pack-task leaked sibs=/inc= — withFileContext must default false for non-expand callers"
else
    ok "(D) --pack-task carries no sibs=/inc= (opt-in default holds)"
fi

# ── (E) well-formedness + determinism ─────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    for f in basic lonely many; do
        xmllint --noout "$TMP/$f.xml" 2>/dev/null && ok "(E) $f.xml well-formed" || no "(E) $f.xml fails xmllint"
    done
else
    printf '  SKIP  xmllint not installed\n'
fi
"$BIN" "$FIX" --expand=manyFn000 --top-k=0 --no-cache >"$TMP/many2.xml" 2>/dev/null
diff -q "$TMP/many.xml" "$TMP/many2.xml" >/dev/null \
    && ok "(E) sibs=/inc= output byte-identical across two runs" \
    || no "(E) sibs=/inc= output non-deterministic"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
