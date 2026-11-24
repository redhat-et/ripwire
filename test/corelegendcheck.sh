#!/usr/bin/env bash
# corelegendcheck.sh — θ5 (lane THETA5, 2026-11-24; PLAN_071 §1.5): THE DEFAULT --for PAGE 1 CARRIES THE CORE LEGEND (src/forpages.h).
#
# Page 1 of the defaulted CLI posture keeps the first (schema) comment of the document legend, cut at a "; " clause boundary to at
# most 1 KiB INCLUDING a pointer to the full legend (the same call with --legend=last), and gives the freed bytes to rows. A spelled
# posture, MCP, --page-bytes=0 and RIPWIRE_NO_CORE_LEGEND keep today's full page-1 legend.
#
# Arms:
#   (C0) PREMISE: the fixture answer is paged (>= 2 pages) and its full page-1 legend is over 1 KiB — without both, (C1)/(C3) are
#        vacuous; the checker COUNTS the legend comments it read and fails on zero
#   (C1) the default page 1's document legend (every comment after the last row block, less the row-line clauses
#        forrowlines.h writes after paging) is <= 1024 B and contains the full-legend pointer
#   (C1n) negative control: the same checker on page 1 with the pointer removed fails, and on the --legend=last page 1 (the full
#        legend, > 1 KiB) fails
#   (C2) the pointer works: --legend=last's page 1 carries the page clause (page=K of pages=N) and a legend over 1 KiB
#   (C3) REFILL, never growth: the default page 1 (rows as lines, as served) is no larger than --legend=last's page 1, and its
#        withheld_bytes= is <= (it holds at least the rows the full-legend page 1 holds)
#   (C4) the switch: RIPWIRE_NO_CORE_LEGEND=1 serves --legend=last's page 1 byte for byte; --page-bytes=0 is unchanged by the core
#   (C5) ROW IDENTITY under the core: following next= to the last page, every page's <d>/<t> rows joined equal the
#        --page-bytes=0 answer's rows in order; (C5n) dropping one row makes it fail
#   (C6) a one-page default answer carries the core legend too, and every default page is well-formed XML
#   (C7) THE CUT IS FORM-INDEPENDENT: page 1 in the line form and in the element form (RIPWIRE_NO_ROWLINES) ends at the same row
#        (equal withheld_bytes=), so the row form stays a lossless re-spelling (rowlinescheck (L1)) and next= needs no --rows=
set -u
export RIPWIRE_NO_ROWLINES=1   # (C5) reads rows as elements; the line form is lossless (rowlinescheck (L1))
unset RIPWIRE_NO_CORE_LEGEND
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
command -v python3 >/dev/null 2>&1 || { echo "corelegendcheck: python3 required"; exit 2; }
fail=0
no(){ printf '  FAIL  %s\n' "$1"; fail=1; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "corelegendcheck: BIN=$BIN"
cd "$ROOT" || exit 2
TASK="legend posture answer first ordering of blocks"

"$BIN" . --for="$TASK"                                   >"$WORK/core_1.xml" 2>/dev/null
"$BIN" . --for="$TASK" --legend=last                     >"$WORK/last_1.xml" 2>/dev/null
RIPWIRE_NO_CORE_LEGEND=1 "$BIN" . --for="$TASK"          >"$WORK/knob_1.xml" 2>/dev/null
"$BIN" . --for="$TASK" --page-bytes=0                    >"$WORK/whole.xml" 2>/dev/null
RIPWIRE_NO_CORE_LEGEND=1 "$BIN" . --for="$TASK" --page-bytes=0 >"$WORK/whole_knob.xml" 2>/dev/null
"$BIN" . --for="$TASK" --page-bytes=100000000            >"$WORK/onepage.xml" 2>/dev/null
env -u RIPWIRE_NO_ROWLINES "$BIN" . --for="$TASK"                 >"$WORK/lines_1.xml" 2>/dev/null
env -u RIPWIRE_NO_ROWLINES "$BIN" . --for="$TASK" --legend=last   >"$WORK/lines_last_1.xml" 2>/dev/null
k=1
while :; do   # follow next= (pasteable shell: shlex, never by hand)
    nx="$( python3 -c 'import re,sys,html; d=open(sys.argv[1],encoding="utf-8").read(); m=re.match(r"<ctx\b[^>]*?\snext=\"([^\"]*)\"",d); print(html.unescape(m.group(1)) if m else "")' "$WORK/core_$k.xml" )"
    [ -n "$nx" ] || break
    k=$(( k + 1 )); [ "$k" -le 60 ] || break
    python3 -c 'import shlex,sys,subprocess; a=shlex.split(sys.argv[3]); sys.exit(subprocess.run([sys.argv[1], "."]+a, stdout=open(sys.argv[2],"wb"), stderr=subprocess.DEVNULL).returncode)' \
        "$BIN" "$WORK/core_$k.xml" "$nx" || break
