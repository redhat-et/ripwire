#!/usr/bin/env bash
# flagscheck.sh — the field-notes §2 gate for --flags, the dark-content dashboard (src/darkflags.h).
#
#   test/flagscheck.sh
#   CTXPACK_BIN=asan/ctxpack test/flagscheck.sh
#
# The fixture test/flagsfix/ carries one instance of every case the verb has to get right:
#   FIXTURE_DARK_FEATURE   — #ifndef/#define 0, guards two regions          -> compile, dark, loc>0
#   FIXTURE_LIT_FEATURE    — #ifndef/#define 1 WITH a trailing comment      -> compile, NOT dark, default="1"
#   FIXTURE_CMAKE_DARK/LIT — option(... OFF|ON)                             -> cmake, dark / not dark
#   FIXTURE_OVERRIDE       — header says 0, CMakeLists says ON              -> cmake/ON wins, header as <also>
#   FIXTURE_ENV_SWITCH     — getenv("…") with a literal name                -> env, default unset
#   FIXTURE_UNREAD_FEATURE — declared, never tested                         -> ABSENT (a dead name, not a gate)
#   flagsfix_wiringFlags_h — a plain include guard (valueless #define)      -> ABSENT (else every header is a gate)
#   a getenv(computedName) — non-literal argument                           -> ABSENT (cannot be named)
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/flagsfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "flagscheck: BIN=$BIN  CORPUS=$CORPUS"

"$BIN" "$CORPUS" --flags --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --flags --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" && ok "determinism (byte-identical)" || no "--flags is non-deterministic"
F="$( cat "$TMP/a" )"

# §A10.5: files= is this verb's OWN harvest scan (source + CMakeLists it read looking for gates), a
# wider crawl than the map's indexed corpus — the two counts legitimately differ (map: 796, --flags: 799
# on the full repo) and the legend must say so, not leave the mismatch undisclosed.
printf '%s' "$F" | grep -q 'files= is THIS' \
    && ok "legend discloses files= as this verb's own harvest scan (§A10.5)" \
    || no "legend does not explain files= — undisclosed divergence from the map's files= count"

# gate_attr NAME ATTR -> the attribute value on that gate's element ("" if the gate is absent)
gate_attr(){ printf '%s' "$F" | tr '<' '\n' | grep "^gate name=\"$1\"" | sed -n "s/.* $2=\"\([^\"]*\)\".*/\1/p"; }
has_gate(){ printf '%s' "$F" | tr '<' '\n' | grep -q "^gate name=\"$1\""; }

# ── 1) the compile lane ───────────────────────────────────────────────────────────────────────────────
[ "$( gate_attr FIXTURE_DARK_FEATURE kind )" = "compile" ] && [ "$( gate_attr FIXTURE_DARK_FEATURE default )" = "0" ] \
    && [ "$( gate_attr FIXTURE_DARK_FEATURE dark )" = "1" ] \
    && ok "FIXTURE_DARK_FEATURE: compile / default 0 / dark" \
    || no "FIXTURE_DARK_FEATURE wrong (kind=$( gate_attr FIXTURE_DARK_FEATURE kind ) default=$( gate_attr FIXTURE_DARK_FEATURE default ) dark=$( gate_attr FIXTURE_DARK_FEATURE dark ))"

[ "$( gate_attr FIXTURE_DARK_FEATURE loc )" -gt 0 ] 2>/dev/null \
    && ok "FIXTURE_DARK_FEATURE sizes the code it guards (loc=$( gate_attr FIXTURE_DARK_FEATURE loc ))" \
    || no "FIXTURE_DARK_FEATURE guarded-LOC is 0 — the #if region accounting is broken"

# The trailing comment on `#define FIXTURE_LIT_FEATURE 1  // shipped ON` must not land in the default.
[ "$( gate_attr FIXTURE_LIT_FEATURE default )" = "1" ] && [ "$( gate_attr FIXTURE_LIT_FEATURE dark )" = "0" ] \
    && ok "FIXTURE_LIT_FEATURE: default is exactly \"1\" (trailing comment stripped), not dark" \
    || no "FIXTURE_LIT_FEATURE default = '$( gate_attr FIXTURE_LIT_FEATURE default )' (want 1)"

# ── 2) the cmake lane ─────────────────────────────────────────────────────────────────────────────────
[ "$( gate_attr FIXTURE_CMAKE_DARK kind )" = "cmake" ] && [ "$( gate_attr FIXTURE_CMAKE_DARK dark )" = "1" ] \
    && ok "FIXTURE_CMAKE_DARK: cmake option, OFF, dark" || no "FIXTURE_CMAKE_DARK wrong"
[ "$( gate_attr FIXTURE_CMAKE_LIT kind )" = "cmake" ] && [ "$( gate_attr FIXTURE_CMAKE_LIT dark )" = "0" ] \
    && ok "FIXTURE_CMAKE_LIT: cmake option, ON, not dark" || no "FIXTURE_CMAKE_LIT wrong"

