#!/usr/bin/env bash
# type3check.sh — gate for the WIRING of Type-3 (gapped / near-miss) clone detection through the ripwire
# BINARY (findClonesType3 → --clones output + --quality-delta duplication regression). The unit-level
# soundness of findClonesType3 itself is covered by type3clonecheck.sh (a header harness); this gate asserts
# the two USER-FACING surfaces the binary exposes:
#   1  --clones emits a type="3" group for a real gapped near-clone (an inserted/changed statement), with
#      similarity in [0.80,1.0); a truly-exact/renamed pair is type="2", never type="3".
#   2  --quality-delta flags a NEWLY-introduced Type-3 near-clone as a `duplication` regression (exit 2) —
#      baseline WITHOUT the near-clone, add it, re-delta.
#   3  both outputs are deterministic run-to-run and well-formed XML.
# Usage:  test/type3check.sh   |   RIPWIRE_BIN=asan/ripwire test/type3check.sh
# Exits non-zero on any failure. Self-contained (own temp dirs). Does NOT edit test/regression.sh.
set -u
BIN="${RIPWIRE_BIN:-./build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ── fixture: alpha vs beta = a Type-3 near-clone (beta adds `total += 1;` and an `int extra` line — same
#    structure, a few statements changed/added). wideOne vs wideTwo = an EXACT/renamed (Type-2) pair (only
#    variable names differ). unrelated = a control that must match nothing. All well over the 40-token floor.
FIX="$WORK/fix"; mkdir -p "$FIX"
cat > "$FIX/a.cpp" <<'EOF'
int alpha( int x, int y )
{
    int total = 0;
    for( int i = 0; i < x; ++i )
    {
        if( i % 2 == 0 ) { total += i * y; }
        else             { total -= i; }
    }
    return total;
}

int beta( int p, int q )
{
    int total = 0;
    for( int i = 0; i < p; ++i )
    {
        if( i % 2 == 0 ) { total += i * q; total += 1; }
        else             { total -= i; }
    }
    int extra = total * 2;
    return extra;
}

int wideOne( int aa, int bb, int cc )
{
    int total = 0;
    for( int i = 0; i < aa; ++i )
    {
        total += i * bb;
        total -= cc;
        if( total > 100 ) { total = total % 100; }
        else              { total = total + 7; }
    }
    return total;
}

int wideTwo( int xx, int yy, int zz )
{
    int total = 0;
    for( int i = 0; i < xx; ++i )
    {
        total += i * yy;
        total -= zz;
        if( total > 100 ) { total = total % 100; }
        else              { total = total + 7; }
    }
    return total;
}

int unrelated( int z )
{
    int r = z;
    r = r + 42;
    r = r * 3;
    return r;
}
EOF

# ── 1) --clones emits a type="3" group for alpha/beta and a type="2" group for wideOne/wideTwo ────────────────
cl="$("$BIN" "$FIX" --clones --no-cache 2>/dev/null)"

# a type="3" group whose members are alpha AND beta (order-independent match on the two <f n=...> names)
t3="$(printf '%s' "$cl" | grep -oE '<group type="3"[^>]*>(<f [^>]*/>)+</group>' | head -1)"
if [ -n "$t3" ] && printf '%s' "$t3" | grep -q 'n="alpha"' && printf '%s' "$t3" | grep -q 'n="beta"'; then
  ok "--clones emits a type=\"3\" group for the alpha/beta near-clone"
else
  no "--clones should emit a type=\"3\" group with members alpha+beta"; echo "     got type3: ${t3:-<none>}"
fi

# similarity attr present and in [0.80,1.0) on the type-3 group
sim="$(printf '%s' "$t3" | grep -oE 'similarity="[0-9.]+"' | grep -oE '[0-9.]+' | head -1)"
if [ -n "$sim" ] && awk -v s="$sim" 'BEGIN{ exit !(s>=0.80 && s<1.0) }'; then
  ok "type=\"3\" group carries similarity=$sim in [0.80,1.0)"
else
  no "type=\"3\" group should carry similarity in [0.80,1.0) (got '${sim:-none}')"
fi

