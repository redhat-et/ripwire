#!/usr/bin/env bash
# callerscheck.sh — RANKING-CORE gate for --callers=SYM (inverse call direction: 1-hop in-edges). Zero
# prior coverage before this gate. Reuses test/queryfix (no new fixture — its call graph is already
# hand-verified by querycheck.sh):
#
#   chain.cpp:  d1 -> d2 -> d3 -> d4                     (linear chain)
#   util.cpp:   hot() called by BOTH caller_a() and caller_b()  (the known unambiguous multi-caller edge)
#               rec()  is SELF-recursive and has NO external callers
#
# Investigated first, not assumed:  §"drop self-loops (src == dst) — in the Google matrix they act
# as rank sinks" 130) — buildGraph's comment confirms self/unresolved/file-scope refs are DROPPED
# by design (src/graph.h ~ buildGraph). Verified directly: even a plain `if(n>0) return f(n-1);`
# self-recursive call produces ZERO edges in the call graph (edges= count in the default map). So rec()
# correctly has --callers count=0 — this is intentional PageRank hygiene, NOT a caller-resolution bug, and
# is exactly why rec() is the fixture's "no callers" case rather than a false negative to chase.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/callerscheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/queryfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/queryfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "callerscheck: BIN=$BIN  CORPUS=test/queryfix"

c(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" --callers="$1" --no-cache 2>/dev/null; }
ec(){ perl -e 'alarm 8; exec @ARGV' "$BIN" "$FIX" --callers="$1" --no-cache >/dev/null 2>&1; echo $?; }
cnt(){ printf '%s' "$1" | grep -oE 'count="[0-9]+"' | grep -oE '[0-9]+'; }

# ── #1: --callers=hot lists exactly the 2 known callers, with correct p="....file:line" (R-E, 2026-08-17
#    harvest: --callers is now root-relative, so a single-root run's p= never carries the crawl root's OWN
#    directory name at all — "queryfix/src/..." became bare "src/..." — match the root-relative spelling
#    directly rather than a "queryfix/" suffix that used to tolerate an absolute-or-./-relative FIX path) ──
OUT_HOT="$( c hot )"
{ [ "$( cnt "$OUT_HOT" )" = 2 ] \
    && printf '%s' "$OUT_HOT" | grep -qE '<s t="fn" n="caller_a" p="src/util\.cpp:3"/>' \
    && printf '%s' "$OUT_HOT" | grep -qE '<s t="fn" n="caller_b" p="src/util\.cpp:4"/>'; } \
    && ok "--callers=hot: exactly caller_a (util.cpp:3) + caller_b (util.cpp:4), count=2" \
    || no "--callers=hot: wrong callers/lines — got: $OUT_HOT"

# ── #2: --callers=d3 lists exactly its one known caller (d2), correct file:line ─────────────────────────
OUT_D3="$( c d3 )"
{ [ "$( cnt "$OUT_D3" )" = 1 ] && printf '%s' "$OUT_D3" | grep -qE '<s t="fn" n="d2" p="src/chain\.cpp:3"/>'; } \
    && ok "--callers=d3: exactly d2 (chain.cpp:3), count=1" \
    || no "--callers=d3: wrong caller/line — got: $OUT_D3"

# ── #3: --callers of a never-called symbol → empty/zero result, no crash. Two witnesses:
#    d1 (head of the chain, nothing calls it) and rec (self-recursive only; self-loops are DROPPED by
#    design — see header note — so it also has count=0, not a caller-resolution miss). ──────────────────
OUT_D1="$( c d1 )"
[ "$( cnt "$OUT_D1" )" = 0 ] && ok "--callers=d1: count=0 (head of chain, never called)" || no "--callers=d1 should be count=0, got: $OUT_D1"
OUT_REC="$( c rec )"
[ "$( cnt "$OUT_REC" )" = 0 ] && ok "--callers=rec: count=0 (self-recursive only; self-loops dropped by design)" || no "--callers=rec should be count=0, got: $OUT_REC"
[ "$( ec d1 )" = 0 ] && ok "--callers=d1 exits 0 (empty result is not an error)" || no "--callers=d1 should exit 0"

# ── #4: --callers of a nonexistent symbol exits cleanly (non-zero) with a clear message on stderr ───────
BOGUS_MSG="$( "$BIN" "$FIX" --callers=totally_bogus_symbol_zzz --no-cache 2>&1 1>/dev/null )"
BOGUS_EC="$( ec totally_bogus_symbol_zzz )"
{ [ "$BOGUS_EC" != 0 ] && printf '%s' "$BOGUS_MSG" | grep -qi "not found"; } \
    && ok "--callers of a nonexistent symbol exits non-zero ($BOGUS_EC) with a 'not found' message" \
    || no "--callers of nonexistent symbol: expected non-zero exit + 'not found' message, got exit=$BOGUS_EC msg='$BOGUS_MSG'"

# ── #5: determinism — twice, byte-identical ──────────────────────────────────────────────────────────
A="$( c hot )"; B="$( c hot )"
[ "$A" = "$B" ] && ok "determinism: --callers=hot byte-identical run-to-run" || no "non-deterministic --callers output"

# ── xml well-formed ──────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    c hot | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# §P10.6: --callers/--callees silently unioned overloads — the only symbol verbs with no defs=. Now the
# root carries defs= (resolved definitions the name matched) and it must AGREE with --uses's defs=.
cdefs="$( "$BIN" "$ROOT" --callers=empty 2>/dev/null | grep -oE 'defs="[0-9]+"' | head -1 )"
udefs="$( "$BIN" "$ROOT" --uses=empty    2>/dev/null | grep -oE 'defs="[0-9]+"' | head -1 )"
if [ -n "$cdefs" ] && [ "$cdefs" = "$udefs" ]; then
    ok "P10.6: --callers defs= present and agrees with --uses ($cdefs)"
else
    no "P10.6: --callers defs= '$cdefs' missing or disagrees with --uses '$udefs'"
fi
"$BIN" "$ROOT" --callees=empty 2>/dev/null | grep -qE '<callees of="empty" defs="[0-9]+"'     && ok "P10.6: --callees carries defs= (a count=0 is now a measurement over N known defs)"     || no "P10.6: --callees root missing defs="

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
