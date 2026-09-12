#!/usr/bin/env bash
# jsverbscheck.sh — do JavaScript + Bash call edges flow into the OTHER navigation/quality verbs, not just
# the default map? jslangcheck.sh (Wave-1's own gate) proves the default map's symbols/edges and spot-checks
# --callees/--callers once each; it does NOT touch --graph-query's bounded closure, --deps' file-level view,
# or --hotspots' git-churn×complexity score on JS/Bash. Those consume the SAME underlying call graph through
# different code paths (graph-query's closure walk, deps' file-adjacency, hotspots' per-file churn join) —
# each is a distinct place a JS/Bash wiring gap could hide even though the base map looks fine.
#
# Fixtures: test/jslangfix (Wave-1's own a.js/b.sh, reused read-only — addTwo->addOne, sum_of_squares->square)
# plus a throwaway git-init'd JS corpus (mktemp) for --hotspots, since churn needs real commit history that
# must not be added to the checked-in fixture.
#
# Usage:
#   test/jsverbscheck.sh
#   RIPWIRE_BIN=asan/ripwire test/jsverbscheck.sh
#
# Exits non-zero on any failure. Does NOT edit regression.sh or any existing test file.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="test/jslangfix"        # relative — cd "$ROOT" below, so emitted p="..." matches this
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
[ -d "$FIX" ] || { echo "no test/jslangfix directory"; exit 2; }

echo "jsverbscheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --graph-query: bounded closure over JS + Bash call edges ==="
# ═══════════════════════════════════════════════════════════════════════════
# callees(name("addTwo"),2) — a 2-hop bounded closure from addTwo. addTwo -> addOne is the only edge, so
# the closure (excluding the source itself) is exactly {addOne}, regardless of the depth cap.
GQ_JS="$( "$BIN" "$FIX" --graph-query='callees(name("addTwo"),2)' --no-cache 2>/dev/null )"
GQ_JS_RC=$?
if [ $GQ_JS_RC -eq 0 ]; then ok "--graph-query exits 0 on the JS call edge"; else no "--graph-query failed on JS (rc=$GQ_JS_RC)"; fi
if printf '%s' "$GQ_JS" | grep -q 'count="1"'; then ok "--graph-query callees(addTwo,2) count=1 (exactly addOne)"; else no "--graph-query JS closure count wrong: $GQ_JS"; fi
if printf '%s' "$GQ_JS" | grep -q 'n="addOne"'; then ok "--graph-query callees(addTwo,2) includes addOne"; else no "--graph-query JS closure missing addOne: $GQ_JS"; fi

GQ_SH="$( "$BIN" "$FIX" --graph-query='callees(name("sum_of_squares"),2)' --no-cache 2>/dev/null )"
GQ_SH_RC=$?
if [ $GQ_SH_RC -eq 0 ]; then ok "--graph-query exits 0 on the Bash call edge"; else no "--graph-query failed on Bash (rc=$GQ_SH_RC)"; fi
if printf '%s' "$GQ_SH" | grep -q 'count="1"'; then ok "--graph-query callees(sum_of_squares,2) count=1 (exactly square)"; else no "--graph-query Bash closure count wrong: $GQ_SH"; fi
if printf '%s' "$GQ_SH" | grep -q 'n="square"'; then ok "--graph-query callees(sum_of_squares,2) includes square"; else no "--graph-query Bash closure missing square: $GQ_SH"; fi

# the callers() direction too (walks the in-edges, a different CSR than callees()).
GQ_CALLERS="$( "$BIN" "$FIX" --graph-query='callers(name("addOne"),2)' --no-cache 2>/dev/null )"
if printf '%s' "$GQ_CALLERS" | grep -q 'n="addTwo"'; then ok "--graph-query callers(addOne,2) includes addTwo (in-edge direction works on JS)"; else no "--graph-query JS callers-direction closure missing addTwo: $GQ_CALLERS"; fi

