#!/usr/bin/env python3
r"""readability_fixrate_validity.py — does `--readability`'s ordering predict anything worth acting on?

§2 and §3 of docs/research/readability-construct-validity.md validate the ORDER against refactor-commit
direction and self-consistency. Neither asks the question an agent actually relies on when it uses the lens
to pick a refactor target: **does a low readability score predict that a function will need fixing later?**
This script answers that, with no human label and no LLM judge, against the shipped `--readability` lens and
a complexity control the repo's own `--quality-delta` "complexity" kind already trusts (cognitive complexity,
`ccx=`), on the SAME population, with and without controlling for function size.

Protocol (fixed in this file before any number below existed; see the paired document's new section for the
narrative write-up):

  1. POPULATION: every `fn`/`method` in `src/**/*.{h,hpp,cpp,cc}` at a pinned CUTOFF commit on `v0.6.2`'s
     history (never `--all` — see the instrument-fix note in the paired doc's §3c). The cutoff is chosen to
     leave a multi-week, thousand-plus-commit follow-up window to the pinned UNTIL ref (default `v0.6.2`)
     so the outcome (see below) has room to happen. Population functions are matched between a real
     `--readability` crawl and a real `--metrics` crawl of the SAME extracted tree (`git archive`, not
     per-file scratch, so cross-file structure is intact for `--metrics`'s in/out/ccx) by
     (path relative to root, function name), with `loc`(metrics) == `lines`(readability) required as a
     sanity check; an ambiguous match (same path+name, disagreeing loc, e.g. two overloads) is dropped and
     counted, not guessed at.

  2. EXPOSURE, per function, read at the cutoff: `z` (the exact pre-sigmoid Posnett score, recomputed from
     integer `toks=`/`vocab=` exactly as bench/readability_refactor_pairs.py does — lower z = less readable)
     and `ccx` (cognitive complexity from `--metrics`, the same metric `src/quality.h`'s "complexity" gate
     kind reads — higher ccx = more complex).

  3. OUTCOME, defined before looking, over the window (CUTOFF, UNTIL]:
       - "fix-shaped" commit: subject line (not body — §3c already found body-matching noisy) matches, case
         insensitively, `\bfix(e[sd])?\b|\bbug(s|fix(e[sd])?)?\b|\bcrash(e[sd])?\b|\bregression(s)?\b`.
       - a function counts as FIXED if any fix-shaped commit in the window has a diff hunk (old-file line
         numbers, i.e. against that commit's OWN parent, not the cutoff) that overlaps the function's span
         AS MEASURED AT THAT PARENT REVISION (re-scored per commit, so line drift from earlier window
         commits cannot misattribute a hunk) — matched back to the population by (basename, function name).
         A pure-insertion hunk (old count 0) is treated as touching whichever function(s) contain old-line
         `start` or `start+1` (the two lines the insertion sits between).
       - a function counts as MODIFIED (the broader arm) under the identical rule, over ALL commits that
         touch a src file in the window, fix-shaped or not. Every fix-shaped commit is also a modifying
         commit, so both arms are computed in one pass over the window's commits.

  4. STATISTIC: fix-rate (and modified-rate) in the least-readable quartile (bottom 25% by z) vs the rest,
     Wilson-interval per proportion, risk ratio with a Katz log-CI — reported beside the identical statistic
     for the highest-ccx quartile vs the rest, on the SAME population, as the trusted-signal baseline.
     Repeated within three size terciles TWICE: once by `lines`-at-cutoff, once by `toks`-at-cutoff (Halstead
     N, --readability's own toks= — the size measure the lens actually consumes for its volume term, not a
     proxy for it), with the least-readable/highest-ccx quartile recomputed WITHIN each tercile. The first
     round of this script (see the paired doc's §4) stratified by lines only; a lines-based stratification
     does not hold the confound constant, because z tracks the SIGN of the token-count change on 96.0% of
     this repo's own refactor pairs (§3c), not the line-count change — a function can gain tokens with no
     line change at all. The token-stratified arm is the decisive one for the size-confound question; the
     line-stratified arm is kept alongside it because the two disagreeing would itself be informative.

  5. DECISION BANDS (restated from the paired doc's own pre-registration): the least-readable quartile's
     raw fix-rate CI excludes a risk ratio of 1 and the effect does not vanish once stratified by size ->
     keep the ordering claim as a weak actionable signal; effect present raw but gone within every size
     tercile -> the size confound explains it, disclose and narrow the claim; CI includes 1 raw -> withdraw
     the "predicts later fixes" claim outright. The complexity arm is reported for comparison, not as a bar
     the lens must clear.

House rule this script exists under (bench/ANSWERQUALITY.md, bench/BENCHMARK.md): a measurement harness is a
LEDGER, never a red CI gate. It reports numbers and exits 0 regardless of what they say; it is not wired into
test/regression.sh.

POST-HOC ADDITION (labelled as such, not pre-registered — prompted after seeing the tercile-stratified
result disagree with the line-stratified one): terciles are wide enough that neither one holds the lens's
own size unit (toks) constant within a band, so the script also reports (a) DECILES by toks — ten narrower
bands, to see whether the effect shrinks toward RR=1 as the band narrows, which is what a residual-size
effect would do and a genuine per-token-count-controlled readability effect would not — beside each
decile's own internal token range, since "does RR track the range" is the actual question; and (b) a
nearest-token-neighbour matched control: each least-readable-quartile function against its closest-toks
match from the rest of the population, one-to-one, rather than against a whole band.

Usage:
    bench/readability_fixrate_validity.py --bin build/ripwire
    bench/readability_fixrate_validity.py --bin build/ripwire --out pop_outcomes.tsv --json
    bench/readability_fixrate_validity.py --load-tsv pop_outcomes.tsv   # re-stratify already-computed data

Deterministic given a fixed git history (pinned CUTOFF/UNTIL refs) and a fixed binary: no randomness anywhere.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import json
import math
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import readability_refactor_pairs as rp  # noqa: E402  (reuses git(), z_score(), DEFAULT_BIN)

# Chosen to leave a multi-week, thousand-plus-commit follow-up window to v0.6.2 (2286 commits / ~17 days at
# the time this was pinned) — far enough back that a fix-shaped commit in the window cannot be an artifact of
# the cutoff being too recent, close enough that the population is still recognizably today's codebase.
DEFAULT_CUTOFF = "4f5c310c767f6f291c1db2e997b081f35b9a675d"
DEFAULT_UNTIL = "v0.6.2"

FIX_RE = re.compile(r"\bfix(e[sd])?\b|\bbug(s|fix(e[sd])?)?\b|\bcrash(e[sd])?\b|\bregression(s)?\b", re.IGNORECASE)
HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


@dataclass
class FnRow:
    path: str          # relative to the population root (src/...)
    name: str
    start_line: int
    lines: int
    toks: int          # Halstead N (operator+operand count) — --readability's own toks=, the exact
                        # integer z's volume term is computed from; the size measure the lens actually
                        # consumes, not a proxy for it.
    z: float
    ccx: int
    fixed: bool = False
    modified: bool = False

    @property
    def basename(self) -> str:
        return Path(self.path).name

    @property
    def end_line(self) -> int:
        return self.start_line + self.lines - 1


def run_xml(binary: str, root: Path, *flags: str) -> ET.Element:
    proc = subprocess.run([binary, str(root), *flags], capture_output=True, text=True, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError(f"{binary} {' '.join(flags)} on {root} exited {proc.returncode}: {proc.stderr.strip()}")
    out = proc.stdout
    start = out.index("<")
    # skip the leading XML comment (legend) to reach the real root element
    while out[start:start + 4] == "<!--":
        start = out.index("-->", start) + 3
        start = out.index("<", start)
    return ET.fromstring(out[start:])


def crawl_population(binary: str, src_root: Path) -> dict[tuple[str, str], FnRow]:
    """Real crawl of the extracted src/ tree at the cutoff: match --readability rows to --metrics rows by
    (path, name), requiring loc==lines to accept the match. Returns {(path, name): FnRow}."""
    read_root = run_xml(binary, src_root, "--readability", "--limit=100000")
    met_root = run_xml(binary, src_root, "--metrics", "--top-k=100000")

    readab: dict[tuple[str, str], list[tuple[int, int, int, float]]] = {}  # (path,name) -> [(start,lines,toks,z)]
    for fn in read_root.findall("fn"):
        p = fn.get("p")
        path, _, lineno = p.rpartition(":")
        toks, vocab = int(fn.get("toks")), int(fn.get("vocab"))
        vol_exact = toks * math.log2(vocab) if vocab > 0 else 0.0
        z = rp.z_score(vol_exact, int(fn.get("lines")), float(fn.get("ent")))
        readab.setdefault((path, fn.get("n")), []).append((int(lineno), int(fn.get("lines")), toks, z))

    metrics: dict[tuple[str, str], list[int]] = {}  # (path,name) -> [loc, loc, ...]  (one per sc match)
    metrics_ccx: dict[tuple[str, str, int], int] = {}
    for f in met_root.findall("f"):
        path = f.get("p")
        for s in f.findall("s"):
            if s.get("t") not in ("fn", "method"):
                continue
            loc = int(s.get("loc"))
            key = (path, s.get("n"))
            metrics.setdefault(key, []).append(loc)
            metrics_ccx[(path, s.get("n"), loc)] = int(s.get("ccx"))

    pop: dict[tuple[str, str], FnRow] = {}
    ambiguous = 0
    for key, entries in readab.items():
        locs = metrics.get(key)
        if not locs:
            continue
        for start, lines, toks, z in entries:
            if lines not in locs:
                continue
            ccx = metrics_ccx.get((key[0], key[1], lines))
            if ccx is None:
                continue
            if key in pop:
                ambiguous += 1
                continue
            pop[key] = FnRow(path=key[0], name=key[1], start_line=start, lines=lines, toks=toks, z=z, ccx=ccx)
    print(f"# population: {len(pop)} matched functions ({ambiguous} ambiguous matches dropped)", file=sys.stderr)
    return pop


def window_commits(until: str, cutoff: str) -> list[str]:
    raw = rp.git("log", "--format=%H", f"{cutoff}..{until}", "--",
                  "src/*.h", "src/*.hpp", "src/*.cpp", "src/*.cc")
    return [ln for ln in raw.splitlines() if ln.strip()]


def parse_hunks(diff_text: str) -> list[tuple[int, int]]:
    """[(old_start, old_end_inclusive)] for each hunk; a pure insertion (old count 0) becomes a
    zero-width marker (start, start+1) so it can match a function containing either boundary line."""
    out = []
    for line in diff_text.splitlines():
        m = HUNK_RE.match(line)
        if not m:
            continue
        old_start = int(m.group(1))
        old_count = int(m.group(2)) if m.group(2) is not None else 1
        if old_count == 0:
            out.append((max(old_start, 1), max(old_start, 1) + 1))
        else:
            out.append((old_start, old_start + old_count - 1))
    return out


def touched_functions_at_parent(binary: str, scratch: Path, sha: str, path: str) -> list[tuple[str, int, int]]:
    """[(name, start, end)] for every function in `path` as it existed at sha^ (the state the diff's old
    line numbers are relative to). Runs --readability directly (not rp.score_file) because that helper
    drops the start line, which this function needs."""
    text = rp.show_file(f"{sha}^", path)
    if text is None:
        return []
    scratch_dir = scratch
    if scratch_dir.exists():
        shutil.rmtree(scratch_dir)
    scratch_dir.mkdir(parents=True)
    (scratch_dir / Path(path).name).write_text(text, encoding="utf-8", errors="surrogateescape")
    root = run_xml(binary, scratch_dir, "--readability", "--limit=100000")
    out = []
    for fn in root.findall("fn"):
        p = fn.get("p")
        _, _, lineno = p.rpartition(":")
        start = int(lineno)
        lines = int(fn.get("lines"))
        out.append((fn.get("n"), start, start + lines - 1))
    return out


def mark_outcomes(binary: str, pop: dict[tuple[str, str], FnRow], commits: list[str], scratch: Path) -> dict:
    """One pass over every window commit that touches a src file: for each touched file, resolve the
    function spans at that commit's PARENT, intersect against the diff's old-line hunks, and mark any
    matching population function (by basename+name) as modified / (if the commit is fix-shaped) fixed."""
    by_basename_name: dict[tuple[str, str], list[FnRow]] = {}
    for row in pop.values():
        by_basename_name.setdefault((row.basename, row.name), []).append(row)

    n_fix_commits = 0
    n_touch_commits = 0
    for sha in commits:
        subject = rp.git("log", "-1", "--format=%s", sha).strip()
        is_fix = bool(FIX_RE.search(subject))
        files = rp.touched_source_files(sha)
        if not files:
            continue
        n_touch_commits += 1
        if is_fix:
            n_fix_commits += 1
        for path in files:
            diff = rp.git("diff", "-U0", f"{sha}^", sha, "--", path)
            hunks = parse_hunks(diff)
            if not hunks:
                continue
            spans = touched_functions_at_parent(binary, scratch, sha, path)
            if not spans:
                continue
            basename = Path(path).name
            for name, start, end in spans:
                key = (basename, name)
                rows = by_basename_name.get(key)
                if not rows:
                    continue
                touched = any(not (end < hs or start > he) for hs, he in hunks)
                if not touched:
                    continue
                for row in rows:
                    row.modified = True
                    if is_fix:
                        row.fixed = True
    return {"fix_commits": n_fix_commits, "touch_commits": n_touch_commits, "window_total": len(commits)}


# ---------- statistics (stdlib only) ----------

def wilson_interval(k: int, n: int, z: float = 1.959963985) -> tuple[float, float, float]:
    if n == 0:
        return (float("nan"),) * 3
    p = k / n
    denom = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denom
    half = (z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / denom
    return p, max(0.0, center - half), min(1.0, center + half)


def risk_ratio_ci(k1: int, n1: int, k0: int, n0: int, z: float = 1.959963985) -> tuple[float, float, float]:
    """Katz log-method CI for the risk ratio (group-1 rate / group-0 rate). NaNs out on a zero cell —
    disclosed as such by the caller, never silently substituted."""
    if n1 == 0 or n0 == 0 or k1 == 0 or k0 == 0:
        return (float("nan"),) * 3
    p1, p0 = k1 / n1, k0 / n0
    rr = p1 / p0
    se = math.sqrt((1 - p1) / (k1) + (1 - p0) / (k0)) if k1 and k0 else float("nan")
    lo = rr * math.exp(-z * se)
    hi = rr * math.exp(z * se)
    return rr, lo, hi


def rate_block(flags: list[bool]) -> tuple[int, int, float]:
    k = sum(1 for f in flags if f)
    n = len(flags)
    return k, n, (k / n if n else float("nan"))


def quartile_split(rows: list[FnRow], key) -> tuple[list[FnRow], list[FnRow]]:
    """Bottom-quartile-by-key vs the rest. `key(row)` ascending; bottom 25% = worst by the study's own
    convention (least readable = lowest z; most complex = HIGHEST ccx, so callers pass a negated key)."""
    if not rows:
        return [], []
    ordered = sorted(rows, key=key)
    cut = max(1, round(len(ordered) * 0.25))
    return ordered[:cut], ordered[cut:]


def report_arm(label: str, worst: list[FnRow], rest: list[FnRow], outcome: str) -> dict:
    wk, wn, wr = rate_block([getattr(r, outcome) for r in worst])
    rk, rn, rr_ = rate_block([getattr(r, outcome) for r in rest])
    _, w_lo, w_hi = wilson_interval(wk, wn)
    _, r_lo, r_hi = wilson_interval(rk, rn)
    rr, rr_lo, rr_hi = risk_ratio_ci(wk, wn, rk, rn)
    return {
        "label": label, "outcome": outcome,
        "worst_k": wk, "worst_n": wn, "worst_rate": wr, "worst_ci": (w_lo, w_hi),
        "rest_k": rk, "rest_n": rn, "rest_rate": rr_, "rest_ci": (r_lo, r_hi),
        "risk_ratio": rr, "rr_ci": (rr_lo, rr_hi),
    }


def size_ntiles(rows: list[FnRow], key=lambda r: r.lines, n: int = 3) -> list[list[FnRow]]:
    """N equal-count bands by `key` (default: lines-at-cutoff, 3 = terciles; pass `lambda r: r.toks` for
    the token-count measure the lens itself consumes, and n=10 for deciles — a POST-HOC refinement, see
    the paired doc's third §4 subsection: terciles are wide enough that a tercile does not hold size
    constant on its own, so a real readability effect and a residual-size effect both predict the same
    tercile-level RR pattern; only a narrower band distinguishes them)."""
    ordered = sorted(rows, key=key)
    total = len(ordered)
    bounds = [round(i * total / n) for i in range(n + 1)]
    return [ordered[bounds[i]:bounds[i + 1]] for i in range(n)]


def size_terciles(rows: list[FnRow], key=lambda r: r.lines) -> list[list[FnRow]]:
    return size_ntiles(rows, key=key, n=3)


def nearest_token_match(pop: list[FnRow], quartile: list[FnRow]) -> list[FnRow]:
    """For each function in `quartile`, its nearest neighbour by `toks` among `pop` functions NOT in the
    quartile (ties broken by the earlier one in token-sorted order; matching is WITH replacement — a
    popular token count can supply more than one match, disclosed at the call site). A cheap alternative
    to a fixed-width band: instead of asking "does the effect survive in a band this wide," it asks "does
    it survive against a control matched almost exactly on the lens's own size unit.\""""
    quartile_keys = {id(r) for r in quartile}
    rest_sorted = sorted((r for r in pop if id(r) not in quartile_keys), key=lambda r: r.toks)
    rest_toks = [r.toks for r in rest_sorted]
    matches = []
    for q in quartile:
        i = bisect.bisect_left(rest_toks, q.toks)
        candidates = [j for j in (i - 1, i) if 0 <= j < len(rest_sorted)]
        best = min(candidates, key=lambda j: abs(rest_sorted[j].toks - q.toks))
        matches.append(rest_sorted[best])
    return matches


