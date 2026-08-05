#!/usr/bin/env bash
# deckclaimcheck.sh — numeric flag claims in the generated showcase source match --help.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
GEN="$ROOT/present/deck5_ripwire_build.js"

[ -x "$BIN" ] || { echo "deckclaimcheck: no binary at $BIN — build first"; exit 2; }
[ -f "$GEN" ] || { echo "deckclaimcheck: missing $GEN"; exit 2; }

derived="$( "$BIN" --help 2>&1 | grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u | wc -l | tr -d ' ' )"
bad="$( grep -oE '[0-9]+ long flags' "$GEN" | grep -v "^${derived} long flags$" || true )"
[ -z "$bad" ] || { echo "deckclaimcheck: stale claim(s), binary has $derived flags: $bad"; exit 1; }
grep -q "${derived} long flags" "$GEN" || { echo "deckclaimcheck: generator does not state derived count $derived"; exit 1; }
echo "deckclaimcheck: ALL PASS"