# and(...) join: kind(all,fn) intersected with callees(addTwo,2) must still yield addOne (both are fn).
GQ_AND="$( "$BIN" "$FIX" --graph-query='and(callees(name("addTwo"),2),kind(all,fn))' --no-cache 2>/dev/null )"
if printf '%s' "$GQ_AND" | grep -q 'n="addOne"'; then ok "--graph-query and(callees(...),kind(all,fn)) join works on JS"; else no "--graph-query JS and() join failed: $GQ_AND"; fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --callers / --callees: --limit/--offset pagination on a JS/Bash corpus ==="
# ═══════════════════════════════════════════════════════════════════════════
# a.js's addOne has exactly one caller (addTwo). --limit=1 --offset=0 must return that one caller;
# --offset=1 (paginating past the only result) must return an EMPTY page, not an error / not a repeat.
PG0="$( "$BIN" "$FIX" --callers=addOne --limit=1 --offset=0 --no-cache 2>/dev/null )"
if printf '%s' "$PG0" | grep -q 'n="addTwo"'; then ok "--callers=addOne --limit=1 --offset=0 returns addTwo"; else no "--callers pagination page 0 missing addTwo: $PG0"; fi
PG1="$( "$BIN" "$FIX" --callers=addOne --limit=1 --offset=1 --no-cache 2>/dev/null )"
PG1_RC=$?
if [ $PG1_RC -eq 0 ]; then ok "--callers=addOne --limit=1 --offset=1 (past the only result) exits 0, not an error"; else no "--callers pagination past-end failed (rc=$PG1_RC)"; fi
printf '%s' "$PG1" | grep -q 'n="addTwo"' && no "--callers pagination page 1 wrongly repeats addTwo (offset not advancing)" || ok "--callers pagination page 1 correctly empty (no repeat)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --deps: JS/Bash files appear in the file-level dependency view (even with no include edges) ==="
# ═══════════════════════════════════════════════════════════════════════════
# a.js/b.sh have no #include-style edges between them (confirmed: jslangcheck's fixture has no require()/
# source), so --deps' <f> listing (which only lists files with outgoing OR incoming edges) is legitimately
# empty of <f> entries — but the <health> summary must still reflect files=2 and must not crash.
DEPS_OUT="$( "$BIN" "$FIX" --deps --no-cache 2>/dev/null )"
DEPS_RC=$?
if [ $DEPS_RC -eq 0 ]; then ok "--deps exits 0 on a JS/Bash corpus with no include edges"; else no "--deps failed on JS/Bash (rc=$DEPS_RC)"; fi
if printf '%s' "$DEPS_OUT" | grep -q 'files="2"'; then ok "--deps health block correctly counts files=2"; else no "--deps file count wrong: $DEPS_OUT"; fi
command -v xmllint >/dev/null 2>&1 && { if printf '%s' "$DEPS_OUT" | xmllint --noout - 2>/dev/null; then ok "--deps output well-formed XML on JS/Bash"; else no "--deps XML malformed on JS/Bash"; fi; }

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --hotspots: complexity x git-churn score computes on a REAL JavaScript history ==="
# ═══════════════════════════════════════════════════════════════════════════
# test/jslangfix's own git history is just the one Wave-1 commit that added it (no churn signal worth
# hand-verifying); build a throwaway git repo with two commits so real churn+complexity both have
# hand-checkable values. leaf(): 1 commit intro + 1 commit that adds 2 levels of if-nesting = churn=2,
# and the SECOND version's ccx must be > 0 (cognitive complexity of if>if).
HOT="$( mktemp -d "$TMP/hot.XXXXXX" )"
( cd "$HOT" && git init -q && git config user.email t@t.com && git config user.name t
  cat > a.js <<'EOF'
function leaf( x )
{
    return x + 1;
}
EOF
  git add a.js && git commit -q -m "init"
  cat > a.js <<'EOF'
function leaf( x )
{
    if ( x > 0 )
    {
        if ( x > 1 )
        {
            return x + 100;
        }
    }
    return x + 1;
}
EOF
  git add a.js && git commit -q -m "add nesting" )
