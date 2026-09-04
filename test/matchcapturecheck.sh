#!/usr/bin/env bash
# matchcapturecheck.sh — §P0.1 gate: a capture-less --match must never produce a bare hits="0".
#
#   --match='(if_statement)'      -> hits="0"      (before)
#   --match='(if_statement) @i'   -> hits="5000"
#   --match='(goto_statement)'    -> hits="0"      (before)
#   --match='(goto_statement) @g' -> hits="N"  (N derived from the tree, never pinned)
#
# astQuery reports CAPTURES, so a query that binds none matches nothing it can report. The zero was clean,
# confident and wrong — and it already did damage: a capture recorded `--match='(goto_statement)' → hits="0"`
# and that was read as evidence this repo has no gotos. It has two.
#
# The invariant: for a capture-less pattern the tool either AUTO-CAPTURES (and says so with
# auto_captured="1") or REFUSES with the add-@name message. A bare hits="0" from a query that bound nothing
# must be unreachable.
#
#   RIPWIRE_BIN=build/ripwire      bash test/matchcapturecheck.sh
#   RIPWIRE_BIN=build_base/ripwire bash test/matchcapturecheck.sh   # must FAIL (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "matchcapturecheck: BIN=$BIN  ROOT=$ROOT"

hitsOf(){ grep -oE ' hits="[0-9]+"' "$1" | head -1 | grep -oE '[0-9]+'; }

# equalsCaptured NAME BARE_PATTERN CAPTURED_PATTERN
#   the capture-less form must agree with the explicit one, OR refuse — never a silent zero.
equalsCaptured(){
    local name="$1" bare="$2" captured="$3"
    "$BIN" "$ROOT" --match="$captured" >"$TMP/cap" 2>/dev/null
    local want; want="$( hitsOf "$TMP/cap" )"
    "$BIN" "$ROOT" --match="$bare" >"$TMP/bare" 2>"$TMP/bareerr"; local rc=$?
    local got;  got="$( hitsOf "$TMP/bare" )"

    if [ "$rc" -eq 1 ]; then
        grep -q '@name' "$TMP/bareerr" && ok "$name: refused with the add-@name message" \
            || no "$name: exited 1 without the add-@name message: $( head -c 160 "$TMP/bareerr" )"
        return
    fi
    [ "${got:-x}" = "${want:-y}" ] && ok "$name: bare hits=$got == captured hits=$want" \
        || no "$name: bare hits=${got:-<none>} != captured hits=${want:-<none>}"
    [ "${got:-0}" != "0" ] || no "$name: bare form still reports hits=\"0\" — the exact defect"
    # the ATTRIBUTE, not the legend: the header comment documents auto_captured= on every run
    grep -oE '<match [^>]*>' "$TMP/bare" | grep -q 'auto_captured="1"' && ok "$name: auto_captured=\"1\" discloses the rewrite" \
        || no "$name: rewrote the query without saying so (no auto_captured=\"1\" on <match>)"
}

equalsCaptured "(goto_statement)" '(goto_statement)' '(goto_statement) @g'
equalsCaptured "(if_statement)"   '(if_statement)'   '(if_statement) @i'
equalsCaptured "(do_statement)"   '(do_statement)'   '(do_statement) @d'

# ── the tree-wide goto population is DERIVED, never pinned. It was pinned at 2 and a later round added a
#    third goto in a FIXTURE (test/sliceflowsensfix/disclosed.cpp — the flow-sensitive slice's deliberately
#    disclosed "goto is untracked" case), which reddened two arms that are not about the number at all: the
#    arms below test that an EXPLICIT capture is left alone and that a trailing comment does not defeat the
#    scan. Deriving the count keeps them testing that, and keeps the next fixture from breaking them.
GOTOS="$( "$BIN" "$ROOT" --match='(goto_statement) @g' 2>/dev/null | grep -oE ' hits="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
case "$GOTOS" in
    ''|0 ) no "cannot derive the goto population (--match '(goto_statement) @g' gave '${GOTOS:-<none>}') — the arms below need a non-zero ground truth"; GOTOS=0 ;;
    * )    ok "goto ground truth derived from the tree: $GOTOS" ;;
