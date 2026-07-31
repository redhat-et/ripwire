#!/usr/bin/env bash
# knownitemcheck.sh — PHASE 2 gate (RESEARCH_outputEconomy note + user ask): the known-item retrieval eval.
#
# WHY: the co-change --eval is SEED-based — it validates which ranker recovers a change's OTHER files, but it
# structurally CANNOT validate query-TIME ranker choice (does name-exact beat subtoken+body on a NAME query?
# does anchoring help or hurt?). --eval-retrieval adds a standard known-item IR eval: for doc-commented
# symbols, query by NAME and by a doc-comment PHRASE, and measure the rank of the gold symbol (in-corpus by
# construction) per ranker per query-mode. This gate asserts the eval's OUTPUT is well-formed, deterministic,
# and numerically sane (MRR in [0,1], recall monotone) — it does NOT assert which ranker wins (that's the
# reported finding, corpus-dependent).
#
# Usage:  CTXPACK_BIN=build/ctxpack bash test/knownitemcheck.sh   |   CTXPACK_BIN=asan/ctxpack bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "knownitemcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out.txt"; OUT2="$TMP/out2.txt"

# run on src/ (rich in doc-commented symbols)
"$BIN" src --eval-retrieval --no-cache >"$OUT" 2>/dev/null

# ── #1: the eval ran and emitted the header + all 8 (ranker × mode) rows ───────────────────────────────
{ grep -q 'known-item' "$OUT" \
    && [ "$( grep -cE '^  (subtoken|name-exact|anchored|routed) +(name|doc-phrase) ' "$OUT" )" -eq 8 ]; } \
    && ok "header + all 8 ranker×mode rows present" \
    || no "missing header or not exactly 8 data rows (got $( grep -cE '^  (subtoken|name-exact|anchored|routed) +(name|doc-phrase) ' "$OUT" ))"

# ── #2: every MRR is a number in [0,1] and recall values are percentages in [0,100] ────────────────────
sane=1
while read -r ranker mode mrr r1 r5 r10; do
    [ -z "$ranker" ] && continue
    # MRR in [0,1]  (awk float compare)
    awk -v v="$mrr" 'BEGIN{exit !(v>=0 && v<=1)}' || { echo "    MRR out of [0,1]: $ranker $mode $mrr"; sane=0; }
    for pct in "$r1" "$r5" "$r10"; do
        p="${pct%\%}"
        awk -v v="$p" 'BEGIN{exit !(v>=0 && v<=100)}' || { echo "    recall out of [0,100]: $ranker $mode $pct"; sane=0; }
    done
    # recall must be monotone non-decreasing: @1 <= @5 <= @10
    a="${r1%\%}"; b="${r5%\%}"; c="${r10%\%}"
    awk -v a="$a" -v b="$b" -v c="$c" 'BEGIN{exit !(a<=b && b<=c)}' || { echo "    recall not monotone: $ranker $mode $r1 $r5 $r10"; sane=0; }
done < <( grep -E '^  (subtoken|name-exact|anchored|routed) +(name|doc-phrase) ' "$OUT" )
[ "$sane" = 1 ] && ok "all MRR in [0,1], recall in [0,100], recall@1<=@5<=@10 (monotone)" \
    || no "some MRR/recall out of range or non-monotone"

# ── #3: DETERMINISM — two runs byte-identical (no threading in the reported numbers) ───────────────────
"$BIN" src --eval-retrieval --no-cache >"$OUT2" 2>/dev/null
diff -q "$OUT" "$OUT2" >/dev/null \
    && ok "deterministic: two runs byte-identical" \
    || no "NON-deterministic: two runs differ"

# ── #4: plain-text / xmllint clean. The eval is a plain-text report (like --eval), NOT an XML document, so
#    it must NOT masquerade as XML: it carries no stray '<...>' markup that a naive xmllint would choke on
#    (the report uses 'note:' prose, not comments). We assert there is no angle-bracket markup line. ──────
if grep -qE '<[a-zA-Z/!]' "$OUT"; then
    no "output contains XML-looking markup — the plain-text eval must not emit tags (would confuse an xmllint consumer)"
else
    ok "plain-text clean: no XML markup lines (won't be mistaken for an XML document)"
fi

# ── #5: name-exact must be PERFECTLY defined on the NAME query mode — a known-item name query should recover
#    the gold at rank 1 for the vast majority (this is the sanity floor: if name-exact can't find a symbol by
#    its own exact name, the ranker is broken). Assert name-exact/name recall@1 >= 50%. ──────────────────
NE_R1="$( grep -E '^  name-exact +name ' "$OUT" | awk '{print $4}' | tr -d '%' )"
{ [ -n "$NE_R1" ] && awk -v v="$NE_R1" 'BEGIN{exit !(v>=50)}'; } \
    && ok "name-exact/name recall@1 ($NE_R1%) >= 50% — the known-item sanity floor holds" \
    || no "name-exact/name recall@1 ($NE_R1%) < 50% — a name query can't recover its own symbol (broken)"

# ── #6: the sample is non-trivial (a handful of doc-commented symbols isn't a benchmark) ───────────────
NSAMP="$( grep -oE 'known-item, [0-9]+ doc-commented' "$OUT" | grep -oE '[0-9]+' )"
{ [ -n "$NSAMP" ] && [ "$NSAMP" -ge 20 ] 2>/dev/null; } \
    && ok "sample size ($NSAMP) >= 20 doc-commented symbols" \
    || no "sample too small ($NSAMP) — not a meaningful benchmark"

# ── #7: ROUTER SAFETY — the confidence-gated router must never CRATER either query mode. It must track the
#    BETTER of the two base rankers on BOTH modes: routed/name ~= name-exact/name (identifier-query win kept)
#    AND routed/doc-phrase ~= subtoken/doc-phrase (conceptual queries recovered, no over-fire to name-exact).
#    Assert each within 0.03 MRR of its target. This is the standing regression guard on the routing gate:
#    if a future change re-introduces the over-eager "any word names a symbol" trigger, routed/doc-phrase
#    collapses and this trips. (Pre-fix routed/doc-phrase was 0.42 src / 0.14 root — far outside 0.03.) ─────
mrrof(){ grep -E "^  $1 +$2 " "$OUT" | awk '{print $3}'; }
SUB_DP="$( mrrof subtoken 'doc-phrase' )"
RT_DP="$( mrrof routed 'doc-phrase' )"
NE_NM="$( mrrof name-exact 'name' )"
RT_NM="$( mrrof routed 'name' )"
{ [ -n "$SUB_DP" ] && [ -n "$RT_DP" ] && awk -v r="$RT_DP" -v s="$SUB_DP" 'BEGIN{d=s-r; if(d<0)d=-d; exit !(d<=0.03)}'; } \
    && ok "routed/doc-phrase MRR ($RT_DP) within 0.03 of subtoken/doc-phrase ($SUB_DP) — conceptual queries not cratered" \
    || no "routed/doc-phrase MRR ($RT_DP) NOT within 0.03 of subtoken/doc-phrase ($SUB_DP) — router over-fires name-exact on prose"
{ [ -n "$NE_NM" ] && [ -n "$RT_NM" ] && awk -v r="$RT_NM" -v n="$NE_NM" 'BEGIN{d=n-r; if(d<0)d=-d; exit !(d<=0.03)}'; } \
    && ok "routed/name MRR ($RT_NM) within 0.03 of name-exact/name ($NE_NM) — identifier-query win preserved" \
    || no "routed/name MRR ($RT_NM) NOT within 0.03 of name-exact/name ($NE_NM) — routing lost the identifier win"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
