#!/usr/bin/env bash
# essentialcxcheck.sh — McCabe ESSENTIAL COMPLEXITY ev(G): what remains after every structured region
# collapses. The essential-complexity design note (untracked, like the readability-metrics note ensemble.h cites) is the contract; this gate was written FIRST and confirmed
# RED against the pre-feature binary (non-negotiable #1).
#
# WHY THIS EXISTS. cx/ccx/loc/nest all measure HOW MUCH structure there is; ev= measures whether the
# pieces COME APART. A 300-line switch dispatcher has cx=41 and ev=1 (enormous, trivially decomposable);
# a 25-line function with one break buried two ifs deep has cx=5 and ev=5 (small, and stuck). Nothing
# else on the row separates those two.
#
# THE RULE (design §2.2, strict single-exit McCabe — §10.1 Option A as resolved by the owner):
#   a jump (break/continue/return/throw/goto/redo/retry/fallthrough) marks IRREDUCIBLE every control
#   construct STRICTLY BETWEEN it and its target; irreducibility then propagates OUTWARD to the function
#   root (stopping at closure/lambda/nested-fn boundaries); a marked switch head contributes EVERY arm.
#   ev = 1 + Σ (own cx decision weight of every marked construct).  Weights mirror isDecisionType
#   exactly, so ev <= cx is structural, not hoped for.
#
# §2.7 RECONCILIATION RECORD (the design's flagged correctness risk, discharged before these numbers
# were pinned). An INDEPENDENT reference implementation — a hand-encoded REAL CFG per fixture plus a
# classic structured-prime reduction (sequence / if-then / if-then-else / case / while / do-while) to
# fixpoint, ev = E-N+2 of the residue; scratchpad refev.py, deliberately not committed — was run over
# 11 shapes covering every row of the design's §2.2 worked table. Outcome:
#   * 10/11 agree exactly with the marking rule above, INCLUDING the outward-propagation half that the
#     design named as its single largest correctness risk (deepEscape=4, smallTangledLoop=5) and the
#     goto/LCA path (gotoCross=3).
#   * 1 disagreement found and reconciled AGAINST THE REFERENCE: the reference's switchBreakEscape CFG
#     first read 4 because the hand-encoding omitted the implicit no-match edge of a default-less C
#     switch; with the real edge restored it reads 5, agreeing with the rule. The error was in the
#     fixture encoding, not in either implementation.
#   * 1 CONVENTION DELTA, recorded rather than "fixed": on a switch whose arms include `default:` the
#     CFG residue arithmetic charges arms-1 (no implicit path), while ev's weights mirror ripwire's cx
#     convention (every case_statement counts, default included) so that ev <= cx stays structural.
#     Same delta, same direction, on both sides of the inequality; disclosed here and in model.h.
#   * The Böhm–Jacopini-PERMISSIVE convention (virtual-exit joins allowed) was also run: it reduces
#     guardClause / bothArmsReturn / continueGuard to 1 where strict single-exit reads 2/2/3. That is
#     §1.3's known Option-A over-fire, made subtractable by ev_why= (guard-return tags) — a definitional
#     choice the owner resolved in §10.1, not an arithmetic disagreement.
#
# ── ARMS (design §7.2) ────────────────────────────────────────────────────────────────────────────────
#   0. PRESENCE      — every fixture symbol, every language, is in the map (a parse failure must not
#                      read as a clean ev).
#   1. THE POINT     — bigStructuredSwitch (cx=6, ev absent) vs smallTangledLoop (cx=5, ev=5): cx within
#                      1 of each other, told apart only by ev.
#   2. HAND-COUNTED  — ~15 C++ fixtures with expected ev covering 1,2,3,4,5 (>=3 distinct nonzero values,
#                      so a stub constant cannot pass).
#   3. ev <= cx      — swept over EVERY row of the whole fixture map, with a row-count positive control.
#   4. OMISSION      — (A) structured fixtures carry NO ev=/ev_floor=/ev_why= (absent means exactly 1 on
#                      a cx row, never a bare "1"); (B) whole-map sweep: ev= present ⟺ ev>=2 ⟺ ev_why
#                      non-empty.
#   5. FLOOR HONESTY — every ev= carries ev_floor="1"; the triple is never half-present.
#   6. NOT-COUNTED   — Rust `?`; `?`+break isolating the break; JS generator yield; C++ &&/||; a
#                      switch with break-per-arm; Go defer; Swift `try`; C# `yield return`.
#   7. LANGUAGE      — hand-computed values for C++ goto, Python return-in-loop + break-out-of-match,
#                      Go labelled break + fallthrough, Rust labelled break, Swift guard (counted) vs
#                      try (not), JS labelled continue + arrow-fn barrier, Java labelled break,
#                      Ruby redo + block-next, C# goto case.
#   8. HYGIENE       — two cold runs byte-identical; xmllint clean; --json parses; top-level function
#                      REORDER yields identical per-symbol ev (order independence, stronger than deep=).
#   9. JSON PARITY   — ev/ev_floor/ev_why on exactly the same rows with the same values; file reader,
#                      exit status checked.
#  10. NO RANKING CHANGE — (a) rows with ev>=2 that clear no structural bar are ABSENT from the quality
#                      panel (ev fires nothing, joins no family); (b) source-level: `s.ev`/`.ev` is read
#                      nowhere outside the two serialize.h emitters, the single why=-annotation line in
#                      ensemble.h (itself gated on the family ALREADY firing), and the compute/wire code
#                      in ingest.cpp/model.h.
#  11. MUTATION      — a knowingly-wrong ev on a pinned fixture fails; ev != cx on one fixture and
#                      ev != 1 on another (ev is neither cx renamed nor a constant).
#
# Reader discipline (nestprofilecheck's recorded lesson): every python reader is a FILE under $TMP,
# invoked as `python3 "$TMP/x.py"`, exit status checked; empty output is only read as "clean" on arms
# with a positive control.
#
# Usage:
#   bash test/essentialcxcheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/essentialcxcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3  >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "essentialcxcheck: BIN=$BIN  TMP=$TMP"

