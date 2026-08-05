#!/usr/bin/env bash
# skillroutingjudgedcheck.sh — hard paraphrases and every selector arm stay diagnosable.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
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

# Frozen held-out corpus: these floors sit below the measured 23/43 and 20/43 values, but prevent the
# hard paraphrase set from regressing while easy description-copy rows keep the aggregate green.
[ $(( descHit * 100 )) -ge $(( judgedN * 50 )) ] \
    && ok "bm25-desc judged hit@1 stays at or above 50% ($descHit/$judgedN)" \
    || no "bm25-desc judged hit@1 fell below 50% ($descHit/$judgedN)"
[ $(( routedHit * 100 )) -ge $(( judgedN * 45 )) ] \
    && ok "for-routed judged hit@1 stays at or above 45% ($routedHit/$judgedN)" \
    || no "for-routed judged hit@1 fell below 45% ($routedHit/$judgedN)"

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
