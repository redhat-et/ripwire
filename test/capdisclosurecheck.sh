#!/usr/bin/env bash
# capdisclosurecheck.sh — three CAPS that cut user-visible output must SAY SO in the answer document.
#
# docs/METHODOLOGY.md §9 #4 ("honesty lives in attributes") and #6 ("a ceiling attribute names the ceiling
# ACTUALLY applied") make silence the one option not on the list. Three caps were silent:
#
#   (A) the matched line of a --grep / --verify / MCP-grep hit is cut at kGrepMatchedLineMaxBytes (512 B,
#       src/search.h). A 50 KB minified line and a 512 B source line printed the SAME bytes, and nothing
#       on the row distinguished them. Now the row carries line_bytes="N" — the WHOLE line's byte length —
#       present ONLY when the cut fired, so an untruncated hit still costs zero bytes (the pr_converged
#       shape: silence means not truncated, presence means truncated AND says how much there is).
#   (B) cleanSig's kMaxSig (240 B, src/serialize.h) hard-broke EVERY emitted signature with no marker at
#       all — --pack-signatures, --for's <sigs>, <calls> callee rows, --lego. Now it goes through
#       truncateUtf8WithEllipsis, the tool's ONE truncator, exactly as the three other signature cuts
#       (kForTailSigBytes / kForCapTailSigBytes / the --pack-task tail) already do: a trailing U+2026.
#   (C) a DEFAULT --for enforces kForPayloadBudgetBytes (7500 B, src/serialize.h) and named NO ceiling:
#       budget_tokens= rode only an EXPLICIT --token-budget, so the bundle disclosed THAT it had been cut
#       (<sigs shown= total= capped="1">) but never WHICH ceiling did it. Now the <sigs> element that was
#       cut names the ceiling that cut it on its root, budget_bytes="7500", in the unit that ceiling is
#       actually spelled in — BYTES. It is not re-expressed as tokens: the constant the ladder compares
#       against is a byte count, and the token rate the root's est_tokens uses (2.50 B/tok) is not the
#       conservative rate a ceiling is sized with, so a token spelling would name a number the tool never
#       applied. Default regime only: an explicit --token-budget already names the caller's own ceiling
#       as budget_tokens=, so exactly one of the two rides a trimmed bundle.
#
# Every arm asserts THREE things, because a disclosure gate that only greps for its own attribute is
# decoration:
#   1. CROSSING — the fixture really does cross the cap (the emitted payload is strictly shorter than the
#      source it came from, or the element really is capped). A fixture sized just past a byte cap can
#      still produce identical visible output, and then the arm proves nothing.
#   2. DISCLOSURE — the crossed answer carries the marker.
#   3. SILENCE — the SAME verb on an UNCROSSED fixture does NOT carry it (G4: an attribute that rides
#      every answer is a tax; the house precedent is pr_converged, which has no pr_converged="1").
#
# MUTATION CONTROL: each arm's assertion 2 is exactly what a revert of its fix removes, and assertion 1
# proves the fixture still reaches the code being reverted. Run this gate against a binary built from the
# parent commit (RIPWIRE_BIN=... test/capdisclosurecheck.sh) and every arm's assertion 2 must FAIL while
# every assertion 1 still passes — that is the red run this gate was written from.
#
# Usage:
#   test/capdisclosurecheck.sh
#   RIPWIRE_BIN=build_base/ripwire test/capdisclosurecheck.sh     # the RED run
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "capdisclosurecheck: python3 required"; exit 2; }

echo "capdisclosurecheck: BIN=$BIN"

