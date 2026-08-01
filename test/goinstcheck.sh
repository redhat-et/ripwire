#!/usr/bin/env bash
# goinstcheck.sh — H4 (L-NEW lane) REJECT-fence: Go explicit generic instantiation.
#
# item 5 asked for `Generic[int](1)` (explicit generic
# instantiation, parses as type_conversion_expression, not call_expression) to be widened UNLESS
# the pattern cannot avoid matching something that is NOT a generic call — in which case an honest
# REJECT is an acceptable deliverable for Go only. It was rejected: verified with --match that
#   (type_conversion_expression type: (generic_type type: (type_identifier) @name))
# binds "Generic" on `Generic[int](1)` — but binds "fs" on ordinary index-then-call `fs[i](3)`
# (bench/h4fixtures/go2/conv.go) with the STRUCTURALLY IDENTICAL shape: `fs` and `i` parse as
# type_identifier nodes exactly like `Generic` and `int` do (tree-sitter has no type-system
# information to disambiguate a generic instantiation from an index expression on a slice/map of
# funcs). No .scm change shipped for Go; see the H4 comment block in queries/go/tags.scm for the
# full evidence trail. This is a FENCE, not a fix: it proves (1) the ambiguous shape was never
# shipped despite being investigated, and (2) index-then-call is never miscaptured as a call to
# the indexed variable's name — a future accidental widening attempt would trip this gate.
#
# Fixture test/goinstfix/main.go:
#   F()             — control: bare call (already captured)
#   Generic(1)       — control: type-inferred generic call (plain call_expression, already captured)
#   Generic[int](1)  — explicit instantiation: investigated, REJECTED, stays uncaptured
#   fs[i](3)         — index-then-call (inside take()): must NEVER appear as a call to "fs"
#
# Usage:  test/goinstcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/goinstcheck.sh   (probe follows BIN)
# Exits non-zero on any failure (i.e. on any DRIFT from the rejected/documented behavior).
# Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
# V1 MED-2 fix: honor the harness convention — regression.sh/pargates pass RIPWIRE_BIN only, so
# the probe is derived from the binary under test (house pattern, probecheck.sh), not a hardcoded
# build/ path that silently validates a stale tree.
PROBE="${RIPWIRE_PROBE:-${BIN}_probe}"
[ "${PROBE#/}" = "$PROBE" ] && PROBE="$ROOT/$PROBE"
FIX="$ROOT/test/goinstfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$PROBE" ] || { echo "no ripwire_probe binary at $PROBE — build first (cmake --build build -j)"; exit 2; }
echo "goinstcheck: PROBE=$PROBE  FIX=$FIX"

out="$( "$PROBE" "$FIX" 2>/dev/null )"

# ── caller(): F and Generic(1) (control, inferred) are captured; Generic[int](1) is NOT ─────────
callerline="$( printf '%s\n' "$out" | grep -A1 '\] caller' | tail -1 )"
case "$callerline" in
  *"calls: F Generic"*)
    if printf '%s' "$callerline" | grep -qE 'Generic.*Generic'; then
        no "caller unexpectedly calls 'Generic' TWICE — explicit instantiation is now being captured (widening shipped without updating this fence): $callerline"
    else
        ok "caller calls exactly 'F Generic' — explicit Generic[int](1) still uncaptured (rejected as designed): $callerline"
    fi
    ;;
  *) no "caller's raw refs unexpected (got: $callerline; want exactly 'calls: F Generic')" ;;
esac

# ── take(): fs[i](3) must never surface as a call to "fs" ────────────────────────────────────────
takeline="$( printf '%s\n' "$out" | grep -A1 '\] take' | tail -1 )"
if printf '%s' "$takeline" | grep -q 'calls:'; then
    no "take() unexpectedly has call refs (fs[i](3) index-then-call must stay uncaptured): $takeline"
else
    ok "take() has no call refs — fs[i](3) is not miscaptured as a call to 'fs'"
fi

# ── G/Generic/F/take symbols are all still captured as DEFS (fixture parses cleanly) ────────────
for sym in F G Generic take caller; do
    if printf '%s\n' "$out" | grep -qE "\] $sym +"; then ok "def $sym present"; else no "def $sym MISSING — fixture failed to parse"; fi
done

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
