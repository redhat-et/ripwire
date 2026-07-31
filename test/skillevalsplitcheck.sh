#!/usr/bin/env bash
# skillevalsplitcheck.sh — gate for the test/dev SPLIT on --eval-skills' labelled corpus (r26 P4,
# src/skilleval.h, test/skillevalfix/prompts.tsv). skillevalcheck.sh already pins that the harness
# WORKS; this gate pins the SEPARATE promise added this round: the n=43 judged rows (and every other
# row in the committed corpus) are a FROZEN test split, a future dev split is reported independently,
# split membership is stable (an explicit per-row column, not inferred), and a malformed split value
# is refused as loudly as a malformed provenance value always was.
#
#   test/skillevalsplitcheck.sh   |   CTXPACK_BIN=asan/ctxpack test/skillevalsplitcheck.sh
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/skillevalfix/prompts.tsv"
SKILLS="$ROOT/skills"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$CORPUS" ] || { echo "no corpus at $CORPUS"; exit 2; }

echo "skillevalsplitcheck: BIN=$BIN  CORPUS=$CORPUS"

"$BIN" "$SKILLS" --eval-skills="$CORPUS" --no-cache >"$TMP/a" 2>"$TMP/aerr"; rc_a=$?
[ $rc_a -eq 0 ] || { no "harness failed on the committed corpus (rc=$rc_a)"; head -4 "$TMP/aerr"; }

# ── 1) every row in the committed corpus is explicitly split=test (the freeze is on the file, not left
#    to the parser's back-compat default) — and there are no dev rows yet (empty today, as designed) ──
testRows=$( awk -F'\t' '!/^#/ && NF>=4 && $4=="test"{n++} END{print n+0}' "$CORPUS" )
devRows=$(  awk -F'\t' '!/^#/ && NF>=4 && $4=="dev"{n++}  END{print n+0}' "$CORPUS" )
dataRows=$( awk -F'\t' '!/^#/ && NF>=3 {n++} END{print n+0}' "$CORPUS" )
{ [ "$testRows" = "$dataRows" ] && [ "$devRows" = "0" ]; } \
    && ok "all ${dataRows} committed rows are split=test, 0 are split=dev (frozen, dev empty today)" \
    || no "split accounting off: dataRows=$dataRows testRows=$testRows devRows=$devRows"

judgedRows=$( awk -F'\t' '!/^#/ && NF>=3 && $3=="judged"{n++} END{print n+0}' "$CORPUS" )
awk -v j="$judgedRows" 'BEGIN{exit !(j+0 >= 40)}' \
    && ok "judged rows = ${judgedRows} (>= 40, the frozen hard set this round names)" \
    || no "judged rows = ${judgedRows} fell under 40 — the frozen set this gate protects shrank"

# ── 2) --eval-skills' own header reports split sizes, and they match the corpus exactly ─────────────
grep -q "split test=${dataRows} dev=0" "$TMP/a" \
    && ok "header reports split test=${dataRows} dev=0 (matches the corpus, not just asserted)" \
    || { no "header split counts missing/wrong (want test=${dataRows} dev=0)"; grep -o 'split test=[0-9]* dev=[0-9]*' "$TMP/a"; }

# ── 3) the split-specific report section exists, split=test's numbers equal the whole-corpus numbers
#    (today: whole corpus == test split, dev is empty) — and it does NOT collide with the existing
#    arm-name-keyed lookups skillevalcheck.sh performs (field 1 must be "split=test", never a bare arm) ─
grep -q '^  split=test ' "$TMP/a" && grep -q '^  split=dev ' "$TMP/a" \
    && ok "split=test and split=dev report sections both present" \
    || no "split report section(s) missing"

h1Overall=$( awk '$1=="bm25-desc"{gsub("%","",$2); print $2}' "$TMP/a" )
h1Split=$(   awk '$1=="split=test" && $2=="bm25-desc"{gsub("%","",$3); print $3}' "$TMP/a" )
[ -n "$h1Overall" ] && [ "$h1Overall" = "$h1Split" ] \
    && ok "split=test bm25-desc hit@1 (${h1Split}%) matches the whole-corpus number (${h1Overall}%) — dev is empty, so they must agree" \
    || no "split=test bm25-desc hit@1 ('$h1Split') != whole-corpus ('$h1Overall')"

