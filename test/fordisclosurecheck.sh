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
#      subtoken+body): the <ctx> root ALWAYS carries a bundle= disclosure — bundle="auto" bodies="N"
#      on the name-exact route's body walk, bundle="compact" bodies="0" on the conceptual route's
#      <hops> shape — with a reason= of "budget" | "no_candidates" | "compact-route" whenever
#      bodies="0". WHICH spelling depends on the serving shape; THAT there is one does not. No
#      silent shape exists on either. (The compact spelling entered this arm when this round landed
#      on a trunk that had gained the compact conceptual route, 2026-08-23 — the round was authored
#      against a trunk where every conceptual query still took the body walk. The rule is unchanged;
#      only the set of shapes it has to hold across grew, and the compact shape had inherited its own
#      fresh copy of the silent branch, fixed at that merge.)
#   2) the target-exhausted case (the explicit --token-budget spent by the signature rows) discloses on
#      the root — bodies="0" reason="budget" — and, since forbudget-soft (2026-10-14: an explicit
#      --token-budget is a SOFT target over the <sigs> rows; no header ladder, no over_ceiling=), it
#      KEEPS the bundle legend and serves the empty <bodies shown="0" capped="1"> shell (no body
#      bytes): the old attribute-only shape existed to fit a hard byte ceiling that is gone. The <sigs>
#      block stays intact and byte-identical to the --signatures-only run, and est_tokens prices the
#      extra disclosure bytes (rises, at no more than one token per kMinBytesPerToken bytes).
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
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
    # the conceptual route serves COMPACT on this trunk (bundle="compact" bodies="0" + a reason=), so the
    # assertion is on the DISCLOSURE, not on one spelling of it — see contract note 1 in the header.
    grep -qE 'bundle="(auto|compact)" bodies="[0-9]+"' "$TMP/c$B" \
        && ok "#1 conceptual route, --token-budget=$B: bundle=/bodies= disclosed ($( grep -oE 'bundle="(auto|compact)" bodies="[0-9]+"( reason="[a-z_-]+")?' "$TMP/c$B" | head -1 ))" \
        || no "#1 conceptual route, --token-budget=$B: <ctx> carries no bundle=/bodies= (the memo's silent shape)"
    # a bodies="0" without a reason= is half a disclosure: the reader is told nothing was served and
    # not told why. Both shapes owe the reason; only a nonzero bodies= count is allowed to omit it.
    if grep -q 'bodies="0"' "$TMP/c$B"; then
        grep -qE 'bodies="0" reason="(budget|no_candidates|compact-route)"' "$TMP/c$B" \
            && ok "#1 conceptual route, --token-budget=$B: the zero carries its reason=" \
            || no "#1 conceptual route, --token-budget=$B: bodies=\"0\" with no reason= (why-zero is unstated)"
    fi
done

# ── #1b: the COMPACT route's own ceiling-exhausted shape — the second copy of the silent branch ─────────
#    The compact <hops> builder was written a day after the body builder and inherited the same
#    "exhausted ceiling => turn the whole surface off, say nothing" branch. Same fix, same reserve
#    argument (kCompactAttrReserve is inside committedBytes), same rule: the attribute survives alone.
#    At --token-budget=400 the conceptual allowance is spent by header+sigs, so this fires by construction.
CT="$TMP/c400"
grep -q 'bundle="compact" bodies="0" reason="budget"' "$CT" \
    && ok "#1b compact route, ceiling exhausted: bodies=\"0\" reason=\"budget\" disclosed" \
    || no "#1b compact route, ceiling exhausted: no reason=\"budget\" disclosure (the silent shape, compact copy)"
# BY-DESIGN CHANGE (lego-charge fix round 4, review rv-wrap-recipe-k29 F1, rule 5 "never a silent cut"; reported under
# PROCESS rule 4): this arm used to require NO <hops> element at all, which made the cut silent — the hop rows vanished
# with nothing naming them. What it protected still holds and is asserted: no hop ROW (<h>) and no hops section legend
# leaks past a spent ceiling. The one <hops> allowed is the counted marker: empty, shown="0", capped="1", next= the same
# question without the budget.
ct_hops="$( grep -oE '<hops [^>]*>' "$CT" | head -1 )"
if [ -z "$ct_hops" ]; then
    no "#1b compact route, ceiling exhausted: no <hops> element — the cut hop rows are silent (rule 5)"
elif printf '%s' "$ct_hops" | grep -qE "^<hops shown=\"0\" total=\"[1-9][0-9]*\" capped=\"1\" next=\"--for=&apos;$CONCTASK&apos;\"/>\$" && ! grep -q '<h ' "$CT"; then
    ok "#1b compact route, ceiling exhausted: <hops> is the counted marker only, no hop row leaked ($ct_hops)"