# ---------------------------------------------------------------------------------------------------
# fixtures. Written by python3 rather than a heredoc so the CROSSING sizes are computed, not eyeballed:
# a fixture that lands one byte short of a cap is a green arm that asserts nothing.
# ---------------------------------------------------------------------------------------------------
FIX="$TMP/fix"
mkdir -p "$FIX"
python3 - "$FIX" <<'PY'
import os, sys
d = sys.argv[1]
# (A) one line far past the 512 B matched-line cap, and one comfortably under it, both holding the needle.
wide   = "int wideOne( void ) { /* NEEDLEZQ " + ("x" * 2000) + " */ return 1; }"
narrow = "int narrowOne( void ) { /* NEEDLEZQ short */ return 2; }"
assert len(wide) > 512 and len(narrow) < 512
open(os.path.join(d, "grep.c"), "w").write(wide + "\n" + narrow + "\n")
# (B) one signature far past the 240 B cleanSig cap, and one comfortably under it.
params = ", ".join("const unsigned long long int parameterNumber%02d" % i for i in range(12))
wideSig = "int wideSignatureFunction( %s )" % params
assert len(wideSig) > 240
open(os.path.join(d, "sig.c"), "w").write(
    wideSig + "\n{\n    return 0;\n}\n"
    "int narrowSignatureFunction( int a, int b )\n{\n    return a + b;\n}\n")
PY
WIDE_LINE_BYTES="$( head -1 "$FIX/grep.c" | LC_ALL=C awk '{ print length( $0 ) }' )"

# A corpus small enough that --for CANNOT saturate kForPayloadBudgetBytes — the only way to test arm (C)'s
# silence half. Two symbols, no doc comments: the whole bundle is a few hundred bytes.
TINY="$TMP/tiny"
mkdir -p "$TINY"
cat > "$TINY/a.c" <<'EOF'
int leafOne( int x ) { return x + 1; }
int rootOne( int x ) { return leafOne( x ) + 1; }
EOF

BIG="$ROOT/src"
run(){ "$BIN" "$@" 2>/dev/null; }
mcp_text() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message","") if "error" in r else r["result"]["content"][0]["text"])
'
}

# ===================================================================================================
# (A) the matched line: --grep, --verify and the MCP grep verb
# ===================================================================================================
echo "-- (A) matched-line cap (kGrepMatchedLineMaxBytes)"
run "$FIX" --grep=NEEDLEZQ > "$TMP/a_grep.xml"
python3 - "$TMP/a_grep.xml" "$WIDE_LINE_BYTES" <<'PY' > "$TMP/a_grep.res" 2>&1
import re, sys
doc = open(sys.argv[1], encoding="utf-8", errors="replace").read()
want = int(sys.argv[2])
rows = re.findall(r'<hit l="(\d+)"([^>]*)><!\[CDATA\[(.*?)\]\]></hit>', doc, re.S)
by = { int(l): (attrs, text) for l, attrs, text in rows }
if 1 not in by or 2 not in by:
    print("PROBE_BROKEN rows=%s" % sorted(by)); raise SystemExit
wattrs, wtext = by[1]
nattrs, ntext = by[2]
# 1. CROSSING — the printed text really is shorter than the line on disk.
print("A1 %s crossing: printed=%d disk=%d" % ("OK" if len(wtext.encode()) < want else "NO", len(wtext.encode()), want))
# 2. DISCLOSURE — the cut row names the whole line's size.
m = re.search(r'\bline_bytes="(\d+)"', wattrs)
print("A2 %s disclosure: line_bytes=%s (want %d)" % ("OK" if m and int(m.group(1)) == want else "NO", m.group(1) if m else "<absent>", want))
# 3. SILENCE — the uncut row pays nothing.
print("A3 %s silence: uncut row attrs=%r" % ("OK" if "line_bytes" not in nattrs else "NO", nattrs.strip()))
PY
while read -r tag verdict rest; do
    [ "$verdict" = OK ] && ok "$tag $rest" || no "$tag $rest"
done < <( grep -E '^A[0-9] ' "$TMP/a_grep.res" )
grep -q PROBE_BROKEN "$TMP/a_grep.res" && no "(A) --grep probe broken: $( cat "$TMP/a_grep.res" )"

# --verify serves the same matched line through <m> — the same cut, so the same disclosure.
# the --verify claim language is CLOSED (SHAPE(ARGS)); contains() is the literal-scan shape.
run "$FIX" --verify='contains(grep.c, "NEEDLEZQ")' > "$TMP/a_verify.xml"
if grep -q '<m>' "$TMP/a_verify.xml"; then
    vtext="$( python3 -c '
