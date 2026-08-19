#!/usr/bin/env python3
"""make_snapshot.py — freeze and verify the eval's frozen corpora (recall lane's docs, ranking lane's source).

WHY THIS EXISTS: test/recallevalcheck.sh's recall-lane floor was ratcheted 85→83→78→69 in five days
by CORPUS COMPOSITION alone — the eval corpus was the live repo's own docs, so every documentation
round moved BM25 length normalization and rank boundaries while the ranker was provably neutral
(the forensic record is the gate's own header, entries 2026-08-03 through 2026-08-07). The owner
ruling: the recall lane scores a FROZEN snapshot of the doc corpus, so the lane measures the RANKER;
live-corpus composition stays reported by the harness's live pollution@5 probe.

THE RANKING LANE INHERITED THE SAME DEFECT AND THE SAME FIX (2026-08-19). It scored the live SOURCE
tree, so every wave that added load-bearing symbols to this repository displaced its own gold —
measured three independent times (docs/EVALS.md §6 probe 4's three-cell control, the wave-2 verifier's
follow-up F, and the subtoken round's 2×2), each time with the ranker provably neutral. Both lanes are
now frozen and this module owns both corpora; a lane differs only by the row it occupies in CORPORA.

WHAT A SNAPSHOT IS: every tracked file matching a corpus's predicate at one pinned commit, packed into
ONE file — a length-prefixed concatenation ("<path>\\n<size>\\n<bytes>\\n" per entry, sorted by path,
after one magic header line). ONE file, deliberately: a first cut stored the doc corpus as 113
suffix-renamed files and pushed the warm --edit-check crawl over its 100 ms budget (92 ms → 110-136 ms,
measured) — a snapshot must not tax every walk of the live tree. The .mdpack / .srcpack extensions are
the litter defense: the crawler indexes by extension, so a pack appears in neither --recall nor the
flagless map (probed: unknown extensions are not indexed), and a frozen corpus cannot become a decoy
inside the live tree it froze. The harness unpacks a pack into a temp root per run. Self-contained
bytes, deliberately NOT git-blob references: this repository's trunk has been force-rebased before, so
commit reachability is not an integrity anchor; a checked-in copy plus a content hash is.

THE TWO CORPORA:
  docs (snapshot.mdpack, snapshot.lock)     — every tracked *.md. The recall lane's --recall universe
                                              is markdown-only on purpose; scores are comparable only
                                              WITHIN a snapshot generation.
  src  (snapshot.srcpack, srcsnapshot.lock) — every tracked file the crawl can reach, so the ranking
                                              lane's --for universe is the whole indexed tree, exactly
                                              as it was live. Stored gzip-compressed: the corpus is
                                              ~32 MB of text and 1.4k files, ~7 MB packed; the docs
                                              pack stays uncompressed and byte-unchanged.

THE SELECTION RULES, and why the src one cannot be wrong in a way that moves a number:
  * docs excludes this directory so a re-freeze cannot pack a previous pack (and no pack is *.md).
  * src excludes the two pack files BY NAME (same anti-recursion reason) and prunes the directory
    names in PRUNE_DIRS. That list MIRRORS part of ingest.h's kCrawlSkipDirs and is a SIZE
    optimization, not a correctness requirement: the crawl prunes those directories inside the frozen
    root exactly as it does inside the live one, so a MISSING entry can only make the pack bigger and
    an entry that stops matching anything can only make it smaller — neither can change a measurement.
    (third_party/ alone is 185 MB of vendored grammars the crawl never opens.) Verified, not assumed:
    at the 2026-08-19 freeze the ranking lane's 32 per-query rank vectors were byte-identical between
    the live root and the frozen root — see the gate header's FROZEN RANKING CORPUS entry.

THE LOCK: each corpus's lock pins source_commit, source_commit_date, files, corpus_sha256. The hash is
sha256 over every frozen entry in sorted repo-relative order ("<path>\\0<bytes>\\0"), recomputed from
the pack on disk — verification needs no git history at all, and the hash is independent of the
container format (a per-file layout, or a change of compression, of the same bytes hashes identically).

UPDATE POLICY (the gate header's FROZEN SNAPSHOT entries are authoritative): refresh ONLY in a
deliberate recalibration commit that states why, re-freezes, re-measures that lane's frozen baselines,
and resets the gate's floors — all in one commit. A red floor is never a reason to refresh. --corpus is
REQUIRED for --freeze and has no default on purpose: the two lanes' baselines are independent, and a
refresh that silently moved the other lane's corpus would reset a baseline nobody re-measured.

Usage:
  python3 bench/recalleval/make_snapshot.py --verify                        # gate check #0: both locks vs disk
  python3 bench/recalleval/make_snapshot.py --verify --corpus src           # one corpus only
  python3 bench/recalleval/make_snapshot.py --freeze [COMMIT] --corpus src  # recalibration only; default HEAD

Exit codes mirror the gate family: 0 ok, 1 broken/mismatch, 2 setup error.
"""

import argparse
import collections
import gzip
import hashlib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

