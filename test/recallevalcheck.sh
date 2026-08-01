#!/usr/bin/env bash
# recallevalcheck.sh — gate for the held-out recall/ranking eval (bench/recalleval/,
# PLAN_outputAudit_2026-07-28.md §Sequencing: the measuring instrument that must precede §P2b and
# §P4's ranking half). Asserts the INSTRUMENT works — labels load clean, both lanes computable with
# zero skipped queries, two runs byte-identical — and pins only FLOORS/CEILINGS loose enough to
# survive intentional improvement (§P7 philosophy: never pin exact scores; a ranking fix should move
# pollution@5 DOWN and must not trip this gate by improving).
#
# Baseline 2026-07-28 (pre-§P2b/§P4, the numbers any future ranking change must beat):
#   recall  lane: strict_r1=82.1 strict_r5=89.7 lenient_r1=84.6 lenient_r5=97.4 mrr_lenient=0.885 pollution5=2.1
#   ranking lane: strict_r1=56.2 strict_r5=75.0 lenient_r1=59.4 lenient_r5=81.2 mrr_lenient=0.689 pollution5=8.8
#   (ranking adversarial class: pollution5=28.0 — the §P4 number the future fix must move.)
# §P4 landed 2026-07-28 (tier down-weight, filter.h rankTierMultiplierOf ×0.35 in the ranking lenses):
#   ranking lane: strict_r1=59.4 strict_r5=78.1 lenient_r1=65.6 lenient_r5=84.4 mrr_lenient=0.726 pollution5=0.0
#   (adversarial class pollution5=0.0; recall lane byte-identical — §P4 does not touch the docs lens.)
#   Ranking-lane ceilings/floors below are tightened to sit just past those numbers, still floor-style (§P7).
# RECALIBRATED 2026-07-29 (capture-audit-4 Phase 0, R21 owner ruling — labels_ranking.tsv edited with
# per-label reasons recorded in that file; zero ranker changes; these are the frozen bars here-forward):
#   recall  lane: strict_r1=82.1 strict_r5=89.7 lenient_r1=84.6 lenient_r5=97.4 mrr_strict=0.839 mrr_lenient=0.890 pollution5=2.1
#   ranking lane: strict_r1=59.4 strict_r5=78.1 lenient_r1=62.5 lenient_r5=78.1 mrr_strict=0.675 mrr_lenient=0.700 pollution5=0.0
#   (ranking adversarial class pollution5=0.0. NOTE: pollution 0 is a RANKING-LANE claim only — the
#   recall lane's honest baseline is 2.1%; never report "pollution 0 every class". The lenient_r5
#   81.2→78.1 step is the from-trace label re-anchor pricing out a path-only artifact, not a ranker
#   regression; floors below unchanged — still comfortably floor-style under the recalibrated numbers.)
#
# RE-BASELINED 2026-07-31 for the PUBLIC EXPORT (labels_recall.tsv re-authored — 27 of its 39 labels
# named documents this export does not ship, so the recall lane was measuring almost nothing; zero
# ranker changes). Measured on the exported tree, recall=42 / ranking=32 labels, zero skipped:
#   recall  lane: strict_r1=52.4 strict_r5=88.1 lenient_r1=57.1 lenient_r5=92.9 mrr_strict=0.669 mrr_lenient=0.720 pollution5=10.0
#   ranking lane: strict_r1=56.2 strict_r5=75.0 lenient_r1=59.4 lenient_r5=75.0 mrr_strict=0.642 mrr_lenient=0.676 pollution5=0.0
#   (ranking adversarial class pollution5=0.0 — unchanged, and its labels are unchanged.)
#
# TWO THINGS THAT MOVED, both measured, neither a ranker regression:
#   1. Recall-lane pollution 2.1% -> 10.0% is CORPUS COMPOSITION, not a ranking change. The private
#      tree carried ~70 real documents against ~19 fixture markdown files under test/; this export
#      carries ~27 against the same ~19, so the fixture share of any top-5 is structurally higher.
#      Measured split of the 25 polluted slots before the README exemption below: 4 were
#      test/README.md (a legitimate shipped document the path predicate cannot distinguish), 21 were
#      genuine fixture documents. run_recalleval.py now exempts any basename README.md from the
#      fixture predicate — a rule about READMEs, not a special case — leaving 21/210 = 10.0%.
#      FINDING FOR A LATER ROUND: the fixture path-tier de-prioritization was applied to the RANKING
#      lenses only. The recall lens has no fixture defense at all; it looked clean on the private
#      corpus only because real documents outnumbered fixtures there. The ceiling is widened below to
#      16% so this gate measures a regression rather than the corpus, and that gap stays visible.
#   2. Ranking-lane lenient_r5 78.1 -> 75.0 and mrr 0.700 -> 0.676 on UNCHANGED labels: the export
#      moved source files (the first-party infrastructure headers relocated), so a ranked set over a
#      different tree is a different measurement. Recorded, not chased. Floors below still hold with
#      real headroom.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/recallevalcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null || { echo "recallevalcheck: python3 required"; exit 2; }
echo "recallevalcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/run1.txt"; OUT2="$TMP/run2.txt"

