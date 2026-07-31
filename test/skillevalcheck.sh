#!/usr/bin/env bash
# skillevalcheck.sh — gate for --eval-skills, the labelled skill-ROUTING eval (src/skilleval.h,
# RESEARCH_skillEval2026.md). Two jobs:
#
#   (a) pin that the harness WORKS: runs clean on the committed corpus (test/skillevalfix/prompts.tsv),
#       deterministic, counts agree with the corpus, the TRIVIAL keyword-overlap baseline is MEASURED
#       (printed, never asserted away), and the headline arm (bm25-desc) clears an absolute floor —
#       a description edit that tanks routing fails here, loudly.
#   (b) prove the metric CAN FAIL — the --eval-stray lesson (3 of 4 plausible statistics were INVERTED
#       until labelled data exposed them): feed deliberately WRONG labels and prove hit@1 collapses;
#       SWAP the positive/negative labels and prove sep-auc inverts to exactly 1-auc (and lands < 0.5).
#       A metric that cannot drop under sabotage measures nothing.
#
#   test/skillevalcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/skillevalcheck.sh
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/skillevalfix/prompts.tsv"
SKILLS="$ROOT/skills"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$CORPUS" ] || { echo "no corpus at $CORPUS"; exit 2; }

echo "skillevalcheck: BIN=$BIN  CORPUS=$CORPUS"

# ── 1) the harness runs clean and is deterministic ────────────────────────────────────────────────────
"$BIN" "$SKILLS" --eval-skills="$CORPUS" --no-cache >"$TMP/a" 2>"$TMP/aerr"; rc_a=$?
"$BIN" "$SKILLS" --eval-skills="$CORPUS" --no-cache >"$TMP/b" 2>/dev/null
{ [ $rc_a -eq 0 ] && cmp -s "$TMP/a" "$TMP/b"; } \
    && ok "runs clean (rc=0) and two runs are byte-identical" \
    || { no "harness failed (rc=$rc_a) or is non-deterministic"; head -4 "$TMP/aerr"; }

# ── 2) row counts in the header agree with the corpus (no silently dropped rows) ─────────────────────
posWant=$( awk -F'\t' '!/^#/ && NF>=3 && $2!="none"{n++} END{print n+0}' "$CORPUS" )
negWant=$( awk -F'\t' '!/^#/ && NF>=3 && $2=="none"{n++} END{print n+0}' "$CORPUS" )
grep -q "${posWant} positive + ${negWant} negative prompts" "$TMP/a" \
    && ok "header counts match the corpus (${posWant} pos + ${negWant} neg — nothing silently skipped)" \
    || { no "header counts disagree with the corpus (want ${posWant}+${negWant})"; head -1 "$TMP/a"; }

# ── 3) the JUDGED split stays past the resolution floor (2026-07-25 growth pass, PLAN §P2) ────────────
# n=16 judged rows resolves +-6pp per row, coarse enough to hide real movement — grown to 43. Pin the
# corpus size itself, not just the harness's own row count, so a future edit cannot silently shrink the
# hard (paraphrase) set back toward noise without this gate objecting.
judgedWant=$( awk -F'\t' '!/^#/ && NF>=3 && $3=="judged"{n++} END{print n+0}' "$CORPUS" )
awk -v j="$judgedWant" 'BEGIN{exit !(j+0 >= 40)}' \
    && ok "judged split = ${judgedWant} rows (floor 40 — the resolution this gate was grown to reach)" \
    || no "judged split = ${judgedWant} rows fell under the 40-row floor — resolution regressed to +-6pp-ish noise"

# ── 4) the TRIVIAL baseline is measured (printed as a row), never just asserted ──────────────────────
awk '$1=="overlap"{found=1} END{exit !found}' "$TMP/a" \
    && ok "trivial keyword-overlap baseline is measured and printed" \
    || no "no overlap baseline row in the report"

# ── 5) headline-arm floors: a description edit that tanks routing must fail HERE ─────────────────────
# (floors sit ~8-9pp / 0.06-0.07 under the 2026-07-25 measured values on the grown n=43-judged corpus —
# bm25-desc hit@1 77.3%, sep-auc 0.970; drift room, not free fall. Superseded the pre-growth 78.7%/0.969
# floor pair, which was pinned against the n=16 corpus and is no longer the corpus this binary scores.)
h1=$(  awk '$1=="bm25-desc"{gsub("%","",$2); print $2}' "$TMP/a" )
auc=$( awk '$1=="bm25-desc"{print $5}' "$TMP/a" )
awk -v v="$h1"  'BEGIN{exit !(v+0 >= 69.0)}' \
    && ok "bm25-desc hit@1 = ${h1}% (floor 69.0%)" \
    || no "bm25-desc hit@1 = ${h1}% fell under the 69.0% floor — a skill description likely broke routing"
