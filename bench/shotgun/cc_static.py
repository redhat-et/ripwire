#!/usr/bin/env python3
"""Static Shotgun-Surgery prototype (Lanza & Marinescu 2006): CM = distinct caller symbols, CC = distinct caller
FILES, read off ripwire's own map (<f p=><s n= id=><c n=/></s></f>). Name-based inversion: a callee name with
several defs is credited to the same-file def when one exists; otherwise the edge is DROPPED (the default, an
honest floor) or, with a 4th argument `all`, credited to EVERY def (an upper bound, marked amb — this is what
puts `size`/`empty`/`find` at the top: a resolver artifact, shown only to explain why the floor is the rule).
    python3 bench/shotgun/cc_static.py MAP.xml [CM_T=7] [CC_T=5] [unambiguous|all]"""
import sys, collections, xml.etree.ElementTree as ET
path = sys.argv[1]; CM_T = int(sys.argv[2]) if len(sys.argv) > 2 else 7; CC_T = int(sys.argv[3]) if len(sys.argv) > 3 else 5
creditAll = len(sys.argv) > 4 and sys.argv[4] == 'all'
root = ET.parse(path).getroot()
defs = collections.defaultdict(list)   # name -> [(file, key, kind)]
syms = []                              # (file, name, key, kind, [callee names])
for f in root.iter('f'):
    fp = f.get('p')
    for s in f.findall('s'):
        key = s.get('id') or f"{fp}::{s.get('n')}"
        if s.get('t') in ('fn', 'method', 'macro'):
            defs[s.get('n')].append((fp, key, s.get('t')))
        syms.append((fp, s.get('n'), key, s.get('t'), [c.get('n') for c in s.findall('c')]))
callerSyms = collections.defaultdict(set); callerFiles = collections.defaultdict(set); amb = collections.defaultdict(int)
kindOf = {}; fileOf = {}
for fp, name, key, kind, callees in syms:
    kindOf[key] = kind; fileOf[key] = fp
    for cn in callees:
        targets = defs.get(cn)
        if not targets: continue
        same = [t for t in targets if t[0] == fp]
        chosen = same if len(same) == 1 else (targets if (creditAll or len(targets) == 1) else [])
        for tf, tk, tt in chosen:
            if tk == key: continue                   # self-recursion is not a caller
            callerSyms[tk].add(key); callerFiles[tk].add(fp)
            if len(chosen) > 1: amb[tk] += 1
rows = []
for key in callerSyms:
    cm, cc = len(callerSyms[key]), len(callerFiles[key])
    rows.append((cc, cm, amb[key], fileOf.get(key, '?'), key))
n_syms = sum(1 for s in syms if s[3] in ('fn', 'method', 'macro'))
flag = [r for r in rows if r[1] > CM_T and r[0] > CC_T]
print(f"callable symbols={n_syms} with>=1 caller={len(rows)}  FLAGGED (CM>{CM_T} AND CC>{CC_T}) = {len(flag)}  ({100*len(flag)/max(1,n_syms):.2f}% of callables)")
ccs = sorted(r[0] for r in rows)
q = lambda p: ccs[min(len(ccs)-1, int(p*len(ccs)))]
print(f"CC quantiles over symbols with a caller: p50={q(.5)} p90={q(.9)} p95={q(.95)} p99={q(.99)} max={ccs[-1]}")
for t in (2,3,5,8,10,15,20):
    print(f"  CC>={t}: {sum(1 for c in ccs if c>=t)}", end='')
print()
print(f"\n{'CC':>3} {'CM':>4} {'amb':>4}  {'file':<40} symbol")
for cc, cm, a, fp, key in sorted(flag, key=lambda r: (-r[0], -r[1], r[4]))[:60]:
    print(f"{cc:3d} {cm:4d} {a:4d}  {fp:<40} {key}")
