#!/usr/bin/env bash
# constcheck.sh — module-level settings-constant extraction + ranking gate.
#
# WHY (bench/headtohead/r3-headroom-2026-08-03/REPORT.md, loss q10). The r3 head-to-head lost a
# question because a Django settings constant (PASSWORD_HASHERS in global_settings.py) never
# surfaced in --for/--pack-task. The audit's mechanism claim ("module-level constants are not
# extracted as rankable symbols at all") was re-verified before this gate was written and is WRONG
# for Python — the vendored Python tags capture every module-level assignment, and the django
# index holds ~956 var symbols — but TRUE for TypeScript, JavaScript, Rust, Ruby, Java, C#, C and
# C++: none of those grammars' tags captured a module-level constant, so a settings table in any
# of them contributed ZERO rankable symbols and --for structurally could not surface it.
#
# WHAT THIS GATE PINS (fixture: test/constfix/ — one settings file per gap language plus a
# distractor-dense hashers.ts so the --for assertion has real lexical competition):
#   1. RED-BEFORE-FIX extraction: each language's SCREAMING_SNAKE module-level constant appears in
#      the map as t="var". (Run against a pre-fix binary, every one of these FAILS — verified
#      2026-08-03 against b6068c3.)
#   2. RED-BEFORE-FIX ranking: --for with a config-flavored task ("...selectable password
#      hashers...") surfaces the settings constant TS_PASSWORD_HASHERS in the lens — the r3
#      report's own gate shape ("a --for=...selectable/config... fixture must surface a settings
#      constant"). Structurally impossible pre-fix: the symbol did not exist.
#   3. SCOPE negatives (the "do not rank every literal" contract): lowercase top-level consts
#      (TS/JS), camelCase/CamelCase names (Java field, Ruby alias), function-local
#      SCREAMING_SNAKE (TS), and a lowercase mutable C global stay UNindexed.
#   4. KIND precedence: a SCREAMING_SNAKE arrow-function const stays t="fn" (dedup keeps the more
#      specific kind — the constant pattern must not demote real functions to vars).
#   5. EXISTING behavior pinned unchanged: Python module-level assignments stay var defs
#      regardless of case; the C# property_declaration var def survives.
#   6. Determinism: two runs over the fixture are byte-identical.
#
# Usage:
#   test/constcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/constcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/constfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "constcheck: BIN=$BIN  FIX=$FIX"

MAP="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP" 2>"$TMP/map.err" || { no "default map exited non-zero: $( cat "$TMP/map.err" )"; exit 1; }

command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP" && ok "map passes xmllint --noout" || no "map fails xmllint"; }

# a var-def row for NAME anywhere in the map: <s t="var" n="NAME" ...
has_var(){ grep -q "t=\"var\" n=\"$1\"" "$MAP"; }
# any def row for NAME regardless of kind
has_any(){ grep -q "n=\"$1\"" "$MAP"; }

# ── 1. extraction: one settings constant per gap language ──────────────────────────────────────
for sym in TS_PASSWORD_HASHERS TS_FEATURE_FLAGS TS_MAX_RETRIES \
           JS_RATE_LIMITS JS_LEGACY_LIMIT \
           RS_MAX_CONNECTIONS RS_DEFAULT_TIMEOUT_MS \
           RB_PASSWORD_HASHERS RB_TIMEOUT_SECONDS \
           JV_MAX_POOL_SIZE \
           CS_MAX_RETRIES CS_DEFAULT_HOSTS \
           C_MAX_BUFFER_BYTES C_DEFAULT_NAME C_DEFAULT_HOSTS \
           CPP_MAX_DEPTH CPP_DEFAULT_HOSTS; do
    has_var "$sym" && ok "extracted t=\"var\": $sym" || no "MISSING t=\"var\" def: $sym"
done

# ── 2. ranking: the r3 report's gate shape — a config-flavored --for surfaces the constant ─────
FOR_OUT="$TMP/for.xml"
$BIN "$FIX" --no-cache --for="which config setting lists the selectable password hashers?" >"$FOR_OUT" 2>/dev/null
grep -q 'n="TS_PASSWORD_HASHERS"' "$FOR_OUT" \
    && ok "--for (config query) surfaces TS_PASSWORD_HASHERS in the lens" \
    || no "--for (config query) does NOT surface TS_PASSWORD_HASHERS — the r3 q10 loss shape"

# ── 3. scope negatives: not every literal becomes a symbol ─────────────────────────────────────
for sym in retryBudget helperBudget TS_LOCAL_GUARD CamelAlias javaCounter c_mutable_global; do
    has_any "$sym" && no "over-capture: '$sym' must stay unindexed" || ok "unindexed as required: $sym"
done

# ── 4. kind precedence: SCREAMING_SNAKE arrow const stays a function ───────────────────────────
grep -q 't="fn" n="TS_MAKE_HANDLER"' "$MAP" \
    && ok "TS_MAKE_HANDLER stays t=\"fn\" (function beats var on dedup)" \
    || no "TS_MAKE_HANDLER lost its function kind"
has_var "TS_MAKE_HANDLER" && no "TS_MAKE_HANDLER doubled as a var def" || ok "TS_MAKE_HANDLER not doubled as var"

# ── 5. existing behavior pinned ────────────────────────────────────────────────────────────────
has_var "PY_SETTING_MODE"   && ok "Python module assignment still var (upper)" || no "Python PY_SETTING_MODE regressed"
has_var "py_lower_setting"  && ok "Python module assignment still var (lower — case-blind, unchanged)" || no "Python py_lower_setting regressed"
has_var "NotAConst"         && ok "C# property_declaration var def survives" || no "C# NotAConst property def regressed"

# ── 6. determinism on this fixture ─────────────────────────────────────────────────────────────
$BIN "$FIX" --no-cache >"$TMP/map2.xml" 2>/dev/null
diff -q "$MAP" "$TMP/map2.xml" >/dev/null && ok "two runs byte-identical" || no "determinism drift on constfix"

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
