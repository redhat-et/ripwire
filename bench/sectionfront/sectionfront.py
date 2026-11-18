#!/usr/bin/env python3
"""sectionfront.py -- BAND SF: do sections printed AFTER <sigs> belong AHEAD of it?  (docs/EVALS.md, 2026-11-17)

An ANSWER-QUALITY instrument over one permutation. It never measures how many bytes an answer has (a permutation has
the same bytes); it measures WHERE the required evidence sits. Grains are kept apart on every line and never pooled:
  STRICT ITEM  a rubric item is LOCATED by the n-th CLAIM of the answer (sectionpos.claims: a start tag carrying a path
               that resolves in the pinned checkout and a line; <dc>/<skip>/<tail>/<inv>/<t>, comments and next= are
               disclaimed and yield none), within +-3 lines of a manifest location. Budget K=20 claims.
  FILE         a required FILE has APPEARED, as a string anywhere in the answer (tail pointers count). Prefix offset.

  sectionfront.py collect BIN OUTDIR dev|held          run the stored argv of each cell on BIN (needs SF_WORK)
  sectionfront.py readout OUTDIR dev|held RULE         one rule against printed order, every bar, solo firing
  sectionfront.py selftest                             positive/negative controls and the reader-protecting mutations

RULES (frozen; docs/EVALS.md "BAND SF"): R1 = every EVIDENCE section ahead of <sigs>;  R2 = R1 and the section is
at most R2_BYTES.  The corpus, the checkouts and the stored questions are local and unpublished (SF_WORK)."""
import collections, json, os, re, subprocess, sys, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get("SF_WORK", "")
_spec = importlib.util.spec_from_file_location("sectionpos", os.path.join(HERE, "..", "sectionpos", "sectionpos.py"))
sp = importlib.util.module_from_spec(_spec)
os.environ.setdefault("ST_WORK", WORK)
_spec.loader.exec_module(sp)

POP = json.load(open(os.path.join(HERE, "s1_manifest_MECHANICAL_NOT_GOLD.json")))
SPLIT = json.load(open(os.path.join(HERE, "split.json")))
K = 20
R2_BYTES = 450
WINDOW = 8192
EVIDENCE = sp.EVIDENCE
ANSWERS = "results/FIRE321_1116/a"      # stored argv per cell (the question), never read for DEV/HELD answers' bytes


def cells(which):
    for k, v in sorted(POP.items()):
        if v["req"] and (which == "all" or SPLIT[v["repo"]].lower() == which.lower()):
            yield k, v


def argv_of(k):
    return json.load(open(f"{WORK}/{ANSWERS}/{k}.out.meta"))["argv"]


def skeleton(doc):
    """(root name, blocks) read AFTER stripping comments for the root search: the compact legend spells row schemas
    in prose, so 'the first element in the document' can land inside a comment."""
    bare = re.sub(r"<!--.*?-->", "", doc, flags=re.S)
    m = re.search(r"<([A-Za-z_][A-Za-z0-9_-]*)\b", bare)
    return (m.group(1) if m else None), sp.blocks(doc)


RULES = {
    "R0": None,
    "R1": lambda name, nbytes: name in EVIDENCE,
    "R2": lambda name, nbytes: name in EVIDENCE and nbytes <= R2_BYTES,
}


def ahead_of_sigs(doc, pred):
    """A PERMUTATION: every element block for which pred(name, bytes) holds, and every comment that declares it, is
    moved to stand immediately in front of <sigs>, in printed order. Returns doc unchanged when nothing moves."""
    root, sc = skeleton(doc)
    if root != "ctx" or sc is None:
        return doc
    head, bs, close = sc
    owner = [sp.owner_of(doc, bs, k) if b[0] == "comment" else None for k, b in enumerate(bs)]
    elems = [k for k, b in enumerate(bs) if b[0] == "element"]
    names = [bs[k][1] for k in elems]
    if "sigs" not in names:
        return doc
    sg = elems[names.index("sigs")]
    moved = [k for k in elems if k > sg and pred(bs[k][1], bs[k][3] - bs[k][2])]
    if not moved:
        return doc
    order = []
    def emit(k):
        order.extend(c for c in range(len(bs)) if owner[c] == k)
        order.append(k)
    for k, b in enumerate(bs):
        if b[0] == "comment":
            if owner[k] is None:
                order.append(k)
            continue
        if k in moved:
            continue
        if k == sg:
            for mk in moved:
                emit(mk)
        emit(k)
    out = doc[:head] + "".join(doc[bs[k][2]:bs[k][3]] for k in order) + doc[close:]
    return out


