#!/usr/bin/env bash
# verbslimcheck.sh — VERB-SLIM-1 (src/verbslim.h): the default posture's cut of --expand and --quality-delta.
#
# THE CONTRACT:
#   (1) OFF SWITCH. RIPWIRE_VERB_SLIM=0 is today's answer: sibs=/inc= on <b>, root=/est_tokens= on <ctx>, every zero counter
#       on the quality-delta root, full sym= ids. --legend=full and the held-dictionary postures (--legend-have=, --legend-seen=) never pass
#       through the cut (ON == OFF byte for byte).
#   (2) EXPAND ORDER. No <b> tag carries sibs=/inc=; a <b>'s inside (CDATA, <calls>) is unchanged and its <fctx> follows the </b>.
#   (3) EXPAND RECOVERY. A long include list becomes inc_total= + inc_next=, and running inc_next= prints that list; a short one
#       stays inline (inc=), never a pointer longer than the list. sibs= is unchanged (cap, total, capped flag).
#   (4) EXPAND ROOT. topk_default= est_tokens= leave the <ctx> root and their legend readings leave with them; a
#       --max-tokens answer keeps est_tokens= (it is judged against that ceiling).
#   (5) LEGEND. The slim bundle's legend names <fctx> and every attribute on it; the document is well-formed XML.
#   (6) QUALITY-DELTA (6c: a C answer too). Zero counters that only count are absent; regressions= minor= gating= preexisting-worse= new-symbol=
#       always print. Every row's sym= is the OFF answer's, byte for byte: it is the canonical id scripts and --ack-only read
#       (a Rust/C++/Python id keeps its FILE:: head). The EXIT CODE and the gating rows (kind + canonical id) are the OFF answer's.
#   (7) OTHER VERBS. --callers on the same fixture is byte-identical ON and OFF.
#   (8) CDATA. A body that spells `<b sibs=` in its text is data: its bytes are served unchanged.
#
# Usage:  bash test/verbslimcheck.sh [BIN]   (default build/ripwire). Prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/expandsibsfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "verbslimcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
# on/off: one call per posture. Exit 0 (answer) and 2 (a gating --quality-delta) are answers; anything else FAILs the gate here.
on(){ env -u RIPWIRE_VERB_SLIM "$BIN" "$@"; local rc=$?; [ "$rc" -le 2 ] || no "ON run exited $rc: $*"; return "$rc"; }
off(){ RIPWIRE_VERB_SLIM=0 "$BIN" "$@"; local rc=$?; [ "$rc" -le 2 ] || no "OFF run exited $rc: $*"; return "$rc"; }
first(){ perl -0pe 's/<!--.*?-->//gs' "$2" | grep -oE "$1" | head -1; }   # a tag, never the legend text that spells one

# ── expand: basic.c (2 siblings, 2 short includes) and manyfn.c (144 siblings, 30 includes) ─────────────────────────────
# --top-k=0 keeps the bundle serving: these files are small enough that the auto choice would serve the whole file.
on  "$FIX" --expand=alphaFn --no-cache --top-k=0 >"$TMP/a.on"  2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
off "$FIX" --expand=alphaFn --no-cache --top-k=0 >"$TMP/a.off" 2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
on  "$FIX" --expand=manyFn000 --no-cache --top-k=0 >"$TMP/m.on"  2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
off "$FIX" --expand=manyFn000 --no-cache --top-k=0 >"$TMP/m.off" 2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
# the default call (no top-k) serves these small files whole: that root carries root= and est_tokens= today
on  "$FIX" --expand=alphaFn --no-cache >"$TMP/w.on"  2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
off "$FIX" --expand=alphaFn --no-cache >"$TMP/w.off" 2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
for f in a m w; do [ -s "$TMP/$f.on" ] && [ -s "$TMP/$f.off" ] || no "(0) $f: an empty answer"; done

# (1) OFF is today's shape
B_OFF="$( first '<b [^>]*>' "$TMP/a.off" )"
printf '%s' "$B_OFF" | grep -q 'sibs="betaFn,gammaFn" sibs_total="2" inc="foo.h,bar.h" inc_total="2"' \
 \
        && ok "(1) OFF: sibs=/inc= on <b>, as today" \
        || no "(1) OFF <b> lost sibs/inc: $B_OFF"
