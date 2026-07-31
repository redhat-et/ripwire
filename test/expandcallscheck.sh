#!/usr/bin/env bash
# expandcallscheck.sh — §P10.1 gate (PLAN_outputAudit_2026-07-28.md): --expand's <calls> block used to
# silently truncate. src/serialize.h's per-body callee-signature loop stops at `shown < 16 && used <
# budgetBytes` and emitted a bare `<calls>` with no total and no capped= — for a large-fanout symbol
# (`ingest`, 39 callees) the block showed as few as 1, and an agent reading it concluded the symbol calls
# one function. FIX: `<calls total="N">` is now ALWAYS emitted (total = outOff[id+1]-outOff[id], the same
# deduped-per-source count `--callees=SYM` reports for an unambiguous symbol — graph.h:37), and when the
# 16-cap or the byte budget actually cuts the list, `shown="S" capped="1"` is added (pageview.h THE
# TRUNCATION VOCABULARY rule 3: capped= always accompanies shown=, and both are omitted — not
# shown="T" capped="0" — when the listing is complete).
#
# Usage:  CTXPACK_BIN=build/ctxpack bash test/expandcallscheck.sh   |   CTXPACK_BIN=asan/ctxpack bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "expandcallscheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── #1: a large-fanout symbol (ingest) — <calls> carries total=, and total= equals --callees=ingest's count=
EXP_XML="$( "$BIN" . --top-k=0 --expand=ingest --no-cache 2>/dev/null )"
CALLS_TAG="$( printf '%s' "$EXP_XML" | grep -oE '<calls[^>]*>' | head -1 )"
CALLEES_COUNT="$( "$BIN" . --callees=ingest --no-cache 2>/dev/null | grep -oE 'count="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
EXP_TOTAL="$( printf '%s' "$CALLS_TAG" | grep -oE 'total="[0-9]+"' | grep -oE '[0-9]+' )"

[ -n "$CALLS_TAG" ] && ok "--expand=ingest emits a <calls> block ($CALLS_TAG)" || no "--expand=ingest emitted NO <calls> block"
[ -n "$EXP_TOTAL" ] && ok "<calls> carries total= ($EXP_TOTAL)" || no "<calls> has no total= attribute (the P10.1 bug)"
if [ -n "$EXP_TOTAL" ] && [ -n "$CALLEES_COUNT" ] && [ "$EXP_TOTAL" = "$CALLEES_COUNT" ]; then
    ok "<calls total=\"$EXP_TOTAL\"> agrees with --callees=ingest's count=\"$CALLEES_COUNT\""
else
    no "<calls total=\"$EXP_TOTAL\"> disagrees with --callees=ingest's count=\"$CALLEES_COUNT\""
fi

# ── #2: the block IS cut for ingest (39 callees, 16-cap/byte-budget) — capped="1" and shown= present, shown < total
if printf '%s' "$CALLS_TAG" | grep -q 'capped="1"'; then
    ok "--expand=ingest's <calls> discloses capped=\"1\""
else
    no "--expand=ingest's <calls> is missing capped=\"1\" (block is provably cut: $CALLS_TAG)"
fi
EXP_SHOWN="$( printf '%s' "$CALLS_TAG" | grep -oE 'shown="[0-9]+"' | grep -oE '[0-9]+' )"
if [ -n "$EXP_SHOWN" ] && [ -n "$EXP_TOTAL" ] && [ "$EXP_SHOWN" -lt "$EXP_TOTAL" ] 2>/dev/null; then
    ok "shown=\"$EXP_SHOWN\" < total=\"$EXP_TOTAL\" (the cut is honest, not a phantom flag)"
else
    no "shown=\"$EXP_SHOWN\" not < total=\"$EXP_TOTAL\""
fi
ACTUAL_C="$( printf '%s' "$EXP_XML" | grep -oE '<c n=' | wc -l | tr -d ' ' )"
[ -n "$EXP_SHOWN" ] && [ "$EXP_SHOWN" = "$ACTUAL_C" ] \
    && ok "shown=\"$EXP_SHOWN\" matches the actual emitted <c> row count ($ACTUAL_C)" \
    || no "shown=\"$EXP_SHOWN\" does not match the actual emitted <c> row count ($ACTUAL_C)"

# ── #3: a small-fanout symbol shows total==shown with NO capped= (the listing is complete — no phantom cut)
SMALL_XML="$( "$BIN" . --top-k=0 --expand=isDocExtension --no-cache 2>/dev/null )"
SMALL_TAG="$( printf '%s' "$SMALL_XML" | grep -oE '<calls[^>]*>' | head -1 )"
SMALL_CALLEES="$( "$BIN" . --callees=isDocExtension --no-cache 2>/dev/null | grep -oE 'count="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
SMALL_TOTAL="$( printf '%s' "$SMALL_TAG" | grep -oE 'total="[0-9]+"' | grep -oE '[0-9]+' )"
if [ -n "$SMALL_TOTAL" ] && [ "$SMALL_TOTAL" = "$SMALL_CALLEES" ]; then
    ok "small-fanout symbol: <calls total=\"$SMALL_TOTAL\"> agrees with --callees count=\"$SMALL_CALLEES\""
else
    no "small-fanout symbol: <calls total=\"$SMALL_TOTAL\"> disagrees with --callees count=\"$SMALL_CALLEES\""
fi
if printf '%s' "$SMALL_TAG" | grep -q 'capped='; then
    no "small-fanout symbol's <calls> carries a spurious capped= ($SMALL_TAG) — nothing was cut"
else
    ok "small-fanout symbol's <calls> carries no capped= — complete listing, nothing to disclose"
fi

# ── #4: G4 — xmllint clean on the (now attribute-richer) <calls> block ─────────────────────────────────
if printf '%s' "$EXP_XML" | xmllint --noout - 2>/dev/null; then
    ok "G4: --expand=ingest output is well-formed XML"
else
    no "G4: --expand=ingest output FAILS xmllint"
fi

# ── #5: det-gate — byte-identical across two runs ───────────────────────────────────────────────────────
"$BIN" . --top-k=0 --expand=ingest --no-cache >"$TMP/a.xml" 2>/dev/null
"$BIN" . --top-k=0 --expand=ingest --no-cache >"$TMP/b.xml" 2>/dev/null
if cmp -s "$TMP/a.xml" "$TMP/b.xml"; then
    ok "det-gate: --expand=ingest byte-identical across two runs"
else
    no "det-gate: --expand=ingest output DIFFERS across two runs"
fi

if [ "$fail" = 0 ]; then echo "expandcallscheck: ALL PASS"; else echo "expandcallscheck: FAILURES ABOVE"; fi
exit "$fail"
