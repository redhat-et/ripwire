#!/usr/bin/env bash
# evalcheck.sh — gate for --eval itself (NOTHING gated --eval before this: fillordercheck only mentions it).
# --eval is ripwire's self-benchmark: for each of the last N commits it hides that commit's touched files,
# ranks the rest by co-change proximity to them under several rankers (ripwire PageRank, BM25 variants,
# fused, same-dir, random floor), and reports recall@{5,10,20}. It's the oracle the aider-multiplier tuning
# leaned on — so an --eval that silently mis-computes recall would quietly corrupt every
# ranking-quality decision. This gate asserts the STRUCTURE and the MATH INVARIANTS of the table, on a
# synthetic git repo with a KNOWN co-change signal (files change in fixed pairs).
#
# Invariants asserted (true for any correct recall@k table, not observed-and-frozen):
#   (1) the table lists all the expected rankers incl. ripwire, BM25, fused, random
#   (2) every real-ranker cell is a percentage in [0,100]  (recall is a fraction; >100 only for the
#       explicitly-labelled `random` FLOOR row, which normalises differently — excluded)
#   (3) recall is MONOTONE NON-DECREASING across @5 → @10 → @20 for every real ranker (a larger cut-off
#       can only find MORE of the held-out set) — the single strongest correctness invariant here
#   (4) the header reports averaging over ≥1 historical commit (it actually ran the held-out eval)
#   (5) determinism
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/evalcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh. Needs git.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required for --eval gate"; exit 2; }
echo "evalcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src"
git -C "$R" init -q; git -C "$R" config user.email a@x.com; git -C "$R" config user.name A
# 12 files so recall@5 (a 5-of-~12 cut-off) is strictly < recall@20 — this GUARANTEES a real @5<@10<@20
# spread, which is what gives the monotonicity check teeth (an all-100%/all-equal table can't test it).
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'int g%s() { return 0; }\n' "$i" > "$R/src/g$i.cpp"; done
git -C "$R" add -A
GIT_AUTHOR_DATE="2026-06-01T00:00:00" GIT_COMMITTER_DATE="2026-06-01T00:00:00" git -C "$R" commit -q -m init
one(){ printf '// %s\n' "$2" >> "$R/src/$1.cpp"; git -C "$R" add -A
       GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$R" commit -q -m x; }
pair(){ for f in $1; do printf '// %s\n' "$2" >> "$R/src/$f.cpp"; done; git -C "$R" add -A
        GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$R" commit -q -m x; }
# single-file commits do NOT qualify for eval (goldTotal==0); exactly ONE 2-file commit qualifies, so the
# average is that one held-out commit → a clean, differentiated, deterministic recall spread.
one g1 "2026-06-02T00:00:00"; one g2 "2026-06-03T00:00:00"
pair "g1 g7" "2026-06-04T00:00:00"

run(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$R" --eval --no-cache 2>/dev/null; }
EV="$( run )"
run >/dev/null 2>&1; EC=$?

# ── 0) it ran, exit 0 ────────────────────────────────────────────────────────────────────────────────
{ [ "$EC" = 0 ] && [ -n "$EV" ]; } && ok "--eval runs (exit 0, non-empty)" || no "--eval failed (exit=$EC empty=$( [ -z "$EV" ] && echo y || echo n ))"

# ── 1) expected rankers present ──────────────────────────────────────────────────────────────────────
missing=""
for rk in ripwire BM25 fused same-dir random; do printf '%s' "$EV" | grep -q "$rk" || missing="$missing $rk"; done
[ -z "$missing" ] && ok "--eval lists all expected rankers (ripwire, BM25, fused, same-dir, random)" || no "--eval missing rankers:$missing"

# ── 2) averaged over ≥1 historical commit (the held-out eval actually happened) ──────────────────────
NC="$( printf '%s' "$EV" | grep -oE 'over [0-9]+ historical commit' | grep -oE '[0-9]+' | head -1 )"
{ [ -n "$NC" ] && [ "$NC" -ge 1 ]; } && ok "--eval averaged over $NC historical commit(s)" || no "--eval header reports 0/no historical commits (NC='$NC')"

# ── 3+4) per-real-ranker: cells in [0,100] AND monotone non-decreasing @5≤@10≤@20 ────────────────────
#    (parse rows that begin with a real ranker name; the `random` floor row is EXCLUDED — it normalises
#     over F files and legitimately exceeds 100%.)
#    A single awk pass over the table: for each row whose first field is a real ranker AND that carries
#    exactly three NN.N% cells, check every cell in [0,100] and the triple monotone non-decreasing.
#    Emits ROWS=<n> so we can also assert that at least the 6 real-ranker rows were actually examined
#    (a parse that silently matched ZERO rows would otherwise "pass" both checks vacuously).
PARSE="$( printf '%s\n' "$EV" | awk '
    { name=$1 }
    name!="ripwire" && name!="BM25" && name!="BM25sub" && name!="BM25body" && name!="fused" && name!="same-dir" { next }
    {
        n=0
        for( i=1; i<=NF; i++ ) if( $i ~ /^[0-9]+\.[0-9]+%$/ ) { v=$i; sub(/%/,"",v); c[++n]=v+0 }
        if( n!=3 ) next            # header "ripwire --eval …" row has 0 cells → skipped here
        rows++
        for( i=1; i<=3; i++ ) if( c[i]<0 || c[i]>100 ) badrange=badrange " " name "(" c[i] ")"
        if( !(c[1]<=c[2] && c[2]<=c[3]) ) badmono=badmono " " name "(" c[1] "/" c[2] "/" c[3] ")"
    }
    END{ printf "ROWS=%d\nRANGE=%s\nMONO=%s\n", rows, badrange, badmono }
' )"
ROWS="$( printf '%s' "$PARSE" | sed -n 's/^ROWS=//p' )"
BAD_RANGE="$( printf '%s' "$PARSE" | sed -n 's/^RANGE=//p' )"
BAD_MONO="$( printf '%s' "$PARSE" | sed -n 's/^MONO=//p' )"
{ [ -n "$ROWS" ] && [ "$ROWS" -ge 6 ]; } \
    && ok "--eval: parsed $ROWS real-ranker rows (all 6 rankers examined, not a vacuous pass)" \
    || no "--eval: parsed only ROWS='$ROWS' real-ranker rows (expected ≥6 — table format changed?)"
[ -z "$BAD_RANGE" ] && ok "--eval: every real-ranker recall cell is a percentage in [0,100]" || no "--eval out-of-range recall cells:$BAD_RANGE"
[ -z "$BAD_MONO" ]  && ok "--eval: recall MONOTONE non-decreasing @5≤@10≤@20 for every real ranker" || no "--eval recall not monotone (a larger cut-off found FEWER held-out files):$BAD_MONO"

# ── 5) determinism ───────────────────────────────────────────────────────────────────────────────────
[ "$( run )" = "$( run )" ] && ok "--eval deterministic (byte-identical run-to-run)" || no "--eval non-deterministic"

# ── 6) §P11.12: an interpretive note names what each ranker is and which one is the SHIPPED default ────
# (purely additive — the table rows/columns above are untouched, so this gates green-by-design; asserted
# here so the note can't silently regress back to a bare, uninterpreted table).
printf '%s' "$EV" | grep -q 'note:' && ok "--eval: table carries an interpretive note (was bare pre-§P11.12)" || no "--eval: no interpretive note found"
printf '%s' "$EV" | grep -q 'SHIPPED default' && ok "--eval: note names which ranker is the SHIPPED default" || no "--eval: note does not name the shipped default"
printf '%s' "$EV" | grep -q 'structural-only PageRank' && ok "--eval: note explains ripwire= is structural PageRank, not a retrieval ranker" || no "--eval: note does not explain the ripwire row"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