def permcheck(before, after):
    """The reader-protecting validator. Returns the list of broken arms; [] means the permutation is honest.
    P1 size   P2 multiset of top-level blocks   P3 root open tag and every byte before the first block
    P4 every document-level comment keeps its place among the unmoved blocks
    P5 every declaring comment still stands immediately in front of the block it names."""
    broke = []
    if len(before) != len(after):
        broke.append("P1")
    a, b = sp.blocks(before), sp.blocks(after)
    if a is None or b is None:
        return broke + ["P0-shape"]
    ea = sorted(before[x[2]:x[3]] for x in a[1])
    eb = sorted(after[x[2]:x[3]] for x in b[1])
    if ea != eb:
        broke.append("P2")
    if before[:a[0]] != after[:b[0]] or before[a[2]:] != after[b[2]:]:
        broke.append("P3")
    def legends(doc, sc):
        return [doc[x[2]:x[3]] for k, x in enumerate(sc[1]) if x[0] == "comment" and sp.owner_of(doc, sc[1], k) is None]
    if legends(before, a) != legends(after, b):
        broke.append("P4")
    for k, x in enumerate(b[1]):
        if x[0] != "comment":
            continue
        w = re.match(r"<!--\s*([A-Za-z0-9_-]+)", after[x[2]:x[3]])
        nxt = next((y for y in b[1][k + 1:] if y[0] != "comment"), None)
        named = {y[1] for y in b[1] if y[0] == "element"}
        if w and w.group(1) in named and (nxt is None or nxt[1] != w.group(1)):
            broke.append("P5")
            break
    return broke


def grade_cell(repo, text, v):
    items = {r: {"locs": v["locs"][r]} for r in v["req"]}
    g = sp.grade_text(repo, text, items, v["req"], {})
    files = sorted({f for r in v["req"] for f, _l in v["locs"][r]})
    offs = {}
    for f in files:
        at = text.find(f)
        offs[f] = sp.byte_off(text, at) if at >= 0 else None
    g["file_off"] = offs
    g["all_files_off"] = max(offs.values()) if offs and all(x is not None for x in offs.values()) else None
    return g


def metrics(g, v):
    pos, off = g["pos"], g["off"]
    return {"k20": sorted(r for r in v["req"] if pos[r] and pos[r] <= K),
            "in_win": sorted(r for r in v["req"] if off[r] is not None and off[r] < WINDOW),
            "first": g["first"], "first_off": g["first_off"], "all_files": g["all_files_off"], "claims": g["claims"]}


