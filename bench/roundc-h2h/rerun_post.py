#!/usr/bin/env python3
"""POST-FIX re-run of the FROZEN 30 questions — the paired half of the round-C loss list.

Only the arms that CAN have moved are re-run: ripwire (cold + warm) and the placebo,
whose budget is defined by ripwire's emitted bytes and therefore moves with it. gortex,
cocoindex-code and the rg floor are untouched by this lane's changes, so their frozen
columns in results.json stand as measured and re-running them would only add noise
(and 16 minutes of daemon setup) to a paired comparison they are not part of.

The questions are read from the SAME questions.json and are NOT re-derived, re-scoped
or re-selected. The scorer is the SAME scorer.py. Nothing here may change either.

Usage:  RW_H2H_HOME=<scratch h2h tree> RIPWIRE_POST=<post-fix ripwire> python3 rerun_post.py
"""
from __future__ import annotations
import json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arms
from scorer import score

HERE = os.path.dirname(os.path.abspath(__file__))
POST = os.environ.get('RIPWIRE_POST')
if not POST or not os.path.exists(POST):
    sys.exit("RIPWIRE_POST must name the post-fix binary")
arms.RIPWIRE = POST

qs = json.load(open(os.path.join(HERE, 'questions.json')))
pre = {(r['qid'], r['arm']): r for r in json.load(open(os.path.join(HERE, 'results.json')))}

universe = sorted(
    f for f in subprocess.run(['git', '-C', arms.CORPUS, 'ls-files'],
                              capture_output=True, text=True).stdout.split('\n')
    if f.endswith(('.cc', '.h', '.cpp', '.hpp', '.c', '.cxx', '.hxx', '.hh')))

rows = []
for q in qs:
    per = {}
    for name, cold in (('ripwire-cold', True), ('ripwire-warm', False)):
        out, ms, rc, argv = arms.ripwire(q, cold)
        per[name] = score(q['qid'], name, out, q['gold'], ms, rc, argv)
    out, ms, rc, argv = arms.placebo(q, universe, per['ripwire-warm']['emitted_bytes'])
    per['placebo'] = score(q['qid'], 'placebo', out, q['gold'], ms, rc, argv)
    rows.extend(per[n] for n in ('ripwire-cold', 'ripwire-warm', 'placebo'))
    a, b = pre[(q['qid'], 'ripwire-warm')], per['ripwire-warm']
    print(f"q{q['qid']:2d} {q['shape']} n={q['n']:2d} "
          f"hits {a['hits']}->{b['hits']}  ttca {a['ttca_bytes']}{'' if a['complete'] else '*'}"
          f"->{b['ttca_bytes']}{'' if b['complete'] else '*'}", file=sys.stderr)

json.dump(rows, open(os.path.join(HERE, 'results_post.json'), 'w'), indent=1)
print("wrote results_post.json", file=sys.stderr)
