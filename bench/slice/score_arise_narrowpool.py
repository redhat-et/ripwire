#!/usr/bin/env python3
"""score_arise_narrowpool.py -- EVALS' own narrow-pool arm, committed (arise-line-ranking-prereg.md §4.3.2).

Re-measures order="defuse" (already shipped, docs/EVALS.md's "def-use row order" ADOPT) and
order="defrole" (this lane's §3.1 def-primacy rule) on the SAME 478 (scored instance, inventory
variable) pairs that ADOPT measured -- the emission-order MRR/Recall@k metric, per (instance, var) pair
whose --slice=SYM:VAR rows hold a gold line. defuse's order is the row order --slice already emits
today (`sliceDefUseRowOrder`: coverage(l) desc, l asc). defrole re-sorts the SAME seed-restricted row
set by (hasAnyDef(l) desc, coverage(l) desc, l asc) -- both facts read from every row's own k=
attribute and the per-instance UNION of v1 rows across every inventory variable, seed-free, exactly
src/slice.h's sliceRowHasAnyDef/sliceRowCoverage (prereg §8's code<->harness equivalence,
test/slicerank_unit.cpp item (6)). No --slice-flow invocation -- the narrow-pool arm is v1-only, same
as R3 itself (§3.1).

Before this can run against a real corpus: EVALS' narrow-pool arm was, as registered in docs/EVALS.md,
a 43-line uncommitted scratch diff over bench/slice/run_slice_linerecall.py (research branch,
unmerged). This script is that arm's committed, self-tested, standalone form -- reusing nothing from
that uncommitted diff, computing the identical statistic from first principles against real --slice
output.

Usage:
  python3 bench/slice/score_arise_narrowpool.py --gold gold.json --bin build/ripwire --work <scratch> \
      --json narrowpool_results.json
  python3 bench/slice/score_arise_narrowpool.py --self-test    # synthetic <s>/<v> XML only, no corpus,
                                                                 # no binary invoked
"""

import argparse, json, re, statistics, subprocess, sys
from pathlib import Path

S_ROW = re.compile(r'<s\b([^>]*)>')
ATTR = re.compile(r'(\w+)="([^"]*)"')
V_ROW = re.compile(r'<v\b([^>]*)/>')
WORD = re.compile(r"[A-Za-z_]\w*")
KS = (1, 3, 5, 10, 20)


def attrs(s):
    return dict(ATTR.findall(s))


def git(repo, *args, ok_fail=False):
    r = subprocess.run(["git", "-C", str(repo)] + list(args), capture_output=True, text=True)
    if r.returncode != 0 and not ok_fail:
        raise RuntimeError(f"git {args} failed in {repo}: {r.stderr}")
    return r


def run(binary, tree, args):
    r = subprocess.run([binary, str(tree)] + args, capture_output=True, text=True, errors="replace")
    return r.returncode, r.stdout


def slice_rows_defkind(out):
    """[(line, hasdef)] for every <s> row, in EMISSION order -- hasdef read from k= ("def"/"both" -> 1,
    "use" -> 0). The prereg's §8 names this exact one-line change against run_slice_linerecall.py's own
    slice_rows(), which reads t=, not k=."""
    rows = []
    for a in (attrs(m.group(1)) for m in S_ROW.finditer(out)):
        if "l" not in a:
            continue
        rows.append((int(a["l"]), 1 if a.get("k", "") in ("def", "both") else 0))
    return rows


def recall_at_k(order, gold, k):
    if not gold:
        return None
    return len(set(order[:k]) & gold) / len(gold)


def mrr(order, gold):
    for i, ln in enumerate(order, 1):
        if ln in gold:
            return 1.0 / i
    return 0.0


def dedup_order(seq):
    """First-occurrence order, no duplicate lines -- a row set never repeats a line under
    sliceFoldLines; defensive here so a duplicate can never double-count a rank."""
    seen, out = set(), []
    for x in seq:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def score_pair(defuse_rows, hasdef_all, coverage_all):
    """defuse_rows: [(line, hasdef)] in the emitted (defuse) order for ONE seed variable's own rows.
    Returns (defuse_order, defrole_order) over the SAME line set -- defrole re-sorted by
    (hasAnyDef desc, coverage desc, line asc), both read at the INSTANCE level (every variable's rows
    unioned), never from this one seed's own hasdef column alone (§3.1's seed-free correction: R1/R3
    read scan.all, not one seed's scan.occ)."""
    lines = dedup_order(ln for ln, _ in defuse_rows)
    defuse_order = lines
    defrole_order = sorted(lines, key=lambda l: (-hasdef_all.get(l, 0), -coverage_all.get(l, 0), l))
    return defuse_order, defrole_order