CPPDIR="$TMP/cpp";   mkdir -p "$CPPDIR"
PYDIR="$TMP/py";     mkdir -p "$PYDIR"
RSDIR="$TMP/rs";     mkdir -p "$RSDIR"
SWDIR="$TMP/swift";  mkdir -p "$SWDIR"
GODIR="$TMP/go";     mkdir -p "$GODIR"
JSDIR="$TMP/js";     mkdir -p "$JSDIR"
JAVADIR="$TMP/java"; mkdir -p "$JAVADIR"
RBDIR="$TMP/rb";     mkdir -p "$RBDIR"
CSDIR="$TMP/cs";     mkdir -p "$CSDIR"

# ── the C++ fixture ───────────────────────────────────────────────────────────────────────────────────
# Every ev below is HAND-COUNTED against the §2.2 rule and cross-checked per the reconciliation record
# in this header. cx counts are 1 + decision nodes (case arms count; && / || count toward cx only).
cat >"$CPPDIR/ev.cpp" <<'EOF'
// cx=3 (2 ifs... if + for), no jump but the tail return: ev ABSENT (fully structured).
int plainStructured( int n )
{
    if( n > 0 ) { n += 1; }
    for( int i = 0; i < n; ++i ) { n -= 1; }
    return n;
}

// cx=6 (5 case arms + base), ev ABSENT: every break sits at its arm's tail — the case prime's normal
// exit (design §2.2 row 1). Enormous and trivially decomposable. Arm 1's left half.
int bigStructuredSwitch( int x )
{
    switch( x )
    {
        case 1: x += 1; break;
        case 2: x += 2; break;
        case 3: x += 3; break;
        case 4: x += 4; break;
        case 5: x += 5; break;
    }
    return x;
}

// cx=5, ev=5: the break targets the while with the if strictly between; propagation keeps if(n>0)
// and the for in the residue too. Small, and stuck. Arm 1's right half (design §7.3 verbatim shape).
int smallTangledLoop( int n )
{
    for( int i = 0; i < n; ++i )
    {
        if( n > 0 )
        {
            while( n-- )
            {
                if( n % 2 ) { break; }
            }
        }
    }
    return n;
}

// cx=4, ev=2: ONE guard clause (strict single-exit counts it; ev_why makes it subtractable). The two
// structured ifs below the guard stay out of the residue, so ev != cx here (arm 11's separation pin).
int guardClause( int n )
{
    if( n < 0 ) { return 0; }
    if( n > 10 ) { n -= 1; }
    if( n > 20 ) { n -= 2; }
    return n;
}

// cx=3, ev=3: two SEQUENTIAL guards — each marks its own if; guard-return:2.
int guardTwo( int n )
{
    if( n < 0 ) { return 0; }
    if( n == 0 ) { return 1; }
    return n + 2;
}

// cx=3, ev=3: the canonical branch-out-of-a-loop (design §2.2 row 3).
int loopEscape( int n )
{
    while( n > 0 )
    {
        if( n == 7 ) { break; }
        n -= 1;
    }
    return n;
}

// cx=4, ev=4: outward propagation — the outer if's branch contains an uncollapsed blob, so the outer
// if is not a prime either (design §2.2 row 5, the flagged-risk row; reference-confirmed).
int deepEscape( int n )
{
    if( n > 0 )
    {
        while( n > 2 )
        {
            if( n % 3 ) { break; }
            n -= 1;
        }
    }
    return n;
}

