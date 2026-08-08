#!/bin/bash
# usage: run.sh <qfile> <corpusdir> <tag>
QF="$1"; CORPUS="$2"; TAG="$3"
ROOT=SCRATCH/r7
RW=REPOROOT/ripwire/build/ripwire
CG=$ROOT/cginstall/node_modules/.bin/codegraph
export DO_NOT_TRACK=1 CODEGRAPH_TELEMETRY=0 NO_COLOR=1
OUT=$ROOT/out/$TAG
mkdir -p "$OUT"
i=0
printf "idx\thit_rw\thit_cg\tbytes_rw\tbytes_cg\tquestion\ttruth\n" > "$OUT/scores.tsv"
while IFS=$'\t' read -r q truth; do
  [ -z "$q" ] && continue
  i=$((i+1))
  "$RW" "$CORPUS" --for="$q" > "$OUT/rw_$i.txt" 2>/dev/null
  ( cd "$CORPUS" && "$CG" explore "$q" --no-color > "$OUT/cg_$i.txt" 2>&1 )
  br=$(wc -c < "$OUT/rw_$i.txt" | tr -d ' ')
  bc=$(wc -c < "$OUT/cg_$i.txt" | tr -d ' ')
  hr=0; hc=0
  grep -qF "$truth" "$OUT/rw_$i.txt" && hr=1
  grep -qF "$truth" "$OUT/cg_$i.txt" && hc=1
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$i" "$hr" "$hc" "$br" "$bc" "$q" "$truth" >> "$OUT/scores.tsv"
done < "$QF"
echo "=== $TAG ==="
awk -F'\t' 'NR>1{r+=$2;c+=$3;br+=$4;bc+=$5;n++} END{printf "n=%d  ripwire hit=%d (%.0f%%)  codegraph hit=%d (%.0f%%)  bytes: rw=%d cg=%d (cg/rw=%.1fx)\n",n,r,100*r/n,c,100*c/n,br,bc,bc/br}' "$OUT/scores.tsv"
column -t -s$'\t' "$OUT/scores.tsv" | cut -c1-150
