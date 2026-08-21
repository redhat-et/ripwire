#!/usr/bin/env bash
# skillevalsplitcheck.sh — gate for the test/dev SPLIT on --eval-skills' labelled corpus (r26 P4,
# src/skilleval.h, test/skillevalfix/prompts.tsv). skillevalcheck.sh already pins that the harness
# WORKS; this gate pins the SEPARATE promise added this round: the n=43 judged rows (and every other
# row in the committed corpus) are a FROZEN test split, a future dev split is reported independently,
# split membership is stable (an explicit per-row column, not inferred), and a malformed split value
# is refused as loudly as a malformed provenance value always was.
#
#   test/skillevalsplitcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/skillevalsplitcheck.sh
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

echo "skillevalsplitcheck: BIN=$BIN  CORPUS=$CORPUS"

"$BIN" "$SKILLS" --eval-skills="$CORPUS" --no-cache >"$TMP/a" 2>"$TMP/aerr"; rc_a=$?
[ $rc_a -eq 0 ] || { no "harness failed on the committed corpus (rc=$rc_a)"; head -4 "$TMP/aerr"; }

# ── 1) the FROZEN test split holds at exactly 128 rows (that count must never move — see prompts.tsv's
#    own header), and test+dev accounts for every row in the corpus with none silently falling through.
#    2026-08-11 (S1 growth pass): the one sanctioned kind of move — a deliberate, sealed growth EVENT —
#    grew the frozen split 128→183 append-only (split assigned by sha256(prompt) parity at collection,
#    corpus hash sealed in the growth commit); the pinned count above now reads 183 and stays frozen there.
#    2026-08-08: the dev split gained its first n=20 tuning rows (audit H1 follow-up), so this gate no
#    longer asserts dev is empty — it asserts the FROZEN half stays frozen and the accounting still closes.
testRows=$( awk -F'\t' '!/^#/ && NF>=4 && $4=="test"{n++} END{print n+0}' "$CORPUS" )
devRows=$(  awk -F'\t' '!/^#/ && NF>=4 && $4=="dev"{n++}  END{print n+0}' "$CORPUS" )
dataRows=$( awk -F'\t' '!/^#/ && NF>=3 {n++} END{print n+0}' "$CORPUS" )
{ [ "$testRows" = "183" ] && [ "$(( testRows + devRows ))" = "$dataRows" ]; } \
    && ok "frozen test split holds at 183 rows; test+dev (${testRows}+${devRows}) accounts for all ${dataRows} corpus rows" \
    || no "split accounting off: dataRows=$dataRows testRows=$testRows devRows=$devRows (test must stay exactly 183)"

# Scoped to split=test: the frozen hard set this round names lives there, and the 2026-08-08 dev split
# also carries judged-provenance rows that must not be able to mask a shrink of the frozen ones.
judgedRows=$( awk -F'\t' '!/^#/ && NF>=3 && $3=="judged" && ( NF<4 || $4=="test" ){n++} END{print n+0}' "$CORPUS" )
awk -v j="$judgedRows" 'BEGIN{exit !(j+0 >= 80)}' \
    && ok "judged rows (split=test) = ${judgedRows} (>= 80, the frozen hard set after the 2026-08-11 growth pass)" \
    || no "judged rows (split=test) = ${judgedRows} fell under 80 — the frozen set this gate protects shrank"

# ── 2) --eval-skills' own header reports split sizes, and they match the corpus exactly ─────────────
grep -q "split test=${testRows} dev=${devRows}" "$TMP/a" \
    && ok "header reports split test=${testRows} dev=${devRows} (matches the corpus, not just asserted)" \
    || { no "header split counts missing/wrong (want test=${testRows} dev=${devRows})"; grep -o 'split test=[0-9]* dev=[0-9]*' "$TMP/a"; }

# ── 3) the split-specific report section exists, and does NOT collide with the existing arm-name-keyed
#    lookups skillevalcheck.sh performs (field 1 must be "split=test"/"split=dev", never a bare arm) ────
grep -q '^  split=test ' "$TMP/a" && grep -q '^  split=dev ' "$TMP/a" \
    && ok "split=test and split=dev report sections both present" \
    || no "split report section(s) missing"

h1Split=$( awk '$1=="split=test" && $2=="bm25-desc"{gsub("%","",$3); print $3}' "$TMP/a" )