else
    no "#1b compact route, ceiling exhausted: a <hops> other than the empty counted marker leaked past a spent ceiling ($ct_hops)"
fi
# #1c (fix round 4): the cut file tail under the same spent ceiling carries the call that lists the files it left out —
# the --for file page — and that call answers (rc 0, a <files> page holding at least the tail's total).
# forbudget-soft (rule 4, decision D-4): a capped <tail> is continued in EVERY regime, so the old negative "the default
# regime's tail carries no next=" is replaced by its positive: the default (no --token-budget) capped tail carries the same
# file-page next=, and that page holds at least the default tail's total. RED on base (d4325a8c: the default tail has no next=).
ct_tail="$( grep -oE '<tail [^>]*>' "$CT" | head -1 )"
ct_ttot="$( printf '%s' "$ct_tail" | sed -nE 's/.* total="([0-9]+)".*/\1/p' )"
"$BIN" src --for="$CONCTASK" --limit=40 --no-cache >"$TMP/cpage" 2>/dev/null; cp_rc=$?
cp_tot="$( grep -oE '^<files [^>]*>' "$TMP/cpage" | sed -nE 's/.* total="([0-9]+)".*/\1/p' )"
{ printf '%s' "$ct_tail" | grep -qE "capped=\"1\" next=\"--for=&apos;$CONCTASK&apos; --limit=40\"( p_only=\"[0-9]+\")?>\$" && [ "$cp_rc" -eq 0 ] \
  && [ -n "$cp_tot" ] && [ -n "$ct_ttot" ] && [ "$cp_tot" -ge "$ct_ttot" ] 2>/dev/null; } \
    && ok "#1c compact route, ceiling exhausted: the cut <tail> names the file page (next=), which pages $cp_tot files >= the tail's $ct_ttot" \
    || no "#1c compact route, ceiling exhausted: the cut <tail> has no working next= (tail '$ct_tail', page rc=$cp_rc total='${cp_tot:-none}')"
"$BIN" src --for="$CONCTASK" --no-cache >"$TMP/cdef" 2>/dev/null
cd_tail="$( grep -oE '<tail [^>]*>' "$TMP/cdef" | head -1 )"
cd_ttot="$( printf '%s' "$cd_tail" | sed -nE 's/.* total="([0-9]+)".*/\1/p' )"
if ! printf '%s' "$cd_tail" | grep -q ' capped="1"'; then
    no "#1c default regime premise: the default <tail> is not capped ('$cd_tail') — this arm measures nothing; re-anchor it on a capped tail"
# FOLD C (forbudget-soft round C; rule 4): the default tail carries page 0 of the file page, so its next= is the page FROM ITS
# FIRST UNPRINTED PAGE ROW (`--limit=40 --offset=K`); that call must answer with a <files> page whose rows start at K.
elif cd_off="$( printf '%s' "$cd_tail" | sed -nE "s/.*capped=\"1\" next=\"--for=&apos;$CONCTASK&apos; --limit=40( --offset=([0-9]+))?\"( p_only=\"[0-9]+\")?>\$/\2/p" )"; \
     printf '%s' "$cd_tail" | grep -qE "capped=\"1\" next=\"--for=&apos;$CONCTASK&apos; --limit=40( --offset=[0-9]+)?\"( p_only=\"[0-9]+\")?>\$" && [ "$cp_rc" -eq 0 ] \
     && [ -n "$cp_tot" ] && [ -n "$cd_ttot" ] && [ "$cp_tot" -ge "$cd_ttot" ] 2>/dev/null \
     && "$BIN" src --for="$CONCTASK" --limit=40 ${cd_off:+--offset=$cd_off} --no-cache 2>/dev/null | grep -qE "^<files [^>]* offset=\"${cd_off:-0}\""; then
    ok "#1c default regime: the capped <tail> carries the file-page next= (D-4; offset=${cd_off:-0}, FOLD C) that answers; the page holds $cp_tot files >= the tail's $cd_ttot"
else
    no "#1c default regime: the capped <tail> has no working file-page next= ('$cd_tail', page rc=$cp_rc total='${cp_tot:-none}')"
