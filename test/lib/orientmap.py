"""orientmap.py — the shared reader, classifier and oracle behind test/orientmapcheck.sh (the orient sections of the default
map: O1 <entry_points>, O2 <subsystems>, O2-overflow <overflow>, O3 utility_demoted=). Written BEFORE the code it measures.

The section schema this module reads (fixed by the gate, so the arm implements it, not the other way round):
  <entry_points shown= total= [capped= next=]> <e p="FILE:LINE" n="SYMBOL" why="bin|script|main|entry"/> ... </entry_points>
  <subsystems g="G" shown= total= capped= [next=]> <grp l="LABEL" n="N"> <m p="PATH"/> x <= 3 </grp> ... </subsystems>
  <overflow shown= total= capped= [next=]> <grp l="LABEL"> <m p="PATH"/> ... </grp> ... </overflow>
  utility_demoted="N" on ONE element of the answer, which carries its own next= when N > 0.
Labels: a child directory of G is "dir/"; a prefix group in G is "prefix"; outside G, a top-level directory is "/top/"
and a root file's prefix is "/prefix". <m p=> is relative to G, or repo-relative with a leading "/" outside G. <e p=> is
repo-relative. JSON mirrors the XML one to one: the three section keys hold their attributes plus one array per child tag.

A next= value is argv appended to `BIN ROOT --no-cache`; its answer pages with has_more="1"/next_offset= (pasted as
--offset=) until has_more is absent or "0". Page rows: elements with p= (file pages), l= (group pages), why= (entry
pages); a page root's g= relativises its p= exactly as <subsystems g=> does.

The classifier mirrors BASE's src/filter.h (pathTierOf, isDemoOrGeneratedPath) and docparse.h's prose extensions; the
oracle is the registered rule (G descent at 2/3 of core mass, groups, order, breadth-first overflow). Masses come from
the map's k= (4 dp), so every comparison carries a worst-case rounding interval; a comparison the interval cannot decide
is counted as AMBIGUOUS, never guessed."""
import html, json, os, re, shlex, subprocess

SECTION_TAGS = ("entry_points", "subsystems", "overflow")
NEW_TAGS = SECTION_TAGS + ("e", "grp", "m")
WHY = ("bin", "script", "main", "entry")
VENDOR_SEGS = ("vendor/", "vendored/", "third_party/", "thirdparty/", "external/", "extern/", "deps/", "compat/")
DEMO_SEGS = ("present/", "docs/captures/", "static/", "locale/", "min/", ".yarn/releases/")
DOC_EXTS = (".adoc", ".markdown", ".md", ".mdx", ".org", ".rst", ".tsv", ".txt", ".ipynb", ".html", ".htm", ".csv",
            ".pdf", ".docx", ".pptx", ".xlsx")
NONCODE_KINDS = ("sec", "modscope")
OVERFLOW_CAP = 2048
SECTIONS_CAP = 4096
START_CAP = 1024
ROUND = 5e-5          # k= prints 4 dp
ALL = "--top-k=100000000"

COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
TAG_RE = re.compile(r'<(/?)([A-Za-z_][\w-]*)((?:\s+[\w:-]+="[^"]*")*)\s*(/?)>')
ATTR_RE = re.compile(r'([\w:-]+)="([^"]*)"')


def attrs(s):
    return {k: html.unescape(v) for k, v in ATTR_RE.findall(s)}


def blank(doc):
    """comments and CDATA replaced by spaces of the same length, so offsets survive"""
    return re.sub(r"<!--.*?-->|<!\[CDATA\[.*?\]\]>", lambda m: " " * len(m.group(0)), doc, flags=re.S)


def legend(doc):
    return "".join(COMMENT_RE.findall(doc))


class Node:
    """one element: tag, attribute dict a, byte span [start, end), child Nodes"""
    def __init__(self, tag, a, start):
        self.tag = tag
        self.a = a
        self.start = self.end = start
        self.kids = []

    def find(self, tag):
        return [k for k in self.kids if k.tag == tag]


