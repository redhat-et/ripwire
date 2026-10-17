#!/usr/bin/env python3
"""The one root-resolution rule the three aismells scripts share.

Each of them takes either a single `--root` or a `--corpus` directory of checkouts, and each of
them wants the same answer: a list of `(label, path)` pairs, sorted, optionally capped, optionally
restricted to directories that are actually git repositories. Written once, on purpose — three
copies of this loop is the finding `docs/research/ai-smells-reuse-decline.md` is about.
"""

import os


def resolve_roots(root, corpus, limit=0, require_git=False):
    """(label, path) pairs for one root, or for every subdirectory of a corpus directory."""
    if not corpus:
        path = os.path.abspath(root)
        return [(os.path.basename(path) or path, root)]
    picked = []
    for name in sorted(os.listdir(corpus)):
        path = os.path.join(corpus, name)
        if not os.path.isdir(path):
            continue
        if require_git and not os.path.isdir(os.path.join(path, ".git")):
            continue
        picked.append((name, path))
        if limit and len(picked) >= limit:
            break
    return picked
