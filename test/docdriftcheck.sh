#!/usr/bin/env bash
# docdriftcheck.sh — the gate for --doc-drift, the doc-anchor verifier (src/docdrift.h).
#
#   test/docdriftcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/docdriftcheck.sh
#
# The fixture test/docdriftfix/ is a half-stale design note (NOTES.md) over a two-header corpus. Every
# anchor in it is labelled with the verdict the verb must reach, so ONE run proves both directions:
#
#   TRUE POSITIVES (must be reported)                TRUE NEGATIVES (must NOT be reported)
#     code.h:23 named stableHelper  -> line-moved      code.h:18 named stableHelper  (holds)
#     code.h:900                    -> past-eof        `stableHelper`                (still defined)
#     deletedFile.h:12              -> missing-file    `kHoldingLimit` = 7           (value agrees)
#     `deletedHelper`               -> undefined       `kHoldingTable[4]`            (extent agrees)
#     `kDriftedLimit` = 10          -> const-value     `phantomHelper`               (uncorroborated)
#     `kDriftedTable[16]`           -> array-extent    `otherProject::vanishedThing` (foreign scope)
#     a bare [16] beside that name  -> array-extent    anything inside a ``` fence   (illustration)
#
# Four more docs pin the DATED-RECORD lane — which failed anchors the AUTHOR dated, so they count in dated=
# rather than drift=. Each fires one rec= kind, and two of them are negative controls:
#
#   FIRES (kind="dated-record")                      ABSTAINS (must stay LIVE, in drift=)
#     RECORD_2026-01-15.md    -> rec="title"           live_notes.md "Last updated: 2026-01-15" (liveness)
#     record_stamp.md **Date:** -> rec="stamp"         live_notes.md "the 2026-01-15 migration" (talked about)
#     its "## §Status — DATE"   -> rec="block"         live_notes.md "## Status (opened DATE)"  (inception)
#     record_line.md hedge/as-of/log row -> rec="line" record_line.md's one unhedged sentence
#     …and NOTES.md itself is undated, so all 7 of its rows stay LIVE
#
# …plus the two honesty invariants the verb's whole claim rests on: checked + unchecked == anchors, with
# every declined check named in an <unchecked> row; and drift + dated == every anchor that failed, so a
# record is re-bucketed, never dropped.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/docdriftfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "docdriftcheck: BIN=$BIN  CORPUS=$CORPUS"

"$BIN" "$CORPUS" --doc-drift --no-cache >"$TMP/a" 2>/dev/null
rc=$?
"$BIN" "$CORPUS" --doc-drift --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" && ok "determinism (byte-identical)" || no "--doc-drift is non-deterministic"
[ "$rc" = "0" ] && ok "exits 0 (a report, not a gate)" || no "--doc-drift exited $rc, expected 0"
F="$( cat "$TMP/a" )"

# rows: one <a .../> element per line, so grep can assert on whole rows
rows(){ printf '%s' "$F" | tr '<' '\n' | grep '^a k='; }
attr(){ printf '%s' "$F" | sed -n "s/.*<doc-drift[^>]* $1=\"\([^\"]*\)\".*/\1/p"; }
# the rows of ONE doc element, so a per-doc assertion cannot be satisfied by another doc's row
docrows(){ printf '%s' "$F" | tr '<' '\n' | sed -n "/^doc p=\"$1\"/,/^\/doc/p" | grep '^a k='; }
# the <w .../> disclosure rows of ONE weak-file-line group — a SIBLING section to <doc>, not nested in it
# (F5: a doc can carry these while staying clean, so they must never live inside the drift-gated <doc> loop)
weakrows(){ printf '%s' "$F" | tr '<' '\n' | sed -n "/^weak-file-line p=\"$1\"/,/^\/weak-file-line/p" | grep '^w l='; }

# ── 1) file:line — the three failure modes, each named separately ─────────────────────────────────────
rows | grep -q 'k="file-line" .*why="line-moved" ref="code.h:23" sym="stableHelper" got="movedHelper"' \
    && ok "line-moved: code.h:23 is no longer stableHelper, and got= names the squatter" \
    || { no "line-moved row missing/wrong"; rows | grep 'line-moved'; }

