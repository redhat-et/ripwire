#!/usr/bin/env python3
"""Clone LOCALITY: how much near-duplicate code sits in DIFFERENT files vs the same file.

Feeds on `ripwire <root> --clones --limit=N`, which already reports every clone group
with one `<f n= p="path:line"/>` row per member. The only thing added here is the
same-file / cross-file split, which the verb does not compute today.

    python3 bench/aismells/clone_locality.py --bin ./build/ripwire --root .
    python3 bench/aismells/clone_locality.py --bin ./build/ripwire --corpus DIR --max 40

Output is a TSV table on stdout (one row per root) plus a totals line. Deterministic:
a pure function of ripwire's own deterministic output.
"""

import argparse
import os
import re
import subprocess
import sys

from corpora import resolve_roots

GROUP_RE = re.compile(r'<group\b([^>]*)>(.*?)</group>', re.S)
MEMBER_RE = re.compile(r'<f\b[^>]*\bp="([^"]*)"')
ATTR_RE = re.compile(r'(\w+)="([^"]*)"')


def run_clones(binary, root, limit, timeout):
    cmd = [binary, root, "--clones", "--limit=%d" % limit]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError("ripwire --clones rc=%d on %s: %s"
                           % (proc.returncode, root, proc.stderr.strip()[:200]))
    return proc.stdout


def classify(xml, skip_exempt):
    """Return (same_file, cross_file, exempt, per_type, cross_dir) group counts for one root."""
    same = cross = exempt = cross_dir = 0
    per_type = {"2": [0, 0], "3": [0, 0]}   # type -> [same, cross]
    for attrs_txt, body in GROUP_RE.findall(xml):
        attrs = dict(ATTR_RE.findall(attrs_txt))
        if skip_exempt and "exempt" in attrs:
            exempt += 1
            continue
        files = {p.rsplit(":", 1)[0] for p in MEMBER_RE.findall(body)}
        gtype = attrs.get("type", "2")
        slot = per_type.setdefault(gtype, [0, 0])
        if len(files) <= 1:
            same += 1
            slot[0] += 1
        else:
            cross += 1
            slot[1] += 1
            if len({f.rsplit("/", 1)[0] for f in files}) > 1:
                cross_dir += 1
    return same, cross, exempt, per_type, cross_dir


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--root", default=".")
    ap.add_argument("--corpus", help="directory of checkouts; every subdirectory is a root")
    ap.add_argument("--max", type=int, default=0, help="stop after this many roots (0 = all)")
    ap.add_argument("--limit", type=int, default=100000)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--keep-exempt", action="store_true",
                    help="count fixture/shell-runner groups too (default: skip, as quality-delta does)")
    args = ap.parse_args()

    tot_same = tot_cross = tot_exempt = 0
    tot_t2 = [0, 0]
    tot_t3 = [0, 0]
    tot_cross_dir = 0
    print("root\tgroups\tsame_file\tcross_file\tcross_pct\tcross_dir\texempt_skipped")
    for label, root in resolve_roots(args.root, args.corpus, args.max):
        try:
            xml = run_clones(args.bin, root, args.limit, args.timeout)
        except Exception as exc:                       # noqa: BLE001 - a root that will not index is reported, not fatal
            print("%s\tERROR\t%s" % (root, exc), file=sys.stderr)
            continue
        same, cross, exempt, per_type, cross_dir = classify(xml, not args.keep_exempt)
        total = same + cross
        pct = (100.0 * cross / total) if total else 0.0
        print("%s\t%d\t%d\t%d\t%.1f\t%d\t%d" % (label, total, same, cross, pct, cross_dir, exempt))
        tot_same += same
        tot_cross += cross
        tot_exempt += exempt
        tot_cross_dir += cross_dir
        for idx in (0, 1):
            tot_t2[idx] += per_type.get("2", [0, 0])[idx]
            tot_t3[idx] += per_type.get("3", [0, 0])[idx]

    grand = tot_same + tot_cross
    pct = (100.0 * tot_cross / grand) if grand else 0.0
    print("TOTAL\t%d\t%d\t%d\t%.1f\t%d\t%d" % (grand, tot_same, tot_cross, pct, tot_cross_dir, tot_exempt))
    print("TYPE2\t%d\t%d\t%d\t%.1f\t-\t-" % (tot_t2[0] + tot_t2[1], tot_t2[0], tot_t2[1],
                                          100.0 * tot_t2[1] / (tot_t2[0] + tot_t2[1]) if (tot_t2[0] + tot_t2[1]) else 0.0))
    print("TYPE3\t%d\t%d\t%d\t%.1f\t-\t-" % (tot_t3[0] + tot_t3[1], tot_t3[0], tot_t3[1],
                                          100.0 * tot_t3[1] / (tot_t3[0] + tot_t3[1]) if (tot_t3[0] + tot_t3[1]) else 0.0))


if __name__ == "__main__":
    main()
