#!/usr/bin/env bash
# localscountcheck.sh — Phase 1 of the local-variable-indexing plan (PLAN.md, "2026-08-06 (evening) —
# local-variable-indexing plan, orchestrated"): Symbol/RawDef gained a `locals` uint32_t FLOOR count,
# populated inside the ALREADY-EXISTING fused cc_walk complexity DFS (ingest.cpp) — C/C++ only (MVP scope,
# model.h::localsCountedLang). Emitted on `--metrics` as `locals="N" locals_floor="1"` (XML) /
# `"locals":N,"locals_floor":true` (JSON), NEVER a bare `locals="0"` for a language Phase 1 doesn't cover.
#
# ── WHAT THIS PINS ───────────────────────────────────────────────────────────────────────────────────
# The counting RULE (cc_isCountableLocalDecl, ingest.cpp): a `declaration` node whose PARENT is the
# enclosing `compound_statement` — i.e. a direct block-statement local. This ONE rule, with no per-shape
# special case, naturally excludes an if-init / switch-condition / for-init declarator (their parent is
# the control-structure node, not compound_statement) and a catch-clause exception declarator (parent is
# catch_clause; also a DIFFERENT node kind — parameter_declaration — in the vendored grammar). A
# structured-binding declarator (`auto [a,b] = …`) is excluded explicitly (cc_declHasStructuredBinding,
# a bounded-depth search — the vendored grammar nests it TWO levels below `declaration`, verified against
# a real parse-tree dump, not assumed): it IS a direct compound_statement child but introduces an unknown
# COUNT of names from one node, which is a MISCOUNTING risk (not the honest-undercounting the floor
# marker already discloses) — kept out on a different axis on purpose. A lambda init-capture
# (`[x = f()]{...}`) is never a `declaration` node at all, so it needs no special case either — arm 2
# below proves that absence empirically rather than assuming the grammar shape.
#
# ── ARMS ──────────────────────────────────────────────────────────────────────────────────────────────
#   0. PRESENCE       — the fixtures spell every shape the arms below claim to assert (green-while-inert
#                        guard).
#   1. COUNT           — three (in fact four) fixture functions with distinct HAND-COUNTED locals=: a
#                        single-constant-stub implementation cannot pass all of them.
#   2. FLOOR-BOUNDARY  — the five excluded declarator shapes (if-init, switch-condition, catch-clause,
#                        structured-binding, lambda-init-capture) contribute ZERO to locals=, while a
#                        real local sharing the same function DOES count (so the arm cannot pass by a
#                        rule that excludes everything).
#   3. LANGUAGE-OMISSION — a Python def with real locals emits NO locals=/locals_floor= at all (ABSENT,
#                        never a bare "0" — Phase 1 MVP scope is C/C++ only, model.h::localsCountedLang).
#   4. STALE-CACHE     — a --cache=PATH blob is built once, its on-disk parserVer field is corrupted to
#                        simulate a pre-bump blob, and a second run on the SAME cache path is proven to
#                        (a) emit a degrade note ("cache ... corrupt", never a silent misread) and
#                        (b) produce byte-identical stdout to the from-scratch run — the version guard
#                        rejects the stale blob and self-heals to a correct cold reparse.
#                        (a) is a DEGRADED_PATH_ALERT, so it is observable only on a non-NDEBUG build; on a
#                        Release binary the arm SKIPS with the flavour named, and CI's plain leg proves it.
#   5. HYGIENE         — two cold runs are byte-identical (determinism) and the map is well-formed XML.
#   6. JSON-PARITY      — --json carries the same locals=/locals_floor pair as XML, absent on the same
#                        language-omission fixture.
#
# Usage:
#   bash test/localscountcheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/localscountcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3  >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "localscountcheck: BIN=$BIN  TMP=$TMP"

CPPDIR="$TMP/cpp"; mkdir -p "$CPPDIR"
PYDIR="$TMP/py";   mkdir -p "$PYDIR"

