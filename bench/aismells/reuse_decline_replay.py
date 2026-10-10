#!/usr/bin/env python3
"""How often does `--quality-delta`'s reuse-decline kind actually FIRE?

Replays `ripwire <root> --quality-delta=<parent>..<sha>` over a window of commits and
counts, per kind, how many rows each commit produced. The reuse-decline kind is spelled
`new-clone-of-reused-helper` in the output.

    python3 bench/aismells/reuse_decline_replay.py --bin ./build/ripwire --root . --commits 150
    python3 bench/aismells/reuse_decline_replay.py --bin ./build/ripwire \
        --corpus /path/to/checkouts --repos 20 --commits 20

Prints a per-commit TSV (only commits with at least one row, unless --all) and a summary.
Merge commits are skipped: a range whose base is one of several parents does not describe
"what this change made worse".
"""

import argparse
import re
import subprocess
import sys
from collections import Counter

from corpora import resolve_roots

ROW_RE = re.compile(r'<r\s([^>]*?)/?>')
ACK_RE = re.compile(r'<sa\s([^>]*?)/?>')
COMMENT_RE = re.compile(r'<!--.*?-->', re.S)
ATTR_RE = re.compile(r'(\w+)="([^"]*)"')
HDR_RE = re.compile(r'<quality-delta\b([^>]*)>')
REUSE = "new-clone-of-reused-helper"


def git(root, *args):
    proc = subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError("git %s rc=%d: %s" % (" ".join(args), proc.returncode, proc.stderr.strip()[:200]))
    return proc.stdout


def commit_window(root, count):
    """Non-merge commits, newest first, that have exactly one parent."""
    out = git(root, "log", "--no-merges", "--first-parent", "-n", str(count), "--format=%H")
    return [line.strip() for line in out.splitlines() if line.strip()]


def delta_rows(binary, root, sha, timeout):
    cmd = [binary, root, "--quality-delta=%s~1..%s" % (sha, sha), "--legend=compact"]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    # rc 2 = "something got materially worse" — an expected, informative exit, not a failure.
    if proc.returncode not in (0, 2):
        raise RuntimeError("rc=%d %s" % (proc.returncode, proc.stderr.strip()[:200]))
    xml = COMMENT_RE.sub("", proc.stdout)   # the legend comment spells the row grammar; it is not a row
    hdr = dict(ATTR_RE.findall(HDR_RE.search(xml).group(1))) if HDR_RE.search(xml) else {}
    kinds = Counter()
    reuse_rows = []
    for attrs_txt in ROW_RE.findall(xml):
        attrs = dict(ATTR_RE.findall(attrs_txt))
        kind = attrs.get("kind", "?")
        kinds[kind] += 1
        if kind == REUSE:
            reuse_rows.append(attrs)
    acked = Counter()
    for attrs_txt in ACK_RE.findall(xml):
        acked[dict(ATTR_RE.findall(attrs_txt)).get("kind", "?")] += 1
    return hdr, kinds, reuse_rows, acked


def sweep(binary, root, label, args, out):
    kinds_total = Counter()
    acked_total = Counter()
    fired = 0
    seen = 0
    reuse_detail = []
    for sha in commit_window(root, args.commits):
        try:
            _hdr, kinds, reuse_rows, acked = delta_rows(binary, root, sha, args.timeout)
        except Exception as exc:                     # noqa: BLE001 - one bad commit must not end the sweep
            print("%s\t%s\tERROR\t%s" % (label, sha[:12], exc), file=sys.stderr)
            continue
        seen += 1
        kinds_total.update(kinds)
        acked_total.update(acked)
        if kinds.get(REUSE):
            fired += 1
            for attrs in reuse_rows:
                reuse_detail.append((label, sha[:12], attrs.get("now", "?"),
                                     attrs.get("p", "?"), (attrs.get("members") or attrs.get("sym") or "?")[:240]))
        if args.all or kinds:
            print("%s\t%s\t%d\t%d" % (label, sha[:12], sum(kinds.values()), kinds.get(REUSE, 0)), file=out)
    return seen, fired, kinds_total, reuse_detail, acked_total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--root", default=".")
    ap.add_argument("--corpus", help="directory of checkouts; sweep each subdirectory")
    ap.add_argument("--repos", type=int, default=0, help="stop after this many corpus repos")
    ap.add_argument("--commits", type=int, default=50)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--all", action="store_true", help="print a row even for clean commits")
    args = ap.parse_args()

    roots = resolve_roots(args.root, args.corpus, args.repos, require_git=True)

    seen_all = fired_all = 0
    kinds_all = Counter()
    acked_all = Counter()
    detail_all = []
    print("root\tcommit\trows\treuse_decline_rows")
    for label, path in roots:
        seen, fired, kinds, detail, acked = sweep(args.bin, path, label, args, sys.stdout)
        seen_all += seen
        fired_all += fired
        kinds_all.update(kinds)
        acked_all.update(acked)
        detail_all.extend(detail)

    print("\n# commits swept: %d" % seen_all)
    print("# commits with >=1 reuse-decline row: %d (%.2f%%)"
          % (fired_all, 100.0 * fired_all / seen_all if seen_all else 0.0))
    print("# rows by kind (all commits):")
    for kind, count in sorted(kinds_all.items(), key=lambda kv: (-kv[1], kv[0])):
        print("#   %-32s %6d" % (kind, count))
    print("# acked/stale ledger rows by kind (suppressed, never gating):")
    for kind, count in sorted(acked_all.items(), key=lambda kv: (-kv[1], kv[0]))[:12]:
        print("#   %-32s %6d" % (kind, count))
    if detail_all:
        print("\n# reuse-decline rows (root, commit, eroded helper fan-in, locator, members):")
        for row in detail_all:
            print("#   %s" % "\t".join(row))


if __name__ == "__main__":
    main()
