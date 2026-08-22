#!/usr/bin/env bash
# deadfiltercheck.sh — §P0.3 gate: --dead-code=DIR must scope, not silently return zero.
#
# The filter was a bare path SUFFIX test, so it could only match a FILENAME. Every directory argument
# produced `count="0" confidence="high" evidence="internal-linkage+zero-callers"` — the tool asserting
# high confidence about a directory it never established exists — and a typo'd directory was
# byte-identical to a real one:
#   --dead-code=test  -> 0   (the dir holding 2 of the 3)
#   --dead-code=bench -> 0   (the dir holding the 3rd)
#   --dead-code=nosuchdir -> 0, exit 0, stderr empty
#
# Invariants frozen here: a directory filter SELECTS (its counts sum back to the unfiltered total), a
# filename filter still works, and a filter naming nothing in the tree REFUSES instead of measuring zero.
#
#   RIPWIRE_BIN=build/ripwire      bash test/deadfiltercheck.sh
#   RIPWIRE_BIN=build_base/ripwire bash test/deadfiltercheck.sh   # must FAIL (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "deadfiltercheck: BIN=$BIN  ROOT=$ROOT"

deadCount(){ "$BIN" "$ROOT" "$@" 2>/dev/null | grep -oE '<dead-code count="[0-9]+"' | grep -oE '[0-9]+'; }

BARE="$( deadCount --dead-code )"
[ "${BARE:-0}" -ge 3 ] && ok "bare --dead-code: count=$BARE" || no "bare --dead-code: count=${BARE:-<none>} (expected >= 3)"

# ── 1. a DIRECTORY filter selects the symbols under it (2 in test/, 1 in bench/ on this repo)
T="$( deadCount --dead-code=test )"
[ "${T:-0}" -ge 2 ] && ok "--dead-code=test: count=$T (>= 2)" || no "--dead-code=test: count=${T:-<none>} (expected >= 2)"
B="$( deadCount --dead-code=bench )"
[ "${B:-0}" -ge 1 ] && ok "--dead-code=bench: count=$B (>= 1)" || no "--dead-code=bench: count=${B:-<none>} (expected >= 1)"

# a trailing slash is the same directory
TS="$( deadCount --dead-code=test/ )"
[ "${TS:-x}" = "${T:-y}" ] && ok "--dead-code=test/ == --dead-code=test ($TS)" || no "--dead-code=test/ = ${TS:-<none>} != ${T:-<none>}"

# ── 2. the parts never exceed the whole (a filter SELECTS, it does not invent findings)
[ $(( ${T:-0} + ${B:-0} )) -le "${BARE:-0}" ] \
    && ok "test+bench ($(( ${T:-0} + ${B:-0} ))) <= unfiltered total ($BARE)" \
    || no "filtered counts $(( ${T:-0} + ${B:-0} )) exceed the unfiltered total ${BARE:-<none>}"

# ── 3. the FILENAME form must keep working (it is the one shape the old suffix test got right)
F="$( deadCount --dead-code=deadfix.cpp )"
[ "${F:-0}" -ge 1 ] && ok "--dead-code=deadfix.cpp: count=$F (filename form still matches)" \
    || no "--dead-code=deadfix.cpp: count=${F:-<none>} (expected >= 1)"

# ── 4. a filter matching NO indexed path refuses loudly — never a confident zero
"$BIN" "$ROOT" --dead-code=nosuchdir >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" -eq 1 ] && ok "--dead-code=nosuchdir exits 1" || no "--dead-code=nosuchdir exits $rc (expected 1)"
grep -q 'nosuchdir' "$TMP/err" && ok "refusal names the filter" || no "refusal does not name the filter: $( head -c 200 "$TMP/err" )"
grep -q 'count=' "$TMP/out" && no "refusal still printed a <dead-code count=> element" || ok "no count= element on the refusal path"

# a directory-boundary near-miss must also refuse rather than prefix-match loosely
"$BIN" "$ROOT" --dead-code=sr >/dev/null 2>"$TMP/err2"; rc2=$?
[ "$rc2" -eq 1 ] && ok "--dead-code=sr (partial component) refuses" || no "--dead-code=sr exits $rc2 (expected 1 — 'sr' is not a path component)"

# ── 5. a REAL indexed directory that simply holds no dead code stays a MEASUREMENT (exit 0, count="0").
#      The refusal must fire on "names nothing in the tree", never on "found nothing there".
"$BIN" "$ROOT" --dead-code=scripts >"$TMP/tp" 2>/dev/null; rc3=$?
[ "$rc3" -eq 0 ] && grep -q '<dead-code count="0"' "$TMP/tp" \
    && ok "--dead-code=scripts (real dir, no dead code) exits 0 with count=\"0\" — a measurement" \
    || no "--dead-code=scripts exits $rc3 without a count=\"0\" measurement"

# ── 7. §A10.6: a LEADING ./ anchors the filter at the repo ROOT — ./src matches only the top-level
#      src/ subtree, never test/archmetricsfix/src/... (an interior src/ component a bare `src` also,
#      correctly, matches). The archmetricsfix fixture holds exactly one dead-code candidate
#      (orphan/util.cpp::unused_helper) purpose-built for this — the real top-level src/ has none.
ANCHORED_PATHS="$( "$BIN" "$ROOT" --dead-code=./src 2>/dev/null | grep -oE 'p="[^"]*"' )"
echo "$ANCHORED_PATHS" | grep -q 'archmetricsfix' \
    && no "--dead-code=./src wrongly includes the interior test/archmetricsfix/src/... path" \
    || ok "--dead-code=./src excludes the interior test/archmetricsfix/src/... path (root-anchored)"

BARE_PATHS="$( "$BIN" "$ROOT" --dead-code=src 2>/dev/null | grep -oE 'p="[^"]*"' )"
echo "$BARE_PATHS" | grep -q 'archmetricsfix' \
    && ok "--dead-code=src (bare) still matches the interior test/archmetricsfix/src/... path (component semantics unchanged)" \
    || no "--dead-code=src (bare) no longer matches the interior fixture path — component semantics regressed"

# ── 6. determinism
"$BIN" "$ROOT" --dead-code=test >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT" --dead-code=test >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "deterministic (byte-identical run-to-run)" || no "non-deterministic --dead-code output"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
