#!/usr/bin/env bash
# registermacrocheck.sh — P2.2 (agent-friction round, 2026-08-29) gate: self-registering test/benchmark
# macros must never surface as dead-code.
#
# THE DEFECT THIS PINS. A doctest/Catch2 TEST_CASE (and a GoogleTest TEST/TEST_F/TEST_P, and a Google
# Benchmark BENCHMARK) registers itself through a STATIC INITIALIZER at file scope — invisible to the
# name-based call graph. Before this fix, isDeadCandidate's zero-in-edges evidence flagged every one of
# them, so --quality-delta reported the whole file as `dead-code origin="new-symbol"` rows the moment an
# agent added a test (an orchestrated multi-agent authorship wave: the single most repeated
# --quality-delta false positive, three separate task gates). A SECOND, independently found bug: the
# --dead-code verb's own
# `static`-token precondition scans the SIGNATURE TEXT, which for a doctest/Catch2 title INCLUDES the
# title string — a TEST_CASE titled "...static..." was reported as high-confidence dead-code even before
# any quality-delta involvement (arm 3 below).
#
# THE FIX. quality.h's isDeadCandidate now also excludes a symbol whose OWN signature text (read at
# sigStartByte — the same byte for both extraction shapes, see quality.h's P2.2 comment block) begins
# with a REGISTERED macro name immediately followed by '(': a built-in list (doctest/Catch2's TEST_CASE
# family, GoogleTest's TEST/TEST_F/TEST_P, Google Benchmark's BENCHMARK family) plus whatever a repo's
# OWN `.ripwire_config` adds via `register_macros = NAME[, NAME...]` (a brand-new sidecar — no config
# parser existed in this codebase before this round). The exemption is DISCLOSED, never silent: both
# --dead-code and --quality-delta always print `register-macro-excluded="N"` (0 included, never omitted)
# and both header comments define the attribute in `name=` form (legendcoveragecheck.sh's convention).
#
# ARMS:
#   1. FULL MACRO FAMILY (--quality-delta) — doctest TEST_CASE/TEST_CASE_FIXTURE/SCENARIO + GoogleTest
#      TEST/TEST_F/TEST_P + Google Benchmark BENCHMARK, added uncommitted against a baseline that has
#      none of them: ZERO dead-code rows for any of the seven, register-macro-excluded="7", and a
#      genuinely-dead static helper added in the SAME diff still flags (the true-positive control).
#   2. STATIC-TITLE PRECISION BUG (--dead-code, no git needed) — a TEST_CASE titled with the literal word
#      "static" must not appear; a genuinely-dead static function in the same file still does.
#   3. CONFIG EXTENSION, negative control (--quality-delta, NO .ripwire_config) — a custom identifier-arg
#      macro NOT in the built-in list is NOT exempt: it flags as dead-code exactly like ordinary code,
#      proving the built-in list alone does not cover it (so arm 4's rescue is the config, not a fluke).
#   4. CONFIG EXTENSION, positive (--quality-delta, WITH .ripwire_config) — the SAME custom macro,
#      registered via `register_macros=`, is exempt; a SECOND, still-unregistered custom macro in the
#      same diff still flags — the config adds exactly the one name it lists, not "any macro-shaped call".
#   5. DISCLOSURE — both verbs' header comments define register-macro-excluded= (legendcoveragecheck's
#      `name=` convention), and neither ever OMITS the attribute (0 is printed, not absent).
#   6. HYGIENE — determinism (two runs byte-identical) and well-formed XML.
#
# Usage:
#   bash test/registermacrocheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/registermacrocheck.sh
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolutize BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  registermacrocheck (git not available)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "registermacrocheck: BIN=$BIN  (temp corpora)"

newrepo(){ mkdir -p "$1" && ( cd "$1" && git init -q && git config user.email t@t && git config user.name t ); }
commit(){ ( cd "$1" && git add -A >/dev/null 2>&1 && git commit -qm "$2" >/dev/null 2>&1 ); }

# ── ARM 1: the full macro family, via --quality-delta ──────────────────────────────────────────────────
A1="$WORK/a1"; newrepo "$A1"
cat > "$A1/sample.cpp" <<'EOF'
#include <cstdio>

static void liveHelper()
{
    std::printf( "called from tests\n" );
}

