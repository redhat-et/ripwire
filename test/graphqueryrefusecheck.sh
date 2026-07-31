#!/usr/bin/env bash
# graphqueryrefusecheck.sh — §P0.5b gate: --graph-query must refuse an unknown name() like its siblings.
#
#   --graph-query='name("DoesNotExist")'  ->  count="0", exit 0, stderr EMPTY      (before)
#   --callers=DoesNotExist                ->  exit 1 + did-you-mean
#
# Eleven of thirteen symbol-taking verbs refuse an unknown name with a suggestion; --graph-query returned a
# silent zero — and it is where a typo is MOST likely, because the name is buried inside an expression.
#
# The line this gate draws: judge the LITERAL, not the result. A name() that resolves to nothing is always a
# user error. A name() that DOES resolve, inside a composed query that legitimately selects nothing, is a
# measurement and must still exit 0 with count="0".
#
#   RIPWIRE_BIN=build/ripwire      bash test/graphqueryrefusecheck.sh
#   RIPWIRE_BIN=build_base/ripwire bash test/graphqueryrefusecheck.sh   # must FAIL (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "graphqueryrefusecheck: BIN=$BIN  ROOT=$ROOT"

# ── 1. a bare unknown name refuses, names the literal, and prints no <query> element
# §P12.1: didYouMean() now does true bounded edit distance (not the old shared-prefix*4-lenDelta score that
# always forced SOME guess, however unrelated), so it only suggests when a real near-miss exists. "mainn" is
# a genuine 1-edit typo of this repo's own "main" — a real near-miss — so the did-you-mean assertion still
# tests the actual (fixed) behavior instead of pinning the old bug.
"$BIN" "$ROOT" --graph-query='name("mainn")' >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" -eq 1 ] && ok "unknown name(): exit 1" || no "unknown name(): exit $rc (expected 1)"
grep -q 'mainn' "$TMP/err" && ok "refusal names the unresolved literal" \
    || no "refusal does not name the literal: $( head -c 200 "$TMP/err" )"
grep -q 'count=' "$TMP/out" && no "refusal still printed a <query count=> element" || ok "no count= element on the refusal path"
grep -qi 'did you mean' "$TMP/err" && ok "refusal carries a did-you-mean suggestion" \
    || no "refusal has no did-you-mean (siblings all offer one)"

# ── 2. an unknown name BURIED inside a larger expression refuses too — that is the likeliest typo site
"$BIN" "$ROOT" --graph-query='and(callers(name("parseArgsTypo"),2),kind(all,fn))' >"$TMP/out2" 2>"$TMP/err2"; rc2=$?
[ "$rc2" -eq 1 ] && ok "unknown name() nested in an expression: exit 1" \
    || no "unknown name() nested in an expression: exit $rc2 (expected 1)"
grep -q 'parseArgsTypo' "$TMP/err2" && ok "nested refusal names the literal" || no "nested refusal does not name the literal"

# ── 3. a RESOLVING name inside a query that legitimately selects nothing is a MEASUREMENT
"$BIN" "$ROOT" --graph-query='cx(name("main"),999999)' >"$TMP/zero" 2>/dev/null; rc3=$?
[ "$rc3" -eq 0 ] && grep -q '<query [^>]*count="0"' "$TMP/zero" \
    && ok 'name("main") + impossible filter still exits 0 with count="0" (a measurement)' \
    || no "name(\"main\") + impossible filter: exit $rc3 without count=\"0\""

# ── 4. an ordinary query is untouched
"$BIN" "$ROOT" --graph-query='name("main")' >"$TMP/ok" 2>/dev/null; rc4=$?
N="$( grep -oE ' count="[0-9]+"' "$TMP/ok" | head -1 | grep -oE '[0-9]+' )"
[ "$rc4" -eq 0 ] && [ "${N:-0}" -ge 1 ] && ok "name(\"main\") resolves: exit 0 count=$N" \
    || no "name(\"main\"): exit $rc4 count=${N:-<none>} (expected exit 0, count >= 1)"

# ── 5. the refusal must agree with the siblings — same string, same verdict
"$BIN" "$ROOT" --callers=mainn >/dev/null 2>&1; sib=$?
[ "$sib" -eq 1 ] && ok "--callers=mainn also exits 1 (siblings agree)" \
    || no "--callers=mainn exits $sib — the sibling contract this gate mirrors has moved"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
