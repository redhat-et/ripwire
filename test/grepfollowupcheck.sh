#!/usr/bin/env bash
# grepfollowupcheck.sh — gate for the two --grep follow-up answers (the 2026-08-12 usage mine):
#
#   R1a — ZERO HITS answers the retry the agent was about to type. --grep is the dominant real verb and
#         its zero-hit case is the measured dead-end: agents retry with another literal and never switch
#         verb family. The fix is additive and disclosed: hits="0" stays an honest "none found" (never a
#         match), and a <suggest> element follows INSIDE <grep> carrying
#           near= the nearest indexed symbol name (the ONE didyoumean.h suggester — same machinery as
#                 every SYM-verb's "did you mean", see test/didyoumeancheck.sh)
#           next= a ready-to-paste conceptual fallback (--for="PATTERN") for word-like patterns —
#                 the grep→for conversion the mine shows never happens unprompted.
#         The legend labels both as SUGGESTIONS, never as matches (G4 honesty grammar).
#         Scope: literal --grep only (a zero-hit --regex pattern is not a near-miss identifier, and
#         --for of a regex is not a task); non-word-like patterns get no <suggest> at all — the
#         pre-change bytes, exactly.
#
#   R1b — NON-ZERO HITS carry the map's context without a second call. Each hit already names its
#         enclosing symbol (in=); the <enc> rows after the hit list attach, ONCE per DISTINCT enclosing
#         symbol on THIS page (first-appearance order, so the block is bounded by the page's own row
#         cap — no new cap, no repetition per hit, existing <hit> rows byte-untouched):
#           callers= the symbol's 1-hop caller count (in-edge CSR, a FLOOR — the graph already holds it)
#           cx=      complexity (already on the ingested Symbol; emitted when > 0)
#           amp=/tested= only when a co-run (--metrics) already computed the Q3 lens — grep itself
#                        never spawns new analysis (no git popen, no qmetrics pass).
#
# RED-FIRST: every arm tagged [red] fails against the pre-change binary
#   RIPWIRE_BIN=<pre-change ripwire> bash test/grepfollowupcheck.sh   # expect those arms to FAIL
#
# Usage:
#   test/grepfollowupcheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/grepfollowupcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "grepfollowupcheck: BIN=$BIN  CORPUS=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== R1a: zero hits — honest none-found PLUS the two suggestions ==="
# ═══════════════════════════════════════════════════════════════════════════

# (1) [red] a one-edit typo of a real fixture symbol: hits="0" preserved, near= names the real symbol,
#     next= is the ready-to-paste --for fallback. Exit stays 0 (a zero is a measurement, not an error).
"$BIN" "$FIX" --no-cache --grep=perimeterr >"$TMP/typo.xml" 2>/dev/null
e=$?
[ "$e" = 0 ] \
    && ok "(1) zero-hit grep still exits 0" \
    || no "(1) zero-hit grep exits $e, expected 0"

grep -q '<grep pattern="perimeterr" files="0" hits="0"' "$TMP/typo.xml" \
    && ok "(1a) hits=\"0\" stays an honest none-found (presence guard)" \
    || no "(1a) zero-hit header missing or reshaped"

grep -q '<suggest near="perimeter" next="--for=&quot;perimeterr&quot;"/>' "$TMP/typo.xml" \
    && ok "(1b) [red] <suggest> carries near= (did-you-mean) AND next= (--for fallback)" \
    || no "(1b) [red] no/wrong <suggest> element: $( grep -o '<suggest[^>]*>' "$TMP/typo.xml" | head -1 )"

# (1c) the suggestions are LABELED suggestions in the legend, never matches
grep -q 'SUGGESTIONS, never matches' "$TMP/typo.xml" \
    && ok "(1c) [red] legend labels the block as suggestions, never matches" \
    || no "(1c) [red] legend does not label <suggest> honestly"

# (2) [red] a word-like phrase with no near-miss: near= absent, next= still offered
"$BIN" "$FIX" --no-cache --grep='total area computation' >"$TMP/phrase.xml" 2>/dev/null
grep -q '<suggest next="--for=&quot;total area computation&quot;"/>' "$TMP/phrase.xml" \
    && ok "(2) [red] word-like phrase: next= --for fallback offered, no forced near=" \
    || no "(2) [red] phrase suggestion missing/wrong: $( grep -o '<suggest[^>]*>' "$TMP/phrase.xml" | head -1 )"