R_OFF="$( first '<ctx [^>]*>' "$TMP/w.off" )"
printf '%s' "$R_OFF" | grep -q ' root="' && printf '%s' "$R_OFF" | grep -q ' est_tokens="' \
 \
        && ok "(1) OFF: root= and est_tokens= on <ctx>" \
        || no "(1) OFF <ctx> lost root=/est_tokens=: $R_OFF"
grep -q '<fctx' "$TMP/a.off" && no "(1) OFF wrote <fctx>" || ok "(1) OFF writes no <fctx>"
on  "$FIX" --expand=alphaFn --no-cache --top-k=0 --legend=full >"$TMP/af.on"  2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
off "$FIX" --expand=alphaFn --no-cache --top-k=0 --legend=full >"$TMP/af.off" 2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
cmp -s "$TMP/af.on" "$TMP/af.off" && [ -s "$TMP/af.on" ] \
    && ok "(1) --legend=full: ON == OFF byte for byte" \
    || no "(1) --legend=full moved under the cut"
# The held-dictionary postures reduce the legend against the entries the caller holds; the slim purpose is none of them, so
# they serve today's answer.
DV="$( off "$FIX" --legend-dict 2>/dev/null | head -1 | grep -o 'dictv=[0-9a-f]*' | cut -d= -f2 )"   # status: off() FAILs an exit above 2; an empty dictv/seen FAILs the posture-inputs arm
off "$FIX" --expand=alphaFn --no-cache --top-k=0 2>/dev/null | off "$FIX" --legend-dict=seen >"$TMP/seen.txt" 2>/dev/null   # status: off() FAILs an exit above 2; an empty dictv/seen FAILs the posture-inputs arm
[ -n "$DV" ] && [ -s "$TMP/seen.txt" ] && ok "(1) posture inputs: dictv=$DV, $( wc -l <"$TMP/seen.txt" | tr -d ' ' ) seen line(s)" \
    || no "(1) posture inputs missing (dictv='$DV', seen file empty?)"
for POST in "--legend-have=$DV" "--legend-seen=$TMP/seen.txt"; do
    on  "$FIX" --expand=alphaFn --no-cache --top-k=0 "$POST" >"$TMP/ap.on"  2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
    off "$FIX" --expand=alphaFn --no-cache --top-k=0 "$POST" >"$TMP/ap.off" 2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
    # premise: the default answer of this call carries <fctx> (so equality is not vacuous) and the posture really reduced it
    grep -q '<fctx' "$TMP/a.on" || no "(1) premise: the default --expand=alphaFn answer carries no <fctx>"
    cmp -s "$TMP/ap.on" "$TMP/a.on" && no "(1) premise: $POST served the default answer unchanged (the posture never ran)"
    if cmp -s "$TMP/ap.on" "$TMP/ap.off" && [ -s "$TMP/ap.on" ]; then
        ok "(1) $POST: ON == OFF byte for byte"
    else
        no "(1) $POST moved under the cut"
    fi
done

# (2) order
B_ON="$( first '<b [^>]*>' "$TMP/a.on" )"
printf '%s' "$B_ON" | grep -qE ' (sibs|inc|sibs_total|inc_total)="' && no "(2) ON <b> still carries sibs/inc: $B_ON" || ok "(2) ON <b> carries no sibs=/inc="
python3 - "$TMP/a.on" "$TMP/a.off" "$TMP/m.on" "$TMP/m.off" <<'PY' \
    && ok "(2) each <b>'s inside (CDATA body, then <calls>) is OFF's byte for byte, and its <fctx> directly follows the </b>" \
    || no "(2) <fctx> misplaced or a <b>'s inside changed"
import re, sys
B = re.compile(r'<b [^>]*>(.*?)</b>', re.S)
for on, off in ((sys.argv[1], sys.argv[2]), (sys.argv[3], sys.argv[4])):
    t_on, t_off = (re.sub(r'<!--.*?-->', '', open(x).read(), flags=re.S) for x in (on, off))
    i_on, i_off = B.findall(t_on), B.findall(t_off)
    assert i_on and i_on == i_off, (on, 'b inner moved')
    assert all(x.startswith('<![CDATA[') and '<fctx' not in x for x in i_on), (on, 'fctx inside a b')
    ends = [m.end() for m in re.finditer(r'</b>', t_on)]
    assert ends and all(t_on.startswith('<fctx ', e) for e in ends), (on, 'a </b> not followed by <fctx')