// cx=5, ev=5: a break under an if escapes the SWITCH; the marked switch contributes every arm, and the
// enclosing for joins the residue by propagation. The arm-tail breaks are free.
int switchBreakEscape( int n )
{
    for( int i = 0; i < n; ++i )
    {
        switch( n )
        {
            case 1: if( n > 4 ) { break; } n += 1; break;
            case 2: n += 2; break;
        }
    }
    return n;
}

// cx=3, ev=3: goto across the loop boundary (LCA at function root; both paths marked).
int gotoCross( int n )
{
    while( n > 0 )
    {
        if( n == 7 ) { goto out; }
        n -= 1;
    }
    n += 5;
out:
    return n;
}

// cx=3, ev=3: a conditional continue is a second exit of the if under strict single-exit.
int continueGuard( int n )
{
    for( int i = 0; i < n; ++i )
    {
        if( n % 2 ) { continue; }
        n -= 1;
    }
    return n;
}

// cx=4 (if + && + ||), ev ABSENT: short-circuit operators form a prime that collapses first — they
// count toward cx and NEVER toward ev (arm 6's containment case).
int boolNotCounted( int a, int b, int c )
{
    int n = 0;
    if( ( a > 0 && b > 0 ) || c > 0 ) { n = 1; }
    return n;
}

// cx=2, ev=2: both arms return — two exits under the single-exit discipline; guard-return:2.
int bothArmsReturn( int c )
{
    if( c > 0 ) { return 1; }
    else { return 2; }
}

// cx=2, ev=2: a throw with no enclosing try targets the function — same shape as a guard return.
int throwGuard( int n )
{
    if( n < 0 ) { throw n; }
    return n;
}

// cx=3 (if + catch), ev=2: the throw targets its enclosing try; only the if sits strictly between.
// The catch clause is NOT on the chain and stays out of the residue.
int tryLocalThrow( int n )
{
    try
    {
        if( n > 2 ) { throw n; }
        n += 1;
    }
    catch( ... ) { n = 0; }
    return n;
}

// cx=3, ev=2: the guard lives INSIDE the lambda; the lambda is a function boundary, so the mark stays
// inside it and the outer for never joins the residue (fn-barrier pin).
int lambdaContained( int n )
{
    for( int i = 0; i < n; ++i )
    {
        auto f = [ & ]( int v ) { if( v < 0 ) { return -1; } return v; };
        n = f( n );
    }
    return n;
}
EOF

cat >"$PYDIR/ev_py.py" <<'EOF'
def py_structured(n):
    if n > 0:
        n += 1
    for i in range(n):
        n -= 1
    return n

def py_return_in_loop(xs):
    for x in xs:
        if x:
            return 1
    return 0

def py_break_match_in_loop(xs):
    t = 0
    for x in xs:
        match x:
            case 1:
                if t:
                    break
            case _:
                t += 1
    return t

def py_raise_in_try(n):
    try:
        if n > 0:
            raise ValueError(n)
        n += 1
    except ValueError:
        n = 0
    return n
EOF

cat >"$RSDIR/ev_rs.rs" <<'EOF'
fn rs_question_only(n: i32) -> Result<i32, ()> {
    let x = rs_helper(n)?;
    let y = rs_helper(x)?;
    Ok(x + y)
}

fn rs_question_plus_break(n: i32) -> Result<i32, ()> {
    let mut t = 0;
    for i in 0..n {
        if i > 3 { break; }
        t += rs_helper(i)?;
    }
    Ok(t)
}

fn rs_labelled(n: i32) -> i32 {
    let mut t = 0;
    'outer: loop {
        for i in 0..n {
            if i == 7 { break 'outer; }
            t += i;
        }
    }
    t
}

fn rs_helper(n: i32) -> Result<i32, ()> { Ok(n) }
EOF

cat >"$SWDIR/ev_swift.swift" <<'EOF'
func swiftGuardExit(n: Int) -> Int {
    guard n > 0 else { return 0 }
    return n + 1
}

func swiftTryNotCounted(n: Int) throws -> Int {
    let v = try swiftHelper(n)
    return v + 1
}

func swiftLoopEscape(xs: [Int]) -> Int {
    var t = 0
    for x in xs {
        if x == 3 { break }
        t += x
    }
    return t
}

func swiftHelper(_ n: Int) throws -> Int { return n }
EOF

cat >"$GODIR/ev_go.go" <<'EOF'
package evgo

func goLabelled(n int) int {
	t := 0
outer:
	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			if j == 7 {
				break outer
			}
			t += j
		}
	}
	return t
}

func goFallthrough(n int) int {
	t := 0
	switch n {
	case 1:
		t++
		fallthrough
	case 2:
		t += 2
	}
	return t
}

