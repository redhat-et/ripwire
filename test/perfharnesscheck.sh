#!/usr/bin/env bash
# perfharnesscheck.sh — deterministic semantic preflights for the two on-demand performance gates.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
grep -q 'exclusive = {"editcheckcheck.sh"}' "$ROOT/test/pargates.py" \
    && ok "parallel runner isolates the wall-clock edit-check budget" \
    || no "parallel runner measures edit-check while unrelated gates contend for the machine"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "perfharnesscheck: BIN=$BIN"

RIPWIRE_BIN="$BIN" "$ROOT/bench/perfgate.sh" --preflight-only >"$TMP/core.out" 2>"$TMP/core.err"; coreRc=$?
[ "$coreRc" -eq 0 ] && grep -q 'all semantic preflights passed' "$TMP/core.out" \
    && ok "core performance gate semantic preflight passes" \
    || { no "core performance preflight failed (rc=$coreRc)"; sed -n '1,12p' "$TMP/core.out" "$TMP/core.err"; }

RIPWIRE_BIN="$BIN" RIPWIRE_REP_PERF_RUNS=5 "$ROOT/bench/representative_perfgate.sh" --preflight-only \
    >"$TMP/rep.out" 2>"$TMP/rep.err"; repRc=$?
[ "$repRc" -eq 0 ] && grep -q 'all semantic preflights passed' "$TMP/rep.out" \
    && ok "representative performance gate semantic preflight passes" \
    || { no "representative performance preflight failed (rc=$repRc)"; sed -n '1,12p' "$TMP/rep.out" "$TMP/rep.err"; }

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
