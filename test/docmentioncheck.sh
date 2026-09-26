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
#   (vi)  CHANGE LOGS AND TRANSLATIONS GO LAST IN THE LIFT on a code question (filter.h docNoiseSymbolMultipliers):
#         consulted after every other doc and lifted lower, never dropped; the default-language docs keep the lift;
#         a change / translation question, a named file, --no-route and a single-language repo keep the old lift.
#
# Usage:  bash test/docmentioncheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/docmentioncheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
# L1 (2026-09-19): the CLI default legend is compact; this arm reads the FULL --pack-task legend's doc-mention note, so it asks for it.
"$BIN" "$FIX" --pack-task="$Q" --no-cache --legend=full 2>/dev/null | grep -q 'doc mentions:' \
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
    if xmllint --noout "$TMP/d1.xml" 2>/dev/null; then ok "doc-mention bundle is xmllint-clean (G4)"; else no "doc-mention bundle not well-formed"; fi
else ok "xmllint not present — skipped (G4 covered by xmlwellformed.sh)"; fi
"$BIN" "$FIX" --for="$Q" --no-doc-mention --no-cache >"$TMP/f1.xml" 2>/dev/null
RIPWIRE_NO_DOC_MENTION=1 "$BIN" "$FIX" --for="$Q" --no-cache >"$TMP/f2.xml" 2>/dev/null
cmp -s "$TMP/f1.xml" "$TMP/f2.xml" && ok "RIPWIRE_NO_DOC_MENTION=1 == --no-doc-mention (byte-identical)" \
    || no "env disable and flag disable diverge"
"$BIN" "$FIX" --no-doc-mention >/dev/null 2>"$TMP/refuse.err"
if [ $? -ne 0 ] && grep -q 'no-doc-mention' "$TMP/refuse.err"; then ok "flag alone refuses loudly"; else no "flag alone did not refuse"; fi

# ── §L10b (finding #1): doc_mentions= is a root ATTRIBUTE, not just legend prose — the "doc mentions: N
#    doc..." note had no machine-readable twin, so a caller that wants the count without parsing prose had
#    nothing to read. The XML root now carries doc_mentions="N" (N == the note's own doc count, 2 here per
#    the per-anchor-cap arm above) whenever the note fires, and is ABSENT (never doc_mentions="0") when it
#    does not — the JSON dialect gets the matching numeric "doc_mentions" key beside its "doc_mention" prose.
DM_ATTR="$( grep -o 'doc_mentions="[0-9]*"' "$TMP/d1.xml" | head -1 )"
[ "$DM_ATTR" = 'doc_mentions="2"' ] && ok "L10b: XML root carries doc_mentions=\"2\" (matches the note's own count)" \
    || no "L10b: XML root doc_mentions= missing or wrong (got '${DM_ATTR:-<absent>}')"
grep -q 'doc_mentions=' "$TMP/i1.xml" && no "L10b: doc_mentions= present on a query the boost never touched" \
    || ok "L10b: doc_mentions= absent when the note did not fire (never doc_mentions=\"0\")"
JSON_HIT="$( "$BIN" "$FIX" --for="$Q" --json --no-cache 2>/dev/null )"
printf '%s' "$JSON_HIT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("doc_mentions")==2, d.get("doc_mentions")' \
    && ok "L10b: --json carries the matching \"doc_mentions\":2" \
    || no "L10b: --json doc_mentions key missing or wrong"

# ── (vi) CHANGE LOGS AND TRANSLATIONS GO LAST IN THE LIFT on a code question (filter.h docNoiseSymbolMultipliers) ──
# Dogfood 2026-09-26: on a public repo, three CHANGELOG `### Added` sections and a translated README section took
# 4 of the top 20 --for slots for a code question. Both kinds backtick the identifiers the code defines, so the
# doc-mention lift raised them to 0.55 x their anchor, above weaker real code — and, taking the lowest node ids
# first under the per-anchor cap, ahead of the default-language README that actually explains the code.
# Fixture NF: 8 stage functions that match the question strongly, 40 weaker helpers that match it too, a README
# explaining stage 1, a CHANGELOG and two translated READMEs (basename form) that backtick the stages, a docs/en +
# docs/ko pair (directory form), and ui/README.md — a two-letter directory that is NOT a language, beside a root
# README.md (the removal-twin guard's control).
NF="$TMP/noisefix"
mkdir -p "$NF/search" "$NF/docs/en" "$NF/docs/ko" "$NF/ui"
for i in 1 2 3 4 5 6 7 8; do
cat > "$NF/search/stage$i.py" <<PY
def rank_search_results_stage$i(query, results):
    """Rank the search results for a query: stage $i ranks results by query score."""
    return sorted(results, key=lambda r: r.score, reverse=True)
