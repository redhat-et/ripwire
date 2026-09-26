#!/usr/bin/env python3
r"""readability_refactor_pairs.py — proxy (a) of docs/research/readability-construct-validity.md: without
any human label, does `--readability`'s Posnett rank move the direction a refactor/simplify/cleanup commit
message says it should?

For each commit in this repo's history whose subject matches /refactor|simplify|clean(\s|-)?up/i and that
touches a bounded number of C/C++ source lines, this script extracts each touched .h/.cpp file at the
commit and at its parent, scores every function in each version with the real `--readability` lens (via a
single-file scratch directory, so the lens's own tokenizer and Posnett fit run unmodified), and matches
functions by (file basename, name) that are present in both versions with a DIFFERENT token shape (a
same-shape match means the diff did not touch that specific function's body and is not evidence either
way). It reports what fraction of genuinely-changed functions the lens ranks MORE readable after a commit
whose author called it a refactor — a cheap, label-free stand-in for "does the ranking move the direction a
human editor intended."

This is a proxy, not ground truth: a commit message is not a readability judgement, and "refactor" commits
sometimes trade readability for something else (performance, a new abstraction boundary) the author valued
more. Read the numbers this way, and see the "what we would like help with" section of the paired doc.

House rule this script exists under (bench/ANSWERQUALITY.md, bench/BENCHMARK.md): a measurement harness is
a LEDGER, never a red CI gate. It reports numbers and exits 0 regardless of what they say; it is not wired
into test/regression.sh.

Usage:
    bench/readability_refactor_pairs.py                       # default: this repo, 60 commits, src/
    bench/readability_refactor_pairs.py --max-commits 150 --out /tmp/pairs.tsv
    RIPWIRE_BIN=asan/ripwire bench/readability_refactor_pairs.py --json > pairs.json

Deterministic given a fixed git history and a fixed binary: git log ordering is chronological, the lens
itself is deterministic (docs/ARCHITECTURE.md), and this script does not thread.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BIN = os.environ.get("RIPWIRE_BIN", str(ROOT / "build" / "ripwire"))

# The population must be pinned to ONE immutable ref, never `--all`: this clone's shared .git carries every
# worktree's branches, so `--all` makes the candidate-commit population — and therefore the published
# fraction — move whenever any unrelated lane is pushed. That is an instrument defect, not a measurement
# (docs/research/readability-construct-validity.md §3a). v0.6.2 is the tag the shipped scoring binary was
# built from; override with --ref for a different pinned population, but never pass --all here.
DEFAULT_REF = "v0.6.2"

REFACTOR_RE = re.compile(r"refactor|simplify|clean(\s|-)?up", re.IGNORECASE)
SOURCE_EXT = {".h", ".hpp", ".cc", ".cpp", ".cxx"}

# The Posnett coefficients, copied verbatim from src/readability.h (kPosnettIntercept/Volume/Lines/Entropy)
# so this script can recompute the pre-sigmoid z on FULL precision instead of comparing the CLI's own
# 3-decimal, sigmoid-saturating `posnett=` attribute. z is monotonic in posnett (sigmoid is monotonic), so
# ranking by z ranks identically to ranking by posnett, without the display truncation or the saturation
# that makes several distinct functions all print posnett="0.000" (readability.h's own legend text says
# so). toks= and vocab= are exact integers in the XML, so vol = toks*log2(vocab) is recovered EXACTLY —
# only ent= (2 decimals as printed) stays at display precision, since the per-token frequency table itself
# is not exposed by the verb.
POSNETT_INTERCEPT = 8.87
POSNETT_VOLUME = -0.033
POSNETT_LINES = 0.40
POSNETT_ENTROPY = -1.5


def z_score(vol: float, lines: int, ent: float) -> float:
    return POSNETT_INTERCEPT + POSNETT_VOLUME * vol + POSNETT_LINES * lines + POSNETT_ENTROPY * ent


@dataclass
class FnPair:
    sha: str
    subject: str
    path: str
    name: str
    lines_before: int
    lines_after: int
    toks_before: int
    toks_after: int
    vol_before: float
    vol_after: float
    ent_before: float
    ent_after: float
    posnett_before: float   # the CLI's own displayed value — kept for reference, not for comparison
    posnett_after: float

    @property
    def z_before(self) -> float:
        return z_score(self.vol_before, self.lines_before, self.ent_before)

    @property
    def z_after(self) -> float:
        return z_score(self.vol_after, self.lines_after, self.ent_after)

    @property
    def delta(self) -> float:
        return self.z_after - self.z_before

    @property
    def improved(self) -> bool:
        return self.z_after > self.z_before + 1e-9

    @property
    def worsened(self) -> bool:
        return self.z_after < self.z_before - 1e-9


def git(*args: str) -> str:
    proc = subprocess.run(["git", *args], cwd=str(ROOT), capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout


def candidate_commits(max_commits: int, max_changed_lines: int, ref: str = DEFAULT_REF) -> list[tuple[str, str]]:
    """(sha, subject) pairs, newest first, whose subject reads as a refactor/simplify/cleanup and whose
    total changed-line count over the whole commit is small enough that attributing a per-function score
    delta to "the refactor" is defensible rather than noise from an unrelated bulk edit riding along.

    Walks exactly ONE immutable ref (default the v0.6.2 tag), never `--all`: see DEFAULT_REF's comment."""
    raw = git(
        "log", "--format=%H\x1f%s", ref, "-i",
        "--grep=refactor", "--grep=simplify", "--grep=clean up", "--grep=cleanup",
        "--", "src/*.h", "src/*.hpp", "src/*.cpp", "src/*.cc",
    )
    out: list[tuple[str, str]] = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        sha, _, subject = line.partition("\x1f")
        if not REFACTOR_RE.search(subject):
            continue
        stat = git("show", "--shortstat", "--format=", sha)
        m = re.search(r"(\d+) insertion.*?(\d+) deletion|(\d+) insertion|(\d+) deletion", stat)
        changed = 0
        for tok in re.findall(r"(\d+) (?:insertion|deletion)s?\(\+?-?\)?", stat):
            changed += int(tok)
        if changed == 0 or changed > max_changed_lines:
            continue
        out.append((sha, subject))
        if len(out) >= max_commits:
            break
    return out