cat >"$CPPDIR/locals.cpp" <<'EOF'
#include <stdexcept>
#include <utility>

// zero locals
int zeroLocals( int a, int b )
{
    return a + b;
}

// three direct locals
int threeLocals( int n )
{
    int x = 1;
    int y = 2;
    int z = x + y + n;
    return z;
}

// five direct locals (a second distinct count, so a stub that hardcodes "3" cannot pass both)
int fiveLocals( int n )
{
    int a = 1;
    int b = 2;
    int c = 3;
    int d = 4;
    int e = a + b + c + d + n;
    return e;
}

// excluded shapes: if-init, for-init, switch-condition, catch-clause, structured binding.
// real locals that DO count: the for-body local + the structured-binding source pair = 2.
int excludedShapes( int n )
{
    if( int r = n * 2; r > 0 )
    {
        return r;
    }
    for( int i = 0; i < n; ++i )
    {
        int body = i * 2;
        (void)body;
    }
    switch( int s = n % 3 )
    {
        case 0: break;
        default: break;
    }
    try
    {
        throw std::runtime_error( "x" );
    }
    catch( const std::exception& e )
    {
        (void)e;
    }
    auto pr = std::make_pair( 1, 2 );
    auto [ aa, bb ] = pr;
    (void)aa; (void)bb;
    return 0;
}

// lambda init-capture: `capd` must NOT count toward the ENCLOSING function's locals (it is never a
// `declaration` node at all); `base` and the lambda variable `lam` itself DO count = 2.
int lambdaInitCapture( int n )
{
    int base = n;
    auto lam = [ capd = base * 2 ]() { return capd; };
    return lam();
}
EOF

cat >"$PYDIR/m.py" <<'EOF'
def fn_with_locals( n ):
    x = 1
    y = 2
    return x + y + n
EOF

# ══ 0. PRESENCE ══════════════════════════════════════════════════════════════════════════════════════
presence(){ if grep -qF -- "$2" "$1"; then ok "presence: $3"; else no "presence: $3 — fixture drifted"; fi; }
presence "$CPPDIR/locals.cpp" 'if( int r = n * 2; r > 0 )'    'if-init present'
presence "$CPPDIR/locals.cpp" 'for( int i = 0; i < n; ++i )'  'for-init present'
presence "$CPPDIR/locals.cpp" 'switch( int s = n % 3 )'       'switch-condition present'
presence "$CPPDIR/locals.cpp" 'catch( const std::exception& e )' 'catch-clause present'
presence "$CPPDIR/locals.cpp" 'auto [ aa, bb ] = pr;'         'structured binding present'
presence "$CPPDIR/locals.cpp" 'capd = base * 2'               'lambda init-capture present'

xml(){ "$BIN" "$1" --metrics --no-cache 2>/dev/null; }
locals_of(){ # locals_of <xml> <fnname>
    printf '%s' "$1" | tr '>' '\n' | grep "n=\"$2\"" | grep -oE 'locals="[0-9]+"' | grep -oE '[0-9]+'
}

CPPXML="$( xml "$CPPDIR" )"

# ══ 1. COUNT ═════════════════════════════════════════════════════════════════════════════════════════
c_zero="$( locals_of "$CPPXML" zeroLocals )"
c_three="$( locals_of "$CPPXML" threeLocals )"
c_five="$( locals_of "$CPPXML" fiveLocals )"
[ "$c_zero" = "0" ]  && ok "count: zeroLocals -> locals=0"  || no "count: zeroLocals -> got '$c_zero', want 0"
[ "$c_three" = "3" ] && ok "count: threeLocals -> locals=3" || no "count: threeLocals -> got '$c_three', want 3"
[ "$c_five" = "5" ]  && ok "count: fiveLocals -> locals=5"  || no "count: fiveLocals -> got '$c_five', want 5"

