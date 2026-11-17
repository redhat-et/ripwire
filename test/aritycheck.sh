#!/usr/bin/env bash
# aritycheck.sh — F1 gate (X3): the B2.2 arity filter
# (src/graph.h provablyWrong, fed by src/ingest.cpp cc_paramArityExact) must not "provably" exclude a
# candidate def just because the CALL has FEWER args than that def's visible param count. arityExact is
# computed from the DEFINITION node only, so a C++ out-of-line def whose default argument lives ONLY on a
# separate header PROTOTYPE reads as a fixed arity == params. An (N-1)-arg call against it is legal (the
# header default fills the gap) but the OLD code compared `params != argCount` and excluded it outright —
# dropping the correct edge AND silently keeping the tier at size 1, so `amb=` never fired even though a
# rival same-name overload also matched. DECIDED FIX (do not re-litigate): keep the exclusion ONLY for
# `argCount > params` (no default can rescue a call with too many args), in ALL languages; for
# `argCount < params` the def stays a candidate and correctly re-enters `amb=` when multiple defs survive.
#
#   test/aritycheck.sh                       # uses build/ripwire on test/arityfix/{cpp,py,toomany}
#   RIPWIRE_BIN=asan/ripwire test/aritycheck.sh
#
# Fixtures (the first three are the F1 gate; section 3b holds the minimum-arity arms):
#   cpp/     — the audit's exact repro: f.h declares `f(int x, int y=5)` (proto only); a.cpp defines
#              `f(int x, int y){...}` out-of-line (no default visible on the def ⇒ arityExact=1, params=2);
#              b.cpp defines a genuine 1-arg overload `f(int x)`. caller.cpp calls `f(1)` (argCount=1 <
#              params=2 on a.cpp). MUST bind both overloads (count=2 + amb=1) — never a lone confident pick
#              that silently drops a.cpp.
#   py/      — the same shape without any decl/def split: a.py `f(x)` (params=1), b.py `f(x, y)` (params=2, no
#              default). REVERSED by the minimum-arity rule (train 29, arity-min): a 1-arg call to a 2-parameter
#              Python function with no default is a TypeError, so b.py is provably not the callee and `f(1)` binds
#              a.py ALONE (count=1). The C++ shape above still binds both: its default lives on the prototype, and
#              the minimum is taken over the definition AND every declaration of it.
#   toomany/ — the negative control: the exclusion must still fire for `argCount > params`. a.cpp `g(int x)`
#              (params=1), b.cpp `g(int x,int y,int z)` (params=3). caller.cpp calls `g(1,2,3)`
#              (argCount=3 > params=1 on a.cpp ⇒ still provably wrong). MUST resolve confidently to b.cpp
#              alone (count=1, amb=0) — a regression here would mean the fix over-corrected into silence.
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/arityfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "aritycheck: BIN=$BIN  FIX=$FIX"

callees(){ "$BIN" "$1" --callees="$2" --no-cache 2>/dev/null; }
callee_count(){ callees "$1" "$2" | grep -oE 'count="[0-9]+"' | head -1 | grep -oE '[0-9]+'; }
hdr_amb(){ "$BIN" "$1" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | grep -oE '[0-9]+'; }

# ── 1) cpp/: header-default + out-of-line def — must bind BOTH overloads (count=2, amb=1) ──────────
CC="$( callees "$FIX/cpp" call_f )"
N="$( callee_count "$FIX/cpp" call_f )"; N="${N:-0}"
A="$( hdr_amb "$FIX/cpp" )"; A="${A:-0}"
HAS_A="$( printf '%s' "$CC" | grep -c 'a\.cpp:2' )"     # a.cpp's f (params=2, header-default-hidden — was dropped)
HAS_B="$( printf '%s' "$CC" | grep -c 'b\.cpp:1' )"     # b.cpp's f (params=1, genuinely a 1-arg overload)
if [ "$N" = "1" ] && [ "$HAS_B" -ge 1 ] && [ "$HAS_A" -eq 0 ]; then
    no "REGRESSION: f(1) resolves CONFIDENTLY to b.cpp alone — a.cpp's def (header-default arity) silently dropped, amb=$A"
    printf '    %s\n' "$CC"
elif [ "$N" -ge 2 ] && [ "$HAS_A" -ge 1 ] && [ "$HAS_B" -ge 1 ] && [ "$A" -ge 1 ]; then
    ok "cpp: f(1) binds both overloads (count=$N, amb=$A) — header-default def no longer silently dropped"
elif [ "$N" = "1" ] && [ "$HAS_A" -ge 1 ] && [ "$HAS_B" -eq 0 ]; then
    ok "cpp: f(1) resolves to the correct a.cpp overload alone (count=$N) — also an acceptable honest outcome"