def touched_source_files(sha: str) -> list[str]:
    raw = git("show", "--name-only", "--format=", sha)
    return [p for p in raw.splitlines() if p and Path(p).suffix in SOURCE_EXT and p.startswith("src/")]


def show_file(rev: str, path: str) -> Optional[str]:
    proc = subprocess.run(["git", "show", f"{rev}:{path}"], cwd=str(ROOT), capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    return proc.stdout


def score_file(binary: str, scratch_dir: Path, basename: str, text: str) -> dict[str, tuple]:
    """Write `text` as the sole file in an otherwise-empty directory, run --readability over it, and
    return {function_name: (lines, toks, vol_exact, ent, posnett)}. A single-file directory is enough —
    the lens is per-function and needs no cross-file resolution (readability.h's own header note)."""
    if scratch_dir.exists():
        shutil.rmtree(scratch_dir)
    scratch_dir.mkdir(parents=True)
    (scratch_dir / basename).write_text(text, encoding="utf-8", errors="surrogateescape")
    proc = subprocess.run(
        [binary, str(scratch_dir), "--readability", "--limit=100000"],
        capture_output=True, text=True, timeout=60,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"--readability exited {proc.returncode} on {scratch_dir}: {proc.stderr.strip()}")
    root = ET.fromstring(proc.stdout)
    rows: dict[str, tuple] = {}
    for fn in root.findall("fn"):
        name = fn.get("n")
        # Same-named overload/specialization collisions are rare in one file; keep the first, since a
        # scratch single-file rescoring only needs A representative match, not perfect overload resolution.
        if name not in rows:
            toks = int(fn.get("toks"))
            vocab = int(fn.get("vocab"))
            vol_exact = toks * math.log2(vocab) if vocab > 0 else 0.0   # readability.h's own formula, integer inputs
            rows[name] = (int(fn.get("lines")), toks, vol_exact, float(fn.get("ent")), float(fn.get("posnett")))
    return rows


def collect_pairs(binary: str, max_commits: int, max_changed_lines: int, scratch: Path, ref: str = DEFAULT_REF) -> list[FnPair]:
    pairs: list[FnPair] = []
    commits = candidate_commits(max_commits, max_changed_lines, ref)
    print(f"# {len(commits)} candidate refactor/simplify/cleanup commits (max_changed_lines={max_changed_lines}, ref={ref})", file=sys.stderr)
    before_dir = scratch / "before"
    after_dir = scratch / "after"
    for sha, subject in commits:
        for path in touched_source_files(sha):
            before_text = show_file(f"{sha}^", path)
            after_text = show_file(sha, path)
            if before_text is None or after_text is None:
                continue   # file added or deleted in this commit — no pair to compare
            basename = Path(path).name
            try:
                before_rows = score_file(binary, before_dir, basename, before_text)
                after_rows = score_file(binary, after_dir, basename, after_text)
            except RuntimeError as exc:
                print(f"# skip {sha[:10]} {path}: {exc}", file=sys.stderr)
                continue
            for name, (lb, tb, volb, entb, pb) in before_rows.items():
                if name not in after_rows:
                    continue
                la, ta, vola, enta, pa = after_rows[name]
                if (lb, tb) == (la, ta):
                    continue   # identical shape — this function's body was not touched by the diff
                pairs.append(FnPair(sha, subject, path, name, lb, la, tb, ta, volb, vola, entb, enta, pb, pa))
    return pairs


def summarize(pairs: list[FnPair]) -> dict:
    improved = sum(1 for p in pairs if p.improved)
    worsened = sum(1 for p in pairs if p.worsened)
    tied = len(pairs) - improved - worsened
    n_directional = improved + worsened
    frac_improved = improved / n_directional if n_directional else float("nan")
    mean_delta = sum(p.delta for p in pairs) / len(pairs) if pairs else float("nan")
    return {
        "pairs": len(pairs),
        "improved": improved,
        "worsened": worsened,
        "tied_within_1e-9": tied,
        "frac_improved_of_directional": frac_improved,
        "mean_z_delta": mean_delta,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bin", default=DEFAULT_BIN)
    ap.add_argument("--max-commits", type=int, default=60)
    ap.add_argument("--max-changed-lines", type=int, default=400,
                     help="skip commits whose total insertion+deletion count exceeds this (default 400) — "
                          "keeps the compared functions attributable to the named refactor")
    ap.add_argument("--ref", default=DEFAULT_REF,
                     help=f"walk history from exactly this ref (default {DEFAULT_REF!r}) — never --all, "
                          "which makes the population move whenever any unrelated branch is pushed to a "
                          "shared .git")
    ap.add_argument("--out", default=None, help="write the per-pair TSV here (default: stdout table only)")
    ap.add_argument("--json", action="store_true", help="print the summary as JSON instead of a table")
    ap.add_argument("--scratch", default=None, help="scratch directory (default: a fresh temp dir)")
    args = ap.parse_args()

    if not Path(args.bin).is_file():
        print(f"error: ripwire binary not found at {args.bin} — build it first (see CLAUDE.md)", file=sys.stderr)
        return 2

    scratch = Path(args.scratch) if args.scratch else Path(tempfile.mkdtemp(prefix="rw_readpairs_"))
    try:
        pairs = collect_pairs(args.bin, args.max_commits, args.max_changed_lines, scratch, args.ref)
    finally:
        if not args.scratch:
            shutil.rmtree(scratch, ignore_errors=True)

    summary = summarize(pairs)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write("sha\tsubject\tpath\tname\tz_before\tz_after\tz_delta\tposnett_before\tposnett_after\tlines_before\tlines_after\ttoks_before\ttoks_after\n")
            for p in pairs:
                f.write(f"{p.sha}\t{p.subject}\t{p.path}\t{p.name}\t{p.z_before:.6f}\t{p.z_after:.6f}\t{p.delta:.6f}\t{p.posnett_before:.3f}\t{p.posnett_after:.3f}\t{p.lines_before}\t{p.lines_after}\t{p.toks_before}\t{p.toks_after}\n")
        print(f"# wrote {len(pairs)} pairs to {args.out}", file=sys.stderr)

    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print(f"pairs (changed-function before/after)        : {summary['pairs']}")
        print(f"lens ranks AFTER more readable (z increased)  : {summary['improved']}")
        print(f"lens ranks AFTER less readable (z decreased)  : {summary['worsened']}")
        print(f"exact tie (z unchanged, to 1e-9)               : {summary['tied_within_1e-9']}")
        frac = summary["frac_improved_of_directional"]
        print(f"fraction improved, of the directional pairs   : {frac:.3f}" if frac == frac else "fraction improved: n/a (no directional pairs)")
        print(f"mean z delta (after - before; +delta=more readable) : {summary['mean_z_delta']:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
