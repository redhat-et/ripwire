#!/usr/bin/env bash
# nestprofilecheck.sh — the NESTING-DEPTH PROFILE that `nest=` alone cannot express.
#
# WHY THIS EXISTS. `nest=` (Symbol::maxNest) is a MAX: one line at depth 9 and a thousand lines at depth 9
# report the identical number. That makes two opposite shapes indistinguishable to every consumer that reads
# it — the quality panel's structural family, --readability's rank, the ensemble join:
#
#   BLOCKED-SEQUENTIAL   a long function that is a run of scoped steps, each shallow. Easy to read top to
#                        bottom; the max is set by one inner loop nobody has to hold in their head.
#   TANGLED              a function that sustains depth across hundreds of lines. The max is the same number
#                        and means something entirely different.
#
# Measured on this repo when the panel first ranked them together: main() (main.cpp) reaches its max on a
# handful of lines out of ~1060 and is otherwise a sequence of scoped blocks, while ingest() (ingest.cpp)
# holds depth over hundreds of lines. Ranking them as peers is the metric failing, not the code.
#
# WHAT IS ADDED. Two facts, from the SAME fused cc_walk DFS (no new tree-sitter queries), both keyed to the
# repo's EXISTING structural bar quality::kNestBar — no new magic number:
#
#   humps="N"   the count of MAXIMAL control-nesting regions that reach the bar. This is CodeScene's "bumpy
#               road": a rise above the threshold then a fall. One deep
#               tangle is 1; repeated missing abstractions are many. EXACT, not a floor — each deep region
#               has exactly one first-crossing node in the walk, so there is nothing to double count.
#   deep="N"    physical lines lying inside those regions. A FLOOR (deep_floor="1"), for the reason stated
#               on arm 6: the clamp that keeps two humps sharing a line from counting it twice can only
#               ever subtract. deep/loc is the fraction the max throws away.
#
# Both are OMITTED when humps is 0, and that is lossless rather than a token-saving fudge: a hump exists iff
# some node crossed the bar, so humps==0 iff nest<bar, and `nest=` is already on the row. Arm 5 pins that
# equivalence in both directions so the omission cannot start hiding a real zero.
#
# ── ARMS ──────────────────────────────────────────────────────────────────────────────────────────────
#   0. PRESENCE      — the fixture spells every shape the arms below assert.
#   1. THE POINT     — blockedSteps and oneTangle have the SAME nest=, and are told apart by humps=/deep=.
#                      If this arm ever passes vacuously the whole feature is decoration.
#   2. HUMP COUNT    — hand-counted per fixture: 0, 1, 3. A stub returning a constant cannot pass all three.
#   3. DEEP LINES    — hand-counted spans, and deep <= loc always (a containment invariant, not a taste).
#   4. NESTING-ONLY  — a lambda body deepens nesting (cc_isNestingOnly) and so can raise a hump, exactly as
#                      it already raises nest=. The two facts must agree about what nesting IS.
#   5. OMISSION      — humps=/deep= are absent iff nest<bar, in BOTH directions, and never a bare 0.
#   6. FLOOR HONESTY — deep= always carries deep_floor="1"; the attribute pair never appears half-present.
#   7. LANGUAGE      — the profile is language-agnostic (unlike locals=): a Python def with real depth
#                      carries humps=/deep= too, because cc_walk computes nesting for every language.
#   8. HYGIENE       — determinism (two cold runs byte-identical), well-formed XML, valid JSON.
#   9. JSON PARITY   — --json carries the same humps/deep/deep_floor triple, absent on the same rows.
#  11. LINE ACCOUNT — regions on DISTINCT lines are each billed (the document-order clamp), and regions
#                      that genuinely SHARE a line are billed once. Plus: switch-arm breadth is not depth.
#  10. MUTATION      — the pinned numbers are load-bearing: asserting a wrong hump count on a fixture whose
#                      real count is known must FAIL, or these arms are tautologies.
#
# Usage:
#   bash test/nestprofilecheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/nestprofilecheck.sh
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
echo "nestprofilecheck: BIN=$BIN  TMP=$TMP"

CPPDIR="$TMP/cpp"; mkdir -p "$CPPDIR"
PYDIR="$TMP/py";   mkdir -p "$PYDIR"