# ── #1: the harness runs end-to-end, labels load clean ─────────────────────────────────────────────────
RIPWIRE_BIN="$BIN" python3 "$ROOT/bench/recalleval/run_recalleval.py" >"$OUT" 2>"$TMP/err1.txt"
rc=$?
{ [ "$rc" = 0 ] && grep -q '^labels OK: recall=' "$OUT"; } \
    && ok "harness exit 0, labels load clean ($( grep '^labels OK' "$OUT" ))" \
    || { no "harness failed (rc=$rc): $( head -3 "$TMP/err1.txt" )"; echo 'FAILURES ABOVE'; exit 1; }

# ── #2: both lanes present with a non-trivial sample and ZERO skipped labels ───────────────────────────
REC="$( grep -E '^AGG\trecall\t' "$OUT" )"
RNK="$( grep -E '^AGG\tranking\t' "$OUT" )"
field(){ printf '%s' "$1" | tr '\t' '\n' | sed -n "s/^$2=//p"; }
{ [ -n "$REC" ] && [ -n "$RNK" ]; } && ok "both AGG rows present" || no "missing an AGG row"
RN="$( field "$REC" n )"; KN="$( field "$RNK" n )"
{ [ "${RN:-0}" -ge 30 ] && [ "${KN:-0}" -ge 25 ]; } \
    && ok "sample sizes recall=$RN (>=30), ranking=$KN (>=25)" \
    || no "sample too small (recall=$RN ranking=$KN)"
{ [ "$( field "$REC" skipped )" = 0 ] && [ "$( field "$RNK" skipped )" = 0 ]; } \
    && ok "zero skipped labels — every labelled path resolves on disk" \
    || no "skipped labels (a labelled doc/symbol path no longer exists — fix the label)"

# ── #3: metrics computable and numerically sane (recall@1 <= recall@5, values in range) ────────────────
sane=1
for row in "$REC" "$RNK"; do
    r1="$( field "$row" lenient_r1 )"; r5="$( field "$row" lenient_r5 )"
    mrr="$( field "$row" mrr_lenient )"; pol="$( field "$row" pollution5 )"
    awk -v a="$r1" -v b="$r5" 'BEGIN{exit !(a>=0 && b<=100 && a<=b)}' || sane=0
    awk -v m="$mrr" 'BEGIN{exit !(m>=0 && m<=1)}' || sane=0
    awk -v p="$pol" 'BEGIN{exit !(p>=0 && p<=100)}' || sane=0
done
[ "$sane" = 1 ] && ok "metrics in range: recall@1<=recall@5, MRR in [0,1], pollution in [0,100]" \
    || no "a metric is out of range or non-monotone"

# ── #4: DETERMINISM — two runs byte-identical ──────────────────────────────────────────────────────────
RIPWIRE_BIN="$BIN" python3 "$ROOT/bench/recalleval/run_recalleval.py" >"$OUT2" 2>/dev/null
diff -q "$OUT" "$OUT2" >/dev/null \
    && ok "deterministic: two full runs byte-identical" \
    || no "NON-deterministic: two runs differ"

# ── #5: FLOORS (loose, must survive improvement) + pollution CEILINGS (improvement lowers pollution,
#    so a ceiling above today's baseline only trips on regression). Never pin exact scores (§P7). ───────
floor(){ awk -v v="$1" -v f="$2" 'BEGIN{exit !(v>=f)}'; }
ceil(){  awk -v v="$1" -v c="$2" 'BEGIN{exit !(v<=c)}'; }
RL5="$( field "$REC" lenient_r5 )"; RMRR="$( field "$REC" mrr_lenient )"; RPOL="$( field "$REC" pollution5 )"
KL5="$( field "$RNK" lenient_r5 )"; KMRR="$( field "$RNK" mrr_lenient )"; KPOL="$( field "$RNK" pollution5 )"
floor "$RL5" 85   && ok "recall lane lenient recall@5 ($RL5%) >= floor 85% (baseline 97.4%)"  || no "recall lane lenient recall@5 ($RL5%) under floor 85%"
floor "$RMRR" 0.60 && ok "recall lane lenient MRR ($RMRR) >= floor 0.60 (exported-tree baseline 0.720)" || no "recall lane lenient MRR ($RMRR) under floor 0.60"
ceil  "$RPOL" 16   && ok "recall lane pollution@5 ($RPOL%) <= ceiling 16% (exported-tree baseline 10.0%; see the composition note above)" || no "recall lane pollution@5 ($RPOL%) over ceiling 16% — generated/fixture docs are retaking --recall"
floor "$KL5" 70   && ok "ranking lane lenient recall@5 ($KL5%) >= floor 70% (post-§P4 84.4%)"  || no "ranking lane lenient recall@5 ($KL5%) under floor 70%"
floor "$KMRR" 0.55 && ok "ranking lane lenient MRR ($KMRR) >= floor 0.55 (post-§P4 0.726)"    || no "ranking lane lenient MRR ($KMRR) under floor 0.55"
ceil  "$KPOL" 5    && ok "ranking lane pollution@5 ($KPOL%) <= ceiling 5% (post-§P4 0.0%)"    || no "ranking lane pollution@5 ($KPOL%) over ceiling 5% — fixtures/present are retaking --for"

