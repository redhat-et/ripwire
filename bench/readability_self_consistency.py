#!/usr/bin/env python3
r"""readability_self_consistency.py — proxy (b) of docs/research/readability-construct-validity.md: without
any human label, does `--readability` agree with ITSELF across two mechanical rewrites that should not
change how readable a function is — renaming one local to a fresh, non-colliding name, and reordering two
adjacent, mutually-independent simple statements?

Method: sample functions from this repo's own `src` at percentile positions across the lens's own ranked
list (least-readable-first), so the sample spans the whole distribution rather than only the worst decile
--readability itself prints by default. For each sampled function, re-score its OWN whole file unmodified
in a single-file scratch directory (so the comparison baseline takes the identical measurement path the
mutant does — no cross-file ingest differences to explain away), apply one mutation, re-score the mutated
whole file, and compare.

WHAT THIS TEST ACTUALLY MEASURES, STATED PLAINLY. Halstead volume and Shannon entropy are functions of the
MULTISET of token (class, frequency) pairs, not of token identity or statement order — readability.h's own
determinism note says the entropy sum runs over a token-text-sorted vector precisely because order must not
reach the output. So for a rename to a fresh (non-colliding) identifier, or a reorder of two independent
statements, ZERO change in `vol=`/`ent=`/`posnett=` is what the formula predicts mathematically, not a
finding this script discovers. A pass here mostly certifies IMPLEMENTATION correctness (no stray
non-determinism, no order leak) rather than any claim about human-perceived readability invariance — and it
is honest about that limit rather than overselling a trivial pass as construct validity. The genuinely
informative reading is the FAILURE case: any pair that does NOT tie exactly is either an extraction/mutation
bug in this harness or a real order/identity sensitivity in the lens worth filing. The other honest reading
is what this test structurally CANNOT catch: because the formula is blind to identifier length and to
statement order by construction, it also cannot reward `numberOfActiveConnections` over `n`, or a
better-ordered proof over a worse one — see the "what we would like help with" section of the paired doc.

House rule this script exists under (bench/ANSWERQUALITY.md, bench/BENCHMARK.md): a measurement harness is
a LEDGER, never a red CI gate. It reports numbers and exits 0 regardless of what they say.

Usage:
    bench/readability_self_consistency.py                     # default: this repo's src/, 30 samples
    bench/readability_self_consistency.py --samples 60 --seed 7
    RIPWIRE_BIN=asan/ripwire bench/readability_self_consistency.py --json > consistency.json
"""

from __future__ import annotations

import argparse
import json
import os
import random
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
DEFAULT_CORPUS = "src"

# A fixed, deliberately weird suffix: astronomically unlikely to already occur as a real identifier in this
# tree, so a rename to `<name>_mutrn7k` cannot collide with an existing token and silently change vocab=.
RENAME_SUFFIX = "_mutrn7k"

CPP_KEYWORDS = {
    "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return",
    "const", "static", "inline", "constexpr", "auto", "void", "int", "bool", "char", "double", "float",
    "struct", "class", "namespace", "using", "typename", "template", "public", "private", "protected",
    "true", "false", "nullptr", "new", "delete", "this", "sizeof", "noexcept", "override", "virtual",
    "std", "size_t", "uint32_t", "uint64_t", "int32_t", "int64_t", "std::size_t",
}

IDENT_RE = re.compile(r"\b[a-z_][a-zA-Z0-9_]*\b")
IDENT_ANY_RE = re.compile(r"[A-Za-z_]\w*")
# A conservative "simple statement" shape: one line, ending `;`, no braces (so it is not secretly a whole
# block), with exactly one PLAIN `=` — not `==`/`!=`/`<=`/`>=` and not a compound `+=`/`-=`/… . Matches both
# a bare reassignment (`x = y + z;`) and a one-line typed declaration (`const Foo& x = expr;`), which this
# house style uses constantly (CONTRIBUTING.md Allman style, one statement per line).
SIMPLE_STMT_RE = re.compile(r"^(?P<indent>\s*)(?P<body>[^{};]+);\s*$")
COMPOUND_EQ_PREV = set("=!<>+-*/%&|^")


