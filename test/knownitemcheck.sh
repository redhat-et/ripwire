#!/usr/bin/env bash
# knownitemcheck.sh — PHASE 2 gate ( note + user ask): the known-item retrieval eval.
#
# WHY: the co-change --eval is SEED-based — it validates which ranker recovers a change's OTHER files, but it
# structurally CANNOT validate query-TIME ranker choice (does name-exact beat subtoken+body on a NAME query?
# does anchoring help or hurt?). --eval-retrieval adds a standard known-item IR eval: for doc-commented
# symbols, query by NAME and by a doc-comment PHRASE, and measure the rank of the gold symbol (in-corpus by
# construction) per ranker per query-mode. This gate asserts the eval's OUTPUT is well-formed, deterministic,
# and numerically sane (MRR in [0,1], recall monotone) — it does NOT assert which ranker wins (that's the
# reported finding, corpus-dependent).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/knownitemcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
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

# ── #8/#9/#10: THE SAMPLER. Everything above grades the RANKER; these three grade the INSTRUMENT that
#    chooses which symbols the ranker is graded on. The defect they exist for: the gold set was built by
#    walking symbol ids from 0 and stopping at the first kMaxSample doc-commented symbols. Symbol ids are
#    assigned in CRAWL order and the crawl is sorted by path, so the sample was "whichever N doc-commented
#    symbols sort earliest by path" — a documented file added under an early-sorting directory silently
#    displaces real symbols off the tail and MOVES A PUBLISHED NUMBER with the ranker byte-identical.
#    Measured on db6a416d with an identical 60-symbol probe placed at two paths: aaa_probe/ gave
#    subtoken/name MRR 0.834, zzz_probe/ gave 0.729. Same corpus, same content, 0.105 MRR from spelling.
#    A sample whose rule is invisible is the thing that failed, so the eval must PRINT its own population
#    and rule, and membership must depend only on a symbol's own identity — never on what sorts before it.

