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
#   K1-K10, M1-M5 (lane LITERAL-ANCHOR; RED on base 4e8bfde7 where [P], fixture built at runtime): a dotted key (3+ segments, or 2 with a setting/option/key/command/flag word) or
#          an unquoted/backticked/single-quoted 3+ word message with an error/notification/message word, read from the --for text: whole-key rows, longer= counts, frag=1, near misses
#   T1-T22 (lane TABLE-CONST V2; RED on base b8c31789 where [P], fixture built at runtime): shape="table", the last try: a registration, table, compile-time or
#          add-a-new word, or default/handler when a table row exists, reaches the sites of the identifier the task names; near misses keep the answer byte-identical
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
# ── K / M (lane LITERAL-ANCHOR): a dotted key or an unquoted cued message read from the --for text; fixture built here at runtime ──
KF="$TMP/keys"; mkdir -p "$KF/app/test" "$KF/docs" "$KF/pkg"
python3 -I -c 'import sys
d=sys.argv[1]
mention="".join("  \"see #files.autoSave# in row %d\",\n"%i for i in range(12))
open(d+"/app/registry.ts","w").write("export const R = {\n  \"files.autoSave\": {\n    \"type\": \"string\",\n    \"default\": \"off\",\n  },\n  \"files.autoSaveDelay\": { \"type\": \"number\" },\n  \"files.autoSave.onWindowChange\": { \"type\": \"boolean\" },\n};\n")
open(d+"/app/aaa_mentions.ts","w").write("export const D = [\n"+mention+"];\n")
open(d+"/app/service.ts","w").write("export function readAuto(c: any) {\n  return c.getValue(\"files.autoSave\");\n}\nexport function other(c: any) {\n  return c.getValue(\"myfiles.autoSave\") + c.getValue(\"files.autoSaveDelay\");\n}\n")
open(d+"/app/cfg.py","w").write("def load(cfg):\n    return cfg.get(\"sql.stats.collection.enabled\")\n\ndef fail():\n    # Stale cache entry found\n    raise ValueError(\"Invalid user settings file\")\n\ndef chain(n):\n    raise ValueError(\"terminal {} must be the last filter in a chain\".format(n))\n\ndef nameit():\n    return \"Widget.render\" + \"config.settings.json\" + \"self.alpha.beta\" + \"why does retry fail\" + \"bad state\" + \"Widget.render.now\" + \"a.b.c\" + \"foo(x) bar baz\" + \"a.b.k\" + \"no outer cue message here\"\n\ndef codeonly(alpha, beta):\n    x = alpha if beta else 0\n    return x\n\ndef caller():\n    return \"foo.bar.baz\"\n")
open(d+"/app/cfg.go","w").write("package app\n\nfunc Reg() string {\n\treturn \"go.only.key\"\n}\n")
open(d+"/app/test/registry.test.ts","w").write("const a = \"only.test.key\";\nconst m = \"Only a test message here\";\n")
open(d+"/app/note.py","w").write("# only.comment.key is mentioned here\nX = 1\n")
open(d+"/docs/guide.md","w").write("only.doc.key is documented\n")
many="".join("def r%d():\n    return \"many.sites.key\"\n\n"%i for i in range(11))
open(d+"/pkg/many.py","w").write(many)' "$KF"
krun(){ ( cd "$KF" || exit 1; "$BIN" "$KF" --no-cache "$@" </dev/null 2>/dev/null ); }
koff(){ ( cd "$KF" || exit 1; RIPWIRE_NO_LITERAL_ANCHOR=1 "$BIN" "$KF" --no-cache "$@" </dev/null 2>/dev/null ); }
K1="$( krun '--for=files.autoSave afterDelay setting flow' )"; KL="$( lit <<<"$K1" )"
if has "$KL" 's="files.autoSave" shape="dotted"' && has "$KL" '<ls p="app/registry.ts" l="2" k="string"' && has "$KL" 'lines="2-4"' \
   && has "$KL" '<ls p="app/service.ts" l="2" k="string" in="readAuto"' && has "$KL" 'in="readAuto" ink="fn" body="above"'; then
    ok "K1 [P] a two-segment key with a setting cue, bare in the --for text: the registration (lines after it) and the reader, whose body the answer already printed"
else no "K1 dotted key block wrong: ${KL:0:900}"; fi
# K2: rows are the WHOLE key; a longer name or a child key is counted, never a row; quoted whole-key sites rank above the mentions past the row cap
if has "$KL" 'longer="4"' && has "$KL" 'capped="1"' && ! has "$KL" 'autoSaveDelay":' && ! has "$KL" 'onWindowChange' && ! has "$KL" 'myfiles.autoSave'; then
    ok "K2 [P] files.autoSaveDelay, a child key and myfiles.autoSave are counted in longer=, never rows"
