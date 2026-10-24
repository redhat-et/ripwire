#!/usr/bin/env python3
"""Measure --adaptive's cut behavior on short/low-content queries vs richer ones.

Research support for docs/research/adaptive-short-query.md. Runs `ripwire <corpus> --for="Q" --json`
twice per query (with and without --adaptive) against two corpora, and records the disclosed
confidence/margin_pct/kept/scored/corpus facts plus the actually-served row count and the top few
signature names (for an eyeball relevance check -- there is no external gold set for these ad hoc
queries, so "gold-ish" survival is judged by a human reading the printed top-5, not scored here).

Usage:
    python3 run_adaptive_shortquery.py --bin /path/to/ripwire --out results.json \
        --corpus repo1=/path/to/repo1 --corpus repo2=/path/to/repo2

Deterministic modulo the corpus and binary: same binary + same tree -> same output (G3/G-determinism
contract), so re-running this script re-derives the same table.
"""
import argparse
import json
import subprocess
import sys

QUERIES = [
    ("common_word",        "value"),
    ("two_words",           None),   # filled per-corpus below
    ("contentless",         "summarize this"),
    ("technical_multiword", None),   # filled per-corpus below
    ("named_symbol",        None),   # filled per-corpus below
]

# Per-corpus overrides for the three queries that need a real symbol/concept from that tree.
PER_CORPUS = {
    "ripwire": {
        "two_words": "data flow",
        "technical_multiword": "cut a ranked list at the largest relative score gap",
        "named_symbol": "adaptiveCut",
    },
    # The second corpus used for the recorded run is private and not redistributable;
    # its three corpus-specific queries are redacted. Fill these in for your own
    # second corpus: a two-word domain phrase, a specific multi-word technical task,
    # and one symbol that really exists in that tree.
    "private-corpus": {
        "two_words": "<two-word domain phrase>",
        "technical_multiword": "<specific multi-word technical task>",
        "named_symbol": "<a symbol that exists in that corpus>",
    },
}


def run_for(binpath, corpus, query, adaptive):
    args = [binpath, corpus, "--for=" + query, "--json"]
    if adaptive:
        args.append("--adaptive")
    p = subprocess.run(args, capture_output=True, text=True, timeout=120)
    if p.returncode != 0:
        return {"error": f"rc={p.returncode}", "stderr": p.stderr[-500:]}
    try:
        d = json.loads(p.stdout)
    except json.JSONDecodeError as e:
        return {"error": f"bad json: {e}", "stdout_head": p.stdout[:300]}
    sigs = d.get("sigs", [])
    return {
        "route": d.get("route"),
        "confidence": d.get("confidence"),
        "margin_pct": d.get("margin_pct"),
        "kept_disclosed": d.get("kept"),
        "scored": d.get("scored"),
        "corpus_n": d.get("corpus"),
        "served_rows": len(sigs),
        "top5": [f'{s.get("n")}({s.get("p")}:{s.get("l")})' for s in sigs[:5]],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--corpus", action="append", required=True, help="name=path, repeatable")
    args = ap.parse_args()

    corpora = dict(c.split("=", 1) for c in args.corpus)

    results = []
    for cname, cpath in corpora.items():
        overrides = PER_CORPUS.get(cname, {})
        for label, default_q in QUERIES:
            q = overrides.get(label, default_q)
            if q is None:
                print(f"skip {cname}/{label}: no query defined", file=sys.stderr)
                continue
            row = {"corpus": cname, "label": label, "query": q}
            row["default"] = run_for(args.bin, cpath, q, adaptive=False)
            row["adaptive"] = run_for(args.bin, cpath, q, adaptive=True)
            results.append(row)
            print(f"{cname:14s} {label:20s} {q!r:55s} "
                  f"default={row['default'].get('served_rows')} "
                  f"adaptive={row['adaptive'].get('served_rows')} "
                  f"conf={row['default'].get('confidence')}/{row['default'].get('margin_pct')}",
                  file=sys.stderr)

    with open(args.out, "w") as f:
        json.dump(results, f, indent=2)
    print(f"wrote {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