fi
# forbudget-soft (rule 4): a spent SOFT target has no header ladder, so the old "legend dropped (no reserve at a spent ceiling)"
# arm (which only ever read the FULL legend's spelling, so it passed vacuously on the compact default) is replaced by HL: the
# --legend=full twin keeps the bundle=compact: clause, and neither answer drops a clause "(ceiling)" or carries over_ceiling=.
# RED on base (d4325a8c: the full twin drops route=/r=/tail "(ceiling)" and labels over_ceiling="1").
"$BIN" src --for="$CONCTASK" --token-budget=400 --legend=full --no-cache >"$TMP/c400full" 2>/dev/null; cf_rc=$?
if [ "$cf_rc" -eq 0 ] && grep -q 'bundle=compact:' "$TMP/c400full" && ! grep -q '(ceiling)' "$TMP/c400full" "$CT" \
   && ! grep -q 'over_ceiling="1"' "$TMP/c400full" "$CT"; then
    ok "#1b compact route, target exhausted: the bundle legend is kept (--legend=full carries bundle=compact:), no (ceiling) drop, no over_ceiling"
else
    no "#1b compact route, target exhausted: legend/label (full rc=$cf_rc; bundle=compact: $( grep -c 'bundle=compact:' "$TMP/c400full" ), (ceiling) drops $( cat "$TMP/c400full" "$CT" | grep -c '(ceiling)' ), over_ceiling $( cat "$TMP/c400full" "$CT" | grep -c 'over_ceiling="1"' ))"
fi
grep -q '<sigs' "$CT" && ok "#1b compact route, ceiling exhausted: the <sigs> block is intact" \
    || no "#1b compact route, ceiling exhausted: the <sigs> block vanished"

# ── #2: the ceiling-exhausted case (the memo's exact mechanism) discloses, shell and all ────────────────
#    at 400 tokens the byte allowance (~850 B) is below the header+sigs floor, so leftBytes==0 by
#    construction — the branch that used to turn the whole surface off silently.
T="$TMP/n400"
grep -q 'bundle="auto" bodies="0" reason="budget"' "$T" \
    && ok "#2 ceiling-exhausted: bodies=\"0\" reason=\"budget\" disclosed" \
    || no "#2 ceiling-exhausted: missing bodies=\"0\" reason=\"budget\" on the <ctx> root"
# forbudget-soft (rule 4): the attribute-only shape existed to fit a hard ceiling; on a soft target the empty <bodies> shell
# rides (shown="0", capped="1", no <b> row — the no-body-bytes arm below still holds) and the bundle legend is kept (HL, read
# on the --legend=full twin; the compact default never spelled bundle=auto:), with no (ceiling) drop and no over_ceiling.
# RED on base (d4325a8c: no shell, the full legend drops clauses "(ceiling)", over_ceiling="1").
t_bodies="$( grep -oE '<bodies [^>]*>' "$T" | head -1 )"
{ printf '%s' "$t_bodies" | grep -qE '^<bodies shown="0" total="[1-9][0-9]*" capped="1">$' && ! grep -q '<b ' "$T"; } \
    && ok "#2 target exhausted: the empty <bodies> shell rides ($t_bodies), no body row" \
    || no "#2 target exhausted: expected the empty <bodies shown=\"0\" total=N capped=\"1\"> shell, got '${t_bodies:-none}'"
"$BIN" src --for="$NAMETASK" --token-budget=400 --legend=full --no-cache >"$TMP/n400full" 2>/dev/null; nf_rc=$?
if [ "$nf_rc" -eq 0 ] && grep -q 'bundle=auto:' "$TMP/n400full" && ! grep -q '(ceiling)' "$TMP/n400full" "$T" \
   && ! grep -q 'over_ceiling="1"' "$TMP/n400full" "$T"; then
    ok "#2 target exhausted: the bundle legend is kept (--legend=full carries bundle=auto:), no (ceiling) drop, no over_ceiling"
else
    no "#2 target exhausted: legend/label (full rc=$nf_rc; bundle=auto: $( grep -c 'bundle=auto:' "$TMP/n400full" ), (ceiling) drops $( cat "$TMP/n400full" "$T" | grep -c '(ceiling)' ), over_ceiling $( cat "$TMP/n400full" "$T" | grep -c 'over_ceiling="1"' ))"
fi
grep -q '<b [^>]*><!\[CDATA\[' "$T" \
    && no "#2 ceiling-exhausted: emitted body bytes past an exhausted ceiling (must serve none)" \
    || ok "#2 ceiling-exhausted: no body bytes (whole-body-or-nothing still holds)"
grep -q '<sigs' "$T" && ok "#2 ceiling-exhausted: the <sigs> block is intact" \
    || no "#2 ceiling-exhausted: the <sigs> block vanished"
