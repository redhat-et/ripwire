#!/usr/bin/env python3
"""sectionpos.py -- where does a `--for` answer put the SECTION that holds the required evidence?

The instrument of docs/EVALS.md "ITEM ST" (section-before-tail, 2026-11-17). An ANSWER-QUALITY instrument: it
measures where the evidence sits, never how many bytes the answer has (a permutation has the same bytes).

GRAINS, kept apart in every line this prints -- pooling them is a known error in this project:
  STRICT ITEM   one rubric item R<n> is LOCATED by a claim (file, line) in the item's file within +-3 lines of a
                manifest location. The claim rule is ITEM RD's (bench/rankpos/firstpos.py), reproduced here so
                each claim also carries its byte offset and its top-level section: one XML start tag carrying a
                path that resolves in the pinned checkout (exactly, or by a UNIQUE suffix) and a line. ripwire's
                disclaimed surfaces yield NO claim: comments, <dc>/<skip>/<tail>/<inv>/<t>, next=/sigs_next=/task=.
  LENIENT ITEM  one rubric item is DELIVERED at the first byte where its primary path or one of its terms (>= 4
                characters) appears ANYWHERE in the answer -- <tail> pointer rows and the echoed question
                included. This is the grain on which whole-tail-last was registered as a null (amendment 8).

  sectionpos.py collect BIN OUTDIR dev|fresh|all [--flag ...]   run BIN <repo> --for=<Q> and --for=<SUBJECT> per cell
  sectionpos.py permute SRC DST dev|fresh|all VARIANT           offline permutation of stored answers (a prediction, not a build)
  sectionpos.py census OUTDIR dev|fresh|all                     section order against <tail>; <tail> share; gold-free
  sectionpos.py report OUTDIR dev|fresh|all [OUT.json]          the distributions, never a mean
  sectionpos.py compare BASE.json AFTER.json                    paired, per wording
  sectionpos.py prefix OUTDIR dev|fresh|all [BYTES]             disclosure attributes inside the reading prefix
  sectionpos.py selftest                                        the mutation controls; exit 1 if one stays green

VARIANT: tail-last (every row block printed after <tail> moves ahead of it) | evidence (only the line-carrying
task sections move) | sigs-last (control: those sections ahead of <sigs>).

The corpus is local and unpublished (ST_WORK): the gold files, the mechanical location manifest and the
checkouts. Records no time and no memory. Sealed corpora are refused by name."""
import collections, html, json, os, re, subprocess, sys

WORK = os.environ.get("ST_WORK", "")
SEALED = {"helix", "waybar", "handlebars"}
MANIFEST = "results/ITEM_GRAIN_PEER_GRADER_1117/item_manifest_probe_MECHANICAL_NOT_GOLD.json"
GOLD_DIRS = ["orch/tmp/table/large-dev/gold/gold", "orch/tmp/table/large-dev/gold-b/gold", "orch/tmp/table/large-dev-2/gold",
             "orch/tmp/table/mf1-dev-2/gold", "orch/tmp/gr1/mf1-gold-dev-amended/gold"]
# DEV = every repo holding a cell the section finding was read from (ITEM RD's DEV split, the 72 cells its
# "12 of 33" came from); FRESH = the repo-disjoint rest. The split is ITEM RD's, unchanged, so it was fixed
# before this band existed.
DEV_REPOS = {"axum", "envoy", "tmux", "django", "vscode", "cockroach", "ninja", "pydantic", "mdbook"}
KS = (10, 20, 40)
BUDGETS = (4096, 8192, 16384, 32768)
DELTA = 3
MIN_ANCHOR = 4
# The sections ITEM ST moves ahead of <tail>: each prints rows that carry a LINE. <tail> prints file pointers.
EVIDENCE = ("ep", "hops", "bodies", "fold", "reexports", "shortkey", "syms", "lit", "callers", "decl_rows", "graph_verb",
            "selfhooks", "dotted_strings", "doc_body", "exemplar_family", "listed", "dispatch")