PY

# (3) recovery: short include list inline, long one behind inc_next=, and inc_next= prints it
F_A="$( first '<fctx [^>]*>' "$TMP/a.on" )"
printf '%s' "$F_A" | grep -q 'sibs="betaFn,gammaFn" sibs_total="2" inc="foo.h,bar.h" inc_total="2"/>' \
 \
        && ok "(3) short lists stay inline: $F_A" \
        || no "(3) basic.c <fctx> wrong: $F_A"
F_M="$( first '<fctx [^>]*>' "$TMP/m.on" )"
printf '%s' "$F_M" | grep -q 'sibs_total="144" sibs_capped="1"' \
    && ok "(3) sibs cap and count unchanged (144, capped)" \
    || no "(3) manyfn sibs moved: $F_M"
SIBS_ON="$( printf '%s' "$F_M" | grep -oE ' sibs="[^"]*"' )"; SIBS_OFF="$( first '<b [^>]*>' "$TMP/m.off" | grep -oE ' sibs="[^"]*"' )"
[ -n "$SIBS_ON" ] && [ "$SIBS_ON" = "$SIBS_OFF" ] \
    && ok "(3) the sibs= list is OFF's, name for name" \
    || no "(3) sibs= list differs from OFF"
printf '%s' "$F_M" | grep -q ' inc="' && no "(3) a 30-entry include list stayed inline" || ok "(3) a long include list leaves the page"
NEXT="$( printf '%s' "$F_M" | grep -oE 'inc_next="[^"]*"' | sed -E 's/^inc_next="(.*)"$/\1/' )"
printf '%s' "$F_M" | grep -q 'inc_total="30"' && [ -n "$NEXT" ] \
    && ok "(3) inc_total=\"30\" inc_next=\"$NEXT\"" \
    || no "(3) no inc_total/inc_next: $F_M"
python3 -c 'import shlex,sys; print("\n".join(shlex.split(sys.argv[1])))' "$NEXT" >"$TMP/argv"
ARGS=(); while IFS= read -r a; do ARGS+=( "$a" ); done <"$TMP/argv"
on "$FIX" --no-cache "${ARGS[@]}" >"$TMP/next.out" 2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
INC_OFF="$( first '<b [^>]*>' "$TMP/m.off" | grep -oE ' inc="[^"]*" inc_total="30" inc_capped="1"' )"
[ -n "$INC_OFF" ] && grep -q -- "$INC_OFF" "$TMP/next.out" \
    && ok "(3) running inc_next= prints OFF's include list" \
    || no "(3) inc_next= does not print the list"

# (4) root
R_ON="$( first '<ctx [^>]*>' "$TMP/w.on" )"
printf '%s' "$R_ON" | grep -qE ' (topk_default|est_tokens|map_next)="' && no "(4) ON <ctx> kept a dead attribute: $R_ON" || ok "(4) ON <ctx>: $R_ON"
# root= stays: an absolute-root single-root run owes it once, the rows' p= are relative to it (test/rootrelcheck.sh)
if printf '%s' "$R_ON" | grep -q ' root="'; then ok "(4) ON <ctx> keeps root= (rootrelcheck's disclosure)"; else no "(4) ON <ctx> lost root=: $R_ON"; fi
grep -qE 'topk_default=0: |est_tokens=: ' "$TMP/w.on" && no "(4) a removed attribute's reading stayed" || ok "(4) their readings left with them"
on  "$FIX" --expand=alphaFn --no-cache --max-tokens=4000 >"$TMP/mt.on"  2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
off "$FIX" --expand=alphaFn --no-cache --max-tokens=4000 >"$TMP/mt.off" 2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
MR_ON="$( first '<r [^>]*>' "$TMP/mt.on" )"
[ -n "$MR_ON" ] && [ "$MR_ON" = "$( first '<r [^>]*>' "$TMP/mt.off" )" ] && printf '%s' "$MR_ON" | grep -q ' est_tokens="' \
        && ok "(4) a map that rides keeps its own root= / est_tokens= (only <ctx> is cut)" \
        || no "(4) the riding map's root moved: $MR_ON"

# (4b) a degraded price keeps its label: the charge-buffer fault (RIPWIRE_FAULT_CHARGE_BUFFER=1, the seam estchargecheck #14 uses)
# makes the root say est_measured="0", and est_tokens= stays beside it — the reader who acts on an estimate still sees it
RF="$( RIPWIRE_FAULT_CHARGE_BUFFER=1 env -u RIPWIRE_VERB_SLIM "$BIN" "$FIX" --expand=alphaFn --top-k=0 --no-cache 2>/dev/null | perl -0pe 's/<!--.*?-->//gs' | grep -oE '<ctx [^>]*>' | head -1 )"   # status: the root tag is the verdict; a failed run leaves RF empty and the premise arm FAILs
if printf '%s' "$RF" | grep -q ' est_measured="0"'; then
    printf '%s' "$RF" | grep -q ' est_tokens="[0-9]*"' \
        && ok "(4b) a degraded estimate keeps est_tokens= beside est_measured=\"0\": $RF" \
        || no "(4b) the slim cut est_tokens= off a root that labels it an estimate: $RF"
    if printf '%s' "$RF" | grep -q ' root="'; then ok "(4b) root= stays on the degraded root"; else no "(4b) root= left the degraded root: $RF"; fi
else
    no "(4b) premise: the charge-buffer fault no longer labels the root est_measured=\"0\": [$RF]"
fi

# (5) legend + XML
LEG="$( perl -0ne 'print $1 if /(<!-- ripwire expand schema=ripwire\.expand\/v1: .*?-->)/s' "$TMP/m.on" )"
miss=""
for a in '<fctx ' ' sibs=' ' sibs_total=' ' sibs_capped=' ' inc_total=' ' inc_next=' '(inc='; do
    case "$LEG" in *"$a"*) ;; *) miss="$miss [$a]" ;; esac