# ── #5b: §P4's own number — the adversarial class (queries built to let fixtures/decks win) must stay
#    de-polluted. Ceiling 8% = one polluted top-5 slot across the class (5 queries × 5 slots → 1/25 = 4%);
#    two slots trips. Pre-§P4 baseline was 28.0%, post-§P4 0.0%. ─────────────────────────────────────────
APOL="$( grep -E $'^  CLASS\tranking\tadversarial\t' "$OUT" | sed -n 's/.*pollution5=\([0-9.]*\)%$/\1/p' )"
[ -n "$APOL" ] && ceil "$APOL" 8 \
    && ok "ranking adversarial-class pollution@5 ($APOL%) <= ceiling 8% (pre-§P4 28.0%, post-§P4 0.0%)" \
    || no "ranking adversarial-class pollution@5 (${APOL:-missing}) over ceiling 8% — the §P4 class is regressing"

# ── #6: §P4 direct XML assertions over the shipping binary at THIS repo root (the plan's cited repro +
#    the two interactions the tier down-weight must NOT break). Paths asserted here are pinned by the
#    label files, whose on-disk presence check #2 already enforces. ──────────────────────────────────────
CAND="$TMP/cand.xml"

# 6a — the plan's cited query: the real implementation must outrank every fixture/deck row (RED pre-§P4:
#      a test/chafix stub held rank 1). Rank of pageRankDouble strictly above the best test/ or present/ row.
"$BIN" . --for="pagerank power iteration" --format=candidates --top-k=10 >"$CAND" 2>/dev/null
PRRANK="$( tr '<' '\n' <"$CAND" | sed -n 's/^cand r="\([0-9]*\)" [^>]*n="pageRankDouble".*/\1/p' | head -1 )"
FIXRANK="$( tr '<' '\n' <"$CAND" | grep -E '^cand ' | grep -E 'p="\./(test|present)/' | sed -n 's/^cand r="\([0-9]*\)".*/\1/p' | sort -n | head -1 )"
if [ -n "$PRRANK" ] && { [ -z "$FIXRANK" ] || [ "$PRRANK" -lt "$FIXRANK" ]; }; then
    ok "cited query ranks pageRankDouble (r=$PRRANK) above any test/present row (best fixture r=${FIXRANK:-none in top-10})"
else
    no "cited query: pageRankDouble r=${PRRANK:-absent} vs best fixture/deck row r=${FIXRANK:-none} — §P4 repro is back"
fi

# 6b — mention anchor beats the tier penalty: a fixture file literally NAMED in the task still surfaces
#      in the top 5 (de-prioritized is not unanchorable).
"$BIN" . --for="fix the virtual dispatch in test/chafix/cha.cpp" --format=candidates --top-k=5 >"$CAND" 2>/dev/null
tr '<' '\n' <"$CAND" | grep -E '^cand ' | grep -q 'p="\./test/chafix/cha\.cpp"' \
    && ok "mention anchor survives the penalty: task naming test/chafix/cha.cpp surfaces it in the top 5" \
    || no "mention anchor lost to the tier penalty: test/chafix/cha.cpp absent from its own task's top 5"

# 6c — name-exact route beats the tier penalty: a fixture symbol queried by its EXACT name is still rank 1
#      (its competitors score 0 — shrinking the only hit must not bury it).
"$BIN" . --for="Robot" --format=candidates --top-k=1 >"$CAND" 2>/dev/null
tr '<' '\n' <"$CAND" | grep -E '^cand r="1" ' | grep 'n="Robot"' | grep -q 'p="\./test/chafix/cha\.cpp"' \
    && ok "name-exact survives the penalty: --for=Robot still lands the fixture class at rank 1" \
    || no "name-exact buried by the tier penalty: --for=Robot no longer lands test/chafix Robot at rank 1"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
