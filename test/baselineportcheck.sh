#!/usr/bin/env bash
# baselineportcheck.sh — gate test for S2: the baseline sidecars are ROOT-SPELLING PORTABLE.
#
# The bug (reproduced): both `.ripwire_arch_baseline` and
# `.ripwire_quality_baseline` used to hash the RAW ingest-root path prefix. A baseline written via
# `ripwire .` then failed enforcement when the same repo was scanned via an ABSOLUTE root path
# (`ripwire /abs/repo`) — the hashes embedded `./src/x` vs `/abs/repo/src/x`, so the committed baseline
# broke for any teammate/CI with a different root spelling (exit 0 vs exit 2; phantom quality regressions).
#
# The fix hashes ROOT-RELATIVE paths (relForHash) inside the baseline hash paths ONLY — canonId/`id=` and
# the default map are untouched. This gate proves the portability both ways:
#
#   ARCH:    write baseline via `ripwire .` --baseline, then enforce via BOTH `ripwire .` and
#            `ripwire "$PWD"` (absolute). With NO new violation, BOTH must exit 0. (On the pre-fix binary
#            the absolute form exits 2 — this gate FAILS on it, so it is the executable spec.)
#   QUALITY: write baseline via `ripwire .` --quality-baseline, then `--quality-delta` from BOTH the
#            relative and the absolute root spelling → BOTH must report zero regressions / exit 0.
#
# Self-mutation test at the end: temporarily corrupt one root spelling's expectation to confirm the gate
# actually distinguishes portable from non-portable (a green-no-matter-what gate is worthless).
#
# Usage:
#   bash test/baselineportcheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/baselineportcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN

fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "baselineportcheck: BIN=$BIN"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# PART A — ARCH baseline portability
# ════════════════════════════════════════════════════════════════════════════════════════════════════
# Reuse the arch fixture (2 deterministic layering violations: game/*.cpp include infra/allocator.h,
# violating `deny game -> infra`). We do NOT add a new violation — with the baseline present, EVERY root
# spelling must suppress all violations and exit 0.
ARCH_FIXTURE="$ROOT/test/baselinefix"
TMPA="$( mktemp -d )"; trap 'rm -rf "$TMPA"' EXIT
WORK="$TMPA/baselinefix"
cp -R "$ARCH_FIXTURE" "$WORK"
cd "$WORK"

# write the baseline via the RELATIVE root spelling ('.')
"$BIN" . --arch=rules.txt --baseline --no-cache >/dev/null 2>"$TMPA/a_base.err"
rc=$?
if [ "$rc" -eq 0 ] && [ -f .ripwire_arch_baseline ]; then
    ok "arch: baseline written via 'ripwire .' (exit 0, sidecar present)"
else
    no "arch: baseline write via '.' failed (exit $rc)"; cat "$TMPA/a_base.err"
fi

# enforce via the SAME relative spelling → exit 0 (baseline established under '.')
"$BIN" . --arch=rules.txt --no-cache >/dev/null 2>"$TMPA/a_rel.err"
rc_rel=$?
if [ "$rc_rel" -eq 0 ]; then
    ok "arch: enforce via 'ripwire .' exits 0 (all violations baselined)"
else
    no "arch: enforce via '.' expected exit 0, got $rc_rel — $(cat "$TMPA/a_rel.err")"
fi

# enforce via the ABSOLUTE spelling ($PWD) → MUST ALSO exit 0. This is the bug: pre-fix, this exits 2.
"$BIN" "$PWD" --arch=rules.txt --no-cache >/dev/null 2>"$TMPA/a_abs.err"
rc_abs=$?
if [ "$rc_abs" -eq 0 ]; then
    ok "arch: enforce via absolute 'ripwire \$PWD' exits 0 (PORTABLE — was exit 2 pre-fix)"
else
    no "arch: enforce via absolute \$PWD expected exit 0, got $rc_abs — baseline NOT portable"
    echo "        stderr: $(cat "$TMPA/a_abs.err")"
fi

# enforce via the ABSOLUTE spelling WITH A TRAILING SLASH → still exit 0 (root normalization).
"$BIN" "$PWD/" --arch=rules.txt --no-cache >/dev/null 2>"$TMPA/a_slash.err"
rc_slash=$?
if [ "$rc_slash" -eq 0 ]; then
    ok "arch: enforce via 'ripwire \$PWD/' (trailing slash) exits 0"
else
    no "arch: enforce via '\$PWD/' expected exit 0, got $rc_slash — $(cat "$TMPA/a_slash.err")"
fi

# sanity: a genuinely NEW violation must STILL be caught under the absolute spelling (the fix must not
# have made the baseline suppress everything). Add game/enemy.cpp → exit 2 under $PWD.
cp "$ARCH_FIXTURE/game/enemy.cpp.NEW" "$WORK/game/enemy.cpp"
"$BIN" "$PWD" --arch=rules.txt --no-cache >"$TMPA/a_new.xml" 2>/dev/null
rc_new=$?
if [ "$rc_new" -eq 2 ] && grep -q 'new_violations="1"' "$TMPA/a_new.xml"; then
    ok "arch: a genuinely NEW violation still trips exit 2 under absolute root (fix didn't over-suppress)"
else
    no "arch: new violation under absolute root expected exit 2 + new_violations=\"1\", got exit $rc_new"