func goDefer(n int) int {
	t := n
	defer goHelper(t)
	t += 1
	return t
}

func goHelper(n int) int { return n }
EOF

cat >"$JSDIR/ev_js.js" <<'EOF'
function jsLabelled(n) {
  let t = 0;
  outer: for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      if (j === 7) continue outer;
      t += j;
    }
  }
  return t;
}

function* jsGenerator(n) {
  yield n;
  yield n + 1;
  return n;
}

function jsArrowContained(n) {
  const f = (v) => { if (v < 0) return -1; return v; };
  return f(n);
}
EOF

cat >"$JAVADIR/EvJ.java" <<'EOF'
class EvJ {
    int javaLabelled(int n) {
        int t = 0;
        outer: for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++) {
                if (j == 7) break outer;
                t += j;
            }
        }
        return t;
    }
}
EOF

cat >"$RBDIR/ev_rb.rb" <<'EOF'
def redo_loop(n)
  t = 0
  while t < n
    t += 1
    redo if t == 99
  end
  t
end

def next_block(xs)
  xs.each do |x|
    next if x.nil?
  end
  0
end
EOF

cat >"$CSDIR/EvC.cs" <<'EOF'
class EvC {
    int GotoCase(int n) {
        switch (n) {
            case 1: n += 1; break;
            case 2: goto case 1;
        }
        return n;
    }
    System.Collections.Generic.IEnumerable<int> YieldNotCounted(int n) {
        if (n > 0) { yield return 1; }
        yield break;
    }
}
EOF

xml(){  "$BIN" "$1" --metrics --no-cache 2>/dev/null; }
json_map(){ "$BIN" "$1" --metrics --json --no-cache 2>/dev/null; }

CPPXML="$(   xml "$CPPDIR" )"
PYXML="$(    xml "$PYDIR" )"
RSXML="$(    xml "$RSDIR" )"
SWXML="$(    xml "$SWDIR" )"
GOXML="$(    xml "$GODIR" )"
JSXML="$(    xml "$JSDIR" )"
JAVAXML="$(  xml "$JAVADIR" )"
RBXML="$(    xml "$RBDIR" )"
CSXML="$(    xml "$CSDIR" )"

# row_of <xml> <name>  → the <s …> row for that symbol; attr_of <row> <attr> → value or "" when absent
row_of(){ printf '%s' "$1" | tr '>' '\n' | grep "n=\"$2\"" | head -1; }
attr_of(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E "s/.*=\"([^\"]*)\"/\1/"; }

# ══ 0. PRESENCE ══════════════════════════════════════════════════════════════════════════════════════
for spec in \
    "CPP:plainStructured" "CPP:bigStructuredSwitch" "CPP:smallTangledLoop" "CPP:guardClause" \
    "CPP:guardTwo" "CPP:loopEscape" "CPP:deepEscape" "CPP:switchBreakEscape" "CPP:gotoCross" \
    "CPP:continueGuard" "CPP:boolNotCounted" "CPP:bothArmsReturn" "CPP:throwGuard" \
    "CPP:tryLocalThrow" "CPP:lambdaContained" \
    "PY:py_structured" "PY:py_return_in_loop" "PY:py_break_match_in_loop" "PY:py_raise_in_try" \
    "RS:rs_question_only" "RS:rs_question_plus_break" "RS:rs_labelled" \
    "SW:swiftGuardExit" "SW:swiftTryNotCounted" "SW:swiftLoopEscape" \
    "GO:goLabelled" "GO:goFallthrough" "GO:goDefer" \
    "JS:jsLabelled" "JS:jsGenerator" "JS:jsArrowContained" \
    "JAVA:javaLabelled" "RB:redo_loop" "RB:next_block" "CS:GotoCase" "CS:YieldNotCounted"; do
    lang="${spec%%:*}"; sym="${spec#*:}"
    case "$lang" in
        CPP) doc="$CPPXML" ;; PY) doc="$PYXML" ;; RS) doc="$RSXML" ;; SW) doc="$SWXML" ;;
        GO) doc="$GOXML" ;; JS) doc="$JSXML" ;; JAVA) doc="$JAVAXML" ;; RB) doc="$RBXML" ;; CS) doc="$CSXML" ;;
    esac
    if [ -n "$( row_of "$doc" "$sym" )" ]; then
        ok "presence: $sym ($lang) is in the map"
    else
        no "presence: $sym ($lang) missing — fixture drifted or parse failed"
    fi
done

