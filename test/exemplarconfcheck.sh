#!/usr/bin/env bash
# exemplarconfcheck.sh — §P5 gate: --exemplar's low_confidence signal must actually FIRE and must fire
# ONLY when the task→kind donation is untrustworthy (src/exemplar.h: resolveExemplarKind, INVARIANT 3).
#
#   test/exemplarconfcheck.sh                       # uses build/ripwire on the ripwire repo itself
#   RIPWIRE_BIN=asan/ripwire test/exemplarconfcheck.sh
#
# Regression for the reported defect: --exemplar="format byte sizes for humans" returned fnv1a64 (a hash
# fn, unrelated to the task) with NO low_confidence flag — a no-topical-match answer indistinguishable from
# a good one. The pre-fix check inspected only the single #1-scoring lexical hit's name, which is fooled in
# BOTH directions: a generic word shared with an unrelated #1 hit reads as confident (false negative), while
# a genuine topical cluster that merely lost the #1 slot to one such outlier reads as unmatched (false
# positive — "parse command line arguments" flagged low_confidence pre-fix despite a real parse* cluster).
# The fix (src/exemplar.h: kExemplarConfWindow/kExemplarConfMinShare) checks what fraction of the top-K
# lexical hits corroborate the match by name, not just the #1 hit.
#
# This gate does NOT touch selection (the ROLE-based composite winner, e.g. fnv1a64 for kind=fn repo-wide,
# is unchanged and out of scope per §P5) — only the confidence SIGNAL attached to the kind-donation step.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "exemplarconfcheck: BIN=$BIN  CORPUS=$ROOT"

exemhdr(){ printf '%s' "$1" | grep -o '<exemplar[^>]*>' | head -1; }

# ── 1) a task with NO topical match anywhere in this repo MUST emit low_confidence="1" ────────────────────
# The originally-reported false-negative: fnv1a64 (a hash fn) is not a "format bytes for humans" exemplar,
# and the pre-fix signal never said so.
WEAK="$( "$BIN" "$ROOT" --no-cache --exemplar="format byte sizes for humans" 2>/dev/null )"
WHDR="$( exemhdr "$WEAK" )"
printf '%s' "$WHDR" | grep -q 'low_confidence="1"' \
    && ok "weak query (byte-size formatting) fires low_confidence=1: $WHDR" \
    || no "weak query (byte-size formatting) did NOT fire low_confidence: $WHDR"

