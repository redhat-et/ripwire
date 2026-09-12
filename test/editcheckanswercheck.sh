#!/usr/bin/env bash
# editcheckanswercheck.sh — --edit-check may BOUND its context rows; it may never bound its ANSWER.
#
# --edit-check carries a VERDICT — status=, callers=, incompatible=, the flagged <c> rows and their
# sites_l= — and that verdict is the only thing an agent acts on. A row cap over an unwindowed emitter is
# the cheapest possible way to make it WRONG: cut the one flagged caller because it happened to sort past
# the window and the document says "no incompatible callers" while an incompatible caller exists. A wrong
# answer with capped="1" beside it is still a wrong answer, so the bound this gate pins is deliberately
# NOT "the emitter stops at N rows". It is:
#
#   1. EVERY verdict/count/status attribute is computed over the FULL caller set, never the emitted window.
#   2. The rows that ARE the answer — every caller flagged incompatible="1", and the COMPLETE sites_l= line
#      list on each — are never subject to any cap, offset or page. They ride EVERY page, complete, the way
#      --test-gate's <t> rows already do.
#   3. Only the UNFLAGGED context rows page, under pageview.h's own vocabulary
#      (shown_unflagged=/unflagged_capped= + total=/has_more=/next_offset=/offset=/limit=).
#   4. The <def> overload census is the set behind defs= and is never cut either.
#
# THE DECISIVE ARM is (B) RE-DERIVATION, not "does the bound trip". "Does the bound trip" is green for a
# broken emitter too. (B) asks the only question that matters — DOES THE ANSWER CHANGE WHEN THE BOUND IS
# REMOVED — by running the same binary twice, once at the default cap and once at --limit=1000000, and
# demanding the verdict attributes and the flagged-row set be BYTE-IDENTICAL, on the fixtures and on real
# symbols of this repo's own src/ spanning the caller distribution (a leaf, a typical, the widest).
#
# Each arm asserts the capdisclosurecheck.sh triple, for the same reason it does:
#   CROSSING   — the fixture really is past the cap (proved from the UNCAPPED run's own row count), so a
#                green arm cannot be a fixture that never reached the code under test.
#   DISCLOSURE — the crossed answer says so, in the shared vocabulary.
#   SILENCE    — a fixture that FITS carries none of those attributes and none of the cap legend.
#
# MUTATION CONTROL: run against a binary built before this change —
#     RIPWIRE_BIN=<pre-change>/ripwire bash test/editcheckanswercheck.sh
# — and the DISCLOSURE halves of (A), (C), (D) and all of (G) must FAIL while every CROSSING half still
# passes. That is the red run this gate was written from.
#
# Usage:
#   bash test/editcheckanswercheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/editcheckanswercheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Needs git + python3.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "editcheckanswercheck: git required";     exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "editcheckanswercheck: python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "editcheckanswercheck: BIN=$BIN"

# The cap under test, read from the source that defines it rather than retyped here: a gate that hardcodes
# 40 goes green the day the family constant moves and the emitter stops agreeing with it.
CAP="$( sed -n 's/.*kCallHierarchyRowCap  *= *\([0-9][0-9]*\).*/\1/p' "$ROOT/src/pageview.h" | head -1 )"
case "$CAP" in ''|*[!0-9]*) echo "editcheckanswercheck: could not read kCallHierarchyRowCap from src/pageview.h"; exit 2 ;; esac
echo "  (kCallHierarchyRowCap = $CAP)"

