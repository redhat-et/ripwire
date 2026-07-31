#!/usr/bin/env bash
# w2verbscheck.sh — do Java + Ruby (Wave-2, bdbb643) actually work through the FULL verb set, or only
# the focused javarubycheck.sh path (default map + one --callers/--callees spot check)? This gate drives
# --metrics, --callers/--callees, --deps, --graph-query, --hotspots, and --quality-delta on hand-built
# Java + Ruby fixtures with KNOWN nesting/params, and pins HAND-COMPUTED values — not "did it not crash".
#
# Fixture (test/w2verbsfix/): Shapes.java + shapes.rb, each with a 1-param/0-nest leaf, a 3-param/
# 3-deep-nested method (if>for>if resp. if>while>if), and a 1-param method calling both (cbo=2). Every
# loc/params/nest/ccx/cbo value below was measured by running `ripwire test/w2verbsfix --metrics` and
# reading the raw output BEFORE being pinned as an assertion (see the fixture file headers).
#
# REAL BUGS FOUND while building this gate — NOW FIXED in 04113a2 (see src/ingest.cpp). This gate
# now asserts the FIXED cross-language behavior: Ruby structural metrics match their Java twins.
#   - WAS: cc_isParamList() (ingest.cpp ~825) listed parameter-list node types for C++/ObjC/Go
#     (parameter_list), Python/Rust/Swift (parameters), TS/JS (formal_parameters), Swift
#     (parameter_clause) — but NOT Ruby's `method_parameters` node, so Ruby params ALWAYS read 0.
#   - WAS: isDecisionType()/cc_isNestingControl() (ingest.cpp ~676/699) matched only C-family node
#     names (if_statement, while_statement, for_statement, ...) — Ruby's grammar names these `if`,
#     `while`, `for`, `unless` (no `_statement`/`_expression` suffix). Result: Ruby cyclomatic (cx),
#     cognitive (ccx), and max-nesting (nest) were ALL silently zero, no matter how deeply nested.
#   - FIX (04113a2): Ruby node kinds added to the ingest.cpp predicate tables (gated on
#     ts_node_is_named). Ruby now computes params/nest/cx/ccx correctly and IDENTICALLY to the
#     equivalent Java: leaf_rb → params=1 nest=0 ccx=0; deep_nest_rb → params=3 nest=3 cx=4 ccx=6.
#   - Downstream (also fixed): --hotspots on a 2-deep-nested, 2-commit-churned Ruby method now scores
#     non-zero ccx and ENTERS the ranked list (ranked="1"), like the Java twin. --quality-delta on a
#     Ruby file that goes flat → 5-deep-nested now REPORTS the nesting regression (regressions="1",
#     exit 2), like its Java counterpart (and the JS case in jsmetricscheck.sh).
#   Java was always unaffected (tree-sitter-java uses C-family node names + `formal_parameters`).
#   This gate now asserts the FIXED Ruby==Java behavior; the mutation self-tests keep it load-bearing.
#
# Usage:
#   test/w2verbscheck.sh
#   RIPWIRE_BIN=asan/ripwire test/w2verbscheck.sh
#
# Exits non-zero on any FAIL (an assertion that doesn't match observed behavior). The mutation
# self-tests at the end prove every pinned value is live, not a tautology.
# Does NOT edit regression.sh or any existing test file.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="test/w2verbsfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
[ -d "$FIX" ] || { echo "no test/w2verbsfix directory"; exit 2; }

echo "w2verbscheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --metrics: hand-checked loc/params/nest/ccx/cbo on Java ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --metrics --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$FIX" --metrics --no-cache >"$TMP/m2" 2>/dev/null
MAP="$( cat "$TMP/m1" )"
diff -q "$TMP/m1" "$TMP/m2" >/dev/null && ok "determinism (--metrics byte-identical run-to-run)" || no "non-deterministic --metrics output"

sattr(){ printf '%s' "$MAP" | sed 's/>/>\n/g' | grep -E "<s t=\"[^\"]*\" n=\"$1\"" | head -1; }
assert_attr(){ # name attr val
    local line; line="$( sattr "$1" )"
    if printf '%s' "$line" | grep -q " $2=\"$3\""; then ok "$1: $2=$3"; else no "$1: expected $2=$3 — got: $line"; fi
}