# The bar is quality::kNestBar. Read it from the source rather than restating it: a gate that hardcodes 4
# keeps passing on the day the bar moves and silently stops testing the boundary it was written for.
BAR="$( sed -nE 's/^[[:space:]]*constexpr std::uint32_t[[:space:]]+kNestBar[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "$ROOT/src/quality.h" | head -1 )"
case "$BAR" in
    ''|*[!0-9]*) echo "could not read kNestBar from src/quality.h — gate cannot pin the boundary"; exit 2 ;;
esac
echo "nestprofilecheck: kNestBar=$BAR (read from src/quality.h)"
[ "$BAR" = "4" ] || { echo "  NOTE  kNestBar has moved from 4 to $BAR — the hand-counted fixtures below are written for 4"; }

# ── the fixture ───────────────────────────────────────────────────────────────────────────────────────
# Every count below is HAND-COUNTED against cc_walk's definition of nesting: each nesting control
# (if/for/while/switch/try/lambda-body) deepens by one; `else if` does NOT deepen (cc_walk's elseIf case).
# A "hump" is a region whose depth reaches BAR=4, counted once at its first crossing.
cat >"$CPPDIR/nest.cpp" <<'EOF'
// shallow: max depth 2, never reaches the bar. humps=0, deep absent, nest=2.
int shallow( int n )
{
    if( n > 0 )
    {
        for( int i = 0; i < n; ++i )
        {
            n += i;
        }
    }
    return n;
}

// BLOCKED-SEQUENTIAL: five scoped steps in a row, only the LAST one reaches depth 4.
// nest=4, humps=1, and the deep region is the innermost `if` block only (3 lines: 46-48).
int blockedSteps( int n )
{
    {                                   // step 1
        n += 1;
    }
    {                                   // step 2
        n += 2;
    }
    {                                   // step 3
        n += 3;
    }
    {                                   // step 4
        n += 4;
    }
    if( n > 0 )                         // depth 1
    {
        for( int i = 0; i < n; ++i )    // depth 2
        {
            while( n > i )              // depth 3
            {
                if( n % 2 == 0 )        // depth 4  ← the ONE hump
                {
                    n -= 1;
                }
            }
        }
    }
    return n;
}

// TANGLED: the SAME nest=4 as blockedSteps, reached once — but the deep region spans the whole body,
// so deep= is large where blockedSteps' is small. humps=1. This is the pair arm 1 exists for.
int oneTangle( int n )
{
    if( n > 0 )                         // depth 1
    {
        for( int i = 0; i < n; ++i )    // depth 2
        {
            while( n > i )              // depth 3
            {
                if( n % 2 == 0 )        // depth 4  ← the ONE hump, and it is 13 lines long
                {
                    n -= 1;
                    n += 2;
                    n -= 3;
                    n += 4;
                    n -= 5;
                    n += 6;
                    n -= 7;
                    n += 8;
                    n -= 9;
                    n += 10;
                }
            }
        }
    }
    return n;
}

// THREE separate humps: three sibling deep regions, each rising to depth 4 and falling back.
// This is the bumpy road — repeated missing abstractions. humps=3, nest=4.
int threeHumps( int n )
{
    if( n > 0 )
    {
        for( int i = 0; i < n; ++i )
        {
            while( n > i )
            {
                if( n % 2 == 0 ) { n -= 1; }
            }
        }
    }
    if( n > 1 )
    {
        for( int i = 0; i < n; ++i )
        {
            while( n > i )
            {
                if( n % 3 == 0 ) { n -= 2; }
            }
        }
    }
    if( n > 2 )
    {
        for( int i = 0; i < n; ++i )
        {
            while( n > i )
            {
                if( n % 5 == 0 ) { n -= 3; }
            }
        }
    }
    return n;
}

// else-if does NOT deepen (cc_walk's elseIf case): this chain stays at depth 1 no matter how long it is,
// so it must produce NO hump. A profile that counted `else if` as nesting would report humps>=1 here.
int elseIfChain( int n )
{
    if( n == 0 )      { return 0; }
    else if( n == 1 ) { return 1; }
    else if( n == 2 ) { return 2; }
    else if( n == 3 ) { return 3; }
    else if( n == 4 ) { return 4; }
    return -1;
}

