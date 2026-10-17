#!/usr/bin/env python3
"""Deterministic random sampler of (name, body) pairs from real, on-disk checkouts — the instrument
behind the base-rate estimate in docs/research/naming-consistency-withdrawal.md §3. It has no other
job: it does not judge anything, does not touch src/, and is not part of the ripwire build or CI. A
human (or a future run of this same script feeding a documented judging pass) reads the output and
hand-judges each pair against the criteria stated in that document. Reads only; downloads nothing.

Population sampled — real, already-on-disk checkouts, never generated or curated for this purpose:
  - Python:  a set of real GitHub projects checked out for prior ripwire eval rounds (large, actively
             maintained: CPython, Zulip, pandas-scale scientific projects, etc.)
  - Swift:   Alamofire and swift-nio, checked out the same way
  - C++:     ripwire's own src/ — the tool's own source, the one population this document can also
             cross-check against a second, independent instrument (`--lint`, `--quality-delta`)

Sampling unit: one top-level function/method definition with its full body, >=3 non-blank body lines
(enough behavior to judge against the name) and <=60 lines (short enough to judge in one screen).
Sampling is uniform over the pooled per-language candidate list, seeded for reproducibility — rerunning
this script against the same checkouts reproduces the same sample.

CAVEAT this script cannot fix: it extracts by regex, not by parsing (unlike ripwire itself, which uses
real tree-sitter grammars). On multi-line signatures and language constructs it does not model — a
protocol requirement with no body, a signature split across lines — it can pair the wrong body with a
name, or grab only a fragment. §3 of the document reports how many sampled pairs that happened to (2 of
42, by inspection) and drops them rather than judging a mismatched pair. This is a known, disclosed
limitation of a one-off research script, not a claim about ripwire's own extraction, which does not
have this problem.

Usage: sample_base_rate.py OUT.json [--repos-root DIR] [--ripwire-src DIR]
  --repos-root defaults to the checkout root used for this document's measurement (2026-09-20); pass
  your own if re-running elsewhere. --ripwire-src likewise defaults to this repo's own src/.
"""
import argparse
import json
import os
import random
import sys

SEED = 20260920  # the date of the measurement in docs/research/naming-consistency-withdrawal.md
random.seed(SEED)

MAX_FILES_PER_LANG = 4000
MAX_BODY_LINES = 60
MIN_BODY_LINES = 3

import re

PY_DEF_RE = re.compile(r'^(?P<indent>[ \t]*)def (?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(', re.M)
SWIFT_FUNC_RE = re.compile(
    r'^(?P<indent>[ \t]*)(?:public |private |internal |fileprivate |open |static |final |override '
    r'|mutating |@objc\s*)*func (?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*[\(<]', re.M)
CPP_FUNC_RE = re.compile(
    r'^\s*(?:inline |static |constexpr |[A-Za-z_][\w:<>&\*\s]*?\s)(?P<name>[A-Za-z_][A-Za-z0-9_]*)'
    r'\s*\([^;{]*\)\s*(?:const\s*)?(?:noexcept\s*)?\{', re.M)

SKIP_DIRS = {".git", "node_modules", "vendor", "third_party", "__pycache__",
             ".tox", "build", "dist", ".venv", "venv", "migrations"}

CPP_KEYWORDS = {"if", "for", "while", "switch", "return", "sizeof",
                "static_cast", "reinterpret_cast", "const_cast", "dynamic_cast"}


def iter_files(roots, exts):
    for root in roots:
        if not os.path.isdir(root):
            continue
        n = 0
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fn in filenames:
                if fn.endswith(exts):
                    yield os.path.join(dirpath, fn)
                    n += 1
                    if n > MAX_FILES_PER_LANG:
                        return


def brace_match_body(text, open_idx, max_scan=8000):
    depth = 0
    for j in range(open_idx, min(len(text), open_idx + max_scan)):
        c = text[j]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return text[open_idx + 1:j]
    return None


