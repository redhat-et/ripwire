#!/usr/bin/env bash
# docmentioncheck.sh — R5: doc-mention surfacing on the --for lens.
#
# Reuses g.mentions (the SAME doc<->code backtick edges the `--mentions=SYM` verb already exposes; built
# OUT of the call graph so a doc naming a symbol never inflates that symbol's own PageRank/blast-radius —
# untouched by this feature) to lift, into --for's ranked bundle, a doc that names one of the query's
# top-resolved symbols — even when the doc's OWN prose shares no other words with the query (closing the
# "the doc explains it but --recall's lexical score never sees the code side" gap; recall.h's own comment
# notes the graph half is deliberately NOT fused into --recall — this is the --for-side counterpart, on
# purpose kept out of --recall).
#
# Pinned promises:
#   (i)   SIGNAL — a doc that `backtick`-mentions the query's #1-resolved symbol gets a HIGHER lensRank with
#         the boost on than off (routed AND --no-route; the note is present on default output).
#   (ii)  NEVER OUTRANKS THE CODE IT DISCUSSES — the lifted doc's score stays strictly below the anchor's own
#         score (kDocMentionDecay < 1); the anchor itself (#1) is unaffected.
#   (iii) TARGETED, NOT SWAMPING — a doc mentioning an UNRELATED symbol (never resolved by this query) is not
#         lifted; docs are capped per-anchor even when many mention the same symbol (bounded, not flooding).
#   (iv)  INERT WITHOUT MENTIONS — a query whose resolved symbol nobody mentions leaves output BYTE-IDENTICAL
#         boost-on vs boost-off.
#   (v)   DETERMINISM x3, xmllint-clean, env (RIPWIRE_NO_DOC_MENTION=1) == flag (--no-doc-mention) byte-for-
#         byte, and the flag alone refuses loudly; --pack-task carries the same note (shared computeLensRanking).
#
# Usage:  bash test/docmentioncheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/docmentioncheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "docmentioncheck: BIN=$BIN"

# ── fixture: a code symbol (compute_widget_total), a design doc that backtick-mentions it in prose sharing
# no other query words, several filler code files, an unrelated doc mentioning a DIFFERENT never-queried
# symbol, and a stress file that pads the SAME symbol's mention count past the per-anchor cap. ────────────
FIX="$TMP/fix"
mkdir -p "$FIX/pkg"
cat > "$FIX/pkg/alpha.py" <<'PY'
def compute_widget_total(records):
    """Sum the confirmed item counts for a widget order."""
    return sum(r.count for r in records)

def unrelated_helper():
    return 42
PY
cat > "$FIX/pkg/beta.py" <<'PY'
def flush_stale_cache(entries):
    """Evict stale cache entries."""
    return [e for e in entries if e.fresh]
PY
cat > "$FIX/pkg/gamma.py" <<'PY'
def parse_manifest_header(bytestream):
    """Parse the manifest header block."""
    return bytestream[:16]
PY
cat > "$FIX/DESIGN_widgetTotals.md" <<'MD'
# Order total design

RFC-42 governs the checkout-summary invariant: every returned amount must equal the sum of
confirmed line items, rounded to two decimal places, before tax is applied downstream. Refund
adjustments happen in a later pass and must never mutate the original ledger row. The
`compute_widget_total` routine is the canonical implementation of that invariant and every
call site should route through it rather than re-deriving the sum locally.
MD
cat > "$FIX/NOTES_scratch.md" <<'MD'
# Scratch notes

Random unrelated musings about `unrelated_helper` and the weather forecast for next week.
MD
for i in 1 2 3 4 5 6 7 8 9 10; do
cat > "$FIX/DOC_extra_$i.md" <<MD
# Extra doc $i