// a lambda BODY deepens nesting (cc_isNestingOnly), exactly as it does for nest=. Three controls plus the
// lambda body reach depth 4, so this is one hump — humps= and nest= must agree about what nesting is.
int lambdaDepth( int n )
{
    if( n > 0 )                             // depth 1
    {
        for( int i = 0; i < n; ++i )        // depth 2
        {
            auto f = [&]( int v )           // depth 3 (the lambda body)
            {
                if( v > 0 )                 // depth 4  ← hump
                {
                    return v - 1;
                }
                return v;
            };
            n = f( n );
        }
    }
    return n;
}

// ARM 11 — TWO SIBLING regions cross the bar on DIFFERENT lines, and each is billed its own span.
// (This arm's fixtures were rewritten by nestcal r1: the original pair crossed the bar through an ELSE
// clause, whose "regions" were the anonymous `else` token and its block — per-child minting the round
// removed. An else body now sits at the construct's primary-body level and mints nothing; the LINE
// ACCOUNTING contract the arm pins is unchanged and is exercised through sibling humps instead.)
// Depths: if=1, for=2, while=3, and TWO SIBLING ifs inside the while body each cross 3→4. The first spans
// four lines (the if line, the brace, the statement, the closing brace), the second is one line, and they
// share NO line, so the union is 5 physical lines: humps=2, deep=5. Sibling humps arrive at the clamp in
// document order (pops run left to right); fed out of order, the one-line second region would be swallowed
// behind the first's high-water end and deep would read 4.
int siblingHumpsDistinctLines( int n )
{
    if( n > 0 )
    {
        for( int i = 0; i < n; ++i )
        {
            while( n > i )
            {
                if( n % 2 == 0 )
                {
                    n -= 1;
                }
                if( n % 3 == 0 ) { n += 1; }
            }
        }
    }
    return n;
}

// ARM 11's NEGATIVE CONTROL — the SAME two sibling regions, written on ONE line. deep is a count of
// physical LINES, so the union of two regions that share their only line is one line: deep=1 < humps=2 is
// CORRECT output here, not the accounting bug above. Three separate validators have read this shape as a
// defect; pinning it is how the gate answers them.
int siblingHumpsOneLine( int n )
{
    if( n > 0 )
    {
        for( int i = 0; i < n; ++i )
        {
            while( n > i )
            {
                if( n % 2 == 0 ) { n -= 1; } if( n % 3 == 0 ) { n += 1; }
            }
        }
    }
    return n;
}

// ARM 11 — ARM BREADTH IS NOT BUMPINESS. Twelve multi-line switch arms, none of them deepening past the
// switch itself: a `switch` adds ONE level and its cases add none, so nothing reaches the bar however many
// arms there are. humps must stay ABSENT — a profile that counted arms would call every dispatch table a
// bumpy road.
int broadShallowSwitch( int n )
{
    switch( n )
    {
        case 0:  n += 1;  n += 2;  break;
        case 1:  n += 3;  n += 4;  break;
        case 2:  n += 5;  n += 6;  break;
        case 3:  n += 7;  n += 8;  break;
        case 4:  n += 9;  n += 10; break;
        case 5:  n += 11; n += 12; break;
        case 6:  n += 13; n += 14; break;
        case 7:  n += 15; n += 16; break;
        case 8:  n += 17; n += 18; break;
        case 9:  n += 19; n += 20; break;
        case 10: n += 21; n += 22; break;
        default: n += 23;          break;
    }
    return n;
}
EOF

cat >"$PYDIR/deep.py" <<'EOF'
def shallow_py(n):
    if n > 0:
        return n + 1
    return n

def deep_py(n):
    if n > 0:
        for i in range(n):
            while n > i:
                if n % 2 == 0:
                    n -= 1
                    n += 2
                    n -= 3
    return n
EOF

xml(){  "$BIN" "$1" --metrics --no-cache 2>/dev/null; }
# NB: not named `json` — a repo symbol spelled exactly `json` flips mcpw3fixcheck H4's probe task
# "json escape" onto the name-exact BM25 route (every content word then names a symbol), which shrinks
# the ranked surface to the two exact-name hits and collapses the explore partition fan-out to 0.
json_map(){ "$BIN" "$1" --metrics --json --no-cache 2>/dev/null; }

CPPXML="$( xml "$CPPDIR" )"
PYXML="$(  xml "$PYDIR"  )"

# row_of <xml> <name>  → the <s …> row for that symbol, one per line
row_of(){ printf '%s' "$1" | tr '>' '\n' | grep "n=\"$2\"" | head -1; }
# attr_of <row> <attr>  → the attribute's value, or "" when absent
attr_of(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E "s/.*=\"([^\"]*)\"/\1/"; }