# ── 2) a clearly-matched task MUST NOT emit low_confidence ─────────────────────────────────────────────────
# Verified independently (against --for and manual corpus inspection) that this repo genuinely has a parse*
# cluster (parseGeneric/parseHeaderLine/parseMinedLine/parsePython/parseCorpus/parseNode/...) before pinning
# this as a "strong match" assertion — this is the reported false-positive direction of the same bug.
# QUERY REWORDED 2026-08-12 (module-constant and installer rounds): the original "parse command line arguments" is quoted
# VERBATIM in src/exemplar.h's own comments, and once const-qualified module constants became indexed
# symbols (kParserVer 62), the constant carrying that comment (kExemplarConfWindow) became the top lexical
# hit and donated kind=var — a self-referential corpus artifact, not a donation bug. Arm 3's differential
# claim needs three queries that donate the SAME kind, so the query keeps its meaning (the same argv-parse
# cluster) but no longer matches its own gate's quotation. The v0.3.6 installer tests added enough argv/config
# vocabulary to make the intermediate wording donate kind=var; this phrasing still targets the same parser
# cluster and donates kind=fn, which keeps Arm 3's differential premise honest.
#
# QUERY REPLACED 2026-08-19 (subtoken acronym round, kParserVer 66) — and this time the reason is not a
# corpus artifact but a MEASURED ranker improvement, so the replacement is chosen for ROBUSTNESS, not just
# for meaning. The argv wording sat at share=0.50 — exactly ONE symbol above the strict `> 0.4` cut on a
# 10-sample proportion. That one symbol was `AmbientOptions`, a TypeScript test fixture
# (test/tsshapefix/limits.d.ts, `export interface AmbientOptions { width?: number }`) which "corroborated"
# only because its NAME carries the subtoken `options`. Once acronyms stopped being shredded, its
# doc-comment's shouted words (KNOWN LIMIT / CONTAINER / CONTENTS) began counting toward its BM25 document
# length instead of being silently dropped, it lost the phantom length discount that had inflated it
# (11.1936 -> 10.6999, -4.41%, 12.8x the -0.04 ambient drift), and it left the window — taking the arm's
# only spare corroborator with it. Instrumented dumps, same corpus, both binaries:
#
#   query                          pre-fix        post-fix
#   read command line options      0.50 trust=1   0.40 trust=0   <- one spurious symbol above the cut
#   compute pagerank               0.80 trust=1   0.80 trust=1   <- robust, kept as STRONG2 below
#   format byte sizes for humans   0.30 trust=0   0.20 trust=0   <- the WEAK arm got MORE clearly weak
#   compute the churn of a file    0.60 trust=1   0.60 trust=1   <- the replacement: 2 samples of margin
#
# The weak/strong separation WIDENED (0.30/0.80 -> 0.20/0.80), so the confidence signal did not degrade —
# a knife-edge instance of "strong" stopped qualifying. Candidates measured and rejected, recorded so the
# choice is auditable rather than a hunt for green: "expand a symbol body" (0.60 but donates cls, breaks
# Arm 3), "parse a source file into symbols" (donates cls pre / var post — kind not even stable),
# "rank the graph with pagerank" (0.90 but donates var), "find the callers of a symbol" (0.30, not
# trustworthy on EITHER binary), "resolve a reference to its definition" (0.40, on the cut),
# "rank symbols by lexical score" (0.40, on the cut), "detect clone groups in the corpus" (0.60 -> 0.50,
# drifts). The churn wording is stable at 0.60 on both binaries, donates kind=fn, and is quoted nowhere in
# src/ — so it cannot repeat the self-referential trap the 2026-08-12 note above describes.
STRONG1="$( "$BIN" "$ROOT" --no-cache --exemplar="compute the churn of a file" 2>/dev/null )"
SHDR1="$( exemhdr "$STRONG1" )"
printf '%s' "$SHDR1" | grep -q 'low_confidence' \
    && no "strong query (file churn) wrongly fired low_confidence: $SHDR1" \
    || ok "strong query (file churn) does not fire low_confidence: $SHDR1"

# a second independent strong query (a dense literal "compute" cluster in this repo).
STRONG2="$( "$BIN" "$ROOT" --no-cache --exemplar="compute pagerank" 2>/dev/null )"
SHDR2="$( exemhdr "$STRONG2" )"
printf '%s' "$SHDR2" | grep -q 'low_confidence' \
    && no "strong query (compute pagerank) wrongly fired low_confidence: $SHDR2" \
    || ok "strong query (compute pagerank) does not fire low_confidence: $SHDR2"