import re, sys
doc = open(sys.argv[1], encoding="utf-8", errors="replace").read()
rows = re.findall(r"<hit ([^>]*)><m><!\[CDATA\[(.*?)\]\]></m></hit>", doc, re.S)
wide = [ (a, t) for a, t in rows if "grep.c:1" in a ]
print(wide[0][0] if wide else "__NOWIDEROW__")
' "$TMP/a_verify.xml" )"
    case "$vtext" in
        __NOWIDEROW__) no "A4 --verify: no hit row for the >512 B line (probe broken)" ;;
        *line_bytes=\"$WIDE_LINE_BYTES\"*) ok "A4 --verify <m> names line_bytes=$WIDE_LINE_BYTES" ;;
        *) no "A4 --verify <m> does not disclose the cut: $vtext" ;;
    esac
else
    no "A4 --verify emitted no <m> rows (probe broken)"
fi

# The MCP grep verb is the third caller of grepEnrich — but its JSON rows carry file/line/in/parse_degraded
# and NO matched text at all, so this dialect has no matched-line cut to disclose. That is asserted rather
# than assumed: if a future round starts serving the text, this arm fires and says the disclosure is owed
# with it, which is the only way an absence stays a checked fact instead of a memory.
mcp_text '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"'"$FIX"'","pattern":"NEEDLEZQ"}}}' > "$TMP/a_mcp.json"
python3 - "$TMP/a_mcp.json" "$WIDE_LINE_BYTES" <<'PY' > "$TMP/a_mcp.res" 2>&1
import json, sys
raw  = open(sys.argv[1], encoding="utf-8", errors="replace").read()
want = int(sys.argv[2])
if raw.startswith("__ERROR__"):
    print("A5 NO mcp grep errored: %s" % raw.strip()); raise SystemExit
try:
    d = json.loads(raw)
except Exception as e:
    print("A5 NO mcp grep payload not JSON: %s" % e); raise SystemExit
hits = d.get("hits", [])
wide = [ h for h in hits if h.get("line") == 1 ]
if not wide:
    print("A5 NO mcp grep has no line-1 hit (probe broken)"); raise SystemExit
h = wide[0]
carriesText = any( k in h for k in ("text", "line_text", "m", "match", "matched") )
if not carriesText:
    print("A5 OK mcp grep serves no matched line, so it has no cut to disclose (keys=%s)" % sorted(h))
else:
    print("A5 %s mcp grep now serves the matched line and must disclose the cut: line_bytes=%s (want %d)"
          % ("OK" if h.get("line_bytes") == want else "NO", h.get("line_bytes"), want))
PY
while read -r tag verdict rest; do
    [ "$verdict" = OK ] && ok "$tag $rest" || no "$tag $rest"
done < <( grep -E '^A[0-9] ' "$TMP/a_mcp.res" )

# ===================================================================================================
# (B) the signature cap (cleanSig / kMaxSig)
# ===================================================================================================
echo "-- (B) signature cap (kMaxSig)"
run "$FIX" --pack-signatures > "$TMP/b_sigs.xml"
python3 - "$TMP/b_sigs.xml" "$FIX/sig.c" <<'PY' > "$TMP/b_sigs.res" 2>&1
import re, sys, html
doc = open(sys.argv[1], encoding="utf-8", errors="replace").read()
src = open(sys.argv[2], encoding="utf-8").read()
disk = src.split("\n")[0].strip()
# the <d> row's text payload is the cleaned signature
rows = re.findall(r'<d\b[^>]*n="([^"]*)"[^>]*>(.*?)</d>', doc, re.S)
got = {}
for name, body in rows:
    body = re.sub(r"<doc>.*?</doc>", "", body, flags=re.S)
    body = re.sub(r"<[^>]*>", "", body)
    got[name] = html.unescape(body).strip()
if "wideSignatureFunction" not in got or "narrowSignatureFunction" not in got:
    print("PROBE_BROKEN names=%s" % sorted(got)); raise SystemExit