rows | grep -q 'why="past-eof" ref="code.h:900"' \
    && ok "past-eof: code.h:900 is past the end of a 28-line file" || no "past-eof row missing"

rows | grep -q 'why="missing-file" ref="deletedFile.h:12"' \
    && ok "missing-file: deletedFile.h is gone from the tree" || no "missing-file row missing"

# The holding anchor is INSIDE stableHelper — reporting it would be the cry-wolf failure.
rows | grep -q 'ref="code.h:18"' && no "code.h:18 reported, but that line IS inside stableHelper" \
                                 || ok "code.h:18 (inside stableHelper) is silent — true negative"

# ── 1b) F5: weak-file-line resolves-to= disclosure, and the path:A-B range-straddle check ───────────────
# resolves-to= is a FACT (which symbol the free innermost-at-line resolution names), never a verdict — the
# verb still declines to check whether it is the symbol the doc meant, so this lives OUTSIDE <doc> (§1c below).
weakrows 'NOTES.md' | grep -q 'l="41" c="71" ref="code.h:19" resolves-to="stableHelper"' \
    && ok "weak-file-line resolves-to=: code.h:19 (no symbol named) resolves to stableHelper" \
    || { no "weak-file-line resolves-to= row missing/wrong"; weakrows 'NOTES.md'; }

rows | grep -q 'k="file-line" .*why="range-straddles" ref="code.h:18-23" got="movedHelper" tgt="code.h:23"' \
    && ok "range-straddles: code.h:18-23 starts in stableHelper and ends in movedHelper" \
    || { no "range-straddles row missing/wrong"; rows | grep 'range-straddles'; }

rows | grep -q 'code.h:22-24' && no "code.h:22-24 flagged, but the whole range sits inside movedHelper" \
                              || ok "code.h:22-24 (healthy in-range span) is silent — true negative"

# ── 1c) the weak-file-line disclosure is a SIBLING of <doc>, independent of clean= ───────────────────────
printf '%s' "$F" | grep -q '<weak-file-line p="NOTES.md" n="1">' \
    && ok "<weak-file-line p= n=> groups by doc, one row here (n=\"1\")" || no "the weak-file-line group for NOTES.md is missing"
printf '%s' "$F" | grep -qE '<doc p="NOTES\.md"[^>]*drift="[0-9]+"' \
    && ok "NOTES.md's <doc> row is untouched by the disclosure section (same element, same attributes)" \
    || no "NOTES.md's <doc> row changed shape"

# ── 2) symbol mentions ────────────────────────────────────────────────────────────────────────────────
rows | grep -q 'k="symbol" .*why="undefined" ref="deletedHelper"' \
    && ok "undefined: deletedHelper is gone and the mention sits beside a live name" || no "undefined row missing"

rows | grep -q 'ref="stableHelper"' && no "stableHelper reported, but it is still defined" \
                                    || ok "stableHelper mention is silent — true negative"
rows | grep -q 'phantomHelper' && no "phantomHelper reported despite having no live name on its line" \
                               || ok "uncorroborated mention is silent — true negative"
rows | grep -q 'vanishedThing' && no "a foreign-scope name (otherProject::) reported as our drift" \
                               || ok "foreign-scope mention is silent — true negative"

# ── 3) constants and extents — the field-notes headline cases ─────────────────────────────────────────
rows | grep -q 'k="const" .*why="const-value" .*want="10" got="15" tgt="code.h:11"' \
    && ok "const-value: the doc says 10, code.h:11 says 15 (site in tgt=, not at=)" || { no "const-value row missing/wrong"; rows | grep 'k="const"'; }

rows | grep -q 'k="array" .*ref="kDriftedTable\[16\]" want="16" got="18" tgt="code.h:14"' \
    && ok "array-extent: the doc says [16], code.h:14 declares [18]" || { no "array-extent row missing/wrong"; rows | grep 'k="array"'; }

