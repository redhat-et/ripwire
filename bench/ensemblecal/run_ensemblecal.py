#!/usr/bin/env python3
# run_ensemblecal.py — the CALIBRATION harness behind docs/EVALS.md §9.
#
# WHAT THIS IS. `--ensemble` joins four evidence families (structural / lexical / confusion /
# historical) and ranks by the COUNT of distinct families that fire. That design is only worth
# anything if the families are genuinely orthogonal — if they correlate, the join is one signal
# wearing four hats and the premise is false. This harness is the measurement that decides it, and
# the measurement a preset (which families are enabled + the family-count cut) must be derived from.
# It computes NOTHING new: every number comes out of `--ensemble`, `--readability` and `--metrics`
# through their existing entry points, parsed from their own XML.
#
# HONESTY CONTRACT (house rule — publish the losses with the wins):
#   * A preset derived from one codebase overfits to its conventions. The corpus list is printed
#     with every run and belongs beside every number this produces.
#   * Corpora with a shared lineage are NOT independent evidence. `--indep` marks the subset that
#     pools; everything else is reported separately and never pooled.
#   * A family that could not be MEASURED (historical on a non-git tree) is reported as unavailable
#     and dropped from the correlation, never counted as a clean zero.
#   * The stability pass runs ONE binary over MANY commits. The instrument is fixed and the corpus
#     varies — the reverse would measure the tool's own churn, not the code's.
#
# USAGE
#   python3 bench/ensemblecal/run_ensemblecal.py collect   --out cal.json  DIR[:LABEL[:indep]] ...
#   python3 bench/ensemblecal/run_ensemblecal.py stability --out stab.json REPO[:LABEL] ... [--samples 8]
#   python3 bench/ensemblecal/run_ensemblecal.py report    --in  cal.json [--stability stab.json]
#
# `stability` CHECKS OUT PAST COMMITS. Point it at a throwaway clone
# (`git clone --local --shared <repo> /tmp/x`), never at a tree you are working in.

import argparse, collections, itertools, json, math, os, re, subprocess, sys

FAM = ["structural", "lexical", "confusion", "historical"]
RW = os.environ.get("RIPWIRE_BIN", "./build/ripwire")


def attrs(tok):
    return dict(re.findall(r'([\w_]+)="([^"]*)"', tok))


def run(path, args, timeout=3600):
    return subprocess.run([RW, path] + args, capture_output=True, text=True, timeout=timeout).stdout


def strip_comments(xml):
    return re.sub(r"<!--.*?-->", "", xml, flags=re.S)


# ── collection ────────────────────────────────────────────────────────────────────────────────────
def scan_ensemble(path, extra=()):
    body = strip_comments(run(path, ["--ensemble", "--limit=200000"] + list(extra)))
    m = re.search(r"<ensemble ([^>]*)>", body)
    if not m:
        raise RuntimeError("no <ensemble> root for " + path)
    root, syms, cur = attrs(m.group(1)), [], None
    for tok in body.split("<"):
        if tok.startswith("s "):
            a = attrs(tok)
            cur = {"p": a["p"], "n": a["n"], "fam": int(a["fam"]), "of": int(a["of"]),
                   "fired": [x for x in a["fired"].split(",") if x], "why": {}}
            syms.append(cur)
        elif tok.startswith("e ") and cur is not None:
            a = attrs(tok)
            cur["why"][a["f"]] = a["why"]
    if root.get("syms_capped") == "1":
        raise RuntimeError("symbol rows were capped — raise --limit; a capped listing is not a census")
    return root, syms


def eligible_universe(path, extra=()):
    """The ensemble's own eligible set, named: --readability measures exactly it."""
    body = strip_comments(run(path, ["--readability", "--limit=500000"] + list(extra)))
    return set("|".join((a["p"].rsplit(":", 1)[0], a["n"]))
               for a in (attrs(t) for t in body.split("<") if t.startswith("fn ")))


