#!/usr/bin/env bash
# dispatchordercheck.sh — DISPATCH-PRECEDENCE gate for the navigate verbs.
#
# Why this gate exists. The nine navigate verbs are a flat
# chain of independent `if( cfg.X ) { ... return; }` blocks. Their RELATIVE ORDER is observable
# behaviour — when a run passes two verb flags at once, exactly one of them produces output and the
# other is silently ignored, and WHICH one is decided purely by position in the chain. Nothing pinned
# that before this gate: each verb has its own gate, but every one of those passes a SINGLE verb flag,
# so a refactor that reorders the chain (or promotes the blocks to handlers and calls them back in a
# different sequence) breaks no existing gate at all. Reordering is exactly the mistake a mechanical
# split invites, so the order is pinned here as a contract.
#
# The expected winners below are NOT observed-and-frozen; they are read off the documented dispatch
# order, which is (earlier wins):
#
#   runQualityViews  ...  <- whole handler, ahead of the navigate chain in main()
#   runNavigateVerbs:
#     1 --callers / --callees   (one block; --callers wins the tie inside it)
#     2 --graph-query
#     3 --uses
#     4 --external-surface
#     5 --path
#     6 --connect
#     7 --impact
#     8 --mentions
#     9 --affected
#   runChangeViews   ...  <- whole handler, behind the navigate chain in main()
#
# Each case passes TWO verb flags and asserts the root element of the earlier verb is what comes out.
# Adjacent pairs pin every seam in the chain; the two cross-handler cases pin the chain's endpoints
# against its neighbours in main()'s handler sequence.
#
# Fixture: test/queryfix (shared with querycheck.sh / reachcheck.sh; d1 -> d2 -> d3 -> d4).

set -u

BIN="${1:-${RIPWIRE_BIN:-./build/ripwire}}"   # CA4: this gate ignored $1, so a caller passing a binary
FIX="${FIX:-test/queryfix}"                    # positionally silently measured build/ripwire instead (trap #20)
fails=0

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

# assertWinner NAME EXPECTED_ROOT_TAG ARGS...
#   runs BIN on the fixture with ARGS (two verb flags), and asserts the FIRST XML element emitted is
#   EXPECTED_ROOT_TAG. Leading <!-- ... --> doc comments are skipped: several verbs lead with one, and
#   which verb answered is decided by the first real element, not by the comment.
assertWinner()
{
    local name="$1" want="$2"; shift 2
    local out got
    out="$( "$BIN" "$FIX" "$@" 2>/dev/null )"
    # strip every leading comment, then take the first element name
    got="$( printf '%s' "$out" | sed -e 's/<!--[^>]*-->//g' -e 's/<!--.*-->//g' | grep -o '<[a-zA-Z][a-zA-Z0-9-]*' | head -1 | tr -d '<' )"
    if [ "$got" = "$want" ]; then
        pass "$name: <$want> wins"
    else
        fail "$name: expected <$want>, got <${got:-EMPTY}>"
    fi
}

echo "dispatchordercheck: BIN=$BIN"

# --- the tie INSIDE the first block ------------------------------------------------------------
# --callers and --callees share one block; wantCallers = !cfg.callers.empty(), so --callers wins.
assertWinner "callers-beats-callees"      callers          --callers=d3 --callees=d2

# --- the eight adjacent seams of the nine-verb chain --------------------------------------------
assertWinner "callers-beats-graph-query"  callers          --callers=d3 --graph-query='name("d1")'
assertWinner "graph-query-beats-uses"     query            --graph-query='name("d1")' --uses=d3
assertWinner "uses-beats-external"        uses             --uses=d3 --external-surface
assertWinner "external-beats-path"        external-surface --external-surface --path=d1,d4
assertWinner "path-beats-connect"         path             --path=d1,d4 --connect=d1,d4
assertWinner "connect-beats-impact"       connect          --connect=d1,d4 --impact=d4
assertWinner "impact-beats-mentions"      impact           --impact=d4 --mentions=d4
assertWinner "mentions-beats-affected"    mentions         --mentions=d4 --affected=src/chain.cpp

# --- the chain's two endpoints against its neighbouring handlers in main() -----------------------
# runQualityViews runs BEFORE the navigate chain: --dead-code beats the chain's first verb.
# (bare --dead-code, not --dead-code=all: since §P0.3 a filter naming no indexed path REFUSES, and `all`
#  was never a directory in the fixture — the filter was incidental to what this case pins, the order.)
assertWinner "deadcode-beats-callers"     dead-code        --dead-code --callers=d3
# runChangeViews runs AFTER the navigate chain: the chain's last verb beats --situ, its first branch.
assertWinner "affected-beats-situ"        affected         --affected=src/chain.cpp --situ