esac

# ── an EXPLICITLY captured query is untouched: no auto_captured=, same hits as always
"$BIN" "$ROOT" --match='(goto_statement) @g' >"$TMP/exp" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ "$( hitsOf "$TMP/exp" )" = "$GOTOS" ] && ok "explicit @capture: exit 0 hits=$GOTOS" \
    || no "explicit @capture: exit $rc hits=$( hitsOf "$TMP/exp" ) (expected 0 / $GOTOS)"
grep -oE '<match [^>]*>' "$TMP/exp" | grep -q 'auto_captured=' \
    && no "explicit @capture leaked auto_captured= on <match> (absent = not rewritten)" \
    || ok "explicit @capture has no auto_captured= on <match> (absent = not rewritten)"

# ── a MULTI-pattern capture-less query cannot be auto-captured safely: refuse, do not guess
"$BIN" "$ROOT" --match='(goto_statement) (do_statement)' >"$TMP/multi" 2>"$TMP/multierr"; rcm=$?
[ "$rcm" -eq 1 ] && ok "multi-pattern capture-less query: exit 1" || no "multi-pattern capture-less query: exit $rcm (expected 1)"
grep -q '@name' "$TMP/multierr" && ok "multi-pattern refusal carries the add-@name message" \
    || no "multi-pattern refusal message missing: $( head -c 160 "$TMP/multierr" )"
grep -q 'hits=' "$TMP/multi" && no "multi-pattern refusal still printed a hits= element" \
    || ok "no hits= element on the multi-pattern refusal path"

# ── THE invariant, stated directly: no capture-less pattern may yield a bare hits="0"
for pat in '(goto_statement)' '(if_statement)' '(do_statement)' '(cast_expression)' '(number_literal)'; do
    "$BIN" "$ROOT" --match="$pat" >"$TMP/inv" 2>/dev/null; rci=$?
    if [ "$rci" -eq 0 ] && [ "$( hitsOf "$TMP/inv" )" = "0" ]; then
        no "capture-less '$pat' reached a bare hits=\"0\" at exit 0"
    fi
done
ok "no capture-less pattern reached a bare hits=\"0\""

# ── adversarial-round extensions ─────────────────────────────────────────────────────────────────────
# (a) a `;` line comment must not defeat capture detection: `@x` inside the comment binds nothing, and an
#     appended ` @m` would itself land inside the comment — so a capture-less comment-bearing query REFUSES.
"$BIN" "$ROOT" --match='(goto_statement) ; @x' >/dev/null 2>&1
[ $? -eq 1 ] && ok "comment-hidden @ refuses (a ; comment cannot smuggle a capture past the scan)" \
             || no "comment-hidden @ NOT refused: '(goto_statement) ; @x' must exit 1, got $?"
# (b) a capture + trailing comment is a fine query and must still scan
h="$( "$BIN" "$ROOT" --match='(goto_statement) @g ; note' 2>/dev/null | grep -oE 'hits="[0-9]+"' | head -1 )"
[ "$h" = "hits=\"$GOTOS\"" ] && ok "capture + trailing comment still scans (hits=$GOTOS)" \
                      || no "capture + trailing comment broke: want hits=\"$GOTOS\", got '$h'"
# (c) §P0.4's rule on --match's own engine: a query NO grammar compiles measured nothing — refuse, never zero
for q in '(this_is_not_a_node)' '((call_expression) (#match? @f "x"))'; do
    "$BIN" "$ROOT" --match="$q" >"$TMP/nogram.out" 2>/dev/null
    rc=$?
    if [ "$rc" -eq 1 ] && ! grep -q '<match' "$TMP/nogram.out"; then
        ok "uncompilable query refuses (exit 1, no match element): $q"
    else
        no "uncompilable query '$q': want exit 1 + no match element, got exit $rc"
    fi
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
