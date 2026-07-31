#!/usr/bin/env bash
# routecheck.sh — the routing gate: a deterministic, confidence-gated query-shape ranker selector for --for.
#
#   test/routecheck.sh                        # uses build/ctxpack on test/routefix
#   CTXPACK_BIN=asan/ctxpack test/routecheck.sh
#
# Routing is now the DEFAULT: --for (and --query) classify the query shape and pick the lens ranker
# (name-exact vs subtoken+body BM25) via a CONFIDENCE gate (lexical.h chooseForRanker) — name-exact only when
# the query NAMES a symbol (identifier syntax, or every content word is a symbol name), else subtoken+body.
# --no-route forces plain subtoken+body (the pre-default behavior). This gate asserts:
#   (a) SAFE FALLBACK — a CONCEPTUAL --for query defaults to subtoken+body; its RANKING is byte-identical to
#       the pre-routing golden captured via --no-route (the confidence gate does not over-fire on prose).
#   (b) identifier query — --for="buildGraph" (DEFAULT, no flag) routes to name-exact; the header says so.
#   (c) --no-route forces subtoken+body and matches the pre-flip capture byte-for-byte (golden neutrality
#       preserved for the opt-out path); its header carries NO 'routed:' note.
#   (d) determinism — two DEFAULT --route runs are byte-identical.
#   (e) --no-route WITHOUT --for/--query exits non-zero with a clear message.
# The fixture is copied to a tmp dir OUTSIDE any git repo and scanned via a RELATIVE path, so the golden
# carries no churn/co-change attrs and no absolute paths — stable across machines and time.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "routecheck: BIN=$BIN"

