#!/usr/bin/env python3
"""make_snapshot.py — freeze and verify the recall lane's document corpus.

WHY THIS EXISTS: test/recallevalcheck.sh's recall-lane floor was ratcheted 85→83→78→69 in five days
by CORPUS COMPOSITION alone — the eval corpus was the live repo's own docs, so every documentation
round moved BM25 length normalization and rank boundaries while the ranker was provably neutral
(the forensic record is the gate's own header, entries 2026-08-03 through 2026-08-07). The owner
ruling: the recall lane scores a FROZEN snapshot of the doc corpus, so the lane measures the RANKER;
live-corpus composition stays reported by the harness's live pollution@5 probe.

WHAT A SNAPSHOT IS: every tracked *.md at one pinned commit, packed into the single file
bench/recalleval/snapshot.mdpack — a length-prefixed concatenation ("<path>\\n<size>\\n<bytes>\\n"
per doc, sorted by path, after one header line). ONE file, deliberately: a first cut stored the
corpus as 113 suffix-renamed files and pushed the warm --edit-check crawl over its 100 ms budget
(92 ms → 110-136 ms, measured) — the snapshot must not tax every walk of the live tree. The .mdpack
extension is the litter defense: the crawler indexes markdown by extension, so the pack appears in
neither --recall nor the flagless map (probed: unknown extensions are not indexed), and the frozen
corpus cannot become a decoy inside the live tree it froze. The harness unpacks it into a temp root
per run. Self-contained bytes, deliberately NOT git-blob references: this repository's trunk has
been force-rebased before, so commit reachability is not an integrity anchor; a checked-in copy
plus a content hash is.

THE LOCK: snapshot.lock pins source_commit, source_commit_date, files, corpus_sha256. The hash is
sha256 over every frozen doc in sorted repo-relative order ("<path>\\0<bytes>\\0"), recomputed from
the pack on disk — verification needs no git history at all, and the hash is independent of the
container format (a per-file layout of the same docs hashes identically).

UPDATE POLICY (the gate header's 2026-08-07 FROZEN SNAPSHOT entry is authoritative): refresh ONLY in
a deliberate recalibration commit that states why, re-freezes, re-measures the frozen baselines, and
resets the gate's floors — all in one commit. A red floor is never a reason to refresh.

Usage:
  python3 bench/recalleval/make_snapshot.py --verify           # gate check #0: lock matches disk
  python3 bench/recalleval/make_snapshot.py --freeze [COMMIT]  # recalibration only; default HEAD

Exit codes mirror the gate family: 0 ok, 1 broken/mismatch, 2 setup error.
"""

import argparse
import hashlib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PACK_PATH = os.path.join(HERE, "snapshot.mdpack")
LOCK_PATH = os.path.join(HERE, "snapshot.lock")
PACK_MAGIC = b"RECALLEVAL-SNAPSHOT v1\n"

# The snapshot must never contain itself: nothing under bench/recalleval/ joins the corpus, so a
# re-freeze at a commit that already ships a pack cannot recurse (and the pack is not *.md anyway).
SELF_PREFIX = "bench/recalleval/"


def git(args):
    return subprocess.run(["git", "-C", REPO] + args, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=True).stdout


def read_pack():
    """[(repo-relative doc path, bytes)] in stored (sorted) order; raises ValueError on malformation."""
    with open(PACK_PATH, "rb") as fh:
        blob = fh.read()
    if not blob.startswith(PACK_MAGIC):
        raise ValueError("bad magic — not a v1 snapshot pack")
    docs = []
    pos = len(PACK_MAGIC)
    while pos < len(blob):
        nl = blob.index(b"\n", pos)
        path = blob[pos:nl].decode("utf-8")
        pos = nl + 1
        nl = blob.index(b"\n", pos)
        size = int(blob[pos:nl])
        pos = nl + 1
        content = blob[pos:pos + size]
        if len(content) != size or blob[pos + size:pos + size + 1] != b"\n":
            raise ValueError("truncated entry for %s" % path)
        pos += size + 1
        docs.append((path, content))
    return docs


def write_pack(docs):
    with open(PACK_PATH, "wb") as fh:
        fh.write(PACK_MAGIC)
        for path, content in docs:
            fh.write(path.encode("utf-8") + b"\n")
            fh.write(str(len(content)).encode("ascii") + b"\n")
            fh.write(content + b"\n")