DISCLOSURE = re.compile(r'\b(capped|counts_floor|shown|total|has_more|next|root|[a-z_]+_capped|ambiguous|coverage|confidence)="')
_man = None
_files = {}


def need_work():
    if not WORK:
        raise SystemExit("ST_WORK is not set: name the directory holding repos/, results/ and orch/")


def manifest():
    global _man
    if _man is None:
        need_work()
        _man = json.load(open(f"{WORK}/{MANIFEST}"))
    return _man


def gold(qid):
    for d in GOLD_DIRS:
        p = f"{WORK}/{d}/{qid}.txt"
        if os.path.exists(p):
            f = {"items": {}}
            for ln in open(p, encoding="utf-8", errors="replace"):
                parts = ln.rstrip("\n").split("\t")
                if parts[0] in ("SUBJECT", "Q") and len(parts) > 1:
                    f[parts[0]] = "\t".join(parts[1:])
                elif re.fullmatch(r"R\d+", parts[0]):
                    anchors = []
                    for fld in parts[1:]:
                        if fld.startswith("primary="):
                            anchors.append(fld[len("primary="):].strip())
                        elif fld.startswith("terms="):
                            anchors += [x.strip() for x in fld[len("terms="):].split(",")]
                    f["items"][parts[0]] = [a for a in anchors if len(a) >= MIN_ANCHOR]
            return f
    return {"items": {}}


def cells(which):
    out = []
    for qid in sorted(manifest()):
        m = manifest()[qid]
        repo = m["repo"]
        if repo.lower() in SEALED:
            raise SystemExit(f"sealed corpus named in the manifest: {repo}")
        req = [r for r in m["req"] if m["items"][r]["locs"]]
        if not req or not os.path.isdir(f"{WORK}/repos/{repo}"):
            continue
        split = "dev" if repo in DEV_REPOS else "fresh"
        if which in ("all", split):
            out.append((qid, repo, split, req))
    return out


def repo_files(repo):
    if repo.lower() in SEALED:
        raise SystemExit(f"sealed corpus: {repo}")
    if repo not in _files:
        ls = subprocess.run(["git", "-C", f"{WORK}/repos/{repo}", "ls-files"], capture_output=True, text=True).stdout.split("\n")
        fs = [f for f in ls if f]
        suf = collections.defaultdict(list)
        for f in fs:
            parts = f.split("/")
            for i in range(len(parts)):
                suf["/".join(parts[i:])].append(f)
        _files[repo] = (set(fs), suf)
    return _files[repo]


def resolve(repo, p, files=None):
    fs, suf = files if files is not None else repo_files(repo)
    p = p.strip().strip('"\'`()[],;')
    if p.startswith("./"):
        p = p[2:]
    if p in fs:
        return p
    c = suf.get(p)
    return c[0] if c and len(c) == 1 else None   # an ambiguous suffix is not a claim


# ---- the block scanner: top-level children of the root, hand-rolled because bodies arrive in CDATA ----
def blocks(doc):
    """-> (root open tag end, [(kind, name, begin, end)], close offset); None when the shape is not understood."""
    m = re.search(r"<([A-Za-z_][A-Za-z0-9_-]*)\b[^>]*>", doc)
    if not m:
        return None
    i, close = m.end(), doc.rfind("</%s>" % m.group(1))
    if close < i:
        return None
    out, depth, start, kind = [], 0, None, None
    while i < close:
        if doc.startswith("<!--", i):
            j = doc.find("-->", i)
            if j < 0:
                return None
            if depth == 0:
                out.append(("comment", None, i, j + 3))
            i = j + 3
        elif doc.startswith("<![CDATA[", i):
            j = doc.find("]]>", i)
            if j < 0:
                return None
            i = j + 3
        elif doc.startswith("</", i):
            j = doc.find(">", i)
            depth -= 1
            if depth == 0:
                out.append(("element", kind, start, j + 1))
            i = j + 1
        elif doc[i] == "<":
            j = doc.find(">", i)
            nm = re.match(r"<([A-Za-z_][A-Za-z0-9_-]*)", doc[i:j + 1]).group(1)
            selfclose = doc[j - 1] == "/"
            if depth == 0:
                if selfclose:
                    out.append(("element", nm, i, j + 1))
                else:
                    start, kind = i, nm
            if not selfclose:
                depth += 1
            i = j + 1
        else:
            i += 1
    return (m.end(), out, close) if depth == 0 else None