def readout(outdir, which, rule):
    base, ruleP = {}, RULES[rule]
    absent = unreach = napp = 0
    for k, v in cells(which):
        o = f"{outdir}/{k}.out"
        if not os.path.exists(o):
            absent += 1
            continue
        if open(o + ".rc").read().strip() != "0":
            unreach += 1
            continue
        t = open(o, encoding="utf-8", errors="replace").read()
        root, sc = skeleton(t)
        if root != "ctx" or sc is None or "sigs" not in [b[1] for b in sc[1] if b[0] == "element"]:
            napp += 1
            continue
        u = ahead_of_sigs(t, ruleP)
        gb, gu = grade_cell(v["repo"], t, v), grade_cell(v["repo"], u, v)
        base[k] = (metrics(gb, v), metrics(gu, v), u != t, permcheck(t, u), v)
    n = len(base)
    moved = [k for k in base if base[k][2]]
    d = lambda f: sum(f(base[k][1]) - f(base[k][0]) for k in moved)
    items_in = sum(len(set(base[k][1]["k20"]) - set(base[k][0]["k20"])) for k in moved)
    items_out = sum(len(set(base[k][0]["k20"]) - set(base[k][1]["k20"])) for k in moved)
    cell20 = lambda m: m["first"] is not None and m["first"] <= K
    cells_in = sum(1 for k in moved if cell20(base[k][1]) and not cell20(base[k][0]))
    cells_out = sum(1 for k in moved if cell20(base[k][0]) and not cell20(base[k][1]))
    win_in = sum(len(set(base[k][1]["in_win"]) - set(base[k][0]["in_win"])) for k in moved)
    win_out = sum(len(set(base[k][0]["in_win"]) - set(base[k][1]["in_win"])) for k in moved)
    fw = lambda m: m["all_files"] is not None and m["all_files"] < WINDOW
    fwin_in = sum(1 for k in moved if fw(base[k][1]) and not fw(base[k][0]))
    fwin_out = sum(1 for k in moved if fw(base[k][0]) and not fw(base[k][1]))
    def med(sel):
        vals = sorted(x for x in sel if x is not None)
        return (vals[len(vals) // 2], len(vals)) if vals else (None, 0)
    mb = med([base[k][0]["all_files"] for k in base])
    ma = med([base[k][1]["all_files"] for k in base])
    pc = collections.Counter(x for k in base for x in base[k][3])
    res = {"rule": rule, "split": which, "applicable": n, "not_applicable": napp, "absent": absent, "unreachable": unreach,
           "cells_moved": len(moved), "items_total": sum(len(base[k][4]["req"]) for k in base),
           "items_k20_printed": sum(len(base[k][0]["k20"]) for k in base), "items_k20_rule": sum(len(base[k][1]["k20"]) for k in base),
           "B1_items_in": items_in, "B1_items_out": items_out, "B2_cells_in": cells_in, "B2_cells_out": cells_out,
           "B3_files_median_printed": mb, "B3_files_median_rule": ma, "B3_files_win_in": fwin_in, "B3_files_win_out": fwin_out,
           "B4_items_win_in": win_in, "B4_items_win_out": win_out, "permcheck_failures": dict(pc),
           "per_cell": {k: {"printed": base[k][0], "rule": base[k][1], "moved": base[k][2]} for k in base}}
    res["B1"] = items_in - items_out >= 3 and items_out <= 1
    res["B2"] = cells_out == 0
    res["B3"] = (mb[0] is not None and ma[0] is not None and ma[0] <= mb[0]) and fwin_out - fwin_in <= 0
    res["B4"] = win_in - win_out >= 0
    res["B5"] = not pc
    res["PASS"] = all(res[b] for b in ("B1", "B2", "B3", "B4", "B5"))
    return res


def solo(outdir, which):
    """Per-clause solo firing: for R2 = A(evidence) AND B(size <= R2_BYTES). The A-clause alone is R1; clause B alone
    (every section of any name at most R2_BYTES, lego/tail excluded as non-claim blocks) is R2B."""
    clauses = {"A_evidence_only": RULES["R1"],
               "B_size_only": lambda n, b: n not in ("lego", "tail", "sigs") and b <= R2_BYTES,
               "A_and_B": RULES["R2"]}
    out = {}
    for name, pr in clauses.items():
        RULES["_t"] = pr
        r = readout(outdir, which, "_t")
        out[name] = {k: r[k] for k in ("cells_moved", "B1_items_in", "B1_items_out", "B2_cells_in", "B2_cells_out", "B4_items_win_in", "B4_items_win_out")}
    del RULES["_t"]
    return out


def collect(binp, outdir, which):
    os.makedirs(outdir, exist_ok=True)
    for k, v in cells(which):
        o = f"{outdir}/{k}.out"
        if os.path.exists(o) and os.path.getsize(o) > 0:
            continue
        try:
            argv = argv_of(k)
        except OSError:
            continue
        r = subprocess.run([binp, f"{WORK}/repos/{v['repo']}"] + argv, capture_output=True, timeout=1800)
        open(o, "wb").write(r.stdout)
        open(o + ".rc", "w").write(str(r.returncode))
        print(k, r.returncode, len(r.stdout), flush=True)


# ---- the controls -------------------------------------------------------------------------------------------------
def _synthetic(n_sigs, n_hops, req_in_hops, hops_pos):
    """A <ctx> answer with n_sigs claim rows in <sigs>, n_hops in <hops>; a 'required' location is claim row `hops_pos`
    of <hops> (or of <sigs> when req_in_hops is false)."""
    rows = lambda pre, n: "".join(f'<d n="{pre}{i}" p="src/{pre}.c" l="{100 + i}"/>' for i in range(n))
    return ('<ctx task="t"><!-- sigs reading --><sigs>' + rows("s", n_sigs) + '</sigs><tail><t p="src/x.c" sym="f"/></tail>'
            '<!-- hops reading --><hops>' + rows("h", n_hops) + '</hops></ctx>')


def selftest():
    bad = 0
    def check(name, cond):
        nonlocal bad
        print(("ok   " if cond else "FAIL ") + name)
        bad += 0 if cond else 1
    doc = _synthetic(25, 4, True, 3)
    out = ahead_of_sigs(doc, RULES["R1"])
    check("S1 permutation moves <hops> ahead of <sigs>", out.index("<hops>") < out.index("<sigs>") and out != doc)
    check("S2 a clean permutation passes permcheck", permcheck(doc, out) == [])
    check("S3 declaring comment travels with its block", "<!-- hops reading --><hops>" in out and out.index("<hops>") < out.index("<sigs>"))
    # POSITIVE control: a required row at claim 25+3 of the printed answer enters K=20 once <hops> leads.
    v = {"repo": "x", "req": ["R1"], "locs": {"R1": [["src/h.c", 103]]}}
    fs = ({"src/s.c", "src/h.c", "src/x.c"}, {"src/s.c": ["src/s.c"], "src/h.c": ["src/h.c"], "src/x.c": ["src/x.c"]})
    def pos(text):
        g = sp.grade_text("x", text, {"R1": {"locs": v["locs"]["R1"]}}, ["R1"], {}, fs)
        return g["pos"]["R1"]
    check("S4 POSITIVE control: item at claim >20 printed, <=20 after the move", (pos(doc) or 99) > 20 and (pos(out) or 99) <= 20)
    # NEGATIVE control: an item at <sigs> claim 18 (+-3 line tolerance) leaves K=20 when 4 rows are put in front of it.
    v2 = {"R1": {"locs": [["src/s.c", 120]]}}
    g1 = sp.grade_text("x", doc, v2, ["R1"], {}, fs)["pos"]["R1"]; g2 = sp.grade_text("x", out, v2, ["R1"], {}, fs)["pos"]["R1"]
    check("S5 NEGATIVE control: an item inside K=20 leaves it when rows are put ahead", g1 is not None and g1 <= 20 and g2 is not None and g2 > 20)
    # a required row that is absent is UNLOCATED, never a zero position
    g3 = sp.grade_text("x", doc, {"R1": {"locs": [["src/nope.c", 1]]}}, ["R1"], {}, fs)["pos"]["R1"]
    check("S6 an item with no claim is None, not 0", g3 is None)
    # the reader-protecting mutations: each must be caught
    m_drop = out.replace('<hops>' + out.split("<hops>")[1].split("</hops>")[0] + '</hops>', "")
    check("M1 a DELETED block (smaller answer) is caught", permcheck(doc, m_drop) != [])
    m_sep = out.replace("<!-- hops reading -->", "").replace("</sigs>", "</sigs><!-- hops reading -->")
    check("M2 a declaring comment separated from its block is caught (P5)", "P5" in permcheck(doc, m_sep))
    m_head = out.replace('<ctx task="t">', '<ctx task="t"><!-- document legend -->', 1)
    check("M3 a changed byte before the first block is caught (P1/P3)", permcheck(doc, m_head) != [])
    m_leg = doc.replace("<ctx task=\"t\">", "<ctx task=\"t\"><!-- document legend: nothing -->", 1)
    mv = ahead_of_sigs(m_leg, RULES["R1"])
    check("M4 a document-level legend stays put when sections move", permcheck(m_leg, mv) == [])
    mv2 = mv.replace("<!-- document legend: nothing -->", "", 1) + ""
    check("M5 a document legend dropped is caught", permcheck(m_leg, mv2) != [])
    # the instrument check: a comment that spells a tag in prose must not become the root
    tricky = '<!-- <sigs n= p=> reading --><ctx task="t"><sigs><d p="a.c" l="1"/></sigs></ctx>'
    check("I1 the root is read AFTER stripping comments", skeleton(tricky)[0] == "ctx")
    return 1 if bad else 0


if __name__ == "__main__":
    c = sys.argv[1] if len(sys.argv) > 1 else ""
    if c == "selftest":
        sys.exit(selftest())
    if c in ("collect", "readout", "solo") and not WORK:
        sys.exit("SF_WORK is not set")
    if c == "collect":
        collect(sys.argv[2], sys.argv[3], sys.argv[4])
    elif c == "readout":
        r = readout(sys.argv[2], sys.argv[3], sys.argv[4])
        slim = {k: v for k, v in r.items() if k != "per_cell"}
        print(json.dumps(slim, indent=1))
        if len(sys.argv) > 5:
            json.dump(r, open(sys.argv[5], "w"), indent=1)
    elif c == "solo":
        print(json.dumps(solo(sys.argv[2], sys.argv[3]), indent=1))
    else:
        sys.exit(__doc__)