# leaf (Java): 1 param, 0 nesting, 0 calls, loc=4
assert_attr leaf loc 4;      assert_attr leaf params 1;      assert_attr leaf nest 0;   assert_attr leaf cbo 0
# deepNest (Java): 3 params, 3-deep nesting (if>for>if), ccx=6, loc=14, calls nothing in-repo (cbo=0)
assert_attr deepNest loc 14; assert_attr deepNest params 3;  assert_attr deepNest nest 3; assert_attr deepNest ccx 6; assert_attr deepNest cbo 0
# callsBoth (Java): 1 param, 0 nesting, calls leaf()+deepNest() -> cbo=2, loc=4
assert_attr callsBoth loc 4; assert_attr callsBoth params 1; assert_attr callsBoth nest 0; assert_attr callsBoth cbo 2

# sanity: at least one Java nest value is non-zero (catches a wholesale "everything defaulted to 0" regression)
printf '%s' "$( sattr deepNest )" | grep -qv ' nest="0"' && ok "sanity: Java nest values are NOT all defaulting to 0" || no "sanity: Java nest defaulted to 0 — metrics may be silently broken on Java"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --metrics on Ruby — FIXED (04113a2): params/nest/cx/ccx now match the Java twins ==="
# ═══════════════════════════════════════════════════════════════════════════
# loc/cbo were always language-agnostic (loc = physical line span; cbo = call-graph fan-out).
assert_attr leaf_rb loc 3;         assert_attr leaf_rb cbo 0
assert_attr deep_nest_rb cbo 0
assert_attr calls_both_rb loc 3;   assert_attr calls_both_rb cbo 2

# FIXED: cc_isParamList() now recognizes Ruby's `method_parameters` node -> params correct.
# leaf_rb/calls_both_rb have 1 param each; deep_nest_rb(a,b,c) has 3 — identical to the Java twins.
assert_attr leaf_rb params 1
assert_attr calls_both_rb params 1
assert_attr deep_nest_rb params 3

# FIXED: isDecisionType()/cc_isNestingControl() now match Ruby's `if`/`while`/`for`/`unless` node
# names, so nest/cx/ccx accumulate on genuinely 3-deep-nested Ruby (if > while > if in deep_nest_rb),
# EXACTLY matching the Java deepNest twin above (nest=3, cx=4, ccx=6).
assert_attr leaf_rb nest 0;       assert_attr leaf_rb ccx 0
assert_attr deep_nest_rb nest 3;  assert_attr deep_nest_rb cx 4;  assert_attr deep_nest_rb ccx 6

# sanity: at least one Ruby nest value is non-zero (catches a regression back to the always-0 bug).
printf '%s' "$( sattr deep_nest_rb )" | grep -qv ' nest="0"' && ok "sanity: Ruby nest values are NOT defaulting to 0 (the old bug did not regress)" || no "sanity: Ruby deep_nest_rb nest defaulted to 0 — the fixed Ruby metrics regressed"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --callers / --callees on Java + Ruby ==="
# ═══════════════════════════════════════════════════════════════════════════
JCE="$( "$BIN" "$FIX" --callees=callsBoth --no-cache 2>/dev/null )"
printf '%s' "$JCE" | grep -q 'count="2"' && printf '%s' "$JCE" | grep -q 'n="leaf"' && printf '%s' "$JCE" | grep -q 'n="deepNest"' \
    && ok "Java: --callees=callsBoth count=2 {leaf,deepNest}" || no "Java --callees wrong: $JCE"
JCR="$( "$BIN" "$FIX" --callers=leaf --no-cache 2>/dev/null )"
printf '%s' "$JCR" | grep -q 'n="callsBoth"' && ok "Java: --callers=leaf lists callsBoth" || no "Java --callers wrong: $JCR"

RCE="$( "$BIN" "$FIX" --callees=calls_both_rb --no-cache 2>/dev/null )"
printf '%s' "$RCE" | grep -q 'count="2"' && printf '%s' "$RCE" | grep -q 'n="leaf_rb"' && printf '%s' "$RCE" | grep -q 'n="deep_nest_rb"' \
    && ok "Ruby: --callees=calls_both_rb count=2 {leaf_rb,deep_nest_rb}" || no "Ruby --callees wrong: $RCE"