# ── 3) selection itself is untouched — the ROLE-based winner is a function of (corpus, donated KIND), never ──
# of the query TEXT, proving this fix changed only the confidence signal.
#
# The claim is DIFFERENTIAL — "the same winner regardless of query" — so it is asserted differentially.
# It used to name the winner literally (`fnv1a64`), which made a claim about the corpus rather than about
# the fix: any change to what the tree contains re-scored the role and reddened a gate that was measuring
# something else entirely. Whichever symbol wins, queries must agree on it, because --exemplar chooses by
# ROLE and the role does not read the query.
#
# Re-stated 2026-09-04 (capture-audit close). The arm compared n= across all three queries UNCONDITIONALLY,
# which smuggled in a second claim: that all three queries also DONATE THE SAME KIND. Kind donation is the
# task→kind step this header describes, and it reads the query AND the corpus by design. Measured at the
# wave-1 merge: "compute pagerank" donates kind="var" (n="ResolvedBinary") on the merged tree with the
# ec5e3c3 binary too, and kind="fn" (n="min") with the merged binary on the ec5e3c3 tree — corpus drift
# (the 2026-09-04 legend rewording put "PageRank" into var-kind legend constants' bodies), not a selection
# change. The precise contract, stated rather than loosened: queries that donate the SAME kind= land on the
# SAME n=; and the arm must be non-vacuous — the weak query and at least one strong query must share a kind,
# otherwise it FAILS (a comparison with nothing to compare proves nothing) and a strong query is re-anchored.
kindOf(){ printf '%s' "$1" | sed -n 's/.* kind="\([^"]*\)".*/\1/p'; }
nameOf(){ printf '%s' "$1" | sed -n 's/.* n="\([^"]*\)".*/\1/p'; }
WK="$( kindOf "$WHDR" )"; WINNER="$( nameOf "$WHDR" )"
S1K="$( kindOf "$SHDR1" )"; S1N="$( nameOf "$SHDR1" )"
S2K="$( kindOf "$SHDR2" )"; S2N="$( nameOf "$SHDR2" )"
if [ -z "$WINNER" ] || [ -z "$WK" ]; then
    no "selection: could not read kind=/n= from the weak-query header: $WHDR"
else
    shared=0; agree=1
    for triple in "$S1K|$S1N|file churn" "$S2K|$S2N|compute pagerank"; do
        k="${triple%%|*}"; rest="${triple#*|}"; n="${rest%%|*}"; label="${rest#*|}"
        if [ "$k" = "$WK" ]; then
            shared=$(( shared + 1 ))
            if [ "$n" != "$WINNER" ]; then
                agree=0
                no "selection changed between same-kind queries: weak (kind=$WK) picked \"$WINNER\", '$label' picked \"$n\" — this fix must touch ONLY the confidence signal"
            fi
        else
            ok "selection: '$label' donates kind=$k (weak donated $WK) — a different role pool, not comparable by contract (kind donation reads the query and the corpus)"
        fi
    done
    if [ "$S1K" = "$S2K" ] && [ "$S1K" != "$WK" ] && [ "$S1N" != "$S2N" ]; then
        agree=0
        no "selection changed between the two same-kind strong queries (kind=$S1K): \"$S1N\" vs \"$S2N\""
    fi
    if [ "$shared" -lt 1 ]; then
        no "selection arm VACUOUS: no strong query donates the weak query's kind=$WK (file churn→$S1K, compute pagerank→$S2K) — re-anchor a strong query so the differential claim has a comparand"
    elif [ "$agree" = 1 ]; then
        ok "selection (ROLE-based winner n=\"$WINNER\" for kind=$WK) is query-independent across $shared same-kind strong quer(y/ies), as the confidence-signal fix requires"
    fi
fi

# ── 4) determinism (byte-identical run-to-run) + well-formed XML, on the query that now flags degraded ──
"$BIN" "$ROOT" --no-cache --exemplar="format byte sizes for humans" >"$TMP/w1" 2>/dev/null
"$BIN" "$ROOT" --no-cache --exemplar="format byte sizes for humans" >"$TMP/w2" 2>/dev/null
diff -q "$TMP/w1" "$TMP/w2" >/dev/null && ok "determinism (weak-query --exemplar byte-identical run-to-run)" || no "non-deterministic weak-query --exemplar output"
command -v xmllint >/dev/null 2>&1 \
    && { printf '%s' "$WEAK" | xmllint --noout - 2>/dev/null && ok "xml well-formed (weak-query --exemplar)" || no "xml malformed (weak-query --exemplar)"; } \
    || ok "xml well-formed (xmllint absent — skipped)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