PY
done
for i in $( seq 1 40 ); do
cat > "$NF/search/helper$i.py" <<PY
def helper_$i(items):
    """Helper $i used while results are ranked."""
    return list(items)
PY
done
printf '# Search\n\n## How ranking works\n\nThe ranker runs `rank_search_results_stage1` first.\n' > "$NF/README.md"
for lang in zh-CN ja; do
    { printf '# Search %s\n' "$lang"; for i in 1 2 3 4 5 6 7 8; do printf '\n## %s\n\n`rank_search_results_stage%s`\n' "$i" "$i"; done; } > "$NF/README.$lang.md"
done
{ printf '# Changelog\n'; for i in 1 2 3 4 5 6 7 8; do printf '\n## [1.%s.0]\n\n### Added\n\n- `rank_search_results_stage%s`\n' "$i" "$i"; done; } > "$NF/CHANGELOG.md"
printf '# Guide\n\n## Stage two\n\n`rank_search_results_stage2` runs second.\n' > "$NF/docs/en/guide.md"
printf '# Guide ko\n\n## 2\n\n`rank_search_results_stage2`\n' > "$NF/docs/ko/guide.md"
printf '# UI\n\n## Stage three in the UI\n\n`rank_search_results_stage3` feeds the results panel.\n' > "$NF/ui/README.md"
# presence guards: every file the arms below read must exist, or an arm can pass on nothing
for f in CHANGELOG.md README.md README.zh-CN.md README.ja.md docs/en/guide.md docs/ko/guide.md ui/README.md search/helper40.py; do
    [ -f "$NF/$f" ] || no "fixture NF: $f was not written"
done

NQ="how are search results ranked for a query"
ncands(){ "$BIN" "$NF" --for="$1" --format=candidates --top-k=60 --no-cache "${@:2}" 2>/dev/null; }
# rank of the first candidate row whose path matches $2 (an ERE), or 999 when none does
rankOf(){ printf '%s' "$1" | grep -oE '<cand r="[0-9]+"[^>]* p="[^"]*"' | grep -E " p=\"$2\"" | head -1 | grep -oE 'r="[0-9]+"' | grep -oE '[0-9]+' || echo 999; }
# rank of the LAST code (k="fn") row, and how many code rows there are
lastFnRank(){ printf '%s' "$1" | grep -oE '<cand r="[0-9]+"[^>]* k="fn"' | tail -1 | grep -oE 'r="[0-9]+"' | grep -oE '[0-9]+'; }
fnCount(){ printf '%s' "$1" | grep -oE '<cand r="[0-9]+"[^>]* k="fn"' | wc -l | tr -d ' '; }
NOISE='(CHANGELOG\.md|README\.(zh-CN|ja)\.md|docs/ko/guide\.md)'

CQ="$( ncands "$NQ" )"
lastFn="$( lastFnRank "$CQ" )"; firstNoise="$( rankOf "$CQ" "$NOISE" )"
[ "$( fnCount "$CQ" )" = 48 ] && ok "(vi) NF: all 48 code rows are in the 60-row candidate list (non-vacuity)" \
    || no "(vi) NF: expected the 48 code rows in the candidate list, found $( fnCount "$CQ" )"
[ "$firstNoise" != 999 ] && ok "(vi) NF: the change-log/translation rows are still candidates (r=$firstNoise): demoted, never dropped" \
    || no "(vi) NF: no change-log/translation row among the candidates — the tier must rank them lower, not drop them"
[ "$firstNoise" -gt "${lastFn:-0}" ] && ok "(vi) code question: every code row ranks above every change-log/translation row ($lastFn < $firstNoise)" \
    || no "(vi) code question: a change-log/translation row (r=$firstNoise) ranks above code (last code row r=${lastFn:-none})"