Padding prose entry $i that also discusses the \`compute_widget_total\` routine from a slightly
different angle, so this fixture has 11 total docs mentioning the same symbol (past the per-
anchor cap) — proves the bound fires, not just "some cap exists".
MD
done

cands(){ "$BIN" "$FIX" --for="$1" --format=candidates --top-k=30 --no-cache "${@:2}" 2>/dev/null; }
scoreOf(){ printf '%s' "$1" | grep -o 's="[0-9.]*" n="'"$2"'"' | grep -o '^s="[0-9.]*"' | grep -o '[0-9.]*' | head -1; }

Q="compute_widget_total"

# ── (i) signal: routed AND --no-route, boost-on score > boost-off score ────────────────────────────────
# 2026-08-12 markdown section tier (mdsectioncheck): a `backtick` mention now attributes to its
# enclosing SECTION, so the lift surfaces the SECTION that discusses the symbol ("Order total
# design"), not the whole-doc file node ("DESIGN_widgetTotals") — strictly more precise, and exactly
# the tier's deliver-the-section contract. The row this arm scores moved with it, same wave.
LIFTED="Order total design"
ON="$( cands "$Q" )";               OFF="$( cands "$Q" --no-doc-mention )"
sOn="$( scoreOf "$ON" "$LIFTED" )"; sOff="$( scoreOf "$OFF" "$LIFTED" )"
awk -v a="${sOn:-0}" -v b="${sOff:-0}" 'BEGIN{exit !(a>b)}' \
    && ok "routed: mentioning doc's SECTION score lifted ($sOn vs $sOff off)" \
    || no "routed: mentioning doc's SECTION NOT lifted (on=${sOn:-0} off=${sOff:-0})"

ONnr="$( cands "$Q" --no-route )";   OFFnr="$( cands "$Q" --no-route --no-doc-mention )"
sOnNr="$( scoreOf "$ONnr" "$LIFTED" )"; sOffNr="$( scoreOf "$OFFnr" "$LIFTED" )"
awk -v a="${sOnNr:-0}" -v b="${sOffNr:-0}" 'BEGIN{exit !(a>b)}' \
    && ok "--no-route: mentioning doc score lifted ($sOnNr vs $sOffNr off) — routefix/anchorfix WILL drift, expected" \
    || no "--no-route: mentioning doc NOT lifted (on=${sOnNr:-0} off=${sOffNr:-0})"

"$BIN" "$FIX" --for="$Q" --no-cache 2>/dev/null | grep -q 'doc mentions:' \
    && ok "--for header names the doc-mention lift" || no "--for header note missing"
"$BIN" "$FIX" --pack-task="$Q" --no-cache 2>/dev/null | grep -q 'doc mentions:' \
    && ok "--pack-task carries the same note (shared computeLensRanking)" || no "--pack-task note missing"

# ── (ii) never outranks the code it discusses; anchor (#1) unaffected ──────────────────────────────────
sAnchorOn="$( scoreOf "$ON" compute_widget_total )"; sAnchorOff="$( scoreOf "$OFF" compute_widget_total )"
[ -n "$sAnchorOn" ] && [ "$sAnchorOn" = "$sAnchorOff" ] \
    && ok "anchor's own score unaffected by the boost ($sAnchorOn)" \
    || no "anchor's score changed: on=$sAnchorOn off=$sAnchorOff"
# non-vacuity: sOn is the LIFTED section's real score — a 0 here means the row lookup broke, and
# 0 < anchor would pass green-while-inert.
awk -v doc="${sOn:-0}" 'BEGIN{exit !(doc > 0)}' \
    && ok "lifted section's score is a real (non-zero) reading" \
    || no "lifted section's score reads 0 — the row lookup is broken, the below-anchor arm would be vacuous"
awk -v doc="${sOn:-0}" -v anc="${sAnchorOn:-0}" 'BEGIN{exit !(doc < anc)}' \
    && ok "lifted section stays strictly below the anchor's own score ($sOn < $sAnchorOn)" \
    || no "lifted section ($sOn) did not stay below the anchor ($sAnchorOn)"
top1on="$( printf '%s' "$ON"  | grep -o '<cand r="1" [^>]*n="[^"]*"' )"
top1off="$( printf '%s' "$OFF" | grep -o '<cand r="1" [^>]*n="[^"]*"' )"
[ -n "$top1on" ] && [ "$top1on" = "$top1off" ] && ok "top-1 identical boost-on vs boost-off" \
    || no "top-1 displaced:  ON<<$top1on>>  OFF<<$top1off>>"

# ── (iii) targeted, not swamping ────────────────────────────────────────────────────────────────────────
sUnrelated="$( scoreOf "$ON" NOTES_scratch )"
[ "${sUnrelated:-0}" = "0" ] && ok "doc mentioning an unrelated (never-resolved) symbol is NOT lifted" \
    || no "unrelated doc was lifted (score=${sUnrelated:-0})"
NOTE="$( "$BIN" "$FIX" --for="$Q" --no-cache 2>/dev/null | grep -o 'doc mentions: [0-9]* doc' )"
printf '%s' "$NOTE" | grep -q '^doc mentions: 2 doc' \
    && ok "per-anchor cap fires: 2 of 11 mentioning docs kept ($NOTE)" \
    || no "per-anchor cap did not fire as expected ($NOTE)"

# ── (iv) inert without mentions ─────────────────────────────────────────────────────────────────────────
Q2="flush_stale_cache"
"$BIN" "$FIX" --for="$Q2" --no-cache            >"$TMP/i1.xml" 2>/dev/null
"$BIN" "$FIX" --for="$Q2" --no-doc-mention --no-cache >"$TMP/i2.xml" 2>/dev/null
cmp -s "$TMP/i1.xml" "$TMP/i2.xml" && ok "inert on a symbol nobody mentions (byte-identical)" \
    || no "NOT inert on a mention-free symbol"
grep -q 'doc mentions:' "$TMP/i1.xml" && no "header note must not appear when nothing lifted" \
    || ok "no header note when nothing lifted"

# ── (v) determinism x3, xmllint, env==flag, refuse-loudly ──────────────────────────────────────────────
"$BIN" "$FIX" --for="$Q" --no-cache >"$TMP/d1.xml" 2>/dev/null
"$BIN" "$FIX" --for="$Q" --no-cache >"$TMP/d2.xml" 2>/dev/null
"$BIN" "$FIX" --for="$Q" --no-cache >"$TMP/d3.xml" 2>/dev/null
cmp -s "$TMP/d1.xml" "$TMP/d2.xml" && cmp -s "$TMP/d2.xml" "$TMP/d3.xml" && ok "determinism x3 (doc-mention lifted)" \
    || no "doc-mention output not deterministic"
if command -v xmllint >/dev/null; then
    xmllint --noout "$TMP/d1.xml" 2>/dev/null && ok "doc-mention bundle is xmllint-clean (G4)" || no "doc-mention bundle not well-formed"
else ok "xmllint not present — skipped (G4 covered by xmlwellformed.sh)"; fi
"$BIN" "$FIX" --for="$Q" --no-doc-mention --no-cache >"$TMP/f1.xml" 2>/dev/null
RIPWIRE_NO_DOC_MENTION=1 "$BIN" "$FIX" --for="$Q" --no-cache >"$TMP/f2.xml" 2>/dev/null
cmp -s "$TMP/f1.xml" "$TMP/f2.xml" && ok "RIPWIRE_NO_DOC_MENTION=1 == --no-doc-mention (byte-identical)" \
    || no "env disable and flag disable diverge"
"$BIN" "$FIX" --no-doc-mention >/dev/null 2>"$TMP/refuse.err"
[ $? -ne 0 ] && grep -q 'no-doc-mention' "$TMP/refuse.err" && ok "flag alone refuses loudly" || no "flag alone did not refuse"

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
