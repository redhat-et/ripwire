#!/usr/bin/env bash
# mapdatasectioncheck.sh — data Sections never crowd code rows out of the default map (#339 F1), and the cut is disclosed.
#
# A data Section (a markdown heading, a YAML/JSON key, a Rails schema column) is a SymKind::Section row. With no call
# edge in or out, its rank is its share of the teleport prior, and priorwt's x1.7 specific-name boost fires on data
# names like `database_url_12`. So a data file of a few hundred keys used to push called code, `main` and `_helper`
# out of the top-K the map emits. The map now picks its rows CODE-FIRST (serialize.h codeFirstKeep, the registered
# Option B; Option A, a Section prior x0.1, failed the registered --eval margin): while the rank-order top-K keeps a
# Section and leaves a non-Section row out, the lowest-ranked kept Section is swapped for the highest-ranked excluded
# non-Section row. The rank vector is untouched. The swaps are disclosed as data_sections_cut= with a next= that pages
# them first.
#
# The statistic is end-to-end (docs/METHODOLOGY.md §7): code rows in the top-K the map actually emits, out of 8.
# Fixture: test/mapdatasectionfix/gen.sh — eight Python functions (a call chain under an uncalled `main`, plus an
# uncalled `_helper`) and ONE data file. The data shapes are S1 db/schema.rb columns, S2 markdown headings, S3 YAML
# keys and S4 JSON keys. S1 cells run only on a build that mints Sections from db/schema.rb (the #339 capture);
# elsewhere they are reported SKIP.
#
# Arms (the pre-registration in docs/EVALS.md "Map data Sections" names them):
#   (P)  §1 grid: shape x {long,short} x N in {20,40,200} x K in {200,16}, plus the primary cells S3/S4 long N=220.
#        Surfaces: XML, --json, the --html node set, --tree (the code file is listed first; --tree is not re-picked),
#        --max-tokens=1500, and MCP analyze on a clean git tree. Pass = 8/8 code rows on every cell x surface.
#   (D)  Gate D, for the pick: data_sections_cut = Sections in the rank-order top-K - Sections still shown; next= then
#        next_offset= (until has_more="0") pages every unshown Section once, the swapped ones first, every page <= K rows.
#        Run on XML and --max-tokens; --json, MCP analyze and MCP rank_by must carry the XML's disclosure.
#   (C)  the pick's invariant: a map that shows any Section shows every non-Section row.
#   (L)  the attribute is defined in the full XML legend, the compact legend and --help, and only where it rides.
#   (Z)  a Section-free fixture carries no data_sections_cut= and no next= on its root.
# MAPSEC_EXTRA_ROOTS=dir1:dir2 runs (D) and (C) on those trees too (the measurement harness's corpora).
# Exit 0 all pass, 1 any fail, 2 setup.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
GEN="$ROOT/test/mapdatasectionfix/gen.sh"
[ -x "$BIN" ] || { echo "mapdatasectioncheck: no ripwire binary at $BIN — build first"; exit 2; }
[ -f "$GEN" ] || { echo "mapdatasectioncheck: fixture generator missing: $GEN"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "mapdatasectioncheck: git not on PATH"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "mapdatasectioncheck: BIN=$BIN"

# Every fixture is a committed git tree, so MCP analyze sees a CLEAN working set (changed==0, the map scope).
mkfix(){
    bash "$GEN" "$TMP/$1" "$2" "$3" "$4" || return 1
    git -C "$TMP/$1" init -q && git -C "$TMP/$1" add -A \
        && git -C "$TMP/$1" -c user.name=gate -c user.email=gate@example.invalid -c commit.gpgsign=false commit -qm fixture
}
for shape in S1 S2 S3 S4; do
    for len in long short; do
        for n in 20 40 200; do mkfix "$shape-$len-$n" "$shape" "$len" "$n" || { echo "mapdatasectioncheck: fixture generation failed"; exit 2; }; done
    done
done
mkfix S3-long-220 S3 long 220 && mkfix S4-long-220 S4 long 220 || { echo "mapdatasectioncheck: fixture generation failed"; exit 2; }
# (Z): the code file alone.
mkdir -p "$TMP/codeonly" && bash "$GEN" "$TMP/codeonly-src" S3 short 1 >/dev/null && cp "$TMP/codeonly-src/app.py" "$TMP/codeonly/" || exit 2

python3 - "$BIN" "$TMP" "${MAPSEC_EXTRA_ROOTS:-}" <<'PYEOF' || no "the arms above reported a failure (or the check body could not run)"
import html as htmlmod, json, os, re, shlex, subprocess, sys
BIN, TMP, EXTRA = sys.argv[1], sys.argv[2], sys.argv[3]
CODE = {"load", "parse", "normalize", "transform", "render", "save", "_helper", "main"}
fails = []
def ok(msg): print("  PASS  " + msg)
def no(msg): print("  FAIL  " + msg); fails.append(msg)

def run(d, *args):
    p = subprocess.run([BIN, d, "--no-cache", *args], capture_output=True, text=True)
    return p.stdout
def mcp(d, tool, k):
    msgs = [{"jsonrpc": "2.0", "id": 1, "method": "initialize"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": tool, "arguments": {"path": d}}}]
    p = subprocess.run([BIN, "--mcp", "--top-k=%d" % k], input="".join(json.dumps(m) + "\n" for m in msgs), capture_output=True, text=True)
    last = [l for l in p.stdout.splitlines() if l.strip()][-1]
    return json.loads(last)["result"]["content"][0]["text"]

ATTR_RE = re.compile(r'([A-Za-z_]+)="([^"]*)"')
class _Attr:
    @staticmethod
    def findall(s): return [(k, htmlmod.unescape(v)) for (k, v) in ATTR_RE.findall(s)]
ATTR = _Attr()
def strip_comments(t): return re.sub(r"<!--.*?-->", "", t, flags=re.S)
def xml_map(t):
    """root attrs + rows [(file, t, n, weight)] of an XML map document, in emission order."""
    body = strip_comments(t)
    m = re.search(r"<r(\s[^>]*)?>", body)
    root = dict(ATTR.findall(m.group(1) or "")) if m else {}
    rows, cur = [], None
    for tag in re.finditer(r"<(f|s)\s([^>]*)>", body[m.end():] if m else ""):
        a = dict(ATTR.findall(tag.group(2)))
        if tag.group(1) == "f": cur = a.get("p")
        else: rows.append((cur, a.get("t"), a.get("n"), int(a.get("overloads", "1"))))
    return root, rows
def json_map(t):
    o = json.loads(t)
    rows = [(f["p"], s.get("t"), s.get("n"), int(s.get("overloads", 1))) for f in o.get("r", []) for s in f.get("s", [])]
    return o, rows
def code_rows(rows): return len({n for (p, t, n, w) in rows if t == "fn" and n in CODE and p == "app.py"})
def sec_shown(rows): return sum(w for (p, t, n, w) in rows if t == "sec")
def sec_multiset(rows): return sorted((p, n) for (p, t, n, w) in rows if t == "sec" for _ in range(w))

def gq(d, *args):
    out = run(d, *args)
    m = re.search(r"<query\s([^>]*)>", out)
    a = dict(ATTR.findall(m.group(1))) if m else {}
    body = strip_comments(out)
    rows = []
    for s in re.finditer(r"<s\s([^>]*)/>", body):
        r = dict(ATTR.findall(s.group(1)))
        rows.append((r["p"].rsplit(":", 1)[0], r["n"]))
    return a, rows
def sections_all(d):
    a, _ = gq(d, "--graph-query=kind(all,sec)", "--limit=1")
    if "count" not in a:
        return None   # the Section query itself failed: no <query count=> root (a crash, a refusal, an empty stdout)
    count = int(a["count"])
    if count == 0: return 0, []
    _, rows = gq(d, "--graph-query=kind(all,sec)", "--limit=%d" % count)
    return count, sorted(rows)

def gate_d(label, d, root, rows, K, allsec):
    """Gate D on one map document (the code-first pick): data_sections_cut = the Sections the rank-order top-K would have
    kept minus those still shown (the rank order is graph-query's `all` listing, the same vector); the frozen next=
    spelling past the M shown; the walk (next=, then next_offset= until has_more="0") pages every unshown Section once,
    the swapped ones first, every page <= K rows."""
    count, full = allsec
    M = sec_shown(rows)
    _, topk = gq(d, "--graph-query=all", "--limit=%d" % K)
    secNames = {}
    for x in full: secNames[x] = secNames.get(x, 0) + 1
    wk = []
    pool = dict(secNames)
    for r in topk:
        if pool.get(r, 0) > 0: wk.append(r); pool[r] -= 1
    N = len(wk) - M
    got = root.get("data_sections_cut")
    if N <= 0:
        if got is None and "next" not in root: ok("%s: nothing swapped, no data_sections_cut= / next=" % label)
        else: no("%s: data_sections_cut=%s next=%s on a map that swapped nothing" % (label, got, root.get("next")))
        return
    if got != str(N):
        no("%s: data_sections_cut=%s, expected %d (= %d Sections in the rank-order top-%d - %d still shown)" % (label, got, N, len(wk), K, M)); return
    want = "--graph-query='kind(all,sec)' --offset=%d --limit=%d" % (M, K)
    if root.get("next") != want:
        no("%s: next=%r, expected %r" % (label, root.get("next"), want)); return
    paged, args, pages = [], shlex.split(want), 0
    while True:
        a, prow = gq(d, *args)
        pages += 1
        if len(prow) > K: no("%s: page %d holds %d rows > K=%d" % (label, pages, len(prow), K)); return
        paged += prow
        if a.get("has_more") != "1": break
        if pages > count + 2: no("%s: paging did not terminate" % label); return
        args = [x if not x.startswith("--offset=") else "--offset=" + a["next_offset"] for x in args]
    if sorted(paged + sec_multiset(rows)) != full:
        no("%s: the %d paged Sections + %d shown != the %d indexed (each once)" % (label, len(paged), M, count)); return
    swapped = sorted(wk[M:]) if sorted(wk[:M]) == sorted(sec_multiset(rows)) else None
    if swapped is None or sorted(paged[:N]) != swapped:
        no("%s: the first %d paged Sections are not the %d swapped out of the top-K" % (label, N, N)); return
    ok("%s: data_sections_cut=%d swapped; next= pages them first, then the rest, in %d page(s) of <= %d" % (label, N, pages, K))

def code_first(label, d, K):
    """The pick's invariant: a map that shows any Section shows every non-Section row."""
    S = int(json.loads(run(d, "--json", "--top-k=1"))["symbols"])
    _, allrows = json_map(run(d, "--json", "--top-k=%d" % S))
    total = sum(w for (p, t, n, w) in allrows if t != "sec")
    _, r = json_map(run(d, "--json", "--top-k=%d" % K))
    shownCode = sum(w for (p, t, n, w) in r if t != "sec")
    shownSec = sum(w for (p, t, n, w) in r if t == "sec")
    good = shownSec == 0 or shownCode == total
    (ok if good else no)("%s K=%d code-first: %d Section and %d of %d non-Section rows shown%s" % (label, K, shownSec, shownCode, total, "" if good else " — a Section rides while code is left out"))

print("== (P) code rows in the emitted top-K, (D) the disclosure, per cell ==")
cells = [(s, l, n) for s in ("S1", "S2", "S3", "S4") for l in ("long", "short") for n in (20, 40, 200)] + [("S3", "long", 220), ("S4", "long", 220)]
for (shape, ln, n) in cells:
    d = os.path.join(TMP, "%s-%s-%d" % (shape, ln, n))
    allsec = sections_all(d)
    if allsec is None:
        no("%s %s N=%d: the Section query (--graph-query='kind(all,sec)') returned no answer" % (shape, ln, n)); continue
    if allsec[0] == 0 and shape == "S1":
        # S1 is a db/schema.rb: only a build that indexes Rails schema tables as Sections (#339) has any to crowd code out
        print("  SKIP  %s %s N=%d: this build indexes no Section in the data file" % (shape, ln, n)); continue
    if allsec[0] == 0:
        # Markdown headings, YAML keys and JSON keys are always Sections: zero is an indexing regression, and every check
        # below would pass on a map with no Section in it
        no("%s %s N=%d: no Section indexed in the Markdown/YAML/JSON data file — the cell cannot test the pick" % (shape, ln, n)); continue
    for K in (200, 16):
        lab = "%s %s N=%d K=%d" % (shape, ln, n, K)
        xml = run(d, "--top-k=%d" % K)
        xroot, xrows = xml_map(xml)
        jo, jrows = json_map(run(d, "--json", "--top-k=%d" % K))
        html = run(d, "--html", "--top-k=%d" % K)
        hnames = {o["label"] for o in (json.loads(x) for x in re.findall(r'\{"id":\d+,"label":"[^"]*","type":"fn"[^}]*\}', html)) if o["label"] in CODE}
        tree = run(d, "--tree")
        tfile = re.search(r'<file p="([^"]*)"', strip_comments(tree))
        mt = run(d, "--max-tokens=1500", "--top-k=%d" % K)
        mroot, mrows = xml_map(mt)
        an = mcp(d, "analyze", K)
        aroot, arows = xml_map(an)
        rb = mcp(d, "rank_by", K)
        rroot, rrows = xml_map(rb)
        firsts = [m.start() for m in re.finditer(r'<s t="fn" n="(%s)"' % "|".join(sorted(CODE)), xml)]
        stat = dict(xml=code_rows(xrows), json=code_rows(jrows), html=len(hnames), maxtok=code_rows(mrows), mcp=code_rows(arows))
        print("CELL\t%s\t%s\t%d\t%d\txml=%d\tjson=%d\thtml=%d\ttree_first=%s\tmaxtok=%d\tmcp=%d\tbytes_first=%s\tbytes_8th=%s" % (
            shape, ln, n, K, stat["xml"], stat["json"], stat["html"], tfile.group(1) if tfile else "-", stat["maxtok"], stat["mcp"],
            firsts[0] if firsts else "-", firsts[7] if len(firsts) >= 8 else "-"))
        for surf, v in stat.items():
            (ok if v == 8 else no)("%s %s: %d/8 code rows" % (lab, surf, v))
        (ok if tfile and tfile.group(1) == "app.py" else no)("%s tree: code file listed first (%s)" % (lab, tfile.group(1) if tfile else "none"))
        gate_d(lab + " xml", d, xroot, xrows, K, allsec)
        mk = int(re.search(r"shown=(\d+)", mt).group(1))
        gate_d(lab + " max-tokens", d, mroot, mrows, mk if mk else K, allsec)
        for name, other in (("json", {k: str(v) for k, v in jo.items() if k in ("data_sections_cut", "next")}), ("mcp analyze", aroot), ("mcp rank_by", rroot)):
            pair = (other.get("data_sections_cut"), other.get("next"))
            (ok if pair == (xroot.get("data_sections_cut"), xroot.get("next")) else no)("%s %s: same data_sections_cut=/next= as the XML map %s" % (lab, name, pair))

print("== (C) code-first: a Section is shown only when every non-Section row is ==")
for c in ("S2-long-200", "S3-long-220", "S4-long-220", "S3-short-40"):
    for K in (16, 200):
        code_first(c, os.path.join(TMP, c), K)

print("== (L) legend: defined where it rides ==")
d = os.path.join(TMP, "S3-long-220")
full = run(d, "--legend=full")
compact = run(d, "--legend=compact")
(ok if "data_sections_cut=" in "".join(re.findall(r"<!--.*?-->", full, flags=re.S)) else no)("the full XML legend defines data_sections_cut=")
(ok if "data_sections_cut=" in "".join(re.findall(r"<!--.*?-->", compact, flags=re.S)) else no)("the compact legend defines data_sections_cut=")
helpall = subprocess.run([BIN, "--help=all"], capture_output=True, text=True).stdout
(ok if "data_sections_cut=" in helpall else no)("--help=all defines data_sections_cut=")

print("== (Z) a Section-free tree carries no disclosure ==")
z = run(os.path.join(TMP, "codeonly"))
(ok if "data_sections_cut" not in z and "kind(all,sec)" not in z else no)("code-only map: no data_sections_cut=, no Section next=, no legend clause")
zj = run(os.path.join(TMP, "codeonly"), "--json")
(ok if "data_sections_cut" not in zj else no)("code-only --json map: no data_sections_cut")

for extra in [x for x in EXTRA.split(":") if x]:
    print("== extra root %s ==" % extra)
    allsec = sections_all(extra)
    for K in (200, 16):
        r, rows = xml_map(run(extra, "--top-k=%d" % K))
        gate_d("%s K=%d xml" % (os.path.basename(extra), K), extra, r, rows, K, allsec)
        code_first(os.path.basename(extra), extra, K)

print("mapdatasectioncheck: %d failure(s)" % len(fails))
sys.exit(1 if fails else 0)
PYEOF
if [ "$fail" -ne 0 ]; then
    echo "mapdatasectioncheck: FAILURES ABOVE"
    exit 1
fi
echo "mapdatasectioncheck: all arms PASS"
exit 0