# ══ 1. THE POINT ═════════════════════════════════════════════════════════════════════════════════════
B_ROW="$( row_of "$CPPXML" bigStructuredSwitch )"
T_ROW="$( row_of "$CPPXML" smallTangledLoop )"
b_cx="$( attr_of "$B_ROW" cx )"; t_cx="$( attr_of "$T_ROW" cx )"
b_ev="$( attr_of "$B_ROW" ev )"; t_ev="$( attr_of "$T_ROW" ev )"
if [ -n "$b_cx" ] && [ -n "$t_cx" ] && [ "$(( b_cx - t_cx ))" -ge -1 ] 2>/dev/null && [ "$(( b_cx - t_cx ))" -le 1 ] 2>/dev/null; then
    ok "the point: bigStructuredSwitch cx=$b_cx and smallTangledLoop cx=$t_cx are within 1 — cx cannot tell them apart"
else
    no "the point: the pair no longer share a comparable cx (big=$b_cx tangled=$t_cx) — the premise of this gate is gone"
fi
if [ -z "$b_ev" ] && [ "$t_ev" = "5" ]; then
    ok "the point: ev DOES tell them apart — big switch ABSENT (=1, decomposable) vs tangle ev=5 (stuck)"
else
    no "the point: ev failed to separate them (big='${b_ev:-<absent>}' want absent; tangled='${t_ev:-<absent>}' want 5)"
fi

# ══ 2. HAND-COUNTED VALUES (C++) ═════════════════════════════════════════════════════════════════════
check_ev(){   # <doc> <symbol> <want ev, or - for absent> [<want ev_why>]
    local doc="$1" sym="$2" want="$3" wantwhy="${4:-}"
    local row got gotwhy
    row="$( row_of "$doc" "$sym" )"
    got="$( attr_of "$row" ev )"
    if [ "$want" = "-" ]; then
        [ -z "$got" ] && ok "ev: $sym -> absent (structured)" \
                       || no "ev: $sym -> got ev='$got', want ABSENT"
        return
    fi
    [ "$got" = "$want" ] && ok "ev: $sym -> ev=$want" \
                          || no "ev: $sym -> got '${got:-<absent>}', want $want"
    if [ -n "$wantwhy" ]; then
        gotwhy="$( attr_of "$row" ev_why )"
        [ "$gotwhy" = "$wantwhy" ] && ok "ev_why: $sym -> $wantwhy" \
                                    || no "ev_why: $sym -> got '${gotwhy:-<absent>}', want '$wantwhy'"
    fi
}
check_ev "$CPPXML" plainStructured    -
check_ev "$CPPXML" bigStructuredSwitch -
check_ev "$CPPXML" smallTangledLoop   5 "loop-escape:1"
check_ev "$CPPXML" guardClause        2 "guard-return:1"
check_ev "$CPPXML" guardTwo           3 "guard-return:2"
check_ev "$CPPXML" loopEscape         3 "loop-escape:1"
check_ev "$CPPXML" deepEscape         4 "loop-escape:1"
check_ev "$CPPXML" switchBreakEscape  5 "switch-escape:1"
check_ev "$CPPXML" gotoCross          3 "goto:1"
check_ev "$CPPXML" continueGuard      3 "loop-escape:1"
check_ev "$CPPXML" bothArmsReturn     2 "guard-return:2"
check_ev "$CPPXML" throwGuard         2 "guard-return:1"
check_ev "$CPPXML" tryLocalThrow      2 "guard-return:1"
check_ev "$CPPXML" lambdaContained    2 "guard-return:1"

# ══ 3. ev <= cx INVARIANT — every row of the whole map, with a positive control ══════════════════════
cat >"$TMP/evlecx.py" <<'PYEOF'
import re, sys
rows = 0
bad = []
for line in sys.stdin:
    if not line.startswith( "<s " ):
        continue
    a = dict( re.findall( r'(\w+)="([^"]*)"', line ) )
    if "cx" not in a:
        continue
    rows += 1
    if "ev" in a and int( a["ev"] ) > int( a["cx"] ):
        bad.append( "{}: ev={} > cx={}".format( a.get( "n", "?" ), a["ev"], a["cx"] ) )
print( rows )
print( "; ".join( bad ) )
PYEOF
ALLXML="$CPPXML
$PYXML
$RSXML
$SWXML
$GOXML
$JSXML
$JAVAXML
$RBXML
$CSXML"
if out="$( printf '%s' "$ALLXML" | tr '>' '\n' | python3 "$TMP/evlecx.py" )"; then
    rowcount="$( printf '%s\n' "$out" | sed -n 1p )"
    viol="$( printf '%s\n' "$out" | sed -n 2p )"
    if [ -n "$rowcount" ] && [ "$rowcount" -gt 20 ] 2>/dev/null && [ -z "$viol" ]; then
        ok "invariant: ev <= cx on every one of the $rowcount cx-bearing rows across all nine languages"
    elif [ -n "$viol" ]; then
        no "invariant: ev > cx somewhere — $viol"
    else
        no "invariant: the sweep saw only '$rowcount' rows — the positive control failed, this arm proves nothing"
    fi
