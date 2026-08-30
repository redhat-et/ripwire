#!/usr/bin/env bash
# redactfixcheck.sh — gate for the redactSecrets per-line / per-run memoization.
#
# WHY THIS GATE EXISTS. redactSecrets sweeps the emitted body left to right and, at every candidate
# position, used to (a) walk to both boundaries of the enclosing line, (b) rescan that whole line for the
# GenericAssigned keyword gate, and (c) run regex_search(match_continuous) on [A-Za-z0-9+/=_-]{32,} —
# a greedy class run, so each such call consumed the maximal run from the cursor. Every one of those is
# O(lineLength) or O(runLength) work done once PER POSITION, i.e. quadratic in the line. Ordinary source
# never notices; a minified or vendored bundle is nothing but hundred-kilobyte lines, and --expand's
# whole-file candidate hands exactly such a file to this function. Measured: babel__babel-13928's 2.1 MB /
# 768-line .yarn/releases/yarn-3.1.0.cjs took >200 s for ONE --expand selector, ~100% of it in
# redactSecrets. It was the only timeout the SWE-Explore harness ever hit.
#
# The fix memoizes all three: the line-gate verdict once per LINE, the class run's end once per RUN, and
# the GenericAssigned match itself becomes an arithmetic length test against that run end. Every one of
# those values was already position-independent, so this is pure memoization — same matches, same output
# bytes. The failure mode a memoization CAN have is a stale cache leaking across a boundary, and that is
# exactly what this gate pins: each arm below is a boundary the caches must not cross.
#
# THIS IS NOT A TIMING GATE. Per the house rule, performance is a ledger (bench/PROFILE.md), never a red
# CI threshold — a slow machine must not turn this red. The arms assert BEHAVIOUR only. A revert of the
# memoization would make this gate slow, not red; the guard against a revert is correctness, not a clock.
#
# The fixture is generated here rather than committed: the minified arm needs a 20 KB single line, which
# has no business in the repo as a checked-in file.
#
# Arms:
#   1. gate cache must not leak FORWARD  — a keyword-gated line followed by an ungated line with the same
#      32-char run: the first redacts, the second survives verbatim.
#   2. gate cache must not leak BACKWARD — an ungated line followed by a gated one: first survives, second
#      redacts. (Proves the cache is recomputed on entry to a new line in both directions of verdict.)
#   3. run-length boundary — 31 chars on a gated line survives, 32 redacts. Pins kGenericMinRunLength
#      against the "{32,}" in the pattern.
#   4. run cache must not leak across RUNS — two separate 32-char runs on one gated line both redact.
#   5. minified shape — a 20 KB single line: ungated leaves its trailing 32-run intact, gated redacts it.
#      Proves the caches survive a line long enough to have made the old sweep quadratic.
#   6. the run at end-of-input (no trailing newline) still redacts — pins the classRunEnd < N bound.
#   7. determinism — two runs byte-identical on stdout AND stderr.
#
# Usage: RIPWIRE_BIN=build/ripwire bash test/redactfixcheck.sh   (or: bash test/redactfixcheck.sh BIN)
# Exits non-zero on any failure. Does NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "redactfixcheck: BIN=$BIN"

# ── the generated fixture ───────────────────────────────────────────────────────────────────────────
# Every run below is a distinct repeated letter so an arm can be identified by a grep -F of the whole run;
# after redaction only the rule's 4-byte kept prefix survives, so the full run is absent iff it fired.
CORPUS="$TMP/corpus"
mkdir -p "$CORPUS"
python3 - "$CORPUS" <<'PY'
import pathlib, sys

out = pathlib.Path(sys.argv[1])
run = lambda ch, n=32: ch * n
long_line = "z9" * 10000          # 20 KB of class bytes on ONE line — the minified shape

doc = [
    "def redactfix_memo_boundary():",
    '    """',
    "    arm 1 - gate cache must not leak FORWARD (gated line, then ungated line)",
    f"    api_key: {run('A')}",
    f"    {run('B')}",
    "    arm 2 - gate cache must not leak BACKWARD (ungated line, then gated line)",
    f"    {run('C')}",
    f"    password: {run('D')}",
    "    arm 3 - run-length boundary on a gated line (31 survives, 32 redacts)",
    f"    secret: {run('E', 31)}",
    f"    secret: {run('F')}",
    "    arm 4 - two separate runs on one gated line, both redact",
    f"    token: {run('G')} {run('H')}",
    "    arm 5 - minified shape: a 20 KB single line, ungated then gated",
    f"    minified ungated: {long_line} {run('I')}",
    f"    token: {long_line} {run('J')}",
    '    """',
    "    return 0",
]
( out / "memofix.py" ).write_text( "\n".join( doc ) + "\n" )