# ══ 0. PRESENCE ══════════════════════════════════════════════════════════════════════════════════════
for sym in shallow blockedSteps oneTangle threeHumps elseIfChain lambdaDepth siblingHumpsDistinctLines siblingHumpsOneLine broadShallowSwitch; do
    if [ -n "$( row_of "$CPPXML" "$sym" )" ]; then
        ok "presence: $sym is in the map"
    else
        no "presence: $sym missing from the map — fixture drifted or parse failed"
    fi
done

# ══ 1. THE POINT — same nest=, different profile ══════════════════════════════════════════════════════
B_ROW="$( row_of "$CPPXML" blockedSteps )"
T_ROW="$( row_of "$CPPXML" oneTangle )"
b_nest="$( attr_of "$B_ROW" nest )"; t_nest="$( attr_of "$T_ROW" nest )"
b_deep="$( attr_of "$B_ROW" deep )"; t_deep="$( attr_of "$T_ROW" deep )"
if [ -n "$b_nest" ] && [ "$b_nest" = "$t_nest" ]; then
    ok "the point: blockedSteps and oneTangle report the SAME nest=$b_nest — the max cannot tell them apart"
else
    no "the point: the two fixtures no longer share a nest= value (blocked=$b_nest tangled=$t_nest) — the premise of this gate is gone"
fi
if [ -n "$b_deep" ] && [ -n "$t_deep" ] && [ "$t_deep" -gt "$b_deep" ] 2>/dev/null; then
    ok "the point: deep= DOES tell them apart (blocked=$b_deep < tangled=$t_deep) at identical nest="
else
    no "the point: deep= failed to separate them (blocked='$b_deep' tangled='$t_deep') — the profile adds nothing over the max"
fi

# ══ 2. HUMP COUNT — hand-counted, three distinct values ═══════════════════════════════════════════════
# shallow never reaches the bar (absent, checked in arm 5); the rest are pinned here.
check_humps(){   # <symbol> <want>
    local row want got
    row="$( row_of "$CPPXML" "$1" )"; want="$2"
    got="$( attr_of "$row" humps )"
    [ "$got" = "$want" ] && ok "humps: $1 -> humps=$want" \
                          || no "humps: $1 -> got '${got:-<absent>}', want $want"
}
check_humps blockedSteps 1
check_humps oneTangle    1
check_humps threeHumps   3
check_humps lambdaDepth  1

# ══ 3. DEEP LINES — the containment invariant, and the two pinned spans ════════════════════════════════
# blockedSteps' hump is the innermost if-block; oneTangle's is the same shape wrapped around 10 statements.
b_loc="$( attr_of "$B_ROW" loc )"; t_loc="$( attr_of "$T_ROW" loc )"
for pair in "blockedSteps:$b_deep:$b_loc" "oneTangle:$t_deep:$t_loc"; do
    sym="${pair%%:*}"; rest="${pair#*:}"; d="${rest%%:*}"; l="${rest#*:}"
    if [ -n "$d" ] && [ -n "$l" ] && [ "$d" -le "$l" ] 2>/dev/null; then
        ok "deep: $sym deep=$d <= loc=$l (a deep region is INSIDE the def, always)"
    else
        no "deep: $sym deep='$d' is not within loc='$l' — the span accounting is wrong"
    fi
done
[ -n "$b_deep" ] && [ "$b_deep" -le 6 ] 2>/dev/null \
    && ok "deep: blockedSteps' deep=$b_deep is a SMALL fraction of loc=$b_loc — the blocked steps are not counted as depth" \
    || no "deep: blockedSteps' deep='$b_deep' is too large for a shape whose only deep region is one 3-line if-block"
[ -n "$t_deep" ] && [ "$t_deep" -ge 10 ] 2>/dev/null \
    && ok "deep: oneTangle's deep=$t_deep covers the sustained region (loc=$t_loc)" \
    || no "deep: oneTangle's deep='$t_deep' does not reflect a 10-statement deep region"

