#!/usr/bin/env python3
"""Sweep of single common English words against --for --json, two corpora.

Companion to run_adaptive_shortquery.py. The five-query set in that script showed one word
("value") behaving safely (name-exact route onto a SMALL homonym cluster, sharp legitimate cut) --
this sweep asks whether that holds for other common one-word queries, or whether some resolve to a
LARGE homonym cluster (many unrelated symbols sharing the literal name) where the adaptive cut's
"confidence=high" is misleading. See docs/research/adaptive-short-query.md for the analysis.

Usage:
    python3 word_sweep.py --bin /path/to/ripwire --corpus name=/path [--corpus name2=/path2] [--words w1,w2,...]
"""
import argparse
import json
import subprocess

DEFAULT_WORDS = ["get", "set", "init", "update", "run", "load", "name", "data",
                  "test", "add", "remove", "find", "check"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--corpus", action="append", required=True, help="name=path, repeatable")
    ap.add_argument("--words", default=",".join(DEFAULT_WORDS))
    args = ap.parse_args()

    corpora = dict(c.split("=", 1) for c in args.corpus)
    words = args.words.split(",")

    rows = []
    for w in words:
        for label, path in corpora.items():
            p = subprocess.run([args.bin, path, f"--for={w}", "--json"],
                                capture_output=True, text=True, timeout=60)
            try:
                d = json.loads(p.stdout)
            except Exception as e:
                print(f"{label:10s} {w:8s} ERR {e}")
                continue
            row = {
                "corpus": label, "word": w, "route": d.get("route"),
                "confidence": d.get("confidence"), "margin_pct": d.get("margin_pct"),
                "kept": d.get("kept"), "scored": d.get("scored"), "corpus_n": d.get("corpus"),
            }
            rows.append(row)
            slash = (1.0 - row["kept"] / row["scored"]) if row["scored"] else 0.0
            print(f"{label:10s} {w:8s} route={str(row['route'])[:26]:26s} conf={row['confidence']:5s} "
                  f"margin={row['margin_pct']:>3} kept={row['kept']:>4} scored={row['scored']:>5} "
                  f"discard={slash:5.0%}")
    return rows


if __name__ == "__main__":
    main()