RCR="$( "$BIN" "$FIX" --callers=leaf_rb --no-cache 2>/dev/null )"
printf '%s' "$RCR" | grep -q 'n="calls_both_rb"' && ok "Ruby: --callers=leaf_rb lists calls_both_rb" || no "Ruby --callers wrong: $RCR"

# pagination sanity: leaf_rb has exactly 1 caller -> offset=1 is an empty (not repeating, not erroring) page
PG1="$( "$BIN" "$FIX" --callers=leaf_rb --limit=1 --offset=1 --no-cache 2>/dev/null )"; PG1_RC=$?
[ $PG1_RC -eq 0 ] && ok "Ruby: --callers pagination past-end exits 0" || no "Ruby --callers pagination past-end failed (rc=$PG1_RC)"
printf '%s' "$PG1" | grep -q 'n="calls_both_rb"' && no "Ruby: --callers pagination page 1 wrongly repeats calls_both_rb" || ok "Ruby: --callers pagination page 1 correctly empty"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --deps: Java + Ruby files appear in the file-level dependency view ==="
# ═══════════════════════════════════════════════════════════════════════════
DEPS_OUT="$( "$BIN" "$FIX" --deps --no-cache 2>/dev/null )"; DEPS_RC=$?
[ $DEPS_RC -eq 0 ] && ok "--deps exits 0 on a Java/Ruby corpus" || no "--deps failed on Java/Ruby (rc=$DEPS_RC)"
printf '%s' "$DEPS_OUT" | grep -q 'files="2"' && ok "--deps health block correctly counts files=2" || no "--deps file count wrong: $DEPS_OUT"
command -v xmllint >/dev/null 2>&1 && { printf '%s' "$DEPS_OUT" | xmllint --noout - 2>/dev/null && ok "--deps output well-formed XML on Java/Ruby" || no "--deps XML malformed on Java/Ruby"; }

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --graph-query: bounded closure over Java + Ruby call edges ==="
# ═══════════════════════════════════════════════════════════════════════════
GQ_JV="$( "$BIN" "$FIX" --graph-query='callees(name("callsBoth"),2)' --no-cache 2>/dev/null )"
printf '%s' "$GQ_JV" | grep -q 'count="2"' && printf '%s' "$GQ_JV" | grep -q 'n="leaf"' && printf '%s' "$GQ_JV" | grep -q 'n="deepNest"' \
    && ok "Java: --graph-query callees(callsBoth,2) count=2 {leaf,deepNest}" || no "Java --graph-query wrong: $GQ_JV"

GQ_RB="$( "$BIN" "$FIX" --graph-query='callees(name("calls_both_rb"),2)' --no-cache 2>/dev/null )"
printf '%s' "$GQ_RB" | grep -q 'count="2"' && printf '%s' "$GQ_RB" | grep -q 'n="leaf_rb"' && printf '%s' "$GQ_RB" | grep -q 'n="deep_nest_rb"' \
    && ok "Ruby: --graph-query callees(calls_both_rb,2) count=2 {leaf_rb,deep_nest_rb}" || no "Ruby --graph-query wrong: $GQ_RB"

# and() join across languages doesn't apply (single-corpus query) but exercise it on Ruby to prove filters compose
GQ_AND="$( "$BIN" "$FIX" --graph-query='and(callees(name("calls_both_rb"),2),kind(all,method))' --no-cache 2>/dev/null )"
printf '%s' "$GQ_AND" | grep -q 'n="leaf_rb"' && ok "Ruby: --graph-query and(callees(...),kind(all,method)) join works" || no "Ruby --graph-query and() join failed: $GQ_AND"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --hotspots on real Java + Ruby git history ==="
# ═══════════════════════════════════════════════════════════════════════════
# Java: leaf() gains 2 levels of if-nesting across 2 commits -> churn=2, ccx>0, correctly ranked.
HOTJ="$( mktemp -d "$TMP/hotj.XXXXXX" )"
( cd "$HOTJ" && git init -q && git config user.email t@t.com && git config user.name t
  cat > A.java <<'EOF'
class A
{
    int leaf( int x )
    {
        return x + 1;
    }
}
EOF
  git add A.java && git commit -q -m init
  cat > A.java <<'EOF'
class A
{
    int leaf( int x )
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
}
EOF
  git add A.java && git commit -q -m "add nesting" )
