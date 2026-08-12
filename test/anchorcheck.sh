#!/usr/bin/env bash
# anchorcheck.sh — the steal-#1 gate: LARGER-style lexically-anchored graph expansion (--for --anchor).
#
#   test/anchorcheck.sh                       # uses build/ripwire on test/anchorfix
#   RIPWIRE_BIN=asan/ripwire test/anchorcheck.sh
#
# --anchor seeds the PPR personalization from the top lexical hits of --for=TASK and blends the walk back
# into the lens rank (graph.h anchoredLexicalRank) — surfacing structurally-adjacent symbols the task's
# words never touch. This gate asserts:
#   * GOLDEN NEUTRALITY — --for WITHOUT --anchor is byte-identical to the pre-change golden capture
#     (test/anchorfix/golden_for.xml, captured from the pre---anchor binary).
#   * the targeted expansion case — frobnicateWidgetCache (the lexical anchor) directly calls
#     flushEvictionQueue, which shares NO token with the query: it must appear in the ANCHORED top-4
#     and must NOT appear in the plain lexical top-4.
#   * --for --anchor runs, is xmllint-clean, and is deterministic across two runs.
#   * --anchor without --for refuses loudly (exit non-zero) instead of silently doing nothing.
# The fixture is copied to a tmp dir OUTSIDE any git repo and scanned via a RELATIVE path, so the output
# carries no churn/co-change attrs and no absolute paths — the golden is stable across machines and time.
# Mutation-tested: the expansion assertion is checked to actually FAIL against the plain (un-anchored) run.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# L5: --anchor is dropped from --help and gated behind RIPWIRE_DEV=1 (negative-result
# experiment, kept reachable for continued eval work). This gate exercises the flag directly, so it
# needs the gate itself set.
export RIPWIRE_DEV=1

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "anchorcheck: BIN=$BIN"