wide, narrow = got["wideSignatureFunction"], got["narrowSignatureFunction"]
# 1. CROSSING — the emitted signature is strictly shorter than the one on disk.
print("B1 %s crossing: emitted=%d disk=%d" % ("OK" if len(wide.encode()) < len(disk.encode()) else "NO", len(wide.encode()), len(disk.encode())))
# 2. DISCLOSURE — the cut signature ends in the tool's one truncation marker.
print("B2 %s disclosure: emitted sig ends %r" % ("OK" if wide.endswith("…") else "NO", wide[-24:]))
# 3. SILENCE — an uncut signature carries no marker.
print("B3 %s silence: uncut sig %r" % ("OK" if "…" not in narrow else "NO", narrow))
PY
while read -r tag verdict rest; do
    [ "$verdict" = OK ] && ok "$tag $rest" || no "$tag $rest"
done < <( grep -E '^B[0-9] ' "$TMP/b_sigs.res" )
grep -q PROBE_BROKEN "$TMP/b_sigs.res" && no "(B) --pack-signatures probe broken: $( cat "$TMP/b_sigs.res" )"

# the same cleanSig serves --for's <sigs> rows: the marker must be there too, not only on the map verb.
#
# The marker is matched through python3 rather than grep, and that is not fussiness. The first cut of this
# arm spelled it `grep -q '\xe2\x80\xa6'`, which passed under an interactive shell and FAILED under
# test/pargates.py's own `bash <gate>` invocation on the same machine and the same file — \x escapes are not
# portable across grep implementations or locales, so the arm was testing the runner, not the tool. Reading
# the bytes in python3 makes it say the same thing everywhere (the gate-shell portability trap).
run "$FIX" --for="wideSignatureFunction" > "$TMP/b_for.xml"
python3 - "$TMP/b_for.xml" <<'PY' > "$TMP/b_for.res" 2>&1
import sys
raw = open(sys.argv[1], "rb").read()
if b"wideSignatureFunction" not in raw:
    print("B4 NO --for did not serve wideSignatureFunction (probe broken)"); raise SystemExit
print("B4 %s --for <sigs> carries the same signature-cut marker"
      % ("OK" if "\u2026".encode() in raw else "NO"))
PY
while read -r tag verdict rest; do
    [ "$verdict" = OK ] && ok "$tag $rest" || no "$tag $rest"
done < <( grep -E '^B[0-9] ' "$TMP/b_for.res" )

# ===================================================================================================
# (C) the DEFAULT --for payload ceiling (kForPayloadBudgetBytes)
#
# WHERE IT RIDES, AND WHY IT IS NOT ON <sigs>. The first cut of this fix put budget_bytes= on the <sigs>
# open tag with the ladder's own per-run share as its value. That is more precise and it is wrong here:
# forbudgetmonotoncheck pins the sig section BYTE-IDENTICAL between the default ceiling and any explicit
# ceiling above it ("a wider ceiling never serves less decisive content"), and a per-run number breaks
# that identity while every served row stays the same. It rides the <ctx> root instead, spliced AFTER the
# sigs render — so the ladder's input is untouched and the sig block is byte-for-byte what it was.
#
# WHICH NUMBER. The default regime applies kForPayloadBudgetBytes verbatim (7500 B), so that is what is
# named; the explicit regime already names the caller's own ceiling as budget_tokens=, so the two are
# EXCLUSIVE — a trimmed bundle names exactly one of them, never both and never neither. That exclusivity
# is asserted below, because it is the whole shape of the fix: the bug was one regime disclosing and the
# other not.
# ===================================================================================================
echo "-- (C) default --for payload ceiling (kForPayloadBudgetBytes)"
FORQ="rank symbols by pagerank"
FORPAYLOAD=7500          # kForPayloadBudgetBytes, src/serialize.h
run "$BIG" --for="$FORQ" > "$TMP/c_default.xml"
SIGSTAG="$( grep -o '<sigs[^>]*>' "$TMP/c_default.xml" | head -1 )"
CTXTAG="$(  grep -o '<ctx[^>]*>'  "$TMP/c_default.xml" | head -1 )"
case "$SIGSTAG" in
    *'capped="1"'*) ok "C1 crossing: the default run really is capped — $SIGSTAG" ;;
    *) no "C1 crossing: the default --for was not capped (probe broken) — ${SIGSTAG:-<no sigs element>}" ;;