done
[ -n "$LEG" ] && [ -z "$miss" ] \
    && ok "(5) the slim legend names <fctx> and each of its attributes" \
    || no "(5) the legend misses:$miss"
for f in a.on m.on w.on mt.on; do xmllint --noout "$TMP/$f" 2>/dev/null || no "(5) $f is not well-formed"; done
ok "(5) xmllint: well-formed"

# (7) other verbs
on  "$FIX" --callers=betaFn --no-cache >"$TMP/c.on"  2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
off "$FIX" --callers=betaFn --no-cache >"$TMP/c.off" 2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
cmp -s "$TMP/c.on" "$TMP/c.off" \
    && ok "(7) --callers byte-identical ON/OFF" \
    || no "(7) --callers moved"

# (8) CDATA is data
mkdir -p "$TMP/cd"
printf '#include "x.h"\nconst char* quoteTag(void) {\n  return "<b sibs=\\"q\\" inc=\\"r\\"></b>";\n}\nint other(void) { return 1; }\n' >"$TMP/cd/q.c"
on  "$TMP/cd" --expand=quoteTag --no-cache >"$TMP/q.on"  2>/dev/null   # status: on()/off() FAIL an exit above 2; the answer file is the verdict below
grep -q 'return "<b sibs=\\"q\\" inc=\\"r\\"></b>";' "$TMP/q.on" \
    && ok "(8) a body quoting <b sibs= is served unchanged" \
    || no "(8) CDATA rewritten"
xmllint --noout "$TMP/q.on" 2>/dev/null \
    && ok "(8) well-formed" \
    || no "(8) not well-formed"