fi
rm -f "$WORK/game/enemy.cpp"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# PART B — QUALITY baseline portability
# ════════════════════════════════════════════════════════════════════════════════════════════════════
# Build a tiny fixture with a SCOPED dead-candidate (a class method with a body, no callers, in a .cpp).
# A scoped symbol's canonical id is `path::scope::name`, so it embeds the path — exactly the case the raw
# prefix used to poison. (A FREE function's canonId is the bare name with no path, so it was already
# portable and would not exercise the bug.)
QWORK="$TMPA/qual"
mkdir -p "$QWORK/src"
cat > "$QWORK/src/main.cpp" <<'EOF'
#include "lib.h"
int main() { return usedFunc( 3 ); }
EOF
cat > "$QWORK/src/lib.h" <<'EOF'
int usedFunc( int x );
EOF
cat > "$QWORK/src/lib.cpp" <<'EOF'
#include "lib.h"
int usedFunc( int x ) { return x + 1; }
struct Widget
{
    int orphanMethod( int x )
    {
        int t = 0;
        for( int i = 0; i < x; ++i ) t += i;
        return t;
    }
};
EOF
cd "$QWORK"

# write the quality baseline via the RELATIVE root spelling
"$BIN" . --quality-baseline --no-cache >/dev/null 2>"$TMPA/q_base.err"
rc_qb=$?
if [ "$rc_qb" -eq 0 ] && [ -f .ripwire_quality_baseline ]; then
    ok "quality: baseline written via 'ripwire .' (exit 0, sidecar present)"
else
    no "quality: baseline write via '.' failed (exit $rc_qb)"; cat "$TMPA/q_base.err"
fi

# the baseline must actually contain a scoped record (else the test proves nothing about path-portability)
if grep -q '^dead ' .ripwire_quality_baseline || grep -q '^ccx ' .ripwire_quality_baseline; then
    ok "quality: baseline captured symbol records (scoped canonId path is exercised)"
else
    no "quality: baseline has no ccx/dead records — fixture did not produce a scoped symbol"
    grep -v '^#' .ripwire_quality_baseline | head
fi

# --quality-delta via the SAME relative spelling → zero regressions, exit 0
"$BIN" . --quality-delta --no-cache >"$TMPA/q_rel.xml" 2>/dev/null
rc_qrel=$?
if [ "$rc_qrel" -eq 0 ] && grep -q 'regressions="0"' "$TMPA/q_rel.xml"; then
    ok "quality: delta via 'ripwire .' — zero regressions, exit 0"
else
    no "quality: delta via '.' expected 0 regressions/exit 0, got exit $rc_qrel ($(grep -o 'regressions="[0-9]*"' "$TMPA/q_rel.xml"))"
fi

# --quality-delta via the ABSOLUTE spelling → MUST ALSO be zero regressions, exit 0. Pre-fix: phantom
# regressions + exit 2.
"$BIN" "$PWD" --quality-delta --no-cache >"$TMPA/q_abs.xml" 2>/dev/null
rc_qabs=$?
if [ "$rc_qabs" -eq 0 ] && grep -q 'regressions="0"' "$TMPA/q_abs.xml"; then
    ok "quality: delta via absolute 'ripwire \$PWD' — zero regressions, exit 0 (PORTABLE — was exit 2 pre-fix)"
else
    no "quality: delta via absolute \$PWD expected 0 regressions/exit 0, got exit $rc_qabs ($(grep -o 'regressions="[0-9]*"' "$TMPA/q_abs.xml")) — baseline NOT portable"
fi

# --quality-delta via ABSOLUTE + trailing slash → still zero regressions
"$BIN" "$PWD/" --quality-delta --no-cache >"$TMPA/q_slash.xml" 2>/dev/null
rc_qslash=$?
if [ "$rc_qslash" -eq 0 ] && grep -q 'regressions="0"' "$TMPA/q_slash.xml"; then
    ok "quality: delta via 'ripwire \$PWD/' (trailing slash) — zero regressions, exit 0"
else
    no "quality: delta via '\$PWD/' expected 0 regressions/exit 0, got exit $rc_qslash"
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# MUTATION TEST — prove the gate is LIVE (not vacuously green): a corrupted baseline MUST surface a
# regression. The `.ripwire_quality_baseline` sidecar is CWD-relative, so the real portability scenario is
# "same committed sidecar, differing root ARG spelling" — which PART B above exercises. Here we instead
# mutate the sidecar itself to a wrong hash and confirm --quality-delta then DOES report the dead-code
# regression + exit 2. If it stayed green with a corrupted baseline, the portability PASSes would be
# meaningless.
cd "$QWORK"
grep -v '^dead ' .ripwire_quality_baseline > "$TMPA/q_bl.tmp"
printf 'dead ffffffffffffffff\n' >> "$TMPA/q_bl.tmp"     # a hash that matches NO current dead candidate
cp "$TMPA/q_bl.tmp" .ripwire_quality_baseline
"$BIN" . --quality-delta --no-cache >"$TMPA/q_neg.xml" 2>/dev/null
rc_qneg=$?
if [ "$rc_qneg" -eq 2 ] && grep -q 'kind="dead-code"' "$TMPA/q_neg.xml"; then
    ok "mutation: a corrupted baseline hash DOES surface a dead-code regression + exit 2 (gate is live)"
else
    no "mutation: corrupted baseline did not trip a regression (exit $rc_qneg) — gate may be vacuous"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi
exit "$fail"
