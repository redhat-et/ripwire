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
#
# §F1 (audit 2026-08-08) — eleven verb-shaped flags were missing from the table entirely and so collided in
# TOTAL silence, exactly like the query family did before M1. They are inserted here at their real dispatch
# positions, which extends the adjacent-pair coverage over them: --ensemble/--context-ratio (runMaintenance-
# Views' first two arms, ahead of --hotspots), the six runQualityViews lenses ahead of --dead-code
# (--readability, --comment-coherence, --nonlocal-state, --quality-panel, --naming-calibration,
# --naming-consistency), --handoff (runChangeViews' first arm) and --field-affinity (between --layout and
# --doc-drift). --index-out is verb-shaped too but WRITES cache blobs, so it stays out of this side-effect-
# free list and gets its own arm below.
PREC_VERBS=(
  "--exemplar=chain" "--recall=chain" "--deps" "--ensemble" "--context-ratio" "--clones"
  "--readability" "--comment-coherence" "--nonlocal-state" "--quality-panel"
  "--naming-calibration" "--naming-consistency" "--dead-code" "--edit-check=d2"
  "--callers=d2" "--callees=d1" "--uses=d2" "--external-surface" "--path=d1,d3" "--connect=d1,d2,d3"
  "--impact=d3" "--mentions=d2" "--handoff" "--flags" "--whereis=d2" "--field-affinity" "--doc-drift" "--notes"
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

# ── M1 — the CROSS-FAMILY seam: --for / --query / --pack-task against the ~50 report verbs ────────────
#
# The precedence table used to EXCLUDE the three query-family flags, on the claim that "X9(c) above already
# discloses those three". X9(c) only ever discloses collisions AMONG the three; against a report verb the
# loser was dropped in total silence — stderr empty, exit 0 — which is the one thing the rest of this table
# exists to prevent. M1 made all three ROWS, which closed the silence but froze an order nobody designed:
# --for won everything, --query lost to everything, and --pack-task sat in the middle (losing to --skipped,
# beating --lint) — three different answers to one question, so a caller could not infer the rule from any
# number of observations.
#
# §A2 (audit 2026-08-08) — the family now dispatches UNIFORMLY FIRST. A typed task (--for/--pack-task/
# --query) is the caller's PRIMARY intent; a report verb alongside it is the incidental one. One rule, three
# flags: the query family beats every report verb, in both typed orders. This is a deliberate BEHAVIOUR
# CHANGE — --skipped/--hotspots used to beat --pack-task, and every report verb used to beat --query.
# Intra-family order is unchanged and still X9(c)'s: --for > --pack-task > --query.
#
# Same two-part demand as the adjacent-pair arm above, in BOTH typed orders: stdout must be byte-identical to
# the winner's solo run (proving the named winner is the verb that answered) and stderr must name the winner
# and the ignored flag. The expected winners are read off the dispatch order the table now encodes, NOT
# observed-and-frozen.
crossOne()
{
    local WF="$1" LF="$2" A="$3" B="$4"
    "$BIN" "$FIX" "$A" "$B" >"$PRECTMP/xboth" 2>"$PRECTMP/xerr"
    if ! cmp -s "$PRECTMP/xsolo" "$PRECTMP/xboth"; then
        fail "cross-family [$A $B]: stdout is not $WF's solo output — $WF did not answer"
    elif ! grep -q "ripwire: $WF takes precedence" "$PRECTMP/xerr"; then
        fail "cross-family [$A $B]: stderr does not name $WF as the winner (got: $( head -c 140 "$PRECTMP/xerr" ))"
    elif ! grep -q "IGNORED this run: .*$LF" "$PRECTMP/xerr"; then
        fail "cross-family [$A $B]: stderr does not name $LF as ignored (got: $( head -c 140 "$PRECTMP/xerr" ))"
    else
        pass "cross-family [$A $B]: $WF wins, $LF disclosed as ignored"
    fi
}

# assertCross WINNER LOSER — runs the pair in both typed orders; the winner must not depend on typed order.
assertCross()
{
    local W="$1" L="$2"
    local WF="${W%%=*}" LF="${L%%=*}"
    "$BIN" "$FIX" "$W" >"$PRECTMP/xsolo" 2>/dev/null
    crossOne "$WF" "$LF" "$W" "$L"
    crossOne "$WF" "$LF" "$L" "$W"
}

# One rule for all three: the query family dispatches ahead of the whole table. --skipped and --hotspots are
# the two verbs that used to outrank --pack-task, and --lint is the one it already beat — all three now lose
# to every member of the family, which is the whole point of the change.
assertCross "--for=parse"       "--skipped"
assertCross "--for=parse"       "--hotspots"
assertCross "--for=parse"       "--lint"
assertCross "--pack-task=parse" "--skipped"
assertCross "--pack-task=parse" "--hotspots"
assertCross "--pack-task=parse" "--lint"
assertCross "--query=parse"     "--skipped"
assertCross "--query=parse"     "--hotspots"
assertCross "--query=parse"     "--lint"

# X9(c) owns the INTRA-family collision. The report-verb line must stay quiet for it, or one collision gets
# two warnings — the duplicate §B11.4 says it is avoiding, and the reason the three were excluded at all.
"$BIN" "$FIX" --for=parse --query=parse >/dev/null 2>"$PRECTMP/xf"
if grep -q 'takes precedence over --query/--pack-task' "$PRECTMP/xf" && ! grep -q 'IGNORED this run' "$PRECTMP/xf"; then
    pass "intra-family --for+--query: X9(c) discloses it once, the report-verb line stays quiet"
else
    fail "intra-family --for+--query: expected the X9(c) line alone (got: $( head -c 200 "$PRECTMP/xf" ))"
fi

# ...and when BOTH kinds of collision happen in one run, each line takes exactly its own half.
"$BIN" "$FIX" --for=parse --query=parse --lint >/dev/null 2>"$PRECTMP/xm"
if grep -q 'takes precedence over --query/--pack-task' "$PRECTMP/xm" && grep -q 'IGNORED this run: --lint\.' "$PRECTMP/xm"; then
    pass "mixed --for+--query+--lint: X9(c) takes --query, the report line takes --lint, neither repeats the other"
else
    fail "mixed --for+--query+--lint: expected X9(c) plus 'IGNORED this run: --lint.' (got: $( head -c 240 "$PRECTMP/xm" ))"
fi

# ── F1 — the ELEVEN verb-shaped flags the table never knew about ──────────────────────────────────────
#
# The adversarial verifier's F1: --quality-panel, --expand, --pack-signatures, --map-diff, --field-affinity,
# --naming-consistency and --index-out (plus, once swept properly, --readability, --comment-coherence,
# --nonlocal-state, --naming-calibration, --ensemble, --context-ratio and --handoff) were neither table rows
# nor pure modifiers. Every one of them collided with a real report verb at stderr-EMPTY, exit 0 — the F1
# reproducer being `--quality-panel --lint` (panel bytes, no signal) and `--expand=SYM --lint` (lint bytes,
# --expand silently thrown away).
#
# The eleven that SELECT A HANDLER are now rows (covered by PREC_VERBS above, plus the spot checks here
# against the two verbs that bracket them). The five that shape runDefaultMap are a separate class, below.
assertCross "--hotspots"           "--quality-panel"
assertCross "--quality-panel"      "--lint"
assertCross "--hotspots"           "--readability"
assertCross "--readability"        "--lint"
assertCross "--hotspots"           "--naming-consistency"
assertCross "--naming-consistency" "--lint"
assertCross "--hotspots"           "--field-affinity"
assertCross "--field-affinity"     "--lint"
assertCross "--ensemble"           "--hotspots"
assertCross "--context-ratio"      "--hotspots"
assertCross "--hotspots"           "--handoff"
assertCross "--handoff"            "--lint"

# ── F1 — --index-out dispatches ahead of EVERYTHING, including the query family ───────────────────────
#
# It runs before ingest (it IS the ingest-artifact generator), so it outranks even --for. That made it the
# one row that can beat a query-family flag, and the reason X9(c) is now gated on the family actually
# winning: a run where --index-out answered must not also claim "--for takes precedence".
IOTMP="$( mktemp -d )"; trap 'rm -rf "$PRECTMP" "$IOTMP"' EXIT
"$BIN" "$FIX" --index-out="$IOTMP/ix" --lint >"$IOTMP/o" 2>"$IOTMP/e"
if [ -s "$IOTMP/o" ]; then
    fail "--index-out+--lint: stdout is non-empty — --lint answered instead of --index-out"
elif ! grep -q -- '--index-out takes precedence' "$IOTMP/e"; then
    fail "--index-out+--lint: stderr does not name --index-out as the winner (got: $( head -c 160 "$IOTMP/e" ))"
elif ! grep -q -- 'IGNORED this run: .*--lint' "$IOTMP/e"; then
    fail "--index-out+--lint: stderr does not name --lint as ignored (got: $( head -c 160 "$IOTMP/e" ))"
else
    pass "--index-out+--lint: --index-out wins, --lint disclosed as ignored"
fi
"$BIN" "$FIX" --index-out="$IOTMP/iy" --for=parse >"$IOTMP/o2" 2>"$IOTMP/e2"
if grep -q -- '--for takes precedence over --query/--pack-task' "$IOTMP/e2"; then
    fail "--index-out+--for: X9(c) claims --for won, but --index-out answered"
elif ! grep -q -- 'IGNORED this run: .*--for' "$IOTMP/e2"; then
    fail "--index-out+--for: stderr does not disclose --for as ignored (got: $( head -c 160 "$IOTMP/e2" ))"
else
    pass "--index-out+--for: --index-out wins, --for disclosed, X9(c) stays quiet"
fi

# ── F1 — the MAP-MODIFIER class: --expand / --outline / --pack-signatures / --pack-top-n / --map-diff ──
#
# These five are NOT verbs: none of them selects a handler. They shape what runDefaultMap renders, and
# runDefaultMap serves exactly two runs — a flagless map and --query (which, as main() says, "owns no handler
# of its own"). So the uniform rule is: a map-modifier COMPOSES with any run that reaches the default map and
# is VOIDED by any report verb that answers first — and being voided is disclosed, because a silently dropped
# --expand answers a different question than the one that was asked.
#
# Giving them table ROWS would be wrong in a way this arm proves: a row makes the flag a winner or a loser,
# and `--query --expand` is neither — stdout there is NOT --query's solo output, because the two compose.
#
# composes NAME ARGS...  — stdout must DIFFER from the host verb's solo run, and stderr must stay quiet.
composes()
{
    local name="$1" host="$2" mod="$3"
    "$BIN" "$FIX" $host        >"$PRECTMP/csolo" 2>/dev/null
    "$BIN" "$FIX" $host "$mod" >"$PRECTMP/cboth" 2>"$PRECTMP/cerr"
    if cmp -s "$PRECTMP/csolo" "$PRECTMP/cboth"; then
        fail "$name: [$host $mod] is byte-identical to '$host' alone — $mod did not compose"
    elif grep -q 'DISCARDED this run' "$PRECTMP/cerr"; then
        fail "$name: [$host $mod] composed but stderr still calls $mod discarded"
    else
        pass "$name: [$host $mod] composes, no discard warning"
    fi
}

# voided NAME HOST MOD — stdout must equal the host verb's solo run, and the discard MUST be disclosed.
voided()
{
    local name="$1" host="$2" mod="$3"
    local mf="${mod%%=*}"
    "$BIN" "$FIX" $host        >"$PRECTMP/vsolo" 2>/dev/null
    "$BIN" "$FIX" $host "$mod" >"$PRECTMP/vboth" 2>"$PRECTMP/verr"
    if ! cmp -s "$PRECTMP/vsolo" "$PRECTMP/vboth"; then
        fail "$name: [$host $mod] is not '$host' solo — $mod changed the answer after all"
    elif ! grep -q "DISCARDED this run: .*$mf" "$PRECTMP/verr"; then
        fail "$name: [$host $mod] drops $mf in silence (stderr: $( head -c 160 "$PRECTMP/verr" ))"
    else
        pass "$name: [$host $mod] $mf voided and disclosed"
    fi
}

# the two runs that REACH runDefaultMap — the modifiers compose and nothing is warned
composes "mapmod-query-expand"   "--query=d2" "--expand=d2"
composes "mapmod-query-outline"  "--query=d2" "--outline=d2"
composes "mapmod-query-packsigs" "--query=d2" "--pack-signatures"
composes "mapmod-query-packtopn" "--query=d2" "--pack-top-n=3"
# --pack-top-n is the one map-modifier --for also honours (it budgets --for's bodies), so it composes there too
composes "mapmod-for-packtopn"   "--for=parse" "--pack-top-n=3"

# every report verb that answers first VOIDS them — and says so
voided "mapmod-lint-expand"        "--lint"        "--expand=d2"
voided "mapmod-lint-outline"       "--lint"        "--outline=d2"
voided "mapmod-lint-packsigs"      "--lint"        "--pack-signatures"
voided "mapmod-lint-mapdiff"       "--lint"        "--map-diff"
voided "mapmod-hotspots-expand"    "--hotspots"    "--expand=d2"
voided "mapmod-report-expand"      "--report"      "--expand=d2"
voided "mapmod-for-expand"         "--for=parse"   "--expand=d2"
voided "mapmod-packtask-expand"    "--pack-task=parse" "--expand=d2"
voided "mapmod-packtask-packtopn"  "--pack-task=parse" "--pack-top-n=3"
# --map-diff is the one map-modifier --query does NOT honour (its lexical-rank branch replaces the diff scope)
voided "mapmod-query-mapdiff"      "--query=d2"    "--map-diff"

# a map-modifier on a FLAGLESS run is the composing case with no host verb at all — it must stay silent.
"$BIN" "$FIX" --expand=d2 >/dev/null 2>"$PRECTMP/mf"
if grep -q 'DISCARDED this run\|takes precedence' "$PRECTMP/mf"; then
    fail "mapmod-flagless: --expand alone warned, but the default map is exactly what it modifies"
else
    pass "mapmod-flagless: --expand alone is silent (the map it shapes is the run)"
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