def owner_of(doc, bs, k):
    """The row block a comment DECLARES (its first word names the next element), else None: the document legend."""
    w = re.match(r"<!--\s*([A-Za-z0-9_-]+)", doc[bs[k][2]:bs[k][3]])
    for j in range(k + 1, len(bs)):
        if bs[j][0] == "comment":
            continue
        return j if w and w.group(1) == bs[j][1] else None
    return None


def permute(doc, variant):
    """A PERMUTATION of top-level blocks; returns doc unchanged when nothing moves or the shape is unknown."""
    sc = blocks(doc)
    if sc is None:
        return doc
    head, bs, close = sc
    owner = [owner_of(doc, bs, k) if b[0] == "comment" else None for k, b in enumerate(bs)]
    elems = [k for k, b in enumerate(bs) if b[0] == "element"]
    names = [bs[k][1] for k in elems]
    if "tail" not in names:
        return doc
    tail = elems[names.index("tail")]
    after = [k for k in elems if k > tail]
    if variant == "tail-last":
        moved = after
    elif variant in ("evidence", "sigs-last"):
        moved = [k for k in after if bs[k][1] in EVIDENCE]
    else:
        raise SystemExit(f"unknown variant {variant}")
    if not moved:
        return doc
    anchor = tail
    if variant == "sigs-last" and "sigs" in names:
        anchor = elems[names.index("sigs")]
    order = []
    def emit(k):
        order.extend(c for c in range(len(bs)) if owner[c] == k)
        order.append(k)
    for k, b in enumerate(bs):
        if b[0] == "comment":
            if owner[k] is None:
                order.append(k)       # a document legend keeps its place among the unmoved blocks
            continue
        if k in moved:
            continue
        if k == anchor:
            for mk in moved:
                emit(mk)
        emit(k)
    out = doc[:head] + "".join(doc[bs[k][2]:bs[k][3]] for k in order) + doc[close:]
    assert len(out) == len(doc) and sorted(order) == list(range(len(bs))), "not a permutation"
    return out


# ---- claims, with the byte offset and the top-level section of each ----
PATH = r'(?:/?[\w@+.\[\]-]+/)*[\w@+.\[\]-]+\.[A-Za-z0-9_]{1,8}'
P_COLON = re.compile(r'(?<![\w/.-])(' + PATH + r')(?::|#)L?(\d+)')
P_PATH = re.compile(r'(?<![\w/.-])(' + PATH + r')(?![\w/])')
P_LINEKEY = re.compile(r'(?:\bl="|\bloc=L?|\bline[_ ]?(?:start)?"?\s*[:=]?\s*L?|\blines?\s+L?)(\d+)', re.I)
DISCLAIM_ELEMS = ("dc", "skip", "tail", "inv", "t")
DISCLAIM_ATTRS = re.compile(r'\b(?:next|sigs_next|task)="[^"]*"')
UNIT = re.compile(r'<[A-Za-z_][\w]*\b')


def blank(text, rx):
    return rx.sub(lambda m: " " * len(m.group(0)), text)