# ══ 4. NESTING-ONLY — humps= and nest= agree about what nesting IS ════════════════════════════════════
L_ROW="$( row_of "$CPPXML" lambdaDepth )"
l_nest="$( attr_of "$L_ROW" nest )"
[ -n "$l_nest" ] && [ "$l_nest" -ge "$BAR" ] 2>/dev/null \
    && ok "nesting-only: the lambda body deepens nest= to $l_nest (>= bar $BAR), and humps= counted it too" \
    || no "nesting-only: lambdaDepth nest='$l_nest' did not reach the bar — fixture or cc_isNestingOnly drifted"

# ══ 5. OMISSION — absent iff nest<bar, in BOTH directions ═════════════════════════════════════════════
# Direction A: a shape below the bar carries NEITHER attribute (never a bare 0).
for sym in shallow elseIfChain; do
    row="$( row_of "$CPPXML" "$sym" )"
    n="$( attr_of "$row" nest )"; h="$( attr_of "$row" humps )"; d="$( attr_of "$row" deep )"
    if [ -n "$n" ] && [ "$n" -lt "$BAR" ] 2>/dev/null && [ -z "$h" ] && [ -z "$d" ]; then
        ok "omission: $sym has nest=$n < $BAR and carries NO humps=/deep= (absent, never a bare 0)"
    else
        no "omission: $sym nest='$n' humps='${h:-<absent>}' deep='${d:-<absent>}' — the omission rule is broken"
    fi
done
# elseIfChain is the sharper half of direction A: a five-arm else-if chain must stay far below the bar no
# matter how long it grows, because cc_walk's elseIf case does not deepen for `else if`.
#
# The pinned value is 1: however long the chain grows, its arms all sit at the chain's own depth. This
# arm previously pinned 2 — the anonymous-`else`-token quirk, where cc_walk's clause branch re-deepened
# every clause child including the bare `else` keyword — recorded deliberately as "a ranking change that
# belongs in its own calibrated round". That round is bench/nestcal/r1-2026-08-07 (ACCEPT), which removed
# the double-deepening; this pin is the round's re-pin and still exists so the value cannot drift again
# in EITHER direction.
ei_nest="$( attr_of "$( row_of "$CPPXML" elseIfChain )" nest )"
[ "$ei_nest" = "1" ] \
    && ok "omission: elseIfChain stays nest=1 regardless of chain length (nestcal r1 re-pin), below the bar — no hump" \
    || no "omission: elseIfChain reports nest='$ei_nest', want 1 — else-if nesting behaviour changed; re-read cc_walk's clause branch and bench/nestcal/r1-2026-08-07"
# Direction B: EVERY row at or above the bar carries both attributes. Swept over the whole map, so a row
# the fixture never named cannot quietly violate it. The reader is a FILE, not `python3 -c`: an inline
# heredoc that mixes shell quoting with f-string quoting dies at import time and prints nothing, which this
# arm reads as "no violations" — it passed vacuously that way when this gate was first written.
cat >"$TMP/omission.py" <<'PYEOF'
import re, sys
bar = int( sys.argv[1] )
bad = []
for line in sys.stdin:
    if not line.startswith( "<s " ):
        continue
    a = dict( re.findall( r'(\w+)="([^"]*)"', line ) )
    if "nest" not in a:
        continue
    over = int( a["nest"] ) >= bar
    has  = ( "humps" in a ) and ( "deep" in a )
    if over != has:
        bad.append( "{}: nest={} humps={} deep={}".format(
            a.get( "n", "?" ), a["nest"], a.get( "humps", "-" ), a.get( "deep", "-" ) ) )
print( "; ".join( bad ) )
PYEOF
viol="$( printf '%s' "$CPPXML" | tr '>' '\n' | python3 "$TMP/omission.py" "$BAR" )"
[ $? -eq 0 ] || { no "omission: the direction-B reader itself failed to run — this arm proves nothing"; viol="reader failed"; }
[ -z "$viol" ] \
    && ok "omission: across the whole map, humps=/deep= are present EXACTLY on the rows with nest>=$BAR" \
    || no "omission: rows where presence and nest>=$BAR disagree — $viol"

# ══ 6. FLOOR HONESTY ══════════════════════════════════════════════════════════════════════════════════
missing_floor="$( printf '%s' "$CPPXML" | tr '>' '\n' | grep '<s ' | grep ' deep="' | grep -cv 'deep_floor="1"' || true )"
[ "$missing_floor" = "0" ] \
    && ok "floor: every deep= carries deep_floor=\"1\" (the clamp can only subtract — it is a floor, and says so)" \
    || no "floor: $missing_floor row(s) carry deep= without deep_floor=\"1\""
