#!/usr/bin/env bash
# tornreadcheck.sh — G-C: a torn read (file rewritten mid-parse) never crashes and self-heals.
#
# Regression fence (RESEARCH_agentQuality2026.md §3a / §3c): the audit reproduced that ctxpack's
# ingest is structurally self-healing against concurrent rewrites — the cache keys hash(bytes actually
# read)->facts(those bytes), so a torn read just produces a parse of SOME transient byte sequence,
# never a crash, and the NEXT whole read hashes differently and reparses cleanly. The audit's own
# repro was 77 runs vs 27k rewrites, zero crashes; this gate reproduces the same shape at a smaller,
# CI-friendly scale (deterministic invariant, not deterministic bytes — see below).
#
# Recipe (RESEARCH_agentQuality2026.md §3c "G-C"):
#   1. in a mktemp dir, background a writer loop that rapidly rewrites a .cpp file with varying
#      content (bounded iteration count so the gate finishes in well under a minute)
#   2. concurrently run `ctxpack <dir> --no-cache` ~60 times, asserting the exit code is never a
#      crash-range code (>= 128, i.e. killed by a signal) on EACH run
#   3. wait for the writer to finish
#   4. a FINAL `ctxpack <dir> | xmllint --noout -` must be clean — the tool converges to a valid
#      parse of whatever the file's resting content ends up being
#
# This is a RACE, not a deterministic-bytes test — we assert the INVARIANT (no crash, ever; final
# state is valid XML), never exact output bytes. Do not tighten this to byte-for-byte comparison.
#
# Usage:
#   bash test/tornreadcheck.sh
#   CTXPACK_BIN=asan/ctxpack bash test/tornreadcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "tornreadcheck: BIN=$BIN  TMP=$TMP"

WORK="$TMP/proj"
mkdir -p "$WORK"
printf 'int a0(){return 0;}\n' > "$WORK/f.cpp"

# ── background writer: rapidly rewrite f.cpp with varying (always-parseable) content ─────────────
# Bounded to a few thousand iterations so the whole gate stays well under a minute even on slow CI.
REWRITES=4000
(
    for i in $( seq 1 "$REWRITES" ); do
        printf 'int a%d(){return %d;}\n' $(( i % 3 )) "$i" > "$WORK/f.cpp" 2>/dev/null
    done
) &
WRITER_PID=$!

# ── foreground: ~60 concurrent ctxpack runs, asserting no crash-range exit code on ANY of them ───
RUNS=60
crash_count=0
crash_run=""
run=0
while [ "$run" -lt "$RUNS" ]; do
    run=$(( run + 1 ))
    "$BIN" "$WORK" --no-cache >/dev/null 2>"$TMP/run_${run}.err"
    rc=$?
    # >=128 conventionally means "killed by signal N-128" (segv, abrt, bus error, ...) — a crash.
    # Also treat 134 (SIGABRT from an ASan/UBSan trap under -fno-sanitize-recover) explicitly as a crash
    # (it's already covered by >=128, called out here for clarity).
    if [ "$rc" -ge 128 ]; then
        crash_count=$(( crash_count + 1 ))
        [ -z "$crash_run" ] && crash_run="$run (rc=$rc)"
    fi
done

if [ "$crash_count" -eq 0 ]; then
    ok "no crash across $RUNS concurrent runs during $REWRITES background rewrites"
else
    no "$crash_count/$RUNS run(s) crashed (first: run $crash_run) — torn-read self-heal REGRESSION"
    cat "$TMP/run_${crash_run%% *}.err" 2>/dev/null | head -20
fi

# ── wait for the writer to finish before asserting the final converged state ─────────────────────
wait "$WRITER_PID" 2>/dev/null

# ── final run on the now-settled file must be a clean, well-formed parse ─────────────────────────
"$BIN" "$WORK" >"$TMP/final.xml" 2>"$TMP/final.err"
rc_final=$?
if [ "$rc_final" -eq 0 ]; then
    ok "final run (post-writer, settled file) exits 0"
else
    no "final run expected exit 0, got $rc_final"
    cat "$TMP/final.err"
fi

command -v xmllint >/dev/null 2>&1 \
    && { xmllint --noout "$TMP/final.xml" 2>/dev/null \
         && ok "final run: xml well-formed (reparsed final state is valid)" \
         || { no "final run: xml malformed"; head -5 "$TMP/final.xml"; } ; } \
    || ok "final run: xml well-formed (xmllint absent — skipped)"

# The final content is one of the writer's known-good lines (int aN(){return M;}); confirm the tool
# extracted SOME aN symbol from it — proves it converged to a real parse, not an empty/degraded map.
if grep -qE 'n="a[0-9]+"' "$TMP/final.xml" 2>/dev/null; then
    ok "final run: settled symbol present (converged to a valid parse of final content)"
else
    no "final run: no aN symbol found — did not converge to a valid parse"
    head -5 "$TMP/final.xml"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
