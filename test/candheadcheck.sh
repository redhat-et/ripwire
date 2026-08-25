#!/usr/bin/env bash
# candheadcheck.sh — the candidate-head bound: restrict the auto-body candidate surface to the route's
# anchor BEFORE taking the top-K head, not after (candhead-ugrep lane, N08, 2026-08-25).
#
#   test/candheadcheck.sh                            # uses build/ripwire on test/candheadfix
#   RIPWIRE_BIN=asan/ripwire test/candheadcheck.sh
#
# THE DEFECT THIS PINS (docs/EVALS.md, "N08 — the candidate-head bound"; upstream: the anchor-body and
# def-over-decl lane reports, both naming it and leaving it for "the next round"). main.cpp's
# buildForAutoBodies takes the top-kPackTaskBodyCandidates (6) positive-score rows of the WHOLE ranked
# surface FIRST, and only THEN calls restrictBodiesToRouteAnchor to narrow that already-capped six down
# to the route's anchor file. When the anchor resolves correctly but unrelated same-named symbols
# elsewhere in the corpus outscore it — measured on rocksdb: --for="Slice" anchors correctly to
# include/rocksdb/slice.h, but seven Slice.java rows (a different file, a different language) fill the
# whole pre-restriction top-6 first — restriction then narrows an ALREADY-EMPTY-of-anchor-matches set to
# nothing: bodies="0" reason="no_candidates", even though the caller's own anchor was resolved correctly.
#
# THE SCORE GAP, reproduced deliberately rather than assumed: BM25's length-normalization term counts a
# symbol WITH a written scope (a class's own constructor, "Frobnicator::Frobnicator") as a two-token "document"
# against the whole-name scorer, while an UNSCOPED free function ("Frobnicator") scores as one token and wins
# the length penalty — real and measured, not a synthetic tie. test/candheadfix/b_pollutants.hpp is
# seven overloads of a free function Frobnicator(), each unscoped and each outscoring a_gold.hpp's class
# Frobnicator (whose constructor carries the written scope "Frobnicator"); seven is one past
# kPackTaskBodyCandidates = 6, so the pollutants fill the WHOLE pre-restriction head.
#
# THE FIX: main.cpp's buildForAutoBodies restricts the FULL positive-score surface to the anchor's own
# file first, THEN takes the top-K of what remains — a pure REORDER of two already-existing calls
# (restrictBodiesToRouteAnchor, isRouteAnchorSymbol), no new rule, no scoring change, no anchor-selection
# change. A no-anchor route (anchorDefs empty) takes the unrestricted head exactly as before.
#
# ARMS
#   (a) RED-FIRST — --for=Frobnicator: the anchor resolves to a_gold.hpp (rank 8/9 in the raw candidate
#       list, past the 6-cap) but bodies="0" before the fix; the fix serves the gold's own cls+fn.
#   (b) THE POLLUTANTS SURVIVE IN <sigs> — the seven unscoped Frobnicator overloads are still ranked ahead
#       of the gold in the SIGNATURE rows; this fix touches body SELECTION only, never ranking.
#   (c) THE ANCHOR ITSELF DOES NOT MOVE — anchors: Frobnicator(.../a_gold.hpp+8) is byte-identical before
#       and after. A rule that changed anchor selection to "fix" this would be the wrong mechanism.
#   (d) NO-ANCHOR CONTROL — a query naming no symbol at all (routes subtoken+body, anchorDefs empty)
#       is untouched: this fix's restrict-then-cap branch never executes there.
#   (e) UNIQUE-DEFINITION INVARIANCE — Gadget, declared once, nothing competing for its anchor or its
#       candidate head: byte-identical bundle before and after. The registered invariance criterion.
#   (f) ROUTE SCOPE — --for=Frobnicator takes the name-exact route (sanity for the arms above).
#   (g) determinism — two runs byte-identical.
#
# The fixture is copied to a tmp dir OUTSIDE any git repo and scanned via a RELATIVE path, so no churn
# or co-change attribute and no absolute path can reach the assertions.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "candheadcheck: BIN=$BIN"

mkdir -p "$TMP/candheadfix"
cp "$ROOT"/test/candheadfix/*.hpp "$TMP/candheadfix/"
cd "$TMP"

# ── (a) RED-FIRST: the anchor is correct but the gold's body is served ──────────────────────────────
"$BIN" candheadfix --for=Frobnicator >"$TMP/lens" 2>/dev/null
anchor="$( sed -n 's/.*anchors: Frobnicator(\([^)]*\)).*/\1/p' "$TMP/lens" | head -1 )"
[ "$anchor" = "candheadfix/a_gold.hpp+8" ] \
    && ok "the anchor resolves to a_gold.hpp (anchors: Frobnicator($anchor))" \
    || no "anchors: Frobnicator($anchor) — expected candheadfix/a_gold.hpp+8"