# ---------------------------------------------------------------------------------------------------
# FIXTURES. Sized from $CAP by python3, never eyeballed: a fixture that lands one row short of the cap is
# a green arm that asserts nothing. Grown WELL past it (cap + 20 unflagged rows) so the gate cannot go
# green at a raised cap value either.
#
# ANS — the answer-safety fixture. HEAD holds `int target( int a )`; the working tree widens it to
#   ( int a, int b ), so status="contract-change" with params 1 -> 2.
#     src/a###.cpp   CAP+20 callers that pass TWO arguments — they match the NEW arity, so none is flagged.
#     src/zz_last.cpp ONE caller that passes ONE argument — provably incompatible with every definition in
#                    the set, so it IS the answer. It lives in the alphabetically LAST file at a high line,
#                    so under any (file, line, name) window it sorts past the cap: an emitter that windows
#                    the row list drops exactly this row and reports incompatible callers it cannot name.
#                    It calls the target on 50 DISTINCT LINES, so sites_l= is far wider than any row cap.
# ---------------------------------------------------------------------------------------------------
python3 - "$TMP" "$CAP" <<'PY'
import os, sys
tmp, cap = sys.argv[1], int(sys.argv[2])
wide = cap + 20                       # unflagged context rows: comfortably past the cap, from the cap itself

ans = os.path.join(tmp, "ans", "src");  os.makedirs(ans)
open(os.path.join(ans, "target.cpp"), "w").write("int target( int a ) { return a; }\n")   # the HEAD contract
for i in range(1, wide + 1):
    open(os.path.join(ans, "a%03d.cpp" % i), "w").write(
        "int callerA%03d( void ) { return target( 1, 2 ); }\n" % i)
last = ["int zzLastCaller( void )", "{", "    int t = 0;"]
last += ["    t += target( 1 );"] * 50                 # 50 distinct LINES, one call each
last += ["    return t;", "}"]
open(os.path.join(ans, "zz_last.cpp"), "w").write("\n".join(last) + "\n")

# TINY — the SILENCE fixture: two callers, nothing to cut at any cap.
tiny = os.path.join(tmp, "tiny", "src");  os.makedirs(tiny)
open(os.path.join(tiny, "a.cpp"), "w").write(
    "int tinyTarget( int x ) { return x + 1; }\n"
    "int tinyCallerOne( void ) { return tinyTarget( 1 ); }\n"
    "int tinyCallerTwo( void ) { return tinyTarget( 2 ); }\n")

# OVL — the overload CENSUS fixture: cap+5 definitions of one name at ONE definition site, so <def> rows
# outnumber any row cap. defs= counts them; the rows behind defs= may never be cut.
ovl = os.path.join(tmp, "ovl", "src");  os.makedirs(ovl)
defs = ["int ov( %s ) { return 0; }" % ", ".join("int p%d" % j for j in range(i + 1))
        for i in range(cap + 5)]
open(os.path.join(ovl, "ov.cpp"), "w").write("\n".join(defs) + "\n")
print(wide)
PY
WIDE="$(( CAP + 20 ))"

gitinit(){ ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
             && git add -A && git commit -qm init >/dev/null 2>&1 ); }
gitinit "$TMP/ans";  gitinit "$TMP/tiny";  gitinit "$TMP/ovl"
# THE EDIT: widen the contract AFTER the baseline commit, so the comparison has something to report.
printf 'int target( int a, int b ) { return a + b; }\n' > "$TMP/ans/src/target.cpp"

ec(){ # $1 = repo dir, $2 = symbol, $3.. = extra flags
    local dir="$1" sym="$2"; shift 2
    ( cd "$dir" && "$BIN" . --edit-check="$sym" --no-cache "$@" 2>/dev/null )
}