esac
case "$CTXTAG" in
    *"budget_bytes=\"$FORPAYLOAD\""*) ok "C2 disclosure: the cut default bundle names budget_bytes=\"$FORPAYLOAD\" on its root" ;;
    *) no "C2 disclosure: a DEFAULT --for cut its bundle and named no ceiling — $CTXTAG" ;;
esac
# the ladder's input must not have moved: the <sigs> block is what it was before the disclosure existed,
# which is the invariant forbudgetmonotoncheck pins and the reason this attribute is spliced late.
case "$SIGSTAG" in
    *budget_bytes*) no "C6 the disclosure leaked into the <sigs> open tag (forbudgetmonotoncheck pins it) — $SIGSTAG" ;;
    *) ok "C6 the <sigs> open tag is untouched by the disclosure — $SIGSTAG" ;;
esac
# the LEGEND must define the attribute where the reader meets it (the legendcoveragecheck contract).
if head -c 20000 "$TMP/c_default.xml" | grep -q 'budget_bytes='; then
    ok "C7 the cut bundle's legend defines budget_bytes="
else
    no "C7 the cut default bundle's legend does not define budget_bytes= (absent attribute, or an attribute with no definition where the reader meets it)"
fi

# the explicit path was ALREADY correct and must stay correct — and must NOT gain a second ceiling.
run "$BIG" --for="$FORQ" --token-budget=3000 > "$TMP/c_explicit.xml"
ECTX="$( grep -o '<ctx[^>]*>' "$TMP/c_explicit.xml" | head -1 )"
case "$ECTX" in
    *'budget_tokens="3000"'*) ok "C3 the explicit --token-budget path still names budget_tokens=\"3000\"" ;;
    *) no "C3 --token-budget=3000 stopped naming budget_tokens=" ;;
esac
case "$ECTX" in
    *budget_bytes*) no "C8 exclusivity: an explicit run named BOTH ceilings — $ECTX" ;;
    *) ok "C8 exclusivity: the explicit run names its own ceiling and only that one" ;;
esac

# SILENCE: a corpus whose bundle fits pays nothing — no attribute AND no legend clause.
run "$TINY" --for="leafOne" > "$TMP/c_tiny.xml"
TINYTAG="$( grep -o '<sigs[^>]*>' "$TMP/c_tiny.xml" | head -1 )"
case "$TINYTAG" in
    *capped*) no "C4 silence: the tiny corpus was capped (probe broken) — $TINYTAG" ;;
    "")       no "C4 silence: no <sigs> element on the tiny corpus (probe broken)" ;;
    *)        ok "C4 silence: the tiny corpus is genuinely uncapped — $TINYTAG" ;;
esac
if grep -q 'budget_bytes' "$TMP/c_tiny.xml"; then
    no "C9 silence: an UNCUT bundle paid for a ceiling attribute and its legend clause"
else
    ok "C9 silence: an uncut bundle carries neither the attribute nor its legend clause"
fi

# SURFACE PARITY (§P8: one element name, one attribute order, both surfaces). The MCP `for` verb is the
# same verb budgeted the same way by default (mcpverbs.h forBudgetBytes), and it had the same silence. A fix
# that landed on the CLI alone would have replaced one honesty gap with a disagreement between two surfaces
# an agent can reach for the same answer, so both are asserted here — including the exclusivity half.
mcp_text '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$BIG"'","task":"'"$FORQ"'"}}}' > "$TMP/c_mcp.xml"
mcp_text '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$BIG"'","task":"'"$FORQ"'","budget_tokens":3000}}}' > "$TMP/c_mcp_tb.xml"
MCTX="$(  grep -o '<ctx[^>]*>' "$TMP/c_mcp.xml"    | head -1 )"
MCTXTB="$( grep -o '<ctx[^>]*>' "$TMP/c_mcp_tb.xml" | head -1 )"
MSIGS="$( grep -o '<sigs[^>]*>' "$TMP/c_mcp.xml"   | head -1 )"
case "$MSIGS" in
    *'capped="1"'*) ok "C11 crossing: the MCP for verb's default bundle is capped too — $MSIGS" ;;
    *) no "C11 crossing: the MCP for default was not capped (probe broken) — ${MSIGS:-<none>}" ;;