def fmt_ci(ci: tuple[float, float]) -> str:
    lo, hi = ci
    if lo != lo or hi != hi:
        return "n/a"
    return f"[{lo:.3f}, {hi:.3f}]"


def print_report(pop: list[FnRow], meta: dict) -> None:
    print(f"population: {len(pop)} functions at cutoff; window: {meta['window_total']} commits touching src, "
          f"{meta['touch_commits']} with a matched src diff, {meta['fix_commits']} fix-shaped")
    for outcome in ("fixed", "modified"):
        print(f"\n=== outcome: {outcome} ===")
        worst_z, rest_z = quartile_split(pop, key=lambda r: r.z)
        worst_ccx, rest_ccx = quartile_split(pop, key=lambda r: -r.ccx)
        for arm in (report_arm("readability (least-readable quartile)", worst_z, rest_z, outcome),
                    report_arm("complexity (highest-ccx quartile)", worst_ccx, rest_ccx, outcome)):
            print(f"  {arm['label']}: worst {arm['worst_k']}/{arm['worst_n']} = {arm['worst_rate']:.3f} "
                  f"{fmt_ci(arm['worst_ci'])}  vs rest {arm['rest_k']}/{arm['rest_n']} = {arm['rest_rate']:.3f} "
                  f"{fmt_ci(arm['rest_ci'])}  RR={arm['risk_ratio']:.3f} {fmt_ci(arm['rr_ci'])}")
        for strat_label, strat_key, unit_key, unit_name in (
            ("lines-at-cutoff", (lambda r: r.lines), (lambda r: r.lines), "lines"),
            ("toks-at-cutoff (Halstead N, --readability's own toks=)", (lambda r: r.toks), (lambda r: r.toks), "toks"),
        ):
            print(f"  -- size-stratified (terciles by {strat_label}, quartile recomputed within each) --")
            for i, band in enumerate(size_terciles(pop, key=strat_key), start=1):
                wz, rz = quartile_split(band, key=lambda r: r.z)
                wc, rc = quartile_split(band, key=lambda r: -r.ccx)
                lo_u = min(unit_key(r) for r in band) if band else 0
                hi_u = max(unit_key(r) for r in band) if band else 0
                a = report_arm("readability", wz, rz, outcome)
                b = report_arm("complexity", wc, rc, outcome)
                print(f"    T{i} (n={len(band)}, {unit_name} {lo_u}-{hi_u}):"
                      f" readab RR={a['risk_ratio']:.3f} {fmt_ci(a['rr_ci'])}  |"
                      f" complexity RR={b['risk_ratio']:.3f} {fmt_ci(b['rr_ci'])}")
        print("  -- POST-HOC (prompted by the tercile result, not pre-registered): "
              "DECILES by toks-at-cutoff, quartile recomputed within each decile --")
        for i, band in enumerate(size_ntiles(pop, key=lambda r: r.toks, n=10), start=1):
            wz, rz = quartile_split(band, key=lambda r: r.z)
            a = report_arm("readability", wz, rz, outcome)
            lo_t = min(r.toks for r in band) if band else 0
            hi_t = max(r.toks for r in band) if band else 0
            ratio = (hi_t / lo_t) if lo_t > 0 else float("inf")
            print(f"    D{i:02d} (n={len(band)}, toks {lo_t}-{hi_t}, internal range {ratio:.2f}x):"
                  f" readab RR={a['risk_ratio']:.3f} {fmt_ci(a['rr_ci'])}")
        print("  -- POST-HOC: nearest-token-neighbour matched control "
              "(least-readable quartile vs. its 1-NN-by-toks match from the rest) --")
        worst_z, _rest_z = quartile_split(pop, key=lambda r: r.z)
        matched = nearest_token_match(pop, worst_z)
        wk, wn, wr = rate_block([getattr(r, outcome) for r in worst_z])
        mk, mn, mr = rate_block([getattr(r, outcome) for r in matched])
        _, w_lo, w_hi = wilson_interval(wk, wn)
        _, m_lo, m_hi = wilson_interval(mk, mn)
        rr, rr_lo, rr_hi = risk_ratio_ci(wk, wn, mk, mn)
        mean_gap = (sum(r.toks for r in worst_z) - sum(r.toks for r in matched)) / len(worst_z) if worst_z else 0.0
        print(f"    least-readable quartile {wk}/{wn} = {wr:.3f} {fmt_ci((w_lo, w_hi))}  vs matched control "
              f"{mk}/{mn} = {mr:.3f} {fmt_ci((m_lo, m_hi))}  RR={rr:.3f} {fmt_ci((rr_lo, rr_hi))}"
              f"  (mean token gap quartile-minus-match: {mean_gap:+.1f})")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bin", default=rp.DEFAULT_BIN)
    ap.add_argument("--cutoff", default=DEFAULT_CUTOFF)
    ap.add_argument("--until", default=DEFAULT_UNTIL)
    ap.add_argument("--out", default=None, help="write the per-function TSV here")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--scratch", default=None)
    ap.add_argument("--load-tsv", default=None,
                     help="skip the population crawl and outcome-marking pass (the slow ~15-minute step) "
                          "and re-load a previously written --out TSV instead — for re-stratifying "
                          "(--strata, deciles, the matched control) on data already computed. The window/"
                          "fix-commit counts in the report line are not available from a TSV alone and "
                          "print as 'n/a'.")
    args = ap.parse_args()

    if args.load_tsv:
        pop = []
        with open(args.load_tsv, encoding="utf-8") as f:
            for row in csv.DictReader(f, delimiter="\t"):
                pop.append(FnRow(path=row["path"], name=row["name"], start_line=int(row["start_line"]),
                                  lines=int(row["lines"]), toks=int(row["toks"]), z=float(row["z"]),
                                  ccx=int(row["ccx"]), fixed=bool(int(row["fixed"])),
                                  modified=bool(int(row["modified"]))))
        meta = {"window_total": "n/a (--load-tsv)", "touch_commits": "n/a", "fix_commits": "n/a"}
    else:
        if not Path(args.bin).is_file():
            print(f"error: ripwire binary not found at {args.bin}", file=sys.stderr)
            return 2
        scratch = Path(args.scratch) if args.scratch else Path(tempfile.mkdtemp(prefix="rw_fixrate_"))
        try:
            pop_src = scratch / "population_src"
            pop_src.mkdir(parents=True)
            archive = subprocess.run(["git", "archive", args.cutoff, "--", "src"], cwd=str(rp.ROOT),
                                      capture_output=True, timeout=60)
            if archive.returncode != 0:
                print(f"error: git archive {args.cutoff} -- src failed: {archive.stderr.decode()}", file=sys.stderr)
                return 2
            with tempfile.NamedTemporaryFile(suffix=".tar") as tf:
                tf.write(archive.stdout)
                tf.flush()
                with tarfile.open(tf.name) as tar:
                    tar.extractall(pop_src)

            pop_map = crawl_population(args.bin, pop_src)
            commits = window_commits(args.until, args.cutoff)
            meta = mark_outcomes(args.bin, pop_map, commits, scratch / "mark_scratch")
            meta["window_total"] = len(commits)
            pop = list(pop_map.values())
        finally:
            if not args.scratch:
                shutil.rmtree(scratch, ignore_errors=True)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write("path\tname\tstart_line\tlines\ttoks\tz\tccx\tfixed\tmodified\n")
            for r in pop:
                f.write(f"{r.path}\t{r.name}\t{r.start_line}\t{r.lines}\t{r.toks}\t{r.z:.6f}\t{r.ccx}\t{int(r.fixed)}\t{int(r.modified)}\n")
        print(f"# wrote {len(pop)} rows to {args.out}", file=sys.stderr)

    if args.json:
        def arm_json(rows, key):
            worst, rest = quartile_split(rows, key=key)
            return {o: report_arm("x", worst, rest, o) for o in ("fixed", "modified")}
        def strat_json(strat_key):
            return [
                {"n": len(band),
                 "readability": arm_json(band, lambda r: r.z),
                 "complexity": arm_json(band, lambda r: -r.ccx)}
                for band in size_terciles(pop, key=strat_key)
            ]
        print(json.dumps({
            "meta": meta,
            "n_population": len(pop),
            "readability": arm_json(pop, lambda r: r.z),
            "complexity": arm_json(pop, lambda r: -r.ccx),
            "stratified_by_lines": strat_json(lambda r: r.lines),
            "stratified_by_toks": strat_json(lambda r: r.toks),
        }, indent=2, default=str))
    else:
        print_report(pop, meta)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