# the exact/renamed pair is type="2", NEVER type="3"
t2="$(printf '%s' "$cl" | grep -oE '<group type="2"[^>]*>(<f [^>]*/>)+</group>' | grep 'n="wideOne"')"
if [ -n "$t2" ] && printf '%s' "$t2" | grep -q 'n="wideTwo"'; then
  ok "exact/renamed pair wideOne/wideTwo reported as type=\"2\" (not type=\"3\")"
else
  no "wideOne/wideTwo should be a type=\"2\" group"; echo "     got: ${t2:-<none>}"
fi

# the exact pair must NOT also appear as a type-3 group
if printf '%s' "$cl" | grep -oE '<group type="3"[^>]*>(<f [^>]*/>)+</group>' | grep -q 'n="wideOne"'; then
  no "wideOne/wideTwo leaked into a type=\"3\" group (exact should be excluded from Type-3)"
else
  ok "exact pair excluded from the Type-3 pass (no type=\"3\" group for wideOne/wideTwo)"
fi

# XML well-formed
if printf '%s' "$cl" | xmllint --noout - 2>/dev/null; then ok "--clones output is well-formed XML"; else no "--clones output is not well-formed XML"; fi

# determinism
c1="$("$BIN" "$FIX" --clones --no-cache 2>/dev/null)"
c2="$("$BIN" "$FIX" --clones --no-cache 2>/dev/null)"
[ "$c1" = "$c2" ] && ok "--clones deterministic run-to-run" || no "--clones not deterministic"

# ── 2) --quality-delta flags a NEWLY-introduced Type-3 near-clone as a duplication regression ─────────────────
QD="$WORK/qd"; mkdir -p "$QD"
# baseline: ONE function only (no clone of any kind)
cat > "$QD/q.cpp" <<'EOF'
int alpha( int x, int y )
{
    int total = 0;
    for( int i = 0; i < x; ++i )
    {
        if( i % 2 == 0 ) { total += i * y; }
        else             { total -= i; }
    }
    return total;
}
EOF
"$BIN" "$QD" --quality-baseline --no-cache >/dev/null 2>&1

# baseline clean → no duplication regression yet
d0="$("$BIN" "$QD" --quality-delta --no-cache 2>/dev/null)"
if printf '%s' "$d0" | grep -q 'kind="duplication"'; then
  no "baseline (single fn) should have NO duplication regression"; echo "     got: $d0"
else
  ok "baseline with no clone reports no duplication regression"
fi

# introduce a Type-3 near-clone of alpha → beta (added statements) → duplication regression must fire
cat >> "$QD/q.cpp" <<'EOF'

int beta( int p, int q )
{
    int total = 0;
    for( int i = 0; i < p; ++i )
    {
        if( i % 2 == 0 ) { total += i * q; total += 1; }
        else             { total -= i; }
    }
    int extra = total * 2;
    return extra;
}
EOF
d1="$("$BIN" "$QD" --quality-delta --no-cache 2>/dev/null)"; drc=$?
if printf '%s' "$d1" | grep -qE '<r kind="duplication"[^>]*members="[^"]*alpha[^"]*beta|<r kind="duplication"[^>]*members="[^"]*beta[^"]*alpha'; then
  ok "--quality-delta flags the new Type-3 near-clone as a duplication regression"
else
  no "--quality-delta should flag the new alpha/beta Type-3 near-clone as duplication"; echo "     got: $d1"
fi
[ "$drc" -eq 2 ] && ok "--quality-delta exits 2 on the new duplication regression" || no "--quality-delta should exit 2 (got $drc)"

# XML well-formed + determinism of the delta
if printf '%s' "$d1" | xmllint --noout - 2>/dev/null; then ok "--quality-delta output is well-formed XML"; else no "--quality-delta output is not well-formed XML"; fi
q1="$("$BIN" "$QD" --quality-delta --no-cache 2>/dev/null)"
q2="$("$BIN" "$QD" --quality-delta --no-cache 2>/dev/null)"
[ "$q1" = "$q2" ] && ok "--quality-delta deterministic run-to-run" || no "--quality-delta not deterministic"