def tree(doc):
    """every element of doc (comments/CDATA blanked) as a forest of Nodes with byte offsets"""
    b = blank(doc)
    roots, stack = [], []
    for m in TAG_RE.finditer(b):
        close, tag, at, selfc = m.group(1), m.group(2), m.group(3), m.group(4)
        if close:
            while stack:
                n = stack.pop()
                n.end = m.end()
                if n.tag == tag:
                    break
            continue
        n = Node(tag, attrs(at), m.start())
        (stack[-1].kids if stack else roots).append(n)
        if selfc:
            n.end = m.end()
        else:
            stack.append(n)
    return roots


def walk(nodes):
    for n in nodes:
        yield n
        yield from walk(n.kids)


def region(doc):
    """(start, end) of the bytes from the first section tag through the end of the last one; None when absent"""
    secs = [n for n in walk(tree(doc)) if n.tag in SECTION_TAGS]
    if not secs:
        return None
    return min(n.start for n in secs), max(n.end for n in secs)


def sections(doc):
    """{tag: Node} for the three sections (absent ones missing), plus the utility_demoted carrier under 'demoted'"""
    out = {}
    for n in walk(tree(doc)):
        if n.tag in SECTION_TAGS and n.tag not in out:
            out[n.tag] = n
        if "utility_demoted" in n.a and "demoted" not in out:
            out["demoted"] = n
    return out


def unrel(p, g):
    return p[1:] if p.startswith("/") else (g or "") + p


# ── running the binary ──────────────────────────────────────────────────────────────────────────────────────────────
def run(BIN, root, *args, env=None):
    e = dict(os.environ)
    e.update(env or {})
    p = subprocess.run([BIN, root, "--no-cache", *args], capture_output=True, env=e, timeout=3600)
    return p.stdout.decode("utf-8", "replace"), p.returncode


def mcp(BIN, path, calls, ref=False, env=None):
    msgs = [{"jsonrpc": "2.0", "id": 1, "method": "initialize"}]
    if ref:
        msgs.append({"jsonrpc": "2.0", "id": 9, "method": "resources/read", "params": {"uri": "ripwire://legend-dict"}})
    for i, (tool, a) in enumerate(calls):
        aa = dict(path=path)
        aa.update(a)
        msgs.append({"jsonrpc": "2.0", "id": 100 + i, "method": "tools/call", "params": {"name": tool, "arguments": aa}})
    e = dict(os.environ)
    e.update(env or {})
    p = subprocess.run([BIN, "--mcp"], input="".join(json.dumps(m) + "\n" for m in msgs).encode(), capture_output=True,
                       env=e, timeout=3600)
    res = {}
    for line in p.stdout.decode("utf-8", "replace").splitlines():
        try:
            j = json.loads(line)
        except ValueError:
            continue
        if isinstance(j.get("id"), int) and j["id"] >= 100:
            r = j.get("result")
            res[j["id"]] = r["content"][0]["text"] if r else "ERROR " + json.dumps(j.get("error"))
    return [res.get(100 + i, "") for i in range(len(calls))]


PAGE_K = 200        # the map's default top-K: no follow-up page may carry more rows
MAX_PAGES = 2000


