#!/usr/bin/env bash
# orientmapcheck.sh — the default whole-repo map orients: entry points with evidence, a subsystem grouping, every core
# file named once (inside a 2,048 B overflow, the rest one next= away), utility sinks and vendored code in one counted
# tail (fix list #8, the registered orient-map v2 arms O / O-narrow; docs/EVALS.md "A default map that orients").
#
# WRITTEN BEFORE THE CODE IT MEASURES (CLAUDE.md non-negotiable #1): on the pre-change binary every arm that needs the
# sections is RED, and the arms about what must NOT change are green. The section schema, the label/path conventions
# and the classifier/oracle live in test/lib/orientmap.py (its docstring is the schema).
#
# Arms, on the generated fixture (test/orientmapfix/gen.sh, a committed git tree so MCP analyze sees a clean working set;
# the oracle must decide every comparison it makes and the two designed ties must print equal k=, or the fixture fails):
#   (F) THE RULE, exactly: g= is the registered grouping root; <subsystems> lists the first 12 groups in mass order (ties by
#       label) with n= and the top 3 members (ties by path); <overflow> holds a PREFIX of the breadth-first list of every core
#       file not yet named, re-grouped in group order; total=/shown=/capped= are the rule's own counts; <entry_points> lists
#       evidence from CORE files only, in evidence order (bin/script, `main`, entry module), within a class by file mass then
#       path, at most 5 rows; total= counts core evidence only (a bin with no source twin, a bin into tests/, and `main` in a
#       test, fixture or vendored file are neither listed nor counted); the demoted set is EXACTLY the compat file and the
#       utility sink (pinned here; the vendored file is not indexed at all).
#   (D) DISCLOSURE (Gate D): each next= (entry points, subsystems, overflow, utility_demoted) and then next_offset= pages
#       EXACTLY what its element cut, in rank order, each once, every page <= K rows; on the fixture the pages equal the
#       oracle's (groups 13.. with n=, the overflow's breadth-first tail, the demoted set); no file is named twice across
#       <subsystems> and <overflow>; every name is a core file; named + paged = every core file; a group's n= is its size.
#   (U) UNCAPPED (the reported variant, RIPWIRE_ORIENT_UNCAPPED=1): <overflow> is the whole breadth-first list, capped="0"
#       unless the runaway ceiling fired, and every byte outside <overflow> is the capped answer's.
#   (P) PARITY (Gate P): the bytes from the first section tag to the end of the last are identical on the CLI map (compact,
#       --legend=full, --top-k=16, --max-tokens=4000, --max-tokens=200 — the sections are never budgeted away —,
#       --rank-by=pagerank), MCP analyze (clean tree: {}, compact, full, paths:[ROOT], an untracked-only change, a non-git
#       root, a legend=ref session) and MCP rank_by (omitted, pagerank, pagerank+full); --json and --json --max-tokens=4000
#       carry the same sections row for row; --html carries every label and name.
#   (N) NOT APPLIED: --tree, --rank-by=authority|hub|rrf, --for, MCP analyze with a tracked edit, a staged-only change or a
#       README-only edit, MCP analyze over two roots, MCP rank_by authority and MCP explore carry no section and no
#       utility_demoted=.
#   (L) LEGEND (Gate D, G4): every new element's attributes are defined by a `<tag attr= …>` spelling of THAT element in the
#       compact and full XML legends, the MCP analyze legend, --help=all (the --json keys' legend) and the session dictionary
#       (and, with ORIENTMAP_BASE_BIN, that spelling is new to the dictionary); in a legend=ref session the definition reaches
#       the session at most once (legenddict.h serves an entry lazily, with the first answer that needs it), every ref answer
#       ends with <about legend="ref"> naming the dictionary's dictv=, and leans only on the dictionary or itself.
#   (C) COST, explain-or-fail (owner 2026-10-02): the registered numbers are TARGETS — sections <= 4,096 B, <overflow> <=
#       2,048 B, map growth vs ORIENTMAP_BASE_BIN <= +4,096 B. An excess passes only when test/orientmapfix/cost_explanations.tsv
#       (or ORIENTMAP_COST_EXPLAIN) states which content and why the answer needs it; it is then reported, never cut. The
#       first section starts within 1,024 B of the answer BODY (after the leading legend). No further overflow name fits
#       the cut. A section carrying over_ceiling="1" (the runaway guard) is listed as a bug signal. A byte breakdown is
#       printed. With ORIENTMAP_BASE_BIN: every ranked row's k= equals the base binary's (the rank vector is untouched), and
#       with ORIENTMAP_ARM=narrow the ranked rows are byte-identical to the base binary's.
#   (X) xmllint well-formed, two runs byte-identical.
# O-narrow v3 (PREREG_orient_narrow_v3; the blind O2 grading's false rows on hono-01 and the final review's M1), on a second
# fixture (test/orientmapfix/gen_truth.sh) and, for the generic halves, inside (D) on every root:
#   (E) ENTRY ROWS name only exported/public program or package entries: a module-level `main` function or a JVM static
#       main (never a method named main on a helper class); a manifest bin/script/entry module named by the module's first
#       function, class or type its own syntax exports (ES `export`, `export {…}`/`export default NAME`, CommonJS
#       `module.exports`/`exports.X`), else by its module scope <file-scope> at line 1 — never a non-exported alias, a
#       private helper or a constant; a pyproject script by the function it names when the module defines it, else
#       <file-scope>; a build-output path maps only to a same-stem source one source root away (dist/cjs/index.js <-
#       src/index.ts, never the heavier src/jsx/hooks/index.ts). (D) adds on every root: a named row's symbol is declared
#       on its line and is not a constant (t=var).
#   (G) GROUP LABELS are true of every member (shown, overflow and paged): `X/` only when every member sits under X/; a
#       file beside X/ that joins its group by prefix makes the label `X` (`/X` outside g=); a nested X/X.ts keeps `X/`.
#   (M) MEMORY-GUARD PARTIAL INGEST (RIPWIRE_TEST_MEMGUARD=parse:N): the CLI map (XML and --json) and MCP analyze /
#       rank_by carry no section and no utility_demoted= (their totals would be floors with no marker); --orient=KIND
#       refuses (exit 5) like every other selector on a partial index. Byte-neutral on a whole ingest (Gate S).
# ORIENTMAP_EXTRA_ROOTS=dir1:dir2 runs (D), (U), (P) and (C) on those trees too; ORIENTMAP_ONLY_EXTRA=1 skips the fixture.
# Exit 0 all pass, 1 any fail (a fixture the oracle cannot decide is a failure), 2 setup.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
GEN="$ROOT/test/orientmapfix/gen.sh"
GEN_TRUTH="$ROOT/test/orientmapfix/gen_truth.sh"
[ -x "$BIN" ] || { echo "orientmapcheck: no ripwire binary at $BIN — build first"; exit 2; }
[ -f "$GEN" ] && [ -f "$GEN_TRUTH" ] || { echo "orientmapcheck: fixture generator missing: $GEN / $GEN_TRUTH"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "orientmapcheck: git not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "orientmapcheck: python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
export TMPDIR="$TMP/" XDG_CACHE_HOME="$TMP/xdg"
unset RIPWIRE_ORIENT_UNCAPPED
echo "orientmapcheck: BIN=$BIN"
mkfix(){
    bash "${2:-$GEN}" "$1" >/dev/null && git -C "$1" init -q && git -C "$1" add -A \
        && git -C "$1" -c user.name=gate -c user.email=gate@example.invalid -c commit.gpgsign=false commit -qm fixture
}
mkfix "$TMP/fx" || { echo "orientmapcheck: fixture generation failed"; exit 2; }
mkfix "$TMP/fx2" "$GEN_TRUTH" || { echo "orientmapcheck: truth fixture generation failed"; exit 2; }

python3 - "$BIN" "$TMP" "$ROOT" "${ORIENTMAP_EXTRA_ROOTS:-}" <<'PYEOF' || no "the arms above reported a failure (or the check body could not run)"
import html as H, json, os, re, shlex, shutil, subprocess, sys
BIN, TMP, ROOT, EXTRA = sys.argv[1:5]
sys.path.insert(0, os.path.join(ROOT, "test", "lib"))
import orientmap as om

BASE_BIN = os.environ.get("ORIENTMAP_BASE_BIN", "")
ARM = os.environ.get("ORIENTMAP_ARM", "O")
ONLY_EXTRA = os.environ.get("ORIENTMAP_ONLY_EXTRA") == "1"
UNC = {"RIPWIRE_ORIENT_UNCAPPED": "1"}
FX = os.path.join(TMP, "fx")
FIX_DEMOTED = {"src/pkg/compat/list_shim.py", "src/pkg/util/blockpool.py"}
fails = []


def ok(m):
    print("  PASS  " + m)


def no(m):
    print("  FAIL  " + m)
    fails.append(m)


def check(cond, m, why=""):
    (ok if cond else no)(m + ("" if cond or not why else ": " + why))
    return cond


def explanations():
    out = {}
    for path in (os.path.join(ROOT, "test", "orientmapfix", "cost_explanations.tsv"), os.environ.get("ORIENTMAP_COST_EXPLAIN", "")):
        if path and os.path.isfile(path):
            for line in open(path):
                f = line.rstrip("\n").split("\t")
                if len(f) >= 3 and not line.startswith("#") and f[2].strip():
                    out[(f[0], f[1])] = f[2].strip()
    return out


EXPLAIN = explanations()


def model(root, pinned=None):
    """the answer, its sections, the inventory, the demoted set and the oracle over core = candidates - demoted"""
    doc, rc = om.run(BIN, root)
    secs = om.sections(doc)
    inv, invj = om.inventory(BIN, root)
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
    core = [p for p in cand if p not in set(pinned if pinned is not None else dem)]
    syms = {f["p"]: [(s_.get("n"), s_.get("t")) for s_ in f.get("s", [])] for f in invj.get("r", [])}
    return dict(root=root, doc=doc, rc=rc, secs=secs, inv=inv, syms=syms, ms=ms, cand=cand, dem=dem, dprob=dprob, dcount=dcount,
                core=core, orc=om.oracle(core, ms))


def names(node, g):
    """[(label, [repo paths])] of a <subsystems>/<overflow> node"""
    return [(grp.a.get("label"), [om.unrel(m.a.get("p", ""), g) for m in grp.find("m")]) for grp in node.find("grp")]


def runaway(M, label, doc=None, what="answer"):
    hit = [n.tag for n in om.walk(om.tree(doc if doc is not None else M["doc"])) if n.a.get("over_ceiling") == "1"
           and (n.tag in om.SECTION_TAGS or "utility_demoted" in n.a)]
    check(not hit, "(C) %s %s: no section hit the runaway ceiling" % (label, what), "BUG SIGNAL, over_ceiling on %s" % hit)


def gate_d(M, label, exact=False):
    """(D) on one root: counts, next= recovery (against the oracle when exact), core-ness, once-only, completeness"""
    s, root, orc = M["secs"], M["root"], M["orc"]
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
    false_lab = false_labels(printed_groups(sub) + printed_groups(ov) + (paged_groups(root, sub.a["next"]) if "next" in sub.a else []))
    check(not false_lab, "(D)(G) %s: every group label is true of every member it lists, shown and paged (X/ only under X/; a bare X by "
          "prefix or under X/)" % label, str(false_lab[:5]))
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
        if exact:
            k = int(ov.a.get("shown", 0))
            check(cut == [p for _, p in orc["ranked"][k:]], "(D) %s: overflow next= pages the oracle's breadth-first tail, in order" % label)
    missing = sorted(set(M["core"]) - set(shown) - set(cut))
    check(not missing, "(D) %s: named + paged = every core file (%d)" % (label, len(M["core"])), "%d missing, e.g. %s" % (len(missing), missing[:5]))
    sizes = {lab: str(len(ps)) for lab, ps in orc["members"].items()}
    gdecided = not any(a.startswith("G descent") for a in orc["ambiguous"]) and g == orc["G"]
    if "next" in sub.a:
        rows, probs = om.follow(BIN, root, sub.a["next"], "label")
        labs = [r["label"] for r in rows]
        allg = [l for l, _ in names(sub, g)] + labs
        check(not probs and len(allg) == len(set(allg)) and len(allg) == int(sub.a["total"]),
              "(D) %s: subsystems next= pages the %d groups past the shown ones, each once" % (label, int(sub.a["total"]) - int(sub.a["shown"])),
              "; ".join(probs[:3]) or "%d labels" % len(allg))
        if exact:
            check([(r["label"], r.get("n")) for r in rows] == [(l, sizes[l]) for l in orc["order"][12:]],
                  "(D) %s: subsystems next= pages the oracle's groups 13.. in order, each with its n=" % label)
        elif gdecided:
            badn = [(r["label"], r.get("n")) for r in rows if r["label"] in sizes and r.get("n") != sizes[r["label"]]]
            check(not badn, "(D) %s: every paged group's n= is its core-file count" % label, str(badn[:5]))
    if gdecided:
        badn = [(grp.a.get("label"), grp.a.get("n")) for grp in sub.find("grp") if sizes.get(grp.a.get("label")) != grp.a.get("n")]
        check(not badn, "(D) %s: every group row's n= is its core-file count" % label, str(badn[:5]))
    if "entry_points" in s:
        ep = s["entry_points"]
        for e in ep.find("e"):
            mm = re.match(r"(.+):(\d+)$", e.a.get("p", ""))
            f = mm and os.path.join(root, mm.group(1))
            good = bool(mm) and e.a.get("why") in om.WHY and e.a.get("n") and os.path.isfile(f) and entry_file_ok(M, mm.group(1)) \
                and 1 <= int(mm.group(2)) <= max(1, sum(1 for _ in open(f, errors="replace")))
            check(good, "(D) %s: entry row %s is a core file (or a codeless source entry module), file:line inside it, n= and why=" % (label, e.a))
            if good:
                check(entry_symbol_true(M, mm.group(1), int(mm.group(2)), e.a.get("n"), e.a.get("why")),
                      "(D)(E) %s: entry row %s names its module scope at line 1, or a symbol declared on that line that is not a constant "
                      "(JS/TS bin/entry: exported by its own syntax; Python script: not _private)" % (label, e.a))
        if "next" in ep.a:
            rows, probs = om.follow(BIN, root, ep.a["next"], "why")
            check(not probs and len(rows) == int(ep.a["total"]) - int(ep.a["shown"]) and all(r.get("why") in om.WHY for r in rows)
                  and all(entry_file_ok(M, r.get("p", "").rsplit(":", 1)[0]) for r in rows),
                  "(D) %s: entry_points next= returns the %d core entries not listed, each with why=" % (label, int(ep.a["total"]) - int(ep.a["shown"])))
            badp = [r for r in rows if not re.match(r".+:\d+$", r.get("p", ""))
                    or not entry_symbol_true(M, r["p"].rsplit(":", 1)[0], int(r["p"].rsplit(":", 1)[1]), r.get("n"), r.get("why"))]
            check(not badp, "(D)(E) %s: every PAGED entry row names its module scope at line 1 or a true, exported, non-constant symbol" % label,
                  str(badp[:3]))
    if M["dcount"] is None:
        no("(D) %s: no utility_demoted= anywhere in the answer" % label)
    else:
        check(not M["dprob"] and M["dcount"] == len(M["dem"]) == len(set(M["dem"])),
              "(D) %s: utility_demoted=%d equals the files its next= returns, each once" % (label, M["dcount"]),
              "; ".join(M["dprob"][:3]) or "next= returned %d" % len(M["dem"]))
        vend = sorted(p for p in M["cand"] if om.is_vendored(p) and p not in M["dem"])
        check(not vend, "(D) %s: every vendored/compat core candidate is demoted" % label, str(vend[:5]))
        if ARM != "narrow":
            ranked_files = {f.a.get("p") for f in om.walk(om.tree(M["doc"])) if f.tag == "f"}
            check(not (ranked_files & set(M["dem"])), "(D) %s: no demoted file keeps a ranked row" % label)
    runaway(M, label)


JS_EXTS = (".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs")


def js_exported(lines, line, n):
    """does the module's own syntax export the symbol n declared on `line`? `export`/`module.exports`/`exports.` before the
    name on its line, a local `export {… n …}` clause (not `… from`), `export default n`, `module.exports = n`, or
    `[module.]exports.X = n` / `[module.]exports.n =`"""
    L = lines[line - 1]
    m = re.search(r"\b%s\b" % re.escape(n), L)
    if m and re.search(r"\bexport\b|\bmodule\.exports\b|\bexports\.", L[:m.start()]):
        return True
    whole = "\n".join(lines)
    e = re.escape(n)
    for pat in (r"\bexport\s+default\s+%s\b" % e, r"\bmodule\.exports\s*=\s*%s\b" % e, r"\bexports\.[\w$]+\s*=\s*%s\b" % e,
                r"\bexports\.%s\s*=" % e):
        if re.search(pat, whole):
            return True
    for c in re.finditer(r"\bexport\s*(?:type\s*)?\{([^}]*)\}(?!\s*from\b)", whole):
        if n in [x.strip().split(" as ")[0].strip() for x in c.group(1).split(",")]:
            return True
    return False


def entry_file_ok(M, path):
    """an entry row's file: a core file, or a source-tier, non-demo, non-vendored file the index holds no code symbol for
    (a re-export-only package entry module, hono's src/index.ts shape)"""
    if path in set(M["core"]):
        return True
    has_code = bool(set(M["inv"].get(path, set())) - set(om.NONCODE_KINDS))
    return (os.path.isfile(os.path.join(M["root"], path)) and not has_code and om.tier(path) == "source" and not om.is_demo(path)
            and not om.is_vendored(path))


def entry_symbol_true(M, path, line, n, why=None):
    """an entry row names <file-scope> at line 1, or a symbol of that file declared on that line whose kind is not var; a JS/TS
    bin/entry row's symbol is exported by the module's own syntax; a Python script row never names a _private function"""
    if n == "<file-scope>":
        return line == 1
    try:
        text = open(os.path.join(M["root"], path), errors="replace").read().split("\n")
    except OSError:
        return False
    kinds = {t for nm, t in M["syms"].get(path, []) if nm == n}
    if not (1 <= line <= len(text) and re.search(r"\b%s\b" % re.escape(n), text[line - 1]) is not None and bool(kinds) and "var" not in kinds):
        return False
    if why in ("bin", "entry") and path.endswith(JS_EXTS) and not js_exported(text, line, n):
        return False
    if why == "script" and path.endswith(".py") and n.startswith("_"):
        return False
    return True


def false_labels(groups):
    """[(label, printed member)] where a label is not true of a member; groups = [(label, [printed paths])]"""
    return [(lab, p) for lab, ps in groups for p in ps if not om.label_true(lab, p)]


def printed_groups(node):
    return [(grp.a.get("label", ""), [m.a.get("p", "") for m in grp.find("m")]) for grp in node.find("grp")]


def paged_groups(root, nxt, env=None):
    """every <grp> row (label, printed top members) a subsystems next= pages, through next_offset="""
    out, args = [], shlex.split(nxt)
    for _ in range(om.MAX_PAGES):
        doc, rc = om.run(BIN, root, *args, env=env)
        forest = om.tree(doc)
        if rc != 0 or not forest:
            break
        top = forest[0]
        out += printed_groups(top)
        if top.a.get("has_more") != "1" or "next_offset" not in top.a:
            break
        args = [x for x in args if not x.startswith("--offset=")] + ["--offset=" + top.a["next_offset"]]
    return out


def uncapped(M, label):
    """(U) the uncapped variant: the whole breadth-first list, nothing else moved; and it reconstructs the capped cut"""
    doc2, _ = om.run(BIN, M["root"], env=UNC)
    s1, s2 = M["secs"], om.sections(doc2)
    if not check("overflow" in s1 and "overflow" in s2, "(U) %s: both variants carry <overflow>" % label):
        return
    o1, o2 = s1["overflow"], s2["overflow"]
    d1, d2 = M["doc"], doc2
    def unpriced(t):   # est_tokens= prices the answer AS EMITTED, so it moves with the overflow's bytes; nothing else may
        return re.sub(r'est_tokens=("?)\d+', r"est_tokens=\1#", t)
    check(unpriced(d1[:o1.start]) == unpriced(d2[:o2.start]) and unpriced(d1[o1.end:]) == unpriced(d2[o2.end:]),
          "(U) %s: every byte outside <overflow> is the capped answer's (est_tokens= aside: it prices the answer as emitted)" % label)
    runaway(M, label, doc2, "uncapped answer")
    if "subsystems" in s2:
        fl = false_labels(printed_groups(s2["subsystems"]) + printed_groups(o2)
                          + (paged_groups(M["root"], s2["subsystems"].a["next"], env=UNC) if "next" in s2["subsystems"].a else []))
        check(not fl, "(U)(G) %s: every label of the uncapped answer (groups, overflow, paged groups) is true of every member" % label, str(fl[:5]))
    if o2.a.get("over_ceiling") != "1":
        check(o2.a.get("capped") == "0" and "next" not in o2.a and o2.a.get("shown") == o2.a.get("total"), "(U) %s: uncapped <overflow> cuts nothing" % label)
    sub = s1["subsystems"]
    g = sub.a.get("g", "")
    full = {lab: list(ps) for lab, ps in names(sub, g)}
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
    if "next" in o1.a and o2.a.get("over_ceiling") != "1":
        rows, _ = om.follow(BIN, M["root"], o1.a["next"], "p")
        check([r["p"] for r in rows] == ranked[k:], "(U) %s: overflow next= pages the rest of that list in rank order" % label)
    if o1.a.get("capped") == "0":
        check(d1 == d2, "(U) %s: under the cap the uncapped answer is byte-identical" % label)


def json_rows_match(doc, secs):
    j = json.loads(doc)
    bad = []
    for tag, node in secs.items():
        if tag == "demoted":
            continue
        jo = j.get(tag)
        if not isinstance(jo, dict):
            bad.append(tag + " absent")
            continue
        for k, v in node.a.items():
            if str(jo.get(k)) != v:
                bad.append("%s.%s %r != %r" % (tag, k, jo.get(k), v))
        kt = "e" if tag == "entry_points" else "grp"
        xr = [(c.tag, sorted(c.a.items()), [sorted(x.a.items()) for x in c.kids]) for c in node.kids]
        jr = [(kt, sorted((k, str(v)) for k, v in c.items() if k != "m"), [sorted((k, str(v)) for k, v in x.items()) for x in c.get("m", [])])
              for c in jo.get(kt, [])]
        if xr != jr:
            bad.append(tag + " rows differ")
    return bad


def parity(M, label):
    root = M["root"]
    r0 = om.region(M["doc"])
    if not check(r0 is not None, "(P) %s: the CLI map carries the sections" % label):
        return
    ref = M["doc"][r0[0]:r0[1]]
    variants = {a: om.run(BIN, root, *a.split())[0] for a in ("--legend=full", "--top-k=16", "--max-tokens=4000", "--max-tokens=200", "--rank-by=pagerank")}
    calls = [("analyze", {}), ("analyze", {"legend": "compact"}), ("analyze", {"legend": "full"}), ("analyze", {"paths": [root]}),
             ("rank_by", {}), ("rank_by", {"rank_by": "pagerank"}), ("rank_by", {"rank_by": "pagerank", "legend": "full"})]
    for (tool, a), d in zip(calls, om.mcp(BIN, root, calls)):
        variants["MCP %s %s" % (tool, json.dumps(a, sort_keys=True).replace(root, "ROOT"))] = d
    refs = om.mcp(BIN, root, [("analyze", {}), ("analyze", {}), ("analyze", {})], ref=True)
    for i, d in enumerate(refs):
        variants["MCP legend=ref session analyze #%d" % (i + 1)] = d
    bad = [k for k, d in variants.items() if om.region(d) is None or d[om.region(d)[0]:om.region(d)[1]] != ref]
    check(not bad, "(P) %s: section bytes identical on %d CLI/MCP in-scope variants" % (label, len(variants)), str(bad))
    for args in (["--json"], ["--json", "--max-tokens=4000"]):
        jb = json_rows_match(om.run(BIN, root, *args)[0], M["secs"])
        check(not jb, "(P) %s: %s carries the same sections row for row" % (label, " ".join(args)), "; ".join(jb[:4]))
    hp = os.path.join(TMP, "h.html")
    om.run(BIN, root, "--html=" + hp)
    ht = open(hp, errors="replace").read() if os.path.exists(hp) else ""
    want = [n.a.get("label") or n.a.get("p") for n in om.walk([M["secs"][t] for t in ("subsystems", "overflow") if t in M["secs"]]) if n.tag in ("grp", "m")]
    miss = [w for w in want if w and w not in ht and H.escape(w) not in ht and json.dumps(w)[1:-1] not in ht]
    check(bool(want) and not miss, "(P) %s: --html carries every section label and name" % label, str(miss[:5]))
    return refs


def cost(M, label):
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
    s = M["secs"]
    parts = {t: s[t].end - s[t].start for t in om.SECTION_TAGS if t in s}
    ranked = len(doc) - r[1]
    print("  INFO  (C) %s: bytes — leading legend %d, root/header %d, %s, ranked rows and tail %d; answer %d; first section at "
          "byte %d (body offset %d)" % (label, lead_end, r[0] - lead_end, ", ".join("%s %d" % kv for kv in parts.items()), ranked,
                                         len(doc), r[0], r[0] - lead_end))

    def target(metric, val, cap):
        if val <= cap:
            ok("(C) %s: %s %d B within the %d B target" % (label, metric, val, cap))
        elif (label, metric) in EXPLAIN:
            ok("(C) %s: %s %d B over the %d B target, EXPLAINED: %s" % (label, metric, val, cap, EXPLAIN[(label, metric)]))
        else:
            no("(C) %s: %s %d B over the %d B target with no stated reason (add a row to test/orientmapfix/cost_explanations.tsv "
               "or ORIENTMAP_COST_EXPLAIN: which content, and why the answer needs it)" % (label, metric, val, cap))
    target("sections", r[1] - r[0], om.SECTIONS_CAP)
    check(r[0] - lead_end <= om.START_CAP, "(C) %s: the first section starts within %d B of the body (%d)" % (label, om.START_CAP, r[0] - lead_end))
    ov = s.get("overflow")
    if ov is not None:
        ob = ov.end - ov.start
        target("overflow", ob, om.OVERFLOW_CAP)
        if ov.a.get("capped") == "1" and "next" in ov.a and ov.a.get("over_ceiling") != "1":
            rows, _ = om.follow(BIN, M["root"], ov.a["next"], "p")
            if rows:
                g = ov.a.get("g", s["subsystems"].a.get("g", "")) if "subsystems" in s else ""
                nxt = rows[0]["p"]
                lab = next((l for l, ps in M["orc"]["members"].items() if nxt in ps), None)
                add = len('<m p="%s"/>' % H.escape(om.printed(nxt, g)))
                if lab not in {grp.a.get("label") for grp in ov.find("grp")}:
                    add += len('<grp label="%s"></grp>' % H.escape(lab or ""))
                check(ob + add > om.OVERFLOW_CAP, "(C) %s: the first cut name would not have fit (%d + %d B)" % (label, ob, add))
    if BASE_BIN:
        bdoc, _ = om.run(BASE_BIN, M["root"])
        target("growth", len(doc) - len(bdoc), om.GROWTH_CAP)
        _, ja = om.masses(BIN, M["root"])
        _, jb = om.masses(BASE_BIN, M["root"])
        def rows(j, skip):
            return sorted((f["p"], s_.get("t"), s_.get("n"), s_.get("sc", ""), s_.get("k")) for f in j.get("r", []) if f["p"] not in skip for s_ in f.get("s", []))
        skip = set(M["dem"]) if ARM != "narrow" else set()
        check(rows(ja, skip) == rows(jb, skip), "(C) %s: every ranked row's k= equals the base binary's (the rank vector is untouched)" % label)
        if ARM == "narrow":
            def ranked_rows(d):
                # the rows start after the orient region, or — on the base binary's map, which has none — after the root's
                # open tag: searching from byte 0 there landed on the compact LEGEND's own "<f p= layer=>" spelling (first
                # narrow corpus leg, 2026-10-02) and compared legend text to rows. Corrected before any narrow data was graded.
                rr = om.region(d)
                start = rr[1] if rr else d.find(">", d.find("<r ")) + 1
                i = d.find("<f ", start)
                return d[i:] if i >= 0 else ""
            rn, rb = ranked_rows(doc), ranked_rows(bdoc)
            check(rn.startswith("<f ") and rb.startswith("<f "), "(C) %s: both ranked-row extractions start at a row" % label)
            check(rn == rb, "(C) %s: O-narrow's ranked rows are byte-identical to the base binary's" % label)


def legend_arm(M, refs):
    s = M["secs"]
    elems = {}
    for t, node in s.items():
        for n in (om.walk([node]) if t != "demoted" else [node]):
            elems.setdefault(n.tag, set()).update(n.a.keys())
    if not check(bool(elems), "(L) the sections carry elements to define"):
        return
    print("  INFO  (L) new elements and attributes: %s" % {k: sorted(v) for k, v in elems.items()})
    an_c, = om.mcp(BIN, M["root"], [("analyze", {})])
    dict_txt = subprocess.run([BIN, "--legend-dict"], capture_output=True, text=True).stdout
    srcs = {"compact XML legend": om.legend(M["doc"]), "full XML legend": om.legend(om.run(BIN, M["root"], "--legend=full")[0]),
            "MCP analyze legend": om.legend(an_c), "--help=all": subprocess.run([BIN, "--help=all"], capture_output=True, text=True).stdout,
            "--legend-dict": dict_txt}
    for k, text in srcs.items():
        u = sorted("<%s %s>" % (t, " ".join(a + "=" for a in sorted(at))) for t, at in elems.items() if not om.defines(text, t, at))
        check(not u, "(L) %s spells every new element with all of its attributes" % k, str(u))
    if BASE_BIN:
        bd = subprocess.run([BASE_BIN, "--legend-dict"], capture_output=True, text=True).stdout.splitlines()
        newtags = [t for t in elems if t in om.SECTION_TAGS + ("grp",) or "utility_demoted" in elems[t]]
        stale = [t for t in newtags if not any(om.defines(l, t, elems[t]) for l in dict_txt.splitlines() if l not in set(bd))]
        check(not stale, "(L) the dictionary defines each new element on a line the base binary's dictionary lacks", str(stale))
    m = re.search(r"dictv=(\S+)", dict_txt)
    dictv = m.group(1) if m else None
    is_ref = [bool(re.search(r'<about [^>]*legend="ref"', d)) for d in refs]
    check(any(is_ref), "(L) a legend=ref session serves analyze in ref posture (after the first answer)", str(is_ref))
    badr = []
    carried = 0
    for i, d in enumerate(refs):
        if not is_ref[i]:
            continue
        c = om.legend(d)
        if any(om.defines(c, t, at) for t, at in elems.items()):   # served lazily: the first answer that needs it carries it once
            carried += 1
            if carried > 1:
                badr.append("#%d re-carries a section definition the session was already sent" % (i + 1))
        tail = re.search(r'<about ([^>]*)/>\s*</[\w-]+>\s*$', d)
        if not tail or 'legend="ref"' not in tail.group(1) or 'dictv="%s"' % dictv not in tail.group(1):
            badr.append("#%d does not end with <about legend=ref dictv=%s>" % (i + 1, dictv))
        u = [t for t, at in elems.items() if not om.defines(dict_txt + c, t, at)]
        if u:
            badr.append("#%d leans on undefined %s" % (i + 1, u))
    check(not badr, "(L) ref answers carry the section definition at most once per session, end with <about legend=ref> naming the dictionary's dictv, and lean only on it", str(badr))


def truth():
    """(E) entry rows, (G) group labels, (M) the memory-guard partial ingest — on test/orientmapfix/gen_truth.sh"""
    T = os.path.join(TMP, "fx2")
    TM = model(T)
    ts_ = TM["secs"]
    print("== (E) entry rows name exported/public entries only ==")
    if check("entry_points" in ts_, "(E) the truth fixture's map carries <entry_points>"):
        ep = ts_["entry_points"]
        rows = [dict(e.a) for e in ep.find("e")]
        if "next" in ep.a:
            more, probs = om.follow(BIN, T, ep.a["next"], "why")
            check(not probs, "(E) entry_points next= pages cleanly", "; ".join(probs[:3]))
            rows += more
        got = sorted((r.get("p", "").rsplit(":", 1)[0], r.get("n"), r.get("why")) for r in rows)
        print("  INFO  (E) entry rows: %s" % [(r.get("p"), r.get("n"), r.get("why")) for r in rows])
        bad_names = {"Internal", "helperOnly", "VERSION", "VERSION_TAG", "_parseArgs", "isHttpErrorLike", "isPlainHelper", "_helper",
                     "_bind_port", "_prepare", "UpdateStateFunction", "helper", "firstLocal", "_internal", "helperA", "createApp"}
        check(not [r for r in rows if r.get("n") in bad_names],
              "(E) no entry row names a non-exported alias, a private helper or a version constant",
              str([(r.get("p"), r.get("n")) for r in rows if r.get("n") in bad_names]))
        check(("src/index.ts", "<file-scope>", "entry") in got and "src/index.ts:1" in [r.get("p") for r in rows],
              "(E) the package entry module in hono's shape (imports and re-exports, nothing declared) is <file-scope> at line 1")
        check(("src/options.ts", "Options", "bin") in got,
              "(E) a module is named by its first EXPORTED function, class or type (export interface Options, after a non-exported "
              "alias, a private helper and an exported VERSION constant)")
        check(("src/exportlist.ts", "b", "bin") in got and ("src/defexp.ts", "make", "bin") in got and ("lib/cjsx.js", "create", "bin") in got,
              "(E) `export { b }` (b not the first declaration), `export default make` and `exports.create = create` name b, make, create")
        check(not [r for r in rows if r.get("p", "").startswith("src/jsx/hooks/index.ts")],
              "(E) dist/index.js and dist/cjs/index.js map to src/index.ts (one source root away), never the heavier src/jsx/hooks/index.ts")
        check(("src/cli.ts", "<file-scope>", "bin") in got and "src/cli.ts:1" in [r.get("p") for r in rows],
              "(E) a bin module that exports nothing is named by its module scope <file-scope> at line 1")
        check(("lib/server.js", "server", "bin") in got and ("lib/application.js", "Application", "bin") in got,
              "(E) CommonJS: module.exports = server / module.exports = class Application name the row")
        check(("src/tpkg/serve.py", "serve", "script") in got and ("src/tpkg/cli.py", "<file-scope>", "script") in got,
              "(E) pyproject: a script function the module defines is named; one it only imports gives <file-scope>, not the helper above it")
        check(("src/App.java", "main", "main") in got and ("src/tpkg/launch.py", "main", "main") in got and ("cmd/tool/main.go", "main", "main") in got,
              "(E) a module-level main function, a JVM static main and a Go func main in package main are entry rows")
        check(not [r for r in rows if r.get("p", "").startswith("src/gox/helper.go")],
              "(E) a Go func main in a library package (package gox) is not an entry row")
        check(not [r for r in rows if r.get("p", "").startswith("src/tpkg/worker.py")],
              "(E) a Python method named main on a helper class is not an entry row")
        want = sorted([("src/index.ts", "<file-scope>", "entry"), ("src/options.ts", "Options", "bin"), ("src/cli.ts", "<file-scope>", "bin"),
                       ("lib/server.js", "server", "bin"), ("lib/application.js", "Application", "bin"), ("src/exportlist.ts", "b", "bin"),
                       ("src/defexp.ts", "make", "bin"), ("lib/cjsx.js", "create", "bin"), ("src/tpkg/serve.py", "serve", "script"),
                       ("src/tpkg/cli.py", "<file-scope>", "script"), ("src/App.java", "main", "main"), ("src/tpkg/launch.py", "main", "main"),
                       ("cmd/tool/main.go", "main", "main")])
        check(got == want and ep.a.get("total") == str(len(want)), "(E) exactly the %d true entry rows, total=%d" % (len(want), len(want)),
              "got %s total=%s" % (got, ep.a.get("total")))
        badline = [r for r in rows if not entry_symbol_true(TM, r.get("p", "").rsplit(":", 1)[0], int(r.get("p", ":0").rsplit(":", 1)[1] or 0), r.get("n"), r.get("why"))]
        check(not badline, "(E) every named row's symbol is declared on its line (module scope at line 1)", str(badline[:3]))
    print("== (G) group labels are true of every member ==")
    udoc, _ = om.run(BIN, T, env=UNC)
    us = om.sections(udoc)
    if check("subsystems" in us and "overflow" in us, "(G) the truth fixture's uncapped map carries <subsystems> and <overflow>"):
        g = us["subsystems"].a.get("g", "")
        check(g == "src/", "(G) (fixture premise) g= is src/", "got %r" % g)
        grp_of = {}
        labels = []
        for node in (us["subsystems"], us["overflow"]):
            for lab, ps in names(node, g):
                labels.append(lab)
                for p in ps:
                    grp_of[p] = lab
        paged = []
        if "next" in us["subsystems"].a:
            prow, _ = om.follow(BIN, T, us["subsystems"].a["next"], "label")
            paged = [r["label"] for r in prow]
        labels += paged
        check(grp_of.get("src/request.ts") == "request" and grp_of.get("src/request-utils.ts") == "request"
              and grp_of.get("src/request/body.ts") == "request",
              "(G) src/request.ts and src/request-utils.ts beside src/request/ share its group, labelled `request`",
              "request.ts %r, request-utils.ts %r, request/body.ts %r" % (grp_of.get("src/request.ts"), grp_of.get("src/request-utils.ts"),
                                                                         grp_of.get("src/request/body.ts")))
        check("request/" not in labels, "(G) no group is labelled `request/` while it holds a file outside src/request/", str(labels))
        check(grp_of.get("src/router/router.ts") == "router/" and grp_of.get("src/router/trie.ts") == "router/",
              "(G) a nested X/X.ts with no sibling (src/router/router.ts) keeps `router/`", str(grp_of.get("src/router/router.ts")))
        check(grp_of.get("tools.py") == "/tools" and grp_of.get("tools/gen.py") == "/tools" and "/tools/" not in labels,
              "(G) outside g=, tools.py beside tools/ is `/tools`, never `/tools/`", "%r %r" % (grp_of.get("tools.py"), grp_of.get("tools/gen.py")))
        check(grp_of.get("src/Stats.ts") == "stats" and grp_of.get("src/stats/collect.ts") == "stats" and "stats/" not in labels,
              "(G) CamelCase src/Stats.ts beside src/stats/ shares its group, labelled `stats` (never `stats/`)",
              "%r %r" % (grp_of.get("src/Stats.ts"), grp_of.get("src/stats/collect.ts")))
        check(grp_of.get("scripts/build.py") == "/scripts/", "(G) outside g=, a directory alone stays `/scripts/`", str(grp_of.get("scripts/build.py")))
        false_lab = [(lab, m.a.get("p")) for node in (us["subsystems"], us["overflow"]) for grp in node.find("grp")
                     for lab in [grp.a.get("label", "")] for m in grp.find("m") if not om.label_true(lab, m.a.get("p", ""))]
        check(not false_lab, "(G) every label is true of every member it lists (uncapped)", str(false_lab[:5]))
        check(sorted(set(labels)) == sorted(TM["orc"]["order"]), "(G) the labels are the oracle's (the registered rule + truthful labels)",
              "got %s want %s" % (sorted(set(labels)), sorted(TM["orc"]["order"])))
    gate_d(TM, "truth fixture")
    print("== (M) a memory-guard partial ingest carries no orient section ==")
    PART = {"RIPWIRE_TEST_MEMGUARD": "parse:3"}
    full_pg, rc_full = om.run(BIN, T, "--orient=groups")
    check(om.region(TM["doc"]) is not None and rc_full == 0 and "<orient" in full_pg,
          "(M) (premise) the whole ingest carries the sections and --orient=groups pages (rc=%d)" % rc_full)
    pdoc, prc = om.run(BIN, T, env=PART)
    check(prc == 0 and "memory_stop=" in pdoc, "(M) (premise) the seam cuts the ingest: the map answers with memory_stop= (rc=%d)" % prc)
    check(om.region(pdoc) is None and "utility_demoted" not in pdoc,
          "(M) the CLI map on a partial ingest carries no section and no utility_demoted= (their totals would be unmarked floors)")
    pj, _ = om.run(BIN, T, "--json", env=PART)
    check(not any(k in pj for k in ('"entry_points"', '"subsystems"', '"overflow"', '"utility_demoted"')),
          "(M) the --json map on a partial ingest carries no section key")
    for kind in ("entry", "groups", "overflow", "demoted"):
        ppg, pprc = om.run(BIN, T, "--orient=" + kind, env=PART)
        check(pprc == 5 and "<orient" not in ppg, "(M) --orient=%s on a partial ingest refuses (exit 5, no page)" % kind, "rc=%d" % pprc)
    hp = os.path.join(TMP, "partial.html")
    _, hrc = om.run(BIN, T, "--html=" + hp, env=PART)
    check(hrc == 5 and not (os.path.exists(hp) and "request" in open(hp, errors="replace").read()),
          "(M) --html on a partial ingest refuses (exit 5; a rendering with no header cannot carry the floor)", "rc=%d" % hrc)
    man, mrb = om.mcp(BIN, T, [("analyze", {}), ("rank_by", {})], env=PART)
    check("memory_stop=" in man and "memory_stop=" in mrb and not man.startswith("ERROR") and not mrb.startswith("ERROR"),
          "(M) (premise) MCP analyze and rank_by ANSWERED the partial index (memory_stop= in both, no error reply)",
          "%r / %r" % (man[:120], mrb[:120]))
    check(om.region(man) is None and "utility_demoted" not in man and om.region(mrb) is None and "utility_demoted" not in mrb,
          "(M) MCP analyze and rank_by on a partial ingest carry no section and no utility_demoted= (CLI == MCP)")


if not ONLY_EXTRA:
    print("== fixture ==")
    M = model(FX, pinned=FIX_DEMOTED)
    orc = M["orc"]
    ties = [M["ms"].get(a, (None,))[0] == M["ms"].get(b, (-1,))[0] for a, b in (("src/pkg/tie-a.py", "src/pkg/tie/b.py"), ("src/pkg/Kappa.py", "src/pkg/beta/x.py"))]
    if orc["ambiguous"] or orc["G"] != "src/pkg/" or len(orc["order"]) < 14 or len(orc["ranked"]) < 30 or not all(ties):
        no("the fixture no longer exercises the rule decisively (G=%r, %d groups, %d overflow names, ties printed equal %s, %d ambiguous: %s)"
           % (orc["G"], len(orc["order"]), len(orc["ranked"]), ties, len(orc["ambiguous"]), orc["ambiguous"][:3]))
        sys.exit(1)
    s = M["secs"]
    print("== (F) the registered rule, exactly ==")
    check(M["rc"] == 0, "(F) the map exits 0")
    check(orc["order"].index("beta/") < orc["order"].index("kappa") and orc["members"]["tie"] == ["src/pkg/tie-a.py", "src/pkg/tie/b.py"],
          "(F) (oracle) the designed ties break by label and by path")
    if check("subsystems" in s, "(F) the map carries <subsystems>"):
        sub = s["subsystems"]
        check(sub.a.get("g") == orc["G"], "(F) g= is the grouping root %r" % orc["G"], "got %r" % sub.a.get("g"))
        want = [(lab, str(len(orc["members"][lab])), [om.printed(p, orc["G"]) for p in orc["members"][lab][:3]]) for lab in orc["order"][:12]]
        got = [(grp.a.get("label"), grp.a.get("n"), [m.a.get("p") for m in grp.find("m")]) for grp in sub.find("grp")]
        check(got == want, "(F) the 12 group rows: labels, n= and top-3 members, in mass order (ties by label, then path)",
              "first difference: %r" % (next(((a, b) for a, b in zip(got + [None] * 12, want) if a != b), None),))
        check(sub.a.get("total") == str(len(orc["order"])) and sub.a.get("shown") == str(min(12, len(orc["order"]))),
              "(F) <subsystems> total=%d shown=%d" % (len(orc["order"]), min(12, len(orc["order"]))), str(sub.a))
    if check("overflow" in s, "(F) the map carries <overflow>"):
        ov = s["overflow"]
        k = int(ov.a.get("shown", "-1"))
        check(ov.a.get("total") == str(len(orc["ranked"])), "(F) <overflow> total= is every core file not named in the group rows (%d)" % len(orc["ranked"]), str(ov.a))
        surv = set(orc["ranked"][:max(k, 0)])
        regroup = [(lab, [om.printed(p, orc["G"]) for p in orc["members"][lab] if (lab, p) in surv]) for lab in orc["order"]]
        regroup = [x for x in regroup if x[1]]
        got = [(grp.a.get("label"), [m.a.get("p") for m in grp.find("m")]) for grp in ov.find("grp")]
        check(k > 0 and got == regroup, "(F) <overflow> is the first %d of the breadth-first list, re-grouped in group then member order" % k,
              "first difference: %r" % (next(((a, b) for a, b in zip(got + [None] * 30, regroup) if a != b), None),))
        check(0 < k < len(orc["ranked"]), "(F) the fixture's overflow is cut (the cut binds: %d of %d)" % (k, len(orc["ranked"])))
    if check("entry_points" in s, "(F) the map carries <entry_points>"):
        ep = s["entry_points"]
        rows = [e.a for e in ep.find("e")]
        want = [("src/pkg/flat.ts", "bin"), ("src/pkg/sync.ts", "bin"), ("src/pkg/tool.ts", "bin"), ("src/pkg/admin.ts", "bin"),
                ("src/pkg/launcher.py", "main")]
        check([(r.get("p", "").rsplit(":", 1)[0], r.get("why")) for r in rows] == want,
              "(F) the 5 entry rows: core bins by mass (the flattened dist/flat.js mapped to its unique-stem src/pkg/flat.ts), then "
              "core `main` definitions by mass — no test/fixture/vendored main, no bin without a source twin or naming a tests/ file", str(rows))
        check([(r.get("p"), r.get("n")) for r in rows if r.get("why") == "main"] == [("src/pkg/launcher.py:5", "main")],
              "(F) the main row carries file:line of `main` (never main_loop)")
        check(all(r.get("p", "").endswith(":1") for r in rows if r.get("why") == "bin"), "(F) a bin row points at its source module's first exported function (line 1)")
        check(ep.a.get("total") == "8" and ep.a.get("shown") == "5" and "next" in ep.a,
              "(F) total=8 counts core evidence only (4 bins, 2 mains, the entry module, the subpath export)", str(ep.a))
        if "next" in ep.a:
            prow, _ = om.follow(BIN, FX, ep.a["next"], "why")
            check([(r.get("p", "").rsplit(":", 1)[0], r.get("why")) for r in prow]
                  == [("scripts/release_build.py", "main"), ("src/pkg/index.ts", "entry"), ("src/pkg/sub.ts", "entry")]
                  and prow[0].get("p") == "scripts/release_build.py:1" and prow[0].get("n") == "main",
                  "(F) entry_points next= returns the second main, then the entry module, then the subpath export's source", str(prow))
    check(M["dcount"] is not None and set(M["dem"]) == FIX_DEMOTED, "(F) the demoted set is exactly the compat file and the utility sink",
          "got %s" % sorted(M["dem"]))

    print("== (D) disclosure ==")
    gate_d(M, "fixture", exact=True)
    print("== (U) uncapped variant ==")
    uncapped(M, "fixture")
    print("== (P) parity ==")
    refs = parity(M, "fixture") or []
    for name, mut in (("untracked-only change", lambda d: open(os.path.join(d, "src/pkg/brand_new_module.py"), "w").write("def q9999(v):\n    return v\n")),
                      ("non-git root", lambda d: shutil.rmtree(os.path.join(d, ".git")))):
        d = os.path.join(TMP, "near-" + name.split()[0])
        shutil.copytree(FX, d)
        mut(d)
        (a,) = om.mcp(BIN, d, [("analyze", {})])
        ra, rc_ = om.region(a), om.region(om.run(BIN, d)[0])
        check(ra is not None and rc_ is not None, "(P) MCP analyze with an %s is the whole-repo map: it carries the sections" % name)

    print("== (N) not applied ==")
    for args in (["--tree"], ["--rank-by=authority"], ["--rank-by=hub"], ["--rank-by=rrf"], ["--for=where is the request handled"]):
        d, _ = om.run(BIN, FX, *args)
        check(om.region(d) is None and "utility_demoted" not in d, "(N) %s carries no section and no utility_demoted=" % " ".join(args))
    rb_auth, explore, two = om.mcp(BIN, FX, [("rank_by", {"rank_by": "authority"}), ("explore", {"task": "where is the request handled"}),
                                             ("analyze", {"paths": [FX, os.path.join(ROOT, "test", "fixture")]})])
    for k, d in (("MCP rank_by authority", rb_auth), ("MCP explore", explore), ("MCP analyze over two roots", two)):
        check(om.region(d) is None and "utility_demoted" not in d, "(N) %s carries no section and no utility_demoted=" % k)

    def tracked(d):
        with open(os.path.join(d, "src/pkg/wire.py"), "a") as fh:
            fh.write("\n\ndef q9998(value):\n    return value\n")

    def staged(d):
        tracked(d)
        subprocess.run(["git", "-C", d, "add", "src/pkg/wire.py"], check=True)

    def readme(d):
        with open(os.path.join(d, "src/pkg/README.md"), "a") as fh:
            fh.write("\nMore.\n")
    for name, mut in (("a tracked edit", tracked), ("a staged-only change", staged), ("a README-only edit", readme)):
        d = os.path.join(TMP, "dirty-" + name.split()[1])
        shutil.copytree(FX, d)
        mut(d)
        (dan,) = om.mcp(BIN, d, [("analyze", {})])
        check(om.region(dan) is None and "utility_demoted" not in dan, "(N) MCP analyze with %s (a biased working set) carries no section" % name)

    print("== (L) legend and dictionary ==")
    legend_arm(M, refs)
    print("== (C) cost ==")
    cost(M, "fixture")
    print("== (X) well-formed and deterministic ==")
    if shutil.which("xmllint"):
        x = subprocess.run(["xmllint", "--noout", "-"], input=M["doc"].encode(), capture_output=True)
        check(x.returncode == 0, "(X) the map is well-formed XML", x.stderr.decode()[:200])
    check(om.run(BIN, FX)[0] == M["doc"], "(X) two runs are byte-identical")

    print("== truth fixture (O-narrow v3) ==")
    truth()

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