rReadme="$( rankOf "$CQ" 'README\.md' )"
[ "$rReadme" = 9 ] && ok "(vi) the default-language README section is lifted right after the 8 stages it explains (r=9)" \
    || no "(vi) README.md's explaining section is at r=$rReadme, not r=9 — the cap still spent on demoted docs first"
rEn="$( rankOf "$CQ" 'docs/en/guide\.md' )"; rUi="$( rankOf "$CQ" 'ui/README\.md' )"
[ "$rEn" -lt "${lastFn:-0}" ] && ok "(vi) directory form: docs/en/guide.md (the default-language twin) keeps its lift (r=$rEn)" \
    || no "(vi) directory form: docs/en/guide.md is not lifted above code (r=$rEn): demoted, or its cap slot spent on a demoted doc"
[ "$rUi" -lt "${lastFn:-0}" ] && ok "(vi) removal-twin guard: ui/README.md beside README.md is not taken for a translation (r=$rUi)" \
    || no "(vi) removal-twin guard: ui/README.md is not lifted above code (r=$rUi): taken for a translation, or its cap slot spent on a demoted doc"
# the served head (<sigs>, default --for) holds no change-log/translation row on the code question
"$BIN" "$NF" --for="$NQ" --no-cache >"$TMP/nf1.xml" 2>/dev/null
grep -q '<sigs[ >]' "$TMP/nf1.xml" || no "(vi) NF: --for served no <sigs> head"
if sed 's/></>\n</g' "$TMP/nf1.xml" | grep -E '^<d ' | grep -qE " p=\"$NOISE\""; then
    no "(vi) served head carries a change-log/translation row on a code question"
else ok "(vi) served head carries no change-log/translation row on a code question"; fi

# controls — the tier yields whenever the question is about what those files hold: the SAME code question plus
# one cue word gets the old lift back for exactly the family the cue names
CC="$( ncands "$NQ, and what changed in 1.3.0" )"
rCl="$( rankOf "$CC" 'CHANGELOG\.md' )"; lastFnC="$( lastFnRank "$CC" )"
[ "$rCl" -lt "${lastFnC:-0}" ] && ok "(vi) control: a change question still lifts the CHANGELOG above code (r=$rCl)" \
    || no "(vi) control: a change question lost the CHANGELOG (r=$rCl, last code r=${lastFnC:-none})"
CN="$( ncands "what does README.zh-CN.md say about how search results are ranked" )"
rZh="$( rankOf "$CN" 'README\.zh-CN\.md' )"
[ "$rZh" -le 10 ] && ok "(vi) control: a question naming README.zh-CN.md ranks it in the top 10 (r=$rZh)" \
    || no "(vi) control: a question naming README.zh-CN.md ranked it at r=$rZh"
CT="$( ncands "$NQ, per the translated docs" )"
rTr="$( rankOf "$CT" 'README\.(zh-CN|ja)\.md' )"; lastFnT="$( lastFnRank "$CT" )"
[ "$rTr" -lt "${lastFnT:-0}" ] && ok "(vi) control: a translation question keeps translated READMEs above code (r=$rTr)" \
    || no "(vi) control: a translation question lost the translated READMEs (r=$rTr)"
NR="$( ncands "$NQ" --no-route )"
[ "$( rankOf "$NR" "$NOISE" )" -lt "$( lastFnRank "$NR" )" ] && ok "(vi) --no-route restores the untiered lift (the A/B handle)" \
    || no "(vi) --no-route did not restore the untiered lift"

# control — a single-language repo: no change log, no translation, so the tier is inert (its README keeps r=9)
SL="$TMP/singlelang"; mkdir -p "$SL"; cp -R "$NF/search" "$SL/"; cp "$NF/README.md" "$SL/"
SQ="$( "$BIN" "$SL" --for="$NQ" --format=candidates --top-k=60 --no-cache 2>/dev/null )"
[ "$( rankOf "$SQ" 'README\.md' )" = 9 ] && ok "(vi) control: a single-language repo's README keeps its lift (r=9)" \
    || no "(vi) control: a single-language repo's README moved to r=$( rankOf "$SQ" 'README\.md' )"

"$BIN" "$NF" --for="$NQ" --no-cache >"$TMP/nf2.xml" 2>/dev/null
cmp -s "$TMP/nf1.xml" "$TMP/nf2.xml" && ok "(vi) determinism: the tiered --for answer is byte-identical across runs" \
    || no "(vi) tiered --for answer differs between two runs"

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