# ── quality-delta: a Rust crate, one method made deep ───────────────────────────────────────────────────────────────────
# The file sits under a long path, so each row's sym= carries a long FILE:: head: it stays whole (the canonical id).
LP="crates/meter_core/src/instrumentation/registry/accumulators/meter_step_accumulator_impl.rs"
Q="$TMP/qd"; mkdir -p "$Q/$( dirname "$LP" )"
cat >"$Q/$LP" <<'RS'
pub struct Meter { n: i32 }
impl Meter {
    pub fn step(&mut self, x: i32) -> i32 {
        self.n += x;
        self.n
    }
}
pub fn helper(a: i32) -> i32 { a + 1 }
RS
( cd "$Q" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm base ) || no "(6) git fixture"
python3 - "$Q/$LP" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
deep = ''.join('if x > %d { ' % i for i in range(9)) + 'self.n += 1;' + ' }' * 9
s = s.replace('self.n += x;', 'self.n += x;\n        ' + deep + '\n' + '\n'.join('        if x == %d { self.n -= %d; }' % (i, i) for i in range(14)))
open(p, 'w').write(s)
PY
( cd "$Q" && env -u RIPWIRE_VERB_SLIM "$BIN" . --no-cache --quality-delta >"$TMP/q.on" 2>/dev/null; echo $? >"$TMP/q_on.rc" )
( cd "$Q" && RIPWIRE_VERB_SLIM=0 "$BIN" . --no-cache --quality-delta >"$TMP/q.off" 2>/dev/null; echo $? >"$TMP/q_off.rc" )
[ "$( cat "$TMP/q_on.rc" )" = "$( cat "$TMP/q_off.rc" )" ] && [ "$( cat "$TMP/q_on.rc" )" = 2 ] \
 \
        && ok "(6) exit code ON = OFF = 2" \
        || no "(6) exit codes ON=$( cat "$TMP/q_on.rc" ) OFF=$( cat "$TMP/q_off.rc" ) (want 2 2)"
QR_ON="$( first '<quality-delta [^>]*>' "$TMP/q.on" )"; QR_OFF="$( first '<quality-delta [^>]*>' "$TMP/q.off" )"
printf '%s' "$QR_OFF" | grep -q ' acked="0"' \
    && ok "(6) OFF prints acked=\"0\"" \
    || no "(6) OFF root changed: $QR_OFF"
printf '%s' "$QR_ON" | grep -qE ' (acked|stale|api-new-surface)="0"' && no "(6) ON kept a zero counter: $QR_ON" || ok "(6) ON drops zero counters"
for a in regressions minor gating preexisting-worse new-symbol; do
    printf '%s' "$QR_ON" | grep -q " $a=\"" || no "(6) ON lost $a="
done
ok "(6) regressions= minor= gating= preexisting-worse= new-symbol= always print"
printf '%s' "$QR_ON" | grep -q ' omit0="1"' \
    && ok "(6) omit0=\"1\" on the root says a counter left" \
    || no "(6) no omit0: $QR_ON"
grep -q 'omit0=1: ' "$TMP/q.on" \
    && ok "(6) omit0= is read in the legend" \
    || no "(6) omit0= undefined"