# arm 6 - the last run ends at end-of-input with NO trailing newline.
( out / "eofrun.py" ).write_text( 'def redactfix_eof_run():\n    return "token: ' + run( 'K' ) + '"' )
PY

[ -f "$CORPUS/memofix.py" ] || { echo "fixture generation failed (python3 missing?)"; exit 2; }

"$BIN" "$CORPUS" --expand=redactfix_memo_boundary --no-cache >"$TMP/memo.xml" 2>"$TMP/memo.err"
rc=$?
[ $rc -eq 0 ] && ok "--expand on the memo fixture exits 0" || no "--expand on the memo fixture failed (rc=$rc)"

# survives(RUN, LABEL) — the full run must still be in the output verbatim.
survives(){
  if grep -qF "$1" "$TMP/memo.xml"; then ok "$2"; else no "OVER-REDACTION: $2"; fi
}
# redacted(RUN, LABEL) — the full run must be gone.
redacted(){
  if grep -qF "$1" "$TMP/memo.xml"; then no "MISSED REDACTION: $2"; else ok "$2"; fi
}

A=$( printf 'A%.0s' $(seq 32) ); B=$( printf 'B%.0s' $(seq 32) )
C=$( printf 'C%.0s' $(seq 32) ); D=$( printf 'D%.0s' $(seq 32) )
E=$( printf 'E%.0s' $(seq 31) ); F=$( printf 'F%.0s' $(seq 32) )
G=$( printf 'G%.0s' $(seq 32) ); H=$( printf 'H%.0s' $(seq 32) )
I=$( printf 'I%.0s' $(seq 32) ); J=$( printf 'J%.0s' $(seq 32) )
K=$( printf 'K%.0s' $(seq 32) )

# ── 1) gate cache must not leak FORWARD ─────────────────────────────────────────────────────────────
redacted "$A" "arm1: the keyword-gated run redacts"
survives "$B" "arm1: the NEXT line's ungated run survives (gate verdict did not leak forward)"

# ── 2) gate cache must not leak BACKWARD ────────────────────────────────────────────────────────────
survives "$C" "arm2: the ungated run survives"
redacted "$D" "arm2: the NEXT line's gated run redacts (a false verdict did not stick)"

# ── 3) run-length boundary ──────────────────────────────────────────────────────────────────────────
survives "$E" "arm3: a 31-char run on a gated line survives (below the rule's minimum)"
redacted "$F" "arm3: a 32-char run on a gated line redacts (at the rule's minimum)"

# ── 4) run cache must not leak across runs ──────────────────────────────────────────────────────────
redacted "$G" "arm4: first of two runs on one gated line redacts"
redacted "$H" "arm4: second of two runs on the SAME gated line also redacts (run end recomputed)"

# ── 5) minified shape — 20 KB single line ───────────────────────────────────────────────────────────
survives "$I" "arm5: trailing run on a 20 KB UNGATED line survives"
redacted "$J" "arm5: trailing run on a 20 KB GATED line redacts"

# ── 6) a run that ends at end-of-input ──────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --expand=redactfix_eof_run --no-cache >"$TMP/eof.xml" 2>/dev/null
if grep -qF "$K" "$TMP/eof.xml"; then no "arm6: run at end-of-input (no trailing newline) was NOT redacted"; else ok "arm6: run at end-of-input redacts"; fi

# ── 7) determinism ──────────────────────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --expand=redactfix_memo_boundary --no-cache >"$TMP/memo2.xml" 2>"$TMP/memo2.err"
cmp -s "$TMP/memo.xml" "$TMP/memo2.xml" && ok "stdout byte-identical run to run" || no "stdout differs run to run"
cmp -s "$TMP/memo.err" "$TMP/memo2.err" && ok "stderr byte-identical run to run" || no "stderr differs run to run"

# the tally must report the redactions it actually made (7 gated runs: A D F G H J K — K is the other file)
grep -q 'redacted .* secret' "$TMP/memo.err" && ok "stderr redaction tally emitted" || no "no stderr redaction tally"

if [ $fail -eq 0 ]; then
  echo "ALL PASS"
else
  echo "SOME CHECKS FAILED"
fi
exit $fail