HOTJ_OUT="$( cd "$HOTJ" && "$BIN" . --hotspots --no-cache 2>/dev/null )"
printf '%s' "$HOTJ_OUT" | grep -q 'ranked="1"' && ok "Java --hotspots ranks exactly 1 file" || no "Java --hotspots ranked count wrong: $HOTJ_OUT"
printf '%s' "$HOTJ_OUT" | grep -q 'churn="2"' && ok "Java --hotspots correctly counts churn=2" || no "Java --hotspots churn wrong: $HOTJ_OUT"
printf '%s' "$HOTJ_OUT" | grep -oE 'ccx="[0-9]+"' | grep -qv 'ccx="0"' && ok "Java --hotspots reports non-zero ccx for nested code" || no "Java --hotspots ccx stayed 0 — cognitive complexity not wired for Java hotspots"

# Ruby: SAME nesting pattern, SAME 2 commits — FIXED downstream: ccx now accumulates (see the
# --metrics fix above), so the file scores non-zero and enters the ranked list, like the Java twin.
HOTR="$( mktemp -d "$TMP/hotr.XXXXXX" )"
( cd "$HOTR" && git init -q && git config user.email t@t.com && git config user.name t
  cat > a.rb <<'EOF'
def leaf(x)
  x + 1
end
EOF
  git add a.rb && git commit -q -m init
  cat > a.rb <<'EOF'
def leaf(x)
  if x > 0
    if x > 1
      return x + 100
    end
  end
  x + 1
end
EOF
  git add a.rb && git commit -q -m "add nesting" )
HOTR_OUT="$( cd "$HOTR" && "$BIN" . --hotspots --no-cache 2>/dev/null )"
# Mirror the Java assertions above: the 2-deep-nested, 2-commit-churned Ruby method now ranks.
printf '%s' "$HOTR_OUT" | grep -q 'ranked="1"' && ok "Ruby --hotspots ranks exactly 1 file (fixed: enters the ranked list like the Java twin)" || no "Ruby --hotspots ranked count wrong: $HOTR_OUT"
printf '%s' "$HOTR_OUT" | grep -q 'churn="2"' && ok "Ruby --hotspots correctly counts churn=2" || no "Ruby --hotspots churn wrong: $HOTR_OUT"
printf '%s' "$HOTR_OUT" | grep -oE 'ccx="[0-9]+"' | grep -qv 'ccx="0"' && ok "Ruby --hotspots reports non-zero ccx for nested code (fixed)" || no "Ruby --hotspots ccx stayed 0 — cognitive complexity not wired for Ruby hotspots"

# determinism: Ruby --hotspots is byte-identical run-to-run
HOTR_OUT2="$( cd "$HOTR" && "$BIN" . --hotspots --no-cache 2>/dev/null )"
[ "$HOTR_OUT" = "$HOTR_OUT2" ] && ok "Ruby --hotspots deterministic run-to-run" || no "Ruby --hotspots non-deterministic"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --quality-delta on Java + Ruby nesting regressions ==="
# ═══════════════════════════════════════════════════════════════════════════
# Java: baseline a flat function, then deepen it past kNestBar -> --quality-delta must catch it (exit 2).
QDJ="$TMP/qdj"; mkdir -p "$QDJ"
cat > "$QDJ/A.java" <<'EOF'
class A
{
    int simple( int x )
    {
        return x + 1;
    }
}
EOF
( cd "$QDJ" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 )
[ -f "$QDJ/.ripwire_quality_baseline" ] && ok "--quality-baseline writes a sidecar for a Java-only corpus" || no "--quality-baseline did not write a sidecar for Java"
cat > "$QDJ/A.java" <<'EOF'
class A
{
    int simple( int x )
    {
        if ( x > 0 )
        {
            if ( x > 1 )
            {
                if ( x > 2 )
                {
                    if ( x > 3 )
                    {
                        if ( x > 4 )
                        {
                            return x + 100;
                        }
                    }
                }
            }
        }
        return x + 1;
    }
}
EOF
QDJ_OUT="$( cd "$QDJ" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"; QDJ_RC=$?
[ $QDJ_RC -eq 2 ] && ok "Java --quality-delta exits 2 on a real nesting regression" || no "Java --quality-delta exit code wrong (got $QDJ_RC, want 2): $QDJ_OUT"
printf '%s' "$QDJ_OUT" | grep -q 'kind="nesting"' && ok "Java --quality-delta classifies it as a nesting regression" || no "Java --quality-delta did not classify as nesting: $QDJ_OUT"