# ══ 2. FLOOR-BOUNDARY ════════════════════════════════════════════════════════════════════════════════
c_excl="$( locals_of "$CPPXML" excludedShapes )"
[ "$c_excl" = "2" ] && ok "floor-boundary: excludedShapes -> locals=2 (if-init/for-init/switch-cond/catch-clause/structured-binding all excluded; for-body + the binding's source pair counted)" \
                     || no "floor-boundary: excludedShapes -> got '$c_excl', want 2"
c_lam="$( locals_of "$CPPXML" lambdaInitCapture )"
[ "$c_lam" = "2" ] && ok "floor-boundary: lambdaInitCapture -> locals=2 (init-capture excluded; base+lam counted)" \
                    || no "floor-boundary: lambdaInitCapture -> got '$c_lam', want 2"

# ══ 3. LANGUAGE-OMISSION ═════════════════════════════════════════════════════════════════════════════
PYXML="$( xml "$PYDIR" )"
py_row="$( printf '%s' "$PYXML" | tr '>' '\n' | grep 'n="fn_with_locals"' )"
if printf '%s' "$py_row" | grep -q 'locals='; then
    no "language-omission: Python def carries a locals= attribute at all (must be ABSENT, not \"0\") — row: $py_row"
else
    ok "language-omission: Python def emits no locals=/locals_floor= (absent, never a bare 0)"
fi

# ══ 4. STALE-CACHE ═══════════════════════════════════════════════════════════════════════════════════
CACHE="$TMP/x.ripwirecache"
"$BIN" "$CPPDIR" --metrics --cache="$CACHE" >"$TMP/warmA.xml" 2>"$TMP/warmA.err"
if [ ! -s "$CACHE" ]; then
    no "stale-cache: --cache=PATH did not create a blob — cannot test the version guard"
else
    CORRUPT="$TMP/x_corrupt.ripwirecache"
    cp "$CACHE" "$CORRUPT"
    # header layout: u32 magic, u32 cacheVersion, u32 parserVer(+1 for rich), u8 arch — corrupt just the
    # parserVer field (offset 8) to a plausible PRE-BUMP value, simulating a blob from an older binary.
    python3 - "$CORRUPT" <<'PYEOF'
import sys
path = sys.argv[1]
with open( path, 'r+b' ) as f:
    f.seek( 8 )
    f.write( (41).to_bytes( 4, 'little' ) )   # one below this binary's rich parserVer