# #2c (rv-knob-honesty-068 C2; CHECKLIST 17) the intact-block grep above CAN FAIL on exactly this document. It is a ceiling-
# exhausted one: its <sigs> is capped, its next= rides unpaid and the root carries over_ceiling="1" with the clause defining
# that in the header legend — BEFORE the real tag. A clause that spelled the tag literally (dd6e4c8e's floor clause did)
# satisfied `grep -q '<sigs'` with the block cut out, and moved sigsblock()'s span start into the legend comment. Premise
# first (a floor document: root over_ceiling="1", the LAST <sigs tag capped with a next=; else this arm proves nothing), then:
# the same document with its real block removed must NOT match, and sigsblock() must start at the real tag (its span never
# crosses a comment close). RED on dd6e4c8e.
# forbudget-soft (rule 4): the premise is re-anchored on what still holds. A soft target labels nothing (no over_ceiling=),
# but the 400 document still has a capped <sigs> carrying next= with the header legend's sigs/next= clauses BEFORE the real
# tag, so the two anti-forgery greps keep their teeth. Premise: no over_ceiling on the root, the LAST <sigs tag capped + next=.
if ! grep -qE '^<ctx [^>]* over_ceiling=' "$T" && grep -oE '<sigs [^>]*>' "$T" | tail -1 | grep -q ' capped="1".* next="'; then
    python3 -c 'import sys; s=open(sys.argv[1],"rb").read(); a=s.rfind(b"<sigs"); b=s.find(b"</sigs>",a); sys.stdout.buffer.write(s[:a]+s[b+7:] if a>=0 and b>=0 else s)' "$T" >"$TMP/n400_nosigs"
    grep -q '<sigs' "$TMP/n400_nosigs" \
        && no "#2c the intact-block grep still matches with the <sigs> block removed — a legend clause spells the tag" \
        || ok "#2c the intact-block grep FAILS once the <sigs> block is removed (no legend clause spells the tag)"
    sigsblock "$T" | grep -q -- '-->' \
        && no "#2c sigsblock() starts inside the header legend comment, not at the real tag" \
        || ok "#2c sigsblock() starts at the real <sigs> tag"
else
    no "#2c premise: the --token-budget=400 document has no capped <sigs> with next= (or labels over_ceiling= on a soft target) — re-anchor this arm on one that is"
fi
"$BIN" src --for="$NAMETASK" --token-budget=400 --signatures-only --no-cache >"$TMP/n400so" 2>/dev/null
sigsblock "$T" >"$TMP/s_a"; sigsblock "$TMP/n400so" >"$TMP/s_s"
[ -s "$TMP/s_a" ] || no "#2 presence: could not extract a <sigs> block from the disclosed run"
diff -q "$TMP/s_a" "$TMP/s_s" >/dev/null \
    && ok "#2 ceiling-exhausted: <sigs> byte-identical to --signatures-only (disclosure never eats the signature budget)" \
    || no "#2 ceiling-exhausted: the disclosure changed the <sigs> bytes"
ET_T=$( grep -o 'est_tokens="[0-9]*"' "$T" | head -1 | grep -o '[0-9]*' )
ET_S=$( grep -o 'est_tokens="[0-9]*"' "$TMP/n400so" | head -1 | grep -o '[0-9]*' )
# forbudget-soft (rule 4): the old band (0..30 tokens: the attribute's reserved worth) priced a disclosure squeezed under a hard
# ceiling; the legend clause and the <bodies> shell now ride, so the band is replaced by honest pricing of the extra bytes:
# est_tokens rises (>= 1) and by no more than one token per kMinBytesPerToken (2.36) bytes of the byte delta (+1 rounding).
BY_T=$( wc -c <"$T" | tr -d ' ' ); BY_S=$( wc -c <"$TMP/n400so" | tr -d ' ' )
ET_MAX=$( python3 -c 'import math,sys; print(math.ceil(max(0,int(sys.argv[1])-int(sys.argv[2]))/2.36)+1)' "${BY_T:-0}" "${BY_S:-0}" 2>/dev/null )
{ [ -n "${ET_T:-}" ] && [ -n "${ET_S:-}" ] && [ -n "${ET_MAX:-}" ] && [ "$BY_T" -gt "$BY_S" ] && [ $(( ET_T - ET_S )) -ge 1 ] && [ $(( ET_T - ET_S )) -le "$ET_MAX" ]; } \
    && ok "#2 target exhausted: est_tokens prices the disclosure bytes ($ET_T vs $ET_S for +$(( BY_T - BY_S )) B, band 1..$ET_MAX)" \
    || no "#2 target exhausted: est_tokens delta out of band (tight=${ET_T:-?} vs sig-only=${ET_S:-?}, bytes ${BY_T:-?} vs ${BY_S:-?}, max ${ET_MAX:-?})"

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
    if [ "$lint" = 1 ]; then ok "#5 all disclosed shapes well-formed XML (G4)"; else no "#5 malformed XML"; fi
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
