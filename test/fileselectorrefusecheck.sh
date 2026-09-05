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
#   G  MULTI-ROOT (verify-wave1 N3): the refusal is evaluated over the UNION of roots while the answer is
#      printed per root, so a root the selector matches nothing in printed "(no changed files in this root)"
#      at exit 0 — the exact sentence H6 was opened to kill, one level down. The rule is one refusal-or-
#      answer per SELECTOR: a selector that resolves in the workspace but names nothing under THIS root gets
#      a selector sentence (which root(s) its matches live under), never the empty-diff sentence; a selector
#      that resolves nowhere still refuses for the whole workspace (exit 1); the default git-diff form keeps
#      its empty-diff sentence, because there it is a measurement.
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

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== G: multi-root --situ — one refusal-or-answer per SELECTOR, never a per-root false zero ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
FIX2="$( mktemp -d )/betaroot"; mkdir -p "$FIX2"
printf 'int beta( int x ) { return x + 1; }\n' >"$FIX2/beta.cpp"
LBL2="$( basename "$FIX2" )"
"$BIN" "$FIX" "$FIX2" "--situ=$GOOD" --no-cache >"$FIX2.out" 2>"$FIX2.err"; rc=$?
[ "$rc" -eq 0 ] && ok "G two roots, --situ=$GOOD (lives in root 1) → exit 0 (the selector resolves in the workspace)" \
                || no "G two roots, --situ=$GOOD → exit $rc: $( head -c 200 "$FIX2.err" )"
SEC2="$( awk -v lbl="=== root $LBL2 " 'index($0, lbl)==1 {on=1; next} /^=== root /{on=0} on' "$FIX2.out" )"
if [ -z "$SEC2" ]; then
    no "G presence guard — no section for root $LBL2 in the multi-root answer: $( head -c 300 "$FIX2.out" )"
else
    case "$SEC2" in
        *"no changed files in this root"*) no "G root $LBL2 prints \"(no changed files in this root)\" for a selector that names nothing under it — a false zero (an empty diff is a measurement; a selector that does not name this root is not): $SEC2" ;;
        *) ok "G root $LBL2 does not print the empty-diff sentence for a selector that names nothing under it" ;;
    esac
    printf '%s' "$SEC2" | grep -qF -- "--situ=$GOOD" && printf '%s' "$SEC2" | grep -q 'names no indexed file under this root' \
        && ok "G root $LBL2 says the SELECTOR (--situ=$GOOD) names no indexed file under this root" \
        || no "G root $LBL2 does not attribute the empty section to the selector: $SEC2"
    printf '%s' "$SEC2" | grep -qF "$( basename "$FIX" )" \
        && ok "G root $LBL2 names the root(s) the selector's matches live under ($( basename "$FIX" ))" \
        || no "G root $LBL2 does not say where the selector's matches live: $SEC2"
fi
grep -q 'changed file(s)' "$FIX2.out" && ok "G root $( basename "$FIX" ) still answers for the file it holds" \
                                       || no "G the root that holds $GOOD did not answer: $( head -c 300 "$FIX2.out" )"
# the union miss keeps refusing for the whole workspace
"$BIN" "$FIX" "$FIX2" "--situ=$BAD" --no-cache >/dev/null 2>"$FIX2.err2"; rc=$?
[ "$rc" -ne 0 ] && grep -qF -- "--situ" "$FIX2.err2" && grep -qF "$BAD" "$FIX2.err2" \
    && ok "G two roots, --situ=$BAD (nowhere) → exit $rc, refusal names the flag and the path" \
    || no "G two roots, --situ=$BAD → exit $rc; the union refusal regressed: $( head -c 200 "$FIX2.err2" )"
rm -rf "$( dirname "$FIX2" )"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
