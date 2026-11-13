#!/usr/bin/env bash
# qdentryceilingcheck.sh — gate for QD-ENTRY-CEILING (GE design E2, owner decision C4 2026-11-12): a NEW function
# gates once it reaches the new-function ceiling, kNewSymbolCeilingMul (4) times the kind's bar — ccx 60 or 240
# code lines — after the two artifacts that made such rows noise are fixed first.
#
# What this pins (each arm counts the premise it needs and FAILS on zero, so no arm can pass blind):
#   P1. a seeded new 250-line src function gates (exit 2, gating="1", ceiling="240", origin="new-symbol");
#   P2. a seeded new ccx-61 src function gates (ceiling="60");
#   N1. a new ccx-59 function and a new 239-line function stay printed, origin="new-symbol", and do not gate;
#   N2. MOVED-BODY: the same 250-line body moved to another file under another name (re-indented) prints
#       origin="moved" and does not gate; a COPY (the original kept) is not a move and still gates;
#   N3. EXTENT-CTOR: a class whose constructor shares its canonical id (C++: Foo::Foo) is measured over the
#       constructor's own body — the class extent (well over 240 lines) never reaches a verbosity row;
#   T.  TEST DRIVERS are report-only: the same 250-line new function under test/ prints and does not gate;
#   J.  --json carries the same gating count and the per-row origin/ceiling;
#   L.  every surface stating "new-symbol rows never gate" names the ceiling exception.
#
# Everything runs in git-backed temp repos (the auto-baseline-vs-HEAD path), never the real repo.
# Usage:  bash test/qdentryceilingcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qdentryceilingcheck (git required for the HEAD-baseline fixtures)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" TMPDIR="$WORK/tmp"; mkdir -p "$HOME" "$TMPDIR"
echo "qdentryceilingcheck: BIN=$BIN  (temp git corpora)"

# ifs N: N sibling ifs at nesting 0 — each adds exactly 1 to cognitive complexity (calibrated by arm C below).
ifs(){ n=$1; s=''; i=1; while [ "$i" -le "$n" ]; do s="$s if(a>$i){ s++; }"; i=$(( i + 1 )); done; printf '%s' "$s"; }
# lines N INDENT: N straight-line code lines (no branch), one statement each.
lines(){ n=$1; i=1; while [ "$i" -le "$n" ]; do printf '%s s += a * %d;\n' "$2" "$i"; i=$(( i + 1 )); done; }
# longfn NAME N INDENT: a function of N straight-line statements; codeLoc = N + 5 (signature, braces, the local, the return).
longfn(){ printf '%sint %s( int a )\n%s{\n%s int s = 0;\n' "$3" "$1" "$3" "$3"; lines "$2" "$3"; printf '%s return s;\n%s}\n' "$3" "$3"; }
newrepo(){ mkdir -p "$1/src"; ( cd "$1" && git init -q && git config user.email t@t && git config user.name t ); }
commitall(){ ( cd "$1" && git add -A >/dev/null 2>&1 && git commit -qm "$2" >/dev/null 2>&1 ); }
dq(){  ( cd "$1" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null ); }
# run once, keep stdout and rc: every arm checks the rc BEFORE it reads rows (a crash prints nothing).
run(){ OUT="$( cd "$1" && "$BIN" . --quality-delta --no-cache --legend=full 2>"$WORK/err" )"; RC=$?; }
rows(){ printf '%s' "$1" | tr '>' '\n' | grep '<r '; }
# rowof OUT KIND NAME: the row whose sym= ENDS in NAME as a whole segment (sym= may carry a path::scope:: prefix).
rowof(){ rows "$1" | grep -E "kind=\"$2\" sym=\"([^\"]*::)?$3\""; }
hattr(){ printf '%s' "$1" | grep -o "$2=\"[0-9]*\"" | head -1 | cut -d'"' -f2; }
newrows(){ rows "$1" | grep -c 'origin="\(new-symbol\|moved\)"' | tr -d ' '; }
crashed(){ case "$RC" in 0|2) return 1;; *) no "$1: ripwire exited rc=$RC (crash or refusal); stderr: $( head -c 300 "$WORK/err" )"; return 0;; esac; }

