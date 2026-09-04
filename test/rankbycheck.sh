#!/usr/bin/env bash
# rankbycheck.sh — RANKING-CORE gate for all five --rank-by modes (pagerank, authority, hub, rrf, churn).
# Zero prior coverage before this gate: this is the dispatch table that decides WHICH ranking algorithm
# runs (src/main.cpp ~2119-2138) — a mode silently falling through to plain PageRank is exactly the bug
# class this gate exists to catch.
#
# Fixture test/rankbyfix/star.py is an ASYMMETRIC star:
#   hub() calls a(), b(), c()      — hub is the HITS hub (high out-fan to good authorities)
#   d(), e() both call sink()      — a,b,c end up the HITS authorities (see below — NOT sink; verified
#                                     against real Kleinberg mutual-reinforcement math, not assumed)
#
# House rule: float scores are NEVER asserted bit-exact — order + coarse ratios via k= parsing only.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/rankbycheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/rankbyfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/rankbyfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "rankbycheck: BIN=$BIN  CORPUS=test/rankbyfix"

r(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --rank-by="$1" --no-cache 2>/dev/null; }
top_name(){ printf '%s' "$1" | grep -oE '<s [^>]*n="[^"]*"' | head -1 | grep -oE 'n="[^"]*"' | sed 's/n="//;s/"//'; }
sym_count(){ printf '%s' "$1" | grep -oE '<s ' | wc -l | tr -d ' '; }

# ── per-mode: exit 0, deterministic, non-empty ──────────────────────────────────────────────────────────
OUT_pagerank="";  OUT_authority=""; OUT_hub=""; OUT_rrf=""; OUT_churn=""
for mode in pagerank authority hub rrf churn; do
    perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --rank-by="$mode" --no-cache >/dev/null 2>&1
    ec=$?
    A="$( r "$mode" )"; B="$( r "$mode" )"
    case "$mode" in
        pagerank)  OUT_pagerank="$A" ;;
        authority) OUT_authority="$A" ;;
        hub)       OUT_hub="$A" ;;
        rrf)       OUT_rrf="$A" ;;
        churn)     OUT_churn="$A" ;;
    esac
    { [ "$ec" = 0 ] && [ "$A" = "$B" ] && [ -n "$A" ] && [ "$( sym_count "$A" )" = 7 ]; } \
        && ok "--rank-by=$mode: exit 0, deterministic, non-empty (7 symbols)" \
        || no "--rank-by=$mode failed basic checks (exit=$ec, identical=$( [ "$A" = "$B" ] && echo y || echo n ), count=$( sym_count "$A" ))"
done

# ── semantic: --rank-by=hub top symbol is hub() (highest out-fan to good authorities) ──────────────────
hub_top="$( top_name "$OUT_hub" )"
[ "$hub_top" = "hub" ] && ok "--rank-by=hub top symbol is hub() (got: $hub_top)" || no "--rank-by=hub top should be hub(), got: $hub_top"

# ── semantic: --rank-by=authority top is NOT hub() — verified against real HITS math first: Kleinberg
#    mutual reinforcement makes a()/b()/c() (pointed to by the one strong hub, hub()) the authorities here,
#    not sink() (pointed to by d()/e(), which themselves never accumulate hub mass). Pin the observed,
#    defensible behavior: top authority is one of a/b/c, and is never hub() itself. ─────────────────────
auth_top="$( top_name "$OUT_authority" )"
case "$auth_top" in
    a|b|c) ok "--rank-by=authority top is a/b/c (got: $auth_top — HITS mutual-reinforcement: hub() is the one strong hub, so its callees win authority mass, not sink()'s weak callers d()/e())" ;;
    *)     no "--rank-by=authority top should be a/b/c, got: $auth_top" ;;
esac
[ "$auth_top" != "hub" ] && ok "--rank-by=authority top is NOT hub() (HITS roles are distinct)" || no "--rank-by=authority top should never be hub()"

# ── semantic: pagerank top differs from hub top — proves the dispatch table actually switches algorithms
#    instead of every mode silently falling through to plain PageRank ─────────────────────────────────
pr_top="$( top_name "$OUT_pagerank" )"
[ "$pr_top" != "$hub_top" ] \
    && ok "pagerank top ($pr_top) differs from hub top ($hub_top) — dispatch is not collapsed" \
    || no "pagerank top == hub top ($pr_top) — SUSPECT: --rank-by=hub may be falling through to plain pagerank"

# also: pagerank top differs from authority top's mode-defining symbol in the general case here (pagerank
# top is sink(), by raw in-degree/importance, not a/b/c) — another independent dispatch-not-collapsed check.
[ "$pr_top" != "$auth_top" ] \
    && ok "pagerank top ($pr_top) differs from authority top ($auth_top) — authority dispatch is not collapsed" \
    || no "pagerank top == authority top ($pr_top) — SUSPECT: --rank-by=authority may be falling through to plain pagerank"

# ── churn: synthetic git repo, star.py committed 4x, other.py committed 1x. Under --rank-by=churn, star.py's
#    symbols should be boosted RELATIVE to other.py's relative to pagerank (not necessarily under plain
#    pagerank, which has no churn signal at all). Concretely: other()'s k under churn, as a fraction of
#    other()'s k under pagerank, should drop well below 1 (churn demotes the untouched file). ───────────
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/churnrepo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "setup@x.com"
git -C "$REPO" config user.name  "Setup"

cp "$FIX/star.py" "$REPO/star.py"
cat >"$REPO/other.py" <<'EOF'
def other():
    return 1