def parse_simple_stmt(line: str) -> Optional[tuple[str, str, str]]:
    """(indent, lhs_variable_name, rhs_text) for a line this script is willing to reorder, or None. The LHS
    name is the LAST identifier immediately before the plain `=` — for a typed declaration that is the
    variable, not the type."""
    m = SIMPLE_STMT_RE.match(line)
    if not m:
        return None
    body = m.group("body")
    plain_eqs = [i for i, ch in enumerate(body)
                 if ch == "=" and (i == 0 or body[i - 1] not in COMPOUND_EQ_PREV) and body[i + 1:i + 2] != "="]
    if len(plain_eqs) != 1:
        return None
    i = plain_eqs[0]
    lhs_part, rhs_part = body[:i].rstrip(), body[i + 1:].strip()
    if "(" in lhs_part or "[" in lhs_part or "->" in lhs_part:
        return None   # a call, subscript or member target — too easy to get independence wrong
    idents = IDENT_ANY_RE.findall(lhs_part)
    if not idents or idents[-1] in CPP_KEYWORDS:
        return None
    return m.group("indent"), idents[-1], rhs_part


@dataclass
class FnRow:
    path: str
    line: int
    name: str
    lines: int
    posnett: float
    rank_index: int   # position in the lens's own least-readable-first ordering


def run_readability(binary: str, target: str, cwd: Optional[Path] = None) -> list[FnRow]:
    proc = subprocess.run(
        [binary, target, "--readability", "--limit=100000"],
        capture_output=True, text=True, timeout=120, cwd=str(cwd) if cwd else None,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"--readability exited {proc.returncode} on {target}: {proc.stderr.strip()}")
    root = ET.fromstring(proc.stdout)
    rows = []
    for i, fn in enumerate(root.findall("fn")):
        p, _, ln = fn.get("p").rpartition(":")
        rows.append(FnRow(p, int(ln), fn.get("n"), int(fn.get("lines")), float(fn.get("posnett")), i))
    return rows


def score_single_file(binary: str, scratch_dir: Path, basename: str, text: str) -> dict[str, dict]:
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
    out: dict[str, dict] = {}
    for fn in root.findall("fn"):
        name = fn.get("n")
        if name not in out:
            out[name] = {
                "lines": int(fn.get("lines")), "toks": int(fn.get("toks")), "vocab": int(fn.get("vocab")),
                "vol": float(fn.get("vol")), "ent": float(fn.get("ent")), "posnett": float(fn.get("posnett")),
            }
    return out


def stratified_sample(rows: list[FnRow], n: int, rng: random.Random) -> list[FnRow]:
    """n rows spread across the WHOLE ranked distribution (percentile bins with one jittered pick each), not
    just the worst decile the verb shows by default — a consistency check only worth trusting if it covers
    functions the lens currently calls readable as well as ones it calls unreadable."""
    if len(rows) <= n:
        return list(rows)
    picked = []
    bin_size = len(rows) / n
    for i in range(n):
        lo = int(i * bin_size)
        hi = max(lo + 1, int((i + 1) * bin_size))
        hi = min(hi, len(rows))
        picked.append(rows[rng.randrange(lo, hi)])
    return picked


def extract_span(file_lines: list[str], start_line: int, span: int) -> Optional[tuple[int, int]]:
    """1-indexed inclusive [start_line, start_line+span-1], clamped; None if out of range."""
    lo = start_line - 1
    hi = lo + span
    if lo < 0 or hi > len(file_lines) or lo >= hi:
        return None
    return lo, hi