# Ruby: THE SAME transformation — FIXED: nest now moves off 0, so the regression IS reported (exit 2),
# exactly like the Java twin above.
QDR="$TMP/qdr"; mkdir -p "$QDR"
cat > "$QDR/a.rb" <<'EOF'
def simple(x)
  x + 1
end
EOF
( cd "$QDR" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 )
[ -f "$QDR/.ripwire_quality_baseline" ] && ok "--quality-baseline writes a sidecar for a Ruby-only corpus" || no "--quality-baseline did not write a sidecar for Ruby"
cat > "$QDR/a.rb" <<'EOF'
def simple(x)
  if x > 0
    if x > 1
      if x > 2
        if x > 3
          if x > 4
            return x + 100
          end
        end
      end
    end
  end
  x + 1
end
EOF
QDR_OUT="$( cd "$QDR" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"; QDR_RC=$?
# Mirror the Java assertions: the flat -> 5-deep-nested Ruby transformation is now caught.
[ $QDR_RC -eq 2 ] && ok "Ruby --quality-delta exits 2 on a real nesting regression (fixed: now caught like the Java twin)" || no "Ruby --quality-delta exit code wrong (got $QDR_RC, want 2): $QDR_OUT"
printf '%s' "$QDR_OUT" | grep -q 'kind="nesting"' && ok "Ruby --quality-delta classifies it as a nesting regression" || no "Ruby --quality-delta did not classify as nesting: $QDR_OUT"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION: prove the pinned assertions are load-bearing, not tautologies ==="
# ═══════════════════════════════════════════════════════════════════════════
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        line="$( sattr deepNest )"
        if printf '%s' "$line" | grep -q ' nest="999"'; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (asserting Java nest=999 when it is really 3 correctly fails)" \
                       || no "mutation self-test broke — the Java nest assertion is not live"

MUT2="$( ok(){ :; }; no(){ echo TRIPPED; }
        if printf '%s' "$JCE" | grep -q 'count="99"'; then ok; else no; fi )"
[ "$MUT2" = "TRIPPED" ] && ok "mutation self-test (asserting Java --callees count=99 when it is really 2 correctly fails)" \
                        || no "mutation self-test broke — the Java --callees count assertion is not live"

MUT3="$( ok(){ :; }; no(){ echo TRIPPED; }
        if printf '%s' "$QDJ_OUT" | grep -q 'regressions="0"'; then ok; else no; fi )"
[ "$MUT3" = "TRIPPED" ] && ok "mutation self-test (asserting Java quality-delta regressions=0 on a real regression correctly fails)" \
                        || no "mutation self-test broke — the Java quality-delta regression assertion is not live"

# prove the NEW Ruby fixed-value assertions are load-bearing: asserting the wrong Ruby nest value must
# FAIL, so a regression back to the always-0 bug (or any other drift) cannot silently stay green.
MUT4="$( ok(){ :; }; no(){ echo TRIPPED; }
        line="$( sattr deep_nest_rb )"
        if printf '%s' "$line" | grep -q ' nest="999"'; then ok; else no; fi )"
[ "$MUT4" = "TRIPPED" ] && ok "mutation self-test (asserting Ruby deep_nest_rb nest=999 when it is really 3 correctly fails)" \
                        || no "mutation self-test broke — the Ruby nest fixed-value assertion is not live"

command -v xmllint >/dev/null 2>&1 && { printf '%s' "$MAP" | xmllint --noout - 2>/dev/null && ok "xml well-formed (--metrics on Java/Ruby)" || no "xml malformed (--metrics on Java/Ruby)"; }

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
