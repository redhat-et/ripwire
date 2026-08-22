#!/usr/bin/env bash
# skillevalcheck.sh — gate for --eval-skills, the labelled skill-ROUTING eval (src/skilleval.h).
# Two jobs:
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
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
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

# ── 3) the JUDGED split stays past the resolution floor (2026-07-25 growth pass) ────────────────────
# n=16 judged rows resolves +-6pp per row, coarse enough to hide real movement — grown to 43. Pin the
# corpus size itself, not just the harness's own row count, so a future edit cannot silently shrink the
# hard (paraphrase) set back toward noise without this gate objecting. Scoped to split=test ONLY (a 4th
# column of "test", or absent, back-compat default): the 2026-08-08 dev split also carries judged-
# provenance rows, and counting them in here would let a shrink of the FROZEN test set hide behind an
# unrelated dev-row addition — the two pools must be protected independently.
judgedWant=$( awk -F'\t' '!/^#/ && NF>=3 && $3=="judged" && ( NF<4 || $4=="test" ){n++} END{print n+0}' "$CORPUS" )
awk -v j="$judgedWant" 'BEGIN{exit !(j+0 >= 80)}' \
    && ok "judged split (split=test) = ${judgedWant} rows (floor 80 — the resolution of the 2026-08-11 S1 growth pass)" \
    || no "judged split (split=test) = ${judgedWant} rows fell under the 80-row floor — the grown hard set shrank"

# ── 4) the TRIVIAL baseline is measured (printed as a row), never just asserted ──────────────────────
awk '$1=="overlap"{found=1} END{exit !found}' "$TMP/a" \
    && ok "trivial keyword-overlap baseline is measured and printed" \
    || no "no overlap baseline row in the report"

# ── 5) headline-arm floors: a description edit that tanks routing must fail HERE ─────────────────────
# (floors sit ~8-9pp / 0.06-0.07 under the 2026-07-25 measured values on the grown n=43-judged corpus —
# bm25-desc hit@1 77.3%, sep-auc 0.970; drift room, not free fall. Superseded the pre-growth 78.7%/0.969
# floor pair, which was pinned against the n=16 corpus and is no longer the corpus this binary scores.
# 2026-08-11 (S1 growth pass): recalibrated again — the test split grew 128→183 rows (test-judged 43→85);
# on the grown corpus the unchanged skills measure bm25-desc split=test hit@1 68.5%, sep-auc 0.953, so
# the 2026-07-25 pair above is likewise superseded; full recalibration record in docs/EVALS.md.
# 2026-08-08: scoped to the split=test row, NOT the whole-corpus arm line — since the dev split gained
# rows this round, the whole-corpus number is now a mix of the frozen benchmark and free-to-iterate
# tuning rows, and this floor exists to protect the FROZEN half specifically.)
h1=$(  awk '$1=="split=test" && $2=="bm25-desc"{gsub("%","",$3); print $3}' "$TMP/a" )
auc=$( awk '$1=="split=test" && $2=="bm25-desc"{print $6}' "$TMP/a" )
awk -v v="$h1"  'BEGIN{exit !(v+0 >= 60.0)}' \
    && ok "bm25-desc hit@1 (split=test) = ${h1}% (floor 60.0%)" \
    || no "bm25-desc hit@1 (split=test) = ${h1}% fell under the 60.0% floor — a skill description likely broke routing"
awk -v v="$auc" 'BEGIN{exit !(v+0 >= 0.89)}' \
    && ok "bm25-desc sep-auc (split=test) = ${auc} (floor 0.89 — negatives stay quiet)" \
    || no "bm25-desc sep-auc (split=test) = ${auc} fell under 0.89 — positives/negatives no longer separate"

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
# 2026-08-11 (S1 growth pass): band 0.01→0.02 — AUC inversion is exact only up to the score-TIE mass,
# and ties grew with the corpus (d=0.012 measured on unchanged skills at 266 rows); still must be < 0.5.
awk -v t="$auc" -v s="$aucS" 'BEGIN{ d=s+0-(1.0-(t+0)); if(d<0)d=-d; exit !(d <= 0.02 && s+0 < 0.5) }' \
    && ok "swapped labels invert sep-auc to ${aucS} (= 1 - ${auc} within 0.02, and < 0.5) — inversion is DETECTED" \
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

# ── 11) every skill directory has >= 1 permitted row in the corpus. A skill with zero permitted rows
#     can never win, lose, or be measured for routing accuracy — it silently free-rides forever, and it
#     can still steal top-1 away from a permitted skill without this gate ever noticing (2026-08-08 audit
#     H1: ripwire-opt-remarks, added 08-05, shipped with 0 permitted rows and stole top-1 on several
#     for-routed prompts + a bm25-desc negative fire before anyone had a row to prove it wrong). ripwire-
#     router is exempt: it is the fallback map, never a legal label (see gate 9 above).
skillDirs=$( find "$SKILLS" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort )
missingSkills=""
for sd in $skillDirs; do
    [ "$sd" = "ripwire-router" ] && continue
    awk -F'\t' -v s="$sd" '!/^#/ && NF>=3 && $2!="none" { n=split($2,a,","); for(i=1;i<=n;i++) if(a[i]==s) f=1 } END{exit !f}' "$CORPUS" \
        || missingSkills="$missingSkills $sd"
done
[ -z "$missingSkills" ] \
    && ok "every skill directory (except ripwire-router) has >=1 permitted row in the corpus" \
    || no "skill(s) with ZERO permitted rows in the corpus, unmeasurable for routing:$missingSkills"

# ── 12) dev-split floor: bm25-desc must not fall below a measured-with-margin floor on the TUNING rows
#     (test/skillevalfix/prompts.tsv split=dev, added 2026-08-08 for the Aug 5-8 routing findings — nest-
#     profile/essential-complexity trust, cache-lint pack, --skipped-vs---doctor, opt-remarks triage +
#     its hard negatives). MEASURED on this commit: hit@1=62.5% (10/16), sep-auc=0.969, N=20 (16 positive
#     + 4 negative). RECALIBRATED 2026-08-11 (S1 growth pass): dev grew 20→83 rows (68 positive + 15
#     negative); measured on the grown corpus with unchanged skills: hit@1=61.8%, sep-auc=0.896. The dev
#     pool keeps its WIDE margin — 15pp under hit@1, 0.15 under sep-auc (61.8−15→floor 46.0;
#     0.896−0.15→floor 0.75) — deliberately looser than test's 8-9pp/0.06-0.07.
#     Recalibrate only on a deliberate dev-split edit (new rows, a description iteration you mean to
#     measure), never silently.
h1d=$(  awk '$1=="split=dev" && $2=="bm25-desc"{gsub("%","",$3); print $3}' "$TMP/a" )
aucd=$( awk '$1=="split=dev" && $2=="bm25-desc"{print $6}' "$TMP/a" )
awk -v v="$h1d"  'BEGIN{exit !(v+0 >= 46.0)}' \
    && ok "dev-split bm25-desc hit@1 = ${h1d}% (floor 46.0%)" \
    || no "dev-split bm25-desc hit@1 = ${h1d}% fell under the 46.0% floor"
awk -v v="$aucd" 'BEGIN{exit !(v+0 >= 0.75)}' \
    && ok "dev-split bm25-desc sep-auc = ${aucd} (floor 0.75)" \
    || no "dev-split bm25-desc sep-auc = ${aucd} fell under 0.75"

[ $fail -eq 0 ] && echo "skillevalcheck: ALL PASS" || echo "skillevalcheck: FAILURES"
exit $fail