def masked(text):
    """The answer with every disclaimed surface blanked IN PLACE, so offsets survive."""
    text = blank(text, re.compile(r'<!--.*?-->', re.S))
    text = blank(text, DISCLAIM_ATTRS)
    for e in DISCLAIM_ELEMS:
        text = blank(text, re.compile(r'<' + e + r'\b[^>]*/>'))
        text = blank(text, re.compile(r'<' + e + r'\b[^>]*>.*?</' + e + r'>', re.S))
    return text


def claims(repo, text, files=None):
    """-> [(file, line, char offset, section)] in document order, first appearance of each (file, line)."""
    sc = blocks(text)
    spans = [(b[2], b[3], b[1]) for b in sc[1] if b[0] == "element"] if sc else []
    def section(off):
        for a, b, n in spans:
            if a <= off < b:
                return n
        return "(root)"
    mk = masked(text)
    cuts = [m.start() for m in UNIT.finditer(mk)] + [len(mk)]
    out, seen = [], set()
    for a, b in zip([0] + cuts, cuts):
        for raw in mk[a:b].split("\n"):
            u = html.unescape(raw)
            got = []
            for m in P_COLON.finditer(u):
                f = resolve(repo, m.group(1), files)
                if f:
                    got.append((f, int(m.group(2))))
            if not got:
                lk = P_LINEKEY.search(u)
                if lk:
                    for m in P_PATH.finditer(u):
                        f = resolve(repo, m.group(1), files)
                        if f:
                            got.append((f, int(lk.group(1))))
                            break
            for c in got:
                if c not in seen:
                    seen.add(c)
                    out.append((c[0], c[1], a, section(a)))
    return out


def byte_off(text, char_off):
    return len(text[:char_off].encode("utf-8", errors="replace"))


def grade_text(repo, text, items, req, anchors, files=None):
    cl = claims(repo, text, files)
    pos, off, sec = {}, {}, {}
    for r in req:
        locs = [tuple(x) for x in items[r]["locs"]]
        hit = next(((i, c) for i, c in enumerate(cl) if any(c[0] == gf and abs(c[1] - gl) <= DELTA for gf, gl in locs)), None)
        pos[r] = hit[0] + 1 if hit else None
        off[r] = byte_off(text, hit[1][2]) if hit else None
        sec[r] = hit[1][3] if hit else None
    located = [r for r in req if pos[r]]
    first = min(located, key=lambda r: pos[r]) if located else None
    len_off = {}
    for r, an in anchors.items():
        at = [text.find(a) for a in an]
        at = [x for x in at if x >= 0]
        len_off[r] = byte_off(text, min(at)) if at else None
    lfound = [v for v in len_off.values() if v is not None]
    sc = blocks(text)
    tail = next(((b[2], b[3]) for b in sc[1] if b[0] == "element" and b[1] == "tail"), None) if sc else None
    return {"state": "VALUE" if cl else "ANSWERED_UNLOCATED", "claims": len(cl), "bytes": len(text.encode("utf-8", errors="replace")),
            "pos": pos, "off": off, "sec": sec, "first": pos[first] if first else None, "first_off": min(off[r] for r in located) if located else None,
            "first_sec": sec[first] if first else None, "nreq": len(req),
            "len_first": min(lfound) if lfound else None, "len_all": max(lfound) if lfound else None, "len_found": len(lfound),
            "tail_bytes": byte_off(text, tail[1]) - byte_off(text, tail[0]) if tail else 0,
            "order": [b[1] for b in sc[1] if b[0] == "element"] if sc else None}


def read_cell(outdir, qid, w):
    o = f"{outdir}/{qid}.{w}.xml"
    if not os.path.exists(o):
        return None, None          # ABSENT: never a zero
    rc = open(o + ".rc").read().strip() if os.path.exists(o + ".rc") else "?"
    return rc, open(o, encoding="utf-8", errors="replace").read()


