#!/usr/bin/env bash
# fordisclosurecheck.sh — the T3 disclosure contract holds on EVERY --for-family serving path
# (docs/EVALS.md §4, T3 round: "Disclosure rides the container: the <ctx> root carries
# bundle=\"auto\" bodies=\"N\", and when no body fits the remaining budget, bodies=\"0\"
# reason=\"budget\""; plus the anchor-only round's criterion (b): serve no body and DISCLOSE the zero).
#
# WHY THIS GATE EXISTS. The 2026-08-22 Lane-AA transcript mine
# (PLAN_HARVEST_REPORTS_2026-08-20/bodyuse-memo.md §7) found 5 of 26 real --for calls whose <ctx>
# carried NEITHER bundle= NOR bodies= — a silent branch fired whenever an explicit --token-budget's
# byte allowance was fully consumed by header+sigs (leftBytes==0). Not a corner case: it hit at
# --token-budget=4000 on a sphinx-sized corpus, and est_tokens (mid-band rate, 2.50 B/tok) sits
# BELOW the stated budget while the byte allowance (2.36 x 0.90 B/tok) is already exhausted, so the
# output looked under budget AND undisclosed at once. A disclosure that disappears exactly when the
# budget is tight is the opposite of a disclosure.
#
# Contract:
#   1) CLI XML, auto mode, ANY explicit --token-budget, on BOTH routes (name-exact and
#      subtoken+body): the <ctx> root ALWAYS carries bundle="auto" — bodies="N", or bodies="0"
#      reason="budget"|"no_candidates". No silent shape exists.
#   2) the ceiling-exhausted case (allowance fully consumed by the signature bundle) discloses as
#      the ATTRIBUTE ALONE — bodies="0" reason="budget", no legend, no <bodies> element, because
#      only the attribute has reserved bytes at a spent ceiling (D10's "trims to fit" is a contract
#      too: fornotesbudgetcheck/forrootlegendcheck hold est_tokens to the stated ceiling at these
#      budgets, and the ~half-KB legend has no reserve there). The <sigs> block stays intact and
#      byte-identical to the --signatures-only run, and est_tokens moves by at most the attribute's
#      own worth. The no-fit-but-allowance-exists case (forautobodycheck #3b) keeps its richer
#      shell + legend disclosure — those budgets can pay for them.
#   3) --for --json serves no bodies BY DESIGN and says so: "bundle":"sigs" is always present
#      (the B1.4 rule — a reader must be able to tell "genuinely none" from "not in this dialect").
#   4) the MCP `for` verb (and batch's for sub-query — same builder, forTaskText) serves the
#      lazy-body posture and says so: bundle="sigs" on the ctx root, legend names fetch_body.
#   5) the disclosed shapes are deterministic (x2) and xmllint-clean (G4).
#
# Caller-CHOSEN postures stay attribute-free BY CONTRACT: --signatures-only restores the pre-T3
# bundle byte-identically and --detail=N is the explicit body knob (forautobodycheck #4/#9 own
# those arms). Absence of disclosure is only legal when the caller explicitly chose the posture;
# every posture the TOOL chose for the caller must be disclosed. That is this gate's one rule.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/fordisclosurecheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the MCP assertions"; exit 2; }
cd "$ROOT"
echo "fordisclosurecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
NAMETASK="pageRankDouble"                              # name-exact route (anchors the symbol)
CONCTASK="tree-sitter parse of a source file"          # subtoken+body route (anchors nothing)

# the <sigs>…</sigs> span, extracted byte-exactly (same helper as forautobodycheck.sh)
sigsblock(){ python3 -c 'import sys; s=open(sys.argv[1],"rb").read(); a=s.find(b"<sigs"); b=s.find(b"</sigs>"); sys.stdout.buffer.write(s[a:b+7] if a>=0 and b>=0 else b"")' "$1"; }

