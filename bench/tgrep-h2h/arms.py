#!/usr/bin/env python3
"""Arm adapters for the tgrep head-to-head.

The verb map was FROZEN from each tool's own --help before any timing existed.

Five arms, and the DELIVERY POSTURE of each is part of its definition because the
comparison is otherwise a lie of omission:

  rw-cold     ripwire --grep/--regex with a FRESH TMPDIR (the per-root warm cache lives at
              $TMPDIR/ripwire), so the tree-sitter ingest is paid inside the query.
  rw-warm     the same invocation with the cache already written by a preceding run.
              WARM MEANS THE PARSE, NOT THE TEXT: the symbol graph is restored from the
              cache, and every file is still read and scanned byte by byte on every call.
  rw-warm-all ripwire warm with --limit=1000000, i.e. every hit emitted rather than the
              default 100-hit page. This is the only ripwire arm whose emission is
              comparable to rg's, and it is the arm the agreement matrix reads.
  tgrep-warm  a query against a resident `tgrep serve` whose index is already built.
  tgrep-cold  `tgrep --no-index`, tgrep's own brute-force scanner - the control that
              separates "the index helps" from "the Rust scanner is faster".
  rg          ripgrep --sort path (Round C's README requires --sort path: without it the
              floor arm is nondeterministic).

All arms honour .gitignore by default, skip binary files by default, and are given the
same corpus root.
"""

import json
import os
import re
import shutil
import subprocess
import time

RIPWIRE = os.environ.get("RIPWIRE_BIN", "./build/ripwire")
TGREP = os.environ.get("TGREP_BIN", "tgrep")
RG = os.environ.get("RG_BIN", shutil.which("rg") or "rg")

DEVNULL = subprocess.DEVNULL


# ── timing primitive ──────────────────────────────────────────────────────────────────
def _wall(argv, env=None, timeout=300, capture=False):
    """One run. Returns (seconds, bytes_out, rc, out_or_None).

    stdout goes to /dev/null unless capture is asked for, so the timing arm never pays
    for a temp file that only one of the arms would fill.
    """
    e = dict(os.environ)
    if env:
        e.update(env)
    t0 = time.perf_counter()
    try:
        if capture:
            p = subprocess.run(argv, env=e, stdout=subprocess.PIPE, stderr=DEVNULL, timeout=timeout)
            out = p.stdout
        else:
            p = subprocess.run(argv, env=e, stdout=DEVNULL, stderr=DEVNULL, timeout=timeout)
            out = None
    except subprocess.TimeoutExpired:
        return (float("inf"), 0, 124, None)
    dt = time.perf_counter() - t0
    return (dt, len(out) if out is not None else -1, p.returncode, out)


def median(xs):
    xs = sorted(x for x in xs if x == x)
    if not xs:
        return float("nan")
    n = len(xs)
    return xs[n // 2] if n % 2 else 0.5 * (xs[n // 2 - 1] + xs[n // 2])


# ── argv builders (the frozen verb map) ───────────────────────────────────────────────
def rw_argv(root, pat, is_regex, limit=None, extra=()):
    a = [RIPWIRE, root, ("--regex=" + pat) if is_regex else ("--grep=" + pat), "--grep-in=any"]
    if limit:
        a.append("--limit=%d" % limit)
    a.extend(extra)
    return a


def tgrep_argv(root, pat, is_regex, index_path, no_index=False):
    a = [TGREP, "--index-path", index_path, "--sort", "path", "-n", "--no-heading", "-H"]
    if no_index:
        a.append("--no-index")
    if not is_regex:
        a.append("-F")
    a += ["-e", pat, root]
    return a


def rg_argv(root, pat, is_regex):
    a = [RG, "--sort", "path", "-n", "--no-heading", "-H"]
    if not is_regex:
        a.append("-F")
    a += ["-e", pat, root]
    return a


# ── hit-set extraction ────────────────────────────────────────────────────────────────
_RW_F = re.compile(rb'<f p="([^"]*)"')
_RW_HIT = re.compile(rb'<(?:hit|at) l="(\d+)"')
_RW_TOKEN = re.compile(rb'<f p="([^"]*)"|<(?:hit|at) l="(\d+)"')


def rw_hitset(out, root):
    """(relpath, line) pairs from a ripwire --grep answer.

    Both <hit l=> and its folded <at l=> siblings count: a byte-identical match at another
    site in the same file folds into the first hit's n= plus one <at/> per extra site.
    The legend comment is stripped first - it quotes the element names.
    """
    body = out.split(b"-->", 1)[1] if out.startswith(b"<!--") else out
    hits = set()
    cur = None
    for m in _RW_TOKEN.finditer(body):
        if m.group(1) is not None:
            cur = m.group(1).decode("utf-8", "replace")
        elif cur is not None:
            hits.add((cur, int(m.group(2))))
    return hits


def rw_header(out):
    body = out.split(b"-->", 1)[1] if out.startswith(b"<!--") else out
    m = re.match(rb"<grep ([^>]*)>", body)
    if not m:
        return {}
    return {k.decode(): v.decode() for k, v in re.findall(rb'(\w+)="([^"]*)"', m.group(1))}


_LINE = re.compile(rb"^(.*?):(\d+):", re.M)


def grep_hitset(out, root):
    """(relpath, line) pairs from rg/tgrep -n --no-heading -H output."""
    root = os.path.normpath(root)
    hits = set()
    for m in _LINE.finditer(out):
        p = m.group(1).decode("utf-8", "replace")
        if p.startswith(root):
            p = os.path.relpath(p, root)
        hits.add((p, int(m.group(2))))
    return hits