def follow(BIN, root, nxt, rowattr, env=None):
    """walk next= and then next_offset= to the end. Returns (rows, problems): rows in page order as attribute dicts
    (p= already made repo-relative), problems a list of strings (a page over K rows, a refusal, a loop)."""
    rows, probs, args, seen = [], [], shlex.split(nxt), set()
    for _ in range(MAX_PAGES):
        key = tuple(args)
        if key in seen:
            probs.append("next_offset loops at %s" % " ".join(args))
            break
        seen.add(key)
        doc, rc = run(BIN, root, *args, env=env)
        if rc != 0:
            probs.append("follow-up %s exits %d" % (" ".join(args), rc))
            break
        forest = tree(doc)
        if not forest:
            probs.append("follow-up %s returns no element" % " ".join(args))
            break
        top = forest[0]
        g = top.a.get("g")
        page = [dict(n.a) for n in walk(top.kids) if rowattr in n.a]
        for r in page:
            if "p" in r and rowattr == "p":
                r["p"] = unrel(r["p"], g)
        lim = min(PAGE_K, int(top.a["limit"])) if top.a.get("limit", "").isdigit() else PAGE_K
        if len(page) > lim:
            probs.append("a page of %d rows > K=%d" % (len(page), lim))
        rows += page
        if top.a.get("has_more") != "1":
            break
        if "next_offset" not in top.a:
            probs.append("has_more=1 without next_offset=")
            break
        args = [x for x in args if not x.startswith("--offset=")] + ["--offset=" + top.a["next_offset"]]
    else:
        probs.append("more than %d pages" % MAX_PAGES)
    return rows, probs


# ── the BASE classifier (src/filter.h, src/docparse.h) ─────────────────────────────────────────────────────────────
def has_seg(p, seg):
    i = p.find(seg)
    while i != -1:
        if i == 0 or p[i - 1] == "/":
            return True
        i = p.find(seg, i + 1)
    return False


def is_test_path(p):
    if any(has_seg(p, s) for s in ("test/", "tests/", "__tests__/")):
        return True
    fn = p.rsplit("/", 1)[-1]
    return fn.startswith("test_") or any(m in fn for m in ("_test.", ".test.", "_spec.", ".spec."))


def tier(p):
    dot = p.rfind(".")
    if dot != -1 and p[dot:].lower() in DOC_EXTS:
        return "doc"
    if is_test_path(p) or any(has_seg(p, s) for s in ("bench/", "benches/", "fixture/", "fixtures/", "testdata/")):
        return "test"
    return "source"


def is_demo(p):
    if any(has_seg(p, s) for s in DEMO_SEGS):
        return True
    fn = p.rsplit("/", 1)[-1]
    if fn in (".pnp.cjs", ".pnp.loader.mjs"):
        return True
    d = len(fn) - len(fn.lstrip("0123456789"))
    return has_seg(p, "migrations/") and d >= 2 and d < len(fn) and fn[d] == "_"


def is_vendored(p):
    return any(has_seg(p, s) for s in VENDOR_SEGS)


def inventory(BIN, root):
    """{path: set(kinds)} for every indexed file, from an out-of-scope listing (--rank-by=authority, Gate S-pinned)"""
    doc, rc = run(BIN, root, "--json", "--rank-by=authority", ALL)
    j = json.loads(doc)
    inv = {}
    for f in j.get("r", []):
        inv.setdefault(f["p"], set()).update(s["t"] for s in f.get("s", []))
    return inv, j


def masses(BIN, root):
    """{path: (mid, half)} from the default map's k= over every symbol (the BASE rank vector, untouched by O)"""
    doc, rc = run(BIN, root, "--json", ALL)
    j = json.loads(doc)
    out = {}
    for f in j.get("r", []):
        mid = half = 0.0
        for s in f.get("s", []):
            v, ov = float(s.get("k", 0.0)), int(s.get("overloads", 1))
            mid += v * ov                       # a merged row prints its representative's k=: the others are approximated
            half += ROUND * ov + v * (ov - 1)   # by it, and the interval widens by their whole value
        out[f["p"]] = (mid, half)
    return out, j


def core_candidates(inv):
    """files with a code symbol, Source tier, not demo/generated — before O3"""
    return sorted(p for p, k in inv.items() if (k - set(NONCODE_KINDS)) and tier(p) == "source" and not is_demo(p))


# ── the oracle ──────────────────────────────────────────────────────────────────────────────────────────────────────
def prefix(base):
    stem = base.rsplit(".", 1)[0] if "." in base else base
    s = stem.lstrip("_").lower()
    cut = min([i for i in (s.find("-"), s.find("_")) if i != -1] or [len(s)])
    return s[:cut] or stem.lower()