# The pack files, excluded from the SOURCE corpus by name — the src selection keeps this directory's
# .py/.tsv (they are real indexed source, and dropping them would change corpus statistics), so the
# anti-recursion rule has to name the packs rather than the whole directory.
PACK_NAMES = ("snapshot.mdpack", "snapshot.srcpack")

# Directory names the crawl prunes (ingest.h kCrawlSkipDirs). Size optimization only — see the module
# docstring: an incomplete list can only enlarge the pack, never change what the frozen root measures.
PRUNE_DIRS = ("third_party", "vendor", "node_modules", "captures")

# One frozen corpus: where its bytes live, how they are selected, how they are stored, and what to call
# them in a message. DATA, with one shared `selects()` reading it — not a per-corpus predicate function:
# a callback stored in a table is invisible to a name-based call graph (ripwire's own --quality-delta
# read the first draft's two selectors as dead code, correctly by its rules), and a rule you can read as
# a row beats a rule you have to go find the body of.
#   suffix        lowercase filename suffix a path must carry, or None for "any file"
#   prune_dirs    path COMPONENT names that disqualify a path (directories only, never the basename)
#   exclude_names basenames that disqualify a path — the anti-recursion rule
#   unit/lane     honest wording for messages ("113 docs", "the recall lane"); never logic
Corpus = collections.namedtuple(
    "Corpus", "key pack_path lock_path magic compressed suffix prune_dirs exclude_names unit lane")

CORPORA = {
    "docs": Corpus("docs", os.path.join(HERE, "snapshot.mdpack"), os.path.join(HERE, "snapshot.lock"),
                   b"RECALLEVAL-SNAPSHOT v1\n", False, ".md", ("recalleval",), (), "docs", "recall"),
    "src": Corpus("src", os.path.join(HERE, "snapshot.srcpack"), os.path.join(HERE, "srcsnapshot.lock"),
                  b"RECALLEVAL-SRCSNAPSHOT v1\n", True, None, PRUNE_DIRS, PACK_NAMES, "files", "ranking"),
}


def selects(corpus, path):
    """Does this repo-relative tracked path belong to corpus's frozen universe?

    The docs row spells its self-exclusion as the directory component `recalleval` rather than the
    prefix `bench/recalleval/` the 2026-08-07 cut used: identical on this tree (that is the only
    directory of the name) and the same shape as the src row, so both corpora read as one rule.
    """
    if corpus.suffix is not None and not path.lower().endswith(corpus.suffix):
        return False
    if os.path.basename(path) in corpus.exclude_names:
        return False
    return not any(comp in corpus.prune_dirs for comp in path.split("/")[:-1])


def git(args):
    return subprocess.run(["git", "-C", REPO] + args, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=True).stdout


def read_pack(corpus):
    """[(repo-relative path, bytes)] in stored (sorted) order; raises ValueError on malformation."""
    with open(corpus.pack_path, "rb") as fh:
        blob = fh.read()
    if not blob.startswith(corpus.magic):
        raise ValueError("bad magic — not a %s" % corpus.magic.decode().strip())
    body = blob[len(corpus.magic):]
    if corpus.compressed:
        try:
            body = gzip.decompress(body)
        except (OSError, EOFError) as e:
            raise ValueError("compressed payload unreadable: %s" % e)
    entries = []
    pos = 0
    while pos < len(body):
        nl = body.index(b"\n", pos)
        path = body[pos:nl].decode("utf-8")
        pos = nl + 1
        nl = body.index(b"\n", pos)
        size = int(body[pos:nl])
        pos = nl + 1
        content = body[pos:pos + size]
        if len(content) != size or body[pos + size:pos + size + 1] != b"\n":
            raise ValueError("truncated entry for %s" % path)
        pos += size + 1
        entries.append((path, content))
    return entries


def write_pack(corpus, entries):
    body = bytearray()
    for path, content in entries:
        body += path.encode("utf-8") + b"\n"
        body += str(len(content)).encode("ascii") + b"\n"
        body += content + b"\n"
    # mtime=0: a gzip container that stamps the wall clock would make the committed pack differ on
    # every re-freeze of identical bytes. The lock's hash is over CONTENTS, so compression is free to
    # change — but a needlessly churning 7 MB blob in git history is not.
    payload = gzip.compress(bytes(body), 9, mtime=0) if corpus.compressed else bytes(body)
    with open(corpus.pack_path, "wb") as fh:
        fh.write(corpus.magic)
        fh.write(payload)


def corpus_hash(entries):
    """sha256 over "<path>\\0<bytes>\\0" in sorted path order — container-independent, no git needed."""
    h = hashlib.sha256()
    for path, content in sorted(entries):
        h.update(path.encode("utf-8") + b"\0")
        h.update(content)
        h.update(b"\0")
    return h.hexdigest()