esac
case "$MCTX" in
    *"budget_bytes=\"$FORPAYLOAD\""*) ok "C12 the MCP surface names the same ceiling as the CLI" ;;
    *) no "C12 the MCP for verb cut its bundle and named no ceiling — ${MCTX:-<none>}" ;;
esac
case "$MCTXTB" in
    *budget_bytes*) no "C13 MCP exclusivity: an explicit budget_tokens run named BOTH ceilings" ;;
    *'budget_tokens="3000"'*) ok "C13 MCP exclusivity: the explicit run names its own ceiling and only that one" ;;
    *) no "C13 MCP: budget_tokens=3000 named no ceiling at all — ${MCTXTB:-<none>}" ;;
esac
# the two surfaces must say the SAME sentence about the attribute, not two paraphrases of it.
CLAUSE_CLI="$( grep -o '\[budget_bytes=[^]]*\]' "$TMP/c_default.xml" | head -1 )"
CLAUSE_MCP="$( grep -o '\[budget_bytes=[^]]*\]' "$TMP/c_mcp.xml"     | head -1 )"
if [ -n "$CLAUSE_CLI" ] && [ "$CLAUSE_CLI" = "$CLAUSE_MCP" ]; then
    ok "C14 both surfaces define budget_bytes= with the same sentence"
else
    no "C14 the two surfaces define budget_bytes= differently: CLI=${CLAUSE_CLI:-<none>} MCP=${CLAUSE_MCP:-<none>}"
fi

# the JSON dialect answers the same question (forLensJsonBudgetStanza's twin).
run "$BIG" --for="$FORQ" --json > "$TMP/c_json.json"
run "$BIG" --for="$FORQ" --json --token-budget=3000 > "$TMP/c_json_tb.json"
python3 - "$TMP/c_json.json" "$TMP/c_json_tb.json" "$FORPAYLOAD" <<'PY' > "$TMP/c_json.res" 2>&1
import json, sys
want = int(sys.argv[3])
try:
    d  = json.load(open(sys.argv[1], encoding="utf-8"))
    dt = json.load(open(sys.argv[2], encoding="utf-8"))
except Exception as e:
    print("C5 NO --for --json did not parse: %s" % e); raise SystemExit
if not d.get("capped"):
    print("C5 NO --for --json was not capped (probe broken)"); raise SystemExit
print("C5 %s --for --json names budget_bytes=%s (want %d)"
      % ("OK" if d.get("budget_bytes") == want else "NO", d.get("budget_bytes"), want))
print("C10 %s --json exclusivity: explicit run has budget_tokens=%s and budget_bytes=%s"
      % ("OK" if dt.get("budget_tokens") == 3000 and "budget_bytes" not in dt else "NO",
         dt.get("budget_tokens"), dt.get("budget_bytes")))
PY
while read -r tag verdict rest; do
    [ "$verdict" = OK ] && ok "$tag $rest" || no "$tag $rest"
done < <( grep -E '^C[0-9]+ ' "$TMP/c_json.res" )

# ===================================================================================================
# (D) determinism + well-formedness of every document this gate produced (contract #2 and G4).
# ===================================================================================================
echo "-- (D) determinism + well-formedness"
run "$BIG" --for="$FORQ" > "$TMP/d_a.xml"
run "$BIG" --for="$FORQ" > "$TMP/d_b.xml"
if cmp -s "$TMP/d_a.xml" "$TMP/d_b.xml"; then ok "D1 the disclosed default --for is byte-identical run to run"; else no "D1 the default --for is not deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
    xmlfail=0
    for f in "$TMP/a_grep.xml" "$TMP/a_verify.xml" "$TMP/b_sigs.xml" "$TMP/b_for.xml" "$TMP/c_default.xml" "$TMP/c_tiny.xml"; do
        [ -s "$f" ] || continue
        xmllint --noout "$f" >/dev/null 2>&1 || { xmlfail=1; echo "      ill-formed: $f"; }
    done
    [ "$xmlfail" -eq 0 ] && ok "D2 every disclosed document is well-formed XML" || no "D2 a disclosed document is ill-formed"
else
    ok "D2 (skipped: no xmllint)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