def grade(outdir, which):
    rows = {}
    for qid, repo, split, req in cells(which):
        for w in ("Q", "SUBJECT"):
            rc, text = read_cell(outdir, qid, w)
            if rc is None:
                continue
            if rc != "0" or "<ctx" not in text:
                rows[f"{qid}|{w}"] = {"split": split, "state": "UNREACHABLE", "rc": rc}
                continue
            row = grade_text(repo, text, manifest()[qid]["items"], req, gold(qid)["items"])
            row["split"] = split
            rows[f"{qid}|{w}"] = row
    return rows


def collect(binp, outdir, which, flags):
    os.makedirs(outdir, exist_ok=True)
    for qid, repo, _split, _req in cells(which):
        g = gold(qid)
        for w in ("Q", "SUBJECT"):
            o = f"{outdir}/{qid}.{w}.xml"
            if w not in g or (os.path.exists(o) and os.path.getsize(o) > 0):
                continue
            try:
                r = subprocess.run([binp, f"{WORK}/repos/{repo}", f"--for={g[w]}"] + flags, capture_output=True, timeout=1800)
                rc, data = r.returncode, r.stdout
            except subprocess.TimeoutExpired:
                rc, data = 124, b""
            open(o, "wb").write(data)
            open(o + ".rc", "w").write(str(rc))
            print(qid, w, rc, len(data), flush=True)


def permute_dir(src, dst, which, variant):
    os.makedirs(dst, exist_ok=True)
    moved = n = 0
    for qid, _repo, _split, _req in cells(which):
        for w in ("Q", "SUBJECT"):
            rc, text = read_cell(src, qid, w)
            if rc is None:
                continue
            out = permute(text, variant) if rc == "0" else text
            n += 1
            moved += out != text
            open(f"{dst}/{qid}.{w}.xml", "w", encoding="utf-8", errors="replace").write(out)
            open(f"{dst}/{qid}.{w}.xml.rc", "w").write(rc)
    print(f"permute {variant}: {moved} of {n} answers reordered (offline prediction, not a build)")


def quantiles(vals):
    v = sorted(vals)
    if not v:
        return "n=0"
    q = lambda p: v[min(len(v) - 1, int(p * len(v)))]
    return f"n={len(v)} min {v[0]} p25 {q(.25)} p50 {q(.5)} p75 {q(.75)} p90 {q(.9)} max {v[-1]}"


BIN_EDGES = ((5, '1-5'), (10, '6-10'), (20, '11-20'), (40, '21-40'))


def bins(vals):
    b = collections.Counter(('never' if not v else next((n for e, n in BIN_EDGES if v <= e), '>40')) for v in vals)
    return "  ".join(f"{k}: {b[k]}" for k in ('1-5', '6-10', '11-20', '21-40', '>40', 'never'))