done
echo "$k" >"$WORK/pages.n"

python3 - "$WORK" <<'PY'
import re, sys, glob, subprocess
W = sys.argv[1]; bad = 0
POINTER = "FULL LEGEND (every definition): this call with the legend=last flag"
ROWCLAUSES = ("<!-- sigs rseq=1:", "<!-- sigs/tail rows are lines:")
def rd(p): return open(p, encoding="utf-8").read()
def say(okay, msg):
    global bad
    print(("  PASS  " if okay else "  FAIL  ") + msg); bad |= (not okay)
def doc_legend(t):
    """the trailing run of top-level comments before </ctx>, less the row-line clauses; -> (bytes, count)"""
    body = t[: t.rfind("</ctx>")]
    comments = []
    while body.endswith("-->"):
        s = body.rfind("<!--"); comments.insert(0, body[s:]); body = body[:s]
    kept = [c for c in comments if not c.startswith(ROWCLAUSES)]
    return "".join(kept), len(kept)
def core_ok(t):
    leg, n = doc_legend(t)
    return n > 0 and len(leg.encode()) <= 1024 and POINTER in leg, len(leg.encode()), n
def root_int(t, a):
    m = re.match(r'<ctx\b[^>]*?\s' + a + r'="(\d+)"', t); return int(m.group(1)) if m else None
core, last, knob = rd(W + "/core_1.xml"), rd(W + "/last_1.xml"), rd(W + "/knob_1.xml")
pages = int(open(W + "/pages.n").read())
lleg, ln = doc_legend(last)
say(pages >= 2 and len(lleg.encode()) > 1024 and ln > 0, f"(C0) premise: {pages} pages, full page-1 legend {len(lleg.encode())} B in {ln} comments (> 1 KiB)")
okc, nb, nc = core_ok(core)
say(okc, f"(C1) default page 1 legend {nb} B in {nc} comment(s), <= 1024 B, carries the full-legend pointer")
say(not core_ok(core.replace(POINTER, ""))[0], "(C1n) the checker fails page 1 with the pointer removed")
say(not core_ok(last)[0], "(C1n) the checker fails the full-legend (--legend=last) page 1")
say("<!-- page=K of pages=N:" in last and len(lleg.encode()) > 1024, "(C2) --legend=last page 1 carries the page clause and the full legend")
lc, ll = rd(W + "/lines_1.xml"), rd(W + "/lines_last_1.xml")
cw, lw = root_int(lc, "withheld_bytes"), root_int(ll, "withheld_bytes")
say(len(lc.encode()) <= len(ll.encode()) and cw is not None and lw is not None and cw <= lw,
    f"(C3) refill: page 1 as served {len(lc.encode())} B <= {len(ll.encode())} B; withheld_bytes {cw} <= {lw}")
say(knob == last, "(C4) RIPWIRE_NO_CORE_LEGEND=1 page 1 == --legend=last page 1, byte for byte")
say(rd(W + "/whole.xml") == rd(W + "/whole_knob.xml"), "(C4) --page-bytes=0 is untouched by the core legend")
ROW = re.compile(r"<d\b[^>]*>.*?</d>|<t\b[^>]*/>", re.S)
def rows(t): return ROW.findall(re.sub(r"<!--.*?-->", "", t, flags=re.S))
joined = [r for k in range(1, pages + 1) for r in rows(rd(f"{W}/core_{k}.xml"))]
whole = rows(rd(W + "/whole.xml"))
say(len(whole) > 0 and joined == whole, f"(C5) row identity: {len(joined)} rows over {pages} pages == {len(whole)} whole-answer rows")
say(joined[:-1] != whole, "(C5n) a page chain with one row dropped fails the identity")
one = rd(W + "/onepage.xml")
say(' page="' not in one[:one.find(">")] and core_ok(one)[0], "(C6) a one-page default answer is served whole with the core legend")
for p in sorted(glob.glob(W + "/core_*.xml")) + [W + "/onepage.xml"]:
    r = subprocess.run(["xmllint", "--noout", p], capture_output=True)
    if r.returncode: say(False, f"(C6) {p.rsplit('/',1)[1]} is not well-formed: {r.stderr[:200]!r}")
say(True, "(C6) every default page parsed (xmllint)")
ew = root_int(core, "withheld_bytes")
say(cw is not None and cw == ew, f"(C7) one cut in both row forms: withheld_bytes lines {cw} == elements {ew}")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || no "an arm above failed"
[ "$fail" -eq 0 ] && echo "corelegendcheck: PASS" || echo "corelegendcheck: FAIL"
exit "$fail"