def corpus_hash(docs):
    """sha256 over "<path>\\0<bytes>\\0" in sorted path order — container-independent, no git needed."""
    h = hashlib.sha256()
    for path, content in sorted(docs):
        h.update(path.encode("utf-8") + b"\0")
        h.update(content)
        h.update(b"\0")
    return h.hexdigest()


def read_lock():
    lock = {}
    with open(LOCK_PATH, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                lock[key] = val
    return lock


def cmd_verify():
    if not os.path.isfile(LOCK_PATH):
        print("make_snapshot: no snapshot.lock at %s — run --freeze in a recalibration commit" % LOCK_PATH, file=sys.stderr)
        return 1
    if not os.path.isfile(PACK_PATH):
        print("make_snapshot: no snapshot pack at %s" % PACK_PATH, file=sys.stderr)
        return 1
    lock = read_lock()
    for key in ("source_commit", "files", "corpus_sha256"):
        if key not in lock:
            print("make_snapshot: snapshot.lock is missing '%s'" % key, file=sys.stderr)
            return 1
    try:
        docs = read_pack()
    except (ValueError, IndexError) as e:
        print("make_snapshot: snapshot pack unreadable: %s" % e, file=sys.stderr)
        return 1
    if len(docs) != int(lock["files"]):
        print("make_snapshot: MISMATCH — lock pins files=%s but the pack holds %d docs" % (lock["files"], len(docs)), file=sys.stderr)
        return 1
    digest = corpus_hash(docs)
    if digest != lock["corpus_sha256"]:
        print("make_snapshot: MISMATCH — corpus_sha256 %s… on disk vs %s… in the lock; the pack was edited or a refresh went unrecorded" % (digest[:12], lock["corpus_sha256"][:12]), file=sys.stderr)
        return 1
    print("snapshot verified: commit=%s files=%d sha=%s" % (lock["source_commit"][:12], len(docs), digest[:12]))
    return 0


def cmd_freeze(commit):
    try:
        full_commit = git(["rev-parse", "--verify", commit + "^{commit}"]).decode().strip()
        commit_date = git(["show", "-s", "--format=%cI", full_commit]).decode().strip()
        listing = git(["ls-tree", "-r", "--name-only", "-z", full_commit]).decode("utf-8")
    except subprocess.CalledProcessError as e:
        print("make_snapshot: git failed: %s" % e.stderr.decode(errors="replace").strip(), file=sys.stderr)
        return 2
    doc_paths = sorted(p for p in listing.split("\0")
                       if p.lower().endswith(".md") and not p.startswith(SELF_PREFIX))
    if not doc_paths:
        print("make_snapshot: %s has no tracked *.md — refusing to freeze an empty corpus" % commit, file=sys.stderr)
        return 2

    docs = [(path, git(["show", "%s:%s" % (full_commit, path)])) for path in doc_paths]
    write_pack(docs)
    digest = corpus_hash(docs)
    with open(LOCK_PATH, "w", encoding="utf-8") as fh:
        fh.write(
            "# snapshot.lock — pins the recall lane's FROZEN doc corpus (see make_snapshot.py and the\n"
            "# 2026-08-07 FROZEN SNAPSHOT entry in test/recallevalcheck.sh). Regenerated ONLY by\n"
            "#   python3 bench/recalleval/make_snapshot.py --freeze [COMMIT]\n"
            "# in a deliberate recalibration commit that also re-measures the frozen baselines and resets\n"
            "# the gate's floors. Hand-editing this file or snapshot.mdpack reds gate check #0.\n"
            "source_commit=%s\n"
            "source_commit_date=%s\n"
            "files=%d\n"
            "corpus_sha256=%s\n" % (full_commit, commit_date, len(docs), digest))
    print("froze %d docs @ %s (%s) — sha=%s" % (len(docs), full_commit[:12], commit_date, digest[:12]))
    print("now: re-measure the frozen baselines (run_recalleval.py twice, byte-identical) and reset the")
    print("gate floors in test/recallevalcheck.sh — same commit, per the update policy.")
    return 0


def main():
    ap = argparse.ArgumentParser(description="freeze / verify the recall lane's frozen doc corpus")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--verify", action="store_true", help="check snapshot.lock against the bytes on disk")
    mode.add_argument("--freeze", nargs="?", const="HEAD", metavar="COMMIT",
                      help="re-freeze the corpus at COMMIT (default HEAD) — recalibration commits only")
    args = ap.parse_args()
    return cmd_verify() if args.verify else cmd_freeze(args.freeze)


if __name__ == "__main__":
    sys.exit(main())