base(){ newrepo "$1"; printf 'int keep(){ return 1; }\nint usek(){ return keep(); }\n' > "$1/src/base.cpp"; commitall "$1" init; }

# ═══ C) CALIBRATION — the fixtures measure what their names say (the premise of P2/N1) ═════════════════
CAL="$WORK/cal"; mkdir -p "$CAL"
printf 'int c61( int a ){ int s=0;%s return s; }\n' "$( ifs 61 )" > "$CAL/c.cpp"
longfn l240 235 '' > "$CAL/l.cpp"
MET="$( cd "$CAL" && "$BIN" . --metrics --no-cache 2>/dev/null )"
CCX="$( printf '%s' "$MET" | tr '>' '\n' | grep 'n="c61"' | grep -o ' ccx="[0-9]*"' | cut -d'"' -f2 )"
LOC="$( printf '%s' "$MET" | tr '>' '\n' | grep 'n="l240"' | grep -o ' loc="[0-9]*"' | cut -d'"' -f2 )"
[ "$CCX" = 61 ] && ok "C: ifs 61 measures ccx=61" || no "C: ifs 61 measures ccx=${CCX:-<none>} (fixture calibration off)"
[ "$LOC" = 240 ] && ok "C: longfn of 235 statements spans loc=240" || no "C: longfn 235 spans loc=${LOC:-<none>}"

# ═══ P1) A NEW 250-LINE SRC FUNCTION GATES ═════════════════════════════════════════════════════════════
R="$WORK/p1"; base "$R"; longfn big 245 '' > "$R/src/big.cpp"
run "$R"
if ! crashed P1; then
    ROW="$( rowof "$OUT" verbosity big )"
    [ "$( newrows "$OUT" )" -ge 1 ] || no "P1: premise — 0 new-symbol rows seen"
    if [ "$RC" = 2 ] && printf '%s' "$ROW" | grep -q 'now="250"' && printf '%s' "$ROW" | grep -q 'gating="1"' \
       && printf '%s' "$ROW" | grep -q 'ceiling="240"' && printf '%s' "$ROW" | grep -q 'origin="new-symbol"'; then
        ok "P1: new 250-line function gates (exit 2, ceiling=\"240\", gating=\"1\")"
    else no "P1: new 250-line function should gate (rc=$RC row: ${ROW:-<none>})"; fi
fi
P1OUT="$OUT"

# ═══ P2) A NEW ccx-61 SRC FUNCTION GATES ═══════════════════════════════════════════════════════════════
R="$WORK/p2"; base "$R"; printf 'int cx61( int a ){ int s=0;%s return s; }\n' "$( ifs 61 )" > "$R/src/cx.cpp"
run "$R"
if ! crashed P2; then
    ROW="$( rowof "$OUT" complexity cx61 )"
    [ "$( newrows "$OUT" )" -ge 1 ] || no "P2: premise — 0 new-symbol rows seen"
    if [ "$RC" = 2 ] && printf '%s' "$ROW" | grep -q 'now="61"' && printf '%s' "$ROW" | grep -q 'gating="1"' && printf '%s' "$ROW" | grep -q 'ceiling="60"'; then
        ok "P2: new ccx-61 function gates (exit 2, ceiling=\"60\")"
    else no "P2: new ccx-61 function should gate (rc=$RC row: ${ROW:-<none>})"; fi
fi

# ═══ N1) JUST UNDER THE CEILING: printed, never gating ═════════════════════════════════════════════════
R="$WORK/n1"; base "$R"
printf 'int cx59( int a ){ int s=0;%s return s; }\n' "$( ifs 59 )" > "$R/src/cx.cpp"
longfn l239 234 '' > "$R/src/l.cpp"
run "$R"
if ! crashed N1; then
    N="$( newrows "$OUT" )"
    C="$( rowof "$OUT" complexity cx59 )"; V="$( rowof "$OUT" verbosity l239 )"
    if [ "$N" -lt 2 ]; then no "N1: premise — expected the two under-ceiling new-symbol rows, saw $N"
    elif [ "$RC" = 0 ] && printf '%s' "$C" | grep -q 'now="59"' && printf '%s' "$V" | grep -q 'now="239"' \
         && ! rows "$OUT" | grep -q 'gating="1"' && ! rows "$OUT" | grep -q 'ceiling='; then
        ok "N1: ccx-59 and 239-line new functions print ($N new-symbol rows) and do not gate (exit 0)"
    else no "N1: under-ceiling rows must not gate (rc=$RC; $C; $V)"; fi