else
    no "invariant: the ev<=cx reader itself failed to run — this arm proves nothing"
fi

# ══ 4. OMISSION, BOTH DIRECTIONS ═════════════════════════════════════════════════════════════════════
for sym in plainStructured bigStructuredSwitch boolNotCounted; do
    row="$( row_of "$CPPXML" "$sym" )"
    e="$( attr_of "$row" ev )"; f="$( attr_of "$row" ev_floor )"; w="$( attr_of "$row" ev_why )"
    if [ -n "$( attr_of "$row" cx )" ] && [ -z "$e" ] && [ -z "$f" ] && [ -z "$w" ]; then
        ok "omission A: $sym carries cx= and NO ev=/ev_floor=/ev_why= — absent means exactly 1, never a bare \"1\""
    else
        no "omission A: $sym ev='${e:-<absent>}' ev_floor='${f:-<absent>}' ev_why='${w:-<absent>}' — the omission rule is broken"
    fi
done
cat >"$TMP/omission.py" <<'PYEOF'
import re, sys
bad = []
for line in sys.stdin:
    if not line.startswith( "<s " ):
        continue
    a = dict( re.findall( r'(\w+)="([^"]*)"', line ) )
    has_ev = "ev" in a
    if has_ev and int( a["ev"] ) < 2:
        bad.append( a.get( "n", "?" ) + ": emitted ev=" + a["ev"] + " < 2" )
    if has_ev and not a.get( "ev_why", "" ):
        bad.append( a.get( "n", "?" ) + ": ev= without a non-empty ev_why=" )
    if not has_ev and ( "ev_why" in a or "ev_floor" in a ):
        bad.append( a.get( "n", "?" ) + ": ev_why=/ev_floor= without ev=" )
print( "; ".join( bad ) )
PYEOF
if viol="$( printf '%s' "$ALLXML" | tr '>' '\n' | python3 "$TMP/omission.py" )"; then
    [ -z "$viol" ] \
        && ok "omission B: across all nine maps, ev= is present exactly with ev>=2 and a non-empty ev_why=" \
        || no "omission B: $viol"
else
    no "omission B: the reader itself failed to run — this arm proves nothing"
fi

# ══ 5. FLOOR HONESTY ═════════════════════════════════════════════════════════════════════════════════
missing_floor="$( printf '%s' "$ALLXML" | tr '>' '\n' | grep '<s ' | grep ' ev="' | grep -cv 'ev_floor="1"' || true )"
[ "$missing_floor" = "0" ] \
    && ok "floor: every ev= carries ev_floor=\"1\" (noreturn calls / macro-hidden exits are unseen — a floor, and says so)" \
    || no "floor: $missing_floor row(s) carry ev= without ev_floor=\"1\""
orphan_floor="$( printf '%s' "$ALLXML" | tr '>' '\n' | grep '<s ' | grep 'ev_floor="1"' | grep -cv ' ev="' || true )"
[ "$orphan_floor" = "0" ] \
    && ok "floor: no row carries ev_floor= without ev= (the triple is never half-present)" \
    || no "floor: $orphan_floor row(s) carry ev_floor= with no ev="

# ══ 6. NOT-COUNTED — the exclusions, each asserting ABSENCE (or containment) ═════════════════════════
check_ev "$RSXML" rs_question_only      -
check_ev "$RSXML" rs_question_plus_break 3 "loop-escape:1"
check_ev "$JSXML" jsGenerator           -
check_ev "$CPPXML" boolNotCounted       -
check_ev "$GOXML" goDefer               -
check_ev "$SWXML" swiftTryNotCounted    -
check_ev "$CSXML" YieldNotCounted       -

# ══ 7. LANGUAGE — one hand-computed value per language-specific target rule ══════════════════════════
check_ev "$PYXML" py_structured         -
check_ev "$PYXML" py_return_in_loop     3 "guard-return:1"
check_ev "$PYXML" py_break_match_in_loop 3 "loop-escape:1"
check_ev "$PYXML" py_raise_in_try       2 "guard-return:1"
check_ev "$RSXML" rs_labelled           4 "labelled-jump:1"
check_ev "$SWXML" swiftGuardExit        2 "guard-return:1"
check_ev "$SWXML" swiftLoopEscape       3 "loop-escape:1"
check_ev "$GOXML" goLabelled            4 "labelled-jump:1"
check_ev "$GOXML" goFallthrough         3 "fallthrough:1"
check_ev "$JSXML" jsLabelled            4 "labelled-jump:1"
check_ev "$JSXML" jsArrowContained      2 "guard-return:1"
check_ev "$JAVAXML" javaLabelled        4 "labelled-jump:1"
check_ev "$RBXML" redo_loop             3 "back-edge:1"
check_ev "$RBXML" next_block            2 "loop-escape:1"
check_ev "$CSXML" GotoCase              3 "goto:1"

