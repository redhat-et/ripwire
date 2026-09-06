#!/usr/bin/env python3
"""Arm adapters. The verb map is FROZEN here from each tool's own --help text,
BEFORE any score was seen — choosing a verb after seeing which one scores best
is the exact defect this round exists to refuse.

Every third-party arm goes through run/senv.sh: env -i plus an explicit
allowlist (PATH, scratch HOME, TMPDIR, LANG) so this agent session's
credentials are never inherited.
"""
from __future__ import annotations
import os, random, re, subprocess, time

H = "$RW_H2H_HOME"
CORPUS = f"{H}/corpus/rocksdb"
SENV = f"{H}/run/senv.sh"
GORTEX = f"{H}/gortex/prefix/gortex"
CCC = f"{H}/bin/ccc"
RG = "/opt/homebrew/bin/rg"
RIPWIRE = "$RIPWIRE"
TIMEOUT = 300


def _run(argv, cwd=None, env=None):
    t0 = time.perf_counter()
    try:
        p = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, timeout=TIMEOUT)
        out, rc = p.stdout, p.returncode
    except subprocess.TimeoutExpired as e:
        out, rc = (e.stdout or b""), 124
    return out, (time.perf_counter() - t0) * 1000.0, rc, argv


# ---------------------------------------------------------------- ripwire
def _ripwire_argv(q, cold):
    s, base = q["shape"], [RIPWIRE, CORPUS]
    if cold:
        base.append("--no-cache")
    if s == "S1":
        return base + [f"--for={q['subject']}"]
    if s == "S2":
        return base + [f"--situ={q['src'][0]}"]
    if s == "S3":
        return base + [f"--affected={q['src'][0]}"]
    if s == "S4":
        return base + [f"--for={q['question']}"]
    if s == "S5":
        return base + ["--rank-by=churn-decay"]


def ripwire(q, cold):
    return _run(_ripwire_argv(q, cold))


# ---------------------------------------------------------------- gortex
def gortex(q):
    s = q["shape"]
    if s == "S3":
        a = [SENV, GORTEX, "affected", "--index", CORPUS, q["src"][0]]
    elif s == "S5":
        d = q["question"].split(" in ")[1].rstrip("?").strip("`")
        a = [SENV, GORTEX, "docs", CORPUS, "--path-prefix", d,
             "--since", "87600h", "--top", "20"]
    elif s == "S1":
        a = [SENV, GORTEX, "context", "--index", CORPUS, "-t", q["subject"]]
    else:  # S2, S4 — the question plus the file it names as the entry point
        a = [SENV, GORTEX, "context", "--index", CORPUS, "-t", q["question"],
             "-e", q["src"][0]]
    return _run(a)


# ---------------------------------------------------------------- cocoindex
def cocoindex(q):
    return _run([SENV, CCC, "search", q["question"], "--limit", "10"], cwd=CORPUS)


# ---------------------------------------------------------------- rg floor
_STOP = {"where", "what", "which", "how", "does", "the", "with", "change", "changed",
         "changes", "recently", "implemented", "tests", "cover", "reach", "else",
         "has", "that", "this", "when", "from", "into", "have", "been", "were",
         "will", "there", "their", "then", "than", "make", "made", "using", "used",
         "support", "initial", "missing", "remove", "removed", "print", "unknown",
         "record", "flag", "start", "true", "fix", "bug", "add"}


def rg_literal(q):
    """ONE rule, every shape: the first path the question names decides the
    literal (its basename stem); a question that names no path falls back to
    the longest non-stop-word token in it."""
    m = re.search(r'([A-Za-z0-9_./-]+/[A-Za-z0-9_.-]+\.(?:cc|h))', q["question"])
    if m:
        return os.path.basename(m.group(1)).rsplit(".", 1)[0]
    m = re.search(r'in ([A-Za-z0-9_/]+/)\?', q["question"])
    if m:
        return m.group(1)
    toks = [t for t in re.findall(r'[A-Za-z_][A-Za-z0-9_]{3,}', q["question"])
            if t.lower() not in _STOP]
    return max(toks, key=len) if toks else q["question"].split()[0]


def rg_floor(q, max_reads=200):
    """rg for the literal, then whole-file reads of every file it names, in rg's
    own order — what a user without any of these tools does. The read phase is
    capped at 200 files (disclosed); the cap can only make this arm look better,
    because an uncapped incomplete run would score MORE emitted bytes."""
    lit = rg_literal(q)
    t0 = time.perf_counter()
    p = subprocess.run([RG, "-l", "--fixed-strings", "--", lit, CORPUS],
                       capture_output=True, timeout=TIMEOUT)
    out = bytearray(p.stdout)
    files = [l for l in p.stdout.decode(errors="replace").split("\n") if l.strip()]
    for f in files[:max_reads]:
        try:
            with open(f, "rb") as fh:
                out += fh.read()
        except OSError:
            pass
    return (bytes(out), (time.perf_counter() - t0) * 1000.0, p.returncode,
            [RG, "-l", "--fixed-strings", "--", lit, CORPUS,
             f"+whole-file-reads(n<={max_reads})"])


# ---------------------------------------------------------------- placebo
def placebo(q, universe, budget):
    """Random-rank at matched budget: files drawn uniformly at random from the
    corpus's C/C++ universe, seeded by the question index, truncated to the byte
    budget the ripwire arm actually consumed on this question."""
    rnd = random.Random(q["qid"])
    order = universe[:]
    rnd.shuffle(order)
    out = bytearray()
    for p in order:
        line = (p + "\n").encode()
        if len(out) + len(line) > budget:
            break
        out += line
    return bytes(out), 0.0, 0, [f"placebo:random-rank seed={q['qid']} budget={budget}B"]
