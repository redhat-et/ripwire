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
#        forrowlines.h writes after paging) is the schema comment (<= 1024 B, carrying the full-legend pointer) plus at most one
#        paging/act comment (<= 512 B, less the ACT-EDGES lane's edges: clause, <= 100 B, present with its line —
#        src/forpages.h kCoreEdgesClause, pinned by test/actedgescheck.sh)
#   (C1n) negative control: the same checker on page 1 with the pointer removed fails, and on the --legend=last page 1 (the full
#        legend, > 1 KiB) fails
#   (C2) the pointer works: --legend=last's page 1 carries the page clause (page=K of pages=N) and a legend over 1 KiB
#   (C3) REFILL, never growth: the default page 1 (rows as lines, as served) is no larger than --legend=last's page 1, and its
#        withheld_bytes= is <= (it holds at least the rows the full-legend page 1 holds)
#   (C4) the switch: RIPWIRE_NO_CORE_LEGEND=1 serves --legend=last's page 1 byte for byte, but for the --legend=compact its next= names (C9)
#        and the root's est_tokens= that prices it; --page-bytes=0 is unchanged by the core
#   (C5) ROW IDENTITY under the core: following next= to the last page, every page's <d>/<t> rows joined equal the
#        --page-bytes=0 answer's rows in order; (C5n) dropping one row makes it fail
#   (C6) a one-page default answer carries the core legend too, and every default page is well-formed XML
#   (C8) CORE + PAGING/ACT (owner 11-24, CLAUDE.md G4): every paging/act attribute page 1 carries is DEFINED on page 1 — the root's
#        page= pages= withheld_bytes= continued= deferred= next= root= at=, the act line's read=, and demote's ptr= when a sigs <t> has
#        none — on the paged page 1 and on a one-page answer; (C8n) page 1 with its paging/act comment removed fails
#   (C7) THE CUT IS FORM-INDEPENDENT: page 1 in the line form and in the element form (RIPWIRE_NO_ROWLINES) ends at the same row
#        (equal withheld_bytes=), so the row form stays a lossless re-spelling (rowlinescheck (L1)) and next= needs no --rows=
#   (C9) A SPELLED POSTURE KEEPS ITS PLAN (CR #740): page 1 of --legend=last|compact|dict names the resolved posture in next=
#        (--legend=compact: the three page the same answer, and dict stays byte-identical to compact, legenddefaultcheck D1; a
#        continuation without it is cut under the core-legend refill, and the rows between the two cuts land on no page); the
#        default next= names none; following the --legend=last chain to the last page delivers the --page-bytes=0 rows in order.
#        COUNTS the next= calls it read and fails on zero
# (C1), (C3) and (C6) run in the shipped row-line form too (CR #740 nitpick); (C5) and (C9)'s row identity read element rows.
set -u
export RIPWIRE_NO_ROWLINES=1   # (C5)/(C9) read rows as elements; (C1)/(C3)/(C6) also read the line form (env -u below)
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
env -u RIPWIRE_NO_ROWLINES "$BIN" . --for="$TASK" --page-bytes=100000000 >"$WORK/lines_onepage.xml" 2>/dev/null
for p in compact dict; do "$BIN" . --for="$TASK" --legend=$p >"$WORK/${p}_1.xml" 2>/dev/null; done
follow(){   # follow next= from $WORK/$1_1.xml to the last page (pasteable shell: shlex, never by hand); pages served -> $1.n
    local k=1 nx   # $2..: the env(1) arguments every continuation runs under
    while :; do
        nx="$( python3 -c 'import re,sys,html; d=open(sys.argv[1],encoding="utf-8").read(); m=re.match(r"<ctx\b[^>]*?\snext=\"([^\"]*)\"",d); print(html.unescape(m.group(1)) if m else "")' "$WORK/$1_$k.xml" )"
        [ -n "$nx" ] || break
        [ "$k" -lt 60 ] || break
        env "${@:2}" python3 -c 'import shlex,sys,subprocess; a=shlex.split(sys.argv[3]); sys.exit(subprocess.run([sys.argv[1], "."]+a, stdout=open(sys.argv[2],"wb"), stderr=subprocess.DEVNULL).returncode)' \
            "$BIN" "$WORK/$1_$(( k + 1 )).xml" "$nx" || break
        k=$(( k + 1 ))
    done
    echo "$k" >"$WORK/$1.n"
}
follow core RIPWIRE_NO_ROWLINES=1; mv "$WORK/core.n" "$WORK/pages.n"
follow last RIPWIRE_NO_ROWLINES=1
follow lines -u RIPWIRE_NO_ROWLINES   # the shipped form, for (C6)'s xmllint