# ══ 8. HYGIENE — determinism, well-formedness, order independence ════════════════════════════════════
A="$( xml "$CPPDIR" )"; B="$( xml "$CPPDIR" )"
[ "$A" = "$B" ] && ok "hygiene: two cold --metrics runs are byte-identical (determinism)" \
                 || no "hygiene: two cold runs DIFFER"
printf '%s' "$CPPXML" | xmllint --noout - >/dev/null 2>&1 \
    && ok "hygiene: --metrics output is well-formed XML" \
    || no "hygiene: --metrics output failed xmllint"
# order independence: reverse the top-level function order; per-symbol ev must be identical.
REORDDIR="$TMP/reord"; mkdir -p "$REORDDIR"
cat >"$TMP/reorder.py" <<'PYEOF'
import re, sys
src = open( sys.argv[1] ).read()
# split on blank-line boundaries between top-level definitions (each fixture fn is comment+body)
chunks = [ c for c in src.split( "\n\n" ) if c.strip() ]
open( sys.argv[2], "w" ).write( "\n\n".join( reversed( chunks ) ) + "\n" )
PYEOF
if python3 "$TMP/reorder.py" "$CPPDIR/ev.cpp" "$REORDDIR/ev.cpp"; then
    RXML="$( xml "$REORDDIR" )"
    cat >"$TMP/evpairs.py" <<'PYEOF'
import re, sys
for line in sys.stdin:
    if line.startswith( "<s " ):
        a = dict( re.findall( r'(\w+)="([^"]*)"', line ) )
        if "cx" in a:
            print( a.get( "n", "?" ), a.get( "ev", "-" ), a.get( "ev_why", "-" ) )
PYEOF
    P1="$( printf '%s' "$CPPXML" | tr '>' '\n' | python3 "$TMP/evpairs.py" | sort )"
    P2="$( printf '%s' "$RXML"   | tr '>' '\n' | python3 "$TMP/evpairs.py" | sort )"
    if [ -n "$P1" ] && [ "$P1" = "$P2" ]; then
        ok "hygiene: reordering the top-level functions leaves every per-symbol ev/ev_why identical (order independence)"
    else
        no "hygiene: per-symbol ev differs after a pure reorder — marking depends on visit order"
    fi
else
    no "hygiene: the reorder writer failed — order-independence unproven"
fi

# ══ 9. JSON PARITY ═══════════════════════════════════════════════════════════════════════════════════
CPPJSON="$( json_map "$CPPDIR" )"
printf '%s' "$CPPJSON" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 \
    && ok "json: --json --metrics output is valid JSON" \
    || no "json: --json --metrics output is not valid JSON"
cat >"$TMP/parity.py" <<'PYEOF'
import json, sys
rows = {}
def walk( o ):
    if isinstance( o, dict ):
        if "n" in o and "cx" in o:
            rows[ o["n"] ] = o
        for v in o.values():
            walk( v )
    elif isinstance( o, list ):
        for v in o:
            walk( v )
walk( json.load( sys.stdin ) )
bad = []
for name, ev, why in ( ( "smallTangledLoop", 5, "loop-escape:1" ),
                       ( "guardClause", 2, "guard-return:1" ),
                       ( "switchBreakEscape", 5, "switch-escape:1" ) ):
    r = rows.get( name )
    if r is None:
        bad.append( name + ": no JSON row" )
        continue
    if r.get( "ev" ) != ev:
        bad.append( "{}: ev={} want {}".format( name, r.get( "ev" ), ev ) )
    if r.get( "ev_floor" ) is not True:
        bad.append( name + ": ev_floor is not the JSON boolean true" )
    if r.get( "ev_why" ) != why:
        bad.append( "{}: ev_why={} want {}".format( name, r.get( "ev_why" ), why ) )
for name in ( "plainStructured", "bigStructuredSwitch", "boolNotCounted" ):
    r = rows.get( name )
    if r is not None and ( "ev" in r or "ev_floor" in r or "ev_why" in r ):
        bad.append( name + ": JSON carries ev keys on a structured row" )
print( "; ".join( bad ) )
PYEOF
if parity="$( printf '%s' "$CPPJSON" | python3 "$TMP/parity.py" )"; then
    [ -z "$parity" ] \
        && ok "json: ev/ev_floor/ev_why match the XML dialect, and are absent on the same rows" \
        || no "json: XML/JSON parity broken — $parity"