int main()
{
    liveHelper();
    return 0;
}
EOF
commit "$A1" "baseline: no tests yet"
cat > "$A1/sample.cpp" <<'EOF'
#include <cstdio>

static void trulyDeadHelper()
{
    std::printf( "never called\n" );
}

static void liveHelper()
{
    std::printf( "called from tests\n" );
}

TEST_CASE( "doctest handles the basic contract" )
{
    liveHelper();
}

TEST_CASE_FIXTURE( MyFixture, "fixture-scoped case" )
{
    liveHelper();
}

SCENARIO( "a bdd-style scenario" )
{
    liveHelper();
}

TEST( MySuite, MyGtestCase )
{
    liveHelper();
}

TEST_F( MyFixtureSuite, AnotherCase )
{
    liveHelper();
}

TEST_P( MyParamSuite, ParamCase )
{
    liveHelper();
}

BENCHMARK( MyBenchmark )
{
    liveHelper();
}

int main()
{
    liveHelper();
    return 0;
}
EOF
QD1="$( cd "$A1" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
for sym in "doctest handles the basic contract" "fixture-scoped case" "a bdd-style scenario" TEST TEST_F TEST_P BENCHMARK; do
    printf '%s' "$QD1" | grep -q "kind=\"dead-code\" sym=\"$sym\"" \
        && no "arm1: '$sym' wrongly reported as dead-code" \
        || ok "arm1: '$sym' correctly excluded from dead-code"
done
printf '%s' "$QD1" | grep -q 'kind="dead-code" sym="trulyDeadHelper"' \
    && ok "arm1: trulyDeadHelper still flagged (true positive preserved)" \
    || { no "arm1: trulyDeadHelper missing — true-positive detection regressed"; printf '%s\n' "$QD1"; }
printf '%s' "$QD1" | grep -q 'register-macro-excluded="7"' \
    && ok "arm1: register-macro-excluded=\"7\" (all seven macro bodies counted)" \
    || { no "arm1: register-macro-excluded count wrong"; printf '%s\n' "$QD1" | grep -oE 'register-macro-excluded="[0-9]*"'; }
printf '%s' "$QD1" | grep -q 'regressions="1"' \
    && ok "arm1: regressions=\"1\" (only the genuine dead helper)" \
    || { no "arm1: regressions count wrong (macro bodies leaked into the count)"; printf '%s\n' "$QD1" | grep -oE 'regressions="[0-9]*"'; }

# ── ARM 2: the static-title precision bug, via --dead-code (no git needed) ─────────────────────────────
A2="$WORK/a2"; mkdir -p "$A2"
cat > "$A2/sample.cpp" <<'EOF'
#include <cstdio>

TEST_CASE( "verifies the static analyzer stays quiet" )
{
    std::printf( "uncalled\n" );
}

static void trulyDeadHelper()
{
    std::printf( "also uncalled\n" );
}

int main()
{
    return 0;
}
EOF
DC2="$( "$BIN" "$A2" --dead-code --no-cache 2>/dev/null )"
printf '%s' "$DC2" | grep -q 'n="verifies the static analyzer stays quiet"' \
    && no "arm2: the static-titled TEST_CASE wrongly appears in --dead-code" \
    || ok "arm2: the static-titled TEST_CASE is excluded (the precision bug this pins)"
printf '%s' "$DC2" | grep -q 'n="trulyDeadHelper"' \
    && ok "arm2: trulyDeadHelper still flagged (true positive preserved)" \
    || { no "arm2: trulyDeadHelper missing from --dead-code"; printf '%s\n' "$DC2"; }
printf '%s' "$DC2" | grep -q 'count="1"' \
    && ok "arm2: --dead-code count=\"1\" (only the genuine candidate)" \
    || { no "arm2: --dead-code count wrong"; printf '%s\n' "$DC2" | grep -oE 'count="[0-9]*"'; }
printf '%s' "$DC2" | grep -q 'register-macro-excluded="1"' \
    && ok "arm2: register-macro-excluded=\"1\"" \
    || { no "arm2: register-macro-excluded count wrong"; printf '%s\n' "$DC2" | grep -oE 'register-macro-excluded="[0-9]*"'; }

