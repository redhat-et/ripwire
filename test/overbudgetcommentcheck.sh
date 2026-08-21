#!/usr/bin/env bash
# overbudgetcommentcheck.sh — A4-F9 gate: a symbol NAME containing "--" must never break the XML when it
# lands on the packBodies over-budget OMISSION path.
#
# packBodies, when a def does not fit the remaining --pack-budget-bytes AND something was already emitted,
# skips the whole def and leaves a visible marker:  <!-- body omitted (over budget): NAME -->.  A NAME with
# a "--" run (C++ operator--, a markdown "-- heading") is ill-formed inside an XML comment and xmllint
# rejects the whole document (the G4 gate). The fix collapses every '-' run to a single '-' before splicing.
#
# This gate feeds test/overbudgetfix/ (a struct with a big `bump()` method + an `operator--`), forces the
# omission path with a tiny budget, and asserts:
#   - the output passes xmllint --noout (would FAIL pre-fix: the raw "operator--" in the comment)
#   - the omission marker for operator-- is present but with the '--' run collapsed (contains "operator-",
#     never a raw "operator--")
#
# Usage:  test/overbudgetcommentcheck.sh   [ RIPWIRE_BIN=path/to/ripwire ]
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/overbudgetfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }
echo "overbudgetcommentcheck: BIN=$BIN  FIX=$FIX"

# fixture sanity: operator-- is actually captured as a symbol with a "--" in its name
"$BIN" "$FIX" --no-cache 2>/dev/null | grep -q 'n="operator--"' \
    && ok "fixture sanity: operator-- captured as a symbol name" \
    || no "fixture sanity: operator-- not captured (name check)"

# force the omission path: expand bump (fills the budget) then operator-- (over budget → omitted)
OUT="$TMP/out.xml"
"$BIN" "$FIX" --expand=bump,operator-- --pack-budget-bytes=60 --no-cache >"$OUT" 2>/dev/null

# the omission marker for operator-- must be present (proves we hit the over-budget path)
grep -q 'body omitted (over budget): operator-' "$OUT" \
    && ok "over-budget omission marker for operator-- is present" \
    || no "expected over-budget omission marker for operator-- (did the path trigger?)"

# G4: the whole document must be well-formed — the crux of A4-F9 (pre-fix: xmllint rejects the raw '--')
xmllint --noout "$OUT" 2>"$TMP/lint.err" \
    && ok "over-budget comment: passes xmllint --noout (no ill-formed '--' in the comment)" \
    || no "over-budget comment: xmllint FAILED: $( cat "$TMP/lint.err" )"

# the omission COMMENT must carry the collapsed 'operator-', never the raw 'operator--' ('--' is only
# legal elsewhere — e.g. the map's id="…::operator--" attribute, which xmllint already accepted above).
if grep -qF 'body omitted (over budget): operator--' "$OUT"; then
    no "raw 'operator--' ('--' run) survived into the XML comment — collapse did not apply"
else
    ok "omission comment carries the collapsed 'operator-' (no ill-formed '--' run in a comment)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
