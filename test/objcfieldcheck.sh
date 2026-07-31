#!/usr/bin/env bash
# objcfieldcheck.sh — H4 (L-NEW lane) gate: ObjC field_expression call parity with C.
#
# H4_grammarSurvey_2026-07-30.md found queries/objc/tags.scm missing the field_expression call
# pattern its parent C grammar already carries (queries/c/tags.scm:58-59) — `ops->init()` (a call
# through a function-pointer struct field) extracted NOTHING. PLAN item 4 copies the one line:
#   (call_expression function: (field_expression field: (field_identifier) @name)) @reference.call
#
# In practice ObjC field-calls are almost always function-pointer struct fields (methods use
# message sends, not field_expression), so this is a probe-level (extraction) fix, not a
# resolution fix — the fixture deliberately has no symbol named "init", so the reference stays
# UNRESOLVED after the fix too. This gate therefore asserts the RAW EXTRACTION via
# ctxpack_probe (which prints refs pre-resolution), not --callees/--uses (which would show no
# change at all, since the ref never resolves either before or after).
#
# Fixture test/objcfieldfix/main.m:
#   freeFn()    — control: bare C call (already captured pre-H4)
#   ops->init() — field-expression call (H4 widening: now extracted, still resolves to nothing)
#
# RED-FIRST (recorded 2026-07-31, plain dev build, both binaries same tree, via ctxpack_probe):
#   pre-change (ctxpack_probe_base): caller's raw refs = "freeFn ops"       (2 refs; no "init")
#   post-change (ctxpack_probe):     caller's raw refs = "freeFn init ops" (3 refs; "init" present)
# This gate reproduces that exact comparison live against build/ctxpack_probe_base when present.
#
# Usage:  test/objcfieldcheck.sh   |   CTXPACK_PROBE=asan/ctxpack_probe test/objcfieldcheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
# V1 MED-1 fix: the probe must FOLLOW the binary under test (house pattern, probecheck.sh) — the
# harness invokes gates with CTXPACK_BIN only, never CTXPACK_PROBE, so a hardcoded build/ default
# made an asan/base run validate the wrong build's extraction.
PROBE="${CTXPACK_PROBE:-${BIN}_probe}"
[ "${PROBE#/}" = "$PROBE" ] && PROBE="$ROOT/$PROBE"
FIX="$ROOT/test/objcfieldfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$PROBE" ] || { echo "no ctxpack_probe binary at $PROBE — build first (cmake --build build -j)"; exit 2; }
[ -x "$BIN" ]   || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
echo "objcfieldcheck: PROBE=$PROBE  BIN=$BIN  FIX=$FIX"

# ── extraction: probe's raw "calls:" line for caller must now include "init" ────────────────────
callsline="$( "$PROBE" "$FIX" 2>/dev/null | grep -A1 '\[   1\] caller' | tail -1 )"
case "$callsline" in
  *"calls: freeFn init ops"*) ok "caller's raw refs include init (extraction landed): $callsline" ;;
  *) no "caller's raw refs missing init (got: $callsline)" ;;
esac
printf '%s' "$callsline" | grep -q 'freeFn' && ok "control freeFn still present" || no "control freeFn MISSING (regression on the unrelated bare-call pattern)"

# ── resolution stays honest: init has no def in this fixture, so --callees is UNCHANGED ─────────
cout="$( "$BIN" "$FIX" --callees=caller --no-cache 2>/dev/null )"
ccount="$( printf '%s' "$cout" | grep -oE 'count="[0-9]+"' | head -1 )"
[ "$ccount" = 'count="1"' ] && ok "--callees=caller stays count=\"1\" (init extracts but does not resolve, matching C's own documented behavior)" \
                             || no "--callees=caller count changed unexpectedly (got $ccount) — init should NOT resolve in this fixture"
printf '%s' "$cout" | grep -q 'n="freeFn"' && ok "--callees=caller still names freeFn" || no "--callees=caller lost freeFn"

# ── honesty: no new mis-resolution / ambiguity introduced by the widened pattern ────────────────
hdr="$( "$BIN" "$FIX" --no-cache 2>/dev/null )"
amb="$( printf '%s' "$hdr" | grep -oE 'ambiguous=[0-9]+' | head -1 )"
unr="$( printf '%s' "$hdr" | grep -oE 'unresolved=[0-9]+' | head -1 )"
[ "$amb" = "ambiguous=0" ] && ok "fixture $amb" || no "fixture $amb (expected 0)"
[ "$unr" = "unresolved=0" ] && ok "fixture $unr (init drops silently pre-resolution, same as C field calls — it never reaches the unresolved= gauge)" || no "fixture $unr (expected 0)"

# ── determinism ───────────────────────────────────────────────────────────────────────────────
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
"$BIN" "$FIX" --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" && ok "deterministic" || no "non-deterministic"
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

# ── RED-FIRST live check against a committed pre-change probe binary, when present ──────────────
redfirst_check()
{
    # Deliberately NOT derived from CTXPACK_BIN: this arm wants the hand-saved PRE-CHANGE artifact
    # (a lane copies it before editing), whatever binary is under test. Absent -> honest SKIP below.
    local BASEPROBE="$ROOT/build/ctxpack_probe_base"
    [ -x "$BASEPROBE" ] || { skip "red-first: build/ctxpack_probe_base not present"; return; }
    local before
    before="$( "$BASEPROBE" "$FIX" 2>/dev/null | grep -A1 '\[   1\] caller' | tail -1 )"
    case "$before" in
      *"calls: freeFn ops"*) ok "red-first: ctxpack_probe_base's caller refs = 'freeFn ops' (no init) — this gate is a real regression fence" ;;
      *"init"*) no "red-first FAILED: ctxpack_probe_base ALREADY extracts init (got: $before) — base binary may already carry this fix" ;;
      *) no "red-first: unexpected pre-change output ($before)" ;;
    esac
}
redfirst_check

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