# ── ARM 3: config extension, NEGATIVE control (no .ripwire_config) ─────────────────────────────────────
A3="$WORK/a3"; newrepo "$A3"
cat > "$A3/sample.cpp" <<'EOF'
#include <cstdio>

static void liveHelper()
{
    std::printf( "x\n" );
}

int main()
{
    liveHelper();
    return 0;
}
EOF
commit "$A3" "baseline"
cat > "$A3/sample.cpp" <<'EOF'
#include <cstdio>

static void liveHelper()
{
    std::printf( "x\n" );
}

MY_CUSTOM_TEST( MySuite, MyCase )
{
    liveHelper();
}

int main()
{
    liveHelper();
    return 0;
}
EOF
QD3="$( cd "$A3" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$QD3" | grep -q 'kind="dead-code" sym="MY_CUSTOM_TEST"' \
    && ok "arm3: unregistered custom macro MY_CUSTOM_TEST correctly flags as dead-code (control)" \
    || { no "arm3: MY_CUSTOM_TEST should flag without a .ripwire_config entry"; printf '%s\n' "$QD3"; }

# ── ARM 4: config extension, POSITIVE (.ripwire_config registers ONLY MY_CUSTOM_TEST) ──────────────────
A4="$WORK/a4"; newrepo "$A4"
cat > "$A4/sample.cpp" <<'EOF'
#include <cstdio>

static void liveHelper()
{
    std::printf( "x\n" );
}

int main()
{
    liveHelper();
    return 0;
}
EOF
printf 'register_macros = MY_CUSTOM_TEST\n' > "$A4/.ripwire_config"
commit "$A4" "baseline + .ripwire_config"
cat > "$A4/sample.cpp" <<'EOF'
#include <cstdio>

static void liveHelper()
{
    std::printf( "x\n" );
}

MY_CUSTOM_TEST( MySuite, MyCase )
{
    liveHelper();
}

OTHER_CUSTOM_TEST( OtherSuite, OtherCase )
{
    liveHelper();
}

int main()
{
    liveHelper();
    return 0;
}
EOF
QD4="$( cd "$A4" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$QD4" | grep -q 'kind="dead-code" sym="MY_CUSTOM_TEST"' \
    && no "arm4: registered MY_CUSTOM_TEST wrongly still flags as dead-code" \
    || ok "arm4: .ripwire_config's register_macros= exempts MY_CUSTOM_TEST"
printf '%s' "$QD4" | grep -q 'kind="dead-code" sym="OTHER_CUSTOM_TEST"' \
    && ok "arm4: unregistered OTHER_CUSTOM_TEST still flags (config is narrow, not a blanket heuristic)" \
    || { no "arm4: OTHER_CUSTOM_TEST should still flag — config over-exempted"; printf '%s\n' "$QD4"; }
printf '%s' "$QD4" | grep -q 'register-macro-excluded="1"' \
    && ok "arm4: register-macro-excluded=\"1\" (only the registered name)" \
    || { no "arm4: register-macro-excluded count wrong"; printf '%s\n' "$QD4" | grep -oE 'register-macro-excluded="[0-9]*"'; }

# ── ARM 5: disclosure — legend defines the attribute (legendcoveragecheck's name= convention) ──────────
printf '%s' "$QD1" | grep -q 'register-macro-excluded=' \
    && ok "arm5: --quality-delta legend defines register-macro-excluded=" \
    || no "arm5: --quality-delta legend never defines register-macro-excluded="
printf '%s' "$DC2" | grep -q 'register-macro-excluded=' \
    && ok "arm5: --dead-code legend defines register-macro-excluded=" \
    || no "arm5: --dead-code legend never defines register-macro-excluded="

# ── ARM 6: hygiene — determinism + well-formed XML ──────────────────────────────────────────────────────
QD1b="$( cd "$A1" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
[ "$QD1" = "$QD1b" ] && ok "arm6: --quality-delta deterministic (byte-identical run-to-run)" \
    || no "arm6: --quality-delta non-deterministic output"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$QD1" | xmllint --noout - 2>/dev/null && ok "arm6: --quality-delta xml well-formed" || no "arm6: --quality-delta xml malformed"
    printf '%s' "$DC2" | xmllint --noout - 2>/dev/null && ok "arm6: --dead-code xml well-formed" || no "arm6: --dead-code xml malformed"
else
    ok "arm6: xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