python3 - "$WORK" <<'PY'
import re, sys, glob, subprocess, shlex, html
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
LANE = re.compile(r"edges: per act symbol[^;]*?(?:; |(?= -->))")   # ACT-EDGES: the clause of the line the page carries
def paging_ok(c):
    return len(LANE.sub("", c).encode()) <= 512 and all(len(x.encode()) <= 100 for x in LANE.findall(c))
def core_ok(t):
    leg, n = doc_legend(t)
    cs = re.findall(r"<!--.*?-->", leg, re.S)
    ok = 1 <= n <= 2 and len(cs[0].encode()) <= 1024 and POINTER in cs[0] and all(paging_ok(c) for c in cs[1:])
    return ok, len(leg.encode()), n
PAGING = ("page", "pages", "withheld_bytes", "continued", "deferred", "next", "root", "at")
def undefined(t):
    """paging/act attributes page t carries with no `name=` spelled in its comments; -> (missing, how many it checked)"""
    comments = " ".join(re.findall(r"<!--.*?-->", t, re.S))
    root = t[: t.find(">") + 1]
    need = [a for a in PAGING if re.search(r"\s" + a + r'="', root)]
    m = re.search(r"<act\b[^>]*\sread=", t)
    if m: need.append("read")
    sg = re.search(r"<sigs\b.*?</sigs>", re.sub(r"<!--.*?-->", "", t, flags=re.S), re.S)
    if sg and re.search(r"<t\b(?![^>]*\sptr=)[^>]*>", sg.group(0)): need.append("ptr")
    return [a for a in need if not re.search(r"(?<![a-z_])" + a + "=", comments)], len(need)
def root_int(t, a):
    m = re.match(r'<ctx\b[^>]*?\s' + a + r'="(\d+)"', t); return int(m.group(1)) if m else None
core, last, knob = rd(W + "/core_1.xml"), rd(W + "/last_1.xml"), rd(W + "/knob_1.xml")
pages = int(open(W + "/pages.n").read())
lleg, ln = doc_legend(last)
say(pages >= 2 and len(lleg.encode()) > 1024 and ln > 0, f"(C0) premise: {pages} pages, full page-1 legend {len(lleg.encode())} B in {ln} comments (> 1 KiB)")
okc, nb, nc = core_ok(core)
cs = [len(c.encode()) for c in re.findall(r"<!--.*?-->", doc_legend(core)[0], re.S)]
say(okc, f"(C1) default page 1 legend {nb} B in {nc} comment(s) {cs}: schema <= 1024 B with the full-legend pointer, paging/act <= 512 B")
okl, nbl, ncl = core_ok(rd(W + "/lines_1.xml"))
say(okl, f"(C1) row-line form (as served): page 1 legend {nbl} B in {ncl} comment(s), the same core bounds")
say(not core_ok(core.replace(POINTER, ""))[0], "(C1n) the checker fails page 1 with the pointer removed")
say(not core_ok(last)[0], "(C1n) the checker fails the full-legend (--legend=last) page 1")
say("<!-- page=K of pages=N:" in last and len(lleg.encode()) > 1024, "(C2) --legend=last page 1 carries the page clause and the full legend")
lc, ll = rd(W + "/lines_1.xml"), rd(W + "/lines_last_1.xml")
cw, lw = root_int(lc, "withheld_bytes"), root_int(ll, "withheld_bytes")
say(len(lc.encode()) <= len(ll.encode()) and cw is not None and lw is not None and cw <= lw,
    f"(C3) refill: page 1 as served {len(lc.encode())} B <= {len(ll.encode())} B; withheld_bytes {cw} <= {lw}")
def unposture(t):   # --legend=last's page 1 less the posture its next= names and the est_tokens= digits that price those bytes
    t = re.sub(r'(<ctx\b[^>]*?\snext="[^"]*?) --legend=compact', r"\1", t, count=1)
    return re.sub(r'(<ctx\b[^>]*?\sest_tokens=")\d+', r"\g<1>N", t, count=1)
say(knob != last and unposture(knob) == unposture(last),
    "(C4) RIPWIRE_NO_CORE_LEGEND=1 page 1 == --legend=last page 1, byte for byte but for next='s --legend=compact and est_tokens=")
