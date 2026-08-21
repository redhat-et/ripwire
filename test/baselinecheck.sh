#!/usr/bin/env bash
# baselinecheck.sh — gate test for S5-B: --arch --baseline / --baseline-update.
#
# Verifies the four-step adoption story:
#   (1) --arch=rules --baseline   → exit 0; sidecar written with 2 hashes
#   (2) re-run --arch=rules       → exit 0  (both violations suppressed by baseline)
#   (3) add a 3rd violation       → --arch=rules  → exit 2; only the new one is named
#   (4) --baseline-update         → exit 0; sidecar now has 3 hashes
#
# Uses a TEMP COPY of test/baselinefix so the sidecar never lands in the repo.
# The fixture (test/baselinefix/) produces exactly 2 arch violations:
#   game/player.cpp and game/world.cpp both include infra/allocator.h, violating `deny game -> infra`.
# A third source file (game/enemy.cpp.NEW) is copied in as game/enemy.cpp for step (3).
#
# Usage:
#   bash test/baselinecheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/baselinecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN

FIXTURE="$ROOT/test/baselinefix"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

# Work in a temp copy so the sidecar never pollutes the fixture or the repo.
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
WORK="$TMP/baselinefix"
cp -R "$FIXTURE" "$WORK"

RULES="$WORK/rules.txt"
SIDECAR="$WORK/.ripwire_arch_baseline"

echo "baselinecheck: BIN=$BIN  FIXTURE=$FIXTURE"

# Change into the work dir so ripwire resolves paths relative to it (consistent with archcheck.sh).
cd "$WORK"

# ── step 1: --baseline writes the sidecar and exits 0 ────────────────────────────────────────────
"$BIN" . --arch=rules.txt --baseline --no-cache >"$TMP/s1.xml" 2>"$TMP/s1.err"
rc_s1=$?
if [ "$rc_s1" -eq 0 ]; then
    ok "step 1: --arch --baseline exits 0"
else
    no "step 1: --arch --baseline expected exit 0, got $rc_s1"
fi

# Sidecar must exist
if [ -f "$SIDECAR" ]; then
    ok "step 1: sidecar written (.ripwire_arch_baseline exists)"
else
    no "step 1: sidecar missing (.ripwire_arch_baseline not created)"
fi

# Sidecar must contain exactly 2 hex hashes (one per violation)
hash_count=$( grep -cE '^[0-9a-f]{16}$' "$SIDECAR" 2>/dev/null || echo 0 )
if [ "$hash_count" -eq 2 ]; then
    ok "step 1: sidecar contains exactly 2 violation hashes"
else
    no "step 1: sidecar has $hash_count hash(es), expected 2"
    cat "$SIDECAR" 2>/dev/null | head -8
fi

# XML output must mark violations as baselined (baselined="1")
if grep -q 'baselined="1"' "$TMP/s1.xml" 2>/dev/null; then
    ok "step 1: XML marks violations as baselined"
else
    no "step 1: XML missing baselined=\"1\" attribute"
    head -3 "$TMP/s1.xml"
fi

# ── step 2: re-run without --baseline — both violations suppressed, exit 0 ───────────────────────
"$BIN" . --arch=rules.txt --no-cache >"$TMP/s2.xml" 2>"$TMP/s2.err"
rc_s2=$?
if [ "$rc_s2" -eq 0 ]; then
    ok "step 2: re-run with sidecar exits 0 (all violations baselined)"
else
    no "step 2: re-run with sidecar expected exit 0, got $rc_s2"
    cat "$TMP/s2.err"
fi

# XML must report new_violations="0"
if grep -q 'new_violations="0"' "$TMP/s2.xml" 2>/dev/null; then
    ok "step 2: XML reports new_violations=\"0\""
else
    no "step 2: XML missing new_violations=\"0\" (got: $(head -1 "$TMP/s2.xml"))"
fi

# ── step 3: add a 3rd violation — only the new one triggers exit 2 ───────────────────────────────
cp "$FIXTURE/game/enemy.cpp.NEW" "$WORK/game/enemy.cpp"
"$BIN" . --arch=rules.txt --no-cache >"$TMP/s3.xml" 2>"$TMP/s3.err"
rc_s3=$?
if [ "$rc_s3" -eq 2 ]; then
    ok "step 3: new violation triggers exit 2"
else
    no "step 3: expected exit 2 after adding new violation, got $rc_s3"
fi

# XML must report new_violations="1"
if grep -q 'new_violations="1"' "$TMP/s3.xml" 2>/dev/null; then
    ok "step 3: XML reports new_violations=\"1\" (only the new one)"
else
    no "step 3: XML new_violations count wrong (got: $(head -1 "$TMP/s3.xml"))"
fi

# The new violation (enemy.cpp) must appear WITHOUT baselined="1" on its <v> element.
# All <v> elements are compact XML on one line separated by the pattern `/>`. Split on the
# self-closing tag boundary and find the one that names enemy.cpp.
enemy_elem=$( tr '>' '\n' < "$TMP/s3.xml" 2>/dev/null | grep 'enemy.cpp' | head -1 )
if [ -n "$enemy_elem" ] && ! echo "$enemy_elem" | grep -q 'baselined'; then
    ok "step 3: enemy.cpp named as new (un-baselined) violation"
else
    no "step 3: enemy.cpp missing or incorrectly marked as baselined (elem: ${enemy_elem:-<not found>})"
fi

# ── step 4: --baseline-update merges the 3rd violation; exit 0 ───────────────────────────────────
"$BIN" . --arch=rules.txt --baseline-update --no-cache >"$TMP/s4.xml" 2>"$TMP/s4.err"
rc_s4=$?
if [ "$rc_s4" -eq 0 ]; then
    ok "step 4: --baseline-update exits 0"
else
    no "step 4: --baseline-update expected exit 0, got $rc_s4"
fi

# Sidecar must now contain 3 hashes
hash_count3=$( grep -cE '^[0-9a-f]{16}$' "$SIDECAR" 2>/dev/null || echo 0 )
if [ "$hash_count3" -eq 3 ]; then
    ok "step 4: sidecar now contains 3 violation hashes"
else
    no "step 4: sidecar has $hash_count3 hash(es), expected 3"
fi

# Verify the updated baseline suppresses all 3: re-run must exit 0
"$BIN" . --arch=rules.txt --no-cache >"$TMP/s4b.xml" 2>/dev/null
rc_s4b=$?
if [ "$rc_s4b" -eq 0 ]; then
    ok "step 4: post-update re-run exits 0 (all 3 violations suppressed)"
else
    no "step 4: post-update re-run expected exit 0, got $rc_s4b"
fi

# ── determinism: two runs (with sidecar present) produce byte-identical output ───────────────────
"$BIN" . --arch=rules.txt --no-cache >"$TMP/det_a.xml" 2>/dev/null || true
"$BIN" . --arch=rules.txt --no-cache >"$TMP/det_b.xml" 2>/dev/null || true
if diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null 2>&1; then
    ok "determinism: byte-identical output with baseline active"
else
    no "determinism: output differs between runs with baseline active"
    diff "$TMP/det_a.xml" "$TMP/det_b.xml" | head -8
fi

# ── summary ───────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