fi

# ═══ N2) A MOVED BODY IS QUIET; A COPY IS NOT A MOVE ═══════════════════════════════════════════════════
R="$WORK/n2"; base "$R"; longfn big 245 '' > "$R/src/old.cpp"; printf 'int useb(){ return big(1); }\n' >> "$R/src/old.cpp"; commitall "$R" big
rm "$R/src/old.cpp"
{ printf 'namespace lib\n{\n'; longfn moved_big 245 '    '; printf '}\nint useb(){ return lib::moved_big(1); }\n'; } > "$R/src/new.cpp"
run "$R"
if ! crashed N2; then
    MV="$( rows "$OUT" | grep -c 'origin="moved"' | tr -d ' ' )"
    if [ "$MV" -lt 1 ]; then no "N2: premise — 0 moved bodies seen (rows: $( rows "$OUT" | tr '\n' ' ' ))"
    elif [ "$RC" = 0 ] && ! rows "$OUT" | grep -q 'gating="1"' && rowof "$OUT" verbosity 'lib::moved_big' | grep -q 'origin="moved"'; then
        ok "N2: the 250-line body moved to another file and name prints origin=\"moved\" ($MV row(s)) and does not gate"
    else no "N2: a moved body must not gate (rc=$RC rows: $( rows "$OUT" | tr '\n' ' ' ))"; fi
    MH="$( hattr "$OUT" 'new-symbol' )"; [ "$MH" = "$( newrows "$OUT" )" ] && ok "N2: new-symbol= counts the moved rows too ($MH)" \
        || no "N2: header new-symbol=$MH but $( newrows "$OUT" ) rows carry origin=new-symbol|moved"
fi
R="$WORK/n2c"; base "$R"; longfn big 245 '' > "$R/src/old.cpp"; printf 'int useb(){ return big(1); }\n' >> "$R/src/old.cpp"; commitall "$R" big
{ printf 'namespace lib\n{\n'; longfn copy_big 245 '    '; printf '}\nint usec(){ return lib::copy_big(1); }\n'; } > "$R/src/new.cpp"
run "$R"
if ! crashed N2c; then
    ROW="$( rowof "$OUT" verbosity 'lib::copy_big' )"
    if [ -z "$ROW" ]; then no "N2c: premise — no row for the copied function"
    elif [ "$RC" = 2 ] && printf '%s' "$ROW" | grep -q 'origin="new-symbol"' && printf '%s' "$ROW" | grep -q 'gating="1"'; then
        ok "N2c: a COPY (original still present) is not a move — it still gates"
    else no "N2c: a copied body must still gate (rc=$RC row: $ROW)"; fi
fi

# ═══ N3) CONSTRUCTOR EXTENT: measured over its own body, not the class ═════════════════════════════════
R="$WORK/n3"; base "$R"
{
    printf 'class Wide\n{\npublic:\n    Wide( int a ) : m_a( a ), m_b( a + 1 ), m_c( a + 2 )\n    {\n        m_d = a;\n    }\n'
    i=1; while [ "$i" -le 260 ]; do printf '    int m_x%d = %d;\n' "$i" "$i"; i=$(( i + 1 )); done
    printf 'private:\n    int m_a;\n    int m_b;\n    int m_c;\n    int m_d = 0;\n};\n'
    longfn sibling 120 ''
} > "$R/src/wide.h"
run "$R"
if ! crashed N3; then
    CLS="$( cd "$R" && "$BIN" . --metrics --no-cache 2>/dev/null | tr '>' '\n' | grep 't="cls" n="Wide"' | grep -o ' loc="[0-9]*"' | cut -d'"' -f2 )"
    N="$( newrows "$OUT" )"
    if [ "${CLS:-0}" -lt 240 ]; then no "N3: premise — the class extent is ${CLS:-<none>} lines, not over the ceiling"
    elif [ "$N" -lt 1 ]; then no "N3: premise — 0 new-symbol rows seen (the sibling's row is missing)"
    elif ! rowof "$OUT" verbosity 'Wide::Wide' | grep -q . && [ "$RC" = 0 ]; then
        ok "N3: the class extent ($CLS lines) never reaches the constructor's row; $N new-symbol row(s) seen, exit 0"
    else no "N3: Wide::Wide carries the class extent (rc=$RC row: $( rowof "$OUT" verbosity 'Wide::Wide' ))"; fi