# The VERDICT — everything a caller acts on, as one canonical line. at= is deliberately excluded: it
# carries the +dirty stamp, which a concurrent gate writing a transient file into the tree can flip
# between two runs (memory: "dirty stamp under parallel gates"), and it is not a verdict attribute.
verdict(){ python3 -c '
import re, sys
doc  = sys.stdin.read()
root = re.search(r"<edit-check [^>]*>", doc)
if not root: print("__NO_ROOT__"); raise SystemExit(0)
attrs = dict(re.findall(r"([a-z_]+)=\"([^\"]*)\"", root.group(0)))
keys  = ["sym","t","p","status","defs","params_was","params_now","public_was","public_now",
         "defs_was","defs_now","change","callers","incompatible"]
print(" ".join("%s=%s" % (k, attrs[k]) for k in keys if k in attrs))
'; }

# The ANSWER ROWS — every flagged caller with its complete site list, in document order.
flagged(){ grep -oE '<c [^>]*incompatible="1"[^>]*/>' || true; }
# The CONTEXT ROWS — the unflagged callers, by name, in document order.
unflagged(){ grep -oE '<c [^>]*/>' | grep -v 'incompatible="1"' | sed -E 's/.* n="([^"]*)".*/\1/' || true; }
rootattr(){ grep -oE '<edit-check [^>]*>' | head -1; }

UNCAP="--limit=1000000"

# ===================================================================================================
# (A) THE VERDICT IS COMPUTED OVER THE FULL CALLER SET, AND THE FLAGGED ROW SURVIVES THE WINDOW
# ===================================================================================================
echo "--- (A) verdict over the full set; the flagged caller past the window is still emitted ---"
ec "$TMP/ans" target            > "$TMP/a_def.xml"
ec "$TMP/ans" target  $UNCAP    > "$TMP/a_all.xml"

# CROSSING — read off the DEFAULT run's own FULL-SET counts, so the assertion holds on a pre-change binary
# too (it must: a crossing half that only passes once the fix is in proves nothing about the fixture).
# callers=/incompatible= are full-set counts under both shapes, so WIDE unflagged callers really do exist
# and really are more than the cap.
ALLUNF="$WIDE"
CALLERS_SEEN="$( rootattr < "$TMP/a_def.xml" | grep -oE ' callers="[0-9]+"' | tr -cd '0-9' )"
INC_SEEN="$(     rootattr < "$TMP/a_def.xml" | grep -oE ' incompatible="[0-9]+"' | tr -cd '0-9' )"
[ "$CALLERS_SEEN" = "$(( WIDE + 1 ))" ] && [ "$INC_SEEN" = 1 ] && [ "$WIDE" -gt "$CAP" ] \
    && ok "(A) CROSSING: $WIDE unflagged callers (> cap $CAP) plus 1 flagged one — the fixture is past the window" \
    || no "(A) CROSSING: fixture did not cross the cap (callers=$CALLERS_SEEN incompatible=$INC_SEEN cap=$CAP) — the arm proves nothing"
# and the flagged row is the LAST row of all: nothing but a partition can keep it inside a $CAP-row window.
[ "$( grep -oE '<c [^>]*/>' "$TMP/a_def.xml" | tail -1 | grep -c 'n="zzLastCaller"' )" = 1 ] \
    && ok "(A) CROSSING: the flagged caller is the LAST caller row — past any first-page window" \
    || no "(A) CROSSING: zzLastCaller is not last in document order; re-check the fixture's sort key"

# ANSWER — it is still there at the default cap, with its complete site list.
grep -q '<c n="zzLastCaller"[^>]*incompatible="1"' "$TMP/a_def.xml" \
    && ok "(A) ANSWER: the incompatible caller past the window IS emitted at the default cap" \
    || { no "(A) ANSWER: the incompatible caller was CUT — the document now says less than it knows"; head -c 400 "$TMP/a_def.xml"; }
SITES="$( grep -oE '<c n="zzLastCaller"[^>]*/>' "$TMP/a_def.xml" | grep -oE 'sites_l="[^"]*"' | head -1 | tr ',' '\n' | grep -c . )"
[ "${SITES:-0}" = 50 ] \
    && ok "(A) ANSWER: sites_l= carries all 50 call-site lines, uncut" \
    || no "(A) ANSWER: sites_l= holds $SITES of 50 lines — the lines to open were truncated"

# VERDICT — the counts are the FULL set's, not the page's.
grep -q "callers=\"$(( WIDE + 1 ))\" incompatible=\"1\"" "$TMP/a_def.xml" \
    && ok "(A) VERDICT: callers=$(( WIDE + 1 )) incompatible=1 — counted over the full set, not the window" \
    || { no "(A) VERDICT: root counts follow the window"; rootattr < "$TMP/a_def.xml"; }
grep -q 'status="contract-change"' "$TMP/a_def.xml" && grep -q 'params_was="1" params_now="2"' "$TMP/a_def.xml" \
    && ok "(A) VERDICT: status=contract-change with params 1 -> 2" \
    || no "(A) VERDICT: wrong contract verdict on the widened definition"

# DISCLOSURE — the context listing says it was cut, in the shared vocabulary. (RED on a pre-change binary.)
grep -q "shown_unflagged=\"$CAP\" unflagged_capped=\"1\"" "$TMP/a_def.xml" \
    && ok "(A) DISCLOSURE: shown_unflagged=$CAP unflagged_capped=1" \
    || { no "(A) DISCLOSURE: the cut context listing is SILENT"; rootattr < "$TMP/a_def.xml"; }
grep -q "total=\"$WIDE\" has_more=\"1\" next_offset=\"$CAP\" offset=\"0\" limit=\"0\"" "$TMP/a_def.xml" \
    && ok "(A) DISCLOSURE: total=$WIDE has_more=1 next_offset=$CAP offset=0 limit=0 — a loop can continue" \
    || { no "(A) DISCLOSURE: the paging half is missing or wrong"; rootattr < "$TMP/a_def.xml"; }
grep -qF 'never paged and never cut' "$TMP/a_def.xml" \
    && ok "(A) DISCLOSURE: the legend states, in band, that the flagged rows are never paged and never cut" \
    || no "(A) DISCLOSURE: the legend does not say that only unflagged rows page"

# ===================================================================================================
# (B) RE-DERIVATION — the decisive arm. Remove the bound; the ANSWER must not move by one byte.
# ===================================================================================================
echo "--- (B) re-derivation: verdict + flagged rows identical with the bound removed ---"
same_answer(){ # $1 = label, $2 = capped doc, $3 = uncapped doc
    local label="$1" a="$2" b="$3"
    verdict < "$a" > "$a.v";  verdict < "$b" > "$b.v"
    flagged < "$a" > "$a.f";  flagged < "$b" > "$b.f"
    if cmp -s "$a.v" "$b.v"; then ok "(B) $label: verdict attributes byte-identical with the bound removed"
    else no "(B) $label: THE VERDICT MOVED when the bound was removed"; diff "$a.v" "$b.v" | head -4; fi
    if cmp -s "$a.f" "$b.f"; then ok "(B) $label: flagged rows (with sites_l=) byte-identical"
    else no "(B) $label: THE FLAGGED ROWS MOVED when the bound was removed"; diff "$a.f" "$b.f" | head -4; fi
}
same_answer "fixture target" "$TMP/a_def.xml" "$TMP/a_all.xml"

# and on REAL symbols of this repo's own src/, spanning the measured caller distribution: a leaf, a
# typical mid-fan-in symbol, and the widest name in the tree. Named rather than discovered so a rename
# fails LOUDLY here instead of quietly reducing the arm to a leaf-only test.
for sym in editCheckSiteList escapeXml push_back; do
    "$BIN" "$ROOT/src" --edit-check="$sym"         > "$TMP/r_$sym.def.xml" 2>/dev/null
    "$BIN" "$ROOT/src" --edit-check="$sym" $UNCAP  > "$TMP/r_$sym.all.xml" 2>/dev/null
    if [ -s "$TMP/r_$sym.def.xml" ] && [ -s "$TMP/r_$sym.all.xml" ]; then
        same_answer "src/ $sym" "$TMP/r_$sym.def.xml" "$TMP/r_$sym.all.xml"
    else
        no "(B) src/ $sym: --edit-check produced nothing — the symbol was renamed or the run failed"
    fi
done

# ===================================================================================================
# (C) PAGING REACHES EVERY CONTEXT ROW — exactly once, and every page still carries the answer
# ===================================================================================================
echo "--- (C) walking the disclosed pages visits every unflagged row exactly once ---"
unflagged < "$TMP/a_all.xml" > "$TMP/c_expected.txt"
: > "$TMP/c_walked.txt"
off=0; pages=0; guard=0
while : ; do
    ec "$TMP/ans" target --limit="$CAP" --offset="$off" > "$TMP/c_page.xml"
    unflagged < "$TMP/c_page.xml" >> "$TMP/c_walked.txt"
    pages=$(( pages + 1 ))
    grep -q '<c n="zzLastCaller"[^>]*incompatible="1"' "$TMP/c_page.xml" || { no "(C) page at offset=$off dropped the flagged row"; break; }
    grep -q 'has_more="1"' "$TMP/c_page.xml" || break
    off="$( grep -oE 'next_offset="[0-9]+"' "$TMP/c_page.xml" | head -1 | tr -cd '0-9' )"
    guard=$(( guard + 1 ));  [ "$guard" -gt 20 ] && { no "(C) the paging loop did not terminate in 20 pages"; break; }
done
if cmp -s "$TMP/c_expected.txt" "$TMP/c_walked.txt"; then
    ok "(C) $pages pages visited all $ALLUNF unflagged rows, in order, no duplicate and no gap"
else
    no "(C) the page walk does not reconstruct the full context listing"
    diff "$TMP/c_expected.txt" "$TMP/c_walked.txt" | head -5
fi

# ===================================================================================================
# (D) THE MCP TWIN ANSWERS THE SAME DOCUMENT
# ===================================================================================================
echo "--- (D) MCP edit_check parity ---"
MCPDOC="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"edit_check\",\"arguments\":{\"path\":\"$TMP/ans\",\"symbol\":\"target\"}}}" \
    | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("" if "error" in r else r["result"]["content"][0]["text"])
' )"
printf '%s' "$MCPDOC" > "$TMP/d_mcp.xml"
if [ -s "$TMP/d_mcp.xml" ]; then
    verdict < "$TMP/d_mcp.xml" > "$TMP/d_mcp.v"
    cmp -s "$TMP/d_mcp.v" "$TMP/a_def.xml.v" \
        && ok "(D) MCP twin: verdict attributes identical to the CLI answer" \
        || { no "(D) MCP twin: verdict differs from the CLI"; diff "$TMP/a_def.xml.v" "$TMP/d_mcp.v" | head -4; }
    grep -q '<c n="zzLastCaller"[^>]*incompatible="1"' "$TMP/d_mcp.xml" \
        && ok "(D) MCP twin: the flagged caller past the window is emitted there too" \
        || no "(D) MCP twin: the flagged caller was cut on the MCP surface"
    grep -q "shown_unflagged=\"$CAP\" unflagged_capped=\"1\"" "$TMP/d_mcp.xml" \
        && ok "(D) MCP twin: the same cut disclosure rides the MCP document" \
        || no "(D) MCP twin: the MCP surface caps silently (or does not cap) — the two surfaces disagree"
else
    no "(D) MCP twin: edit_check returned no payload"
fi

# ===================================================================================================
# (E) SILENCE — a fixture that FITS carries none of it
# ===================================================================================================
echo "--- (E) silence on an answer that was never cut ---"
ec "$TMP/tiny" tinyTarget > "$TMP/e_tiny.xml"
grep -q 'callers="2"' "$TMP/e_tiny.xml" \
    && ok "(E) CROSSING(control): the fitting fixture really does answer with 2 callers" \
    || { no "(E) control fixture did not resolve"; head -c 300 "$TMP/e_tiny.xml"; }
for a in 'shown_unflagged=' 'unflagged_capped=' ' total="' ' has_more="' ' next_offset="' ' offset="' ' limit="'; do
    grep -qF -- "$a" "$TMP/e_tiny.xml" \
        && no "(E) SILENCE: an uncut answer carries $a — the disclosure is a tax, not a disclosure" \
        || ok "(E) SILENCE: no $a on an uncut answer"
done

# ===================================================================================================
# (F) THE CENSUS AND THE SITE LISTS ARE NEVER CUT
# ===================================================================================================
echo "--- (F) <def> overload census and sites_l= are never windowed ---"
ec "$TMP/ovl" ov > "$TMP/f_ovl.xml"
NDEF="$( grep -oE '<def [^>]*/>' "$TMP/f_ovl.xml" | wc -l | tr -d ' ' )"
# off the ROOT TAG, never the whole document: the legend itself contains the string defs="1" (it defines
# the at-defs="1"-no-def-row rule in band), and a document-wide grep reads that as the answer.
DECL="$( rootattr < "$TMP/f_ovl.xml" | grep -oE ' defs="[0-9]+"' | tr -cd '0-9' )"
[ "$DECL" -gt "$CAP" ] \
    && ok "(F) CROSSING: defs=$DECL definitions at one site (> cap $CAP)" \
    || no "(F) CROSSING: the overload fixture did not pass the cap (defs=$DECL)"
[ "$NDEF" = "$DECL" ] \
    && ok "(F) every one of the $DECL definitions behind defs= is listed — the census is uncut" \
    || no "(F) defs=$DECL but only $NDEF <def> rows — the set behind the count was windowed"
ec "$TMP/ovl" ov --limit=1 > "$TMP/f_ovl1.xml"
[ "$( grep -oE '<def [^>]*/>' "$TMP/f_ovl1.xml" | wc -l | tr -d ' ' )" = "$DECL" ] \
    && ok "(F) --limit=1 windows context rows, never the census" \
    || no "(F) --limit=1 cut the <def> census — defs= now names a set the document does not hold"

# ===================================================================================================
# (G) THE DOCUMENT IS PRICED — est_tokens=, from the ONE estimator, on every answer
# ===================================================================================================
echo "--- (G) est_tokens= prices the answer a caller is about to be handed ---"
priced(){ python3 -c '
import re, sys
doc = sys.stdin.buffer.read()
m = re.search(rb" est_tokens=\"([0-9]+)\"", doc)
if not m: print("MISSING"); raise SystemExit(0)
est, want = int(m.group(1)), int(len(doc) / 2.50 + 0.5)
print("OK" if abs(est - want) <= 1 else "WRONG est=%d want=%d bytes=%d" % (est, want, len(doc)))
'; }
for f in "$TMP/a_def.xml" "$TMP/e_tiny.xml" "$TMP/f_ovl.xml"; do
    case "$( priced < "$f" )" in
        OK) ok "(G) $( basename "$f" ): est_tokens= present and equal to the shared estimator's price" ;;
        MISSING) no "(G) $( basename "$f" ): no est_tokens= — the caller cannot see the size coming" ;;
        *) no "(G) $( basename "$f" ): $( priced < "$f" )" ;;
    esac
done

# ===================================================================================================
# well-formedness — every document this gate produced must still parse
# ===================================================================================================
if command -v xmllint >/dev/null 2>&1; then
    xmlfail=0
    for f in "$TMP"/a_def.xml "$TMP"/a_all.xml "$TMP"/e_tiny.xml "$TMP"/f_ovl.xml "$TMP"/f_ovl1.xml; do
        if [ ! -s "$f" ]; then
            xmlfail=1; no "(X) $( basename "$f" ) is EMPTY — that invocation produced no document at all"
        else
            xmllint --noout "$f" 2>/dev/null || { xmlfail=1; no "(X) $( basename "$f" ) is not well-formed XML"; }
        fi
    done
    [ "$xmlfail" = 0 ] && ok "(X) every emitted document is well-formed XML"
fi

echo
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES above"; exit 1