# ── #1: no silent shape — every explicit budget, both routes, carries bundle="auto" ─────────────────────
for B in 400 900 2000 4000 12000; do
    "$BIN" src --for="$NAMETASK" --token-budget="$B" --no-cache >"$TMP/n$B" 2>/dev/null; rc=$?
    [ "$rc" = 0 ] || no "#1 name-exact --token-budget=$B exited $rc"
    grep -q 'bundle="auto" bodies="[0-9]*"' "$TMP/n$B" \
        && ok "#1 name-exact route, --token-budget=$B: bundle=\"auto\" bodies= disclosed" \
        || no "#1 name-exact route, --token-budget=$B: <ctx> carries no bundle=/bodies= (the memo's silent shape)"
    "$BIN" src --for="$CONCTASK" --token-budget="$B" --no-cache >"$TMP/c$B" 2>/dev/null; rc=$?
    [ "$rc" = 0 ] || no "#1 conceptual --token-budget=$B exited $rc"
    grep -q 'bundle="auto" bodies="[0-9]*"' "$TMP/c$B" \
        && ok "#1 conceptual route, --token-budget=$B: bundle=\"auto\" bodies= disclosed" \
        || no "#1 conceptual route, --token-budget=$B: <ctx> carries no bundle=/bodies= (the memo's silent shape)"
done

# ── #2: the ceiling-exhausted case (the memo's exact mechanism) discloses, shell and all ────────────────
#    at 400 tokens the byte allowance (~850 B) is below the header+sigs floor, so leftBytes==0 by
#    construction — the branch that used to turn the whole surface off silently.
T="$TMP/n400"
grep -q 'bundle="auto" bodies="0" reason="budget"' "$T" \
    && ok "#2 ceiling-exhausted: bodies=\"0\" reason=\"budget\" disclosed" \
    || no "#2 ceiling-exhausted: missing bodies=\"0\" reason=\"budget\" on the <ctx> root"
grep -q '<bodies' "$T" \
    && no "#2 ceiling-exhausted: a <bodies> element leaked past a spent ceiling (attribute-only there)" \
    || ok "#2 ceiling-exhausted: no <bodies> element (the attribute IS the disclosure at a spent ceiling)"
grep -q 'bundle=auto:' "$T" \
    && no "#2 ceiling-exhausted: the ~half-KB legend leaked past a spent ceiling (it has no reserve there)" \
    || ok "#2 ceiling-exhausted: legend dropped (only the attribute's reserved bytes are spent)"
grep -q '<b [^>]*><!\[CDATA\[' "$T" \
    && no "#2 ceiling-exhausted: emitted body bytes past an exhausted ceiling (must serve none)" \
    || ok "#2 ceiling-exhausted: no body bytes (whole-body-or-nothing still holds)"
grep -q '<sigs' "$T" && ok "#2 ceiling-exhausted: the <sigs> block is intact" \
    || no "#2 ceiling-exhausted: the <sigs> block vanished"
"$BIN" src --for="$NAMETASK" --token-budget=400 --signatures-only --no-cache >"$TMP/n400so" 2>/dev/null
sigsblock "$T" >"$TMP/s_a"; sigsblock "$TMP/n400so" >"$TMP/s_s"
[ -s "$TMP/s_a" ] || no "#2 presence: could not extract a <sigs> block from the disclosed run"
diff -q "$TMP/s_a" "$TMP/s_s" >/dev/null \
    && ok "#2 ceiling-exhausted: <sigs> byte-identical to --signatures-only (disclosure never eats the signature budget)" \
    || no "#2 ceiling-exhausted: the disclosure changed the <sigs> bytes"
ET_T=$( grep -o 'est_tokens="[0-9]*"' "$T" | head -1 | grep -o '[0-9]*' )
ET_S=$( grep -o 'est_tokens="[0-9]*"' "$TMP/n400so" | head -1 | grep -o '[0-9]*' )
{ [ -n "${ET_T:-}" ] && [ -n "${ET_S:-}" ] && [ $(( ET_T - ET_S )) -ge 0 ] && [ $(( ET_T - ET_S )) -le 30 ]; } \
    && ok "#2 ceiling-exhausted: est_tokens moved by only the attribute's worth ($ET_T vs $ET_S, band 0..30)" \
    || no "#2 ceiling-exhausted: est_tokens delta out of band (tight=$ET_T vs sig-only=$ET_S — the disclosure leaked more than its reserve)"