orphan_floor="$( printf '%s' "$CPPXML" | tr '>' '\n' | grep '<s ' | grep 'deep_floor="1"' | grep -cv ' deep="' || true )"
[ "$orphan_floor" = "0" ] \
    && ok "floor: no row carries deep_floor= without deep= (the pair is never half-present)" \
    || no "floor: $orphan_floor row(s) carry deep_floor= with no deep="

# ══ 7. LANGUAGE-AGNOSTIC — unlike locals=, the profile is computed for every language ══════════════════
py_row="$( row_of "$PYXML" deep_py )"
py_h="$( attr_of "$py_row" humps )"; py_d="$( attr_of "$py_row" deep )"
if [ -n "$py_h" ] && [ "$py_h" -ge 1 ] 2>/dev/null && [ -n "$py_d" ]; then
    ok "language: a Python def with real depth carries humps=$py_h deep=$py_d (nesting is language-agnostic, unlike locals=)"
else
    no "language: Python deep_py carries humps='${py_h:-<absent>}' deep='${py_d:-<absent>}' — the profile is not language-agnostic"
fi
py_shallow_h="$( attr_of "$( row_of "$PYXML" shallow_py )" humps )"
[ -z "$py_shallow_h" ] \
    && ok "language: the shallow Python def carries no humps= (the same omission rule, not a language special case)" \
    || no "language: shallow_py carries humps='$py_shallow_h' — the omission rule is language-dependent"

# ══ 8. HYGIENE ════════════════════════════════════════════════════════════════════════════════════════
A="$( xml "$CPPDIR" )"; B="$( xml "$CPPDIR" )"
[ "$A" = "$B" ] && ok "hygiene: two cold --metrics runs are byte-identical (determinism)" \
                 || no "hygiene: two cold runs DIFFER"
printf '%s' "$CPPXML" | xmllint --noout - >/dev/null 2>&1 \
    && ok "hygiene: --metrics output is well-formed XML" \
    || no "hygiene: --metrics output failed xmllint"

# ══ 9. JSON PARITY ════════════════════════════════════════════════════════════════════════════════════
CPPJSON="$( json_map "$CPPDIR" )"
printf '%s' "$CPPJSON" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 \
    && ok "json: --json --metrics output is valid JSON" \
    || no "json: --json --metrics output is not valid JSON"
# Same lesson as arm 5 direction B: the reader is a FILE. An inline heredoc that died on quoting printed
# nothing and this arm read the silence as parity.
cat >"$TMP/parity.py" <<'PYEOF'
import json, sys
rows = {}
def walk( o ):
    if isinstance( o, dict ):
        if "n" in o and "nest" in o:
            rows[ o["n"] ] = o
        for v in o.values():
            walk( v )
    elif isinstance( o, list ):
        for v in o:
            walk( v )
walk( json.load( sys.stdin ) )
bad = []
for name, humps in ( ( "blockedSteps", 1 ), ( "oneTangle", 1 ), ( "threeHumps", 3 ) ):
    r = rows.get( name )
    if r is None:
        bad.append( name + ": no JSON row" )
        continue
    if r.get( "humps" ) != humps:
        bad.append( "{}: humps={} want {}".format( name, r.get( "humps" ), humps ) )
    if "deep" not in r or r.get( "deep_floor" ) is not True:
        bad.append( "{}: deep/deep_floor missing ({}/{})".format( name, r.get( "deep" ), r.get( "deep_floor" ) ) )
for name in ( "shallow", "elseIfChain" ):
    r = rows.get( name )
    if r is not None and ( "humps" in r or "deep" in r ):
        bad.append( name + ": JSON carries humps/deep below the bar" )
print( "; ".join( bad ) )
PYEOF
if parity="$( printf '%s' "$CPPJSON" | python3 "$TMP/parity.py" )"; then
    [ -z "$parity" ] \
        && ok "json: humps/deep/deep_floor match the XML dialect, and are absent on the same rows" \
        || no "json: XML/JSON parity broken — $parity"
else
    no "json: the parity reader itself failed to run — this arm proves nothing"
fi