else
    no "cpp: unexpected resolution shape (count=$N, a=$HAS_A, b=$HAS_B, amb=$A)"
    printf '    %s\n' "$CC"
fi

# ── 2) py/: no default, no declaration — the 2-parameter def cannot take 1 argument (minimum-arity rule) ──
CP="$( callees "$FIX/py" call_f )"
NP="$( callee_count "$FIX/py" call_f )"; NP="${NP:-0}"
HAS_PA="$( printf '%s' "$CP" | grep -c 'a\.py:1' )"     # a.py's f (params=1)
HAS_PB="$( printf '%s' "$CP" | grep -c 'b\.py:1' )"     # b.py's f (params=2, no default: needs 2 arguments)
if [ "$NP" = "1" ] && [ "$HAS_PA" -ge 1 ] && [ "$HAS_PB" -eq 0 ]; then
    ok "py: f(1) binds a.py alone (count=$NP) — the 2-parameter b.py def is provably not the callee"
else
    no "py: f(1) still lists the 2-parameter def or lost a.py (count=$NP, a=$HAS_PA, b=$HAS_PB)"
    printf '    %s\n' "$CP"
fi

# ── 3) toomany/: argCount > params must STILL provably exclude (negative control) ──────────────────
CT="$( callees "$FIX/toomany" call_g )"
NT="$( callee_count "$FIX/toomany" call_g )"; NT="${NT:-0}"
AT="$( hdr_amb "$FIX/toomany" )"; AT="${AT:-0}"
HAS_TA="$( printf '%s' "$CT" | grep -c 'a\.cpp:1' )"    # a.cpp's g (params=1 — too few, must stay excluded)
HAS_TB="$( printf '%s' "$CT" | grep -c 'b\.cpp:1' )"    # b.cpp's g (params=3 — the only possible match)
if [ "$NT" = "1" ] && [ "$HAS_TB" -ge 1 ] && [ "$HAS_TA" -eq 0 ] && [ "$AT" = "0" ]; then
    ok "toomany: g(1,2,3) resolves confidently to b.cpp alone (count=$NT, amb=$AT) — too-many-args exclusion still fires"
else
    no "toomany: too-many-args exclusion regressed (count=$NT, a=$HAS_TA, b=$HAS_TB, amb=$AT) — expected a lone b.cpp edge"
    printf '    %s\n' "$CT"
fi

