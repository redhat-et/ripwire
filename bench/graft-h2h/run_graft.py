#!/usr/bin/env python3
"""Run the Graft head-to-head on the FROZEN Round C instrument.

Same `questions.json`, same `scorer.py`, same corpus at the same pin, same placebo construction.
Nothing is re-derived or re-selected. Paired per question; arm order alternates by question-index
parity; the placebo runs last because its budget is what ripwire-warm actually emitted.

Usage:
  RW_H2H_HOME=<scratch h2h tree> RIPWIRE_BIN=<ripwire> [OUT=results.json] python3 run_graft.py
"""
from __future__ import annotations
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'roundc-h2h'))
import arms            # noqa: E402
import arms_graft      # noqa: E402
from scorer import score  # noqa: E402

qs = json.load(open(os.path.join(HERE, '..', 'roundc-h2h', 'questions.json')))
OUT = os.environ.get('OUT', 'results.json')

universe = sorted(
    f for f in subprocess.run(['git', '-C', arms.CORPUS, 'ls-files'],
                              capture_output=True, text=True).stdout.split('\n')
    if f.endswith(('.cc', '.h', '.cpp', '.hpp', '.c', '.cxx', '.hxx', '.hh')))
print(f"placebo universe: {len(universe)} C/C++ files", file=sys.stderr)

REAL = [
    ('ripwire-cold',  lambda q: arms.ripwire(q, True)),
    ('ripwire-warm',  lambda q: arms.ripwire(q, False)),
    ('graft-ask',     arms_graft.graft_ask),
    ('graft-expert',  arms_graft.graft_expert),
    ('rg-floor',      arms.rg_floor),
]
NAMES = [n for n, _ in REAL] + ['placebo']

rows, raws = [], {}
for q in qs:
    order = REAL if q['qid'] % 2 == 0 else list(reversed(REAL))
    per = {}
    for name, fn in order:
        out, ms, rc, argv = fn(q)
        per[name] = score(q['qid'], name, out, q['gold'], ms, rc, argv)
        raws[f"{q['qid']}:{name}"] = out
    budget = per['ripwire-warm']['emitted_bytes']
    out, ms, rc, argv = arms.placebo(q, universe, budget)
    per['placebo'] = score(q['qid'], 'placebo', out, q['gold'], ms, rc, argv)
    raws[f"{q['qid']}:placebo"] = out
    rows.extend(per[n] for n in NAMES)
    print(f"q{q['qid']:2d} {q['shape']} n={q['n']:2d} " + "  ".join(
        f"{n}={per[n]['ttca_bytes']}{'' if per[n]['complete'] else '*'}" for n in NAMES),
        file=sys.stderr)

json.dump(rows, open(os.path.join(HERE, OUT), 'w'), indent=1)
rawdir = os.path.join(HERE, 'raw' if OUT == 'results.json' else 'raw_' + OUT.replace('.json', ''))
os.makedirs(rawdir, exist_ok=True)
for k, v in raws.items():
    qid, arm = k.split(':')
    open(os.path.join(rawdir, f"q{int(qid):02d}.{arm}.txt"), 'wb').write(v)
print(f"wrote {OUT}", file=sys.stderr)
