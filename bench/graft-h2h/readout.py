#!/usr/bin/env python3
"""Readout of a results file: per-arm totals, the paired verdicts, and the placebo rule.

The placebo comparison follows the AMENDED Round C rule (docs/EVALS.md, "The placebo arm"):
  ripwire beats the placebo on a row when it completes and the placebo does not, or both complete and
  ripwire's TTCA is strictly smaller; a row where BOTH are incomplete is a TIE (decided only by
  line-truncation slack), reported in its own column; the placebo wins the rest.
The same three-way rule is applied to every ripwire-vs-arm pairing so the columns are comparable.

Usage: python3 readout.py results.json [results_post.json]
"""
from __future__ import annotations
import json, statistics, sys
from collections import defaultdict

def load(p):
    rows = json.load(open(p))
    by = defaultdict(dict)
    for r in rows:
        by[r['qid']][r['arm']] = r
    return by

def verdict(a, b):
    """a vs b -> 'win' | 'tie' | 'loss' for a."""
    if a['complete'] and not b['complete']: return 'win'
    if b['complete'] and not a['complete']: return 'loss'
    if not a['complete'] and not b['complete']: return 'tie'
    if a['ttca_bytes'] < b['ttca_bytes']: return 'win'
    if a['ttca_bytes'] > b['ttca_bytes']: return 'loss'
    return 'tie'

def table(by, arms):
    print(f"| arm | complete | gold files named | median TTCA (B) | median wall ms |")
    print(f"| --- | ---: | ---: | ---: | ---: |")
    for arm in arms:
        rows = [by[q][arm] for q in sorted(by) if arm in by[q]]
        if not rows: continue
        comp = sum(r['complete'] for r in rows)
        hits = sum(r['hits'] for r in rows); gold = sum(r['n_gold'] for r in rows)
        med = statistics.median(r['ttca_bytes'] for r in rows)
        wall = statistics.median(r['wall_ms'] for r in rows)
        print(f"| {arm} | {comp}/{len(rows)} | {hits}/{gold} = {100*hits//gold}% | {med:,.0f} | {wall:,.0f} |")

def paired(by, ref, arms):
    print(f"\n| {ref} vs | wins | ties | losses |")
    print("| --- | ---: | ---: | ---: |")
    for arm in arms:
        if arm == ref: continue
        c = defaultdict(int)
        for q in sorted(by):
            if ref in by[q] and arm in by[q]:
                c[verdict(by[q][ref], by[q][arm])] += 1
        print(f"| {arm} | {c['win']} | {c['tie']} | {c['loss']} |")

def per_shape(by, arms, qs):
    shape = {q['qid']: q['shape'] for q in qs}
    print("\nper-shape completions (complete / gold named):")
    hdr = "| shape | " + " | ".join(arms) + " |"
    print(hdr); print("| --- |" + " ---: |" * len(arms))
    for s in ('S1', 'S2', 'S3', 'S4', 'S5'):
        cells = []
        for arm in arms:
            rows = [by[q][arm] for q in sorted(by) if shape[q] == s and arm in by[q]]
            cells.append(f"{sum(r['complete'] for r in rows)}/{len(rows)} · {sum(r['hits'] for r in rows)}/{sum(r['n_gold'] for r in rows)}")
        print(f"| {s} | " + " | ".join(cells) + " |")

def losses(by, ref, arm, qs):
    shape = {q['qid']: (q['shape'], q['question']) for q in qs}
    out = []
    for q in sorted(by):
        if ref in by[q] and arm in by[q] and verdict(by[q][ref], by[q][arm]) == 'loss':
            a, b = by[q][ref], by[q][arm]
            out.append(f"q{q:02d} {shape[q][0]} {ref} {a['ttca_bytes']}{'' if a['complete'] else '*'} "
                       f"({a['hits']}/{a['n_gold']})  vs {arm} {b['ttca_bytes']}{'' if b['complete'] else '*'} "
                       f"({b['hits']}/{b['n_gold']})  — {shape[q][1][:80]}")
    return out

if __name__ == '__main__':
    import os
    HERE = os.path.dirname(os.path.abspath(__file__))
    qs = json.load(open(os.path.join(HERE, '..', 'roundc-h2h', 'questions.json')))
    for p in sys.argv[1:]:
        by = load(p)
        arms = []
        for q in by.values():
            for a in q:
                if a not in arms: arms.append(a)
        print(f"\n## {p}\n")
        table(by, arms)
        paired(by, 'ripwire-warm', arms)
        per_shape(by, arms, qs)
        for arm in arms:
            if arm.startswith('graft') or arm == 'placebo':
                ls = losses(by, 'ripwire-warm', arm, qs)
                print(f"\nripwire-warm LOSSES vs {arm}: {len(ls)}")
                for l in ls: print("  " + l)
