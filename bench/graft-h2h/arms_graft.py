#!/usr/bin/env python3
"""Graft arm adapters for the head-to-head registered in docs/EVALS.md
("Head-to-head vs Graft — 2026-09-07").

The verb map below was FROZEN from `graft --help` and each sub-command's `--help` BEFORE any
question was scored (see the registration). Two Graft columns are measured, both key-free:

  graft-ask     the plain-words posture: `graft ask "<question verbatim>"` on every shape — what a
                user who pastes the question does. Default `--limit 8`, default refresh-first.
  graft-expert  the verb an expert picks per shape, from the help text alone:
                  S1  ask "<commit subject>"                       (the topical query, no template words)
                  S2  callers <PascalCase(stem of the named file)> --depth 2
                                                                   (graft has no file-level "what depends
                                                                    on this file"; `blast` needs a diff and
                                                                    returned nothing on a synthetic one —
                                                                    probed on an out-of-set file, recorded)
                  S3  grep "<stem of the named file>" --fixed      (exhaustive, grouped by symbol, ranked by
                                                                    coupling: every file that names the stem,
                                                                    tests included)
                  S4  callers <PascalCase(stem of A)> --direction out --depth 2
                                                                   (what A's type reaches, transitively)
                  S5  ask "<question verbatim>"                    (graft has NO history verb; this column
                                                                    is identical to graft-ask by construction
                                                                    and is reported as such)

Every Graft invocation runs through run/senv.sh (env -i + an explicit allowlist) with DO_NOT_TRACK=1,
against its OWN worktree of the corpus at the same pin (graft build mutates the tree: it appends to
.gitignore and writes .ignore, so no other arm may share that checkout).
"""
from __future__ import annotations
import os, re, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'roundc-h2h'))
import arms  # noqa: E402  — the Round C adapters: ripwire, rg floor, placebo, _run, scrub

H = os.environ.get("RW_H2H_HOME", "")
CORPUS_GRAFT = f"{H}/corpus-graft/rocksdb"
SENV = f"{H}/run/senv.sh"
GRAFT = os.environ.get("GRAFT_BIN", f"{os.path.dirname(H)}/bin/graft")


def _stem(path: str) -> str:
    return os.path.basename(path).rsplit(".", 1)[0]


def pascal(stem: str) -> str:
    """`wal_manager` -> `WalManager`. A fixed, disclosed rule; where the real class is spelled otherwise
    (`db_impl` -> `DBImpl`) the row is a measurement of the rule, not an exclusion."""
    return "".join(p[:1].upper() + p[1:] for p in stem.split("_") if p)


def _g(argv, cwd=CORPUS_GRAFT):
    out, ms, rc, rec = arms._run([SENV, GRAFT] + argv, cwd=cwd)
    rec = [a.replace(GRAFT, "$GRAFT") for a in rec]
    return out, ms, rc, rec


def graft_ask(q):
    return _g(["ask", q["question"], CORPUS_GRAFT])


def graft_expert(q):
    s = q["shape"]
    if s == "S1":
        return _g(["ask", q["subject"], CORPUS_GRAFT])
    if s == "S2":
        return _g(["callers", pascal(_stem(q["src"][0])), CORPUS_GRAFT, "--depth", "2"])
    if s == "S3":
        return _g(["grep", _stem(q["src"][0]), CORPUS_GRAFT, "--fixed"])
    if s == "S4":
        return _g(["callers", pascal(_stem(q["src"][0])), CORPUS_GRAFT, "--direction", "out", "--depth", "2"])
    return _g(["ask", q["question"], CORPUS_GRAFT])