# ── 3b) minimum arity: a call with FEWER arguments than a candidate's REQUIRED parameters drops it ────────
# required = params − defaulted, the minimum over the definition and every declaration of the same name and
# parameter count (a default on either makes the shorter call legal). A variadic, implicit-self, JavaScript or
# Kotlin candidate is never dropped this way. `expect DIR SYM "p= ..."` compares the callee p= set EXACTLY.
expect(){
    local got want
    got="$( callees "$FIX/$1" "$2" | grep -oE '<s [^>]*p="[^"]*"' | grep -oE 'p="[^"]*"' | sed 's/^p="//; s/"$//' | sort | tr '\n' ' ' )"
    want="$( printf '%s\n' $3 | sort | tr '\n' ' ' )"
    if [ -z "$got" ]; then
        no "$1 --callees=$2 returned no callee rows (want: $want) — $4"
    elif [ "$got" = "$want" ]; then
        ok "$1 --callees=$2 = { $got} — $4"
    else
        no "$1 --callees=$2 = { $got} want { $want} — $4"
    fi
}
echo "── minimum arity (P = drops a provably-wrong overload; N = near miss that must keep it) ──"
expect fewer    parse_default "u.cpp:2"                   "[P] C++ 3-arg call drops the 4-parameter no-default overload (ninja-26 shape)"
expect protodef parse_proto   "u.cpp:2 u.cpp:6"           "[N] C++ default on the PROTOTYPE only keeps the 4-parameter def"
expect defmin   call_h2       "a.cpp:1"                   "[P] h(1,2): keeps h(int a, int b = 1), drops the 4-parameter h"
expect defmin   call_h1       "a.cpp:1"                   "[P] h(1): keeps h(int a, int b = 1), drops the 4-parameter h"
expect defmin   call_h0       "c.cpp:1"                   "[P] h(): drops h(int a, int b = 1) (one required) and the 4-parameter h"
expect variadic call_v        "a.cpp:1 b.cpp:1"           "[P] v(1): drops v(a,b,c); the variadic v(a, b, ...) is never dropped"
expect voidp    call_z        "a.cpp:1"                   "[P] z(): keeps z(void) (no parameter), drops z(a,b)"
expect pyself   call_m        "a.py:2 b.py:2"             "[N] Python methods (implicit self) are never dropped: A.m(self, a) keeps beside B.m(self) (Python tags methods as functions)"
expect pydef    call_g        "a.py:1"                    "[P] Python g(1): keeps g(x, y=1), drops g(x, y, z)"
expect pydef    call_g2       "a.py:5"                    "[P] Python g2(1): the bare * separator is no parameter — keeps g2(x, *, y=1)"
expect pydef    call_k        "a.py:14"                   "[P] Python k(1): a decorated def keeps (the decorator may supply arguments)"
expect ts       call_t        "a.ts:2"                    "[P] TS t(1): keeps the optional-parameter t, drops t(a,b,c)"
expect ts       call_d        "a.ts:3"                    "[P] TS d(1): keeps d(a, b = 2), drops d(a,b,c)"
expect ts       call_w        "a.ts:4"                    "[P] TS w(1): the this-parameter is not passed — keeps w(this, a)"
expect js       call_j        "a.js:1 b.js:1"             "[N] JavaScript: fewer arguments are legal — both kept"
expect kt       callK         "A.kt:1 B.kt:1"             "[N] Kotlin: a default keeps its edge (no minimum-arity row)"
# fix round 1 (review B1-B4): each [P] arm below was RED on the lane head 3901e59d.
expect tsval    call_h        "a.ts:4 b.ts:2"             "[P] B1 TS field arrow typed by its annotation (hono header: SetHeaders = (name, value, options) => …) keeps — its optional params live in the type"
expect tsval    call_f        "a.ts:6 b.ts:4"             "[P] B1 TS const f: Fn = (a, b) => … keeps — the annotation, not the arrow, is the call's contract"
expect tsval    call_g        "a.ts:7 b.ts:5"             "[P] B1 TS ((a, b) => …) as Fn keeps — a cast arrow takes its type from elsewhere"
expect tsval    call_u        "b.ts:6"                    "[N] B1 control: a bare unannotated-binding arrow with typed params still drops for too few"
expect fallback call_q        "a.cpp:1"                   "[P] B2 C++ q(1,2): the too-many q(int) stays out when the only survivor is too-few (head ⊆ base)"
expect tsfallback call_m      "a.ts:2"                    "[P] B2 TS x.m('a','b'): the too-many B.m(a) stays out when A.m(a,b,c) is too-few"
expect packcall fwd           "a.cpp:1 b.cpp:1"           "[P] B3 C++ p(std::forward<T>(t)...): a pack expansion is an unknown count — p(int,int) kept"
expect packcall call_p2       "a.cpp:1 b.cpp:1"           "[P] B3 C++ p(t...): a pack expansion is an unknown count — p(int,int) kept"
expect packcall call_s        "a.ts:1 b.ts:1"             "[N] B3 TS s(...xs): spread is an unknown count"
expect packcall call_k        "a.py:1 b.py:1"             "[N] B3 Python k(*xs): unpack is an unknown count"
expect packcall call_k2       "a.py:1 b.py:1"             "[N] B3 Python k(**kw): unpack is an unknown count"
expect pyblock  call_m1       "a.py:6 b.py:2"             "[P] B4 Python method under if in a class body is a method (self not counted)"
expect pyblock  call_m2       "a.py:9 b.py:4"             "[P] B4 Python method under try in a class body is a method"
expect pyblock  call_m3       "a.py:14 b.py:6"            "[P] B4 Python method under with in a class body is a method"
expect pyblock  call_m4       "a.py:18 b.py:8"            "[P] B4 Python method under a nested if in a class body is a method"

# ── 3c) assume-audit ingest_metrics.h cc_paramShape: a parameter list with ≥ 65,536 children ─────────
# The named/defaulted/notParam counters were uint16: 65,535 plain parameters + 1 defaulted one wrapped `named` to 0
# while `defaulted` stayed 1, so ASSUME( defaulted + notParam <= named ) trapped the dev build (release: silent UB).
# The fixture is ~0.5 MB, so it is generated here under $TMP, not committed. b.py's 1-parameter big() is the rival
# a 1-argument call must bind: the generated big() needs 65,535 arguments (its minimum, saturated at the field width).
echo "── minimum arity: 65,536-parameter list (generated) ──"
WIDE="$TMP/wide"; mkdir -p "$WIDE"
python3 -c 'import sys; sys.stdout.write( "def big(" + ", ".join( "p%d" % i for i in range( 65535 ) ) + ", d=1):\n    return 0\n" )' >"$WIDE/a.py"
printf 'def big(x):\n    return x\n' >"$WIDE/b.py"
printf 'def call_big():\n    return big(1)\n' >"$WIDE/caller.py"
WOUT="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$WIDE" --callees=call_big --no-cache 2>"$TMP/wide.err" )"; WRC=$?
WGOT="$( printf '%s' "$WOUT" | grep -oE '<s [^>]*p="[^"]*"' | grep -oE 'p="[^"]*"' | sed 's/^p="//; s/"$//' | sort | tr '\n' ' ' )"
if [ "$WRC" = 0 ] && [ "$WGOT" = "b.py:1 " ]; then
    ok "wide --callees=call_big = { $WGOT} — 65,535 params + 1 default: no counter wrap, the 65,535-minimum def drops for big(1)"