def byte_bins(vals):
    out = []
    for B in BUDGETS:
        out.append(f"<={B // 1024}KB: {sum(1 for v in vals if v is not None and v < B)}")
    out.append(f"later: {sum(1 for v in vals if v is not None and v >= BUDGETS[-1])}")
    out.append(f"never: {sum(1 for v in vals if v is None)}")
    return "  ".join(out)


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    h = z * ((p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5)
    return (100 * (c - h) / d, 100 * (c + h) / d)


def report(rows, which):
    for w in ("Q", "SUBJECT"):
        rs = {k: v for k, v in rows.items() if k.endswith("|" + w)}
        val = [v for v in rs.values() if v["state"] == "VALUE"]
        other = collections.Counter(v["state"] for v in rs.values() if v["state"] != "VALUE")
        print(f"{which} wording={w}: cells={len(rs)} VALUE={len(val)} other={dict(other)} bytes={sum(v['bytes'] for v in val)}")
        print(f"   STRICT ITEM, CELL first-required CLAIM position   {bins([v['first'] for v in val])}")
        k = sum(1 for v in val if v["first"] and v["first"] <= 20)
        print(f"   STRICT ITEM, within K=20 claims: {k} of {len(val)}  (Wilson 95 % {wilson(k, len(val))[0]:.1f}-{wilson(k, len(val))[1]:.1f})")
        print(f"   STRICT ITEM, CELL first-required BYTE offset      {byte_bins([v['first_off'] for v in val])}")
        print(f"      located cells only: {quantiles([v['first_off'] for v in val if v['first_off'] is not None])}")
        for B in (8192, 16384):
            k = sum(1 for v in val if v["first_off"] is not None and v["first_off"] < B)
            print(f"      within {B} B: {k} of {len(val)}  (Wilson 95 % {wilson(k, len(val))[0]:.1f}-{wilson(k, len(val))[1]:.1f})")
        items = [o for v in val for o in v["off"].values()]
        print(f"   STRICT ITEM, each required ITEM (n={len(items)}) BYTE offset   {byte_bins(items)}")
        fs = collections.Counter(v["first_sec"] or "never" for v in val)
        print(f"   STRICT ITEM, section carrying the first located required item: {sorted(fs.items(), key=lambda x: -x[1])}")
        print(f"   LENIENT ITEM (anchor anywhere, <tail> included), bytes to the FIRST delivered item: {byte_bins([v['len_first'] for v in val])}")
        print(f"   LENIENT ITEM, bytes until every item the answer ever delivers is delivered:        {byte_bins([v['len_all'] for v in val])}")
        print(f"      {quantiles([v['len_all'] for v in val if v['len_all'] is not None])}")


def compare(b, a):
    rc = 0
    for w in ("Q", "SUBJECT"):
        keys = sorted(k for k in b if k.endswith("|" + w))
        if sorted(k for k in a if k.endswith("|" + w)) != keys:
            print(f"wording={w}: the two arms hold DIFFERENT cell sets -- refusing to print a paired figure")
            rc = 1
            continue
        pair = [k for k in keys if b[k]["state"] == "VALUE" and a[k]["state"] == "VALUE"]
        print(f"wording={w}: paired cells n={len(pair)} of {len(keys)}; bytes {sum(b[k]['bytes'] for k in pair)} -> {sum(a[k]['bytes'] for k in pair)};"
              f" answers whose section order changed: {sum(1 for k in pair if b[k]['order'] != a[k]['order'])}")
        chg = [(k, b[k]["first"], a[k]["first"]) for k in pair if b[k]["first"] != a[k]["first"]]
        print(f"   STRICT ITEM claim position of the first required item: changed on {len(chg)} cells {chg[:12]}")
        ichg = sum(1 for k in pair for r in b[k]["pos"] if b[k]["pos"][r] != a[k]["pos"].get(r))
        print(f"   STRICT ITEM claim position, each required item: changed on {ichg} items")
        lost = [k for k in pair if sum(1 for p in b[k]["pos"].values() if p) > sum(1 for p in a[k]["pos"].values() if p)]
        print(f"   STRICT ITEM located-item count fell on {len(lost)} cells {lost[:8]}  (a permutation must leave this 0)")
        for name, key in (("STRICT ITEM first-required BYTE offset", "first_off"), ("LENIENT ITEM bytes to FIRST delivered item", "len_first"),
                          ("LENIENT ITEM bytes until every delivered item", "len_all")):
            ok = [k for k in pair if b[k][key] is not None and a[k][key] is not None]
            earlier = [(k, b[k][key], a[k][key]) for k in ok if a[k][key] < b[k][key]]
            later = [(k, b[k][key], a[k][key]) for k in ok if a[k][key] > b[k][key]]
            print(f"   {name}: earlier {len(earlier)}, later {len(later)}, same {len(ok) - len(earlier) - len(later)} of {len(ok)}")
            if earlier:
                print(f"      earlier by (bytes): {quantiles([x[1] - x[2] for x in earlier])}")
            if later:
                print(f"      later by (bytes):   {quantiles([x[2] - x[1] for x in later])}")
            for B in BUDGETS:
                ins = [k for k in ok if b[k][key] >= B > a[k][key]]
                outs = [k for k in ok if a[k][key] >= B > b[k][key]]
                print(f"      budget {B:5d} B: cells entering {len(ins)}, leaving {len(outs)}" + (f"  in={ins[:6]} out={outs[:6]}" if ins or outs else ""))
        for B in (8192, 16384):
            ib = sum(1 for k in pair for o in b[k]["off"].values() if o is not None and o < B)
            ia = sum(1 for k in pair for o in a[k]["off"].values() if o is not None and o < B)
            print(f"   STRICT ITEM required ITEMS located within {B} B: {ib} -> {ia} of {sum(b[k]['nreq'] for k in pair)}")
    return rc


def census(outdir, which):
    for w in ("Q", "SUBJECT"):
        n = 0
        after, before, share, tailless, late = collections.Counter(), collections.Counter(), [], 0, 0
        for qid, _repo, _split, _req in cells(which):
            rc, text = read_cell(outdir, qid, w)
            if rc != "0":
                continue
            sc = blocks(text)
            if sc is None:
                continue
            n += 1
            el = [b for b in sc[1] if b[0] == "element"]
            names = [b[1] for b in el]
            if "tail" not in names:
                tailless += 1
                continue
            t = names.index("tail")
            share.append(round(100.0 * (byte_off(text, el[t][3]) - byte_off(text, el[t][2])) / len(text.encode("utf-8", errors="replace")), 1))
            for x in names[:t]:
                before[x] += 1
            for x in names[t + 1:]:
                after[x] += 1
            late += any(x in EVIDENCE for x in names[t + 1:])
        print(f"{which} wording={w}: answers={n}, without a <tail>: {tailless}")
        print(f"   sections printed BEFORE <tail> (answers carrying each): {sorted(before.items(), key=lambda x: -x[1])}")
        print(f"   sections printed AFTER  <tail> (answers carrying each): {sorted(after.items(), key=lambda x: -x[1])}")
        print(f"   answers with at least one line-carrying section after <tail>: {late} of {n}")
        print(f"   <tail> share of the answer's bytes, per answer (%): {quantiles(share)}")


def prefix(outdir, which, nbytes):
    """Which disclosure attributes does a reader of the first NBYTES see? Printed per wording as a multiset total,
    and written per cell so two arms can be diffed: a reordering that pushes one OUT of the prefix is a defect."""
    out = {}
    for qid, _repo, _split, _req in cells(which):
        for w in ("Q", "SUBJECT"):
            rc, text = read_cell(outdir, qid, w)
            if rc != "0":
                continue
            head = text.encode("utf-8", errors="replace")[:nbytes].decode("utf-8", errors="replace")
            head = re.sub(r'<!--.*?(-->|$)', '', head, flags=re.S)
            head = DISCLAIM_ATTRS.sub('', head)
            root = re.match(r'\s*<ctx\b[^>]*>', head)
            out[f"{qid}|{w}"] = {"root_whole": bool(root), "tokens": sorted(collections.Counter(m.group(1) for m in DISCLOSURE.finditer(head)).items())}
    return out


def selftest():
    """Mutation controls: each synthetic answer has a known verdict; a control that reads otherwise is a blind instrument."""
    files = ({"src/a.rs", "src/b.rs", "lib/a.rs"}, {"src/a.rs": ["src/a.rs"], "b.rs": ["src/b.rs"], "src/b.rs": ["src/b.rs"],
                                                    "a.rs": ["src/a.rs", "lib/a.rs"], "lib/a.rs": ["lib/a.rs"]})
    items = {"R1": {"locs": [["src/a.rs", 576]]}, "R2": {"locs": [["src/b.rs", 96]]}}
    row = '<d l="{l}" e="{e}" n="x" p="{p}" r="{r}">sig</d>'
    junk = "".join(row.format(l=10 * i, e=10 * i + 2, p="lib/a.rs", r=i) for i in range(1, 26))
    tail = '<tail total="9" shown="3" capped="1" next="--for=x --offset=3">' + '<t p="src/b.rs" sym="q"/>' * 200 + '</tail>'
    rx = '<reexports><rx p="src/b.rs" l="96" use="a::b"/></reexports>'
    doc = '<ctx task="t" root="."><!-- ripwire for: the legend --><sigs shown="25" total="25" capped="0">' + junk + '</sigs>' + tail + \
          '<!-- syms: its own legend --><syms><y p="src/a.rs:576" n="x"/></syms>' + rx + '</ctx>'
    bad = 0
    def check(name, ok, detail=""):
        nonlocal bad
        bad += 0 if ok else 1
        print(f"  {'PASS' if ok else 'FAIL'}  {name}{detail}")
    g0 = grade_text("fixture", doc, items, ["R1", "R2"], {"R2": ["src/b.rs"]}, files)
    p = permute(doc, "tail-last")
    g1 = grade_text("fixture", p, items, ["R1", "R2"], {"R2": ["src/b.rs"]}, files)
    check("a <tail> pointer row is no STRICT claim: the tail's 200 rows locate nothing", g0["sec"] == {"R1": "syms", "R2": "reexports"}, f": {g0['sec']}")
    check("tail-last is a permutation: same bytes, same sorted bytes", len(p) == len(doc) and sorted(p) == sorted(doc) and p != doc)
    check("tail-last leaves every STRICT claim position where it was", g0["pos"] == g1["pos"], f": {g0['pos']} -> {g1['pos']}")
    check("tail-last brings the STRICT byte offset forward by the tail's size", g0["first_off"] - g1["first_off"] == len(tail), f": {g0['first_off']} -> {g1['first_off']}")
    check("LENIENT sees the cost: the tail's own path is delivered LATER after the move", g1["len_first"] > g0["len_first"], f": {g0['len_first']} -> {g1['len_first']}")
    check("a block-local legend travels with its block", '<!-- syms: its own legend --><syms>' in p and p.index('<!-- ripwire for') < p.index('<sigs'))
    check("the root tag and the document legend do not move", p.startswith(doc[:doc.index('<sigs')]))
    cut = p.replace(rx, "")
    g2 = grade_text("fixture", cut, items, ["R1", "R2"], {}, files)
    check("MUTATION a dropped section is seen: R2 is no longer located", g2["pos"]["R2"] is None and g1["pos"]["R2"] is not None)
    lined = doc.replace('<t p="src/b.rs" sym="q"/>', '<q p="src/b.rs" l="96"/>', 1)
    check("MUTATION a tail row that carried a line WOULD be a claim if it were not inside <tail>", grade_text("fixture", lined.replace("<tail ", "<tale ").replace("</tail>", "</tale>"), items, ["R1", "R2"], {}, files)["sec"]["R2"] == "tale")
    nodoc = '<ctx><sigs>' + junk + '</sigs></ctx>'
    check("an answer without a <tail> is returned unchanged", permute(nodoc, "tail-last") == nodoc)
    return 1 if bad else 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "selftest":
        sys.exit(selftest())
    need_work()
    if cmd == "collect":
        collect(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    elif cmd == "permute":
        permute_dir(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif cmd == "census":
        census(sys.argv[2], sys.argv[3])
    elif cmd == "report":
        rows = grade(sys.argv[2], sys.argv[3])
        report(rows, sys.argv[3])
        if len(sys.argv) > 4:
            json.dump(rows, open(sys.argv[4], "w"), indent=1, sort_keys=True)
    elif cmd == "compare":
        sys.exit(compare(json.load(open(sys.argv[2])), json.load(open(sys.argv[3]))))
    elif cmd == "prefix":
        json.dump(prefix(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 2048), sys.stdout, indent=1, sort_keys=True)
    else:
        sys.exit(__doc__)
