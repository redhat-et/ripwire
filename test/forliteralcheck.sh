#!/usr/bin/env bash
# forliteralcheck.sh — THE LITERAL ANCHOR of a --for answer whose task names a literal (lane MF1-LIT; src/forliteral.h).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 251ac97c; [G] arms are twins and near-miss negatives
# that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   TRIGGER  CLI --for (XML, default regime, one root) whose task carries a "double-quoted message" (two words or more) or a
#            CONST_SHAPED word (APPTOOL_RENDER_MODE, PYTHONASYNCIODEBUG).
#   WHAT     a legend comment + <lit s= shape= hits= src= shown= comment= test= doc= next="--grep=S" bytes=> just before </ctx>:
#            <ls p= l= k=string|code|? in= ink=> source sites (sites in a function first), <b> owner bodies, <x> excerpts.
#   NOT      a comment, a docstring, a test path or a doc file is never an <ls> row (counted only); no literal, no hit,
#            --json and --token-budget carry none (byte-identical to RIPWIRE_NO_LITERAL_ANCHOR=1).
#
# Arms:
#   L1 [P] --for=APPTOOL_RENDER_MODE: shape="const"; config.py k="string" in="read_mode", runner.py in="debug_mode" and the
#          a_table.py rows (src="3", several sites listed, never one picked); the read_mode body is printed whole
#   L1b [P] the first row is the site inside a function (config.py), not a_table.py, which the scan's path order puts first
#   L1c [P] the a_table.py string site (outside any function) carries lines="3-5" and the entry after it
#   L2 [P] the counts: comment="2" (a # comment and a docstring), test="1", doc="1"; none of those files' lines is an <ls> row
#   L3 [P] a quoted message ("dependency cycle detected" error): shape="quoted", the check_cycle row; the ranked answer already
#          prints check_cycle's body, so the row says body="above" and the body appears exactly once
#   L4 [P] a body over the cap (big_dispatch): an <x> excerpt holding the site line, of= the body's lines, next="--expand=…big_dispatch"
#   L2b [P] a triple-quoted string is a docstring only as the FIRST statement of a module / class / def body (Python): a `"""`
#          opening a call-argument line (raise ValueError(\n """msg""")), a bare string in an `if` body and a Kotlin raw
#          string and a GDScript triple-quoted string at the top of the file are string SITES (rows), the four real docstrings stay
#          counted (comment="4")
#   L4b [P] two far-apart sites in one over-ten-line body: ONE window per site, joined by an ellipsis, never the span between
#   L4c [P] a ten-line body is printed whole (<b>); an eleven-line body is an excerpt [site-1, site+5] plus its signature line
#   L4d [G] a ten-line body over 3000 bytes is still an excerpt (the byte cap on a short body), the long line left out
#   L10 [G] caps: ten one-site readers: shown="8" capped="1", exactly three <b>/<x> bodies
#   L11 [P] the compact legend (the default) is a short form; --legend=full keeps the long text; the payload is the same
#   L5 [G] no literal: a lower-case word, a ONE-word quoted value ("full", and "detected", which a source string holds), a
#          backticked span, a 4-byte CONST (ABC_D): no <lit
#   L6 [G] a CONST_SHAPED literal with no hit: no <lit (never a "the literal is unused" claim)
#   L6b [P] a literal met only in a test path and a README (APPTOOL_TEST_ONLY): no <lit (counts alone anchor nothing)
#   L7 [G] prefix identity: the answer minus the legend comment and <lit>…</lit> equals RIPWIRE_NO_LITERAL_ANCHOR=1 byte for byte
#   L8 [G] --json, --token-budget=3000, --format=candidates and a two-root call (--format=columnar is refused with --for): no <lit, byte-identical to
#          RIPWIRE_NO_LITERAL_ANCHOR=1
#   L9 [G] bytes= is the element's own size (open tag to </lit>)
#   X1 [G] determinism  X2 [G] xmllint well-formed  X3 [G] no "--" inside the lit legend comment
#   N2 [train 42b T-5] `x = x + 1  # note:` is no def header: the bare string after it is a row, not a docstring (twin: the same without the comment)
#   N1 [train 42b T-3] an <x> excerpt line over 200 bytes is cut on a UTF-8 boundary with cut="1" (a 48.9 KB minified body); twin: none
#
# Usage:  bash test/forliteralcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forliteralcheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_LITERAL_ANCHOR
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forliteralcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { no "binary not executable: $BIN"; exit 1; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" TMPDIR="$TMP/"; mkdir -p "$HOME"
FIX="$ROOT/test/forliteralfix"
run(){ ( cd "$FIX" || exit 1; "$BIN" "$FIX" --no-cache "$@" </dev/null 2>/dev/null ); }
off(){ ( cd "$FIX" || exit 1; RIPWIRE_NO_LITERAL_ANCHOR=1 "$BIN" "$FIX" --no-cache "$@" </dev/null 2>/dev/null ); }
lit(){ python3 -I -c 'import sys;s=sys.stdin.read();i=s.find("<lit ");print(s[i:s.find("</lit>",i)+6] if i>=0 else "")'; }
has(){ grep -qF -- "$2" <<<"$1"; }

# ── L1 ──
A="$( run --for=APPTOOL_RENDER_MODE )"; rc=$?
L="$( lit <<<"$A" )"
if [ "$rc" -eq 0 ] && [ -n "$L" ] && has "$L" 's="APPTOOL_RENDER_MODE" shape="const"' && has "$L" 'src="3"' \
   && has "$L" '<ls p="app/config.py" l="5" k="string" in="read_mode" ink="fn"' && has "$L" 'in="debug_mode"' \
   && has "$L" '<b t="fn" l="4" p="app/config.py" n="read_mode">'; then
    ok "L1 const literal: every source site listed (src=3), read_mode body printed"
else no "L1 const literal block wrong (rc=$rc): ${L:0:600}"; fi
# ── L1b / L1c ──
first="$( grep -o '<ls p="[^"]*" l="[0-9]*"' <<<"$L" | head -1 )"
if [ "$first" = '<ls p="app/config.py" l="5"' ]; then ok "L1b a site inside a function is the first row (a_table.py sorts earlier by path)"
else no "L1b first row is not the function site: $first"; fi
if has "$L" '<ls p="app/a_table.py" l="3" k="string" in="MODES" ink="var" lines="3-5">' && has "$L" '"OTHER": "flag",'; then
    ok "L1c a string site outside any function carries the lines after it (lines=3-5)"
else no "L1c table row context wrong: ${L:0:600}"; fi
# ── L2 ──
if has "$L" 'comment="2"' && has "$L" 'test="1"' && has "$L" 'doc="1"' && ! has "$L" 'p="tests/' && ! has "$L" 'p="README.md"' \
   && ! has "$L" 'in="helper"' && ! has "$L" 'l="7" k='; then
    ok "L2 comment/docstring/test/doc sites counted (2/1/1), never an <ls> row"
else no "L2 counts or rows wrong: ${L:0:600}"; fi
# ── L3 ──
QA="$( run '--for="dependency cycle detected" error' )"; Q="$( lit <<<"$QA" )"
nb="$( grep -o 'n="check_cycle"><!\[CDATA\[' <<<"$QA" | wc -l | tr -d ' ' )"
if has "$Q" 's="dependency cycle detected" shape="quoted"' && has "$Q" 'in="check_cycle" ink="fn" body="above"' && [ "$nb" = "1" ]; then
    ok "L3 quoted message: check_cycle row; its body, already in the answer, is marked body=above and printed once"
else no "L3 quoted literal block wrong: ${Q:0:600}"; fi
# ── L4 ──
X="$( run --for=APPTOOL_BIG_FLAG | lit )"
if has "$X" '<x p="app/big.py" n="big_dispatch"' && has "$X" 'of="1-' && has "$X" 'next="--expand=app/big.py:1:big_dispatch"' \
   && has "$X" 'environ.get("APPTOOL_BIG_FLAG")' && ! has "$X" '<b t="fn" l="1" p="app/big.py"' && has "$X" 'l="1,63-69"'; then
    ok "L4 a body over ten lines is an excerpt: the signature line and site-1..site+5, next= the whole body"
else no "L4 excerpt wrong: ${X:0:600}"; fi
# ── L2b ──
QB="$( run '--for="bad things happened here" error' )"; B2="$( lit <<<"$QB" )"
if has "$B2" 's="bad things happened here" shape="quoted"' && has "$B2" 'comment="4"' \
   && has "$B2" '<ls p="app/errs.py" l="24" k="string" in="fail_hard" ink="fn"' \
   && has "$B2" '<ls p="app/errs.py" l="31" k="string" in="branch_str" ink="fn"' && has "$B2" '<ls p="app/Msg.kt" l="4"' && has "$B2" '<ls p="app/top.gd" l="1" k="string"' \
   && ! has "$B2" 'p="app/errs.py" l="1"' && ! has "$B2" 'p="app/errs.py" l="6"' && ! has "$B2" 'p="app/errs.py" l="9"' \
   && ! has "$B2" 'p="app/errs.py" l="17"'; then
    ok "L2b only a first-statement string of a module/class/def body is a docstring (4); a call argument, an if-body string, a Kotlin raw string and a GDScript file-top string are sites"
else no "L2b docstring position/language wrong: ${B2:0:900}"; fi
# ── L4b ──
F="$( run --for=APPTOOL_FAR_FLAG | lit )"
nl="$( python3 -I -c 'import sys,re;m=re.search(r"<x [^>]*><!\[CDATA\[(.*?)\]\]></x>",sys.argv[1],re.S);print(len(m.group(1).split(chr(10))) if m else -1)' "$F" )"
if has "$F" '<x p="app/far.py" n="far_apart" l="4-10,29-35" of="4-35"' && has "$F" 'next="--expand=app/far.py:4:far_apart"' \
   && ! has "$F" '<b t="fn" l="4" p="app/far.py"' && ! has "$F" 'filler line number 12' && has "$F" 'filler line number 3' \
   && has "$F" 'filler line number 24' && [ "$nl" = "15" ]; then
    ok "L4b two far-apart sites: one window each (4-10 and 29-35), 15 lines with the ellipsis line between, never the span between them"
else no "L4b far-apart excerpt wrong (lines=$nl): ${F:0:900}"; fi
# ── L4c ──
T10="$( run --for=APPTOOL_TEN_FLAG | lit )"; T11="$( run --for=APPTOOL_ELEVEN_FLAG | lit )"
if has "$T10" '<b t="fn" l="3" p="app/mid.py" n="ten_lines">' && ! has "$T10" '<x ' \
   && has "$T11" '<x p="app/mid.py" n="eleven_lines" l="15-21" of="15-25"' && ! has "$T11" '<b ' && ! has "$T11" 'eleven 6'; then
    ok "L4c a ten-line body is printed whole; an eleven-line body is an excerpt (15-21 of 15-25)"
else no "L4c ten/eleven-line boundary wrong: ${T10:0:400} || ${T11:0:600}"; fi
# ── L4d ──
LL="$( run --for=APPTOOL_LONG_FLAG | lit )"
if has "$LL" '<x p="app/longline.py" n="long_line" l="3,11-12" of="3-12"' && ! has "$LL" '<b ' && ! has "$LL" 'ZZZZZZZZ'; then
    ok "L4d a ten-line body over the 3000-byte cap is an excerpt (3,11-12 of 3-12), the 3.3 KB line left out"
else no "L4d byte cap on a short body wrong: ${LL:0:500}"; fi
# ── L10 ──
M="$( run --for=APPTOOL_MANY_FLAG | lit )"
nbx="$( grep -o '<[bx] ' <<<"$M" | wc -l | tr -d ' ' )"
nls="$( grep -o '<ls ' <<<"$M" | wc -l | tr -d ' ' )"
if has "$M" 'src="10" shown="8" capped="1"' && [ "$nls" = "8" ] && [ "$nbx" = "3" ]; then
    ok "L10 caps: ten readers show 8 rows (capped=1) and exactly 3 bodies"
else no "L10 caps wrong (ls=$nls bodies=$nbx): ${M:0:500}"; fi
# ── L5 / L6 ──
neg=0
for t in 'apptool_render_mode' '"full" mode' 'the `APPTOOL` switch' 'ABC_D toggle' 'NOPE_NOT_HERE_ANYWHERE' 'APPTOOL_TEST_ONLY' '"detected" banner'; do
    o="$( run "--for=$t" )"; nrc=$?
    # CR 5712563408 (forliteralcheck.sh:136): an absence arm reads a run whose success was checked
    if [ "$nrc" -ne 0 ] || [ -z "$o" ]; then neg=1; no "L5/L6 the task did not answer (rc=$nrc): $t"
    elif has "$o" '<lit '; then neg=1; no "L5/L6 a block rode on: $t"; fi
done
if [ "$neg" -eq 0 ]; then
    ok "L5/L6/L6b no block: lower-case word, one-word quotes, backticked word, short CONST, CONST with no hit, test/doc-only CONST"
fi
# ── L7 ──
for t in APPTOOL_RENDER_MODE '"dependency cycle detected" error' APPTOOL_BIG_FLAG; do
    a="$( run "--for=$t" | python3 -I -c 'import sys,re;s=sys.stdin.read();print(re.sub(r"<!-- ripwire for lit:.*?-->(<lit .*?</lit>)","",s,flags=re.S),end="")' )"
    b="$( off "--for=$t" )"
    if [ -n "$b" ] && [ "$a" = "$b" ]; then ok "L7 prefix identity vs RIPWIRE_NO_LITERAL_ANCHOR=1: $t"; else no "L7 answer outside the block changed: $t"; fi
done
# ── L8 ──
for f in --json --token-budget=3000 --format=candidates; do
    a="$( run --for=APPTOOL_RENDER_MODE "$f" )"; b="$( off --for=APPTOOL_RENDER_MODE "$f" )"
    if [ -n "$a" ] && [ "$a" = "$b" ] && ! has "$a" '<lit '; then ok "L8 $f: no block, byte-identical"; else no "L8 $f carries a block or differs"; fi
done
co="$( run --for=APPTOOL_RENDER_MODE --format=columnar )"; crc=$?
if [ "$crc" -ne 0 ] && [ -z "$co" ]; then ok "L8 --format=columnar: the CLI refuses it with --for (the columnar guard in the block is defensive, unreachable)"
else no "L8 --format=columnar with --for no longer refused (rc=$crc): the lit block's columnar guard is now reachable and needs an arm"; fi
mkdir -p "$TMP/root2" && printf 'def second_root():\n    return 1\n' > "$TMP/root2/second.py"
a="$( cd "$FIX" || exit 1; "$BIN" "$FIX" "$TMP/root2" --no-cache --for=APPTOOL_RENDER_MODE </dev/null 2>/dev/null )"
b="$( cd "$FIX" || exit 1; RIPWIRE_NO_LITERAL_ANCHOR=1 "$BIN" "$FIX" "$TMP/root2" --no-cache --for=APPTOOL_RENDER_MODE </dev/null 2>/dev/null )"
if [ -n "$a" ] && [ "$a" = "$b" ] && ! has "$a" '<lit '; then ok "L8 two roots: no block, byte-identical"; else no "L8 a two-root call carries a block or differs"; fi
# ── L9 ──
if python3 -I -c 'import sys,re;s=sys.argv[1];m=re.search(r" bytes=\"(\d+)\"",s);sys.exit(0 if m and int(m.group(1))==len(s.encode()) else 1)' "$L"; then
    ok "L9 bytes= is the element's own size"
else no "L9 bytes= disagrees with the element"; fi
# ── L11 ──
legendOf(){ python3 -I -c 'import sys,re;m=re.search(r"<!-- ripwire for lit:.*?-->",sys.stdin.read(),re.S);print(m.group(0) if m else "MISSING",end="")'; }
noLegend(){ python3 -I -c 'import sys,re;print(re.sub(r"<!-- ripwire for lit:.*?-->","",sys.stdin.read(),flags=re.S),end="")'; }
LC="$( run --for=APPTOOL_RENDER_MODE | legendOf )"; LF="$( run --for=APPTOOL_RENDER_MODE --legend=full | legendOf )"
PC="$( run --for=APPTOOL_RENDER_MODE | lit | noLegend )"; PF="$( run --for=APPTOOL_RENDER_MODE --legend=full | lit | noLegend )"
# train 42b T-4 (rv-mf1-lit-delta N3): the compact form names every attribute the element prints (hits= src= shown= capped= shape=
# bytes= next= and T-3's cut=) and says of= is the body's line range, never "whole": the ceiling moved 340 -> 450 for those names only; CR harvest 42b: 450 -> 470 for body=held (the cap's disclosure)
if [ "${#LC}" -le 470 ] && [ "${#LC}" -ge 250 ] && [ "${#LF}" -ge 700 ] && has "$LF" 'docs, shell, config' && [ "$LC" != "MISSING" ] \
   && has "$LC" 'k=' && has "$LC" 'comment=' && has "$LC" 'floor=' && has "$LC" 'body=above' && has "$LC" 'held' && [ -n "$PC" ] && [ "$PC" = "$PF" ] \
   && has "$LC" 'hits=' && has "$LC" 'src=' && has "$LC" 'shown=' && has "$LC" 'capped=' && has "$LC" 'shape=' && has "$LC" 'bytes=' \
   && has "$LC" 'next=' && has "$LC" 'cut=' && has "$LF" 'cut=' && has "$LC" 'of= body lines' && ! has "$LC" 'of= whole'; then
    ok "L11 compact legend ${#LC} B (the default); --legend=full keeps ${#LF} B naming docs, shell, config; same payload"
else no "L11 legend sizes wrong: compact=${#LC} full=${#LF} samepayload=$([ "$PC" = "$PF" ] && echo y || echo n)"; fi
# ── N1 (train 42b T-3, rv-mf1-lit-delta N1): an <x> excerpt cuts each line at 200 bytes (a minified one-line body printed 48.9 KB) ──
MIN="$TMP/min"; mkdir -p "$MIN/web"
python3 -I -c 'import sys;b="".join("var v%d=a+%d;"%(i,i) for i in range(3000));open(sys.argv[1],"w").write("function minFail(a){"+b+"throw new Error(\"bad things happened here minified\")}\n")' "$MIN/web/m.js"
printf 'export function ok(){ return 1 }\n' >"$MIN/web/ok.js"
MO="$( cd "$MIN" && "$BIN" "$MIN" --no-cache '--for=where is the "bad things happened here" error raised' </dev/null 2>/dev/null )"
MX="$( python3 -I -c 'import sys,re;m=re.search(r"<x [^>]*>.*?</x>",sys.stdin.read(),re.S);print(m.group(0) if m else "MISSING",end="")' <<<"$MO" )"
if [ "$MX" != "MISSING" ] && [ "${#MX}" -le 3000 ] && has "$MX" 'cut="1"' && has "$MX" 'l="1"' && has "$MX" 'function minFail(a)'; then
    ok "N1 a minified body's excerpt is cut per line (${#MX} B), cut=\"1\" disclosed, the site line kept"
else no "N1 excerpt not capped: ${#MX} B, cut=$(has "$MX" 'cut="1"' && echo y || echo n)"; fi
SX="$( run --for=APPTOOL_RENDER_MODE | lit )"
if ! has "$SX" 'cut="1"'; then ok "N1 twin: short lines are never marked cut"; else no "N1 twin: a short-line answer says cut=\"1\""; fi
# ── N2 (train 42b, rv-mf1-lit-delta N2): a trailing comment ending in a colon is no def header, so the next bare string is no docstring ──
DOC="$TMP/doc"; mkdir -p "$DOC/app"
printf 'def colon_comment(x):\n    x = x + 1\n    """bad things happened here in a bare mid-body string"""\n    return x\n\n\ndef colon_comment2(x):\n    x = x + 1  # note:\n    """bad things happened here in a bare mid-body string two"""\n    return x\n' >"$DOC/app/d.py"
DO="$( cd "$DOC" && "$BIN" "$DOC" --no-cache '--for=where is the "bad things happened here" string' </dev/null 2>/dev/null | lit )"
if has "$DO" '<ls p="app/d.py" l="9"' && has "$DO" '<ls p="app/d.py" l="3"'; then ok "N2 a mid-body string after a '# note:' comment is a row (l=9), like its twin (l=3)"
else no "N2 the comment-colon string is not a row: $(grep -o '<ls p="app/d.py" l="[0-9]*"' <<<"$DO" | tr '\n' ' ')"; fi
# ── R1 (CR 4423843223): the matched line, the context lines and an <x> excerpt are raw source text: a credential in them is redacted ──
RD="$TMP/red"; mkdir -p "$RD/app"
# The two secret-shaped values are joined at runtime: the tracked file must not itself hold a credential-shaped literal (ripwirepubliccheck arm 4).
RAWS_AWS="AKIA""IOSFODNN7EXAMPLE"; RAWS_GH="ghp""_abcdefghijklmnopqrstuvwxyz0123456789"
python3 -I -c 'import sys
d,aws,gh=sys.argv[1:4]
body=["def big(x):"]+["    filler%d = %d"%(i,i) for i in range(30)]
body.insert(15,"    key = \""+aws+"\"; mode = os.environ.get(\"APPTOOL_SECRET_FLAG\")")
open(d+"/app/big.py","w").write("\n".join(body)+"\n")
open(d+"/app/tbl.py","w").write("X = 1\nTABLE = {\n  \"APPTOOL_SECRET_FLAG\": \""+gh+"\",\n  \"k\": \""+aws+"\",\n}\n")' "$RD" "$RAWS_AWS" "$RAWS_GH"
RO="$( cd "$RD" && "$BIN" "$RD" --no-cache --for=APPTOOL_SECRET_FLAG </dev/null 2>/dev/null | lit )"
RN="$( cd "$RD" && "$BIN" "$RD" --no-cache --no-redact --for=APPTOOL_SECRET_FLAG </dev/null 2>/dev/null | lit )"
if [ -n "$RO" ] && has "$RO" '<x p="app/big.py"' && has "$RO" 'lines="3-5"' && ! has "$RO" "$RAWS_AWS" && ! has "$RO" "${RAWS_GH:0:15}" \
   && has "$RO" '[REDACTED:aws-key]' && has "$RO" '[REDACTED:github-token]' && has "$RN" "$RAWS_AWS" && has "$RN" "${RAWS_GH:0:15}"; then
    ok "R1 a secret on the matched line, in the lines after a table entry and in an <x> window is redacted; --no-redact keeps it verbatim (twin)"
else no "R1 redaction wrong: ${RO:0:900}"; fi
# ── H1 (CR 5712563408, forliteral.h:619): an owner whose body the 3-body cap held back says body="held" on its rows ──
nheld="$( grep -o 'body="held"' <<<"$M" | wc -l | tr -d ' ' )"; nabove="$( grep -o 'body="above"' <<<"$M" | wc -l | tr -d ' ' )"
if [ "$nheld" = "5" ] && [ "$nabove" = "0" ] && [ "$nbx" = "3" ]; then ok "H1 ten readers: 3 bodies printed, the 5 other shown rows say body=\"held\""
else no "H1 held markers wrong: held=$nheld above=$nabove bodies=$nbx"; fi
TWH="$( run --for=APPTOOL_RENDER_MODE | lit )"
if ! has "$TWH" 'body="held"'; then ok "H1 twin: an answer inside the cap carries no held marker"; else no "H1 twin: held marker with bodies under the cap"; fi
# ── F1 (CR 5712563408, forliteral.h:500): 70 source files hold the literal, 64 are classified: the rest are k=? and comment= is a floor ──
FL="$TMP/floor"; mkdir -p "$FL/app"
python3 -I -c 'import sys
d=sys.argv[1]
for i in range(70):
    open("%s/app/m%02d.py"%(d,i),"w").write("# APPTOOL_FLOOR_FLAG is described here\ndef f%d():\n    return \"APPTOOL_FLOOR_FLAG\"\n"%i)' "$FL"
FO="$( cd "$FL" && "$BIN" "$FL" --no-cache --for=APPTOOL_FLOOR_FLAG </dev/null 2>/dev/null | lit )"
if has "$FO" 'floor="1"'; then ok "F1 a literal in more than 64 source files: floor=\"1\" (comment= cannot see the unclassified ones)"
else no "F1 floor flag missing with unclassified sites: ${FO:0:400}"; fi
if ! has "$L" 'floor="1"'; then ok "F1 twin: a fully classified answer carries no floor"; else no "F1 twin: floor on a clean answer"; fi
# ── X1-X3 ──
if [ "$A" = "$( run --for=APPTOOL_RENDER_MODE )" ]; then ok "X1 deterministic"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "X2 xmllint well-formed"; else no "X2 not well-formed"; fi
else ok "X2 SKIP: xmllint not installed"; fi
C="$( python3 -I -c 'import sys,re;m=re.search(r"<!-- ripwire for lit:(.*?)-->",sys.stdin.read(),re.S);print(m.group(1) if m else "MISSING")' <<<"$A" )"
if [ "$C" != "MISSING" ] && ! has "$C" '--'; then ok "X3 the lit legend comment holds no --"; else no "X3 legend comment missing or holds --"; fi

[ "$fail" -eq 0 ] && echo "forliteralcheck: OK" || echo "forliteralcheck: FAILED"
exit "$fail"