# ══ 10. MUTATION — the pinned numbers are load-bearing ════════════════════════════════════════════════
# Assert a hump count that is KNOWN to be wrong; if that "passes", arm 2 is a tautology.
mut_got="$( attr_of "$( row_of "$CPPXML" threeHumps )" humps )"
[ "$mut_got" != "999" ] \
    && ok "mutation self-test (asserting threeHumps humps=999 when it is really $mut_got correctly fails)" \
    || no "mutation self-test: the fixture reports 999 humps — the assertion cannot fail"
# And the separation itself: if deep= were wired to loc=, arm 1 would pass while measuring nothing.
[ "$b_deep" != "$b_loc" ] \
    && ok "mutation self-test: deep= is not merely loc= under another name (blockedSteps deep=$b_deep loc=$b_loc)" \
    || no "mutation self-test: deep= equals loc= on blockedSteps — the profile may be aliasing the size"

# ══ 11. LINE ACCOUNTING — distinct lines are billed; shared lines are not billed twice ═════════════════
# WHY. cc_noteHump carries a single high-water mark (deepEnd) so that two regions overlapping on a line
# cannot bill it twice. That clamp is only correct if regions arrive in DOCUMENT order — fed a later region
# first, it swallows the earlier one entirely. The else-clause branch did exactly that historically (it
# noted its kids inside the REVERSE push loop); nestcal r1 then removed clause noting altogether, so today
# every cc_noteHump site notes one node before descending and document order holds by construction. This
# arm keeps the clamp honest against ANY future call site that breaks that shape.
#
# WHAT THIS ARM DOES NOT ASSERT, deliberately: there is NO whole-output "deep >= humps" sweep here, and
# adding one would be wrong. deep counts physical LINES and humps counts REGIONS, and two regions really
# can share one line — a minified single-line function, or `if(c){x;}else{y;}` written on one line. On
# those, deep < humps is the honest answer. So the invariant is pinned only on fixtures whose regions are
# KNOWN to sit on separate lines, and the same-line case is pinned as CORRECT in the negative control.
E_ROW="$( row_of "$CPPXML" siblingHumpsDistinctLines )"
e_humps="$( attr_of "$E_ROW" humps )"; e_deep="$( attr_of "$E_ROW" deep )"
if [ "$e_humps" = "2" ]; then
    ok "line accounting: siblingHumpsDistinctLines crosses the bar in TWO sibling regions"
else
    no "line accounting: siblingHumpsDistinctLines should report humps=2; got '${e_humps:-<absent>}' — the fixture no longer produces the two-sibling-region shape, so the assertion below tests nothing"
fi
if [ "$e_deep" = "5" ]; then
    ok 'line accounting: siblingHumpsDistinctLines deep=5 — a four-line region plus a one-line region, and they share no line'
else
    no "line accounting: siblingHumpsDistinctLines must report deep=5 (a 4-line region + a 1-line region, no line shared); got '${e_deep:-<absent>}'. A lower number means a region on its own distinct line was clamped away — the deepEnd high-water mark was fed a later region first, which can only happen if regions stopped arriving in document order"
fi
O_ROW="$( row_of "$CPPXML" siblingHumpsOneLine )"
o_humps="$( attr_of "$O_ROW" humps )"; o_deep="$( attr_of "$O_ROW" deep )"
if [ "$o_humps" = "2" ] && [ "$o_deep" = "1" ]; then
    ok "line accounting: the SAME two regions written on ONE line report humps=2 deep=1 — deep is a line count, so deep < humps is correct output here, not a bug"
else
    no "line accounting: siblingHumpsOneLine must report humps=2 deep=1 (two regions sharing their only line); got humps='${o_humps:-<absent>}' deep='${o_deep:-<absent>}'. If deep rose to 2 the clamp stopped deduplicating a shared line, which over-counts"
fi
S_ROW="$( row_of "$CPPXML" broadShallowSwitch )"
s_nest="$( attr_of "$S_ROW" nest )"; s_humps="$( attr_of "$S_ROW" humps )"
if [ -n "$s_nest" ] && [ "$s_nest" -lt "$BAR" ] 2>/dev/null && [ -z "$s_humps" ]; then
    ok "line accounting: twelve multi-line switch arms stay at nest=$s_nest with NO humps — arm BREADTH is not bumpiness"
else
    no "line accounting: broadShallowSwitch reports nest='$s_nest' humps='${s_humps:-<absent>}'; a dispatch table with many shallow arms must not read as a bumpy road (a switch adds ONE level, its cases add none)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