# split=test's OWN numbers must be invariant to whatever lives in split=dev — proved by comparing against
# a temp corpus with every dev row stripped, rather than the (now populated, since 2026-08-08) whole-corpus
# number, which no longer equals split=test's number and is not what this gate is protecting.
awk -F'\t' '/^#/||$0==""{print;next} NF<4 || $4!="dev"{print}' "$CORPUS" >"$TMP/onlytest.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/onlytest.tsv" --no-cache >"$TMP/onlytestrun" 2>/dev/null
h1TestAlone=$( awk '$1=="split=test" && $2=="bm25-desc"{gsub("%","",$3); print $3}' "$TMP/onlytestrun" )
[ -n "$h1Split" ] && [ "$h1Split" = "$h1TestAlone" ] \
    && ok "split=test bm25-desc hit@1 (${h1Split}%) is IDENTICAL whether or not dev rows are present — no conflation" \
    || no "split=test bm25-desc hit@1 changed when dev rows were stripped (${h1Split}% vs ${h1TestAlone}%) — conflation bug"

# field-1 must never be the bare arm name for a split row (that would silently corrupt skillevalcheck.sh's
# `awk '$1=="bm25-desc"'`-style floors by adding a second matching line).
splitLinesWithBareArmField1=$( awk '$1=="bm25-desc" || $1=="overlap" || $1=="name" || $1=="bm25-full" || $1=="for-routed"{n++} END{print n+0}' "$TMP/a" )
[ "$splitLinesWithBareArmField1" = "5" ] \
    && ok "exactly 5 bare-arm-name field-1 lines in the whole output (the one overall table only — no collision)" \
    || no "found ${splitLinesWithBareArmField1} bare-arm-name field-1 lines (want exactly 5 — a split line is colliding)"

# ── 4) an EMPTY dev split still reports cleanly (no crash, no garbage, no div-by-zero) — the committed
#    corpus's dev split is populated now, so this exercises it against the dev-stripped temp corpus above ─
awk '/^  split=dev /{getline; print; exit}' "$TMP/onlytestrun" | grep -q 'no positive rows in this split yet' \
    && ok "an empty dev split (temp corpus, dev rows stripped) reports cleanly instead of computing garbage stats" \
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
printf 'Wire ripwire into Cursor as an MCP server, tuning row.\tripwire-mcp\tjudged\tdev\n' >>"$TMP/plusdev.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/plusdev.tsv" --no-cache >"$TMP/plusdevrun" 2>/dev/null
devRowsAfter=$(( devRows + 1 ))
grep -q "split test=${testRows} dev=${devRowsAfter}" "$TMP/plusdevrun" \
    && ok "an added split=dev row bumps dev to ${devRowsAfter}, test stays at ${testRows}" \
    || { no "added dev row not reflected in header split counts"; grep -o 'split test=[0-9]* dev=[0-9]*' "$TMP/plusdevrun"; }
h1TestAfter=$( awk '$1=="split=test" && $2=="bm25-desc"{gsub("%","",$3); print $3}' "$TMP/plusdevrun" )
[ "$h1TestAfter" = "$h1Split" ] \
    && ok "test split's bm25-desc hit@1 (${h1TestAfter}%) is UNCHANGED by the extra dev row — no conflation" \
    || no "test split's numbers moved (${h1TestAfter}% vs ${h1Split}%) when a dev row was added — conflation bug"

# ── 7) a malformed split value is refused as loudly as a malformed provenance value ──────────────────
printf 'Some prompt\tripwire-orient\tjudged\tstaging\n' >"$TMP/badsplit.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/badsplit.tsv" --no-cache >/dev/null 2>"$TMP/badsplerr"; rc_bs=$?
{ [ $rc_bs -ne 0 ] && grep -q 'unknown split' "$TMP/badsplerr"; } \
    && ok "an unrecognized split value ('staging') refuses loudly (rc=$rc_bs)" \
    || { no "unrecognized split value did not refuse cleanly (rc=$rc_bs)"; cat "$TMP/badsplerr"; }

# ── 8) back-compat: a bare 3-column row (no split at all) still parses, defaulting to test ───────────
printf 'Some other prompt\tripwire-orient\tjudged\n' >"$TMP/nosplit.tsv"
"$BIN" "$SKILLS" --eval-skills="$TMP/nosplit.tsv" --no-cache >"$TMP/nosplitrun" 2>"$TMP/nosplerr"; rc_ns=$?
{ [ $rc_ns -eq 0 ] && grep -q 'split test=1 dev=0' "$TMP/nosplitrun"; } \
    && ok "a 3-column row with no split column defaults to test (back-compat)" \
    || { no "3-column row did not default cleanly to test"; cat "$TMP/nosplerr"; }

[ "$fail" = 0 ] && echo "skillevalsplitcheck: ALL PASS" || echo "skillevalsplitcheck: FAILURES ABOVE"
exit $fail