PYEOF
    "$BIN" "$CPPDIR" --metrics --cache="$CORRUPT" >"$TMP/warmB.xml" 2>"$TMP/warmB.err"
    if diff -q "$TMP/warmA.xml" "$TMP/warmB.xml" >/dev/null 2>&1; then
        ok "stale-cache: corrupted-version blob still produces byte-identical output (self-heals to a correct reparse)"
    else
        no "stale-cache: corrupted-version blob produced DIFFERENT output — the version guard silently misread it"
        diff "$TMP/warmA.xml" "$TMP/warmB.xml" | head -5
    fi
    # The degrade note is a DEGRADED_PATH_ALERT (ingest.cpp:1521, "[math degraded] ingest: cache checksum
    # mismatch"), and NDEBUG compiles those out — so on a Release binary this arm asserted something the
    # build cannot express, and CI's two Release legs were unconditionally red on it. Decide what a missing
    # note MEANS with the same two independent readings qualitystalecheck.sh arms 7/8c use, rather than
    # trusting either alone:
    #   unrelated alert fires, this one does not  → the seam really regressed          → FAIL
    #   both silent on a dev/asan flavour         → binary contradicts its version str → FAIL
    #   both silent on an NDEBUG flavour          → unobservable BY DESIGN             → SKIP, reason named
    # The SKIP is only honest because CI runs the plain flavour as its own matrix leg, and THERE this arm
    # still fails if the note goes missing. Deleting the assertion instead would have retired the coverage.
    PROBE="$TMP/probe_repo"; mkdir -p "$PROBE"
    ( cd "$PROBE" && git init -q . && git config user.email x@y && git config user.name x \
      && printf 'int p( int x ){ return x + 1; }\n' > a.cpp && git add a.cpp && git commit -qm A ) >/dev/null 2>&1
    "$BIN" "$PROBE" --rank-by=churn --since=notadate >/dev/null 2>"$TMP/probe.err"
    alerts_observable=0
    grep -q 'math degraded' "$TMP/probe.err" && alerts_observable=1
    BUILD_FLAVOUR="$( "$BIN" --version 2>/dev/null | sed -nE 's/^[^(]*\(([^,)]*).*/\1/p' )"
    case "$BUILD_FLAVOUR" in
        Release|RelWithDebInfo|MinSizeRel) ndebug_flavour=1 ;;
        *)                                 ndebug_flavour=0 ;;
    esac
    if grep -qi "cache" "$TMP/warmB.err" && grep -qi "corrupt\|reparse\|mismatch" "$TMP/warmB.err"; then
        ok "stale-cache: a degrade note was emitted for the corrupted blob (never a silent accept)"
    elif [ "$alerts_observable" = "0" ] && [ "$ndebug_flavour" = "1" ]; then
        printf '  SKIP  %s\n' "stale-cache: DEGRADED_PATH_ALERT is compiled out of this binary (--version says build type \"$BUILD_FLAVOUR\", which defines NDEBUG; the unrelated --since=notadate degrade path is silent here too, so alerts are unobservable globally rather than this seam having broken). The PLAIN-flavour leg of the same CI suite is where this arm is proven."
    else
        no "stale-cache: no degrade note for the corrupted blob — build type \"$BUILD_FLAVOUR\" (unrelated alerts observable=$alerts_observable), got stderr: $( cat "$TMP/warmB.err" )"
    fi
fi

# ══ 5. HYGIENE ═══════════════════════════════════════════════════════════════════════════════════════
A="$( xml "$CPPDIR" )"; B="$( xml "$CPPDIR" )"
[ "$A" = "$B" ] && ok "hygiene: two cold runs are byte-identical (determinism)" || no "hygiene: two cold runs DIFFER"
if printf '%s' "$CPPXML" | xmllint --noout - >/dev/null 2>&1; then
    ok "hygiene: --metrics map is well-formed XML"
else
    no "hygiene: --metrics map failed xmllint"
fi

# ══ 6. JSON-PARITY ═══════════════════════════════════════════════════════════════════════════════════
CPPJSON="$( "$BIN" "$CPPDIR" --metrics --json --no-cache 2>/dev/null )"
if printf '%s' "$CPPJSON" | python3 -c "import json,sys; json.load(sys.stdin)" >/dev/null 2>&1; then
    ok "json-parity: --json --metrics output is valid JSON"
else
    no "json-parity: --json --metrics output failed to parse as JSON"
fi
if printf '%s' "$CPPJSON" | grep -q '"threeLocals"'; then
    if printf '%s' "$CPPJSON" | python3 -c "
import json,sys
d = json.load(sys.stdin)
def walk(o):
    if isinstance(o, dict):
        if o.get('n') == 'threeLocals':
            assert o.get('locals') == 3 and o.get('locals_floor') is True, o
            print('OK')
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(d)
" 2>/dev/null | grep -q OK; then
        ok "json-parity: threeLocals carries locals=3, locals_floor=true in JSON"
    else
        no "json-parity: threeLocals JSON row missing/incorrect locals fields"
    fi
else
    no "json-parity: threeLocals row not found in --json output"
fi
PYJSON="$( "$BIN" "$PYDIR" --metrics --json --no-cache 2>/dev/null )"
if printf '%s' "$PYJSON" | grep -q '"locals"'; then
    no "json-parity: Python JSON row carries a locals key at all (must be absent)"
else
    ok "json-parity: Python JSON row carries no locals key (absent, matching the XML dialect)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
