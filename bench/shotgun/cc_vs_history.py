#!/usr/bin/env python3
"""Does STATIC fan-in-by-files (CC_file) predict HISTORICAL scatter (mean files per commit touching the file)?
Spearman rho over files present in both the map and the history, plus a quintile table."""
import sys, os, collections, statistics, xml.etree.ElementTree as ET
mapPath, logPath, cap = sys.argv[1], sys.argv[2], 30
root = ET.parse(mapPath).getroot()
defs = collections.defaultdict(list); calls = []
for f in root.iter('f'):
    fp = f.get('p')
    for s in f.findall('s'):
        if s.get('t') in ('fn', 'method', 'macro'): defs[s.get('n')].append(fp)
        for c in s.findall('c'): calls.append((fp, c.get('n')))
inFiles = collections.defaultdict(set)
for fp, cn in calls:
    t = defs.get(cn)
    if not t: continue
    same = [x for x in t if x == fp]
    if len(same) == 1: continue                        # intra-file: not scatter
    if len(t) == 1 and t[0] != fp: inFiles[t[0]].add(fp)
indexed = {f.get('p') for f in root.iter('f')}
commits = []; cur = None
for line in open(logPath, errors='replace'):
    line = line.rstrip('\n')
    if line.startswith('COMMIT '): cur = []; commits.append(cur)
    elif line.strip() and cur is not None: cur.append(line.strip())
hist = collections.defaultdict(list)
for files in commits:
    if 1 <= len(files) <= cap:
        for f in files: hist[f].append(len(files))
rows = []
for f in indexed:
    if f in hist and len(hist[f]) >= 3:
        rows.append((len(inFiles.get(f, ())), statistics.mean(hist[f]), len(hist[f]), f))
def spearman(xs, ys):
    def rank(v):
        order = sorted(range(len(v)), key=lambda i: v[i]); r = [0.0]*len(v); i = 0
        while i < len(order):
            j = i
            while j+1 < len(order) and v[order[j+1]] == v[order[i]]: j += 1
            for k in range(i, j+1): r[order[k]] = (i+j)/2 + 1
            i = j+1
        return r
    rx, ry = rank(xs), rank(ys); n = len(xs); mx, my = sum(rx)/n, sum(ry)/n
    num = sum((a-mx)*(b-my) for a, b in zip(rx, ry)); den = (sum((a-mx)**2 for a in rx)*sum((b-my)**2 for b in ry))**0.5
    return num/den if den else float('nan')
xs = [r[0] for r in rows]; ys = [r[1] for r in rows]; zs = [r[2] for r in rows]
print(f"files in map AND history (>=3 commits): {len(rows)}")
print(f"Spearman rho( static CC_file , historical mean-files-per-commit ) = {spearman(xs, ys):+.3f}")
print(f"Spearman rho( static CC_file , commit count/churn )              = {spearman(xs, zs):+.3f}")
print(f"Spearman rho( churn , historical mean-files-per-commit )         = {spearman(zs, ys):+.3f}")
rows.sort(key=lambda r: r[0]); k = 5
print(f"\nCC_file quintile -> mean historical scatter (files/commit), mean churn")
for q in range(k):
    part = rows[q*len(rows)//k:(q+1)*len(rows)//k]
    if part: print(f"  Q{q+1}: CC_file in [{part[0][0]},{part[-1][0]}]  scatter={statistics.mean(r[1] for r in part):.2f}  churn={statistics.mean(r[2] for r in part):.1f}  n={len(part)}")
print("\ntop-15 by CC_file:  CC  scatter  churn  file")
for cc, sc, n, f in sorted(rows, key=lambda r: -r[0])[:15]: print(f"  {cc:3d}  {sc:6.2f}  {n:4d}  {f}")