else
    no "json: the parity reader itself failed to run — this arm proves nothing"
fi

# ══ 10. NO RANKING CHANGE — ev is an annotation, never a firing signal ═══════════════════════════════
# (a) live, both directions. guardClause has ev=2 and clears NO bar and fires NO other family: it must
#     be absent from the panel — if it appears, ev started firing rows. smallTangledLoop fires
#     structural (nest=4 at the bar) + confusion (atoms) for reasons that predate ev — its row must
#     keep fam="2" of="4" and the same fired set (ev joined no family count), while its structural
#     why= now CARRIES the ev annotation (emitted only because the family already fired).
PANEL="$( "$BIN" "$CPPDIR" --quality-panel --no-cache 2>/dev/null )"
if printf '%s' "$PANEL" | grep -q 'n="guardClause"'; then
    no "no-ranking: guardClause (ev=2, clears no bar, fires no family) appears in the quality panel — ev is firing rows"
else
    ok "no-ranking: ev>=2 alone puts no row into the quality panel (annotation-only, joins no family count)"
fi
TROW="$( printf '%s' "$PANEL" | grep -o '<s [^>]*n="smallTangledLoop"[^>]*>' | head -1 )"
if printf '%s' "$TROW" | grep -q 'fam="2"' && printf '%s' "$TROW" | grep -q 'of="4"' && printf '%s' "$TROW" | grep -q 'fired="structural,confusion"'; then
    ok "no-ranking: smallTangledLoop's panel row keeps fam=2 of=4 fired=structural,confusion — ev changed no count and no membership"
else
    no "no-ranking: smallTangledLoop's panel row moved (want fam=2 of=4 fired=structural,confusion): ${TROW:-<row absent>}"
fi
if printf '%s' "$PANEL" | grep -o '<e f="structural"[^/]*/>' | head -1 | grep -q 'ev=5'; then
    ok "no-ranking: the structural why= on the already-firing row carries the ev=5 annotation (strictly more evidence, same rows)"
else
    no "no-ranking: the structural family's why= on smallTangledLoop does not carry ev=5 — the annotation is missing"
fi
# (b) source-level: ev is read nowhere outside the emitters + the single gated annotation line.
EVREADS="$( git -C "$ROOT" grep -n '\.ev\b' -- 'src/*.h' 'src/*.cpp' | grep -vE '^src/(serialize\.h|model\.h|ingest\.cpp):' || true )"
EXTRA="$( printf '%s\n' "$EVREADS" | grep -v '^$' | grep -v '^src/ensemble\.h:' || true )"
if [ -n "$EXTRA" ]; then
    no "no-ranking: .ev is read outside the allowed emitters — $EXTRA"
else
    ok "no-ranking: .ev reads confined to serialize.h/model.h/ingest.cpp/ensemble.h"
fi
ENS="$( printf '%s\n' "$EVREADS" | grep '^src/ensemble\.h:' || true )"
if [ -z "$ENS" ]; then
    no "no-ranking: the ensemble annotation line is missing — the why= annotation was dropped"
elif [ "$( printf '%s\n' "$ENS" | wc -l | tr -d ' ' )" = "1" ] && printf '%s' "$ENS" | grep -q 'why.empty'; then
    ok "no-ranking: ensemble.h reads .ev on exactly one line, gated on the family ALREADY firing (!why.empty())"
else
    no "no-ranking: ensemble.h's .ev read is not the single !why.empty()-gated annotation line: $ENS"
fi

# ══ 11. MUTATION SELF-TEST — the pinned numbers are load-bearing ═════════════════════════════════════
mut_got="$( attr_of "$( row_of "$CPPXML" smallTangledLoop )" ev )"
[ "$mut_got" != "999" ] \
    && ok "mutation self-test: asserting smallTangledLoop ev=999 when it is really '$mut_got' correctly fails" \
    || no "mutation self-test: the fixture reports ev=999 — the assertion cannot fail"
g_ev="$( attr_of "$( row_of "$CPPXML" guardClause )" ev )"
g_cx="$( attr_of "$( row_of "$CPPXML" guardClause )" cx )"
[ -n "$g_ev" ] && [ -n "$g_cx" ] && [ "$g_ev" != "$g_cx" ] \
    && ok "mutation self-test: ev ($g_ev) != cx ($g_cx) on guardClause — ev is not cx under another name" \
    || no "mutation self-test: guardClause ev='$g_ev' equals cx='$g_cx' — ev may be aliasing cx"
[ -n "$t_ev" ] && [ "$t_ev" != "1" ] \
    && ok "mutation self-test: ev=$t_ev on smallTangledLoop — ev is provably not a constant 1" \
    || no "mutation self-test: smallTangledLoop ev='$t_ev' — ev may be a constant"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