fi

# ═══ T) TEST DRIVERS ARE REPORT-ONLY ═══════════════════════════════════════════════════════════════════
R="$WORK/t"; base "$R"; mkdir -p "$R/test"; longfn bigdriver 245 '' > "$R/test/driver.cpp"
run "$R"
if ! crashed T; then
    ROW="$( rowof "$OUT" verbosity bigdriver )"
    if [ -z "$ROW" ]; then no "T: premise — no row for the 250-line test function"
    elif [ "$RC" = 0 ] && printf '%s' "$ROW" | grep -q 'origin="new-symbol"' && ! printf '%s' "$ROW" | grep -q 'gating='; then
        ok "T: a 250-line new function under test/ prints and does not gate"
    else no "T: a test-driver row must not gate (rc=$RC row: $ROW)"; fi
fi

# ═══ J) JSON PARITY ════════════════════════════════════════════════════════════════════════════════════
J="$( cd "$WORK/p1" && "$BIN" . --quality-delta --json --no-cache 2>/dev/null )"; JRC=$?
JG="$( printf '%s' "$J" | grep -o '"gating":[0-9]*' | head -1 | cut -d: -f2 )"
if [ "$JRC" = 2 ] && [ "$JG" = "$( hattr "$P1OUT" gating )" ] && printf '%s' "$J" | grep -q '"ceiling":240'; then
    ok "J: --json gating=$JG and \"ceiling\":240 match the XML (exit 2)"
else no "J: json parity (rc=$JRC gating=$JG xml gating=$( hattr "$P1OUT" gating ))"; fi
JM="$( cd "$WORK/n2" && "$BIN" . --quality-delta --json --no-cache 2>/dev/null )"
printf '%s' "$JM" | grep -q '"origin":"moved"' && ok "J: --json carries \"origin\":\"moved\"" || no "J: --json lacks origin moved"

# ═══ L) LEGEND — the exception is stated wherever the rule is ═════════════════════════════════════════
PHRASE='new-symbol rows never gate, except defect-shape format-arity and a new function at the ceiling'
# compact spends fewer bytes (its prose has a stair-step target): the exception names the ceiling= row it defines
CPHRASE='never gate, except defect-shape format-arity or a ceiling= row'
for leg in full compact; do
    T="$( cd "$WORK/p1" && "$BIN" . --quality-delta --no-cache --legend=$leg 2>/dev/null | tr '\n' ' ' | tr -s ' ' )"
    a="$( printf '%s' "$T" | grep -o 'never gate, except defect-shape' | wc -l | tr -d ' ' )"
    ph="$PHRASE"; [ "$leg" = compact ] && ph="$CPHRASE"
    q="$( printf '%s' "$T" | grep -o "$ph" | wc -l | tr -d ' ' )"
    if [ "$q" -ge 1 ] && [ "$a" = "$q" ]; then ok "L: --legend=$leg states the ceiling exception ($q)"; else no "L: --legend=$leg: phrase x$q of $a"; fi
done
H="$( "$BIN" --help=quality-delta 2>/dev/null | tr '\n' ' ' | tr -s ' ' )"
a="$( printf '%s' "$H" | grep -o 'never gate, except defect-shape' | wc -l | tr -d ' ' )"
q="$( printf '%s' "$H" | grep -o "$PHRASE" | wc -l | tr -d ' ' )"
if [ "$q" -ge 1 ] && [ "$a" = "$q" ]; then ok "L: --help=quality-delta states the ceiling exception ($q)"; else no "L: --help=quality-delta: phrase x$q of $a"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
