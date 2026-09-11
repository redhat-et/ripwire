#!/usr/bin/env python3
"""Re-run ONLY the arms a ripwire change can move — ripwire cold/warm and the placebo (whose budget is
ripwire-warm's emitted bytes) — on the FROZEN 30, carrying the foreign columns (graft-ask, graft-expert,
rg-floor) from a prior results file unchanged. Round C's rerun_post.py posture: a re-run of an arm nothing
touched adds noise to a paired comparison it is not part of (the Graft columns reproduced byte-for-byte on
30/30 across the two full runs anyway).

Usage: RW_H2H_HOME=<h2h tree> RIPWIRE_BIN=<ripwire> FROM=results_post.json OUT=results_post2.json python3 rerun_ripwire.py
"""
from __future__ import annotations
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'roundc-h2h'))
import arms                # noqa: E402
from scorer import score   # noqa: E402
qs = json.load(open(os.path.join(HERE, '..', 'roundc-h2h', 'questions.json')))
FROM, OUT = os.environ.get('FROM', 'results_post.json'), os.environ.get('OUT', 'results_post2.json')
prev = {(r['qid'], r['arm']): r for r in json.load(open(os.path.join(HERE, FROM)))}
universe = sorted(f for f in subprocess.run(['git', '-C', arms.CORPUS, 'ls-files'], capture_output=True, text=True).stdout.split('\n')
                  if f.endswith(('.cc', '.h', '.cpp', '.hpp', '.c', '.cxx', '.hxx', '.hh')))
rows = []
for q in qs:
    per = {}
    for name, cold in (('ripwire-cold', True), ('ripwire-warm', False)):
        out, ms, rc, argv = arms.ripwire(q, cold)
        per[name] = score(q['qid'], name, out, q['gold'], ms, rc, argv)
    for name in ('graft-ask', 'graft-expert', 'rg-floor'):
        per[name] = prev[(q['qid'], name)]
    out, ms, rc, argv = arms.placebo(q, universe, per['ripwire-warm']['emitted_bytes'])
    per['placebo'] = score(q['qid'], 'placebo', out, q['gold'], ms, rc, argv)
    rows.extend(per[n] for n in ('ripwire-cold', 'ripwire-warm', 'graft-ask', 'graft-expert', 'rg-floor', 'placebo'))
    a, b = prev[(q['qid'], 'ripwire-warm')], per['ripwire-warm']
    print(f"q{q['qid']:2d} {q['shape']} n={q['n']:2d} hits {a['hits']}->{b['hits']}  ttca {a['ttca_bytes']}{'' if a['complete'] else '*'}->{b['ttca_bytes']}{'' if b['complete'] else '*'}", file=sys.stderr)
json.dump(rows, open(os.path.join(HERE, OUT), 'w'), indent=1)
print(f"wrote {OUT}", file=sys.stderr)
