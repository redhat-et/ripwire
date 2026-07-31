#!/usr/bin/env bash
# exemplarconfcheck.sh — §P5 gate: --exemplar's low_confidence signal must actually FIRE and must fire
# ONLY when the task→kind donation is untrustworthy (src/exemplar.h: resolveExemplarKind, INVARIANT 3).
#
#   test/exemplarconfcheck.sh                       # uses build/ctxpack on the ctxpack repo itself
#   CTXPACK_BIN=asan/ctxpack test/exemplarconfcheck.sh
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
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
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
STRONG1="$( "$BIN" "$ROOT" --no-cache --exemplar="parse command line arguments" 2>/dev/null )"
SHDR1="$( exemhdr "$STRONG1" )"
printf '%s' "$SHDR1" | grep -q 'low_confidence' \
    && no "strong query (parse command line arguments) wrongly fired low_confidence: $SHDR1" \
    || ok "strong query (parse command line arguments) does not fire low_confidence: $SHDR1"

# a second independent strong query (a dense literal "compute" cluster in this repo).
STRONG2="$( "$BIN" "$ROOT" --no-cache --exemplar="compute pagerank" 2>/dev/null )"
SHDR2="$( exemhdr "$STRONG2" )"
printf '%s' "$SHDR2" | grep -q 'low_confidence' \
    && no "strong query (compute pagerank) wrongly fired low_confidence: $SHDR2" \
    || ok "strong query (compute pagerank) does not fire low_confidence: $SHDR2"

# ── 3) selection itself is untouched — both strong queries and the weak query still land on the SAME ────
# ROLE-based repo-wide kind=fn winner (fnv1a64), proving this fix changed only the confidence signal.
printf '%s' "$WHDR"  | grep -q 'n="fnv1a64"' && printf '%s' "$SHDR1" | grep -q 'n="fnv1a64"' \
    && printf '%s' "$SHDR2" | grep -q 'n="fnv1a64"' \
    && ok "selection (ROLE-based winner) is unchanged by the confidence-signal fix" \
    || no "selection changed — this fix must touch ONLY the confidence signal"

# ── 4) determinism (byte-identical run-to-run) + well-formed XML, on the query that now flags degraded ──
"$BIN" "$ROOT" --no-cache --exemplar="format byte sizes for humans" >"$TMP/w1" 2>/dev/null
"$BIN" "$ROOT" --no-cache --exemplar="format byte sizes for humans" >"$TMP/w2" 2>/dev/null
diff -q "$TMP/w1" "$TMP/w2" >/dev/null && ok "determinism (weak-query --exemplar byte-identical run-to-run)" || no "non-deterministic weak-query --exemplar output"
command -v xmllint >/dev/null 2>&1 \
    && { printf '%s' "$WEAK" | xmllint --noout - 2>/dev/null && ok "xml well-formed (weak-query --exemplar)" || no "xml malformed (weak-query --exemplar)"; } \
    || ok "xml well-formed (xmllint absent — skipped)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