def metric_cdf(path, extra=()):
    body = strip_comments(run(path, ["--metrics", "--top-k=200000"] + list(extra)))
    cols = collections.defaultdict(list)
    n = 0
    for tok in body.split("<"):
        if not tok.startswith("s "):
            continue
        a = attrs(tok)
        if a.get("t") not in ("fn", "method"):
            continue
        n += 1
        for k in ("ccx", "loc", "params", "nest"):
            if k in a:
                cols[k].append(int(a[k]))
    return n, {k: sorted(v) for k, v in cols.items()}


def collect(specs, out):
    res = {}
    for spec in specs:
        parts = spec.split(":")
        path = parts[0]
        label = parts[1] if len(parts) > 1 and parts[1] else os.path.basename(path.rstrip("/"))
        indep = (len(parts) > 2 and parts[2] == "indep")
        root, syms = scan_ensemble(path)
        vecs = collections.Counter()
        for s in syms:
            vecs[tuple(1 if f in s["fired"] else 0 for f in FAM)] += 1
        elig = int(root["eligible"])
        vecs[(0, 0, 0, 0)] += elig - sum(vecs.values())
        bars, barvals = collections.Counter(), collections.defaultdict(list)
        rules = {"lexical": collections.Counter(), "confusion": collections.Counter()}
        for s in syms:
            for k, v in re.findall(r"(\w+)=(\d+)", s["why"].get("structural", "")):
                bars[k] += 1
                barvals[k].append(int(v))
            for fam in rules:
                for tok in s["why"].get(fam, "").split():
                    rules[fam][tok.rsplit("*", 1)[0] if "*" in tok else tok] += 1
        nmet, cdf = metric_cdf(path)
        res[label] = {"path": path, "independent": indep, "root": root, "eligible": elig,
                      "unavail": [x for x in root.get("unavailable", "").split(",") if x],
                      "vecs": {",".join(map(str, k)): v for k, v in vecs.items()},
                      "bars": dict(bars), "barvals": {k: sorted(v) for k, v in barvals.items()},
                      "rules": {k: dict(v) for k, v in rules.items()},
                      "metrics_n": nmet, "cdf": cdf}
        print(f"collected {label:16s} eligible={elig}", flush=True)
    json.dump(res, open(out, "w"))