def measure_instance_narrowpool(binary, tree, r, out_pairs):
    """One carried row: invoke --slice=SEL:VAR for every inventory variable (v1 only), build the
    instance-level hasdef/coverage facts from the UNION of every variable's own rows, then for every
    variable whose rows hold a gold line, score defuse vs defrole in emission order."""
    src = tree / Path(r["path"]).name
    show = git(r["repo_dir"], "show", f"{r['base_commit']}:{r['path']}", ok_fail=True)
    if show.returncode != 0:
        return
    src.write_text(show.stdout)
    lines_txt = show.stdout.splitlines()

    sel = r["selector"]
    rc_inv, inv_out = run(binary, tree, [f"--slice={sel}"])
    if rc_inv != 0:
        return
    invent = [attrs(m.group(1))["n"] for m in V_ROW.finditer(inv_out)]
    if not invent:
        return

    by_var = {}
    for var in invent:
        rc1, o1 = run(binary, tree, [f"--slice={sel}:{var}"])
        if rc1 == 0:
            by_var[var] = slice_rows_defkind(o1)

    hasdef_all, coverage_all = {}, {}
    for var, rows in by_var.items():
        for ln, hd in rows:
            coverage_all[ln] = coverage_all.get(ln, 0) + 1
            if hd:
                hasdef_all[ln] = 1

    gold = set(r["gold"])

    def text_of(n):
        return lines_txt[n - 1] if 1 <= n <= len(lines_txt) else ""

    for var, rows in by_var.items():
        rel = [n for n in sorted(gold) if re.search(r"\b%s\b" % re.escape(var), text_of(n))]
        if not rel:
            continue
        rel_s = set(rel)
        defuse_order, defrole_order = score_pair(rows, hasdef_all, coverage_all)
        out_pairs.append({
            "instance_id": r["instance_id"], "var": var, "relevant": len(rel),
            "defuse_mrr": mrr(defuse_order, rel_s), "defrole_mrr": mrr(defrole_order, rel_s),
            **{f"defuse@{k}": recall_at_k(defuse_order, rel_s, k) for k in KS},
            **{f"defrole@{k}": recall_at_k(defrole_order, rel_s, k) for k in KS},
        })


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--gold")
    ap.add_argument("--bin", default="build/ripwire")
    ap.add_argument("--work")
    ap.add_argument("--json")
    a = ap.parse_args()

    if a.self_test:
        return 0 if self_test() else 1

    if not (a.gold and a.work):
        ap.error("--gold and --work are required unless --self-test")

    binary = str(Path(a.bin).resolve())
    work = Path(a.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    gold_doc = json.loads(Path(a.gold).read_text())
    rows = gold_doc["instances"]

    pairs = []
    for i, r in enumerate(rows):
        tree = work / f"n{i:04d}"
        tree.mkdir(exist_ok=True)
        measure_instance_narrowpool(binary, tree, r, pairs)
        print(f"[{i + 1}/{len(rows)}] {r['instance_id']} pairs_so_far={len(pairs)}", file=sys.stderr)

    def m(key):
        vals = [p[key] for p in pairs if p.get(key) is not None]
        return statistics.mean(vals) if vals else None

    summary = {
        "var_instances": len(pairs),
        "mrr": {"defuse": m("defuse_mrr"), "defrole": m("defrole_mrr")},
        "recall_at_k": {
            "defuse": {k: m(f"defuse@{k}") for k in KS},
            "defrole": {k: m(f"defrole@{k}") for k in KS},
        },
    }
    print(json.dumps(summary, indent=2))
    if a.json:
        Path(a.json).write_text(json.dumps({"summary": summary, "pairs": pairs}, indent=2))
        print(f"wrote {a.json}", file=sys.stderr)
    return 0


# -- self-test: synthetic <s>/<v> XML only, no corpus content, no binary invoked -----------------------

def self_test():
    ok_count = [0]
    fail_count = [0]

    def check(name, cond, detail=""):
        if cond:
            ok_count[0] += 1
            print(f"  PASS  {name}")
        else:
            fail_count[0] += 1
            print(f"  FAIL  {name}  {detail}")

    out = '<slice p="f.py:1"><s l="5" k="use"/><s l="3" k="def"/><s l="7" k="both"/></slice>'
    rows = slice_rows_defkind(out)
    check("slice_rows_defkind: emission order preserved, k=def/both -> hasdef=1, k=use -> 0",
          rows == [(5, 0), (3, 1), (7, 1)], rows)

    defuse_rows = [(10, 0), (4, 0), (6, 1)]  # emitted (defuse) order: 10, 4, 6
    hasdef_all = {10: 0, 4: 0, 6: 1}
    coverage_all = {10: 3, 4: 5, 6: 1}
    defuse_order, defrole_order = score_pair(defuse_rows, hasdef_all, coverage_all)
    check("score_pair: defuse_order is the raw emission order, untouched",
          defuse_order == [10, 4, 6], defuse_order)
    check("score_pair: defrole_order promotes the one hasdef line ahead of higher-coverage use-only lines",
          defrole_order == [6, 4, 10], defrole_order)

    defuse_rows2 = [(1, 1), (2, 1), (3, 1)]
    hasdef_all2 = {1: 1, 2: 1, 3: 1}
    coverage_all2 = {1: 2, 2: 2, 3: 9}
    _, defrole_order2 = score_pair(defuse_rows2, hasdef_all2, coverage_all2)
    check("score_pair: all-hasdef tie breaks on coverage desc, then line asc",
          defrole_order2 == [3, 1, 2], defrole_order2)

    check("mrr: gold at rank 2", mrr([9, 4, 1], {4}) == 0.5)
    check("mrr: gold absent from the order scores 0", mrr([9, 4, 1], {7}) == 0.0)
    check("recall_at_k: k=1 misses, k=3 hits",
          recall_at_k([9, 4, 1], {1}, 1) == 0.0 and recall_at_k([9, 4, 1], {1}, 3) == 1.0)

    check("dedup_order: first occurrence kept, no repeats",
          dedup_order([5, 3, 5, 7, 3]) == [5, 3, 7])

    print(f"score_arise_narrowpool self-test: {ok_count[0]} pass, {fail_count[0]} fail")
    return fail_count[0] == 0


if __name__ == "__main__":
    sys.exit(main())
