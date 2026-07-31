#!/usr/bin/env python3
"""scip_amb_precision.py — measure the PRECISION of ctxpack's amb=-flagged call edges against
Sourcegraph SCIP ground truth, using ctxpack's OWN --scip overlay as the oracle (no src changes).

Method (deterministic; full census, no sampling):
  For a repo R with a scip-python index R.scip:
    * baseline = `ctxpack R --top-k=100000 --no-cache`             (name-based edges)
    * overlay  = `ctxpack R --scip=R.scip --top-k=100000 --no-cache` (edges SCIP resolved carry prov="scip")
  --top-k=100000 defeats the default 200-symbol map truncation so EVERY symbol + edge renders.

  ctxpack renders each call edge as <c n="NAME"/> (the callee NAME; no target id). A name X with
  >1 in-corpus definition is AMBIGUOUS by ctxpack's own criterion (the resolver keeps every same-name
  def -> a split edge, and the owning symbol carries amb="K"). The overlay REPLACES the covered site's
  guess with SCIP's single resolved target, tagged prov="scip"; the dropped split candidates are the
  edges SCIP DISCONFIRMED.

  We align baseline<->overlay symbols by (filepath, symbolName, ordinal-within-file) — stable because a
  file's symbols emit in a fixed intra-file order regardless of PageRank (which differs between runs).
  For each (symbol, calleeName=X) bucket that the overlay COVERS (>=1 prov edge):
     confirmed = # prov="scip" edges to X   (distinct SCIP targets; preciseEdges are unique (from,to))
     emitted   = # baseline <c n="X"/> edges to X
     group     = AMB if X has >1 in-corpus def, else NON-AMB
  precision(group) = sum(confirmed) / sum(emitted) over covered buckets in that group.

  Restricting to COVERED buckets is deliberate: SCIP silence != disconfirmation (external/uncovered
  sites are not ground truth). So this is precision WHERE SCIP SPEAKS.

Caveats (see the writeup): (1) SCIP itself is imperfect for dynamic dispatch. (2) The precise set is
deduped to unique (symbol,target) edges, so repeated identical calls collapse -> the amb denominator can
include repeat-call multiples the numerator deduped away, making precision(amb) a LOWER BOUND on the
true per-target precision. (3) non-amb precision is ~1.0 largely BY CONSTRUCTION (a unique-name edge has
only one possible target, so SCIP cannot pick differently) — it is a sanity floor, not an independent win.
"""
import sys, re, subprocess, collections, os

def run(binp, repo, extra):
    cmd = [binp, repo, "--top-k=100000", "--no-cache"] + extra
    return subprocess.run(cmd, capture_output=True, text=True).stdout

def parse(xml):
    """-> (buckets, defcount)
    buckets: dict[(filepath,name,ordinal)] -> list[(calleeName, isProv)]
    defcount: Counter[name] = # <s ...n="name"> definitions in the corpus
    """
    defcount = collections.Counter(re.findall(r'<s [^>]*\bn="([^"]*)"', xml))
    buckets = {}
    cur_file = None
    file_ord = collections.Counter()   # (file,name)->ordinal
    # walk tokens in document order
    key = None
    for m in re.finditer(r'<f p="([^"]*)"|<s ([^>]*?)>|<c ([^>]*?)/?>', xml):
        if m.group(1) is not None:
            cur_file = m.group(1)
        elif m.group(2) is not None:
            attrs = m.group(2)
            nm = re.search(r'\bn="([^"]*)"', attrs)
            name = nm.group(1) if nm else "?"
            o = file_ord[(cur_file, name)]
            file_ord[(cur_file, name)] += 1
            key = (cur_file, name, o)
            buckets[key] = []
        elif m.group(3) is not None and key is not None:
            cattrs = m.group(3)
            cn = re.search(r'\bn="([^"]*)"', cattrs)
            if not cn:
                continue
            buckets[key].append((cn.group(1), 'prov="scip"' in cattrs))
    return buckets, defcount

def analyze(binp, repo, scip):
    base = run(binp, repo, [])
    over = run(binp, repo, ["--scip=" + scip])
    bb, defc = parse(base)
    ob, _ = parse(over)

    # Denominator universe = CTXPACK's own emitted edges (this is "fraction of ctxpack edges SCIP
    # confirms"). We look only at (symbol, calleeName=X) buckets where (a) ctxpack emitted >=1 edge to X
    # AND (b) the overlay pinned >=1 prov="scip" edge to X (i.e. SCIP SPEAKS about this ctxpack edge).
    # confirmed = min(pinned, emitted): ctxpack's edges to X that hit one of SCIP's resolved targets,
    # capped at what ctxpack actually emitted so SCIP-ONLY edges (calls ctxpack missed, emitted==0) are
    # excluded from precision — they are a RECALL story, tracked separately in scip_only.
    agg = {"amb": [0, 0, 0], "nonamb": [0, 0, 0]}   # [confirmed, emitted, nbuckets]
    scip_only = {"amb": 0, "nonamb": 0}             # prov buckets where ctxpack emitted NOTHING for X
    for key, oedges in ob.items():
        oprov = collections.Counter(cn for cn, p in oedges if p)
        if not oprov:
            continue
        bcount = collections.Counter(cn for cn, _ in bb.get(key, []))
        for name, ns in oprov.items():
            g = "amb" if defc.get(name, 0) > 1 else "nonamb"
            emitted = bcount.get(name, 0)
            if emitted == 0:
                scip_only[g] += 1               # SCIP resolved a call ctxpack's name-based parse missed
                continue
            agg[g][0] += min(ns, emitted)
            agg[g][1] += emitted
            agg[g][2] += 1
    return agg, scip_only

def main():
    binp = os.environ.get("CTXPACK", "./build/ctxpack")
    # (label, repo_dir, scip_index) — fixed list => deterministic
    targets = [(sys.argv[i], sys.argv[i+1], sys.argv[i+2]) for i in range(1, len(sys.argv), 3)]
    for label, repo, scip in targets:
        agg, scip_only = analyze(binp, repo, scip)
        print("==== %s ====" % label)
        for g in ("amb", "nonamb"):
            c, e, n = agg[g]
            p = (c / e) if e else float("nan")
            print("  %-7s covered-buckets=%-5d ctxpack_edges=%-6d scip_confirmed=%-6d  precision=%.3f  scip_only(missed by ctxpack)=%d"
                  % (g, n, e, c, p, scip_only[g]))
        print()

if __name__ == "__main__":
    main()