rows | grep -q 'k="array" .*ref="\[16\]" want="16" got="18"' \
    && ok "array-extent (bare [16] beside a named array) also caught" || no "the bare [N] form was not recognised"

rows | grep -q 'kHoldingLimit' && no "kHoldingLimit = 7 reported, but the code agrees" \
                               || ok "kHoldingLimit = 7 is silent — true negative"
rows | grep -q 'kHoldingTable' && no "kHoldingTable[4] reported, but the code agrees" \
                               || ok "kHoldingTable[4] is silent — true negative"

# ── 4) fenced examples are illustrations, never claims ────────────────────────────────────────────────
rows | grep -q 'code.h:999' && no "a file:line inside a fenced block was reported as an anchor" \
                            || ok "file:line inside a fence is silent — true negative"
rows | grep -q 'ghostSymbol' && no "a symbol mention inside a fenced block was reported" \
                             || ok "symbol mention inside a fence is silent — true negative"

# ── 5) honesty: nothing is dropped, and every declined check is named ─────────────────────────────────
A="$( attr anchors )"; C="$( attr checked )"; U="$( attr unchecked )"; D="$( attr drift )"; P="$( attr prose )"
T="$( attr dated )"
[ -n "$A" ] && [ "$(( C + U ))" = "$A" ] \
    && ok "checked($C) + unchecked($U) == anchors($A) — nothing dropped silently" \
    || no "the honesty invariant broke: checked=$C unchecked=$U anchors=$A"
[ "$D" = "11" ] && ok "drift=11 — the seven labelled true positives, the range-straddle row, plus the three undated record-lane rows" \
                || no "drift=$D, expected 11"
[ "$P" = "1" ] && ok "prose=1 — 'absent_from_all_code = 42' counted as prose, not claimed as an anchor" \
               || no "prose=$P, expected 1"

# NOTES.md carries no date anywhere, so the record lane must leave every one of its rows alone. This is the
# assertion that pins the SPLIT as behaviour-preserving for an undated doc: eight rows (the original seven
# plus the range-straddle row F5 added), none re-bucketed.
[ "$( docrows 'NOTES.md' | grep -c . )" = "8" ] && ok "NOTES.md still reports exactly its eight rows" \
                                                || no "NOTES.md row count changed: $( docrows 'NOTES.md' | grep -c . )"
docrows 'NOTES.md' | grep -q 'dated-record' && no "an undated doc's rows were filed as dated records" \
                                            || ok "NOTES.md is undated, so all seven rows stay LIVE in drift="

for r in named-elsewhere not-indexed not-a-definition foreign-scope uncorroborated; do
    printf '%s' "$F" | grep -q "<unchecked r=\"$r\"" \
        && ok "unchecked reason '$r' is reported with its note" || no "unchecked reason '$r' never fired"
done
printf '%s' "$F" | grep -q '<unchecked r="not-indexed"[^>]*note="[^"]\+"' \
    && ok "every unchecked row carries a human-readable note" || no "an unchecked row shipped without a note"

# ── 5b) the DATED-RECORD lane: it fires on each dating mark, and abstains on each look-alike ──────────
# The abstain half matters more than the fire half: a false record hides real rot, which is the one failure
# this lane must not have. So every negative control below is asserted by NAME, not by a total.
[ "$T" = "6" ] && ok "dated=6 — one title, one stamp, one block and three line records" || no "dated=$T, expected 6"

TOTALROWS="$( rows | grep -c . )"
[ "$TOTALROWS" = "$(( D + T ))" ] \
    && ok "drift($D) + dated($T) == every reported row ($TOTALROWS) — a record is re-bucketed, never dropped" \
    || no "drift+dated ($(( D + T ))) disagrees with the $TOTALROWS rows actually emitted"

docrows 'RECORD_2026-01-15.md' | grep -q 'kind="dated-record" rec="title"' \
    && ok "rec=title: an ISO date in the FILENAME makes the doc an artifact of that day" || no "rec=title never fired"