def read_lock(corpus):
    lock = {}
    with open(corpus.lock_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                lock[key] = val
    return lock


def verify_one(corpus):
    tag = "%s corpus" % corpus.key
    if not os.path.isfile(corpus.lock_path):
        print("make_snapshot: no %s at %s — run --freeze --corpus %s in a recalibration commit"
              % (os.path.basename(corpus.lock_path), corpus.lock_path, corpus.key), file=sys.stderr)
        return 1
    if not os.path.isfile(corpus.pack_path):
        print("make_snapshot: no %s pack at %s" % (tag, corpus.pack_path), file=sys.stderr)
        return 1
    lock = read_lock(corpus)
    for key in ("source_commit", "files", "corpus_sha256"):
        if key not in lock:
            print("make_snapshot: %s is missing '%s'" % (os.path.basename(corpus.lock_path), key), file=sys.stderr)
            return 1
    try:
        entries = read_pack(corpus)
    except (ValueError, IndexError) as e:
        print("make_snapshot: %s pack unreadable: %s" % (tag, e), file=sys.stderr)
        return 1
    if len(entries) != int(lock["files"]):
        print("make_snapshot: MISMATCH — %s lock pins files=%s but the pack holds %d %s"
              % (tag, lock["files"], len(entries), corpus.unit), file=sys.stderr)
        return 1
    digest = corpus_hash(entries)
    if digest != lock["corpus_sha256"]:
        print("make_snapshot: MISMATCH — %s corpus_sha256 %s… on disk vs %s… in the lock; the pack was edited or a refresh went unrecorded"
              % (tag, digest[:12], lock["corpus_sha256"][:12]), file=sys.stderr)
        return 1
    print("snapshot verified: corpus=%s commit=%s %s=%d sha=%s"
          % (corpus.key, lock["source_commit"][:12], corpus.unit, len(entries), digest[:12]))
    return 0


def cmd_verify(keys):
    rc = 0
    for key in keys:
        rc |= verify_one(CORPORA[key])
    return rc


def cmd_freeze(corpus, commit):
    try:
        full_commit = git(["rev-parse", "--verify", commit + "^{commit}"]).decode().strip()
        commit_date = git(["show", "-s", "--format=%cI", full_commit]).decode().strip()
        listing = git(["ls-tree", "-r", "--name-only", "-z", full_commit]).decode("utf-8")
    except subprocess.CalledProcessError as e:
        print("make_snapshot: git failed: %s" % e.stderr.decode(errors="replace").strip(), file=sys.stderr)
        return 2
    paths = sorted(p for p in listing.split("\0") if p and selects(corpus, p))
    if not paths:
        print("make_snapshot: %s has no tracked %s for corpus '%s' — refusing to freeze an empty corpus"
              % (commit, corpus.unit, corpus.key), file=sys.stderr)
        return 2

    entries = [(path, git(["show", "%s:%s" % (full_commit, path)])) for path in paths]
    write_pack(corpus, entries)
    digest = corpus_hash(entries)
    with open(corpus.lock_path, "w", encoding="utf-8") as fh:
        fh.write(
            "# %s — pins the %s lane's FROZEN corpus (see make_snapshot.py and the FROZEN\n"
            "# SNAPSHOT entries in test/recallevalcheck.sh). Regenerated ONLY by\n"
            "#   python3 bench/recalleval/make_snapshot.py --freeze [COMMIT] --corpus %s\n"
            "# in a deliberate recalibration commit that also re-measures that lane's frozen baselines and\n"
            "# resets the gate's floors. Hand-editing this file or %s reds gate check #0.\n"
            "source_commit=%s\n"
            "source_commit_date=%s\n"
            "files=%d\n"
            "corpus_sha256=%s\n" % (os.path.basename(corpus.lock_path), corpus.lane, corpus.key,
                                    os.path.basename(corpus.pack_path), full_commit, commit_date,
                                    len(entries), digest))
    print("froze %d %s @ %s (%s) — corpus=%s sha=%s pack=%d bytes"
          % (len(entries), corpus.unit, full_commit[:12], commit_date, corpus.key, digest[:12],
             os.path.getsize(corpus.pack_path)))
    print("now: re-measure the %s lane's frozen baselines (run_recalleval.py twice, byte-identical) and" % corpus.lane)
    print("reset its gate floors in test/recallevalcheck.sh — same commit, per the update policy.")
    return 0


def main():
    ap = argparse.ArgumentParser(description="freeze / verify the eval's frozen corpora")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--verify", action="store_true", help="check each lock against the bytes on disk")
    mode.add_argument("--freeze", nargs="?", const="HEAD", metavar="COMMIT",
                      help="re-freeze at COMMIT (default HEAD) — recalibration commits only")
    ap.add_argument("--corpus", choices=("docs", "src", "both"),
                    help="which corpus; --verify defaults to both, --freeze REQUIRES an explicit docs|src")
    args = ap.parse_args()

    if args.verify:
        keys = ("docs", "src") if args.corpus in (None, "both") else (args.corpus,)
        return cmd_verify(keys)
    if args.corpus not in ("docs", "src"):
        ap.error("--freeze requires --corpus docs|src (no default: the lanes' baselines are independent, "
                 "and a refresh must move only the corpus whose floors the same commit re-measures)")
    return cmd_freeze(CORPORA[args.corpus], args.freeze)


if __name__ == "__main__":
    sys.exit(main())
