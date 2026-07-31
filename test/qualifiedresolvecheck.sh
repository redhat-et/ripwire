#!/usr/bin/env bash
# qualifiedresolvecheck.sh — gate for AUDIT5 X9(b): --callers/--callees/--impact now accept the qualified
# "file:name" spec syntax that --around/--lego/--edit-check already supported (resolveFocus) — a same-
# named symbol across files previously had no way to disambiguate on these three verbs.
#
# Fixture test/qualifiedfix/: alpha.cpp and beta.cpp EACH define a function named "dup" (deliberately
# colliding), called by exactly one caller apiece (callerA / callerB respectively). Bare "dup" must still
# behave exactly as before (union across both files); "alpha.cpp:dup" / "beta.cpp:dup" must narrow to the
# ONE matching file.
#
# Usage:  CTXPACK_BIN=build/ctxpack bash test/qualifiedresolvecheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/qualifiedfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/qualifiedfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "qualifiedresolvecheck: BIN=$BIN  CORPUS=test/qualifiedfix"

callers(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --callers="$1" --no-cache 2>/dev/null; }
impact(){  perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --impact="$1"  --no-cache 2>/dev/null; }

# ── #1: bare "dup" (unqualified) → UNION across both files, unchanged from before X9(b) ────────────────
BARE="$( callers dup )"
if printf '%s' "$BARE" | grep -q 'n="callerA"' && printf '%s' "$BARE" | grep -q 'n="callerB"'; then
    ok "--callers=dup (bare): union of BOTH files' callers (callerA + callerB)"
else
    no "--callers=dup (bare): expected callerA AND callerB, got: $BARE"
fi

# ── #2: "alpha.cpp:dup" narrows to callerA ONLY ─────────────────────────────────────────────────────────
QA="$( callers alpha.cpp:dup )"
if printf '%s' "$QA" | grep -q 'n="callerA"' && ! printf '%s' "$QA" | grep -q 'n="callerB"'; then
    ok "--callers=alpha.cpp:dup: callerA only (beta's dup excluded)"
else
    no "--callers=alpha.cpp:dup: expected callerA only, got: $QA"
fi

# ── #3: "beta.cpp:dup" narrows to callerB ONLY ──────────────────────────────────────────────────────────
QB="$( callers beta.cpp:dup )"
if printf '%s' "$QB" | grep -q 'n="callerB"' && ! printf '%s' "$QB" | grep -q 'n="callerA"'; then
    ok "--callers=beta.cpp:dup: callerB only (alpha's dup excluded)"
else
    no "--callers=beta.cpp:dup: expected callerB only, got: $QB"
fi

# ── #4: --callees is symmetric (same code path, wantCallers flips) — alpha.cpp:callerA calls ONLY alpha's dup
QC="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --callees="alpha.cpp:callerA" --no-cache 2>/dev/null )"
printf '%s' "$QC" | grep -q 'n="dup"' \
    && ok "--callees=alpha.cpp:callerA: resolves via file:name qualification too" \
    || no "--callees=alpha.cpp:callerA: expected dup in the callee set, got: $QC"

# ── #5: --impact mirrors the same qualification (X9(b) names both --callers and --impact explicitly) ────
IA="$( impact alpha.cpp:dup )"
if printf '%s' "$IA" | grep -q 'n="callerA"' && ! printf '%s' "$IA" | grep -q 'n="callerB"'; then
    ok "--impact=alpha.cpp:dup: reaches callerA only (beta's dup excluded)"
else
    no "--impact=alpha.cpp:dup: expected callerA only, got: $IA"
fi
IBARE="$( impact dup )"
if printf '%s' "$IBARE" | grep -q 'n="callerA"' && printf '%s' "$IBARE" | grep -q 'n="callerB"'; then
    ok "--impact=dup (bare): union of BOTH files' blast radius, unchanged"
else
    no "--impact=dup (bare): expected callerA AND callerB, got: $IBARE"
fi

# ── #6: a qualified spec that matches NOTHING refuses loudly (not silently empty-success) ────────────────
NOMATCH_ERR="$( perl -e 'alarm 8; exec @ARGV' "$BIN" "$FIX" --callers="nosuchfile.cpp:dup" --no-cache 2>&1 1>/dev/null )"
NOMATCH_RC=$?; NOMATCH_RC2=$( perl -e 'alarm 8; exec @ARGV' "$BIN" "$FIX" --callers="nosuchfile.cpp:dup" --no-cache >/dev/null 2>&1; echo $? )
[ "$NOMATCH_RC2" = 1 ] && ok "--callers=nosuchfile.cpp:dup: refuses loudly (exit 1), not a silent empty match" \
    || no "--callers=nosuchfile.cpp:dup: expected exit 1, got $NOMATCH_RC2"
printf '%s' "$NOMATCH_ERR" | grep -q 'not found' \
    && ok "--callers=nosuchfile.cpp:dup: stderr names it not found (did-you-mean uses the bare NAME, not the file: prefix)" \
    || no "--callers=nosuchfile.cpp:dup: missing a not-found message, got: $NOMATCH_ERR"

# ── #7: determinism ─────────────────────────────────────────────────────────────────────────────────────
[ "$( callers alpha.cpp:dup )" = "$( callers alpha.cpp:dup )" ] \
    && ok "determinism: --callers=alpha.cpp:dup byte-identical run-to-run" \
    || no "determinism: --callers=alpha.cpp:dup non-deterministic"

# ── #8: well-formed XML ─────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$QA" | xmllint --noout - 2>/dev/null && printf '%s' "$IA" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (--callers=alpha.cpp:dup, --impact=alpha.cpp:dup)" || no "xml malformed"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