grep -q 'omit0' "$TMP/q.off" && no "(6) OFF says omit0" || ok "(6) OFF carries no omit0"
QS_ON="$( perl -0pe 's/<!--.*?-->//gs' "$TMP/q.on" | grep -oE '<r [^>]*>' | grep -oE ' sym="[^"]*"' )"
QS_OFF="$( perl -0pe 's/<!--.*?-->//gs' "$TMP/q.off" | grep -oE '<r [^>]*>' | grep -oE ' sym="[^"]*"' )"
printf '%s' "$QS_OFF" | grep -q "sym=\"$LP::" \
    && ok "(6) premise: OFF rows carry the long FILE:: head" \
    || no "(6) premise: no $LP:: head in OFF rows: [$QS_OFF]"
[ -n "$QS_ON" ] && [ "$QS_ON" = "$QS_OFF" ] \
    && ok "(6) every row's sym= ON = OFF (the canonical id stays whole)" \
    || no "(6) sym= moved: ON[$QS_ON] OFF[$QS_OFF]"
grep -qE 'acked=N: |stale=N: ' "$TMP/q.on" && no "(6) a dropped counter's reading stayed" || ok "(6) dropped counters' readings left"
python3 - "$TMP/q.on" "$TMP/q.off" <<'PY' \
    && ok "(6) gating rows ON = OFF by kind + canonical id" \
    || no "(6) gating rows differ"
import re, sys
def rows(p):
    t = re.sub(r'<!--.*?-->', '', open(p).read(), flags=re.S); out = []
    for r in re.findall(r'<r [^>]*>', t):
        a = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', r))
        s = a.get('sym', a.get('members', ''))
        out.append((a.get('kind'), s, a.get('gating', '0')))
    return out
on, off = rows(sys.argv[1]), rows(sys.argv[2])
assert on and on == off, (on, off)
assert any(g == '1' for _, _, g in on)
PY
for f in q.on q.off; do xmllint --noout "$TMP/$f" 2>/dev/null || no "(6) $f not well-formed"; done
ON_B=$( wc -c <"$TMP/q.on" ); OFF_B=$( wc -c <"$TMP/q.off" )
[ "$ON_B" -lt "$OFF_B" ] \
    && ok "(6) bytes ON $ON_B < OFF $OFF_B" \
    || no "(6) bytes ON $ON_B >= OFF $OFF_B"
# ── quality-delta on C: the zero-counter cut on a second language, sym= ON = OFF ───────────────────────────────────────────
C="$TMP/qdc"; mkdir -p "$C"
printf 'int step(int x)\n{\n    return x + 1;\n}\n' >"$C/m.c"
( cd "$C" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm base ) || no "(6c) git fixture"
python3 - "$C/m.c" <<'PY'
import sys
p = sys.argv[1]
body = ''.join('    if( x > %d ) {\n' % i for i in range(9)) + '        x++;\n' + '    }\n' * 9 + ''.join('    if( x == %d ) { x -= %d; }\n' % (i, i) for i in range(14))
open(p, 'w').write('int step(int x)\n{\n' + body + '    return x + 1;\n}\n')
PY
( cd "$C" && env -u RIPWIRE_VERB_SLIM "$BIN" . --no-cache --quality-delta >"$TMP/c.on" 2>/dev/null; echo $? >"$TMP/c_on.rc" )
( cd "$C" && RIPWIRE_VERB_SLIM=0 "$BIN" . --no-cache --quality-delta >"$TMP/c.off" 2>/dev/null; echo $? >"$TMP/c_off.rc" )
[ "$( cat "$TMP/c_on.rc" )" = "$( cat "$TMP/c_off.rc" )" ] \
    && ok "(6c) exit code ON = OFF ($( cat "$TMP/c_on.rc" ))" \
    || no "(6c) exit codes ON=$( cat "$TMP/c_on.rc" ) OFF=$( cat "$TMP/c_off.rc" )"
SYM_ON="$( perl -0pe 's/<!--.*?-->//gs' "$TMP/c.on" | grep -oE '<r [^>]*>' | grep -oE ' sym="[^"]*"' )"
SYM_OFF="$( perl -0pe 's/<!--.*?-->//gs' "$TMP/c.off" | grep -oE '<r [^>]*>' | grep -oE ' sym="[^"]*"' )"
[ -n "$SYM_ON" ] && [ "$SYM_ON" = "$SYM_OFF" ] \
    && ok "(6c) every row's sym= ON = OFF ($( printf '%s' "$SYM_ON" | wc -l | tr -d ' ' )+1 rows)" \
    || no "(6c) C sym= moved or no rows: ON[$SYM_ON] OFF[$SYM_OFF]"
xmllint --noout "$TMP/c.on" 2>/dev/null \
    && ok "(6c) well-formed" \
    || no "(6c) not well-formed"
( cd "$Q" && env -u RIPWIRE_VERB_SLIM "$BIN" . --no-cache --quality-delta --legend=full >"$TMP/qf.on" 2>/dev/null; RIPWIRE_VERB_SLIM=0 "$BIN" . --no-cache --quality-delta --legend=full >"$TMP/qf.off" 2>/dev/null )   # status: both runs exit 2 (gating); an empty answer FAILs the presence arm below
if grep -q '<quality-delta ' "$TMP/qf.on" && grep -q '<quality-delta ' "$TMP/qf.off"; then ok "(1) presence: both --legend=full runs printed a root"; else no "(1) presence: a --legend=full run printed no <quality-delta> root"; fi
sed -E 's/ at="[^"]*"//' "$TMP/qf.on" >"$TMP/qf.on.n"; sed -E 's/ at="[^"]*"//' "$TMP/qf.off" >"$TMP/qf.off.n"
cmp -s "$TMP/qf.on.n" "$TMP/qf.off.n" \
    && ok "(1) quality-delta --legend=full: ON == OFF" \
    || no "(1) quality-delta --legend=full moved"

[ "$fail" = 0 ] && echo "verbslimcheck: ALL PASS" || { echo "verbslimcheck: FAIL"; exit 1; }
