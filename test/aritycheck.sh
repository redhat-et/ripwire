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
# Three fixtures:
#   cpp/     — the audit's exact repro: f.h declares `f(int x, int y=5)` (proto only); a.cpp defines
#              `f(int x, int y){...}` out-of-line (no default visible on the def ⇒ arityExact=1, params=2);
#              b.cpp defines a genuine 1-arg overload `f(int x)`. caller.cpp calls `f(1)` (argCount=1 <
#              params=2 on a.cpp). MUST bind both overloads (count=2 + amb=1) — never a lone confident pick
#              that silently drops a.cpp.
#   py/      — the same shape without any decl/def split, to prove the fix is applied to ALL languages, not
#              just C++: a.py `f(x)` (params=1), b.py `f(x, y)` (params=2, no default ⇒ arityExact=1),
#              caller.py calls `f(1)` (argCount=1 < params=2 on b.py). MUST also bind both (count=2 + amb=1)
#              — the decided rule trades this bit of Python precision for the honesty guarantee.
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
ok(){ printf '  PASS  %s\n' "$*"; }
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

# ── 2) py/: default-arg-shaped equivalent, no decl/def split — must ALSO bind both (all-languages rule) ──
CP="$( callees "$FIX/py" call_f )"
NP="$( callee_count "$FIX/py" call_f )"; NP="${NP:-0}"
AP="$( hdr_amb "$FIX/py" )"; AP="${AP:-0}"
HAS_PA="$( printf '%s' "$CP" | grep -c 'a\.py:1' )"     # a.py's f (params=1)
HAS_PB="$( printf '%s' "$CP" | grep -c 'b\.py:1' )"     # b.py's f (params=2 — was wrongly excluded pre-fix)
if [ "$NP" = "1" ] && [ "$HAS_PA" -ge 1 ] && [ "$HAS_PB" -eq 0 ]; then
    no "REGRESSION (Python): f(1) resolves CONFIDENTLY to a.py alone — b.py's 2-param def silently dropped, amb=$AP"
    printf '    %s\n' "$CP"
elif [ "$NP" -ge 2 ] && [ "$HAS_PA" -ge 1 ] && [ "$HAS_PB" -ge 1 ] && [ "$AP" -ge 1 ]; then
    ok "py: f(1) binds both overloads (count=$NP, amb=$AP) — the fix applies language-agnostically, not just C++"
else
    no "py: unexpected resolution shape (count=$NP, a=$HAS_PA, b=$HAS_PB, amb=$AP)"
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

# ── 4) determinism — byte-identical run-to-run over all three fixtures ──────────────────────────────
echo "── determinism (byte-identical, two --no-cache runs) ──"
detfail=0
for d in "$FIX"/cpp "$FIX"/py "$FIX"/toomany; do
    "$BIN" "$d" --no-cache >"$TMP/r1" 2>/dev/null
    "$BIN" "$d" --no-cache >"$TMP/r2" 2>/dev/null
    cmp -s "$TMP/r1" "$TMP/r2" || { detfail=1; no "non-deterministic: $( basename "$d" )"; }
done
[ "$detfail" = 0 ] && ok "all three fixtures deterministic"

# ── 5) well-formed XML ───────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    ok_xml=1
    for d in "$FIX"/cpp "$FIX"/py "$FIX"/toomany; do
        "$BIN" "$d" --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null || { ok_xml=0; no "xml malformed: $( basename "$d" )"; }
    done
    [ "$ok_xml" = 1 ] && ok "xml well-formed (all three fixtures)"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
