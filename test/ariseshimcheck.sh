#!/usr/bin/env bash
# ariseshimcheck.sh — smoke gate for bench/arise-h2h/swe_agent_bundle_ripwire/: every shim of the
# ARISE head-to-head bundle (docs/EVALS.md § "ARISE fault-localization head-to-head") executes the
# pinned binary and emits its verb's OWN output shape on a real corpus — a shim that silently maps
# to the wrong flag, drops an argument, or falls back to a PATH binary fails here, before any
# harness run can be poisoned by it.
#
# Arms:
#   (1) every shim present + executable + config.yaml lists exactly the shims that exist
#   (2) rw_for / rw_at / rw_expand / rw_callers / rw_callees / rw_impact emit their verbs' shapes
#   (3) rw_slice maps (file, line, variable, direction, depth) onto --slice/--at/--slice-flow
#   (4) rw_pack_task / rw_from_trace run end-to-end on task text / a pasted trace
#   (5) RIPWIRE_BIN unset = loud refusal (never a PATH fallback); bad direction refuses naming it
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/ariseshimcheck.sh   |   bash test/ariseshimcheck.sh path/to/ripwire

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
SHIMS="$ROOT/bench/arise-h2h/swe_agent_bundle_ripwire/bin"
CFG="$ROOT/bench/arise-h2h/swe_agent_bundle_ripwire/config.yaml"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"
cat > "$WORK/src/app.py" <<'EOF'
def helper(x):
    return x + 1

def process(seed):
    v = seed + 2
    w = helper(v)
    return w
EOF

echo "ariseshimcheck: BIN=$BIN"
export RIPWIRE_BIN="$BIN"

# ── (1) inventory: bin/ and config.yaml agree ───────────────────────────────────────────────────────
expected="rw_at rw_callees rw_callers rw_expand rw_for rw_from_trace rw_impact rw_pack_task rw_slice"
actual="$( ls "$SHIMS" | sort | tr '\n' ' ' | sed 's/ $//' )"
[ "$actual" = "$expected" ] && ok "(1) bin/ holds exactly the nine registered shims" \
    || no "(1) bin/ inventory drifted: got '$actual'"
missing=0
for s in $expected; do
    [ -x "$SHIMS/$s" ] || { missing=1; no "(1) $s is not executable"; }
    grep -q "^  $s:" "$CFG" || { missing=1; no "(1) $s has no config.yaml entry"; }
done
[ "$missing" = 0 ] && ok "(1) every shim is executable and documented in config.yaml"

# ── (2) the six navigation shims emit their verbs' shapes ───────────────────────────────────────────
"$SHIMS/rw_for" "$WORK" seed processing helper 2>/dev/null | grep -q '<ctx task="seed processing helper"' \
    && ok "(2) rw_for emits the --for lens with the query echoed" || no "(2) rw_for did not emit the <ctx> lens"
AT="$( "$SHIMS/rw_at" "$WORK" src/app.py 6 2>/dev/null )"
printf '%s' "$AT" | grep -q 'sym="process"' \
    && ok "(2) rw_at resolves the enclosing definition (sym=process at app.py:6)" \
    || { no "(2) rw_at did not name the enclosing definition"; printf '%s\n' "$AT" | head -2; }
"$SHIMS/rw_expand" "$WORK" process 2>/dev/null | grep -q 'w = helper(v)' \
    && ok "(2) rw_expand serves the body" || no "(2) rw_expand did not serve the body"
"$SHIMS/rw_expand" "$WORK" process 1 2 2>/dev/null | grep -q 'lines="1-2' \
    && ok "(2) rw_expand start/end maps to the SYM:A-B range slice" \
    || no "(2) rw_expand with a range did not emit the lines= slice marker"
"$SHIMS/rw_callers" "$WORK" helper 2>/dev/null | grep -q 'process' \
    && ok "(2) rw_callers finds the caller" || no "(2) rw_callers did not find process"
"$SHIMS/rw_callees" "$WORK" process 2>/dev/null | grep -q 'helper' \
    && ok "(2) rw_callees finds the callee" || no "(2) rw_callees did not find helper"
"$SHIMS/rw_impact" "$WORK" helper 2>/dev/null | grep -q 'process' \
    && ok "(2) rw_impact reaches the transitive caller" || no "(2) rw_impact did not reach process"

# ── (3) rw_slice maps the ARISE seed onto --slice/--at/--slice-flow ─────────────────────────────────
S="$( "$SHIMS/rw_slice" "$WORK" src/app.py 6 v 2>/dev/null )"
printf '%s' "$S" | grep -q 'flow="back"' && printf '%s' "$S" | grep -q 'var="v"' \
    && ok "(3) rw_slice defaults to a backward flow slice of the named variable" \
    || { no "(3) rw_slice default did not emit flow=\"back\" var=\"v\""; printf '%s\n' "$S" | head -2; }
"$SHIMS/rw_slice" "$WORK" src/app.py 5 v forward 3 2>/dev/null | grep -q 'flow="fwd" depth="3"' \
    && ok "(3) rw_slice maps forward+depth onto --slice-flow=fwd --slice-depth=3" \
    || no "(3) rw_slice forward/depth mapping broken"

# ── (4) the two composite shims run end-to-end ──────────────────────────────────────────────────────
"$SHIMS/rw_pack_task" "$WORK" fix the helper increment for seed processing 2>/dev/null | grep -q '<bodies' \
    && ok "(4) rw_pack_task emits the one-call bundle (bodies section present)" || no "(4) rw_pack_task did not emit the bundle's bodies section"
T="$( "$SHIMS/rw_from_trace" "$WORK" 'Traceback (most recent call last):
  File "src/app.py", line 6, in process
    w = helper(v)
  File "src/app.py", line 2, in helper
    return x + 1
TypeError: unsupported operand' 2>/dev/null )"
printf '%s' "$T" | grep -q 'helper' \
    && ok "(4) rw_from_trace maps the pasted trace to the innermost in-corpus symbol" \
    || { no "(4) rw_from_trace did not surface helper"; printf '%s\n' "$T" | head -2; }

# ── (5) refusals are loud, never a PATH fallback ────────────────────────────────────────────────────
msg="$( env -u RIPWIRE_BIN "$SHIMS/rw_for" "$WORK" anything 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$msg" | grep -q 'RIPWIRE_BIN' \
    && ok "(5) unset RIPWIRE_BIN refuses loudly naming the variable (rc=$rc)" \
    || no "(5) unset RIPWIRE_BIN must fail naming RIPWIRE_BIN (rc=$rc: $msg)"
dmsg="$( "$SHIMS/rw_slice" "$WORK" src/app.py 6 v sideways 2>&1 )"; drc=$?
[ "$drc" -ne 0 ] && printf '%s' "$dmsg" | grep -q "backward|forward|both" \
    && ok "(5) a bad direction refuses naming the legal set" \
    || no "(5) rw_slice accepted direction 'sideways' (rc=$drc)"

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