# ── 3) the override rule — the actual bug the verb exists to catch ────────────────────────────────────
[ "$( gate_attr FIXTURE_OVERRIDE kind )" = "cmake" ] && [ "$( gate_attr FIXTURE_OVERRIDE default )" = "ON" ] \
    && ok "FIXTURE_OVERRIDE: the CMake default (ON) wins over the header's 0" \
    || no "FIXTURE_OVERRIDE headline = $( gate_attr FIXTURE_OVERRIDE kind )/$( gate_attr FIXTURE_OVERRIDE default ) (want cmake/ON)"

printf '%s' "$F" | tr '<' '\n' | grep -q 'also kind="compile" default="0" p="override.h"' \
    && ok "FIXTURE_OVERRIDE: the losing header gate is still shown as an <also> row (contradiction visible)" \
    || { no "FIXTURE_OVERRIDE missing its <also> row"; printf '%s' "$F" | tr '<' '\n' | grep 'also ' | head -3; }

# ── 4) the env lane ───────────────────────────────────────────────────────────────────────────────────
[ "$( gate_attr FIXTURE_ENV_SWITCH kind )" = "env" ] && [ "$( gate_attr FIXTURE_ENV_SWITCH default )" = "unset" ] \
    && ok "FIXTURE_ENV_SWITCH: env gate, default unset" || no "FIXTURE_ENV_SWITCH wrong"

# ── 5) the exclusions — what must NOT be reported ─────────────────────────────────────────────────────
has_gate FIXTURE_UNREAD_FEATURE && no "FIXTURE_UNREAD_FEATURE reported — a declared-but-never-tested name is not a gate" \
                                || ok "FIXTURE_UNREAD_FEATURE absent (declared, never read)"
has_gate flagsfix_wiringFlags_h && no "the include guard flagsfix_wiringFlags_h reported as a gate" \
                                || ok "include guards absent (valueless #define is not a gate)"
printf '%s' "$F" | grep -q 'name="dynamic"' && no "getenv(computedName) produced a gate named after the variable" \
                                            || ok "getenv with a non-literal argument produces no gate"

# ── 6) header counts agree with the rows actually emitted ─────────────────────────────────────────────
DECL="$( printf '%s' "$F" | sed -n 's/.*<flags gates="\([0-9]*\)".*/\1/p' )"
ROWS="$( printf '%s' "$F" | tr '<' '\n' | grep -c '^gate name=' )"
[ "$DECL" = "$ROWS" ] && ok "header gates=\"$DECL\" matches the $ROWS rows emitted" \
                      || no "header claims gates=$DECL but emitted $ROWS rows"

# ── 7) --flags=SUBSTR filters ─────────────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --flags=FIXTURE_OVERRIDE --no-cache 2>/dev/null | grep -q 'gates="1"' \
    && ok "--flags=SUBSTR narrows to the matching gate" || no "--flags=SUBSTR did not filter"

# ── 8) alias resolution: a gate defaulting to another gate's NAME inherits and rolls up ────────────────
"$BIN" "$ROOT/test/flagsaliasfix" --flags --no-cache >"$TMP/al" 2>/dev/null
if [ -d "$ROOT/test/flagsaliasfix" ]; then
    grep -q 'alias-of name="ALIASFIX_ALL"' "$TMP/al" \
        && ok "alias child records alias-of its master" || { no "alias child missing alias-of"; head -c 700 "$TMP/al"; }
    grep -q '<aliases n="2"' "$TMP/al" \
        && ok "alias master rolls up its 2 children" || { no "alias master roll-up wrong"; head -c 700 "$TMP/al"; }
    printf '%s' "$( cat "$TMP/al" )" | tr '<' '\n' | grep '^gate name="ALIASFIX_WALLS"' | grep -q 'dark="1"' \
        && ok "alias child inherits the master's dark default" || no "alias child did not inherit the master default"
fi

# ── 9) well-formed, minified XML (G4) ─────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/a" 2>/dev/null && ok "XML well-formed" || no "XML malformed"
else
    ok "xmllint unavailable — well-formedness skipped"
fi
[ "$( grep -c '' "$TMP/a" )" -le 1 ] && ok "output is minified (no stray newlines)" || no "output contains newlines outside CDATA"

# ── 10) an empty / gate-free corpus is a clean empty report, not a crash ──────────────────────────────
mkdir -p "$TMP/bare"; printf 'int main(){return 0;}\n' > "$TMP/bare/m.cpp"
"$BIN" "$TMP/bare" --flags --no-cache 2>/dev/null | grep -q 'gates="0"' \
    && ok "a gate-free corpus reports gates=0 and exits clean" || no "gate-free corpus did not report gates=0"

[ $fail -eq 0 ] && echo "flagscheck: ALL PASS" || echo "flagscheck: FAILURES"
exit $fail
