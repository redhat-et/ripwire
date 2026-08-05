#!/usr/bin/env bash
# testedreachcheck.sh — tested= must agree with the transitive coverage reported by --exercises.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }
mkdir -p "$TMP/proj/src" "$TMP/proj/test"
printf '%s\n' \
    'int leaf()' \
    '{' \
    '    return 7;' \
    '}' \
    '' \
    'int outer()' \
    '{' \
    '    return leaf();' \
    '}' >"$TMP/proj/src/app.cpp"
printf '%s\n' \
    'int outer();' \
    '' \
    'int testOuter()' \
    '{' \
    '    return outer() == 7 ? 0 : 1;' \
    '}' >"$TMP/proj/test/test_app.cpp"

"$BIN" "$TMP/proj" --for=leaf --no-cache >"$TMP/for" 2>"$TMP/for.err"
"$BIN" "$TMP/proj" --metrics --top-k=20 --no-cache >"$TMP/metrics" 2>"$TMP/metrics.err"
"$BIN" "$TMP/proj" --exercises=test/test_app.cpp --limit=20 --no-cache >"$TMP/exercises" 2>"$TMP/exercises.err"

forLeaf="$( sed 's/></>\n</g' "$TMP/for" | grep '<d .* n="leaf"' | head -1 )"
metricsLeaf="$( sed 's/></>\n</g' "$TMP/metrics" | grep '<s .* n="leaf"' | head -1 )"
exerciseLeaf="$( sed 's/></>\n</g' "$TMP/exercises" | grep '<s .* n="leaf"' | head -1 )"

printf '%s' "$exerciseLeaf" | grep -q 'n="leaf"' \
    && ok "--exercises proves testOuter -> outer -> leaf" \
    || no "--exercises did not report the transitively reached leaf: $exerciseLeaf"
printf '%s' "$forLeaf" | grep -q ' tested="1"' \
    && ok "--for marks transitively reached leaf tested=1" \
    || no "--for disagrees with --exercises for leaf: $forLeaf"
printf '%s' "$metricsLeaf" | grep -q ' tested="1"' \
    && ok "--metrics marks transitively reached leaf tested=1" \
    || no "--metrics disagrees with --exercises for leaf: $metricsLeaf"

if grep -R -n -F 'tested=0' "$ROOT/skills"/*/SKILL.md >"$TMP/impossible"; then
    no "skills request tested=0 even though the binary omits false values: $( tr '\n' ' ' <"$TMP/impossible" )"
else
    ok "skills never request the nonexistent tested=0 spelling"
fi

[ "$fail" -eq 0 ] && echo "testedreachcheck: ALL PASS" || echo "testedreachcheck: FAILURES"
exit "$fail"