awk -v v="$auc" 'BEGIN{exit !(v+0 >= 0.90)}' \
    && ok "bm25-desc sep-auc = ${auc} (floor 0.90 — negatives stay quiet)" \
    || no "bm25-desc sep-auc = ${auc} fell under 0.90 — positives/negatives no longer separate"

# ── 6) the actionable diagnostics exist: per-skill table + per-provenance split ──────────────────────
{ grep -q 'per-skill (bm25-desc)' "$TMP/a" && grep -q 'provenance hit@1' "$TMP/a" && grep -q 'router-magnet' "$TMP/a"; } \
    && ok "per-skill / provenance / router-magnet diagnostics present" \
    || no "diagnostic sections missing from the report"

# ── 7) metric-can-fail A: deliberately WRONG labels ⇒ hit@1 collapses ─────────────────────────────────
# every positive row is relabelled to one fixed wrong skill (rows that permit it get a different one).
awk -F'\t' 'BEGIN{OFS="\t"} /^#/||$0==""{print;next} $2=="none"{print;next} \
    {print $1, ($2 ~ /ripwire-mcp/ ? "ripwire-handoff" : "ripwire-mcp"), $3}' "$CORPUS" >"$TMP/wrong.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/wrong.tsv" --no-cache >"$TMP/w" 2>/dev/null
h1w=$( awk '$1=="bm25-desc"{gsub("%","",$2); print $2}' "$TMP/w" )
awk -v t="$h1" -v w="$h1w" 'BEGIN{exit !(w+0 < (t+0)/2.0)}' \
    && ok "wrong labels drop bm25-desc hit@1 to ${h1w}% (< half of ${h1}%) — the metric CAN fail" \
    || no "wrong labels left hit@1 at ${h1w}% (true ${h1}%) — the metric does not respond to labels"

# ── 8) metric-can-fail B: SWAPPED pos/neg labels ⇒ sep-auc inverts to exactly 1-auc, lands < 0.5 ──────
awk -F'\t' 'BEGIN{OFS="\t"} /^#/||$0==""{print;next} \
    $2=="none"{print $1,"ripwire-orient","judged";next} {print $1,"none","neg"}' "$CORPUS" >"$TMP/swap.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/swap.tsv" --no-cache >"$TMP/s" 2>/dev/null
aucS=$( awk '$1=="bm25-desc"{print $5}' "$TMP/s" )
awk -v t="$auc" -v s="$aucS" 'BEGIN{ d=s+0-(1.0-(t+0)); if(d<0)d=-d; exit !(d <= 0.01 && s+0 < 0.5) }' \
    && ok "swapped labels invert sep-auc to ${aucS} (= 1 - ${auc} within 0.01, and < 0.5) — inversion is DETECTED" \
    || no "swapped labels gave sep-auc ${aucS} (true ${auc}) — the separation statistic is not label-driven"

# ── 9) corpus integrity is enforced, not degraded around: unknown label ⇒ hard refusal ────────────────
printf 'Some prompt\tripwire-no-such-skill\tjudged\n' >"$TMP/bad.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/bad.tsv" --no-cache >/dev/null 2>"$TMP/baderr"; rc_bad=$?
{ [ $rc_bad -ne 0 ] && grep -q 'unknown skill label' "$TMP/baderr"; } \
    && ok "unknown skill label refuses (rc=$rc_bad) — no silently fabricated sample" \
    || no "unknown label did not refuse (rc=$rc_bad)"
printf 'Some prompt\tripwire-router\tjudged\n' >"$TMP/bad2.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/bad2.tsv" --no-cache >/dev/null 2>/dev/null; rc_r=$?
[ $rc_r -ne 0 ] \
    && ok "ripwire-router as a label refuses (it is the map, not a destination)" \
    || no "ripwire-router accepted as a label"

# ── 10) a root that is not a skills directory refuses with a pointer, not a crash ────────────────────
mkdir -p "$TMP/notskills"; printf 'int main(){return 0;}\n' >"$TMP/notskills/m.cpp"
"$BIN" "$TMP/notskills" --eval-skills="$CORPUS" --no-cache >/dev/null 2>"$TMP/nserr"; rc_ns=$?
{ [ $rc_ns -ne 0 ] && grep -q 'ROOT must be a skills directory' "$TMP/nserr"; } \
    && ok "non-skills root refuses with guidance (rc=$rc_ns)" \
    || no "non-skills root did not refuse cleanly (rc=$rc_ns)"

[ $fail -eq 0 ] && echo "skillevalcheck: ALL PASS" || echo "skillevalcheck: FAILURES"
exit $fail