# §P10.5: clones and the quality-delta verb share the detector but not the POLICY — groups whose every
# member is fixture-class or a shell test-runner now carry exempt= (same predicates, one policy source),
# and the root counts them over ALL groups. Facts stay visible; the sibling verb's opinion is disclosed.
CL="$( "$BIN" . --clones 2>/dev/null )"
printf '%s' "$CL" | grep -q 'exempt_groups="' \
    && ok "P10.5: clones root carries exempt_groups=" || no "P10.5: clones root missing exempt_groups="
printf '%s' "$CL" | grep -qE '<group[^>]*exempt="shell-runner"' \
    && ok "P10.5: a shell-runner group is disclosed exempt" || no "P10.5: no shell-runner group carries exempt="
printf '%s' "$CL" | grep -oE '<group[^>]*exempt="[^"]*">(<f [^>]*>)*' | grep -q 'p="./src/' \
    && no "P10.5: an exempt group contains a src/ member (predicate too broad)" \
    || ok "P10.5: no exempt group contains src/ members"

# ── §A8.1: --clones' default root is now arithmetically closeable — groups= is the type-2 SUBSET total,
# type3= the type-3 SUBSET total, and total= (new) is ALWAYS the true row total (groups + type3-group-
# count), on the un-paged default run AND on a --limit run alike — pre-fix total= only existed once
# --limit was passed, so the un-paged root carried no attribute equal to the row total at all.
CLGROUPS="$( printf '%s' "$CL" | grep -oE '<clones[^>]*>' | grep -oE ' groups="[0-9]+"' | grep -oE '"[0-9]+"' | tr -d '"' )"
CLTYPE3="$(  printf '%s' "$CL" | grep -oE '<clones[^>]*>' | grep -oE ' type3="[0-9]+"'  | grep -oE '"[0-9]+"' | tr -d '"' )"
CLTOTAL="$(  printf '%s' "$CL" | grep -oE '<clones[^>]*>' | grep -oE ' total="[0-9]+"'  | grep -oE '"[0-9]+"' | tr -d '"' )"
[ -n "$CLTOTAL" ] \
    && ok "§A8.1: --clones (un-paged) root carries total= ($CLTOTAL)" \
    || no "§A8.1: --clones (un-paged) root is missing total="
[ -n "$CLGROUPS" ] && [ -n "$CLTYPE3" ] && [ -n "$CLTOTAL" ] && [ "$(( CLGROUPS + CLTYPE3 ))" = "$CLTOTAL" ] \
    && ok "§A8.1: total=$CLTOTAL == groups=$CLGROUPS + type3=$CLTYPE3" \
    || no "§A8.1: arithmetic broken (groups=$CLGROUPS type3=$CLTYPE3 total=$CLTOTAL)"

# a --limit run reaching every row: total= (from the paging half) must equal the SAME value, and the
# row count it walks toward must equal groups+type3 too (the "true row total" the audit item names).
CLPAGED="$( "$BIN" . --clones --limit=100000 --no-cache 2>/dev/null )"
CLP_TOTAL="$( printf '%s' "$CLPAGED" | grep -oE '<clones[^>]*>' | grep -oE ' total="[0-9]+"' | grep -oE '"[0-9]+"' | tr -d '"' )"
CLP_SHOWN="$( printf '%s' "$CLPAGED" | grep -oE '<clones[^>]*>' | grep -oE ' shown="[0-9]+"' | grep -oE '"[0-9]+"' | tr -d '"' )"
CLP_ROWS="$(  printf '%s' "$CLPAGED" | grep -o '<group '  | wc -l | tr -d ' ' )"
{ [ "$CLP_TOTAL" = "$CLTOTAL" ] && [ "$CLP_SHOWN" = "$CLTOTAL" ] && [ "$CLP_ROWS" = "$CLTOTAL" ]; } \
    && ok "§A8.1: --clones --limit=100000: total=$CLP_TOTAL == shown=$CLP_SHOWN == $CLP_ROWS emitted rows" \
    || no "§A8.1: --clones --limit=100000 mismatch (total=$CLP_TOTAL shown=$CLP_SHOWN rows=$CLP_ROWS, expected $CLTOTAL)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