else no "K2 whole-key filter wrong: ${KL:0:900}"; fi
frs="$( grep -o '<ls p="[^"]*" l="[0-9]*"' <<<"$KL" | head -2 | tr '\n' ' ' )"
if [ "$frs" = '<ls p="app/service.ts" l="2" <ls p="app/registry.ts" l="2" ' ] && [ "$( grep -o '<ls ' <<<"$KL" | wc -l | tr -d ' ' )" = "8" ]; then
    ok "K2b [P] whole-key sites first (in-function, then the top-level registration), the row cap (8) cuts mentions and says so"
else no "K2b order wrong: $frs"; fi
K3="$( krun '--for=which code reads sql.stats.collection.enabled' | lit )"
if has "$K3" 's="sql.stats.collection.enabled" shape="dotted"' && has "$K3" 'in="load"'; then ok "K3 [P] three segments need no cue"; else no "K3 three-segment key: ${K3:0:500}"; fi
K3G="$( krun '--for=go.only.key' | lit )"
if has "$K3G" 'p="app/cfg.go"' && has "$K3G" 'in="Reg"'; then ok "K3b [P] the same in a Go file of the polyglot fixture"; else no "K3b: ${K3G:0:500}"; fi
K4="$( krun '--for=Widget.render option' | lit )"
if has "$K4" 's="Widget.render" shape="dotted"'; then ok "K4 [P] Class.method WITH a cue is a key"; else no "K4 cued Class.method: ${K4:0:300}"; fi
for near in 'files.autoSave flow' 'files.autoSave' 'Widget.render flow' 'config.settings.json option' 'app/service.ts setting' 'service.ts setting' \
            'self.alpha.beta flow' 'foo.bar.baz() flow' 'only.test.key' 'only.test.key setting' 'files.autoSave keyboard flow' 'files.autoSave hotkeys flow' 'Widget.render.now flow' 'a.b.c' 'a.b.k' 'only.comment.key' 'only.doc.key' 'absent.dotted.key' '1.2.3 setting'; do
    N="$( krun "--for=$near" )"
    if ! has "$N" '<lit ' && [ "$N" = "$( koff "--for=$near" )" ]; then ok "K5 [G] near miss, no <lit and byte-identical: $near"
    else no "K5 near miss fired: $near: $( lit <<<"$N" | cut -c1-300 )"; fi
done
K6="$( krun '--for=files.autoSave setting' )"; K6O="$( koff '--for=files.autoSave setting' )"
K6S="$( python3 -I -c 'import sys,re;s=sys.stdin.read();s=re.sub(r"<!-- ripwire for lit:.*?-->","",s,flags=re.S);print(re.sub(r"<lit .*?</lit>","",s,flags=re.S),end="")' <<<"$K6" )"
if [ "$K6S" = "$K6O" ] && has "$K6" '<lit '; then ok "K6 [P] prefix identity: minus legend and block, the answer equals RIPWIRE_NO_LITERAL_ANCHOR=1"; else no "K6 the ordinary answer moved"; fi
if has "$K6" 'shape=dotted' && has "$K6" 'longer=' && has "$( krun '--for=sql.stats.collection.enabled' --legend=full )" 'shape=dotted'; then
    ok "K7 [P] the key legend clause rides with a dotted fire, compact and full"; else no "K7 legend clause missing"; fi
KT="$( run --for=APPTOOL_RENDER_MODE )"
if ! has "$KT" 'shape=dotted'; then ok "K7b [G] a const fire carries no key clause (its bytes do not move)"; else no "K7b clause on a const fire"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$K1" | xmllint --noout - 2>/dev/null; then ok "K8 [P] xmllint well-formed"; else no "K8 not well-formed"; fi
else ok "K8 SKIP: xmllint not installed"; fi
K9="$( krun '--for=many.sites.key' | lit )"
if has "$K9" 'src="11" shown="8" capped="1"' && has "$K9" 'next="--grep=many.sites.key"'; then ok "K9 [P] the row guard discloses the cut with next="; else no "K9 cap: ${K9:0:300}"; fi
for j in --json --token-budget=3000; do
    if [ "$( krun '--for=files.autoSave setting' "$j" )" = "$( koff '--for=files.autoSave setting' "$j" )" ]; then ok "K10 [G] $j carries no block"; else no "K10 $j moved"; fi
done
# messages: the stored --for subject is unquoted, so the text around the cue word IS the message
M1="$( krun '--for=Invalid user settings file notification' | lit )"
if has "$M1" 's="Invalid user settings file" shape="message"' && has "$M1" 'k="string" in="fail"' && ! has "$M1" 'frag='; then ok "M1 [P] an unquoted message with a trailing cue"; else no "M1: ${M1:0:500}"; fi
M2="$( krun '--for=error Invalid user settings file' | lit )"; M2b="$( krun '--for=Invalid user settings file error message' | lit )"
if has "$M2" 's="Invalid user settings file"' && has "$M2b" 's="Invalid user settings file"'; then ok "M2 [P] a leading cue; a two-word trailing cue"; else no "M2: ${M2:0:300} / ${M2b:0:300}"; fi
M3="$( krun '--for=the `Invalid user settings file` error' | lit )"; M3b="$( krun "--for=it shows the 'Invalid user settings file' message" | lit )"
if has "$M3" 'shape="message"' && has "$M3b" 'shape="message"'; then ok "M3 [P] a backticked or single-quoted span with a cue outside it"; else no "M3: ${M3:0:300} / ${M3b:0:300}"; fi
M4="$( krun '--for=terminal foo must be the last filter in a chain error' | lit )"
if has "$M4" 's="must be the last filter in a chain" shape="message"' && has "$M4" 'frag="1"' && has "$M4" 'in="chain"'; then ok "M4 [P] no whole hit: the longest end-anchored fragment, frag=1 says so"; else no "M4: ${M4:0:500}"; fi
for near in 'Invalid user settings file' 'bad state error' 'Stale cache entry found error' 'Only a test message here error' 'why does retry fail error' '`no outer cue message here`' 'the `no outer cue message here` text' 'Zzq yyx wwv uut error' 'alpha if beta error' 'foo(x) bar baz error' 'Invalid user settings file errorHandler' 'Invalid user settings file terror'; do
    N="$( krun "--for=$near" )"
    if ! has "$N" '<lit ' && [ "$N" = "$( koff "--for=$near" )" ]; then ok "M5 [G] near miss, no <lit and byte-identical: $near"
    else no "M5 near miss fired: $near: $( lit <<<"$N" | cut -c1-300 )"; fi
done
# ── Q (lane LITERAL-ANCHOR fix round 1; [P] arms are RED on a4ac4941): the review's C1-C5 and the mid-sentence cue; fixture built at runtime ──
QF="$TMP/qfix"; mkdir -p "$QF/app" "$QF/pkg"
python3 -I -c 'import sys
d=sys.argv[1]
for i in range(9):
    open(d+"/app/r%d.ts"%i,"w").write("export function rd%d(c: any) {\n  return c.getValue(\x27svc.retry.limit\x27);\n}\n"%i)
for i in range(3):
    open(d+"/app/a_top%d.ts"%i,"w").write("export const T%d = [\x27svc.retry.limit\x27, %d];\n"%(i,i))
open(d+"/app/reg.ts","w").write("export const R = {\n  \x27svc.retry.limit\x27: { type: \x27number\x27 },\n};\n")
open(d+"/app/long.ts","w").write("export function lng(c: any) {\n  const pad = \""+"x"*230+"\"; return c.getValue(\x27svc.long.line\x27);\n}\n")
open(d+"/app/dev.ts","w").write("export const D = {\n  \x27svc.dev.mode\x27: { type: \x27boolean\x27 },\n};\nexport function dm(c: any) {\n  return c.getValue(\x27svc.dev.mode\x27);\n}\n")
open(d+"/app/field.py","w").write("def is_set(self):\n    return \"the value of this field isn\x27t null\"\n")
open(d+"/app/forms.py","w").write("def clean(self):\n    raise ValueError(\"This field is required.\")\n")
open(d+"/app/net.py","w").write("def pool():\n    return \"cannot connect to servers pool\"\n")
open(d+"/app/tx_a.go","w").write("package app\n\nfunc closedMsg() string {\n\treturn \"the transaction is closed\"\n}\n")
open(d+"/app/tx_b.go","w").write("package app\n\nfunc abortedMsg() string {\n\treturn \"transaction is aborted\"\n}\n")
open(d+"/app/fw.py","w").write("def plan():\n    return \"the value of the plan\"\n")
names=[".terraform.lock.hcl","terraform.tfstate","terraform.tfvars","BUILD.bazel","insiders.vscode.dev","vscode.dev","application.properties",".env.local","CHANGES.rst","api.acme.dev","views.jbuilder"]
open(d+"/app/names.py","w").write("def names():\n    return [" + ", ".join("\""+n+"\"" for n in names)+"]\n")
open(d+"/app/views.jbuilder","w").write("json.x = 1\n")
open(d+"/app/lit.py","w").write("def pick(left, right, other):\n    value = left if right else other\n    return value\n\ndef msg():\n    return \"left if right else other\"\n")
open(d+"/app/cmds.ts","w").write("export function reg(r: any) {\n  r.register(\x27workbench.action.files.save\x27, 1);\n}\n")
open(d+"/app/zed.ts","w").write("export const Z = {\n  \x27zed.autoSave\x27: { type: \x27string\x27 },\n  \x27files.autoSave\x27: { type: \x27string\x27 },\n};\nexport function rz(c: any) {\n  return c.getValue(\x27zed.autoSave\x27) + c.getValue(\x27files.autoSave\x27);\n}\n")
open(d+"/app/widget.py","w").write("def boot():\n    raise RuntimeError(\"the widget failed to start\")\n")
open(d+"/app/us_a.py","w").write("def ua():\n    return \"the user settings are stale\"\n")
open(d+"/app/us_b.py","w").write("def ub():\n    return \"user settings file missing\"\n")
open(d+"/app/nu.py","w").write("def nf():\n    return \"Command not found\"\n")' "$QF"
qrun(){ ( cd "$QF" || exit 1; "$BIN" "$QF" --no-cache "$@" </dev/null 2>/dev/null ); }
qoff(){ ( cd "$QF" || exit 1; RIPWIRE_NO_LITERAL_ANCHOR=1 "$BIN" "$QF" --no-cache "$@" </dev/null 2>/dev/null ); }
rowsOf(){ python3 -I -c 'import sys,re;print("\n".join(m.group(0) for m in re.finditer(r"<ls [^>]*>.*?</ls>",sys.stdin.read(),re.S)))'; }
# C1: nine in-function readers and one top-level quoted registration: the registration survives the 8-row cap
Q1="$( qrun '--for=svc.retry.limit setting' | lit )"
if has "$Q1" 's="svc.retry.limit" shape="dotted"' && has "$Q1" '<ls p="app/reg.ts" l="2" k="string"' && has "$Q1" 'shown="8"' && has "$Q1" 'capped="1"' \
   && [ "$( grep -o '<ls ' <<<"$Q1" | wc -l | tr -d ' ' )" = "8" ]; then
    ok "Q1 [P] 9 readers, 3 top-level quoted mentions that sort first and 1 property-key registration: the registration keeps a row slot (8 rows, capped=1 still disclosed)"
else no "Q1 registration cut by the readers: $( grep -o '<ls p="[^"]*" l="[0-9]*"' <<<"$Q1" | tr '\n' ' ' )"; fi
# C1: a row whose key sits past byte 200 is cut around the key
Q2="$( qrun '--for=svc.long.line setting' | lit | rowsOf )"
if [ -n "$Q2" ] && [ "$( grep -c 'svc.long.line' <<<"$Q2" )" = "$( grep -c '<ls ' <<<"$Q2" )" ]; then ok "Q2 [P] a row whose key sits past byte 200 shows the key (window around it)"
else no "Q2 key hidden by the 200-byte cut: ${Q2:0:500}"; fi
# the same registration-slot guard does not move a key the old order already served: the K2b order stands (checked above)
# C2: a fragment is bounded by word edges and holds two content words; a start-anchored stop-word fragment never wins
Q3="$( qrun '--for=this field is required error' | lit )"
if has "$Q3" 'frag="1"' && has "$Q3" 'p="app/forms.py"' && ! has "$Q3" 'app/field.py'; then ok "Q3 [P] 'this field is' is not found inside 'this field isn't': the real message row (forms.py) prints"
else no "Q3 message fragment: ${Q3:0:500}"; fi
Q4="$( qrun '--for=the transaction is aborted error' | lit )"
if has "$Q4" 's="transaction is aborted"' && has "$Q4" 'in="abortedMsg"' && ! has "$Q4" 'closedMsg'; then ok "Q4 [P] 'the transaction is' (start-anchored, one content word) does not win: transaction is aborted prints abortedMsg"
else no "Q4 try order: ${Q4:0:500}"; fi
for near in 'the value of the error' 'cannot connect to server error'; do
    N="$( qrun "--for=$near" )"
    if ! has "$N" '<lit ' && [ "$N" = "$( qoff "--for=$near" )" ]; then ok "Q5 [P] near miss, no <lit and byte-identical: $near"; else no "Q5 near miss fired: $near: $( lit <<<"$N" | cut -c1-300 )"; fi
done
# C3: file names and hosts are no key (a leading dot; an extension or host suffix; the name of an indexed file)
for near in '.terraform.lock.hcl' 'terraform.tfstate key' 'terraform.tfvars setting' 'BUILD.bazel flag' 'insiders.vscode.dev' 'vscode.dev option' 'application.properties setting' \
            '.env.local setting' 'CHANGES.rst option' 'api.acme.dev' 'views.jbuilder setting'; do
    N="$( qrun "--for=$near" )"
    if ! has "$N" '<lit ' && [ "$N" = "$( qoff "--for=$near" )" ]; then ok "Q6 [P] file name or host, no <lit and byte-identical: $near"; else no "Q6 file or host fired: $near: $( lit <<<"$N" | cut -c1-200 )"; fi
done
Q6="$( qrun '--for=svc.dev.mode setting' | lit )"
if has "$Q6" 's="svc.dev.mode" shape="dotted"'; then ok "Q6b [G] a key with dev in the middle is a key (only the last segment names a host)"; else no "Q6b key with a dev segment refused: ${Q6:0:300}"; fi
# C4: a message never prints a code row; the legend says what rows hold
Q7="$( qrun '--for=left if right else other error' | lit )"
if has "$Q7" 'shape="message"' && has "$Q7" 'k="string" in="msg"' && ! has "$Q7" 'k="code"'; then ok "Q7 [P] a message block holds string rows only (the code line 'left if right else other' is no row)"
else no "Q7 code row on a message: ${Q7:0:500}"; fi
QL="$( qrun '--for=svc.retry.limit setting' )"
if ! has "$QL" 'rows hold the whole key' && has "$QL" 'prefix'; then ok "Q8 [P] the legend no longer claims rows hold the whole key and says a dotted prefix may stand before it"; else no "Q8 legend still says the whole key"; fi
# C5: more than the first literal gets a try, capped and disclosed (try=N)
Q9="$( qrun '--for=workbench.action.files.save files.autoSave setting' | lit )"
if has "$Q9" 's="files.autoSave" shape="dotted"' && ! has "$Q9" 'workbench.action'; then ok "Q9 [P] the key beside the cue leads: files.autoSave, not the command id before it"; else no "Q9 cue-adjacent key: ${Q9:0:400}"; fi
Q10="$( qrun '--for=foo.bar zed.autoSave option' | lit )"
if has "$Q10" 's="zed.autoSave" shape="dotted"'; then ok "Q10 [P] 'foo.bar zed.autoSave option': the key beside the cue"; else no "Q10: ${Q10:0:300}"; fi
Q11="$( qrun '--for=API_KEY zed.autoSave setting' | lit )"; Q12="$( qrun '--for="not in repo words" zed.autoSave setting' | lit )"
if has "$Q11" 's="zed.autoSave" shape="dotted"' && has "$Q11" 'try="2"' && has "$Q12" 's="zed.autoSave" shape="dotted"' && has "$Q12" 'try="2"'; then
    ok "Q11 [P] a CONST word or a quoted span with no site does not hide the key after it; try=\"2\" says it was the second literal"
else no "Q11: ${Q11:0:300} | ${Q12:0:300}"; fi
Q13="$( qrun '--for=foo.bar.baz the widget failed to start error' | lit )"
if has "$Q13" 's="the widget failed to start" shape="message"' && has "$Q13" 'try="2"'; then ok "Q12 [P] a dotted word with no site does not hide the message after it (try=\"2\")"; else no "Q12: ${Q13:0:300}"; fi
Q14="$( qrun '--for=files.autoSave setting' | lit )"
if ! has "$Q14" 'try='; then ok "Q12b [G] a first-literal fire carries no try="; else no "Q12b try= on a first literal"; fi
# mid-sentence cue (ld-nushell-05 shape)
Q15="$( qrun '--for=Command not found error for an unknown word' | lit )"
if has "$Q15" 's="Command not found" shape="message"' && has "$Q15" 'in="nf"'; then ok "Q13 [P] a cue inside the sentence: the words before it are the message"; else no "Q13 mid-sentence cue: ${Q15:0:300}"; fi
for near in 'how to report an error when disk is full' 'the message queue handler' 'files.autoSave' 'files.autoSave config' '"files.autoSave setting"x'; do
    N="$( qrun "--for=$near" )"
    if ! has "$N" '<lit ' && [ "$N" = "$( qoff "--for=$near" )" ]; then ok "Q14 [G] near miss, no <lit and byte-identical: $near"; else no "Q14 near miss fired: $near: $( lit <<<"$N" | cut -c1-200 )"; fi
done
for twin in '`svc.retry.limit` setting' '"svc.retry.limit" setting' 'When a user turns on svc.retry.limit, what code reads that setting'; do
    N="$( qrun "--for=$twin" | lit )"
    if has "$N" 's="svc.retry.limit" shape="dotted"'; then ok "Q15 [G] paraphrase fires: $twin"; else no "Q15 paraphrase misses: $twin: ${N:0:200}"; fi
done
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$( qrun '--for=this field is required error' )" | xmllint --noout - 2>/dev/null && printf '%s' "$( qrun '--for=API_KEY zed.autoSave setting' --legend=full )" | xmllint --noout - 2>/dev/null; then ok "Q16 [P] xmllint well-formed (message fragment, try=)"; else no "Q16 not well-formed"; fi
fi
Q5b="$( qrun '--for=the value of the plan error' | lit )"
if has "$Q5b" 's="the value of the plan" shape="message"'; then ok "Q5b [G] twin: a message with two content words (the value of the plan) still fires"; else no "Q5b twin lost: ${Q5b:0:200}"; fi
Q4b="$( qrun '--for=the user settings file error' | lit )"
if has "$Q4b" 's="user settings file"' && has "$Q4b" 'in="ub"' && ! has "$Q4b" 'in="ua"'; then ok "Q4b [P] tries are ordered by content words: 'user settings file' (3) before 'the user settings' (2)"
else no "Q4b try order by content: ${Q4b:0:400}"; fi
Q17="$( qrun '--for=no.such.one no.such.two no.such.three no.such.four svc.dev.mode' )"
if ! has "$Q17" '<lit ' && has "$Q17" '<lit_capped scanned="4" skipped="1" next="--grep=svc.dev.mode"/>' && has "$Q17" 'not scanned'; then
    ok "Q17 [P] the walk is capped (4 literals scanned): a fifth key is not tried, and the answer says so (lit_capped scanned=4 skipped=1)"
else no "Q17 the candidate walk is not capped or not disclosed: $( grep -o '<lit_capped[^>]*>' <<<"$Q17" ) $( lit <<<"$Q17" | cut -c1-200 )"; fi
Q17b="$( qrun '--for=no.such.one no.such.two no.such.three no.such.four svc.dev.mode' | python3 -I -c 'import sys,re;s=sys.stdin.read();s=re.sub(r"<!-- ripwire for lit:.*?-->","",s,flags=re.S);print(re.sub(r"<lit_capped[^>]*/>","",s),end="")' )"
if [ "$Q17b" = "$( qoff '--for=no.such.one no.such.two no.such.three no.such.four svc.dev.mode' )" ]; then ok "Q17b [G] prefix identity: minus the disclosure the answer equals RIPWIRE_NO_LITERAL_ANCHOR=1"; else no "Q17b the ordinary answer moved"; fi
Q17c="$( qrun '--for=no.such.one no.such.two no.such.three svc.dev.mode' )"
if ! has "$Q17c" 'lit_capped'; then ok "Q17c [G] a fourth key within the cap, nothing skipped: no disclosure"; else no "Q17c disclosure without a cap"; fi
# CR pre-pass 44, card C2: the capped note is outside est_tokens like <lit> and its own legend says so
if has "$Q17" 'this note is not in est_tokens'; then ok "Q17d [P] the lit_capped legend says it is not in est_tokens"; else no "Q17d lit_capped legend silent on est_tokens: $( grep -o '<!-- ripwire for lit: lit_capped[^>]*>' <<<"$Q17" | cut -c1-300 )"; fi
# ── R (lane LITERAL-ANCHOR fix round 2; [P] arms are RED on c6aa775f): F1 escape/printf edges, F2 content floor, F4 file table, F5 legend, F6 cap ──
RF="$TMP/rfix"; mkdir -p "$RF/app"
python3 -I -c 'import sys
d=sys.argv[1]+"/app/"
w=lambda n,t: open(d+n,"w").write(t)
w("esc1.c","void a(void) {\n  puts(\"\\nDatabase connection refused\\n\");\n}\n")
w("esc2.go","package app\n\nfunc b() string {\n\treturn \"\\tcluster quorum lost\"\n}\n")
w("esc3.c","void c(char *s) {\n  printf(\"%sdisk quota exceeded\", s);\n}\n")
w("esc4.ts","export function wk() {\n  return \x60\\nworker pool drained\x60;\n}\n")
w("esc5.c","void e(void) {\n  puts(\"\\rbuffer overflow detected\");\n  puts(\"\\0nul byte seen\");\n  puts(\"\\aalarm bell stuck\");\n}\n")
w("esc6.c","void f(int n, double x, long j) {\n  printf(\"%dretry budget spent\", n);\n  printf(\"%5.2fmeter reading stale\", x);\n  printf(\"%ldjobs requeued twice\", j);\n}\n")
w("twin1.c","void g(void) {\n  puts(\"\\\\nfoo bar baz\");\n}\n")
w("twin2.c","void h(char *s) {\n  printf(\"%s: xdisk quota gone\", s);\n}\n")
w("kesc.ts","export function ke(c: any) {\n  c.log(\"\\nsvc.esc.limit exceeded\");\n  return cli(\"--svc.esc.flag\") + c.get(\"x-svc.esc.hy\");\n}\n")
w("emp.py","def chk(v):\n    raise ValueError(\"must not be empty\")\n")
w("dir.py","def chd(p):\n    raise OSError(\"not a directory\")\n")
w("ce.go","package app\n\nfunc ce() error {\n\treturn errors.New(\"cannot be empty\")\n}\n")
w("fw.py","def plan():\n    return \"the value of the plan, it is not the one\"\n")
names=["tasks.rake","page.astro","kernel.cu","kernel.cuh","shader.metal","deps.cljc","build.bb","view.phtml","logo.webp","loader.wasm","styles.less","main.vue","main.scala","app.jar","libfoo.so","api.acme.co","api.acme.app","svc.pkg.lua"]
w("names.py","def names():\n    return [" + ", ".join("\""+n+"\"" for n in names)+"]\n")
w("reg.ts","export function rg(r: any) {\n  r.register(\x27envoy.filters.http.lua\x27, 1);\n}\n")
w("other.ts","export function ot(c: any) {\n  return c.get(\x27svc.rf.key\x27);\n}\n")' "$RF"
rrun(){ ( cd "$RF" || exit 1; "$BIN" "$RF" --no-cache "$@" </dev/null 2>/dev/null ); }
roff(){ ( cd "$RF" || exit 1; RIPWIRE_NO_LITERAL_ANCHOR=1 "$BIN" "$RF" --no-cache "$@" </dev/null 2>/dev/null ); }
# F1: a word byte that is the letter of an escape (\n \t \r \0 \a) or of a printf verb (%s %d %5.2f %ld) right before the message is an edge
for m in 'Database connection refused' 'cluster quorum lost' 'disk quota exceeded' 'worker pool drained' 'buffer overflow detected' 'nul byte seen' 'alarm bell stuck' \
         'retry budget spent' 'meter reading stale' 'jobs requeued twice'; do
    R="$( rrun "--for=$m error" | lit )"
    if has "$R" "s=\"$m\" shape=\"message\"" && ! has "$R" 'frag=' && ! has "$R" 'longer=' && has "$R" 'k="string"'; then ok "R1 [P] escape/printf letter before the message is an edge, the whole text prints: $m"
    else no "R1 escape-led message lost: $m: ${R:0:300}"; fi
done
for near in 'foo bar baz error' 'disk quota gone error'; do
    N="$( rrun "--for=$near" )"
    if ! has "$N" '<lit ' && [ "$N" = "$( roff "--for=$near" )" ]; then ok "R1b [G] a real letter before the hit (even backslash run; a word) stays inside a longer word: $near"
    else no "R1b fired: $near: $( lit <<<"$N" | cut -c1-200 )"; fi
done
for k in svc.esc.limit svc.esc.flag; do
    R="$( rrun "--for=$k setting" | lit )"
    if has "$R" "s=\"$k\" shape=\"dotted\"" && ! has "$R" 'longer=' && has "$R" 'p="app/kesc.ts"'; then ok "R1c [P] a key after an escape letter or a double hyphen is an edge: $k"; else no "R1c key after an escape/dashes lost: $k: ${R:0:300}"; fi
done
R="$( rrun '--for=svc.esc.hy setting' )"
if ! has "$R" '<lit ' && [ "$R" = "$( roff '--for=svc.esc.hy setting' )" ]; then ok "R1d [G] x-svc.esc.hy (a hyphenated longer name) stays inside a longer name"; else no "R1d hyphenated name fired"; fi
# F2: the floor drops a fragment, not the whole text; a whole text with one content word passes when it ends in it
for m in 'must not be empty' 'not a directory' 'cannot be empty'; do
    R="$( rrun "--for=$m error" | lit )"
    if has "$R" "s=\"$m\" shape=\"message\"" && ! has "$R" 'frag='; then ok "R2 [P] a whole one-content-word message ending in its content word prints: $m"; else no "R2 whole message dropped by the floor: $m: ${R:0:300}"; fi
done
for near in 'the value of the error' 'it is not the error'; do
    N="$( rrun "--for=$near" )"
    if ! has "$N" '<lit ' && [ "$N" = "$( roff "--for=$near" )" ]; then ok "R2b [G] a whole text ending in a function word stays out: $near"; else no "R2b fired: $near: $( lit <<<"$N" | cut -c1-200 )"; fi
done
# F4: the file/host refusal reads kLintExtRows (every indexed language's extension) and the asset table; a 4+ segment key is not a file
for f in tasks.rake page.astro kernel.cu kernel.cuh shader.metal deps.cljc build.bb view.phtml logo.webp loader.wasm styles.less main.vue main.scala app.jar libfoo.so api.acme.co api.acme.app svc.pkg.lua; do
    N="$( rrun "--for=$f setting" )"
    if ! has "$N" '<lit ' && [ "$N" = "$( roff "--for=$f setting" )" ]; then ok "R3 [P] file or host, no <lit and byte-identical: $f"; else no "R3 file or host fired: $f: $( lit <<<"$N" | cut -c1-200 )"; fi
done
R="$( rrun '--for=envoy.filters.http.lua setting' | lit )"
if has "$R" 's="envoy.filters.http.lua" shape="dotted"' && has "$R" 'p="app/reg.ts"'; then ok "R3b [P] a 4-segment key ending in a language extension (envoy.filters.http.lua) is a key"; else no "R3b envoy-style key refused: ${R:0:300}"; fi
R="$( rrun '--for=svc.rf.key tasks.rake setting' | lit )"
if has "$R" 's="svc.rf.key"' && ! has "$R" 'try='; then ok "R3c [P] try= counts only literals the task names as keys: tasks.rake is no literal, so svc.rf.key is the first"; else no "R3c try= after a refused file: ${R:0:300}"; fi
# F5: the legend clauses say what is printed
R="$( rrun '--for=svc.rf.key setting' )"
if ! has "$R" 'the earlier ones have no source site' && ! has "$R" 'two row slots kept for a quoted site outside any function' && has "$R" 'were not scanned' && has "$R" 'C #define'; then
    ok "R4 [P] legend: try= says the earlier literals had no site or were not scanned; the slot clause names its limits"; else no "R4 legend clauses still overstate: $( grep -o 'try=N[^.]*' <<<"$R" | head -1 )"; fi
# ── X1-X3 ──
if [ "$A" = "$( run --for=APPTOOL_RENDER_MODE )" ]; then ok "X1 deterministic"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "X2 xmllint well-formed"; else no "X2 not well-formed"; fi
else ok "X2 SKIP: xmllint not installed"; fi
C="$( python3 -I -c 'import sys,re;m=re.search(r"<!-- ripwire for lit:(.*?)-->",sys.stdin.read(),re.S);print(m.group(1) if m else "MISSING")' <<<"$A" )"
if [ "$C" != "MISSING" ] && ! has "$C" '--'; then ok "X3 the lit legend comment holds no --"; else no "X3 legend comment missing or holds --"; fi

# ── Y1 (train 44): the changelog text states the shapes and the literal caps as the code has them. The numbers are read from the constants, so a
# moved cap fails here. The fragment folds into CHANGELOG.md at a release, so both are read (rc of the read checked: a missing file set is a FAIL). ──
Y_TXT="$( cat "$ROOT"/changelog.d/*.md "$ROOT"/CHANGELOG.md 2>/dev/null )"
Y_SRC="$ROOT/src/forliteral.h"
y_cap(){ sed -n "s/^inline constexpr std::size_t $1 *= *\([0-9][0-9]*\);.*/\1/p" "$Y_SRC"; }
Y_CAND="$( y_cap kForLiteralCandidates )"; Y_TRIES="$( y_cap kForLiteralMessageTries )"; Y_SLOTS="$( y_cap kForLiteralRegistrationRows )"; Y_SEG="$( y_cap kForLiteralFileMaxSegments )"
if [ -z "$Y_TXT" ] || [ -z "$Y_CAND" ] || [ -z "$Y_TRIES" ] || [ -z "$Y_SLOTS" ] || [ -z "$Y_SEG" ]; then
    no "Y1 could not read the changelog text or a cap constant (cand=$Y_CAND tries=$Y_TRIES slots=$Y_SLOTS seg=$Y_SEG)"
elif has "$Y_TXT" 'shape="dotted"' && has "$Y_TXT" 'shape="message"' && has "$Y_TXT" '<lit_capped scanned= skipped= next=>' \
     && has "$Y_TXT" "literal caps: $Y_CAND scans of a quoted span, CONST word or dotted key" && has "$Y_TXT" "$Y_TRIES scans for a message" \
     && has "$Y_TXT" "$Y_SLOTS row slots kept" && has "$Y_TXT" "$Y_SEG or more segments"; then
    ok "Y1 changelog names shape=dotted, shape=message, <lit_capped> and the caps ($Y_CAND, $Y_TRIES, $Y_SLOTS, $Y_SEG) as src/forliteral.h has them"
else
    no "Y1 the changelog text does not state the shapes, the disclosure or the caps (cand=$Y_CAND tries=$Y_TRIES slots=$Y_SLOTS seg=$Y_SEG)"
fi

# ── Z (CR 5725024918, thread 4433389581; [P] RED on 44c4c1ba): a CONST word repeated in the task is one candidate, one scan, one slot ──
ZF="$TMP/zfix"; mkdir -p "$ZF/app"
printf 'export const SVC_REAL_CONST = 7;\nexport function zf() { return SVC_REAL_CONST + 1; }\n' > "$ZF/app/c.ts"
Z1="$( cd "$ZF" || exit 1; "$BIN" "$ZF" --no-cache '--for=where is NO_SUCH_AAAA and NO_SUCH_AAAA and NO_SUCH_AAAA and NO_SUCH_AAAA and SVC_REAL_CONST used' </dev/null 2>/dev/null )"
if has "$Z1" 's="SVC_REAL_CONST"' && ! has "$Z1" 'lit_capped'; then ok "Z1 [P] four repeats of one CONST word cost one candidate slot: the fifth word is tried and nothing is reported skipped"
else no "Z1 repeated CONST words took the candidate slots: $( grep -o '<lit_capped[^>]*>' <<<"$Z1" ) $( lit <<<"$Z1" | cut -c1-160 )"; fi

# ── T (lane TABLE-CONST V2; [P] RED on base b8c31789, fixture built at runtime, never under a .gitignored path): shape="table", the last try of <lit>:
# a registration, table, compile-time or add-a-new word, or default/handler when a table row exists, reaches the sites of the identifier the task names. ──
TF="$TMP/tfix"; mkdir -p "$TF/internal/lang" "$TF/internal/funcs" "$TF/crates/cmd" "$TF/src/settings" "$TF/internal/lang_test" "$TF/src/gates"
cat > "$TF/internal/lang/functions.go" <<'GO'
package lang

func (s *Scope) Functions() map[string]Function {
	baseFunctions := map[string]Function{
		"abspath":  funcs.AbsPathFunc,
		"basename": funcs.BaseNameFunc,
		"concat":   funcs.ConcatFunc,
	}
	return baseFunctions
}
GO
cat > "$TF/internal/funcs/path.go" <<'GO'
package funcs

// the tablecomment_word stands in this comment only
var AbsPathFunc = Function{}
var BaseNameFunc = Function{}
var ConcatFunc = Function{}

func helper_user() int {
	x := unlisted_value + 1
	return x
}
func unlisted_value() int { return 1 }
GO
cat > "$TF/crates/cmd/ctx.rs" <<'RS'
use crate::Commands;
use other::{
    ImportedOnly,
    AnotherImport,
};
pub fn add_context() {
    bind_command! {
        Each,
        Filter,
        Map,
    };
}
pub struct Each;
pub struct Filter;
pub struct Map;
pub struct ImportedOnly;
pub struct AnotherImport;
impl_body!(HashJoin(HashJoinNode) => HashJoinBuilder);
pub struct HashJoinNode;
pub struct HashJoinBuilder;
for_all_params! {
    { barrier_interval_ms, u32, Some(1000_u32) },
    { checkpoint_frequency, u64, Some(1_u64) },
}
pub fn barrier_interval_ms() -> u32 { 1 }
pub fn checkpoint_frequency() -> u64 { 1 }
RS
cat > "$TF/src/settings/Settings.cpp" <<'CC'
#define COMMON_SETTINGS(DECLARE) \
    DECLARE(MaxThreads, max_threads, 0, R"(
The maximum number of threads.
)", 0) \
    DECLARE(MaxBlock, max_block_size, 65536, "block") \
    DECLARE(MinBlock, min_block_size, 1, "min")
int max_threads() { return 1; }
int max_block_size() { return 1; }
CC
cat > "$TF/src/gates/kube_features.go" <<'GO'
package gates

const FeatureAlpha = "FeatureAlpha"
const FeatureBeta = "FeatureBeta"

var defaultGates = map[string]Spec{
	FeatureAlpha: {
		Default: true,
	},
	FeatureBeta: {
		Default: false,
	},
}
GO
cat > "$TF/internal/lang_test/only_test.go" <<'GO'
package lang_test

func test_only_anchor() {}
var _ = test_only_anchor
GO
cat > "$TF/internal/funcs/plain.go" <<'GO'
package funcs

func dispatch_one() { dispatch_two() }
func dispatch_two() {}
GO
cat > "$TF/internal/funcs/keys.go" <<'GO'
package funcs

var _ = "svc.retry.limit"
var _ = "other.keyed_word"
func keyed_word() {}
GO
tr1(){ ( cd "$TF" || exit 1; "$BIN" "$TF" --no-cache "$@" </dev/null 2>/dev/null ); }
trf(){ ( cd "$TF" || exit 1; RIPWIRE_NO_LITERAL_ANCHOR=1 "$BIN" "$TF" --no-cache "$@" </dev/null 2>/dev/null ); }
lits(){ python3 -I -c 'import sys,re;s=sys.stdin.read();print("".join(re.findall(r"<lit [^>]*>.*?</lit>",s,re.S)))'; }

# T1 [P] a backticked sibling with an add-a-new word (`abspath`): the table row first, tbl= the opener, lines= the members after it
A="$( tr1 '--for=add a new function; use `abspath` as the model' )"; L="$( lits <<<"$A" )"
if has "$L" 's="abspath" shape="table"' && has "$L" 'p="internal/lang/functions.go" l="5"' && has "$L" 'tbl="baseFunctions := map[string]Function{"' && has "$L" 'lines="5-7"' && has "$L" 'funcs.BaseNameFunc'; then
    ok "T1 add-a-new + backticked sibling: the table row, its opener and the members after it"
else no "T1 table row wrong: ${L:0:500}"; fi
if has "$A" 'ripwire for lit: shape=table'; then ok "T1b the shape's legend clause rides"; else no "T1b no table legend"; fi
# T2 [P] a registration word + an identifier-shaped symbol word, no backticks; the Rust list row
A="$( tr1 '--for=where is HashJoinNode registered' )"; L="$( lits <<<"$A" )"
if has "$L" 's="HashJoinNode" shape="table"' && has "$L" 'tbl="item"' && has "$L" 'impl_body!(HashJoin(HashJoinNode)'; then ok "T2 macro row at top level: tbl=item, no sibling needed"
else no "T2 macro row wrong: ${L:0:400}"; fi
# T3 [P] default on a macro-table row: ClickHouse DECLARE shape
A="$( tr1 '--for=max_threads default' )"; L="$( lits <<<"$A" )"
if has "$L" 'shape="table"' && has "$L" 'DECLARE(MaxThreads, max_threads' && has "$L" 'tbl="#define COMMON_SETTINGS(DECLARE) \"'; then ok "T3 default + X-macro row over a raw-string description, tbl= the #define"; else no "T3 X-macro row wrong: ${L:0:400}"; fi
# T4 [P] default on a map table row, the entry's lines follow
A="$( tr1 '--for=FeatureAlpha feature gate default' )"; L="$( lits <<<"$A" )"
if has "$L" 'FeatureAlpha: {' && has "$L" 'Default: true' && has "$L" 'tbl="var defaultGates = map[string]Spec{"'; then ok "T4 default + map table row with its value"
else no "T4 map row wrong: ${L:0:400}"; fi
# T4b [P] a registry outside any function ranks before a table row inside one (a struct literal in a reader) and before path order
cat > "$TF/src/gates/a_reader.go" <<'GO'
package gates

func readers() []Opts {
	return []Opts{
		{Alpha: 1},
	}
}
func build() Opts {
	o := Opts{
		FeatureAlpha: true,
		Other:        false,
	}
	return o
}
GO
A="$( tr1 '--for=FeatureAlpha feature gate default' )"; L="$( lits <<<"$A" )"
FIRST="$( grep -o '<ls p="[^"]*"' <<<"$L" | sed -n 1p )"
if [ "$FIRST" = '<ls p="src/gates/kube_features.go"' ] && has "$L" 'a_reader.go'; then ok "T4b the top-level registry row first, the reader's literal after it"; else no "T4b order: $FIRST"; fi
# T4c [P] a call chain in backticks anchors on its last link
A="$( tr1 '--for=where does the default of `self.params.load().checkpoint_frequency()` live' )"; L="$( lits <<<"$A" )"
if has "$L" 's="checkpoint_frequency" shape="table"'; then ok "T4c the last link of a backticked call chain"; else no "T4c chain: ${L:0:200}"; fi
# T5 [P] Rust brace rows in a macro table
A="$( tr1 '--for=barrier_interval_ms default' )"; L="$( lits <<<"$A" )"
if has "$L" '{ barrier_interval_ms, u32' && has "$L" 'tbl="for_all_params! {"'; then ok "T5 a Rust macro table row"; else no "T5 brace row wrong: ${L:0:400}"; fi
# T6 [P] member list row beats nothing else; backticked `Each`, case kept
A="$( tr1 '--for=add a new command like `Each`' )"; L="$( lits <<<"$A" )"
if has "$L" 's="Each" shape="table"' && has "$L" 'tbl="bind_command! {"'; then ok "T6 member-list row"; else no "T6 member row wrong: ${L:0:400}"; fi
# T7 [P] exemplar: a plain word after like, an index symbol
A="$( tr1 '--for=add a new filter like concat' )"
if has "$( lits <<<"$A" )" 'funcs.ConcatFunc' || has "$A" 's="concat"'; then no "T7a concat is no symbol: no anchor (near miss, not in index)"; else ok "T7a a plain word that is no index symbol does not anchor"; fi
A="$( tr1 '--for=add a new struct like Filter' )"; L="$( lits <<<"$A" )"
if has "$L" 's="Filter" shape="table"'; then ok "T7b a plain word after like that the index holds anchors"; else no "T7b no sibling: ${L:0:300}"; fi
# Near misses [G]
nomiss(){ local T="$1" W="$2"; local X; X="$( tr1 "--for=$1" )"; if ! has "$( lits <<<"$X" )" 'shape="table"' && [ "$X" = "$( trf "--for=$1" )" ]; then ok "$W"; else no "$W: $( lits <<<"$X" | cut -c1-240 )"; fi; }
nomiss 'where is HashJoinNode used' 'T8 no cue: an identifier alone, no block, byte-identical to the switch off'
nomiss 'register the widget' 'T9 a cue with a stop word and a plain word: no anchor'
nomiss 'add a new argument to HashJoinNode' 'T9b the word after to in an add-a-new task is the target, no anchor'
nomiss 'register no_such_symbol_here' 'T10 an identifier-shaped word that is no symbol: no anchor'
nomiss 'register `no_such_site_here`' 'T11 a backticked identifier with no site: no block, no claim'
nomiss 'register `test_only_anchor`' 'T12 a test-only site: no block (counts alone anchor nothing)'
nomiss 'register `tablecomment_word`' 'T13 a word in a comment only: no row, no block'
nomiss 'dispatch_one default' 'T14 default without a table row: no block'
nomiss 'register `internal/lang/functions.go`' 'T15 a backticked path is no anchor'
A="$( tr1 '--for=register self.keyed_word table' )"
if ! has "$( lits <<<"$A" )" 's="self.keyed_word"'; then ok "T15b a self. chain does not anchor"; else no "T15b self. chain anchored"; fi
# T16 [G] a dotted key beside a cue stays the dotted shape, one element, no table
A="$( tr1 '--for=svc.retry.limit setting table keyed_word' )"; L="$( lits <<<"$A" )"
if has "$L" 'shape="dotted"' && ! has "$L" 'shape="table"'; then ok "T16 a dotted key beside a cue stays dotted"; else no "T16 shape wrong: ${L:0:300}"; fi
# T17 [P] an import list is no table row, but the anchor still has its site rows when the cue is a registration word
A="$( tr1 '--for=ImportedOnly default' )"
if ! has "$( lits <<<"$A" )" 'shape="table"'; then ok "T17 an import list row is no table row"; else no "T17 import read as a table: $( lits <<<"$A" | cut -c1-300 )"; fi
# T18 [P] word edges: a hit inside a longer word is longer=, never a row
printf 'var eachWord = 1\nvar _ = "Eachly"\n' > "$TF/internal/funcs/w.go"
A="$( tr1 '--for=add a new command like `Each`' )"; L="$( lits <<<"$A" )"
if has "$L" 'longer=' && ! has "$L" 'Eachly'; then ok "T18 a hit inside a longer word is counted, not a row"; else no "T18 word edge: ${L:0:300}"; fi
# T19 [G] prefix identity and determinism and well-formed on a table answer
A="$( tr1 '--for=add a new function; use `abspath` as the model' )"; B="$( tr1 '--for=add a new function; use `abspath` as the model' )"; OFF="$( trf '--for=add a new function; use `abspath` as the model' )"
S="$( python3 -I -c 'import sys,re;s=sys.stdin.read();s=re.sub(r"<!-- ripwire for lit[^>]*?-->","",s,flags=re.S);s=re.sub(r"<lit [^>]*>.*?</lit>","",s,flags=re.S);print(s,end="")' <<<"$A" )"
if [ "$S" = "$OFF" ]; then ok "T19a the answer minus the legend and <lit> is the switch-off answer"; else no "T19a prefix moved"; fi
if [ "$A" = "$B" ]; then ok "T19b determinism"; else no "T19b two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "T19c xmllint well-formed"; else no "T19c not well-formed"; fi; else ok "T19c SKIP: xmllint not installed"; fi
# T20 [P] several anchors: one <lit> each, the legend once
A="$( tr1 '--for=register `abspath` and `basename`' )"
n="$( grep -o '<lit s=' <<<"$A" | wc -l | tr -d ' ' )"; m="$( grep -o 'ripwire for lit: shape=table' <<<"$A" | wc -l | tr -d ' ' )"
if [ "$n" = "2" ] && [ "$m" = "1" ]; then ok "T20 two anchors: two elements, one legend"; else no "T20 n=$n legend=$m"; fi
# T21 [P] at most three anchors kept: the fourth is not scanned
A="$( tr1 '--for=register `abspath` `basename` `concat` `Each`' )"
if [ "$( grep -o '<lit s=' <<<"$A" | wc -l | tr -d ' ' )" = "3" ] && ! has "$A" 's="Each"'; then ok "T21 the anchor cap"; else no "T21 anchor cap: $( grep -o '<lit s="[^"]*"' <<<"$A" | tr '\n' ' ' )"; fi
# T22 [P] the byte cap: a row boundary, capped=1, next=, a later anchor counted in <lit_capped>; rows past the row limit disclose too
BF="$TMP/bfix"; mkdir -p "$BF/a"
python3 -I - "$BF/a" <<'PY'
import sys
d=sys.argv[1]
pad="x"*150
for f in range(40):
    with open(f"{d}/t{f}.go","w") as o:
        o.write("package a\n\nvar T%d = map[string]int{\n"%f)
        for i in range(30):
            o.write('\t"%s_%d": cap_anchor_one + cap_anchor_two, // %s\n'%(pad,i,""))
        o.write("}\n")
open(f"{d}/s.go","w").write("package a\n\nfunc cap_anchor_one() {}\nfunc cap_anchor_two() {}\nfunc cap_anchor_three() {}\nvar _ = cap_anchor_three\n")
PY
A="$( cd "$BF" || exit 1; "$BIN" "$BF" --no-cache '--for=register `cap_anchor_one` `cap_anchor_two` `cap_anchor_three`' </dev/null 2>/dev/null )"
CAPJ="$( python3 -I -c '
import sys,re
s=sys.stdin.read()
heads=re.findall(r"<lit s=\"([^\"]*)\"[^>]*?shown=\"(\d+)\"[^>]*?( capped=\"1\")?[^>]*?bytes=\"(\d+)\"",s)
tot=sum(int(h[3]) for h in heads)
for m in re.finditer(r"<lit [^>]*>(.*?)</lit>",s,re.S):
    body=m.group(1)
    assert body.count("<ls ")==body.count("</ls>")
print(len(heads),tot,sum(1 for h in heads if "capped" in h[2]))
' <<<"$A" )"
set -- $CAPJ
if [ "${1:-0}" -ge 1 ] && [ "${2:-99999}" -le 40000 ] && [ "${3:-0}" -ge 1 ] && has "$A" 'next="--grep=cap_anchor_one"'; then ok "T22 the row limit discloses ($2 B over $1 elements), capped=1, next="
else no "T22 byte cap: $CAPJ"; fi
if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "T22b the capped answer is well-formed"; else no "T22b not well-formed"; fi
# T22c-e: paths long enough that two elements spend the 40 KB, and the third anchor has sites but no room
BL="$TMP/blong"; mkdir -p "$BL"
python3 -I - "$BL" <<'PY'
import os,sys
d=sys.argv[1]+"/"+"d"*90+"/"+"e"*90+"/"+"f"*90; os.makedirs(d)
for f in range(40):
    with open(f"{d}/t{f}.go","w") as o:
        o.write("package a\n\nvar T%d = map[string]int{\n"%f)
        for i in range(30):
            o.write('\t"%s_%d": cap_anchor_one + cap_anchor_two + cap_anchor_three,\n'%("x"*150,i))
        o.write("}\n")
open(f"{d}/s.go","w").write("package a\n\nfunc cap_anchor_one() {}\nfunc cap_anchor_two() {}\nfunc cap_anchor_three() {}\n")
PY
A="$( cd "$BL" || exit 1; "$BIN" "$BL" --no-cache '--for=register `cap_anchor_one` `cap_anchor_two` `cap_anchor_three`' </dev/null 2>/dev/null )"
CAPJ="$( python3 -I -c '
import sys,re
s=sys.stdin.read()
h=re.findall(r"<lit s=\"[^\"]*\"[^>]*?shown=\"(\d+)\"[^>]*?bytes=\"(\d+)\"",s)
print(len(h),sum(int(x[1]) for x in h),min(int(x[0]) for x in h))
' <<<"$A" )"
set -- $CAPJ
if [ "${1:-0}" -eq 2 ] && [ "${2:-99999}" -le 40000 ] && [ "${3:-32}" -lt 32 ]; then ok "T22c the byte cap holds ($2 B over $1 elements), the last cut on a row boundary below the row limit"
else no "T22c byte cap: $CAPJ"; fi
if has "$A" '<lit_capped scanned="2" skipped="1"' && has "$A" 'next="--grep=cap_anchor_three"'; then ok "T22d an anchor with sites and no room left is counted by <lit_capped> with next="
else no "T22d later anchor unsaid: $( grep -o '<lit[_a-z]* [^>]*>' <<<"$A" | cut -c1-200 | tr '\n' ' ' )"; fi
if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "T22e the capped answer is well-formed"; else no "T22e not well-formed"; fi

[ "$fail" -eq 0 ] && echo "forliteralcheck: OK" || echo "forliteralcheck: FAILED"
exit "$fail"
