#!/usr/bin/env python3
r"""readability_declared_pairs.py — proxy (c) and the §3a decomposition of
docs/research/readability-construct-validity.md.

Proxy (c): commits whose message DECLARES a readability improvement (the Fakhoury ICPC'19 style of ground
truth), scored with exactly §3a's pairing and z comparison (bench/readability_refactor_pairs.py is imported,
not copied, so the two proxies cannot drift apart). The selection rule below was fixed in the paired
document's §3c before this script existed; do not edit it without also saying so there.

Decomposition: re-runs §3a's own selection and splits every pair's delta-z into its three exact terms —
Halstead volume, token entropy, lines — naming the most negative one as the driver of a wrong-direction pair.

No LLM judgment anywhere: labels come from commit messages, directions from the shipped binary.

A measurement harness is a LEDGER, never a red CI gate (bench/ANSWERQUALITY.md): exits 0 whatever it finds.

Usage:
    bench/readability_declared_pairs.py --bin build/ripwire                 # proxy (c), both arms
    bench/readability_declared_pairs.py --bin build/ripwire --decompose     # §3a decomposition
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import readability_refactor_pairs as rp  # noqa: E402

# Fixed in §3c's protocol, before any result was computed.
DECLARED_RE = re.compile(r"readab|legib|clarity|clarif|clearer|easier to (read|follow|understand)|self-documenting", re.IGNORECASE)
LENS_NAME_MASK = re.compile(r"--readability|readability\.h|readability_|\(readability\)|\(readability,|readability\)", re.IGNORECASE)


def declares_readability(text: str) -> bool:
    return DECLARED_RE.search(LENS_NAME_MASK.sub(" ", text)) is not None


def changed_lines(sha: str) -> int:
    stat = rp.git("show", "--shortstat", "--format=", sha)
    return sum(int(tok) for tok in re.findall(r"(\d+) (?:insertion|deletion)s?\(\+?-?\)?", stat))


def declared_commits(max_changed_lines: int, use_body: bool, ref: str = rp.DEFAULT_REF) -> list[tuple[str, str]]:
    raw = rp.git("log", "--format=%H\x1f%s\x1f%b\x1e", ref, "--", "src/*.h", "src/*.hpp", "src/*.cpp", "src/*.cc")
    out: list[tuple[str, str]] = []
    for rec in raw.split("\x1e"):
        rec = rec.strip("\n")
        if not rec.strip():
            continue
        sha, _, rest = rec.partition("\x1f")
        subject, _, body = rest.partition("\x1f")
        if rp.REFACTOR_RE.search(subject):
            continue   # disjoint from §3a by construction
        if not declares_readability(subject + ("\n" + body if use_body else "")):
            continue
        n = changed_lines(sha)
        if n == 0 or n > max_changed_lines:
            continue
        out.append((sha, subject))
    return out


def pairs_for(binary: str, commits: list[tuple[str, str]], scratch: Path) -> list[rp.FnPair]:
    pairs: list[rp.FnPair] = []
    for sha, subject in commits:
        for path in rp.touched_source_files(sha):
            before_text = rp.show_file(f"{sha}^", path)
            after_text = rp.show_file(sha, path)
            if before_text is None or after_text is None:
                continue
            basename = Path(path).name
            try:
                before_rows = rp.score_file(binary, scratch / "before", basename, before_text)
                after_rows = rp.score_file(binary, scratch / "after", basename, after_text)
            except RuntimeError as exc:
                print(f"# skip {sha[:10]} {path}: {exc}", file=sys.stderr)
                continue
            for name, (lb, tb, volb, entb, pb) in before_rows.items():
                if name not in after_rows:
                    continue
                la, ta, vola, enta, pa = after_rows[name]
                if (lb, tb) == (la, ta):
                    continue
                pairs.append(rp.FnPair(sha, subject, path, name, lb, la, tb, ta, volb, vola, entb, enta, pb, pa))
    return pairs


def report_direction(label: str, commits: list[tuple[str, str]], pairs: list[rp.FnPair]) -> None:
    s = rp.summarize(pairs)
    directional = s["improved"] + s["worsened"]
    by_commit: dict[str, list[rp.FnPair]] = {}
    for p in pairs:
        by_commit.setdefault(p.sha, []).append(p)
    right = sum(1 for ps in by_commit.values() if sum(p.improved for p in ps) > sum(p.worsened for p in ps))
    wrong = sum(1 for ps in by_commit.values() if sum(p.improved for p in ps) < sum(p.worsened for p in ps))
    deltas = sorted(p.delta for p in pairs)
    median = deltas[len(deltas) // 2] if deltas else float("nan")
    print(f"== {label}")
    print(f"selected commits                     : {len(commits)} ({len(by_commit)} contributed >=1 pair)")
    print(f"directional pairs                    : {directional} (improved {s['improved']}, worsened {s['worsened']}, tied {s['tied_within_1e-9']})")
    frac = s["frac_improved_of_directional"]
    print(f"fraction AFTER ranked more readable  : {frac:.3f}" if frac == frac else "fraction: n/a")
    print(f"per-commit majority right/wrong/split: {right}/{wrong}/{len(by_commit) - right - wrong}")
    print(f"mean / median delta-z                : {s['mean_z_delta']:.3f} / {median:.3f}")
    for sha, subject in commits:
        ps = by_commit.get(sha, [])
        print(f"   {sha[:10]} +{sum(p.improved for p in ps)} -{sum(p.worsened for p in ps)}  {subject}")


TERMS = ("volume", "entropy", "lines")


def contributions(p: rp.FnPair) -> dict[str, float]:
    return {
        "volume": rp.POSNETT_VOLUME * (p.vol_after - p.vol_before),
        "entropy": rp.POSNETT_ENTROPY * (p.ent_after - p.ent_before),
        "lines": rp.POSNETT_LINES * (p.lines_after - p.lines_before),
    }


def report_decomposition(pairs: list[rp.FnPair]) -> None:
    for label, subset, pick in (("wrong-direction (delta-z < 0)", [p for p in pairs if p.worsened], min),
                                ("right-direction (delta-z > 0)", [p for p in pairs if p.improved], max)):
        print(f"== {label}: {len(subset)} pairs")
        if not subset:
            continue
        drivers = {t: 0 for t in TERMS}
        sums = {t: 0.0 for t in TERMS}
        for p in subset:
            c = contributions(p)
            drivers[pick(TERMS, key=lambda t: c[t])] += 1
            for t in TERMS:
                sums[t] += c[t]
        for t in TERMS:
            print(f"   driver={t:<8}: {drivers[t]:>4} ({drivers[t] / len(subset):.1%})   mean contribution {sums[t] / len(subset):+.3f}")
        longer = sum(1 for p in subset if p.lines_after > p.lines_before)
        shorter = sum(1 for p in subset if p.lines_after < p.lines_before)
        more_toks = sum(1 for p in subset if p.toks_after > p.toks_before)
        print(f"   got longer (dL>0): {longer}   shorter: {shorter}   same length: {len(subset) - longer - shorter}   more tokens: {more_toks}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bin", default=rp.DEFAULT_BIN)
    ap.add_argument("--max-changed-lines", type=int, default=400)
    ap.add_argument("--decompose", action="store_true", help="decompose §3a's pairs instead of running proxy (c)")
    ap.add_argument("--max-commits", type=int, default=80, help="§3a's commit cap, used only with --decompose")
    ap.add_argument("--ref", default=rp.DEFAULT_REF,
                     help=f"walk history from exactly this ref (default {rp.DEFAULT_REF!r}) — never --all")
    ap.add_argument("--until", default=None, help="only commits committed at or before this date (git log --until); pins §3a's "
                                                  "newest-80 window against refs added later")
    args = ap.parse_args()
    if not Path(args.bin).is_file():
        print(f"error: ripwire binary not found at {args.bin}", file=sys.stderr)
        return 2
    if args.until:
        plain_git = rp.git
        rp.git = lambda *a: plain_git(*a[:1], f"--until={args.until}", *a[1:]) if a and a[0] == "log" else plain_git(*a)
    scratch = Path(tempfile.mkdtemp(prefix="rw_declpairs_"))
    try:
        if args.decompose:
            pairs = rp.collect_pairs(args.bin, args.max_commits, args.max_changed_lines, scratch, args.ref)
            s = rp.summarize(pairs)
            print(f"§3a regenerated: {s['pairs']} pairs, improved {s['improved']}, worsened {s['worsened']}, tied {s['tied_within_1e-9']}")
            report_decomposition(pairs)
        else:
            for label, use_body in (("PRIMARY arm (subject line)", False), ("SECONDARY arm (subject + body, descriptive only)", True)):
                commits = declared_commits(args.max_changed_lines, use_body, args.ref)
                pairs = pairs_for(args.bin, commits, scratch)
                report_direction(label, commits, pairs)
                if not use_body:
                    report_decomposition(pairs)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
