#!/usr/bin/env bash
# skillroutingjudgedcheck.sh — hard paraphrases and every selector arm stay diagnosable.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }
"$BIN" "$ROOT/skills" --eval-skills="$ROOT/test/skillevalfix/prompts.tsv" --no-cache >"$TMP/full" 2>"$TMP/full.err"

for arm in overlap name bm25-desc bm25-full for-routed; do
    grep -q "^  misses ($arm):" "$TMP/full" \
        && ok "per-row miss diagnostics exist for $arm" \
        || no "missing per-row diagnostics for $arm"
done

judged="$( grep '^  judged-only hit@1 per arm:' "$TMP/full" )"
descHit="$( printf '%s' "$judged" | sed -n 's/.*bm25-desc \([0-9][0-9]*\)\/[0-9][0-9]*.*/\1/p' )"
routedHit="$( printf '%s' "$judged" | sed -n 's/.*for-routed \([0-9][0-9]*\)\/[0-9][0-9]*.*/\1/p' )"
judgedN="$( printf '%s' "$judged" | sed -n 's/.*for-routed [0-9][0-9]*\/\([0-9][0-9]*\).*/\1/p' )"
[ -n "$descHit" ] && [ -n "$routedHit" ] && [ -n "$judgedN" ] || { no "could not parse judged-only row: $judged"; exit "$fail"; }

# Frozen held-out corpus: floors sit ~9-10pp below the measured values, preventing the hard paraphrase
# set from regressing while easy description-copy rows keep the aggregate green. RECALIBRATED 2026-08-11
# (S1 growth pass, judged 58→152): measured with unchanged skills bm25-desc 89/152 (58.6%), for-routed
# 91/152 (59.9%); both floors re-derived at 50% — never inherited across a denominator change.
# RECALIBRATED AGAIN 2026-09-02 (lane/n2-d, corpus unchanged at judged=152): measured with unchanged
# skills bm25-desc 98/152 (64.5%), for-routed 92/152 (60.5%) — both had drifted well above the frozen
# 50% floor. Re-derived per the file's own header rule: bm25-desc floor 60%, for-routed floor 55% — a
# smaller margin (~4.5pp / ~5.5pp) than the ~9-10pp convention, because this denominator (n=152) moves
# one full percentage point per ~1.5 rows, so a 9-10pp margin would tolerate an 8-9 row swing before
# firing; the tighter margin here still catches a routing regression on this scale while never being a
# false alarm on the measured value itself. Full record in docs/EVALS.md §4.
[ $(( descHit * 100 )) -ge $(( judgedN * 60 )) ] \
    && ok "bm25-desc judged hit@1 stays at or above 60% ($descHit/$judgedN)" \
    || no "bm25-desc judged hit@1 fell below 60% ($descHit/$judgedN)"
[ $(( routedHit * 100 )) -ge $(( judgedN * 55 )) ] \
    && ok "for-routed judged hit@1 stays at or above 55% ($routedHit/$judgedN)" \
    || no "for-routed judged hit@1 fell below 55% ($routedHit/$judgedN)"

printf '%s\t%s\t%s\n' \
    'I just opened this unfamiliar repository. What are the main subsystems and entry points?' \
    'ripwire-orient' 'judged' >"$TMP/cold.tsv"
"$BIN" "$ROOT/skills" --eval-skills="$TMP/cold.tsv" --no-cache >"$TMP/cold" 2>"$TMP/cold.err"
for arm in bm25-desc for-routed; do
    if awk -v arm="$arm" '
        $0 == "  misses (" arm "):" { inside=1; next }
        inside && /^  misses \(/ { exit }
        inside && /    \(none\)/ { found=1 }
        END { exit !found }
    ' "$TMP/cold"; then
        ok "cold-start orientation routes correctly in $arm"
    else
        no "cold-start orientation misses in $arm"
    fi
done

[ "$fail" -eq 0 ] && echo "skillroutingjudgedcheck: ALL PASS" || echo "skillroutingjudgedcheck: FAILURES"
exit "$fail"