class Order:
    """sort by (-mass, key) and count adjacent comparisons the rounding interval cannot decide"""
    def __init__(self):
        self.ambiguous = []

    def sort(self, items, what):
        # items: [(key, mid, half)]
        s = sorted(items, key=lambda x: (-x[1], x[0]))
        for a, b in zip(s, s[1:]):
            if abs(a[1] - b[1]) <= a[2] + b[2] and a[1] != b[1]:
                self.ambiguous.append("%s: %s %.5f+-%.5f vs %s %.5f+-%.5f" % (what, a[0], a[1], a[2], b[0], b[1], b[2]))
        return [x[0] for x in s]


def grouping_root(core, m, od):
    """descend from the root while one child directory holds >= 2/3 of the core mass under G"""
    G = ""
    while True:
        under = [p for p in core if p.startswith(G)]
        tot = sum(m[p][0] for p in under)
        tot_half = sum(m[p][1] for p in under)
        kids = {}
        for p in under:
            rest = p[len(G):]
            if "/" in rest:
                c = rest.split("/", 1)[0]
                mid, half = kids.get(c, (0.0, 0.0))
                kids[c] = (mid + m[p][0], half + m[p][1])
        for c, (mid, half) in kids.items():
            if (mid - half >= (tot + tot_half) * 2 / 3) != (mid + half >= (tot - tot_half) * 2 / 3):
                od.ambiguous.append("G descent at %r: child %s holds %.5f+-%.5f of %.5f+-%.5f" % (G, c, mid, half, tot, tot_half))
        hit = sorted(c for c, (mid, half) in kids.items() if mid >= tot * 2.0 / 3.0)
        if not hit:
            return G
        G += hit[0] + "/"


def group_label(p, G, childdirs, topdirs):
    if p.startswith(G):
        rest = p[len(G):]
        if "/" in rest:
            return rest.split("/", 1)[0] + "/"
        pre = prefix(rest)
        return pre + "/" if pre in childdirs else pre
    if "/" in p:
        return "/" + p.split("/", 1)[0] + "/"
    pre = prefix(p)
    return "/" + pre + "/" if pre in topdirs else "/" + pre


def breadth_first(order, members):
    """every core file not in a shown group row's top 3: each round j takes every group's j-th member, groups in order"""
    named = {p for lab in order[:12] for p in members[lab][:3]}
    ranked = []
    for j in range(max((len(v) for v in members.values()), default=0)):
        ranked += [(lab, members[lab][j]) for lab in order if j < len(members[lab]) and members[lab][j] not in named]
    return named, ranked


def oracle(core, mass):
    """core: list of repo-relative paths; mass: {path: (mid, half)}. Returns dict(G, order=[labels], members={label:[paths]},
    ranked=[(label, path)] (the breadth-first overflow order), named=set(top-3 of the first 12), ambiguous=[...])"""
    od = Order()
    m = {p: mass.get(p, (0.0, ROUND)) for p in core}
    G = grouping_root(core, m, od)
    childdirs = {p[len(G):].split("/", 1)[0] for p in core if p.startswith(G) and "/" in p[len(G):]}
    topdirs = {p.split("/", 1)[0] for p in core if not p.startswith(G) and "/" in p}
    groups = {}
    for p in core:
        groups.setdefault(group_label(p, G, childdirs, topdirs), []).append(p)
    gm = [(lab, sum(m[p][0] for p in ps), sum(m[p][1] for p in ps)) for lab, ps in groups.items()]
    order = od.sort(gm, "group order")
    members = {lab: od.sort([(p, m[p][0], m[p][1]) for p in groups[lab]], "members of " + lab) for lab in order}
    named, ranked = breadth_first(order, members)
    return dict(G=G, order=order, members=members, named=named, ranked=ranked, ambiguous=od.ambiguous)


def printed(p, G):
    return p[len(G):] if p.startswith(G) else "/" + p