PROBE_N=60
# A BOUNDED corpus, not all of src/: the eval is now exhaustive over its population, so a full-src arm
# would cost ~40 s each and these three arms run four of them. A fixed 24-file slice keeps the sampler
# arms in seconds while still giving the ranker a few hundred real symbols to be graded on. The slice is
# taken in sorted order so it is the same 24 files on every machine.
mkcorpus(){ # $1 = dest dir, $2 = probe subdir ("" for none)
    rm -rf "$1"; mkdir -p "$1/src"
    ls "$ROOT/src"/*.h | sort | head -24 | while read -r f; do cp "$f" "$1/src/"; done
    if [ -n "$2" ]; then
        mkdir -p "$1/$2"
        i=0
        : >"$1/$2/probe.h"
        while [ "$i" -lt "$PROBE_N" ]; do
            printf '// Probe helper number %d that reconciles a widget ledger for the sampler gate.\ninline int probeReconcileLedger%02d( int x ) { return x + %d; }\n\n' "$i" "$i" "$i" >>"$1/$2/probe.h"
            i=$(( i + 1 ))
        done
    fi
}
rows(){ grep -E '^  (subtoken|name-exact|anchored|routed) +(name|doc-phrase) ' "$1"; }
# the sampler's self-disclosure line: "  sample: population=N scored=M rule=..."
popof(){ grep -oE 'population=[0-9]+' "$1" | head -1 | grep -oE '[0-9]+'; }
scoredof(){ grep -oE 'scored=[0-9]+' "$1" | head -1 | grep -oE '[0-9]+'; }

mkcorpus "$TMP/early" "aaa_probe"
mkcorpus "$TMP/late"  "zzz_probe"
mkcorpus "$TMP/plain" ""
"$BIN" "$TMP/early" --eval-retrieval --no-cache >"$TMP/early.txt" 2>/dev/null
"$BIN" "$TMP/late"  --eval-retrieval --no-cache >"$TMP/late.txt"  2>/dev/null
"$BIN" "$TMP/plain" --eval-retrieval --no-cache >"$TMP/plain.txt" 2>/dev/null

# ── #8: ORDER-INDEPENDENCE. Two corpora with byte-identical content differing ONLY in where the probe
#    file sorts must produce identical numbers. This is the defect, reproduced as a test. ───────────────
if diff <( rows "$TMP/early.txt" ) <( rows "$TMP/late.txt" ) >/dev/null 2>&1; then
    ok "sampler order-independent: probe at an EARLY vs LATE path gives identical numbers"
else
    no "sampler is PATH-ORDER DEPENDENT — the same probe file moves the numbers by where it sorts:"
    diff <( rows "$TMP/early.txt" ) <( rows "$TMP/late.txt" ) | sed 's/^/      /'
fi

# ── #9: the sample must DISCLOSE its own population, how many it scored, and by what rule. A sample that
#    does not say how big the population was cannot be audited for silent shrinkage. ────────────────────
P_E="$( popof "$TMP/early.txt" )"; S_E="$( scoredof "$TMP/early.txt" )"
{ [ -n "$P_E" ] && [ -n "$S_E" ] && grep -q 'rule=' "$TMP/early.txt" && [ "$P_E" -ge "$S_E" ] 2>/dev/null; } \
    && ok "sample self-disclosed: population=$P_E scored=$S_E and a named rule= (population >= scored)" \
    || no "sample does not disclose population=/scored=/rule= (got population='$P_E' scored='$S_E') — an invisible sampling rule is unauditable"

# ── #10: POPULATION RE-DERIVATION. Independently derived: the probe adds exactly PROBE_N qualifying
#    doc-commented symbols, so population must rise by exactly PROBE_N. Derives the count from a
#    CONTROLLED INPUT rather than reimplementing docPhraseFirstLine (which would just clone the bug). ──
P_P="$( popof "$TMP/plain.txt" )"
if [ -n "$P_E" ] && [ -n "$P_P" ]; then
    DELTA=$(( P_E - P_P ))
    [ "$DELTA" -eq "$PROBE_N" ] \
        && ok "population re-derives: adding $PROBE_N doc-commented symbols raised population by exactly $DELTA" \
        || no "population moved by $DELTA, expected exactly $PROBE_N ($P_P -> $P_E) — the sampler is miscounting its own population"
else
    no "cannot re-derive population — no population= field emitted"
fi

# ── #11/#12: WHICH INGEST PATH THE RUN TOOK, disclosed. The defect these exist for cost 94% of this eval's
#    CPU and was invisible in every byte of output. lexicalScoresTiered has carried a persisted-stats path
#    since B0.2 (per-symbol subtoken stats built once at parse time, pure lookups per query); it is taken
#    only when the ingest is RICH, and main.cpp's needsValueUses enumerates which verbs ask for that. The
#    eval verbs were simply missing from the list, so they fell to the scan branch and re-tokenized the
#    whole corpus on every one of ~6,000 calls. Nothing said so: a 16x per-query swing, decided by a flag,
#    with no attribute naming it anywhere. Finding it needed a temporary fprintf compiled into the branch.
#    So the regime states itself now, the same way the sampler's own rule had to (#9): lex= on the eval's
#    disclosure line, lex_stats= on doctor's index-cache row.

LEXOUT="$TMP/lex.txt"
"$BIN" src --eval-retrieval --no-cache >"$LEXOUT" 2>/dev/null
LEXPATH="$( grep -oE 'lex=[a-z-]+' "$LEXOUT" | head -1 | cut -d= -f2 )"
{ [ -n "$LEXPATH" ] && [ "$LEXPATH" = "rich" ]; } \
    && ok "eval discloses its lexical path and it is RICH (lex=$LEXPATH) — persisted stats, no per-query corpus re-tokenize" \
    || no "eval's lexical path is '${LEXPATH:-<undisclosed>}', expected rich — a LEAN ingest silently re-tokenizes the corpus per query (add the verb to main.cpp's needsValueUses), and an UNDISCLOSED path is the invisibility that hid it for as long as this eval has existed"

# ── #12: MEMBERSHIP, disclosed and re-derived. --doctor never ingests, so it cannot honestly report "the
#    path this run took"; what it can answer is the question that was actually unanswerable — WHICH VERBS
#    ask for the rich ingest. That enumeration lives in exactly one place (needsValueUses) and doctor's
#    roster is derived by ASKING that predicate per verb, never by restating the list, so the roster cannot
#    drift from the behaviour the way a second hand-written copy would. cachesplitcheck already proves the
#    lean/rich MECHANISM; nothing proved its MEMBERSHIP, which is the gap the eval fell through.
DOCOUT="$TMP/doc.txt"
"$BIN" src --doctor >"$DOCOUT" 2>/dev/null
ROSTER="$( grep -oE 'rich_verbs="[^"]*"' "$DOCOUT" | head -1 | cut -d'"' -f2 )"
if [ -z "$ROSTER" ]; then
    no "--doctor does not disclose rich_verbs= — which verbs get the persisted-stats path is unanswerable from any output, which is exactly how the eval sat on the scan path unnoticed"
else
    # the eval verbs must be IN it (the defect), and a known-lean verb must be OUT of it (the control: a
    # roster that listed everything would satisfy the first assertion while meaning nothing).
    inRoster(){ case ",$ROSTER," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
    miss=""
    for v in eval-retrieval eval-mined eval-skills for exemplar uses metrics; do
        inRoster "$v" || miss="$miss $v"
    done
    extra=""
    for v in grep callers doctor expand; do
        inRoster "$v" && extra="$extra $v"
    done
    if [ -n "$miss" ]; then
        no "--doctor's rich_verbs= omits:$miss — a verb that scores many queries against one tree and is NOT in needsValueUses re-tokenizes the corpus per query"
    elif [ -n "$extra" ]; then
        no "--doctor's rich_verbs= wrongly includes lean verb(s):$extra — a roster that names everything proves nothing (it would satisfy the membership check while meaning nothing)"
    else
        ok "rich_verbs= roster is complete and discriminating: the eval verbs are in it, nav/read verbs are not"
    fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
