#!/usr/bin/env python3
"""Read results.json out: per-corpus tables, the agreement matrix, and Q*.

  python3 readout.py [results.json]

Q* is the amortisation point. With a one-off index build cost B, a per-query cost
q_index against the resident index and a per-query cost q_scan for the scanner,

    Q* = B / (q_scan - q_index)

is the number of queries in one session at which building the index has paid for itself.
Q* is reported against BOTH scan arms - rg (the floor, and the cleanest comparison because
tgrep's output is byte-identical to it) and ripwire warm - because they answer different
questions: rg says whether a trigram index beats a fast scanner at all, ripwire-warm says
whether it would pay off inside THIS tool.
"""

import json
import sys

R = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "results.json"))
C = R["corpora"]
ORDER = [c for c in ("rwsrc", "rwtree", "privcpp", "go", "llvm") if c in C]
ORDER += [c for c in C if c not in ORDER]
ARMS = ["rw-warm", "rw-warm-all", "tgrep-warm", "tgrep-cold", "rg"]
AGREE = ["L1", "L6", "L7", "L8", "R1", "R3", "R4", "R7", "R8"]


def med(c, arm, qs=None):
    """Mean median-wall over `qs` (default: every query this corpus recorded for `arm`)."""
    keys = qs if qs is not None else list(C[c]["queries"])
    v = [C[c]["queries"][q][arm].get("median_s") for q in keys if q in C[c]["queries"]]
    v = [x for x in v if x is not None and x < 1e9]
    return sum(v) / len(v) if v else float("nan")


def rwkeys(c):
    """The queries this corpus actually ran the ripwire arms on.

    The llvm rung runs ripwire over a DECLARED subset (see run.py's RW_QUERIES), so a Q* that
    compared ripwire's mean over six queries against rg's over sixteen would be comparing two
    different workloads. Every ripwire-vs-X figure below is restricted to this set; the rg-vs-tgrep
    figures use all sixteen, and the table says which is which."""
    return [q for q, row in C[c]["queries"].items() if row["rw-warm"].get("median_s") is not None]


print("## corpus ladder — one-off costs\n")
print("| corpus | files | ripwire cold (ingest+scan) | peak RSS | ripwire cache on disk "
      "| tgrep index build | peak RSS | index on disk |")
print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for c in ORDER:
    d = C[c]
    ti = d["tgrep_index"]
    print("| %s | %d | %.3f s | %.2f GB | %.1f MB | %.3f s | %.0f MB | %.1f MB |" % (
        c, d["files_rg"], d["rw_cold"]["wall_s"], d["rw_cold"]["peak_rss_bytes"] / 2**30,
        d["rw_cache_bytes"] / 2**20, ti["wall_s"], ti["peak_rss_bytes"] / 2**20,
        ti["index_bytes"] / 2**20))

print("\n## per-query median wall (s), 5 runs each\n")
for c in ORDER:
    print("\n### %s (%d files)\n" % (c, C[c]["files_rg"]))
    print("| q | pattern | " + " | ".join(ARMS) + " | rg bytes |")
    print("| --- | --- | " + " | ".join("---:" for _ in ARMS) + " | ---: |")
    for q, row in C[c]["queries"].items():
        cells = []
        for a in ARMS:
            m = row[a].get("median_s")
            cells.append("-" if m is None else ("TIMEOUT" if m > 1e9 else "%.3f" % m))
        print("| %s | `%s` | %s | %d |" % (q, row["pat"], " | ".join(cells), row["rg"]["bytes"]))

print("\n## Q* — queries per session at which an index pays for itself\n")
print("| corpus | files | ripwire queries | mean q_scan (rg, all 16) | mean q_scan (rw warm) | mean q_index (tgrep, all 16) "
      "| B (tgrep build) | Q* vs rg | Q* vs ripwire-warm |")
print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for c in ORDER:
    B = C[c]["tgrep_index"]["wall_s"]
    rwq = rwkeys(c)                      # the ripwire arms' own query set on this rung
    qs = med(c, "rg")                    # all 16
    qi = med(c, "tgrep-warm")            # all 16
    qw = med(c, "rw-warm", rwq)          # the declared subset
    qi_rw = med(c, "tgrep-warm", rwq)    # the SAME subset, for the ripwire comparison
    f = lambda s, ix: ("%.1f" % (B / (s - ix))) if s > ix else "never (index is slower)"
    print("| %s | %d | %d/%d | %.4f | %.4f | %.4f | %.3f | %s | %s |" %
          (c, C[c]["files_rg"], len(rwq), len(C[c]["queries"]), qs, qw, qi, B,
           f(qs, qi), f(qw, qi_rw)))

print("\n## agreement matrix — (path,line) hit sets\n")
print("| corpus | q | ripwire | tgrep | rg | verdict |")
print("| --- | --- | ---: | ---: | ---: | --- |")
for c in ORDER:
    for q in AGREE:
        row = C[c]["queries"].get(q)
        if not row:
            continue
        a = row["rw-warm-all"].get("hits_set")
        b = row["tgrep-warm"].get("hits_set")
        d = row["rg"].get("hits_set")
        v = "agree" if a == b == d else ("tgrep==rg, ripwire differs" if b == d else "THREE-WAY SPLIT")
        print("| %s | %s | %s | %s | %s | %s |" % (c, q, a, b, d, v))

print("\n## in-cache index cost — would a persisted trigram index fit ripwire's own cache?\n")
print("| corpus | tgrep build / ripwire cold ingest | tgrep index bytes / ripwire cache bytes |")
print("| --- | ---: | ---: |")
for c in ORDER:
    d = C[c]
    print("| %s | %.2fx | %.2fx |" % (c, d["tgrep_index"]["wall_s"] / d["rw_cold"]["wall_s"],
                                      d["tgrep_index"]["index_bytes"] / d["rw_cache_bytes"]))