docrows 'record_stamp.md' | grep -q 'rec="stamp" ref="code.h:900"' \
    && ok "rec=stamp: a labelled front-matter self-date ('**Date:** …') dates the document" || no "rec=stamp never fired"
docrows 'record_stamp.md' | grep -q 'rec="block" ref="code.h:901"' \
    && ok "rec=block: a dated heading outranks the doc's own stamp (most specific evidence wins)" || no "rec=block never fired"
for r in 902 903 904; do
    docrows 'record_line.md' | grep -q "rec=\"line\" ref=\"code.h:$r\"" \
        && ok "rec=line: code.h:$r is dated by its own line (hedge / as-of / log row)" || no "rec=line missed code.h:$r"
done

# NEGATIVE CONTROLS — each of these is a date that must NOT date the document.
docrows 'record_line.md' | grep 'ref="code.h:905"' | grep -q 'dated-record' \
    && no "an unhedged sentence in an undated doc was called a record" \
    || ok "the one unhedged line in record_line.md stays LIVE — the lane is per-LINE, not per-doc"
docrows 'live_notes.md' | grep -q 'dated-record' \
    && no "live_notes.md was dated by a liveness stamp / a talked-about date / an inception heading" \
    || ok "live_notes.md abstains: 'Last updated:', 'after the … migration' and '(opened …)' are not records"
[ "$( docrows 'live_notes.md' | grep -c . )" = "2" ] \
    && ok "…and both of live_notes.md's stale anchors are still REPORTED, in drift=" \
    || no "live_notes.md lost a row: $( docrows 'live_notes.md' | grep -c . )"

for r in line block title stamp; do
    printf '%s' "$F" | grep -q "<dated r=\"$r\"[^>]*note=\"[^\"]\+\"" \
        && ok "<dated r=\"$r\"> is tallied with its note" || no "the dated tally row '$r' is missing or has no note"
done
printf '%s' "$F" | grep -q '<dated r="live"' && no "Record::Live emitted a tally row — it is the absence of evidence" \
                                             || ok "no <dated r=\"live\"> row (absence of a mark is not a kind)"

# ── 6) well-formed, minified XML (G4) ─────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/a" 2>/dev/null && ok "XML well-formed" || no "XML malformed"
else
    ok "xmllint unavailable — well-formedness skipped"
fi
[ "$( grep -c '' "$TMP/a" )" -le 1 ] && ok "output is minified (no stray newlines)" || no "output contains newlines outside CDATA"

# ── 7) --doc-drift=SUBSTR filters the DOCS, and a miss REFUSES rather than reporting a clean zero ──────
# F-04: docs="0" drift="0" under a typo'd filter used to read as "no rot" (exit 0) — the same trap
# --scope and --dead-code=DIR already refuse for their own filters. A filter naming NOTHING refuses
# loudly (exit 1, naming the filter) instead; the flagless/empty-filter case (§8 below) is untouched.
"$BIN" "$CORPUS" --doc-drift=NOTES --no-cache 2>/dev/null | grep -q 'docs="1"' \
    && ok "--doc-drift=SUBSTR keeps the matching doc" || no "--doc-drift=SUBSTR dropped the matching doc"
OUT=$( "$BIN" "$CORPUS" --doc-drift=no-such-doc --no-cache 2>"$TMP/nomatch.err" ); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 1 ] \
    && ok "--doc-drift=SUBSTR with no match refuses (exit 1, no stdout) rather than reporting docs=0" \
    || no "a non-matching filter did not refuse (rc=$RC, stdout=$OUT)"
grep -q 'no-such-doc' "$TMP/nomatch.err" && grep -q 'matches no document' "$TMP/nomatch.err" \
    && ok "the refusal names the filter and the reason" \
    || no "the refusal did not name the filter/reason: $( cat "$TMP/nomatch.err" )"