def extract_python(path, text):
    out = []
    lines = text.splitlines()
    for m in PY_DEF_RE.finditer(text):
        indent = len(m.group('indent'))
        start_line = text[:m.start()].count('\n')
        i = start_line + 1
        body = []
        while i < len(lines):
            line = lines[i]
            if line.strip() == "":
                body.append(line)
                i += 1
                continue
            cur_indent = len(line) - len(line.lstrip(' \t'))
            if cur_indent <= indent:
                break
            body.append(line)
            i += 1
        nonblank = [l for l in body if l.strip()]
        if MIN_BODY_LINES <= len(nonblank) <= MAX_BODY_LINES:
            out.append({"lang": "python", "file": path, "name": m.group('name'),
                        "signature": lines[start_line].strip(), "body": "\n".join(body)})
    return out


def extract_swift(path, text):
    out = []
    lines = text.splitlines()
    for m in SWIFT_FUNC_RE.finditer(text):
        start_line = text[:m.start()].count('\n')
        open_idx = text.find('{', m.end() - 1)
        if open_idx == -1:
            continue
        body_text = brace_match_body(text, open_idx)
        if body_text is None:
            continue
        nonblank = [l for l in body_text.splitlines() if l.strip()]
        if MIN_BODY_LINES <= len(nonblank) <= MAX_BODY_LINES:
            out.append({"lang": "swift", "file": path, "name": m.group('name'),
                        "signature": lines[start_line].strip(), "body": body_text})
    return out


def extract_cpp(path, text):
    out = []
    lines = text.splitlines()
    for m in CPP_FUNC_RE.finditer(text):
        name = m.group('name')
        if name in CPP_KEYWORDS:
            continue
        start_line = text[:m.start()].count('\n')
        body_text = brace_match_body(text, m.end() - 1)
        if body_text is None:
            continue
        nonblank = [l for l in body_text.splitlines() if l.strip()]
        if MIN_BODY_LINES <= len(nonblank) <= MAX_BODY_LINES:
            out.append({"lang": "cpp", "file": path, "name": name,
                        "signature": lines[start_line].strip(), "body": body_text})
    return out


def collect(files, extractor):
    cands = []
    for f in files:
        try:
            with open(f, 'r', encoding='utf-8', errors='ignore') as fh:
                text = fh.read()
        except OSError:
            continue
        try:
            cands.extend(extractor(f, text))
        except Exception:
            continue
    return cands


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--repos-root", default=os.environ.get("RIPWIRE_BENCH_ASSETS", "bench-assets"),
                     help="root holding the real-project checkouts (python under r4/repos_*, swift under swift/)")
    ap.add_argument("--ripwire-src", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "src"))
    ap.add_argument("--n-python", type=int, default=20)
    ap.add_argument("--n-swift", type=int, default=10)
    ap.add_argument("--n-cpp", type=int, default=12)
    args = ap.parse_args()

    py_dirs = [os.path.join(args.repos_root, "r4", d) for d in ("repos_b", "repos_c", "repos_d", "repos_e")]
    sw_dirs = [os.path.join(args.repos_root, "swift")]
    cpp_dirs = [args.ripwire_src]

    py_files = list(iter_files(py_dirs, (".py",)))
    sw_files = list(iter_files(sw_dirs, (".swift",)))
    cpp_files = list(iter_files(cpp_dirs, (".h", ".cpp")))

    random.shuffle(py_files)
    random.shuffle(sw_files)
    random.shuffle(cpp_files)

    py_cands = collect(py_files[:300], extract_python)
    sw_cands = collect(sw_files[:200], extract_swift)
    cpp_cands = collect(cpp_files[:120], extract_cpp)

    print(f"candidates: python={len(py_cands)} swift={len(sw_cands)} cpp={len(cpp_cands)}", file=sys.stderr)

    sample = (random.sample(py_cands, min(args.n_python, len(py_cands)))
              + random.sample(sw_cands, min(args.n_swift, len(sw_cands)))
              + random.sample(cpp_cands, min(args.n_cpp, len(cpp_cands))))
    random.shuffle(sample)

    for i, s in enumerate(sample):
        s["idx"] = i
        s["file"] = s["file"].replace(args.repos_root, "bench-assets").replace(
            os.path.abspath(args.ripwire_src), "ripwire/src")

    with open(args.out, 'w') as out:
        json.dump(sample, out, indent=2)
    print(f"wrote {len(sample)} samples to {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