bodykinds="$( tr '>' '\n' <"$TMP/lens" | sed -n 's/.*<b t="\([^"]*\)" l="\([0-9]*\)" p="\([^"]*\)".*/\1:\2:\3/p' | sed 's#candheadfix/##' | sort )"
want='cls:28:a_gold.hpp
fn:31:a_gold.hpp'
if [ "$bodykinds" = "$want" ]; then
    ok "the gold's own class + constructor are served in <bodies>"
else
    no "<bodies> does not carry the gold — got:"
    printf '%s\n' "$bodykinds"
fi

# ── (b) THE POLLUTANTS SURVIVE IN <sigs> — reorder, not filter ──────────────────────────────────────
# 9 = the seven pollutant overloads plus the gold's own class + constructor rows; the file-grouping <f
# p="…"> wrapper prints its path ONCE per file, so counting <d n="Frobnicator"> rows (not p="…" occurrences)
# is what actually counts ranked ROWS.
rowcount="$( tr '>' '\n' <"$TMP/lens" | grep -c '<d l="[0-9]*" n="Frobnicator"' )"
[ "$rowcount" = "9" ] \
    && ok "all nine Frobnicator rows (7 pollutants + the gold's cls+fn) still appear ranked — reorder, not a filter" \
    || no "expected 9 Frobnicator rows in <sigs>, got $rowcount"

# ── (c) THE ANCHOR ITSELF DOES NOT MOVE — checked again as its own arm, byte-value pinned ───────────
[ "$anchor" = "candheadfix/a_gold.hpp+8" ] \
    && ok "anchor selection is unchanged by this fix (restated, see (a))" \
    || no "anchor selection moved — this fix must not touch it"

# ── (d) NO-ANCHOR CONTROL ────────────────────────────────────────────────────────────────────────────
CQ="a widget with an unrelated made up made up conceptual phrase nothing names"
"$BIN" candheadfix --for="$CQ" >"$TMP/noanchor" 2>/dev/null
if grep -q 'anchors:' "$TMP/noanchor"; then
    no "the no-anchor control query unexpectedly resolved an anchor — arm (d) is not testing the empty-anchorDefs branch"
else
    ok "a query naming no symbol carries no anchor — the restrict-then-cap branch never executes here"
fi

# ── (e) UNIQUE-DEFINITION INVARIANCE ─────────────────────────────────────────────────────────────────
# Gadget's only two candidates (its class and its own constructor — "+1" is that ambiguity, not a
# competing symbol) both fit comfortably under kPackTaskBodyCandidates = 6, so nothing about this rule
# can reach it regardless of order; anchor and body must be byte-stable before and after.
"$BIN" candheadfix --for=Gadget >"$TMP/gad" 2>/dev/null
gadan="$( sed -n 's/.*anchors: Gadget(\([^)]*\)).*/\1/p' "$TMP/gad" | head -1 )"
gadbody="$( tr '>' '\n' <"$TMP/gad" | sed -n 's/.*<b t="\([^"]*\)" l="\([0-9]*\)" p="\([^"]*\)".*/\1:\2/p' | sed 's#candheadfix/##' | sort )"
gadwant='cls:37
fn:40'
if [ "$gadan" = "candheadfix/a_gold.hpp+1" ] && [ "$gadbody" = "$gadwant" ]; then
    ok "a unique definition's anchor and both bodies are byte-stable (Gadget: $gadan)"
else
    no "--for=Gadget moved: anchor=$gadan — expected candheadfix/a_gold.hpp+1; bodies:"
    printf '%s\n' "$gadbody"
fi

# ── (f) ROUTE SCOPE ───────────────────────────────────────────────────────────────────────────────────
grep -q 'routed: name-exact' "$TMP/lens" \
    && ok "--for=Frobnicator takes the name-exact route (the route this fix's arms measure)" \
    || no "--for=Frobnicator no longer routes name-exact"

# ── (g) determinism ───────────────────────────────────────────────────────────────────────────────────
"$BIN" candheadfix --for=Frobnicator >"$TMP/d1" 2>/dev/null
"$BIN" candheadfix --for=Frobnicator >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" \
    && ok "deterministic: two --for=Frobnicator runs byte-identical" \
    || no "two --for=Frobnicator runs differ"

[ "$fail" -eq 0 ] && echo "candheadcheck: ALL PASS" || echo "candheadcheck: FAILURES"
exit "$fail"