# (3) a non-word-like pattern gets NO suggestion block — byte-parity with the pre-change zero-hit answer
"$BIN" "$FIX" --no-cache --grep='((' >"$TMP/special.xml" 2>/dev/null
if grep -q '<suggest ' "$TMP/special.xml"; then
    no "(3) non-word-like pattern '((' grew a <suggest> block (must stay silent)"
else
    ok "(3) non-word-like pattern '((' stays suggestion-free"
fi

# (4) --regex zero-hit stays suggestion-free (a regex is not a near-miss identifier, nor a --for task)
"$BIN" "$FIX" --no-cache --regex='perimeterr[0-9]+' >"$TMP/rx.xml" 2>/dev/null
if grep -q '<suggest ' "$TMP/rx.xml"; then
    no "(4) --regex zero-hit grew a <suggest> block (scope is literal --grep only)"
else
    ok "(4) --regex zero-hit stays suggestion-free"
fi

# (5) a NON-zero grep never carries <suggest> (suggestions are the zero-hit surface only)
"$BIN" "$FIX" --no-cache --grep=perimeter >"$TMP/hits.xml" 2>/dev/null
if grep -q '<suggest ' "$TMP/hits.xml"; then
    no "(5) non-zero grep carries a <suggest> block"
else
    ok "(5) non-zero grep carries no <suggest> block"
fi

# (6) G4 + determinism ×3 on the suggesting output
xmllint --noout "$TMP/typo.xml" 2>/dev/null \
    && ok "(6) G4: zero-hit suggesting output is well-formed XML" \
    || no "(6) G4: zero-hit suggesting output is malformed XML"
"$BIN" "$FIX" --no-cache --grep=perimeterr >"$TMP/det2.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache --grep=perimeterr >"$TMP/det3.xml" 2>/dev/null
{ diff -q "$TMP/typo.xml" "$TMP/det2.xml" >/dev/null && diff -q "$TMP/typo.xml" "$TMP/det3.xml" >/dev/null; } \
    && ok "(6b) determinism ×3: byte-identical zero-hit output" \
    || no "(6b) determinism ×3: zero-hit output differs across runs"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== R1b: non-zero hits — <enc> rows carry callers= + lens, page-bounded ==="
# ═══════════════════════════════════════════════════════════════════════════

# fixture ground truth (hand-verified): distance is declared in geometry.h and defined in geometry.cpp;
# perimeter (geometry.cpp) and diagonal (sub/consumer.cpp) call it. Grep hits for "distance" therefore
# enclose several DISTINCT symbols, and the geometry.cpp def's row must carry its 1-hop caller count.
"$BIN" "$FIX" --no-cache --grep=distance >"$TMP/dist.xml" 2>/dev/null

# (7) [red] <enc> rows exist, and the def's row carries a positive callers= count
grep -q '<enc n="distance" callers="' "$TMP/dist.xml" \
    && ok "(7) [red] <enc n=\"distance\"> row present with callers=" \
    || no "(7) [red] no <enc> row for distance: $( grep -o '<enc[^>]*>' "$TMP/dist.xml" | head -3 )"

# (7b) [red] the exact row, checked by inspection (grepcheck's exact-value discipline): the two distance
#      defs (geometry.h decl + geometry.cpp def) GROUP into one row (defs="2"), and callers="2" is the
#      DISTINCT-caller union across them — perimeter + diagonal, the same count= the callers verb reports.
grep -q '<enc n="distance" callers="2" defs="2" cx="1"/>' "$TMP/dist.xml" \
    && ok "(7b) [red] distance row exact: callers=\"2\" (union), defs=\"2\", cx=\"1\"" \
    || no "(7b) [red] distance row wrong: $( grep -o '<enc n="distance"[^>]*>' "$TMP/dist.xml" | head -1 )"

