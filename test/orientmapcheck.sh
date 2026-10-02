#!/usr/bin/env bash
# orientmapcheck.sh — the default whole-repo map orients: entry points with evidence, a subsystem grouping, every core
# file named once (inside a 2,048 B overflow, the rest one next= away), utility sinks and vendored code in one counted
# tail (fix list #8, the registered orient-map v2 arms O / O-narrow; docs/EVALS.md "Orient map").
#
# WRITTEN BEFORE THE CODE IT MEASURES (CLAUDE.md non-negotiable #1): on the pre-change binary every arm that needs the
# sections is RED, and the arms about what must NOT change are green. The section schema, the label/path conventions
# and the classifier/oracle live in test/lib/orientmap.py (its docstring is the schema).
#
# Arms, on the generated fixture (test/orientmapfix/gen.sh, a committed git tree so MCP analyze sees a clean working set;
# the oracle must decide every comparison it makes, or the fixture is refused):
#   (F) THE RULE, exactly: g= is the registered grouping root; <subsystems> lists the first 12 groups in mass order with
#       n= and the top 3 members; <overflow> holds a PREFIX of the breadth-first list of every core file not yet named,
#       re-grouped in group order; total=/shown=/capped= are the rule's own counts; <entry_points> carries the manifest
#       bin, the `main` definition and the "." export (in that evidence order), never the near-miss `main_loop` and never
#       a bin whose build output has no source twin; every vendored/compat core file is demoted (utility_demoted=).
#   (D) DISCLOSURE (Gate D): each next= (entry points, subsystems, overflow, utility_demoted) and then next_offset= pages
#       EXACTLY what its element cut, in rank order, each once, every page <= K rows; no file is named twice across
#       <subsystems> and <overflow>; every name is a core file; named + paged = every core file.
#   (U) UNCAPPED (the reported variant, RIPWIRE_ORIENT_UNCAPPED=1): <overflow> is the whole breadth-first list, capped="0",
#       and every byte outside <overflow> is the capped answer's.
#   (P) PARITY (Gate P): the bytes from the first section tag to the end of the last are identical on the CLI map (compact,
#       --legend=full, --top-k=16, --max-tokens=4000), MCP analyze (clean tree, compact and full) and MCP rank_by
#       (omitted and pagerank); --json carries the same sections row for row; --html carries every label and name.
#   (N) NOT APPLIED: --tree, --rank-by=authority|hub|rrf, --for, MCP analyze with an uncommitted edit, MCP rank_by
#       authority and MCP explore carry no section and no utility_demoted=.
#   (L) LEGEND (Gate D, G4): every attribute of every new element is defined (name=) in the compact and full XML legends,
#       the MCP analyze legend and --help=all (the --json keys' legend), each new tag is named there, the session
#       dictionary (--legend-dict) defines them, and an MCP legend=ref analyze leans only on definitions that session has.
#   (C) COST (registered, step 1 of the stair): the sections are <= 4,096 B (deciding on ORIENTMAP_EXTRA_ROOTS, the
#       registered scope; INFO on the fixture, whose long names exist to bind the overflow cap); <overflow> is <= 2,048 B and no further name
#       fits; the first section starts within 1,024 B. The start is measured from byte 0 of the answer (the registered
#       text); ORIENTMAP_START_FROM=body measures from the end of the leading legend comments instead, and both are printed.
#       With ORIENTMAP_BASE_BIN=<pre-change binary>: map growth <= +4,096 B, and with ORIENTMAP_ARM=narrow the ranked rows
#       are byte-identical to the base binary's.
#   (X) xmllint well-formed, two runs byte-identical.
# ORIENTMAP_EXTRA_ROOTS=dir1:dir2 runs (D), (U), (P) and (C) on those trees too (the measurement harness's corpora).
# Exit 0 all pass, 1 any fail (a fixture the oracle cannot decide is a failure), 2 setup.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
GEN="$ROOT/test/orientmapfix/gen.sh"
[ -x "$BIN" ] || { echo "orientmapcheck: no ripwire binary at $BIN — build first"; exit 2; }
[ -f "$GEN" ] || { echo "orientmapcheck: fixture generator missing: $GEN"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "orientmapcheck: git not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "orientmapcheck: python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
export TMPDIR="$TMP/" XDG_CACHE_HOME="$TMP/xdg"
unset RIPWIRE_ORIENT_UNCAPPED
echo "orientmapcheck: BIN=$BIN"
bash "$GEN" "$TMP/fx" >/dev/null && git -C "$TMP/fx" init -q && git -C "$TMP/fx" add -A \
    && git -C "$TMP/fx" -c user.name=gate -c user.email=gate@example.invalid -c commit.gpgsign=false commit -qm fixture \
    || { echo "orientmapcheck: fixture generation failed"; exit 2; }

python3 - "$BIN" "$TMP" "$ROOT" "${ORIENTMAP_EXTRA_ROOTS:-}" <<'PYEOF' || no "the arms above reported a failure (or the check body could not run)"
import html as H, json, os, re, shutil, subprocess, sys
BIN, TMP, ROOT, EXTRA = sys.argv[1:5]
sys.path.insert(0, os.path.join(ROOT, "test", "lib"))
import orientmap as om

BASE_BIN = os.environ.get("ORIENTMAP_BASE_BIN", "")
ARM = os.environ.get("ORIENTMAP_ARM", "O")
START_FROM = os.environ.get("ORIENTMAP_START_FROM", "byte0")
UNC = {"RIPWIRE_ORIENT_UNCAPPED": "1"}
fails = []


def ok(m):
    print("  PASS  " + m)


def no(m):
    print("  FAIL  " + m)
    fails.append(m)


def check(cond, m, why=""):
    (ok if cond else no)(m + ("" if cond or not why else ": " + why))
    return cond


FX = os.path.join(TMP, "fx")


def model(root):
    """everything the arms need about one root: the answer, its sections, the inventory, the oracle"""
    doc, rc = om.run(BIN, root)
    secs = om.sections(doc)
    inv, _ = om.inventory(BIN, root)
    ms, _ = om.masses(BIN, root)
    cand = om.core_candidates(inv)
    dem, dprob, dcount = [], [], None
    d = secs.get("demoted")
    if d is not None:
        dcount = int(d.a.get("utility_demoted", "-1"))
        if dcount > 0:
            if "next" not in d.a:
                dprob.append("utility_demoted=%d with no next=" % dcount)
            else:
                rows, dprob = om.follow(BIN, root, d.a["next"], "p")
                dem = [r["p"] for r in rows]
    core = [p for p in cand if p not in set(dem)]
    return dict(root=root, doc=doc, rc=rc, secs=secs, inv=inv, ms=ms, cand=cand, dem=dem, dprob=dprob, dcount=dcount,
                core=core, orc=om.oracle(core, ms))


def names(node, g):
    """[(label, [repo paths])] of a <subsystems>/<overflow> node"""
    return [(grp.a.get("l"), [om.unrel(m.a.get("p", ""), g) for m in grp.find("m")]) for grp in node.find("grp")]


def gate_d(M, label):
    """(D) on one root: counts, next= recovery, core-ness, once-only, completeness"""
    s, root = M["secs"], M["root"]
    if not check("subsystems" in s and "overflow" in s, "(D) %s: <subsystems> and <overflow> are present" % label):
        return
    sub, ov = s["subsystems"], s["overflow"]
    g = sub.a.get("g", "")
    for node, tag in ((sub, "subsystems"), (ov, "overflow")) + (((s["entry_points"], "entry_points"),) if "entry_points" in s else ()):
        a = node.a
        try:
            sh, tot = int(a["shown"]), int(a["total"])
        except (KeyError, ValueError):
            no("(D) %s: <%s> lacks a numeric shown=/total=" % (label, tag))
            continue
        cap = a.get("capped")
        check(sh <= tot and cap == ("1" if sh < tot else "0") and (("next" in a) == (sh < tot)),
              "(D) %s: <%s> shown=%d <= total=%d, capped=%s and next= exactly when something is cut" % (label, tag, sh, tot, cap))
    sub_names = [p for _, ps in names(sub, g) for p in ps]
    ov_names = [p for _, ps in names(ov, ov.a.get("g", g)) for p in ps]
    shown = sub_names + ov_names
    check(len(shown) == len(set(shown)), "(D) %s: no file is named twice across <subsystems> and <overflow>" % label,
          str(sorted({p for p in shown if shown.count(p) > 1})[:5]))
    notcore = sorted(set(shown) - set(M["core"]))
    check(not notcore, "(D) %s: every name is a core file" % label, str(notcore[:5]))
    check(int(ov.a.get("shown", -1)) == len(ov_names), "(D) %s: <overflow shown=> counts its names" % label)
    cut = []
    if "next" in ov.a:
        rows, probs = om.follow(BIN, root, ov.a["next"], "p")
        cut = [r["p"] for r in rows]
        check(not probs, "(D) %s: overflow next= pages cleanly" % label, "; ".join(probs[:3]))
        check(len(cut) == len(set(cut)) and not (set(cut) & set(shown)), "(D) %s: overflow next= pages each cut name once, none shown" % label)
        check(int(ov.a["total"]) - int(ov.a["shown"]) == len(cut), "(D) %s: overflow next= returns total-shown=%d names (got %d)"
              % (label, int(ov.a["total"]) - int(ov.a["shown"]), len(cut)))
    missing = sorted(set(M["core"]) - set(shown) - set(cut))
    check(not missing, "(D) %s: named + paged = every core file (%d)" % (label, len(M["core"])), "%d missing, e.g. %s" % (len(missing), missing[:5]))
    if "next" in sub.a:
        rows, probs = om.follow(BIN, root, sub.a["next"], "l")
        labs = [r["l"] for r in rows]
        allg = [l for l, _ in names(sub, g)] + labs
        check(not probs and len(allg) == len(set(allg)) and len(allg) == int(sub.a["total"]),
              "(D) %s: subsystems next= pages the %d groups past the shown ones, each once" % (label, int(sub.a["total"]) - int(sub.a["shown"])),
              "; ".join(probs[:3]) or "%d labels" % len(allg))
    if "entry_points" in s and "next" in s["entry_points"].a:
        ep = s["entry_points"]
        rows, probs = om.follow(BIN, root, ep.a["next"], "why")
        check(not probs and len(rows) == int(ep.a["total"]) - int(ep.a["shown"]) and all(r.get("why") in om.WHY for r in rows),
              "(D) %s: entry_points next= returns the %d entries not listed, each with why=" % (label, int(ep.a["total"]) - int(ep.a["shown"])))
    if M["dcount"] is None:
        no("(D) %s: no utility_demoted= anywhere in the answer" % label)
    else:
        check(not M["dprob"] and M["dcount"] == len(M["dem"]) == len(set(M["dem"])),
              "(D) %s: utility_demoted=%d equals the files its next= returns, each once" % (label, M["dcount"]),
              "; ".join(M["dprob"][:3]) or "next= returned %d" % len(M["dem"]))
        vend = sorted(p for p in M["cand"] if om.is_vendored(p) and p not in M["dem"])
        check(not vend, "(D) %s: every vendored/compat core file is demoted" % label, str(vend[:5]))
        if ARM != "narrow":
            ranked_files = {f.a.get("p") for f in om.walk(om.tree(M["doc"])) if f.tag == "f"}
            check(not (ranked_files & set(M["dem"])), "(D) %s: no demoted file keeps a ranked row" % label)
    for e in (s["entry_points"].find("e") if "entry_points" in s else []):
        mm = re.match(r"(.+):(\d+)$", e.a.get("p", ""))
        f = mm and os.path.join(root, mm.group(1))
        good = bool(mm) and e.a.get("why") in om.WHY and e.a.get("n") and os.path.isfile(f) \
            and 1 <= int(mm.group(2)) <= max(1, sum(1 for _ in open(f, errors="replace")))
        check(good, "(D) %s: entry row %s has file:line inside the file, n= and why=" % (label, e.a))


def uncapped(M, label):
    """(U) the uncapped variant: the whole breadth-first list, nothing else moved; and it reconstructs the capped cut"""
    doc2, _ = om.run(BIN, M["root"], env=UNC)
    s1, s2 = M["secs"], om.sections(doc2)
    if not check("overflow" in s1 and "overflow" in s2, "(U) %s: both variants carry <overflow>" % label):
        return
    o1, o2 = s1["overflow"], s2["overflow"]
    d1, d2 = M["doc"], doc2
    check(d1[:o1.start] == d2[:o2.start] and d1[o1.end:] == d2[o2.end:], "(U) %s: every byte outside <overflow> is the capped answer's" % label)
    check(o2.a.get("capped") == "0" and "next" not in o2.a and o2.a.get("shown") == o2.a.get("total"), "(U) %s: uncapped <overflow> cuts nothing" % label)
    sub = s1["subsystems"]
    g = sub.a.get("g", "")
    full = {}
    for lab, ps in names(sub, g):
        full[lab] = list(ps)
    order = list(full)
    for lab, ps in names(o2, o2.a.get("g", g)):
        if lab not in full:
            full[lab] = []
            order.append(lab)
        full[lab] += ps
    named = {p for lab in order[:12] for p in full[lab][:3]}
    ranked = [full[lab][j] for j in range(max((len(v) for v in full.values()), default=0)) for lab in order if j < len(full[lab]) and full[lab][j] not in named]
    capped_names = [p for _, ps in names(o1, o1.a.get("g", g)) for p in ps]
    k = len(capped_names)
    check(set(capped_names) == set(ranked[:k]), "(U) %s: the capped overflow is a prefix of the breadth-first list the uncapped one implies" % label)
    if "next" in o1.a:
        rows, _ = om.follow(BIN, M["root"], o1.a["next"], "p")
        check([r["p"] for r in rows] == ranked[k:], "(U) %s: overflow next= pages the rest of that list in rank order" % label)
    if o1.a.get("capped") == "0":
        check(d1 == d2, "(U) %s: under the cap the uncapped answer is byte-identical" % label)


def parity(M, label):
    root = M["root"]
    r0 = om.region(M["doc"])
    if not check(r0 is not None, "(P) %s: the CLI map carries the sections" % label):
        return
    ref = M["doc"][r0[0]:r0[1]]
    variants = {"--legend=full": om.run(BIN, root, "--legend=full")[0], "--top-k=16": om.run(BIN, root, "--top-k=16")[0],
                "--max-tokens=4000": om.run(BIN, root, "--max-tokens=4000")[0]}
    an, anf, rb, rbp = om.mcp(BIN, root, [("analyze", {}), ("analyze", {"legend": "full"}), ("rank_by", {}), ("rank_by", {"rank_by": "pagerank"})])
    variants.update({"MCP analyze": an, "MCP analyze legend=full": anf, "MCP rank_by": rb, "MCP rank_by pagerank": rbp})
    bad = []
    for k, d in variants.items():
        r = om.region(d)
        if r is None or d[r[0]:r[1]] != ref:
            bad.append(k)
    check(not bad, "(P) %s: section bytes identical on CLI XML, --legend=full, --top-k=16, --max-tokens=4000, MCP analyze, MCP rank_by" % label, str(bad))
    j = json.loads(om.run(BIN, root, "--json")[0])
    jbad = []
    for tag, node in M["secs"].items():
        if tag == "demoted":
            continue
        jo = j.get(tag)
        if not isinstance(jo, dict):
            jbad.append(tag + " absent")
            continue
        for k, v in node.a.items():
            if str(jo.get(k)) != v:
                jbad.append("%s.%s %r != %r" % (tag, k, jo.get(k), v))
        def rows(n):
            return [(c.tag, sorted(c.a.items()), [sorted(x.a.items()) for x in c.kids]) for c in n.kids]
        def jrows(o, kidtag):
            out = []
            for c in o.get(kidtag, []):
                sub = [sorted((k, str(v)) for k, v in x.items()) for x in c.get("m", [])]
                out.append((kidtag, sorted((k, str(v)) for k, v in c.items() if k != "m"), sub))
            return out
        kt = "e" if tag == "entry_points" else "grp"
        if rows(node) != jrows(jo, kt):
            jbad.append(tag + " rows differ")
    check(not jbad, "(P) %s: --json carries the same sections row for row" % label, "; ".join(jbad[:4]))
    hp = os.path.join(TMP, "h.html")
    om.run(BIN, root, "--html=" + hp)
    ht = open(hp, errors="replace").read() if os.path.exists(hp) else ""
    want = [n.a.get("l") or n.a.get("p") for n in om.walk([M["secs"][t] for t in ("subsystems", "overflow") if t in M["secs"]]) if n.tag in ("grp", "m")]
    miss = [w for w in want if w and w not in ht and H.escape(w) not in ht and json.dumps(w)[1:-1] not in ht]
    check(want and not miss, "(P) %s: --html carries every section label and name" % label, str(miss[:5]))


def cost(M, label, deciding=True):
    doc = M["doc"]
    r = om.region(doc)
    if not check(r is not None, "(C) %s: sections present to measure" % label):
        return
    lead_end = 0
    while True:
        m = re.match(r"\s*<!--.*?-->", doc[lead_end:], re.S)
        if not m:
            break
        lead_end += m.end()
    start0, startb = r[0], r[0] - lead_end
    print("  INFO  (C) %s: sections %d B; first section at byte %d (%d after the leading legend); answer %d B" % (label, r[1] - r[0], start0, startb, len(doc)))
    if deciding:
        check(r[1] - r[0] <= om.SECTIONS_CAP, "(C) %s: sections <= %d B (%d)" % (label, om.SECTIONS_CAP, r[1] - r[0]))
    else:   # the registered cost scope is the corpora and the table/OOS repos; the fixture's long names are there to bind the overflow
        print("  INFO  (C) %s: sections %s the %d B cap (decided on the corpora, not on this fixture)" % (label, "within" if r[1] - r[0] <= om.SECTIONS_CAP else "OVER", om.SECTIONS_CAP))
    st = start0 if START_FROM == "byte0" else startb
    check(st <= om.START_CAP, "(C) %s: the first section starts within %d B (%s reading: %d)" % (label, om.START_CAP, START_FROM, st))
    ov = M["secs"].get("overflow")
    if ov is not None:
        ob = ov.end - ov.start
        check(ob <= om.OVERFLOW_CAP, "(C) %s: <overflow> <= %d B (%d)" % (label, om.OVERFLOW_CAP, ob))
        if ov.a.get("capped") == "1" and "next" in ov.a:
            rows, _ = om.follow(BIN, M["root"], ov.a["next"], "p")
            if rows:
                g = ov.a.get("g", M["secs"]["subsystems"].a.get("g", "")) if "subsystems" in M["secs"] else ""
                nxt = rows[0]["p"]
                lab = next((l for l, ps in M["orc"]["members"].items() if nxt in ps), None)
                add = len('<m p="%s"/>' % H.escape(om.printed(nxt, g)))
                if lab not in {grp.a.get("l") for grp in ov.find("grp")}:
                    add += len('<grp l="%s"></grp>' % H.escape(lab or ""))
                check(ob + add > om.OVERFLOW_CAP, "(C) %s: the first cut name would not have fit (%d + %d B)" % (label, ob, add))
    if BASE_BIN:
        bdoc, _ = om.run(BASE_BIN, M["root"])
        check(len(doc) - len(bdoc) <= 4096, "(C) %s: map growth vs base <= +4,096 B (%+d)" % (label, len(doc) - len(bdoc)))
        if ARM == "narrow":
            def ranked(d):
                i = d.find("<f ", om.region(d)[1] if om.region(d) else 0)
                return d[i:] if i >= 0 else ""
            check(ranked(doc) == ranked(bdoc), "(C) %s: O-narrow's ranked rows are byte-identical to the base binary's" % label)


# ── the fixture ──────────────────────────────────────────────────────────────────────────────────────────────────────
print("== fixture ==")
M = model(FX)
orc = M["orc"]
if orc["ambiguous"] or orc["G"] != "src/pkg/" or len(orc["order"]) < 14 or len(orc["ranked"]) < 40:
    print("orientmapcheck: the fixture no longer exercises the rule decisively (G=%r, %d groups, %d overflow names, %d ambiguous: %s)"
          % (orc["G"], len(orc["order"]), len(orc["ranked"]), len(orc["ambiguous"]), orc["ambiguous"][:3]))
    sys.exit(1)
s = M["secs"]
print("== (F) the registered rule, exactly ==")
check(M["rc"] == 0, "(F) the map exits 0")
if check("subsystems" in s, "(F) the map carries <subsystems>"):
    sub = s["subsystems"]
    check(sub.a.get("g") == orc["G"], "(F) g= is the grouping root %r" % orc["G"], "got %r" % sub.a.get("g"))
    want = [(lab, str(len(orc["members"][lab])), [om.printed(p, orc["G"]) for p in orc["members"][lab][:3]]) for lab in orc["order"][:12]]
    got = [(grp.a.get("l"), grp.a.get("n"), [m.a.get("p") for m in grp.find("m")]) for grp in sub.find("grp")]
    check(got == want, "(F) the 12 group rows: labels, n= and top-3 members, in mass order",
          "first difference: %r" % (next(((a, b) for a, b in zip(got + [None] * 12, want) if a != b), None),))
    check(sub.a.get("total") == str(len(orc["order"])) and sub.a.get("shown") == str(min(12, len(orc["order"]))),
          "(F) <subsystems> total=%d shown=%d" % (len(orc["order"]), min(12, len(orc["order"]))), str(sub.a))
if check("overflow" in s, "(F) the map carries <overflow>"):
    ov = s["overflow"]
    k = int(ov.a.get("shown", "-1"))
    check(ov.a.get("total") == str(len(orc["ranked"])), "(F) <overflow> total= is every core file not named in the group rows (%d)" % len(orc["ranked"]), str(ov.a))
    surv = orc["ranked"][:max(k, 0)]
    regroup = []
    for lab in orc["order"]:
        ps = [p for p in orc["members"][lab] if (lab, p) in set(surv)]
        if ps:
            regroup.append((lab, [om.printed(p, orc["G"]) for p in ps]))
    got = [(grp.a.get("l"), [m.a.get("p") for m in grp.find("m")]) for grp in ov.find("grp")]
    check(k > 0 and got == regroup, "(F) <overflow> is the first %d of the breadth-first list, re-grouped in group then member order" % k,
          "first difference: %r" % (next(((a, b) for a, b in zip(got + [None] * 30, regroup) if a != b), None),))
    check(0 < k < len(orc["ranked"]), "(F) the fixture's overflow is cut (the cap binds: %d of %d)" % (k, len(orc["ranked"])))
if check("entry_points" in s, "(F) the map carries <entry_points>"):
    ep = s["entry_points"]
    rows = [(e.a.get("p", "").rsplit(":", 1)[0], e.a.get("why"), e.a.get("n")) for e in ep.find("e")]
    want = [("src/pkg/tool.ts", "bin"), ("src/pkg/cli_main.py", "main"), ("src/pkg/index.ts", "entry")]
    check([(p, w) for p, w, _ in rows] == want, "(F) entry rows: the bin's source twin, the main definition, the '.' export — in evidence order", str(rows))
    mainrow = [e for e in ep.find("e") if e.a.get("why") == "main"]
    check(len(mainrow) == 1 and mainrow[0].a.get("p") == "src/pkg/cli_main.py:5" and mainrow[0].a.get("n") == "main",
          "(F) the main row is src/pkg/cli_main.py:5 n=main (not main_loop)", str([e.a for e in mainrow]))
    check(not any("nosuchstem" in e.a.get("p", "") for e in ep.find("e")), "(F) a bin with no source twin has no row")
    tot = int(ep.a.get("total", "0"))
    check(tot >= len(rows) + 1 and "next" in ep.a, "(F) the subpath export counts in total= and is one next= away", str(ep.a))
    if "next" in ep.a:
        prow, _ = om.follow(BIN, FX, ep.a["next"], "why")
        check(any(r.get("p", "").startswith("src/pkg/sub.ts") for r in prow), "(F) entry_points next= returns the subpath export's source (src/pkg/sub.ts)", str(prow))
check(M["dcount"] is not None and "src/pkg/compat/queue_compat.py" in M["dem"], "(F) the compat file is demoted (utility_demoted= + next=)")

print("== (D) disclosure ==")
gate_d(M, "fixture")
print("== (U) uncapped variant ==")
uncapped(M, "fixture")
print("== (P) parity ==")
parity(M, "fixture")

print("== (N) not applied ==")
for args in (["--tree"], ["--rank-by=authority"], ["--rank-by=hub"], ["--rank-by=rrf"], ["--for=where is the request handled"]):
    d, _ = om.run(BIN, FX, *args)
    check(om.region(d) is None and "utility_demoted" not in d, "(N) %s carries no section and no utility_demoted=" % " ".join(args))
rb_auth, explore = om.mcp(BIN, FX, [("rank_by", {"rank_by": "authority"}), ("explore", {"task": "where is the request handled"})])
for k, d in (("MCP rank_by authority", rb_auth), ("MCP explore", explore)):
    check(om.region(d) is None and "utility_demoted" not in d, "(N) %s carries no section and no utility_demoted=" % k)
dirty = os.path.join(TMP, "fxdirty")
shutil.copytree(FX, dirty)
with open(os.path.join(dirty, "src/pkg/io.py"), "a") as fh:
    fh.write("\n\ndef io_layer_uncommitted(value):\n    return value\n")
(dan,) = om.mcp(BIN, dirty, [("analyze", {})])
check(om.region(dan) is None and "utility_demoted" not in dan, "(N) MCP analyze with an uncommitted edit carries no section")

print("== (L) legend and dictionary ==")
newattrs = set()
for t, node in s.items():
    for n in om.walk([node]):
        if t == "demoted" and n is node:
            newattrs.update(("utility_demoted", "next") if "next" in n.a else ("utility_demoted",))
        elif t != "demoted":
            newattrs.update(n.a.keys())
tags = [t for t in om.NEW_TAGS if any(n.tag == t for n in om.walk(list(v for k, v in s.items() if k != "demoted")))]
def undefined(text):
    return sorted(a for a in newattrs if not re.search(r"(?<![\w-])" + re.escape(a) + "=", text)) + \
           sorted("<%s>" % t for t in tags if not re.search(r"(?<![\w-])" + re.escape(t) + r"(?![\w-])", text))
an_c, = om.mcp(BIN, FX, [("analyze", {})])
srcs = {"compact XML legend": om.legend(M["doc"]), "full XML legend": om.legend(om.run(BIN, FX, "--legend=full")[0]),
        "MCP analyze legend": om.legend(an_c),
        "--help=all": subprocess.run([BIN, "--help=all"], capture_output=True, text=True).stdout,
        "--legend-dict": subprocess.run([BIN, "--legend-dict"], capture_output=True, text=True).stdout}
check(bool(newattrs), "(L) the sections carry attributes to define", "no sections")
for k, text in srcs.items():
    u = undefined(text) if newattrs else ["(no sections)"]
    check(not u, "(L) %s defines every new attribute and names every new tag" % k, str(u))
(an_ref,) = om.mcp(BIN, FX, [("analyze", {})], ref=True)
u = undefined(srcs["--legend-dict"] + om.legend(an_ref)) if newattrs else ["(no sections)"]
check(not u and om.region(an_ref) is not None, "(L) MCP legend=ref analyze: sections present, every definition in the dictionary or the answer", str(u))

print("== (C) cost ==")
cost(M, "fixture", deciding=False)

print("== (X) well-formed and deterministic ==")
if shutil.which("xmllint"):
    x = subprocess.run(["xmllint", "--noout", "-"], input=M["doc"].encode(), capture_output=True)
    check(x.returncode == 0, "(X) the map is well-formed XML", x.stderr.decode()[:200])
check(om.run(BIN, FX)[0] == M["doc"], "(X) two runs are byte-identical")

for extra in [e for e in EXTRA.split(":") if e]:
    lab = os.path.basename(extra.rstrip("/"))
    print("== extra root %s ==" % lab)
    E = model(extra)
    if E["orc"]["ambiguous"]:
        print("  INFO  %s: %d oracle comparisons the 4-dp k= cannot decide (order there is not asserted)" % (lab, len(E["orc"]["ambiguous"])))
    gate_d(E, lab)
    uncapped(E, lab)
    parity(E, lab)
    cost(E, lab)

print("orientmapcheck: %d failure(s)" % len(fails))
sys.exit(1 if fails else 0)
PYEOF
if [ "$fail" -ne 0 ]; then
    echo "orientmapcheck: FAILURES ABOVE"
    exit 1
fi
echo "orientmapcheck: all arms PASS"
exit 0
