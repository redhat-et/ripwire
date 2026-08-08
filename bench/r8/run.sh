#!/bin/bash
# r8 arm A/B runner — ripwire --for vs aider --show-repo-map at equal token budget.
# usage: run_r8.sh <qfile> <corpusdir> <tag> <tokens>
# env: AIDER_BIN (required), AIDER_FLAGS (extra non-interactive flags), RW (ripwire binary)
set -u
QF="$1"; CORPUS="$2"; TAG="$3"; N="$4"
ROOT="$(cd "$(dirname "$0")" && pwd)"
RW="${RW:-REPOROOT/ripwire/build/ripwire}"
AIDER_FLAGS="${AIDER_FLAGS:---no-check-update --yes-always --model gpt-4o --no-show-model-warnings}"
OUT="$ROOT/out/${TAG}_${N}"
mkdir -p "$OUT"

# aider map: ONCE per (corpus, tier) — it is task-independent by design.
( cd "$CORPUS" && "$AIDER_BIN" --show-repo-map --map-tokens "$N" ${AIDER_FLAGS:-} \
    > "$OUT/aider_map.txt" 2> "$OUT/aider_map.err" )
ba=$(wc -c < "$OUT/aider_map.txt" | tr -d ' ')

i=0
printf "idx\thit_rw\thit_aider\tbytes_rw\tbytes_aider\tquestion\ttruth\n" > "$OUT/scores.tsv"
while IFS=$'\t' read -r q truth; do
  [ -z "$q" ] && continue
  i=$((i+1))
  "$RW" "$CORPUS" --for="$q" --token-budget="$N" > "$OUT/rw_$i.txt" 2>/dev/null
  br=$(wc -c < "$OUT/rw_$i.txt" | tr -d ' ')
  hr=0; ha=0
  grep -qF "$truth" "$OUT/rw_$i.txt" && hr=1
  grep -qF "$truth" "$OUT/aider_map.txt" && ha=1
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$i" "$hr" "$ha" "$br" "$ba" "$q" "$truth" >> "$OUT/scores.tsv"
done < "$QF"

echo "=== $TAG @ $N tokens ==="
awk -F'\t' 'NR>1{r+=$2;a+=$3;br+=$4;n++} END{printf "n=%d  ripwire hit=%d (%.0f%%)  aider hit=%d (%.0f%%)  bytes: rw_total=%d rw_mean=%d aider_map=%d\n",n,r,100*r/n,a,100*a/n,br,br/n,$5}' "$OUT/scores.tsv"
