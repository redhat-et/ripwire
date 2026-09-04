#!/usr/bin/env bash
# fileselectorrefusecheck.sh — H6 (capture-audit 2026-09-04, lens 6 F1): a FILE-LIST selector that names
# nothing indexed is a REFUSAL, never an answer of zero.
#
# THE DEFECT. `--situ=src/nosuch.h` printed "0 changed file(s) — nothing to analyze" at exit 0, and the MCP
# twin `situational_awareness{files:"src/nosuch.h"}` returned all-empty arrays with a green `_fresh: ok`.
# Its three siblings over the SAME argument grammar — `--affected`, `--test-gate`, `--exercises` — all
# refuse with flag + path + accepted form. An agent that misspells the file it just edited therefore reads
# "no blast radius, no tests to run" from one verb of the family and a refusal from the other three: the
# false zero non-negotiable #3 forbids ("a zero means none found, never none exists").
#
# THE FAMILY, derived not assumed. The FILE-list selectors are the verbs whose argument is a comma-separated
# list of indexed paths: --situ, --test-gate, --affected, --exercises (CLI) and situational_awareness (MCP).
# `--cochange=FILE` takes one path by the same suffix rule and is checked in the same sweep. Every one of
# them is asserted here, so a sixth verb joining the grammar cannot inherit the silent-zero by omission.
#
# ARMS
#   A  every CLI FILE-selector, given a path that matches no indexed file, exits NON-ZERO
#   B  ... and its stderr names the FLAG and echoes the PATH (a refusal that names neither cannot be
#      matched back to the command that caused it)
#   C  ... and, when the path is a one-edit typo of an indexed one, names that file in a did-you-mean
#      (the MCP `cochange` refusal already did this; the CLI arms did not)
#   D  a path that DOES resolve still answers (the refusal must not swallow the working case)
#   E  MCP situational_awareness with a bad `files` item returns a JSON-RPC error, not empty arrays
#   F  MCP situational_awareness with a good `files` item still answers
#
# RED-FIRST (pre-fix binary): A/B/C fail on --situ, C fails on --test-gate/--affected/--exercises/--cochange,
# E fails (result with empty arrays). Post-fix: ALL PASS.
#
# Usage:  bash test/fileselectorrefusecheck.sh [BIN]   |   RIPWIRE_BIN=build_base/ripwire bash test/…
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/fixture — fixture missing"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the MCP arms"; exit 2; }

echo "fileselectorrefusecheck: BIN=$BIN  FIX=$FIX"

BAD="geometrz_nosuch.h"     # matches no indexed path, and is NOT a one-edit typo (arms A/B)
NEAR="geometrz.h"           # one edit from the indexed geometry.h (arm C)
GOOD="geometry.h"           # really indexed (arm D)

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== A/B: every CLI FILE-list selector REFUSES a path that matches nothing indexed ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
for flag in --situ --test-gate --affected --exercises --cochange; do
    out="$( "$BIN" "$FIX" "$flag=$BAD" --no-cache 2>&1 1>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ]; then
        ok "A $flag=$BAD → exit $rc (non-zero)"
    else
        no "A $flag=$BAD → exit 0 — a selector naming nothing indexed answered instead of refusing"
    fi
    if printf '%s' "$out" | grep -qF -- "$flag" && printf '%s' "$out" | grep -qF -- "$BAD"; then
        ok "B $flag: refusal names the flag and echoes the path"
    else
        no "B $flag: refusal missing flag and/or echoed path: $out"
    fi
done

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== C: a one-edit path typo names the indexed file in a did-you-mean ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
for flag in --situ --test-gate --affected --exercises --cochange; do
    out="$( "$BIN" "$FIX" "$flag=$NEAR" --no-cache 2>&1 1>/dev/null )"
    if printf '%s' "$out" | grep -qF "did you mean" && printf '%s' "$out" | grep -qF "$GOOD"; then
        ok "C $flag=$NEAR → suggests $GOOD"
    else
        no "C $flag=$NEAR → no did-you-mean naming $GOOD: $out"
    fi
done

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== D: a path that resolves still answers (the refusal did not swallow the working case) ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
for flag in --situ --affected --cochange; do
    "$BIN" "$FIX" "$flag=$GOOD" --no-cache >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "D $flag=$GOOD → exit 0"
    else
        no "D $flag=$GOOD → exit $rc (a resolvable path must still answer)"
    fi
done
# --test-gate's exit code IS its gate (4 = obligations) — assert only that it is not the refusal code.
"$BIN" "$FIX" "--test-gate=$GOOD" --no-cache >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 4 ]; then ok "D --test-gate=$GOOD → exit $rc (0 or 4, the gate's own codes)"; else no "D --test-gate=$GOOD → exit $rc"; fi

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== E/F: MCP situational_awareness — bad files item errors, good one answers ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}'
mcp_situ() { # $1 = files value → the LAST JSON-RPC line of a two-request stdio session
    local call="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"situational_awareness\",\"arguments\":{\"path\":\"$FIX\",\"files\":\"$1\"}}}"
    local session
    session="$( printf '%s\n%s\n' "$INIT" "$call" )"
    printf '%s\n' "$session" | "$BIN" --mcp 2>/dev/null | tail -1
}

OUT="$( mcp_situ "$BAD" )"
if printf '%s' "$OUT" | python3 -c 'import sys,json; r=json.load(sys.stdin); sys.exit(0 if "error" in r else 1)' 2>/dev/null; then
    ok "E MCP situational_awareness files=$BAD → JSON-RPC error"
else
    no "E MCP situational_awareness files=$BAD → no error (empty arrays read as 'nothing depends on your edit'): $OUT"
fi

OUT="$( mcp_situ "$GOOD" )"
if printf '%s' "$OUT" | python3 -c 'import sys,json; r=json.load(sys.stdin); sys.exit(0 if "error" not in r else 1)' 2>/dev/null; then
    ok "F MCP situational_awareness files=$GOOD → result"
else
    no "F MCP situational_awareness files=$GOOD → refused a resolvable path: $OUT"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