def try_rename(span_lines: list[str], fn_name: str) -> Optional[tuple[list[str], str]]:
    """Pick a lowercase identifier appearing >=2 times in the span, not a keyword, not the function's own
    name, not already ending in RENAME_SUFFIX, whole-word-replace every occurrence. Returns (new_lines,
    renamed_identifier) or None if no eligible candidate exists."""
    text = "\n".join(span_lines)
    counts: dict[str, int] = {}
    for m in IDENT_RE.finditer(text):
        tok = m.group(0)
        if tok in CPP_KEYWORDS or tok == fn_name or len(tok) < 2 or tok.endswith(RENAME_SUFFIX):
            continue
        counts[tok] = counts.get(tok, 0) + 1
    candidates = [t for t, c in counts.items() if c >= 2]
    if not candidates:
        return None
    # Deterministic pick: the most frequent candidate, ties broken lexically — reproducible across runs.
    candidates.sort(key=lambda t: (-counts[t], t))
    victim = candidates[0]
    new_name = victim + RENAME_SUFFIX
    if new_name in text:
        return None   # pathological collision; skip rather than risk a silent vocab change
    pattern = re.compile(r"\b" + re.escape(victim) + r"\b")
    new_text = pattern.sub(new_name, text)
    return new_text.split("\n"), victim


def try_reorder(span_lines: list[str]) -> Optional[tuple[list[str], int]]:
    """Find the first adjacent pair of simple statement lines (parse_simple_stmt), same indentation,
    different LHS name, where neither RHS mentions the other's LHS as a whole word (the independence
    heuristic) — and swap the two full lines."""
    for i in range(len(span_lines) - 1):
        p1 = parse_simple_stmt(span_lines[i])
        p2 = parse_simple_stmt(span_lines[i + 1])
        if not p1 or not p2:
            continue
        indent1, lhs1, rhs1 = p1
        indent2, lhs2, rhs2 = p2
        if indent1 != indent2 or lhs1 == lhs2:
            continue
        if re.search(r"\b" + re.escape(lhs1) + r"\b", rhs2) or re.search(r"\b" + re.escape(lhs2) + r"\b", rhs1):
            continue
        out = list(span_lines)
        out[i], out[i + 1] = out[i + 1], out[i]
        return out, i
    return None


@dataclass
class MutationResult:
    path: str
    name: str
    kind: str   # "rename" | "reorder"
    detail: str
    baseline: dict
    mutant: dict

    def ties(self) -> bool:
        return (abs(self.baseline["vol"] - self.mutant["vol"]) < 1e-6
                and abs(self.baseline["ent"] - self.mutant["ent"]) < 1e-6
                and self.baseline["posnett"] == self.mutant["posnett"])