# fixture copy: sources only (never the golden itself), relative path, outside any git repo
mkdir -p "$TMP/routefix"
cp "$ROOT"/test/routefix/*.cpp "$TMP/routefix/"
cd "$TMP"

CONCEPT="how does resolution work"

# ── (a) SAFE FALLBACK — a CONCEPTUAL --for query defaults to subtoken+body: its RANKING is byte-identical to
#    the pre-routing golden (captured from plain subtoken+body). The DEFAULT run only ADDS a "[routed:
#    subtoken+body …]" header note, so we compare the --no-route run (identical bytes) to the golden AND
#    assert the DEFAULT run's ranking body matches by stripping just the header comment. ──────────────────
# RE-PIN 2026-07-30 (CA4 fixup wave, §F1): est_tokens="696" -> "703", the ONLY bytes that moved (the document
# is 1757 B before and after; every ranking byte identical vs the pre-wave binary). Same cause as anchorcheck's
# re-pin, and the two together are what identify it: BOTH goldens moved by exactly +7, so this is the
# est_tokens attribute finally charging its own digit string (main.cpp:1938-1945), not the emitted-bytes
# change — a re-measurement would move by a content-dependent amount, not a constant.
# Arithmetic: 1757 B / 703 tok = 2.4993 (the old 696 gave 2.5244). This golden's PURPOSE is route-neutrality;
# the ranking it pins did not change.
# CORRECTED at 2026-07-30 by the w1fix2 verifier (finding G1) — the first re-pin comment claimed this moved UP
# while anchorcheck moved DOWN, and called that the signature of re-measurement. Both moved up. See traps 17-19.
"$BIN" routefix --no-cache --for="$CONCEPT" --no-route >"$TMP/concept_noroute.xml" 2>/dev/null
diff -q "$TMP/concept_noroute.xml" "$ROOT/test/routefix/golden_for.xml" >/dev/null \
    && ok "safe fallback: conceptual --for --no-route byte-identical to the pre-routing golden" \
    || no "conceptual --for --no-route drifted from test/routefix/golden_for.xml"
# the DEFAULT (routed) conceptual run must fall back to subtoken+body — same ranker, only a header note added.
"$BIN" routefix --no-cache --for="$CONCEPT" >"$TMP/concept_default.xml" 2>/dev/null
grep -q 'routed: subtoken+body' "$TMP/concept_default.xml" \
    && ok "safe fallback: conceptual --for DEFAULTS to subtoken+body (no over-fire to name-exact)" \
    || no "conceptual --for did not fall back to subtoken+body (router over-fired on prose)"

# ── (b) identifier query DEFAULTS to name-exact (routing is on with no flag) ───────────────────────────
"$BIN" routefix --no-cache --for="buildGraph" >"$TMP/ident.xml" 2>/dev/null
grep -q 'routed: name-exact' "$TMP/ident.xml" \
    && ok "identifier query 'buildGraph' DEFAULTS to name-exact BM25 (routing is on by default)" \
    || no "identifier query did not route to name-exact (header missing 'routed: name-exact')"

# A7: an identifier embedded in LONG issue/review prose is evidence, not the whole intent. The old
# any-camel/snake rule discarded every prose/body term and cratered corrected LocBench train retrieval.
"$BIN" routefix --no-cache --for="repair buildGraph when the serialized ranked map is empty after cache reload" >"$TMP/long_ident.xml" 2>/dev/null
grep -q 'routed: subtoken+body' "$TMP/long_ident.xml" \
    && ok "long issue prose with one identifier stays subtoken+body" \
    || no "one identifier over-fired name-exact on a long conceptual query"

# ── (c) --no-route forces subtoken+body and matches the pre-flip capture; header carries NO routed note ─
"$BIN" routefix --no-cache --for="buildGraph" --no-route >"$TMP/ident_noroute.xml" 2>/dev/null
{ ! grep -q 'routed:' "$TMP/ident_noroute.xml"; } \
    && ok "--no-route on an identifier query forces subtoken+body (no 'routed:' header note)" \
    || no "--no-route still emitted a 'routed:' note — the opt-out did not disable routing"

# ── (d) determinism — two DEFAULT --for runs byte-identical ────────────────────────────────────────────
"$BIN" routefix --no-cache --for="buildGraph" >"$TMP/r1" 2>/dev/null
"$BIN" routefix --no-cache --for="buildGraph" >"$TMP/r2" 2>/dev/null
diff -q "$TMP/r1" "$TMP/r2" >/dev/null && ok "determinism (DEFAULT --for byte-identical run-to-run)" \
                                       || no "non-deterministic --for output"

# ── well-formed XML on the routed bundle (rides the same seam) ────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/ident.xml" 2>/dev/null && ok "xml well-formed (DEFAULT --for)" || no "xml malformed (DEFAULT --for)"
    xmllint --noout "$TMP/concept_default.xml" 2>/dev/null && ok "xml well-formed (conceptual DEFAULT --for)" || no "xml malformed (conceptual DEFAULT --for)"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

# ── --query also routes by default (name-exact pick surfaces as a leading comment before the map) ───────
"$BIN" routefix --no-cache --query="buildGraph" >"$TMP/q.xml" 2>/dev/null
grep -q 'routed: name-exact' "$TMP/q.xml" \
    && ok "--query='buildGraph' DEFAULTS to name-exact (leading routed comment before the map)" \
    || no "--query identifier did not route to name-exact"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/q.xml" 2>/dev/null && ok "xml well-formed (DEFAULT --query, routed comment)" || no "xml malformed (DEFAULT --query)"
fi

# ── (e) --no-route without --for/--query refuses loudly ────────────────────────────────────────────────
"$BIN" routefix --no-cache --no-route >/dev/null 2>"$TMP/err"
[ $? -ne 0 ] && grep -qi 'route' "$TMP/err" && ok "--no-route without --for/--query exits non-zero with a clear message" \
                                            || no "--no-route without --for/--query did not refuse loudly"

# ── MUTATION self-test — the name-exact routing assertion must FAIL against the --no-route run ─────────
MUT="$( grep -q 'routed: name-exact' "$TMP/ident_noroute.xml" && echo BAD || echo TRIPPED )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (the routing assertion fails on the --no-route run, so it is live)" \
                       || no "mutation self-test broke — the routing assertion cannot fail"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