# field-1 must never be the bare arm name for a split row (that would silently corrupt skillevalcheck.sh's
# `awk '$1=="bm25-desc"'`-style floors by adding a second matching line).
splitLinesWithBareArmField1=$( awk '$1=="bm25-desc" || $1=="overlap" || $1=="name" || $1=="bm25-full" || $1=="for-routed"{n++} END{print n+0}' "$TMP/a" )
[ "$splitLinesWithBareArmField1" = "5" ] \
    && ok "exactly 5 bare-arm-name field-1 lines in the whole output (the one overall table only — no collision)" \
    || no "found ${splitLinesWithBareArmField1} bare-arm-name field-1 lines (want exactly 5 — a split line is colliding)"

# ── 4) dev split, being empty, reports cleanly (no crash, no garbage, no div-by-zero) ───────────────
awk '/^  split=dev /{getline; print; exit}' "$TMP/a" | grep -q 'no positive rows in this split yet' \
    && ok "empty dev split reports cleanly instead of computing garbage stats" \
    || no "empty dev split did not print the expected empty-split message"

# ── 5) split membership is STABLE: two independent runs (fresh temp corpus copy, --no-cache) agree ──
cp "$CORPUS" "$TMP/copy.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/copy.tsv" --no-cache >"$TMP/copyrun" 2>/dev/null
grep -o 'split test=[0-9]* dev=[0-9]*' "$TMP/a" >"$TMP/split_a"
grep -o 'split test=[0-9]* dev=[0-9]*' "$TMP/copyrun" >"$TMP/split_copy"
cmp -s "$TMP/split_a" "$TMP/split_copy" \
    && ok "split membership is stable across independent runs (same file, copied path)" \
    || no "split counts differ between two runs of the same corpus"

# ── 6) a hand-labelled dev row is honored: a single extra split=dev row shows up ONLY in the dev split,
#    dev's own numbers move, and test's numbers are UNCHANGED (the two must never be conflated) ────────
cp "$CORPUS" "$TMP/plusdev.tsv"
printf 'Wire ctxpack into Cursor as an MCP server, tuning row.\tctxpack-mcp\tjudged\tdev\n' >>"$TMP/plusdev.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/plusdev.tsv" --no-cache >"$TMP/plusdevrun" 2>/dev/null
grep -q "split test=${dataRows} dev=1" "$TMP/plusdevrun" \
    && ok "an added split=dev row is counted as dev=1, test stays at ${dataRows}" \
    || { no "added dev row not reflected in header split counts"; grep -o 'split test=[0-9]* dev=[0-9]*' "$TMP/plusdevrun"; }
h1TestAfter=$( awk '$1=="split=test" && $2=="bm25-desc"{gsub("%","",$3); print $3}' "$TMP/plusdevrun" )
[ "$h1TestAfter" = "$h1Split" ] \
    && ok "test split's bm25-desc hit@1 (${h1TestAfter}%) is UNCHANGED by the extra dev row — no conflation" \
    || no "test split's numbers moved (${h1TestAfter}% vs ${h1Split}%) when a dev row was added — conflation bug"

# ── 7) a malformed split value is refused as loudly as a malformed provenance value ──────────────────
printf 'Some prompt\tctxpack-orient\tjudged\tstaging\n' >"$TMP/badsplit.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/badsplit.tsv" --no-cache >/dev/null 2>"$TMP/badsplerr"; rc_bs=$?
{ [ $rc_bs -ne 0 ] && grep -q 'unknown split' "$TMP/badsplerr"; } \
    && ok "an unrecognized split value ('staging') refuses loudly (rc=$rc_bs)" \
    || { no "unrecognized split value did not refuse cleanly (rc=$rc_bs)"; cat "$TMP/badsplerr"; }

# ── 8) back-compat: a bare 3-column row (no split at all) still parses, defaulting to test ───────────
printf 'Some other prompt\tctxpack-orient\tjudged\n' >"$TMP/nosplit.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/nosplit.tsv" --no-cache >"$TMP/nosplitrun" 2>"$TMP/nosplerr"; rc_ns=$?
{ [ $rc_ns -eq 0 ] && grep -q 'split test=1 dev=0' "$TMP/nosplitrun"; } \
    && ok "a 3-column row with no split column defaults to test (back-compat)" \
    || { no "3-column row did not default cleanly to test"; cat "$TMP/nosplerr"; }

[ "$fail" = 0 ] && echo "skillevalsplitcheck: ALL PASS" || echo "skillevalsplitcheck: FAILURES ABOVE"
exit $fail
