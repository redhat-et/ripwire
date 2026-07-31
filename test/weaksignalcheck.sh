#!/usr/bin/env bash
# weaksignalcheck.sh — R4 gate: the --for lens's weak-result HONESTY signal.
#
#   test/weaksignalcheck.sh                       # uses build/ripwire on test/fixture + the routecheck/
#                                                  # anchorcheck golden fixtures
#   RIPWIRE_BIN=asan/ripwire test/weaksignalcheck.sh
#
# When the --for lens's TOP-ranked match's raw lexical (BM25) score falls below
# lexical.h's kWeakLexicalScoreThreshold, the query has too little real textual evidence behind it to
# trust the ranking — the header says so with weak="1" (same insert-before-"-->" mechanism as est_tokens
# in main.cpp runForLens), so the calling agent knows to reformulate (split camelCase, add domain synonyms,
# quote an exact path/symbol) instead of trusting a plausible-looking but ungrounded top-K. This gate
# asserts:
#   * a nonsense (zero corpus overlap) query trips weak="1".
#   * a mistyped/paraphrased symbol name (the realistic "agent guessed the name" case) also trips it.
#   * the two EXISTING golden-gate strong queries — routecheck's "how does resolution work" (test/routefix)
#     and anchorcheck's "frobnicate widget cache" (test/anchorfix) — do NOT trip it (the exact GOLDEN
#     IMPACT check R4 asked for).
#   * a real strong query on this repo's own src/ does not trip it either.
#   * determinism (run twice → byte-identical) + well-formed XML.
# Mutation-tested: the weak-absence assertion is checked to actually FAIL when the threshold is crossed.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "weaksignalcheck: BIN=$BIN"

# ── 1) a nonsense query (no corpus overlap at all) trips weak="1" on this repo's own src/ ───────────────
NONSENSE="$( "$BIN" src --no-cache --for="xyzzy plugh quux flibbertigibbet" 2>/dev/null )"
printf '%s' "$NONSENSE" | grep -q 'weak="1"' \
    && ok "nonsense query trips weak=\"1\"" \
    || no "nonsense query did NOT trip weak=\"1\" (header: $( printf '%s' "$NONSENSE" | head -c 300 ))"

# ── 2) a mistyped symbol name (the realistic reformulate-me case) also trips it ─────────────────────────
TYPO="$( "$BIN" src --no-cache --for="computLensRankng" 2>/dev/null )"
printf '%s' "$TYPO" | grep -q 'weak="1"' \
    && ok "mistyped symbol name trips weak=\"1\"" \
    || no "mistyped symbol name did NOT trip weak=\"1\" (header: $( printf '%s' "$TYPO" | head -c 300 ))"

# ── 3) a real strong query on src/ does NOT trip weak="1" ────────────────────────────────────────────────
STRONG_SRC="$( "$BIN" src --no-cache --for="parse command line arguments" 2>/dev/null )"
printf '%s' "$STRONG_SRC" | grep -q 'weak=' \
    && no "strong src/ query wrongly carries a weak= attr (header: $( printf '%s' "$STRONG_SRC" | head -c 300 ))" \
    || ok "strong src/ query carries no weak= attr"

# ── 4) GOLDEN IMPACT — routecheck's own golden strong query must NOT trip weak="1" on test/routefix ─────
mkdir -p "$TMP/routefix"
cp "$ROOT"/test/routefix/*.cpp "$TMP/routefix/"
ROUTE_OUT="$( cd "$TMP" && "$BIN" routefix --no-cache --for="how does resolution work" 2>/dev/null )"
printf '%s' "$ROUTE_OUT" | grep -q 'weak=' \
    && no "routecheck golden query 'how does resolution work' wrongly trips weak= on test/routefix (header: $( printf '%s' "$ROUTE_OUT" | head -c 300 ))" \
    || ok "routecheck golden query 'how does resolution work' does NOT trip weak= (test/routefix)"

# ── 5) GOLDEN IMPACT — anchorcheck's own golden strong query must NOT trip weak="1" on test/anchorfix ───
mkdir -p "$TMP/anchorfix"
cp "$ROOT"/test/anchorfix/*.cpp "$TMP/anchorfix/"
ANCHOR_OUT="$( cd "$TMP" && "$BIN" anchorfix --no-cache --for="frobnicate widget cache" 2>/dev/null )"
printf '%s' "$ANCHOR_OUT" | grep -q 'weak=' \
    && no "anchorcheck golden query 'frobnicate widget cache' wrongly trips weak= on test/anchorfix (header: $( printf '%s' "$ANCHOR_OUT" | head -c 300 ))" \
    || ok "anchorcheck golden query 'frobnicate widget cache' does NOT trip weak= (test/anchorfix)"

# ── 6) determinism — the same nonsense query re-run gives byte-identical output (weak="1" included) ────
NONSENSE2="$( "$BIN" src --no-cache --for="xyzzy plugh quux flibbertigibbet" 2>/dev/null )"
[ "$NONSENSE" = "$NONSENSE2" ] \
    && ok "determinism: nonsense --for run-to-run byte-identical" \
    || no "nonsense --for is non-deterministic across two runs"

# ── 7) xml well-formed with weak="1" present ─────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$NONSENSE" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (weak=\"1\" present)" \
        || no "xml malformed when weak=\"1\" is emitted"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── 8) mutation self-test — the weak-absence assertion in #3 is LIVE: it must actually fail on a query
#    we know trips weak="1" (reuses the nonsense case from #1) ─────────────────────────────────────────
printf '%s' "$NONSENSE" | grep -q 'weak=' \
    && ok "mutation self-test (the weak-absence assertion correctly fails on a query that trips it)" \
    || no "mutation self-test FAILED — weak= assertion would not catch a real regression"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
