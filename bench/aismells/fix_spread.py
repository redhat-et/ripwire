#!/usr/bin/env python3
"""What does "one fix spread across many files" look like in git history?

Reads `git log --name-only` once per repository (newest-first), classifies each non-merge
commit as a FIX or not from its subject line, and reports, over source files only:

  * how many distinct files a fix commit touches (distribution),
  * how far apart those files sit (distinct top-level directories),
  * the NOVEL-PAIR fraction: of the file pairs a multi-file fix touches together, how many
    had never been committed together before. A high novel-pair fraction is the case
    co-change history cannot warn you about, and therefore the interesting one: the fix
    reached a partner the repository's own history does not connect.

A non-fix CONTROL arm is reported beside it, because "fix commits touch several files" means
nothing until you know how many files an ordinary commit touches in the same repository.

    python3 bench/aismells/fix_spread.py --root . --commits 4000
    python3 bench/aismells/fix_spread.py --corpus /path/to/checkouts --repos 30 --commits 3000

A shallow clone has no history to score: it reports one root commit touching the whole tree,
which looks like a result and is not one. Check `git rev-list --count HEAD` before believing a row.

Deterministic: a pure function of git history at the given window. Prints a TSV row per
repository plus a pooled summary.
"""

import argparse
import itertools
import re
import subprocess
import sys

from corpora import resolve_roots

FIX_RE = re.compile(r'\b(fix(e[sd])?|bug|regression|hotfix|patch|broken|revert|crash|'
                    r'incorrect|wrong|fail(s|ed|ing)?)\b', re.I)
SOURCE_EXT = (".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".hh", ".m", ".mm", ".py", ".ts",
              ".tsx", ".js", ".jsx", ".java", ".rb", ".go", ".rs", ".swift", ".cs", ".sh")
SEP = "\x01"
PAIR_CAP = 60          # a 200-file sweep is a rename, not a fix; bound the pair blow-up
HEADER = ("repo\tcommits\tfix_commits\tmulti_file_pct\t>3_file_pct\t"
          "median_files\tmedian_dirs\tnovel_pair_pct")


def commits(root, window):
    """Yield (subject, [source paths]) newest-first for non-merge commits."""
    cmd = ["git", "-C", root, "log", "--no-merges", "-n", str(window),
           "--name-only", "--format=%x01%s"]   # SEP FIRST: each record is subject-then-names
    proc = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    if proc.returncode != 0:
        raise RuntimeError("git log rc=%d: %s" % (proc.returncode, proc.stderr.strip()[:200]))
    for chunk in proc.stdout.split(SEP):
        lines = [ln for ln in chunk.splitlines() if ln.strip()]
        if not lines:
            continue
        yield lines[0], [p for p in lines[1:] if p.endswith(SOURCE_EXT)]


def top_dir(path):
    parts = path.split("/")
    return parts[0] if len(parts) > 1 else "."


def blank_tally():
    return {"commits": 0, "fix": 0, "multi": 0, "wide": 0, "files": [], "dirs": [],
            "novel_num": 0, "novel_den": 0, "ctrl": 0, "ctrl_multi": 0, "ctrl_files": []}


def count_fix(tally, files, seen_pairs):
    """Fold one FIX commit's file set into the tally, against the pairs history already knows."""
    tally["fix"] += 1
    tally["files"].append(len(files))
    tally["dirs"].append(len({top_dir(p) for p in files}))
    if len(files) > 1:
        tally["multi"] += 1
    if len(files) > 3:
        tally["wide"] += 1
    if not 1 < len(files) <= PAIR_CAP:
        return
    for pair in itertools.combinations(files, 2):
        tally["novel_den"] += 1
        if pair not in seen_pairs:
            tally["novel_num"] += 1


def count_control(tally, files):
    tally["ctrl"] += 1
    tally["ctrl_files"].append(len(files))
    if len(files) > 1:
        tally["ctrl_multi"] += 1


def analyse(root, window):
    """Walk oldest-first so 'were these two files ever committed together BEFORE?' is answerable."""
    history = list(commits(root, window))
    history.reverse()
    tally = blank_tally()
    tally["commits"] = len(history)
    seen_pairs = set()
    for subject, paths in history:
        files = sorted(set(paths))
        if not files:
            continue
        if FIX_RE.search(subject):
            count_fix(tally, files, seen_pairs)
        else:
            count_control(tally, files)
        if len(files) <= PAIR_CAP:
            seen_pairs.update(itertools.combinations(files, 2))
    return tally


def median(values):
    if not values:
        return 0.0
    ordered = sorted(values)
    mid = len(ordered) // 2
    return float(ordered[mid]) if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2.0


def pct(num, den):
    return 100.0 * num / den if den else 0.0


def row(label, t):
    return "%s\t%d\t%d\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f" % (
        label, t["commits"], t["fix"], pct(t["multi"], t["fix"]), pct(t["wide"], t["fix"]),
        median(t["files"]), median(t["dirs"]), pct(t["novel_num"], t["novel_den"]))


def absorb(agg, res):
    for key in ("commits", "fix", "multi", "wide", "novel_num", "novel_den", "ctrl", "ctrl_multi"):
        agg[key] += res[key]
    for key in ("files", "dirs", "ctrl_files"):
        agg[key].extend(res[key])


BUCKET_EDGES = (1, 2, 3, 10)      # "1 / 2 / 3 / 4-10 / 11+"; anything above the last edge is the tail


def bucket_of(count):
    for idx, edge in enumerate(BUCKET_EDGES):
        if count <= edge:
            return idx
    return len(BUCKET_EDGES)


def report(agg):
    print(row("POOLED", agg))
    print("CONTROL(non-fix)\t%d\t%d\t%.1f\t-\t%.1f\t-\t-"
          % (agg["commits"], agg["ctrl"], pct(agg["ctrl_multi"], agg["ctrl"]),
             median(agg["ctrl_files"])))
    buckets = [0] * (len(BUCKET_EDGES) + 1)
    for count in agg["files"]:
        buckets[bucket_of(count)] += 1
    total = sum(buckets) or 1
    print("# fix-commit file-count distribution (1 / 2 / 3 / 4-10 / 11+): "
          + " / ".join("%d (%.1f%%)" % (b, 100.0 * b / total) for b in buckets))
    multi_dirs = sum(1 for d in agg["dirs"] if d > 1)
    print("# fix commits touching more than one top-level directory: %d of %d (%.1f%%)"
          % (multi_dirs, len(agg["dirs"]), pct(multi_dirs, len(agg["dirs"]))))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--corpus")
    ap.add_argument("--repos", type=int, default=0)
    ap.add_argument("--commits", type=int, default=4000)
    args = ap.parse_args()

    print(HEADER)
    agg = blank_tally()
    for label, path in resolve_roots(args.root, args.corpus, args.repos, require_git=True):
        try:
            res = analyse(path, args.commits)
        except Exception as exc:                     # noqa: BLE001 - a repo that will not log is skipped, not fatal
            print("%s\tERROR\t%s" % (label, exc), file=sys.stderr)
            continue
        if res["fix"]:
            print(row(label, res))
            absorb(agg, res)
    report(agg)


if __name__ == "__main__":
    main()