# ── #3: the --json dialect names its own posture ────────────────────────────────────────────────────────
"$BIN" src --for="$NAMETASK" --json --no-cache >"$TMP/j1" 2>/dev/null; rc=$?
[ "$rc" = 0 ] || no "#3 --for --json exited $rc"
grep -q '"bundle":"sigs"' "$TMP/j1" \
    && ok "#3 --json (default budget): \"bundle\":\"sigs\" present" \
    || no "#3 --json (default budget): no bundle key — a reader cannot tell \"none\" from \"not this dialect\""
"$BIN" src --for="$NAMETASK" --json --token-budget=400 --no-cache >"$TMP/j2" 2>/dev/null
grep -q '"bundle":"sigs"' "$TMP/j2" \
    && ok "#3 --json (tight budget): \"bundle\":\"sigs\" present" \
    || no "#3 --json (tight budget): bundle key missing"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/j1" 2>/dev/null \
    && ok "#3 --json output parses as JSON with the new key" \
    || no "#3 --json output is not valid JSON"

# ── #4: the MCP `for` verb (and batch's for sub-query) disclose the lazy-body posture ───────────────────
CORPUS="$ROOT/test/zoomfix"
mcp_call(){ printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }
result_text(){ python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    r = json.loads(line)
    if r.get("id") == 2:
        if "error" in r: print("__ERR__:" + json.dumps(r["error"])); sys.exit(0)
        print(r["result"]["content"][0]["text"])
'; }
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize"}'
FORTXT="$( mcp_call "$INIT" \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"for\",\"arguments\":{\"path\":\"$CORPUS\",\"task\":\"engine scheduling run loop\"}}}" \
    | result_text )"
printf '%s' "$FORTXT" >"$TMP/mcpfor.xml"
grep -q 'bundle="sigs"' "$TMP/mcpfor.xml" \
    && ok "#4 MCP for verb: bundle=\"sigs\" on the ctx root" \
    || no "#4 MCP for verb: no bundle= disclosure (the tool chose the sig-only posture; the caller was not told)"
grep -q 'fetch_body' "$TMP/mcpfor.xml" \
    && ok "#4 MCP for verb: legend names fetch_body (a reader never guesses how to get a body)" \
    || no "#4 MCP for verb: legend does not name fetch_body"
BATTXT="$( mcp_call "$INIT" \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"batch\",\"arguments\":{\"path\":\"$CORPUS\",\"queries\":[{\"verb\":\"for\",\"task\":\"engine scheduling run loop\"}]}}}" \
    | result_text )"
printf '%s' "$BATTXT" >"$TMP/mcpbatch.xml"
grep -q 'bundle="sigs"' "$TMP/mcpbatch.xml" \
    && ok "#4 batch for sub-query: bundle=\"sigs\" rides the same payload" \
    || no "#4 batch for sub-query: disclosure missing from the batched payload"

# ── #5: determinism x2 + well-formedness on the disclosed shapes ────────────────────────────────────────
"$BIN" src --for="$NAMETASK" --token-budget=400 --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" src --for="$NAMETASK" --token-budget=400 --no-cache >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null \
    && ok "#5 ceiling-exhausted shape deterministic (byte-identical x2)" \
    || no "#5 ceiling-exhausted shape NON-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    lint=1
    for F in "$TMP/n400" "$TMP/n4000" "$TMP/c400" "$TMP/mcpfor.xml"; do
        xmllint --noout "$F" 2>/dev/null || { echo "    malformed: $F"; lint=0; }
    done
    [ "$lint" = 1 ] && ok "#5 all disclosed shapes well-formed XML (G4)" || no "#5 malformed XML"
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
