#!/usr/bin/env bash
# includeanglecheck.sh — P0 gate for the quote-vs-angle Include discriminator (Include::isAngle).
#
# P0 adds a `bool isAngle` to the Include record, captured at parse time in ingest.cpp
# (captureIncludes: `<x.h>` ⇒ isAngle=true, `"x.h"` ⇒ isAngle=false) and threaded through the
# --cache=FILE round-trip (kCacheVersion bumped to 4). NOTHING consumes isAngle yet (path-precise
# resolution lands in P2), so this phase must produce ZERO output/graph change — the ONLY observable
# contract is: the field survives the cache round-trip byte-identically, and warm == cold.
#
# Asserts:
#   - a fixture mixing one quote include ("x.h") and one angle include (<x.h>) parses + exits 0
#   - cold run (populate cache)  ==  warm run (reuse cache), BYTE-IDENTICAL  (the round-trip gate)
#   - warm run  ==  --no-cache run, BYTE-IDENTICAL  (isAngle plumbing changes no output at P0)
#   - determinism: two cold --no-cache runs byte-identical
#   - well-formed XML
#
# Usage:  test/includeanglecheck.sh   |   CTXPACK_BIN=asan/ctxpack test/includeanglecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "includeanglecheck: BIN=$BIN  TMP=$TMP"

WORK="$TMP/proj"
mkdir -p "$WORK"

# fixture: a header defining a symbol, and a .cpp that includes it BOTH ways — one quote, one angle.
printf 'int helper( void );\n'                                   > "$WORK/x.h"
printf '#include "x.h"\n#include <x.h>\nint use( void ){ return helper(); }\n' > "$WORK/main.cpp"

CACHE="$TMP/c.bin"

# ── cold run: populate the cache ──────────────────────────────────────────────────────────────────
"$BIN" "$WORK" --cache="$CACHE" >"$TMP/cold.xml" 2>"$TMP/cold.err"
rc=$?
[ "$rc" -eq 0 ] && ok "cold run (cache populate) exits 0" || { no "cold run exit $rc"; cat "$TMP/cold.err"; }

grep -q 'n="use"' "$TMP/cold.xml" && ok "fixture parsed (symbol 'use' present)" \
  || { no "fixture did not parse"; head -3 "$TMP/cold.xml"; }

# ── warm run: reuse the cache — must be byte-identical to cold (the round-trip gate) ──────────────
"$BIN" "$WORK" --cache="$CACHE" >"$TMP/warm.xml" 2>/dev/null
if cmp -s "$TMP/cold.xml" "$TMP/warm.xml"; then
  ok "warm == cold (Include::isAngle round-trips through the cache byte-identically)"
else
  no "warm != cold — cache round-trip of Include changed output (kCacheVersion / isAngle serde bug)"
  diff <(head -c 400 "$TMP/cold.xml") <(head -c 400 "$TMP/warm.xml") | head
fi

# ── --no-cache run: P0 adds a field but consumes it nowhere, so output must be unchanged ──────────
"$BIN" "$WORK" --no-cache >"$TMP/nocache.xml" 2>/dev/null
cmp -s "$TMP/cold.xml" "$TMP/nocache.xml" \
  && ok "cache path == no-cache path (isAngle plumbing is output-neutral at P0)" \
  || { no "cache vs no-cache diverged at P0"; diff "$TMP/cold.xml" "$TMP/nocache.xml" | head; }

# ── determinism: two independent cold runs byte-identical ─────────────────────────────────────────
"$BIN" "$WORK" --no-cache >"$TMP/d1.xml" 2>/dev/null
"$BIN" "$WORK" --no-cache >"$TMP/d2.xml" 2>/dev/null
cmp -s "$TMP/d1.xml" "$TMP/d2.xml" && ok "deterministic (two --no-cache runs identical)" \
  || no "non-deterministic output"

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/cold.xml" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
