#!/usr/bin/env bash
# spectimingcheck.sh — the G-determinism gate for the CTXPACK_MCP_TIMINGS instrumentation
# (DESIGN_specPrefetch.md, Phase E). The MEASURE-FIRST timing observable must be:
#   (1) SILENT + byte-identical on stdout when the env var is UNSET (zero-cost-off, house rule — same
#       contract as ingest.cpp's CTXPACK_CACHE_STATS and the CTXPACK_PROFILE markers);
#   (2) when SET, emit one `ctxpack-timing verb=… wall_ms=… rebuilt=…` line PER request to STDERR ONLY,
#       while the JSON-RPC stdout stream stays BYTE-IDENTICAL to the env-unset run;
#   (3) attribute rebuilt=1 to the first (cache-miss) verb and rebuilt=0 to a subsequent warm read.
#
# The env-gated stderr must never perturb the protocol stream — this gate is the executable proof.
#
# Usage:
#   test/spectimingcheck.sh
#   CTXPACK_BIN=build_ic2/ctxpack test/spectimingcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh; touches no source; drives the server over stdin only (read-only on the repo).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "spectimingcheck: BIN=$BIN"

# a fixed 3-request session: initialize, a cold 'for' (first verb ⇒ rebuild), a warm 'impact' (reuse).
REQS="$TMP/reqs.jsonl"
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$ROOT"'","task":"rank symbols by relevance"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"impact","arguments":{"path":"'"$ROOT"'","symbol":"buildGraph"}}}'
} > "$REQS"

# ── run OFF (env unset) ──
env -u CTXPACK_MCP_TIMINGS "$BIN" --mcp < "$REQS" > "$TMP/off.out" 2> "$TMP/off.err"
# ── run ON (env set) ──
CTXPACK_MCP_TIMINGS=1 "$BIN" --mcp < "$REQS" > "$TMP/on.out" 2> "$TMP/on.err"

# (1) OFF must emit NO timing line on stderr.
if grep -q '^ctxpack-timing ' "$TMP/off.err"; then
  no "(1) env UNSET leaked a ctxpack-timing line to stderr (should be silent)"
else
  ok "(1) env UNSET is silent on stderr (zero-cost-off)"
fi

# (2) stdout byte-identical ON vs OFF (the protocol stream is untouched by the observable).
if diff -q "$TMP/off.out" "$TMP/on.out" >/dev/null; then
  ok "(2) JSON-RPC stdout is byte-identical ON vs OFF (stderr-only, no protocol perturbation)"
else
  no "(2) stdout DIFFERS between ON and OFF — the observable perturbed the protocol stream"
fi

# (2b) every stdout line is still valid JSON with a matching id (the stream was not corrupted).
if python3 - "$TMP/on.out" <<'PY'
import json, sys
n = 0
for ln in open(sys.argv[1]):
    ln = ln.strip()
    if not ln: continue
    o = json.loads(ln)              # raises → non-zero exit → FAIL below
    assert "id" in o
    n += 1
sys.exit(0 if n == 3 else 1)
PY
then ok "(2b) all 3 responses are well-formed JSON-RPC with ids"
else no "(2b) response stream not 3 well-formed JSON-RPC objects"; fi

# (3) ON emits exactly one timing line per request, rebuilt=1 on the cold 'for', rebuilt=0 on warm 'impact'.
NLINES="$( grep -c '^ctxpack-timing ' "$TMP/on.err" )"
[ "$NLINES" = "3" ] && ok "(3) env SET emitted one timing line per request (3)" \
                     || no "(3) expected 3 timing lines, got $NLINES"

if grep -q '^ctxpack-timing verb=for wall_ms=[0-9.]* rebuilt=1' "$TMP/on.err"; then
  ok "(3b) the cold 'for' verb is attributed rebuilt=1"
else
  no "(3b) the cold 'for' verb did not report rebuilt=1"
fi
if grep -q '^ctxpack-timing verb=impact wall_ms=[0-9.]* rebuilt=0' "$TMP/on.err"; then
  ok "(3c) the warm 'impact' verb is attributed rebuilt=0 (index reused)"
else
  no "(3c) the warm 'impact' verb did not report rebuilt=0"
fi

if [ "$fail" = "0" ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