else
    no "wide --callees=call_big rc=$WRC = { $WGOT} want { b.py:1 } — $( head -c 400 "$TMP/wide.err" )"
fi
# CodeRabbit on #586 (1): the b.py:1 answer above would also pass if a.py were never indexed, so pin that the wide def
# IS a row. (2) Its params= saturates at the field width, so it is a floor and says so: params_floor="1" in XML and
# "params_floor":true in JSON, present only on a saturated count. RED on ecba09cd2: no params_floor anywhere.
WMX="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$WIDE" --metrics --no-cache 2>>"$TMP/wide.err" )"
WROW="$( printf '%s' "$WMX" | grep -oE '<f p="a\.py"><s [^>]*>' | head -1 )"
WJS="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$WIDE" --metrics --json --no-cache 2>>"$TMP/wide.err" )"
if printf '%s' "$WROW" | grep -qF 'params="65535"' && printf '%s' "$WROW" | grep -qF 'params_floor="1"' \
   && printf '%s' "$WJS" | grep -qF '"params":65535,' && printf '%s' "$WJS" | grep -qF '"params_floor":true' \
   && ! printf '%s' "$WMX" | grep -oE '<f p="b\.py"><s [^>]*>' | grep -qF 'params_floor'; then
    ok "wide def a.py big() is indexed, params=\"65535\" params_floor=\"1\" (XML) and \"params_floor\":true (JSON); b.py's exact 1 carries none"
else
    no "wide def row/floor: XML row { $WROW } JSON floor=$( printf '%s' "$WJS" | grep -cF '"params_floor":true' ) — $( head -c 400 "$TMP/wide.err" )"
fi
# CodeRabbit on #586 (3): callArity's uint16 counter wrapped a 65,536-argument call to a KNOWN 0, so the arity filter
# kept b.py's zero-parameter big() that 65,536 arguments cannot call. An overflowing count is unknown, and an unknown
# count filters nothing: both candidates stay. RED on ecba09cd2: { b.py:1 } alone — the wrapped 0 dropped a.py's big(x)
# as 'too few' and kept the zero-parameter rival.
CALLW="$TMP/callw"; mkdir -p "$CALLW"
printf 'def big(x):\n    return x\n' >"$CALLW/a.py"
printf 'def big():\n    return 0\n' >"$CALLW/b.py"
python3 -c 'import sys; sys.stdout.write( "def call_big():\n    return big(" + ", ".join( "0" for _ in range( 65536 ) ) + ")\n" )' >"$CALLW/caller.py"
COUT="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$CALLW" --callees=call_big --no-cache 2>"$TMP/callw.err" )"; CRC=$?
CGOT="$( printf '%s' "$COUT" | grep -oE '<s [^>]*p="[^"]*"' | grep -oE 'p="[^"]*"' | sed 's/^p="//; s/"$//' | sort | tr '\n' ' ' )"
if [ "$CRC" = 0 ] && [ "$CGOT" = "a.py:1 b.py:1 " ]; then
    ok "65,536-argument big(...) = { $CGOT} — the overflowing count is unknown, so arity drops neither candidate"
else
    no "65,536-argument --callees=call_big rc=$CRC = { $CGOT} want { a.py:1 b.py:1 } — $( head -c 400 "$TMP/callw.err" )"
fi

# ── 4) determinism — byte-identical run-to-run over all three fixtures ──────────────────────────────
echo "── determinism (byte-identical, two --no-cache runs) ──"
detfail=0
for d in "$FIX"/*/; do
    "$BIN" "$d" --no-cache >"$TMP/r1" 2>/dev/null
    "$BIN" "$d" --no-cache >"$TMP/r2" 2>/dev/null
    cmp -s "$TMP/r1" "$TMP/r2" || { detfail=1; no "non-deterministic: $( basename "$d" )"; }
done
[ "$detfail" = 0 ] && ok "every fixture deterministic"

# ── 5) well-formed XML ───────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    ok_xml=1
    for d in "$FIX"/*/; do
        "$BIN" "$d" --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null || { ok_xml=0; no "xml malformed: $( basename "$d" )"; }
    done
    [ "$ok_xml" = 1 ] && ok "xml well-formed (every fixture)"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