# (8) [red] ONE row per DISTINCT enclosing symbol on the page — never one per hit
ENC_DIST="$( grep -o '<enc n="distance" ' "$TMP/dist.xml" | wc -l | tr -d ' ' )"
[ "$ENC_DIST" = 1 ] \
    && ok "(8) [red] exactly one <enc> row for distance despite multiple hits" \
    || no "(8) [red] $ENC_DIST <enc> rows for distance (dedupe broken)"

# (8b) the block is bounded by the page: #enc rows <= #distinct in= values among shown hits
HITS_IN="$( tr '<' '\n' <"$TMP/dist.xml" | sed -n 's/^hit [^>]*in="\([^"]*\)".*/\1/p' | grep -v '^$' | sort -u | wc -l | tr -d ' ' )"
ENC_ALL="$( grep -o '<enc n="' "$TMP/dist.xml" | wc -l | tr -d ' ' )"
[ "$ENC_ALL" -le "$HITS_IN" ] 2>/dev/null \
    && ok "(8b) enc rows ($ENC_ALL) <= distinct enclosing symbols on the page ($HITS_IN) — page-bounded" \
    || no "(8b) enc rows ($ENC_ALL) exceed the page's distinct enclosing symbols ($HITS_IN)"

# (9) hits outside any symbol (markdown prose) contribute NO enc row: grep a doc-only token
"$BIN" "$FIX" --no-cache --grep=perimeter >"$TMP/peri.xml" 2>/dev/null
if tr '<' '\n' <"$TMP/peri.xml" | grep -q '^enc n=""'; then
    no "(9) an empty-name <enc> row leaked (hits outside any symbol must contribute none)"
else
    ok "(9) no empty-name <enc> rows"
fi

# (10) [red] the legend discloses the block: floor semantics for callers=, page scope, lens conditions
grep -q 'enc.*DISTINCT enclosing symbol' "$TMP/dist.xml" \
    && ok "(10) [red] legend defines <enc> (distinct-per-page contract stated in-band)" \
    || no "(10) [red] legend never defines <enc>"
grep -q 'callers=.*FLOOR' "$TMP/dist.xml" \
    && ok "(10b) [red] legend states callers= is a FLOOR (call-graph honesty)" \
    || no "(10b) [red] legend does not state the callers= floor"

# (11) existing <hit> rows are byte-untouched by the enrichment (the grepcheck exact-shape contract)
grep -q '<hit p="[^"]*geometry\.cpp:11" in="perimeter"><m><!\[CDATA\[' "$TMP/peri.xml" \
    && ok "(11) <hit> rows keep their exact pre-change shape (enrichment is additive-after)" \
    || no "(11) <hit> row shape changed — enrichment must not touch hit rows"

# (12) --metrics co-run: lens attrs may appear, nothing crashes, still well-formed; plain grep never
#      carries amp=/tested= (it must not spawn the analysis)
if tr '<' '\n' <"$TMP/dist.xml" | grep '^enc ' | grep -qE 'amp=|tested='; then
    no "(12) plain --grep carries amp=/tested= — it must not run new analysis"
else
    ok "(12) plain --grep enc rows stay lens-free (no new analysis)"
fi
"$BIN" "$FIX" --no-cache --grep=distance --metrics >"$TMP/distm.xml" 2>/dev/null || true
xmllint --noout "$TMP/distm.xml" 2>/dev/null \
    && ok "(12b) --grep --metrics co-run stays well-formed" \
    || no "(12b) --grep --metrics co-run malformed/crashed"
# ...and the co-run's already-computed lens actually rides the rows (amp= on the distance group)
grep -q '<enc n="distance" callers="2" defs="2" cx="1" amp="' "$TMP/distm.xml" \
    && ok "(12c) [red] metrics co-run: amp= joins the distance enc row (lens rides when computed)" \
    || no "(12c) [red] metrics co-run: no amp= on the distance enc row: $( grep -o '<enc n="distance"[^>]*>' "$TMP/distm.xml" | head -1 )"

# (13) determinism ×3 + G4 on the enriched output
"$BIN" "$FIX" --no-cache --grep=distance >"$TMP/ddet2.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache --grep=distance >"$TMP/ddet3.xml" 2>/dev/null
{ diff -q "$TMP/dist.xml" "$TMP/ddet2.xml" >/dev/null && diff -q "$TMP/dist.xml" "$TMP/ddet3.xml" >/dev/null; } \
    && ok "(13) determinism ×3: byte-identical enriched output" \
    || no "(13) determinism ×3: enriched output differs across runs"
xmllint --noout "$TMP/dist.xml" 2>/dev/null \
    && ok "(13b) G4: enriched output is well-formed XML" \
    || no "(13b) G4: enriched output is malformed XML"

# (14) paging: enc rows describe the WINDOW — a --limit=1 page lists at most 1 enc row
"$BIN" "$FIX" --no-cache --grep=distance --limit=1 >"$TMP/page1.xml" 2>/dev/null
P1_ENC="$( grep -o '<enc n="' "$TMP/page1.xml" | wc -l | tr -d ' ' )"
[ "$P1_ENC" -le 1 ] 2>/dev/null \
    && ok "(14) --limit=1 page carries $P1_ENC enc row(s) (window-scoped)" \
    || no "(14) --limit=1 page carries $P1_ENC enc rows — block ignores the window"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== R1 MCP twins: the grep verb's JSON carries the same follow-ups ==="
# ═══════════════════════════════════════════════════════════════════════════

mcp_grep(){ # $1 = pattern → prints the grep verb's inner JSON text
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FIX\",\"pattern\":\"$1\"}}}" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print(r["result"]["content"][0]["text"] if "result" in r else "__ERROR__:" + r["error"]["message"])'
}

# (15) [red] zero-hit MCP grep carries the suggest object, spelled for the MCP surface (the for verb)
M0="$( mcp_grep perimeterr )"
printf '%s' "$M0" | python3 -c '
import sys, json
j = json.load(sys.stdin)
s = j.get("suggest") or {}
assert j["total"] == 0, "total moved"
assert s.get("near") == "perimeter", "near=%r" % s.get("near")
assert s.get("next_verb") == "for" and s.get("next_task") == "perimeterr", "next=%r" % s
assert "not matches" in s.get("note", ""), "note missing the honesty label"
print("OK")' >"$TMP/m0.res" 2>&1
[ "$( cat "$TMP/m0.res" )" = "OK" ] \
    && ok "(15) [red] MCP zero-hit grep suggests near + the for verb, labeled not-matches" \
    || no "(15) [red] MCP zero-hit suggest wrong: $( cat "$TMP/m0.res" ) — $( printf '%s' "$M0" | head -c 200 )"

# (16) [red] MCP hits carry the enclosing block with callers=
M1="$( mcp_grep distance )"
printf '%s' "$M1" | python3 -c '
import sys, json
j = json.load(sys.stdin)
assert "suggest" not in j, "suggest leaked onto a non-zero answer"
enc = j.get("enclosing") or []
names = [e["n"] for e in enc]
assert names.count("distance") == 1, "enc dedupe: %r" % names
d = [e for e in enc if e["n"] == "distance"][0]
assert d["callers"] >= 2, "callers=%r" % d.get("callers")
print("OK")' >"$TMP/m1.res" 2>&1
[ "$( cat "$TMP/m1.res" )" = "OK" ] \
    && ok "(16) [red] MCP grep enclosing block: one distance row, callers >= 2" \
    || no "(16) [red] MCP enclosing block wrong: $( cat "$TMP/m1.res" ) — $( printf '%s' "$M1" | head -c 200 )"

# (17) MCP determinism: two calls byte-identical
M2="$( mcp_grep distance )"
[ "$M1" = "$M2" ] \
    && ok "(17) MCP grep twin is byte-identical across two server processes" \
    || no "(17) MCP grep twin differs across processes"

# (18) the historic key order other gates read is untouched (files,total,shown,capped adjacency)
printf '%s' "$M1" | grep -q '"files":[0-9]*,"total":[0-9]*,"shown":[0-9]*,"capped":' \
    && ok "(18) un-paged MCP grep keeps its historic key order" \
    || no "(18) un-paged MCP grep key order moved — three other gates read this payload"

# ── Summary ────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