# ── 8) a doc-free corpus is a clean empty report, not a crash ─────────────────────────────────────────
mkdir -p "$TMP/bare"; printf 'int main(){return 0;}\n' > "$TMP/bare/m.cpp"
"$BIN" "$TMP/bare" --doc-drift --no-cache 2>/dev/null | grep -q 'docs="0" clean="0" anchors="0"' \
    && ok "a doc-free corpus reports docs=0 anchors=0 and exits clean" || no "doc-free corpus did not report an empty scan"

# ── 8b) §P11.10: docs are ordered by LIVE drift, worst first ──────────────────────────────────────────
#
# The finding: --doc-drift opened with two screens of drift="0" rows before the first actionable doc.
# Rows were path-ordered, and this repo's alphabetically-early docs are
# audit ledgers whose every failed anchor is a DATED record — so they carry drift="0" and led anyway,
# while the worst live rot (drift="14") sat far below the fold.
#
# Ordering only: live drift DESC, path ASC to break ties. The dated-record rows need no separate demotion
# rule and get none — a fully dated doc IS drift="0" by construction, so it sinks on the same key that
# lifts the rot. Every row still prints; drift= / dated= / the tallies are untouched (§9's golden pins
# that, and it was regenerated only after confirming the doc blocks are a pure PERMUTATION and the root
# counters byte-identical).
#
# On this fixture path order and drift order differ: RECORD_2026-01-15.md (drift 0, fully dated) sorts
# second alphabetically but must sink below live_notes.md (2) and record_line.md (1).
DRIFTSEQ="$( printf '%s' "$F" | tr '<' '\n' | sed -n 's/^doc p="\([^"]*\)".* drift="\([0-9]*\)".*/\2 \1/p' )"

firstDoc="$( printf '%s\n' "$DRIFTSEQ" | head -1 )"
[ "${firstDoc%% *}" = "$( printf '%s\n' "$DRIFTSEQ" | awk '{print $1}' | sort -rn | head -1 )" ] \
    && ok "§P11.10: the first doc row carries the MAXIMUM drift ($firstDoc)" \
    || { no "§P11.10: first doc row is '$firstDoc', not the max drift"; printf '%s\n' "$DRIFTSEQ"; }

# the general contract: drift= is non-increasing down the list, path ascending inside a tie
prevD=""; prevP=""; seqbad=0
while IFS=' ' read -r d p; do
    [ -z "$d" ] && continue
    if [ -n "$prevD" ]; then
        if [ "$d" -gt "$prevD" ]; then seqbad=1; break; fi
        if [ "$d" = "$prevD" ] && [ "$p" \< "$prevP" ]; then seqbad=1; break; fi
    fi
    prevD="$d"; prevP="$p"
done <<EOF
$DRIFTSEQ
EOF
[ "$seqbad" = 0 ] \
    && ok "§P11.10: doc rows non-increasing by drift=, path ascending within a tie" \
    || { no "§P11.10: doc row order violates (drift desc, path asc)"; printf '%s\n' "$DRIFTSEQ"; }

# the dated-record docs sink on the SAME key — no separate rule, and no row is lost doing it
datedPos="$( printf '%s\n' "$DRIFTSEQ" | grep -n 'RECORD_2026-01-15\.md$' | cut -d: -f1 )"
livePos="$(  printf '%s\n' "$DRIFTSEQ" | grep -n 'live_notes\.md$'        | cut -d: -f1 )"
{ [ -n "$datedPos" ] && [ -n "$livePos" ] && [ "$datedPos" -gt "$livePos" ]; } \
    && ok "§P11.10: the fully dated drift=0 doc sorts below the live-rot doc (row $datedPos vs $livePos)" \
    || { no "§P11.10: dated doc at row '$datedPos', live doc at row '$livePos'"; printf '%s\n' "$DRIFTSEQ"; }

[ "$( printf '%s\n' "$DRIFTSEQ" | grep -c . )" = "5" ] \
    && ok "§P11.10: all 5 fixture doc rows still emitted (ordering drops nothing)" \
    || no "§P11.10: $( printf '%s\n' "$DRIFTSEQ" | grep -c . ) doc rows emitted, expected 5"

# The finding's own repro. The fixture's worst doc (NOTES.md) also happens to sort first alphabetically,
# so the "max drift leads" arm above cannot fail there — this repo is where the two orders genuinely
# disagree, and where the finding was measured (drift="0", used to lead).
"$BIN" "$ROOT" --doc-drift >"$TMP/repo" 2>/dev/null
REPOSEQ="$( tr '<' '\n' <"$TMP/repo" | sed -n 's/^doc p="\([^"]*\)".* drift="\([0-9]*\)".*/\2 \1/p' )"
if [ -n "$REPOSEQ" ]; then
    repoFirst="$( printf '%s\n' "$REPOSEQ" | head -1 )"
    repoMax="$(   printf '%s\n' "$REPOSEQ" | awk '{print $1}' | sort -rn | head -1 )"
    { [ "${repoFirst%% *}" = "$repoMax" ] && [ "$repoMax" -gt 0 ]; } \
        && ok "§P11.10(repo): the first doc row carries the max drift ($repoFirst), not a drift-zero ledger" \
        || { no "§P11.10(repo): first row '$repoFirst' but max drift is $repoMax"; printf '%s\n' "$REPOSEQ" | head -6; }
else
    ok "§P11.10(repo): no drifting docs in this checkout — repro arm skipped"
fi

# ── 9) GOLDEN OUTPUT — the whole report, byte for byte ────────────────────────────────────────────────
# The assertions above name the verdicts this verb must reach; this one pins everything they do NOT name —
# every column of every row, the unchecked tallies, the attribute order. This verb's precision was won by
# cutting a naive 329 findings to 119 with seven hand-validated rules, and the failure mode of a refactor
# there is SILENT: the output still looks plausible with a rule quietly inverted. So the reference is the
# bytes, not a summary of them.
#
# The golden lives OUTSIDE test/docdriftfix/ on purpose — a file inside the fixture would join the corpus
# and move the very counts it exists to pin.
#
# Regenerating is a DELIBERATE act, never a reflex to a red gate: confirm the diff is a change you meant,
# then  ./build/ripwire test/docdriftfix --doc-drift --no-cache > test/docdriftfix.golden.xml
#
# r26-stamp Task A: the root <doc-drift> element now carries at="<sha>[+dirty]" — a stamp of the ENCLOSING
# ripwire checkout's own HEAD (test/docdriftfix is a plain directory, not its own repo, so git walks up to
# THIS repo's .git), which by design changes on every commit to this tree. A byte-for-byte golden that
# embedded it would break on the next unrelated commit, for a reason that has nothing to do with doc-drift
# itself. Both sides of the comparison are normalized to strip JUST the root element's at= (never the
# per-anchor `tgt="path:line"` attribute writeAnchor emits — a blanket strip would silently blind
# this golden to a real regression there) before the byte-compare. r27 P2 item 7: the per-anchor site
# attribute is now tgt=, so at= appears on the root element ONLY and the normalization is unambiguous.
NORM_AT='s/(<doc-drift[^>]*) at="[^"]*"/\1/'
GOLDEN="$ROOT/test/docdriftfix.golden.xml"
if [ -f "$GOLDEN" ]; then
    sed -E "$NORM_AT" "$TMP/a"   > "$TMP/a.norm"
    sed -E "$NORM_AT" "$GOLDEN" > "$TMP/golden.norm"
    cmp -s "$TMP/a.norm" "$TMP/golden.norm" \
        && ok "golden: --doc-drift on the fixture is byte-identical to test/docdriftfix.golden.xml (at= normalized out)" \
        || no "golden MISMATCH — --doc-drift's output changed: $( cmp "$TMP/a.norm" "$TMP/golden.norm" 2>&1 | head -1 )"
else
    no "the golden capture test/docdriftfix.golden.xml is missing (regenerate it — see the note above)"
fi

[ $fail -eq 0 ] && echo "docdriftcheck: ALL PASS" || echo "docdriftcheck: FAILURES"
exit $fail