# ── CA4 §B11.4 — the PRECEDENCE DISCLOSURE, checked against the dispatch it claims to describe ─────────
#
# main.cpp's warnReportVerbPrecedence() names the winner from a static table in dispatch order. A table of
# ~50 rows that nobody re-derives is precisely the "count in a comment" failure this round keeps finding, so
# it is NOT asserted by reading: for every ADJACENT pair in the table, this arm runs both flags together and
# demands BOTH halves of the claim -- (1) stderr names the earlier verb as the winner and the later as
# IGNORED, and (2) stdout is BYTE-IDENTICAL to the winner's solo run, which is what proves the verb the
# message names is the verb whose bytes actually came out. A table that rots reds here, by name.
#
# The list is a curated, side-effect-FREE subset of the table (nothing that writes into the corpus: no
# --quality-baseline, --quality-ack, --note-add, --export). It is in table order; each entry is one runnable
# invocation on this fixture. Coverage is the seams BETWEEN listed neighbours, which is stated rather than
# implied -- the unlisted verbs sit inside those spans and are not pinned by this arm.
PREC_VERBS=(
  "--exemplar=chain" "--recall=chain" "--deps" "--clones" "--dead-code" "--edit-check=d2"
  "--callers=d2" "--callees=d1" "--uses=d2" "--external-surface" "--path=d1,d3" "--connect=d1,d2,d3"
  "--impact=d3" "--mentions=d2" "--flags" "--whereis=d2" "--doc-drift" "--notes"
  "--communities" "--zoom" "--seams" "--report" "--tree" "--grep=d2" "--lint" "--around=d2"
)
PRECTMP="$( mktemp -d )"; trap 'rm -rf "$PRECTMP"' EXIT
prec_pairs=0
for (( pi = 0; pi + 1 < ${#PREC_VERBS[@]}; pi++ )); do
    A="${PREC_VERBS[$pi]}"; B="${PREC_VERBS[$((pi+1))]}"
    AFLAG="${A%%=*}"; BFLAG="${B%%=*}"
    "$BIN" "$FIX" "$A"      >"$PRECTMP/solo" 2>/dev/null
    "$BIN" "$FIX" "$A" "$B" >"$PRECTMP/both" 2>"$PRECTMP/err"
    prec_pairs=$((prec_pairs + 1))
    if ! cmp -s "$PRECTMP/solo" "$PRECTMP/both"; then
        fail "precedence $AFLAG+$BFLAG: stdout differs from the winner's solo run — $AFLAG did NOT answer"
    elif ! grep -q "ripwire: $AFLAG takes precedence" "$PRECTMP/err"; then
        fail "precedence $AFLAG+$BFLAG: stderr does not name $AFLAG as the winner (got: $( head -c 120 "$PRECTMP/err" ))"
    elif ! grep -q "IGNORED this run: .*$BFLAG" "$PRECTMP/err"; then
        fail "precedence $AFLAG+$BFLAG: stderr does not name $BFLAG as ignored"
    fi
done
[ "$fails" -eq 0 ] && pass "precedence disclosure: $prec_pairs adjacent pairs — the named winner is the verb that answered, on every one"

# and the claim the message itself makes: the winner does NOT depend on the order the flags were typed.
"$BIN" "$FIX" --owners --clones >/dev/null 2>"$PRECTMP/e1"
"$BIN" "$FIX" --clones --owners >/dev/null 2>"$PRECTMP/e2"
if cmp -s "$PRECTMP/e1" "$PRECTMP/e2" && grep -q -- '--clones takes precedence' "$PRECTMP/e1"; then
    pass "precedence is dispatch-order, not typed-order (--owners --clones == --clones --owners, --clones wins)"
else
    fail "precedence: the two typed orders disagree, or --clones is not the winner the message claims"
fi

# a SINGLE verb must stay silent — a warning that fires when nothing was dropped is worse than none.
"$BIN" "$FIX" --clones >/dev/null 2>"$PRECTMP/e3"
grep -q 'takes precedence when several verbs' "$PRECTMP/e3" \
  && fail "precedence: the warning fires on a single-verb run (nothing was dropped)" \
  || pass "precedence: silent when one verb (or none) is given"

if [ "$fails" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
fi
echo "dispatchordercheck: $fails failure(s)"
exit 1