EOF

commit_file() {
    local file="$1" ts="$2" msg="$3"
    git -C "$REPO" add "$file"
    GIT_AUTHOR_NAME="Setup"    GIT_AUTHOR_EMAIL="setup@x.com"    GIT_AUTHOR_DATE="$ts" \
    GIT_COMMITTER_NAME="Setup" GIT_COMMITTER_EMAIL="setup@x.com" GIT_COMMITTER_DATE="$ts" \
        git -C "$REPO" commit -q -m "$msg"
}

commit_file star.py  "2026-06-01T00:00:00" "star init"     # star.py commit 1/4
commit_file other.py "2026-06-02T00:00:00" "other init"    # other.py commit 1/1
for i in 1 2 3; do                                          # star.py commits 2-4/4
    printf '# churn edit %s\n' "$i" >>"$REPO/star.py"
    commit_file star.py "2026-06-0$(( i + 2 ))T00:00:00" "star edit $i"
done

k_of(){ printf '%s' "$1" | grep -oE '<s [^>]*n="'"$2"'"[^>]*k="[0-9.]+"' | head -1 | grep -oE 'k="[0-9.]+"' | sed 's/k="//;s/"//'; }
CHURN_OUT="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$REPO" --rank-by=churn    --no-cache 2>/dev/null )"
PR_OUT="$(    perl -e 'alarm 15; exec @ARGV' "$BIN" "$REPO" --rank-by=pagerank --no-cache 2>/dev/null )"

churn_k="$( k_of "$CHURN_OUT" "other" )"
pr_k="$(    k_of "$PR_OUT"    "other" )"
if [ -n "$churn_k" ] && [ -n "$pr_k" ]; then
    awk -v c="$churn_k" -v p="$pr_k" 'BEGIN{ exit !(c < p * 0.8) }' \
        && ok "churn: other()'s k drops under --rank-by=churn ($churn_k) vs pagerank ($pr_k) — 4x-committed star.py is boosted relative to 1x-committed other.py" \
        || no "churn: expected other() k under churn ($churn_k) < 0.8x its pagerank k ($pr_k) — churn signal not distinguishing commit frequency"
else
    no "churn: could not parse other()'s k from churn/pagerank output (churn='$churn_k' pr='$pr_k')"
fi

# churn determinism on the synthetic repo too
CHURN_A="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$REPO" --rank-by=churn --no-cache 2>/dev/null )"
CHURN_B="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$REPO" --rank-by=churn --no-cache 2>/dev/null )"
[ "$CHURN_A" = "$CHURN_B" ] && ok "churn: deterministic on synthetic git repo" || no "churn: non-deterministic on synthetic git repo"

# ── §L10: the churn legend must be TRUE, not just present — a differential fixture that proves the two
#    rankings CAN put a different symbol in the #1 slot (a leaf with no call-graph support at all, but
#    heavy recent churn, versus sink() — the structurally best-supported symbol in star.py's topology).
#    Before this gate the legend claimed "the same corpus ranked by pagerank orders differently" as a
#    blanket fact, which is false on THIS REPO's own top ranks (measured 2026-09-04: --rank-by=churn and
#    the default ranking agreed on the top 4, in order) — the legend must describe the MECHANISM (a
#    churn-biased teleport still shaped by structure), not promise an ordering flip that does not always
#    happen. This fixture is the flip's existence proof: it shows the mechanism is real without pretending
#    it is universal.
cat >"$REPO/leaf.py" <<'EOF'
def leafFn():
    return 42
EOF
commit_file leaf.py "2026-06-10T00:00:00" "leaf init"
for i in $( seq 1 20 ); do
    printf '# churn edit %s\n' "$i" >>"$REPO/leaf.py"
    commit_file leaf.py "2026-06-$(( 10 + i ))T00:00:00" "leaf edit $i"
done

PR_OUT2="$(    perl -e 'alarm 15; exec @ARGV' "$BIN" "$REPO" --rank-by=pagerank --no-cache 2>/dev/null )"
CHURN_OUT2="$( perl -e 'alarm 15; exec @ARGV' "$BIN" "$REPO" --rank-by=churn    --no-cache 2>/dev/null )"
pr_top2="$(    top_name "$PR_OUT2" )"
churn_top2="$( top_name "$CHURN_OUT2" )"
{ [ "$pr_top2" != "leafFn" ] && [ "$churn_top2" = "leafFn" ] && [ "$pr_top2" != "$churn_top2" ]; } \
    && ok "L10: churn ranking CAN flip the #1 symbol vs pagerank (pagerank top=$pr_top2, churn top=$churn_top2)" \
    || no "L10: expected pagerank top != leafFn and churn top == leafFn, got pagerank=$pr_top2 churn=$churn_top2"

# The wording itself: no blanket "orders differently" promise, and the mechanism (a churn-biased teleport,
# still PageRank, still shaped by structure) IS stated — on the legend this repo's own default map carries.
printf '%s' "$CHURN_OUT2" | grep -q 'orders differently' \
    && no "L10: churn legend still makes the blanket \"orders differently\" claim (false on this repo's own top ranks)" \
    || ok "L10: churn legend no longer claims the two orderings always differ"
printf '%s' "$CHURN_OUT2" | grep -q 'teleport BIASED by git CHANGE-FREQUENCY' \
    && ok "L10: churn legend states the mechanism (a churn-biased PageRank teleport)" \
    || no "L10: churn legend does not state the teleport mechanism"

# ── xml well-formed (spot-check one mode) ────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    r pagerank | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