say(rd(W + "/whole.xml") == rd(W + "/whole_knob.xml"), "(C4) --page-bytes=0 is untouched by the core legend")
ROW = re.compile(r"<d\b[^>]*>.*?</d>|<t\b[^>]*/>", re.S)
def rows(t): return ROW.findall(re.sub(r"<!--.*?-->", "", t, flags=re.S))
joined = [r for k in range(1, pages + 1) for r in rows(rd(f"{W}/core_{k}.xml"))]
whole = rows(rd(W + "/whole.xml"))
say(len(whole) > 0 and joined == whole, f"(C5) row identity: {len(joined)} rows over {pages} pages == {len(whole)} whole-answer rows")
say(joined[:-1] != whole, "(C5n) a page chain with one row dropped fails the identity")
one = rd(W + "/onepage.xml")
say(' page="' not in one[:one.find(">")] and core_ok(one)[0], "(C6) a one-page default answer is served whole with the core legend")
lone = rd(W + "/lines_onepage.xml")
say(' page="' not in lone[:lone.find(">")] and core_ok(lone)[0], "(C6) row-line form: a one-page default answer is served whole with the core legend")
xs = sorted(glob.glob(W + "/core_*.xml")) + sorted(glob.glob(W + "/lines_*.xml")) + [W + "/onepage.xml"]
for p in xs:
    r = subprocess.run(["xmllint", "--noout", p], capture_output=True)
    if r.returncode: say(False, f"(C6) {p.rsplit('/',1)[1]} is not well-formed: {r.stderr[:200]!r}")
lpages = len(glob.glob(W + "/lines_[0-9]*.xml"))
say(lpages == pages == int(open(W + "/lines.n").read()) and len(xs) == 2 * pages + 3,
    f"(C6) every default page parsed (xmllint): {len(xs)} documents, {pages} element + {lpages} row-line pages")
for name, t in (("paged page 1", core), ("one-page answer", one)):
    miss, n = undefined(t)
    say(n >= 3 and not miss, f"(C8) {name}: {n} paging/act attributes carried, undefined: {miss}")
pa = [c for c in re.findall(r"<!--.*?-->", doc_legend(core)[0], re.S) if "withheld_bytes=" in c]
say(len(pa) == 1 and undefined(core.replace(pa[0], ""))[0] != [], "(C8n) page 1 with its paging/act comment removed fails (C8)")
ew = root_int(core, "withheld_bytes")
say(cw is not None and cw == ew, f"(C7) one cut in both row forms: withheld_bytes lines {cw} == elements {ew}")
def next_of(t):
    m = re.match(r'<ctx\b[^>]*?\snext="([^"]*)"', t); return html.unescape(m.group(1)) if m else None
seen, wrong = 0, []
lpn = int(open(W + "/last.n").read())
for posture, files in (("last", [f"{W}/last_{k}.xml" for k in range(1, lpn + 1)]), ("compact", [W + "/compact_1.xml"]), ("dict", [W + "/dict_1.xml"])):
    for f in files:
        nx = next_of(rd(f))
        if nx is None: continue
        seen += 1
        if "--legend=compact" not in shlex.split(nx): wrong.append(f"{posture} {f.rsplit('/',1)[1]}: {nx}")
say(seen >= 3 and not wrong, f"(C9) {seen} spelled-posture next= call(s) read, each names the resolved --legend=compact; missing: {wrong}")
say(rd(W + "/dict_1.xml") == rd(W + "/compact_1.xml"), "(C9) --legend=dict page 1 == --legend=compact page 1, byte for byte (next= included)")
dn = [next_of(rd(f"{W}/core_{k}.xml")) for k in range(1, pages + 1)]
dn = [x for x in dn if x is not None]
say(len(dn) >= 1 and not any("--legend" in x for x in dn), f"(C9) {len(dn)} default next= call(s) read, none names a --legend (the default call is unchanged)")
ljoined = [r for k in range(1, lpn + 1) for r in rows(rd(f"{W}/last_{k}.xml"))]
say(lpn >= 2 and ljoined == whole, f"(C9) --legend=last chain: {len(ljoined)} rows over {lpn} pages == {len(whole)} whole-answer rows")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || no "an arm above failed"
[ "$fail" -eq 0 ] && echo "corelegendcheck: PASS" || echo "corelegendcheck: FAIL"
exit "$fail"