def stability(specs, out, samples):
    res = {}
    for spec in specs:
        parts = spec.split(":")
        repo = parts[0]
        label = parts[1] if len(parts) > 1 else os.path.basename(repo.rstrip("/"))
        revs = subprocess.run(["git", "-C", repo, "rev-list", "--first-parent", "HEAD"],
                              capture_output=True, text=True).stdout.split()
        step = max(1, len(revs) // samples)
        picked = [revs[i * step] for i in range(samples)][::-1]      # oldest first
        snaps = []
        for sha in picked:
            subprocess.run(["git", "-C", repo, "checkout", "--quiet", "--force", sha], check=True)
            date = subprocess.run(["git", "-C", repo, "log", "-1", "--format=%cd", "--date=short"],
                                  capture_output=True, text=True).stdout.strip()
            root, syms = scan_ensemble(repo)
            fired = {f: set() for f in FAM}
            for s in syms:
                key = "|".join((s["p"].rsplit(":", 1)[0], s["n"]))
                for f in s["fired"]:
                    fired[f].add(key)
            snaps.append({"sha": sha[:9], "cdate": date, "eligible": int(root["eligible"]),
                          "ranked": int(root["ranked"]), "rcut": int(root["rcut"]),
                          "hcut": int(root["hcut"]), "hranked": int(root["hranked"]),
                          "universe": sorted(eligible_universe(repo)),
                          "fired": {f: sorted(v) for f, v in fired.items()}})
            print(f"  {label} {sha[:9]} {date} eligible={root['eligible']}", flush=True)
        subprocess.run(["git", "-C", repo, "checkout", "--quiet", "--force", revs[0]], check=True)
        res[label] = {"repo": repo, "commits_total": len(revs), "step": step, "snaps": snaps}
    json.dump(res, open(out, "w"))


# ── reporting ─────────────────────────────────────────────────────────────────────────────────────
def vecs_of(blk):
    return {tuple(int(x) for x in k.split(",")): v for k, v in blk["vecs"].items()}


def phi(vecs, i, j):
    """Pearson correlation of two binary indicators = the phi coefficient. Undefined (nan) when
    either indicator is constant — which is a MEASUREMENT, not a zero: see the confusion family on
    a corpus with no C-family file."""
    n11 = n10 = n01 = n00 = 0
    for bits, c in vecs.items():
        a, b = bits[i], bits[j]
        if a and b: n11 += c
        elif a:     n10 += c
        elif b:     n01 += c
        else:       n00 += c
    den = math.sqrt((n11 + n10) * (n01 + n00) * (n11 + n01) * (n10 + n00))
    return ((n11 * n00 - n10 * n01) / den if den else float("nan")), (n11, n10, n01, n00)


def pct(vals, q):
    if not vals:
        return float("nan")
    k = (len(vals) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return vals[int(k)] if lo == hi else vals[lo] + (vals[hi] - vals[lo]) * (k - lo)


def sel(bits, enabled, K):
    return sum(bits[FAM.index(f)] for f in enabled) >= K


PRESETS = [("lenient", FAM, 1), ("default", FAM, 2),
           ("strict", ["structural", "lexical", "confusion"], 2)]


def set_jaccard(A, B):
    return len(A & B) / len(A | B) if A | B else float("nan")


def ladder_jaccard(snaps, pick):
    """(mean consecutive, endpoint) Jaccard of `pick(snap)` down one commit ladder."""
    pj = []
    for a, b in zip(snaps, snaps[1:]):
        u = set(a["universe"]) & set(b["universe"])
        pj.append(set_jaccard(set(pick(a)) & u, set(pick(b)) & u))
    pj = [x for x in pj if x == x]
    a, b = snaps[0], snaps[-1]
    u = set(a["universe"]) & set(b["universe"])
    ep = set_jaccard(set(pick(a)) & u, set(pick(b)) & u)
    return (sum(pj) / len(pj) if pj else float("nan")), ep


def preset_set(snap, enabled, K):
    """The symbols one preset emits at one snapshot."""
    per = collections.defaultdict(lambda: [0, 0, 0, 0])
    for i, f in enumerate(FAM):
        for key in snap["fired"][f]:
            per[key][i] = 1
    return set(k for k, b in per.items() if sel(tuple(b), enabled, K))


def report_corpora(D, order):
    print("CORPORA (independent marked *)")
    for k in order:
        print(f"  {'*' if D[k]['independent'] else ' '} {k:16s} eligible={D[k]['eligible']:6d} "
              f"unavailable={','.join(D[k]['unavail']) or '-':12s} {D[k]['path']}")


def report_marginals(D, order):
    print("\n1. FAMILY MARGINALS (fire rate over the eligible denominator)")
    for k in order:
        v, e = vecs_of(D[k]), D[k]["eligible"]
        cells = []
        for i, f in enumerate(FAM):
            if f in D[k]["unavail"]:
                cells.append(f"{f[:4]}=UNAVAIL")
            else:
                n = sum(c for b, c in v.items() if b[i])
                cells.append(f"{f[:4]}={n:5d} {100.0*n/e:5.2f}%")
        print(f"  {k:16s} n={e:6d}  " + "  ".join(cells))


def pooled(D, indep):
    """Two pooled vectors: everything, and the historical-available subset (its honest denominator)."""
    pool, poolh = collections.Counter(), collections.Counter()
    for k in indep:
        for b, c in vecs_of(D[k]).items():
            pool[b] += c
            if "historical" not in D[k]["unavail"]:
                poolh[b] += c
    return pool, poolh


def report_correlation(D, order, pool, poolh):
    print("\n2. CROSS-FAMILY CORRELATION (phi over all eligible symbols)")
    for k in order + ["POOLED-INDEPENDENT"]:
        v = pool if k == "POOLED-INDEPENDENT" else vecs_of(D[k])
        un = [] if k == "POOLED-INDEPENDENT" else D[k]["unavail"]
        print(f"  -- {k}")
        for i in range(4):
            for j in range(i + 1, 4):
                if FAM[i] in un or FAM[j] in un:
                    print(f"     {FAM[i]:11s} x {FAM[j]:11s} n/a (unavailable)")
                    continue
                src = (poolh if k == "POOLED-INDEPENDENT" and "historical" in (FAM[i], FAM[j]) else v)
                p, (n11, n10, n01, n00) = phi(src, i, j)
                jac = n11 / (n11 + n10 + n01) if (n11 + n10 + n01) else float("nan")
                print(f"     {FAM[i]:11s} x {FAM[j]:11s} phi={p:+.3f} "
                      f"n11={n11:6d} n10={n10:6d} n01={n01:6d} n00={n00:7d} jaccard={jac:.3f}")

def report_cofiring(D, order, pool):
    print("\n3. CO-FIRING DISTRIBUTION")
    for k in order + ["POOLED-INDEPENDENT"]:
        v = pool if k == "POOLED-INDEPENDENT" else vecs_of(D[k])
        tot = sum(v.values())
        h = collections.Counter()
        for b, c in v.items():
            h[sum(b)] += c
        print(f"  -- {k} n={tot}  " + "  ".join(f"fam={i}:{h[i]}({100.0*h[i]/tot:.2f}%)" for i in range(5)))
        for b, c in sorted(v.items(), key=lambda kv: (-sum(kv[0]), -kv[1])):
            if sum(b):
                print(f"       {sum(b)} {'+'.join(FAM[i][:4] for i in range(4) if b[i]):26s}"
                      f" {c:6d} {100.0*c/tot:5.2f}%")

def report_thresholds(D, order):
    print("\n4. WHERE THE SHIPPED THRESHOLDS SIT (exceedance over the eligible denominator)")
    bars = [("ccx", 15), ("loc", 60), ("nest", 4), ("params", 5)]
    for k in order:
        e = D[k]["eligible"]
        print(f"  {k:16s} " + "  ".join(
            f"{b}>={t}: {D[k]['bars'].get(b,0):5d} P{100*(1-D[k]['bars'].get(b,0)/e):5.2f}" for b, t in bars))
    print("   full CDF from --metrics (fn/method rows; n is that map's own universe)")
    for b, t in bars:
        print(f"   -- {b} (bar={t})")
        for k in order:
            v = D[k]["cdf"].get(b, [])
            if not v: continue
            ge = sum(1 for x in v if x >= t)
            print(f"      {k:16s} n={len(v):6d} P50={pct(v,.5):>6g} P75={pct(v,.75):>6g} "
                  f"P90={pct(v,.9):>7g} P95={pct(v,.95):>7g} P99={pct(v,.99):>8g} "
                  f"max={v[-1]:>6d} P(x>=bar)={100.0*ge/len(v):5.2f}%")
    print("   ordinal cuts: nominal 'worst decile' vs what the 40-row cap delivers")
    for k in order:
        r = D[k]["root"]
        rm, rc, hr, hc = int(r["rmeasured"]), int(r["rcut"]), int(r["hranked"]), int(r["hcut"])
        print(f"      {k:16s} readability {rc:3d}/{rm:6d} = {100.0*rc/rm if rm else float('nan'):5.2f}%   "
              f"churn {hc:3d}/{hr:6d} = " + (f"{100.0*hc/hr:5.2f}%" if hr else "n/a"))

def report_rules(D, order):
    print("\n5. RULE COMPOSITION inside the lexical and confusion families (symbols flagged per rule)")
    for k in order:
        for fam in ("lexical", "confusion"):
            d = D[k]["rules"].get(fam, {})
            body = "  ".join(f"{t}={c}" for t, c in sorted(d.items(), key=lambda kv: -kv[1])) or "ZERO findings"
            print(f"  {k:16s} {fam:10s} {body}")


def report_stability(S):
    print("\n6. STABILITY ACROSS COMMITS (one binary, many commits; restricted to symbols in BOTH trees)")
    for lbl, blk in S.items():
        snaps = blk["snaps"]
        print(f"  -- {lbl}: {blk['commits_total']} first-parent commits, every ~{blk['step']}, "
              f"{snaps[0]['cdate']} .. {snaps[-1]['cdate']}")
        for f in FAM:
            mean, ep = ladder_jaccard(snaps, lambda s, f=f: s["fired"][f])
            print(f"     {f:11s} mean consecutive jaccard={mean:.3f}  endpoint={ep:.3f}")


def report_presets(D, indep, S):
    print("\n7. PRESET GRID — yield of every (enabled-set, K), and of the three named presets")
    for E, K in [(list(e), k) for r in range(1, 5) for e in itertools.combinations(FAM, r)
                 for k in range(1, r + 1)]:
        cells, pn, pe = [], 0, 0
        for k in indep:
            v, e = vecs_of(D[k]), D[k]["eligible"]
            n = sum(c for b, c in v.items() if sel(b, E, K))
            pn += n; pe += e
            cells.append(f"{k[:10]}={100.0*n/e:5.2f}%" + ("*" if set(E) & set(D[k]["unavail"]) else ""))
        print(f"  {'+'.join(x[:4] for x in E):26s} K>={K}  pooled={100.0*pn/pe:5.2f}%  " + " ".join(cells))
    print("  * = an enabled family was UNAVAILABLE on that corpus")
    print("  NAMED PRESETS")
    for name, E, K in PRESETS:
        pn = pe = 0
        per = []
        for k in indep:
            v, e = vecs_of(D[k]), D[k]["eligible"]
            n = sum(c for b, c in v.items() if sel(b, E, K))
            pn += n; pe += e
            per.append(f"{k[:10]}={n}/{e}={100.0*n/e:.2f}%")
        print(f"    {name:8s} families={','.join(E)} K>={K}  pooled={pn}/{pe}={100.0*pn/pe:.2f}%")
        print(f"             " + "  ".join(per))
    if not S:
        return
    print("  NAMED PRESET OUTPUT-SET STABILITY (the gate-jitter question)")
    for name, E, K in PRESETS:
        line = f"    {name:8s}"
        for lbl, blk in S.items():
            snaps = blk["snaps"]
            mean, ep = ladder_jaccard(snaps, lambda s, E=E, K=K: preset_set(s, E, K))
            line += f"  {lbl[:12]}: n={len(preset_set(snaps[-1], E, K)):5d} jac={mean:.3f}/{ep:.3f}"
        print(line)


def report(cal, stab):
    D = json.load(open(cal))
    order = list(D)
    indep = [k for k in order if D[k]["independent"]]
    S = json.load(open(stab)) if stab else None
    pool, poolh = pooled(D, indep)
    report_corpora(D, order)
    report_marginals(D, order)
    report_correlation(D, order, pool, poolh)
    report_cofiring(D, order, pool)
    report_thresholds(D, order)
    report_rules(D, order)
    if S:
        report_stability(S)
    report_presets(D, indep, S)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["collect", "stability", "report"])
    ap.add_argument("targets", nargs="*")
    ap.add_argument("--out", default="ensemblecal.json")
    ap.add_argument("--in", dest="inp", default="ensemblecal.json")
    ap.add_argument("--stability", default=None)
    ap.add_argument("--samples", type=int, default=8)
    a = ap.parse_args()
    if a.mode == "collect":
        collect(a.targets, a.out)
    elif a.mode == "stability":
        stability(a.targets, a.out, a.samples)
    else:
        report(a.inp, a.stability)


if __name__ == "__main__":
    main()
