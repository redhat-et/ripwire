#!/usr/bin/env bash
# jsnestedcheck.sh — does a JS/TS function NESTED inside another function's scope report its OWN
# loc/cx/params/nest, or does it silently inherit the ENCLOSING function's numbers? Cross-codebase
# validation on webpack (2026-08-07) found the broadcast bug: in lib/html/syntax.js every named
# const-closure inside the ~3439-line `tokenize` arrow reported tokenize's loc=3439 cx=487 params=3
# instead of its own — the @definition capture for `const f = (..) => {..}` (a lexical_declaration,
# which owns no "body" field) climbed ancestors looking for a body-owning node and adopted the
# ENCLOSING arrow_function, stealing its whole span. jsmetricscheck.sh only pins TOP-LEVEL symbols
# (whose climb dead-ends at `program`), so the nested path was unguarded. This gate closes that gap
# for both reported shapes — nested-in-NAMED-function and nested-in-ANONYMOUS `module.exports`
# arrow — on JS and its byte-identical TS twin (the TS grammar shares the defect path).
#
# Fixture (test/jsnestedfix/): nested.js + nested.ts (identical text). Every loc/cx/params/nest
# value below is counted BY HAND from the fixture source (see its comment blocks) and cross-checked
# once against a real run before being pinned.
#
# Usage:
#   test/jsnestedcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/jsnestedcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/jsnestedfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/jsnestedfix directory"; exit 2; }

echo "jsnestedcheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --metrics --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$FIX" --metrics --no-cache >"$TMP/m2" 2>/dev/null
diff -q "$TMP/m1" "$TMP/m2" >/dev/null && ok "determinism (--metrics byte-identical run-to-run)" || no "non-deterministic --metrics output"

# per-file scoping: nested.js and nested.ts carry the SAME symbol names, so every row lookup is
# constrained to its <f p="...nested.EXT"> section (one <f> element per file, rows never cross it).
fsect(){ sed 's/>/>\n/g' "$TMP/m1" | sed -n "/<f p=\"[^\"]*nested\.$1\"/,/<\/f>/p"; }
fsect js >"$TMP/js"; fsect ts >"$TMP/ts"

srow(){ grep -E "<s t=\"[^\"]*\" n=\"$2\"" "$TMP/$1" | head -1; }
assert_attr(){ # ext name attr val
    local line; line="$( srow "$1" "$2" )"
    if [ -z "$line" ]; then no "$1/$2: symbol row missing"; return; fi
    if printf '%s' "$line" | grep -q " $3=\"$4\""; then ok "$1/$2: $3=$4"; else no "$1/$2: expected $3=$4 — got: $line"; fi
}

for ext in js ts; do
    echo
    echo "=== nested-closure attribution on $ext (hand-counted, own-body values) ==="
    # tokenize: the NAMED enclosing fn — its own whole-span numbers (span lines 9..58)
    assert_attr $ext tokenize loc 50;  assert_attr $ext tokenize params 3
    # reportError: nested named const-closure (span 15..33) — was loc=50 params=3 pre-fix (tokenize's)
    assert_attr $ext reportError loc 19;  assert_attr $ext reportError params 4
    assert_attr $ext reportError cx 4;    assert_attr $ext reportError nest 2
    # flushText: second nested closure (span 36..43)
    assert_attr $ext flushText loc 8;   assert_attr $ext flushText params 1
    assert_attr $ext flushText cx 2;    assert_attr $ext flushText nest 1
    # removeProblematicNodes: nested inside the ANONYMOUS `module.exports = (..) => {..}` (span 69..83)
    assert_attr $ext removeProblematicNodes loc 15;  assert_attr $ext removeProblematicNodes params 2
    assert_attr $ext removeProblematicNodes cx 4;    assert_attr $ext removeProblematicNodes nest 2

    # the broadcast signature itself: a nested row must never equal the enclosing row on loc — the
    # sibling-collision heuristic that quantified the webpack damage keys on exactly this identity.
    TOK_LOC="$( srow $ext tokenize | grep -oE ' loc="[0-9]+"' )"
    REP_LOC="$( srow $ext reportError | grep -oE ' loc="[0-9]+"' )"
    [ -n "$TOK_LOC" ] && [ "$TOK_LOC" != "$REP_LOC" ] \
        && ok "$ext: reportError loc differs from enclosing tokenize loc (no broadcast)" \
        || no "$ext: reportError loc==tokenize loc ($REP_LOC) — enclosing-span broadcast is back"

    # call-edge attribution rides the same spans: the calls at the bottom of tokenize's body sit in
    # NO nested closure's span, so they must attribute to tokenize (pre-fix they landed on the last
    # span-stealing closure and tokenize showed cbo=0 out=0).
    TOKROW="$( sed 's/>/>\n/g' "$TMP/m1" | sed -n "/<f p=\"[^\"]*nested\.$ext\"/,/<\/f>/p" | sed -n "/<s t=\"[^\"]*\" n=\"tokenize\"/,/<\/s>/p" )"
    printf '%s' "$TOKROW" | grep -q '<c n="reportError"/>' && printf '%s' "$TOKROW" | grep -q '<c n="flushText"/>' \
        && ok "$ext: tokenize carries call edges to BOTH nested closures" \
        || no "$ext: tokenize's call edges misattributed — got: $( printf '%s' "$TOKROW" | tr '\n' ' ' )"
done

echo
echo "=== MUTATION: wrong expected values must be DETECTED as failures (assertion liveness) ==="
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        line="$( srow js reportError )"
        if printf '%s' "$line" | grep -q ' loc="999"'; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (a wrong loc=999 assertion is correctly detected as a failure)" \
                       || no "mutation self-test broke — a wrong value did NOT fail (assertion logic unsound)"

# a nested row that REGRESSES back to the enclosing numbers must trip the distinctness trap
MUT2="$( ok(){ :; }; no(){ echo TRIPPED; }
        A=' loc="50"'; B=' loc="50"'
        if [ -n "$A" ] && [ "$A" != "$B" ]; then ok; else no; fi )"
[ "$MUT2" = "TRIPPED" ] && ok "mutation self-test (identical loc values correctly fail the distinctness trap)" \
                        || no "mutation self-test broke — the distinctness trap is not live"

# well-formed XML (G4)
command -v xmllint >/dev/null 2>&1 && {
    xmllint --noout "$TMP/m1" 2>/dev/null && ok "xml well-formed (--metrics on nested JS/TS)" || no "xml malformed (--metrics on nested JS/TS)"
}

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
