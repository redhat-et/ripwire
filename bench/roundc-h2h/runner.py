#!/usr/bin/env python3
"""Run the registered head-to-head. Paired per question, arm order alternating
by question-index parity, one scorer called from every arm."""
from __future__ import annotations
import json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arms
from scorer import score

HERE = os.path.dirname(os.path.abspath(__file__))
qs = json.load(open(os.path.join(HERE, 'questions.json')))

universe = sorted(
    f for f in subprocess.run(['git', '-C', arms.CORPUS, 'ls-files'],
                              capture_output=True, text=True).stdout.split('\n')
    if f.endswith(('.cc', '.h', '.cpp', '.hpp', '.c', '.cxx', '.hxx', '.hh')))
print(f"placebo universe: {len(universe)} C/C++ files", file=sys.stderr)

REAL = [
    ('ripwire-cold', lambda q: arms.ripwire(q, True)),
    ('ripwire-warm', lambda q: arms.ripwire(q, False)),
    ('gortex',       arms.gortex),
    ('cocoindex',    arms.cocoindex),
    ('rg-floor',     arms.rg_floor),
]

rows, raws = [], {}
for q in qs:
    order = REAL if q['qid'] % 2 == 0 else list(reversed(REAL))
    per = {}
    for name, fn in order:
        out, ms, rc, argv = fn(q)
        per[name] = score(q['qid'], name, out, q['gold'], ms, rc, argv)
        raws[f"{q['qid']}:{name}"] = out
    # placebo last: its budget is what the ripwire arm actually consumed here
    budget = per['ripwire-warm']['emitted_bytes']
    out, ms, rc, argv = arms.placebo(q, universe, budget)
    per['placebo'] = score(q['qid'], 'placebo', out, q['gold'], ms, rc, argv)
    raws[f"{q['qid']}:placebo"] = out
    for name in [n for n, _ in REAL] + ['placebo']:
        rows.append(per[name])
    print(f"q{q['qid']:2d} {q['shape']} n={q['n']:2d} " + "  ".join(
        f"{n}={per[n]['ttca_bytes']}{'' if per[n]['complete'] else '*'}"
        for n in [x for x, _ in REAL] + ['placebo']), file=sys.stderr)

json.dump(rows, open(os.path.join(HERE, 'results.json'), 'w'), indent=1)
os.makedirs(os.path.join(HERE, 'raw'), exist_ok=True)
for k, v in raws.items():
    qid, arm = k.split(':')
    open(os.path.join(HERE, 'raw', f"q{int(qid):02d}.{arm}.txt"), 'wb').write(v)
print("wrote results.json", file=sys.stderr)
