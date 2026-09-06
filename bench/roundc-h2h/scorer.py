#!/usr/bin/env python3
"""THE scorer. One implementation, called from every arm. Nothing else computes
anything. Implements docs/EVALS.md's registered metric verbatim:

  tokens-to-correct-answer = bytes the arm actually emitted, cumulated over its
  output in the order the arm produced it, up to and including the point at
  which EVERY gold file for that question has been named. An arm that never
  names them all scores its FULL emitted bytes and is marked `incomplete` —
  a measurement, not an exclusion.

The audit columns (files_named_before_ttca, last_gold_rank) are descriptive
facts about the same single scoring pass, not a second metric.
"""
from __future__ import annotations
import re

# ONE path extractor, used for the audit columns only. Corpus-relative paths.
_PATH_RE = re.compile(
    rb'(?:[A-Za-z0-9_.+-]+/)+[A-Za-z0-9_.+-]+\.(?:cc|h|cpp|hpp|cxx|hxx|hh|c|java|py)\b')


def score(qid: int, arm: str, raw: bytes, gold: list[str], wall_ms: float,
          rc: int, argv: list[str]) -> dict:
    emitted = len(raw)
    offsets = {}
    for g in gold:
        gb = g.encode()
        i = raw.find(gb)
        offsets[g] = (i + len(gb)) if i >= 0 else None

    hits = sum(1 for v in offsets.values() if v is not None)
    complete = (hits == len(gold)) and len(gold) > 0
    ttca = max(v for v in offsets.values()) if complete else emitted

    # audit columns: how much undifferentiated haystack sits inside the ttca window
    window = raw[:ttca]
    named = set(m.group(0) for m in _PATH_RE.finditer(window))
    all_named = [m.group(0) for m in _PATH_RE.finditer(raw)]
    seen, ordered = set(), []
    for p in all_named:
        if p not in seen:
            seen.add(p); ordered.append(p)
    last_gold_rank = None
    if complete:
        ranks = []
        for g in gold:
            gb = g.encode()
            r = next((i for i, p in enumerate(ordered) if p.endswith(gb)), None)
            ranks.append(r if r is not None else 10 ** 9)
        last_gold_rank = max(ranks) + 1

    return dict(qid=qid, arm=arm, ttca_bytes=ttca, emitted_bytes=emitted,
                complete=complete, hits=hits, n_gold=len(gold),
                files_named_before_ttca=len(named),
                total_files_named=len(ordered),
                last_gold_rank=last_gold_rank,
                wall_ms=round(wall_ms, 1), rc=rc, argv=argv)