# fixture copy: sources only (never the golden itself), relative path, outside any git repo
mkdir -p "$TMP/anchorfix"
cp "$ROOT"/test/anchorfix/*.cpp "$TMP/anchorfix/"
cd "$TMP"
QUERY="frobnicate widget cache"

# ── 1) GOLDEN NEUTRALITY — --for --no-route WITHOUT --anchor byte-identical to the pre-change capture ──
# The golden captures the plain subtoken+body lens. Routing is now the DEFAULT, so the byte-stable reference
# is the --no-route path (which restores exactly the pre-routing bytes); --anchor must not leak into it.
# (This conceptual query — "frobnicate widget cache" — falls back to subtoken+body even under DEFAULT routing,
# so the RANKING is unchanged either way; the default only ADDS a "[routed: subtoken+body …]" header note,
# which is why the golden compare uses --no-route to stay byte-exact.)
# RE-PIN 2026-07-30 (CA4 fixup wave, §F1): est_tokens="725" -> "732", the ONLY bytes that moved (the document
# is 1830 B before and after; every ranking byte identical vs the pre-wave binary). CAUSE — and it is NOT the
# emitted-bytes change: routefix's golden moved by exactly +7 too, and a CONSTANT delta on two unrelated
# fixtures is a fixed-size addition, not a content-dependent re-measurement. It is the self-reference fix at
# main.cpp:1938-1945 — the est_tokens attribute is part of the document est_tokens measures, and the previous
# form summed the bundle WITHOUT its own digit string, "reported ~8 tokens under, which is why the measured
# rate read 2.51 B/tok where this emitter's rate is 2.50". Arithmetic: 1830 B / 732 tok = 2.5000 (the old 725
# gave 2.5241, i.e. the under-count). This golden's PURPOSE is anchor-neutrality, not the estimate;
# byte-identity is kept deliberately as the strongest available statement of that property.
# CORRECTED at 2026-07-30 by the w1fix2 verifier (finding G1) after the first re-pin comment got the byte
# count, the new value, both rates and the causal story wrong — see the trap ledger entries 17-19.
"$BIN" anchorfix --no-cache --for="$QUERY" --no-route >"$TMP/plain_full.xml" 2>/dev/null
diff -q "$TMP/plain_full.xml" "$ROOT/test/anchorfix/golden_for.xml" >/dev/null \
    && ok "golden-neutral: plain --for --no-route byte-identical to the pre---anchor golden" \
    || no "plain --for --no-route drifted from test/anchorfix/golden_for.xml (--anchor leaked into the default lens)"

# ── 2) the targeted expansion case — a lexically-invisible direct callee, top-4 window ────────────────
PLAIN="$( "$BIN" anchorfix --no-cache --for="$QUERY" --pack-top-n=4 2>/dev/null )"
ANCH="$(  "$BIN" anchorfix --no-cache --for="$QUERY" --pack-top-n=4 --anchor 2>/dev/null )"
# T3 (contract update, same wave): the default bundle now appends the top symbol's FULL body with its
# callee signatures, where a direct callee's name legitimately appears — the property THIS gate pins is
# the RANKED top-4 window, so both membership probes scope to the <sigs> span, not the whole document.
sigspan(){ python3 -c 'import sys; s=sys.stdin.buffer.read(); a=s.find(b"<sigs"); b=s.find(b"</sigs>"); sys.stdout.buffer.write(s[a:b+7] if a>=0 and b>=0 else b"")'; }
PLAIN_SIGS="$( printf '%s' "$PLAIN" | sigspan )"
ANCH_SIGS="$(  printf '%s' "$ANCH"  | sigspan )"
printf '%s' "$PLAIN_SIGS" | grep -q 'flushEvictionQueue' \
    && no "plain lexical top-4 wrongly contains the zero-overlap callee (fixture no longer discriminates)" \
    || ok "plain lexical top-4 excludes flushEvictionQueue (lexically invisible, as designed)"
printf '%s' "$ANCH_SIGS" | grep -q 'flushEvictionQueue' \
    && ok "anchored top-4 surfaces flushEvictionQueue (graph expansion from the lexical anchor)" \
    || no "anchored top-4 missing flushEvictionQueue — expansion did not propagate to the direct callee"
# the anchors themselves must survive the blend (lexical stays dominant — never drowned by the walk)
printf '%s' "$ANCH_SIGS" | grep -q 'frobnicateWidgetCache' \
    && ok "anchored top-4 keeps the lexical anchor itself (frobnicateWidgetCache)" \
    || no "anchored rank drowned the top lexical anchor — blend is broken"

# ── 3) determinism + well-formed XML on the anchored bundle ───────────────────────────────────────────
"$BIN" anchorfix --no-cache --for="$QUERY" --anchor >"$TMP/a1" 2>/dev/null
"$BIN" anchorfix --no-cache --for="$QUERY" --anchor >"$TMP/a2" 2>/dev/null
diff -q "$TMP/a1" "$TMP/a2" >/dev/null && ok "determinism (--for --anchor byte-identical run-to-run)" || no "non-deterministic --anchor output"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/a1" 2>/dev/null && ok "xml well-formed (--for --anchor)" || no "xml malformed (--for --anchor)"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi
# the anchored header comment must declare the mode honestly (EXPERIMENTAL marker)
grep -q 'anchored, EXPERIMENTAL' "$TMP/a1" && ok "anchored output self-declares EXPERIMENTAL in the header comment" \
                                           || no "anchored output missing the EXPERIMENTAL header marker"

# ── 4) --anchor without --for refuses loudly ──────────────────────────────────────────────────────────
"$BIN" anchorfix --no-cache --anchor >/dev/null 2>"$TMP/err"
[ $? -ne 0 ] && grep -qi 'anchor' "$TMP/err" && ok "--anchor without --for exits non-zero with a clear message" \
                                             || no "--anchor without --for did not refuse loudly"

# ── 4b) --anchor WITHOUT RIPWIRE_DEV=1 refuses loudly (the L5 experimental gate) ──────────────────────
env -u RIPWIRE_DEV "$BIN" anchorfix --no-cache --for="$QUERY" --anchor >/dev/null 2>"$TMP/deverr"
[ $? -ne 0 ] && grep -q 'RIPWIRE_DEV' "$TMP/deverr" && ok "--anchor without RIPWIRE_DEV=1 refuses loudly (exit nonzero, names RIPWIRE_DEV)" \
                                                     || no "--anchor without RIPWIRE_DEV=1 did not refuse loudly"

# ── 5) MUTATION self-test — the expansion assertion must FAIL against the un-anchored output ──────────
MUT="$( printf '%s' "$PLAIN_SIGS" | grep -q 'flushEvictionQueue' && echo BAD || echo TRIPPED )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (the expansion assertion fails on the plain run, so it is live)" \
                       || no "mutation self-test broke — the expansion assertion cannot fail"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