def run(binary: str, corpus: str, n_samples: int, seed: int, scratch: Path) -> list[MutationResult]:
    rng = random.Random(seed)
    all_rows = run_readability(binary, corpus, cwd=ROOT)
    print(f"# {len(all_rows)} functions measured in {corpus}; sampling {n_samples} across the ranked distribution", file=sys.stderr)
    sample = stratified_sample(all_rows, n_samples, rng)

    results: list[MutationResult] = []
    baseline_dir = scratch / "baseline"
    mutant_dir = scratch / "mutant"
    for row in sample:
        # `p=` in the lens's own output is relative to the scanned root (its legend says so verbatim);
        # rejoin against the corpus argument this run used to get a real path.
        abspath = ROOT / corpus / row.path
        if not abspath.is_file():
            continue
        whole = abspath.read_text(encoding="utf-8", errors="surrogateescape")
        file_lines = whole.split("\n")
        span = extract_span(file_lines, row.line, row.lines)
        if span is None:
            continue
        lo, hi = span
        span_lines = file_lines[lo:hi]
        span_text = "\n".join(span_lines)
        if row.name not in span_text:
            print(f"# skip {row.path}:{row.line} {row.name} — extracted span does not mention its own name (line-mapping drift)", file=sys.stderr)
            continue
        basename = Path(row.path).name

        try:
            baseline_scores = score_single_file(binary, baseline_dir, basename, whole)
        except RuntimeError as exc:
            print(f"# skip {row.path} baseline: {exc}", file=sys.stderr)
            continue
        if row.name not in baseline_scores:
            continue
        base_row = baseline_scores[row.name]

        renamed = try_rename(span_lines, row.name)
        if renamed is not None:
            new_span, victim = renamed
            new_lines = file_lines[:lo] + new_span + file_lines[hi:]
            mutant_text = "\n".join(new_lines)
            try:
                mutant_scores = score_single_file(binary, mutant_dir, basename, mutant_text)
                if row.name in mutant_scores:
                    results.append(MutationResult(row.path, row.name, "rename", f"{victim} -> {victim}{RENAME_SUFFIX}",
                                                   base_row, mutant_scores[row.name]))
            except RuntimeError as exc:
                print(f"# skip {row.path} rename: {exc}", file=sys.stderr)

        reordered = try_reorder(span_lines)
        if reordered is not None:
            new_span, at = reordered
            new_lines = file_lines[:lo] + new_span + file_lines[hi:]
            mutant_text = "\n".join(new_lines)
            try:
                mutant_scores = score_single_file(binary, mutant_dir, basename, mutant_text)
                if row.name in mutant_scores:
                    results.append(MutationResult(row.path, row.name, "reorder", f"swap span-local lines {at},{at+1}",
                                                   base_row, mutant_scores[row.name]))
            except RuntimeError as exc:
                print(f"# skip {row.path} reorder: {exc}", file=sys.stderr)

    return results


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bin", default=DEFAULT_BIN)
    ap.add_argument("--corpus", default=DEFAULT_CORPUS)
    ap.add_argument("--samples", type=int, default=30)
    ap.add_argument("--seed", type=int, default=20260918)
    ap.add_argument("--out", default=None)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--scratch", default=None)
    args = ap.parse_args()

    if not Path(args.bin).is_file():
        print(f"error: ripwire binary not found at {args.bin} — build it first (see CLAUDE.md)", file=sys.stderr)
        return 2

    scratch = Path(args.scratch) if args.scratch else Path(tempfile.mkdtemp(prefix="rw_readconsist_"))
    try:
        results = run(args.bin, args.corpus, args.samples, args.seed, scratch)
    finally:
        if not args.scratch:
            shutil.rmtree(scratch, ignore_errors=True)

    by_kind: dict[str, list[MutationResult]] = {"rename": [], "reorder": []}
    for r in results:
        by_kind[r.kind].append(r)

    summary = {}
    for kind, rs in by_kind.items():
        ties = sum(1 for r in rs if r.ties())
        summary[kind] = {"attempted": len(rs), "exact_tie": ties, "diverged": len(rs) - ties}

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write("kind\tpath\tname\tdetail\ttie\tvol_before\tvol_after\tent_before\tent_after\tposnett_before\tposnett_after\n")
            for r in results:
                f.write(f"{r.kind}\t{r.path}\t{r.name}\t{r.detail}\t{int(r.ties())}\t{r.baseline['vol']:.4f}\t{r.mutant['vol']:.4f}\t{r.baseline['ent']:.4f}\t{r.mutant['ent']:.4f}\t{r.baseline['posnett']:.3f}\t{r.mutant['posnett']:.3f}\n")
        print(f"# wrote {len(results)} mutation results to {args.out}", file=sys.stderr)

    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        for kind, s in summary.items():
            print(f"{kind:8s} attempted={s['attempted']:3d}  exact_tie={s['exact_tie']:3d}  diverged={s['diverged']:3d}")
        for r in results:
            if not r.ties():
                print(f"  DIVERGED [{r.kind}] {r.path} {r.name} ({r.detail}): "
                      f"vol {r.baseline['vol']:.2f}->{r.mutant['vol']:.2f} "
                      f"ent {r.baseline['ent']:.2f}->{r.mutant['ent']:.2f} "
                      f"posnett {r.baseline['posnett']:.3f}->{r.mutant['posnett']:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