HOT_OUT="$( cd "$HOT" && "$BIN" . --hotspots --no-cache 2>/dev/null )"
HOT_RC=$?
if [ $HOT_RC -eq 0 ]; then ok "--hotspots exits 0 on a real JS git history"; else no "--hotspots failed on JS (rc=$HOT_RC)"; fi
if printf '%s' "$HOT_OUT" | grep -q 'ranked="1"'; then ok "--hotspots ranks exactly 1 file (a.js)"; else no "--hotspots ranked count wrong: $HOT_OUT"; fi
if printf '%s' "$HOT_OUT" | grep -q 'churn="2"'; then ok "--hotspots correctly counts churn=2 (two commits touching a.js)"; else no "--hotspots churn count wrong: $HOT_OUT"; fi
if printf '%s' "$HOT_OUT" | grep -oE 'ccx="[0-9]+"' | grep -qv 'ccx="0"'; then ok "--hotspots reports a NON-ZERO ccx for the nested JS function (cognitive complexity computed)"; else no "--hotspots ccx stayed 0 on nested JS — cognitive complexity may not be wired for the hotspots view on JS"; fi
if printf '%s' "$HOT_OUT" | grep -q 'top="leaf"'; then ok "--hotspots identifies leaf() as the top offending function (top= is the BARE name, no :line suffix)"; else no "--hotspots did not identify leaf() as top, or top= still carries a :line suffix: $HOT_OUT"; fi
# §P11.3: top="main:322" used to read as a file:line pair but was actually name:ccx — split into
# top_ccx= (the worst function's cognitive complexity, matching the digits that used to trail the colon)
# and top_l= (the worst function's actual 1-based source line, so the --expand hop works). leaf() starts
# at line 1 of the second commit's a.js.
if printf '%s' "$HOT_OUT" | grep -oE 'top_ccx="[0-9]+"' | grep -qv 'top_ccx="0"'; then ok "--hotspots emits a non-zero top_ccx= (the worst function's cognitive complexity, split out of top=)"; else no "--hotspots top_ccx= missing or zero: $HOT_OUT"; fi
if printf '%s' "$HOT_OUT" | grep -q 'top_l="1"'; then ok "--hotspots emits top_l=\"1\" (leaf()'s real source line, not its complexity)"; else no "--hotspots top_l= missing/wrong — the --expand hop can't be built from it: $HOT_OUT"; fi

# determinism of the hotspots score on this fixed history.
HOT_OUT2="$( cd "$HOT" && "$BIN" . --hotspots --no-cache 2>/dev/null )"
if [ "$HOT_OUT" = "$HOT_OUT2" ]; then ok "--hotspots deterministic on the JS git history"; else no "--hotspots non-deterministic"; fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism across all verbs on the shared JS/Bash fixture ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --graph-query='callees(name("addTwo"),2)' --no-cache >"$TMP/gq1" 2>/dev/null
"$BIN" "$FIX" --graph-query='callees(name("addTwo"),2)' --no-cache >"$TMP/gq2" 2>/dev/null
if diff -q "$TMP/gq1" "$TMP/gq2" >/dev/null; then ok "--graph-query deterministic on JS/Bash"; else no "--graph-query non-deterministic on JS/Bash"; fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION: prove the count/churn assertions are load-bearing ==="
# ═══════════════════════════════════════════════════════════════════════════
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        if printf '%s' "$GQ_JS" | grep -q 'count="2"'; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (asserting graph-query count=2 when it is really 1 correctly fails)" \
                       || no "mutation self-test broke — the graph-query count assertion is not live"

MUT2="$( ok(){ :; }; no(){ echo TRIPPED; }
        if printf '%s' "$HOT_OUT" | grep -q 'churn="99"'; then ok; else no; fi )"
[ "$MUT2" = "TRIPPED" ] && ok "mutation self-test (asserting hotspots churn=99 when it is really 2 correctly fails)" \
                        || no "mutation self-test broke — the hotspots churn assertion is not live"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
