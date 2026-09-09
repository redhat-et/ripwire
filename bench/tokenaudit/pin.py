#!/usr/bin/env python3
# pin.py — regenerate test/estcalib.manifest: the REAL o200k_base / cl100k_base token counts of
# ripwire's output on the frozen fixture test/estcalibfix, for the invocations that print est_tokens=.
#
# WHY A MANIFEST AND NOT A GATE THAT TOKENIZES. tiktoken is a Python package. G3 is one deterministic
# build step with nothing host-installed, and every gate in test/ runs on a machine that has bash,
# python3's STDLIB and the binary — nothing else. A gate that imported tiktoken would be a dependency
# the build contract forbids, and one that shelled out to a network-fetching encoder would be worse.
# So the tokenizer runs HERE, by hand, and writes numbers; the gate (test/tokenbudgetcheck.sh #18)
# reads those numbers and needs no package at all. Same shape as test/printf_parity.manifest.
#
# WHY THE PINS DO NOT ROT. The fixture is copied to a temp dir OUTSIDE any repository and crawled by a
# RELATIVE path, so the output carries no `at="<sha>+dirty"` stamp (nothing to stamp) and root="f" is
# one byte on every machine. The only thing that can move these numbers is the fixture (frozen) or the
# emitter (which is exactly what the gate is for).
#
# Usage:  python3 bench/tokenaudit/pin.py --bin build/ripwire   # needs tiktoken in the ambient python

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

# The pinned invocations: label, then argv AFTER the root. No argument may contain a space — the
# manifest is space-separated and the gate splits on whitespace, exactly like printf_parity.manifest.
# Only verbs that PRINT est_tokens= belong here; a verb that prints none has nothing to calibrate
# (that absence is itself reported in bench/tokenaudit/README.md, not gated here).
PINNED = [
    ("map",             []),
    ("map-topk5",       ["--top-k=5"]),
    ("metrics",         ["--metrics"]),
    ("pack-signatures", ["--pack-signatures"]),
    ("expand",          ["--expand=billableTotal"]),
    ("for-named",       ["--for=billableTotal"]),
    ("for-budgeted",    ["--for=dedupe", "--token-budget=400"]),
    ("pack-task",       ["--pack-task=dedupe"]),
]

EST = b'est_tokens="'


def est_of(out: bytes):
    i = out.find(EST)
    if i < 0:
        return None
    j = out.find(b'"', i + len(EST))
    return int(out[i + len(EST):j])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", default="build/ripwire")
    ap.add_argument("--fixture", default="test/estcalibfix")
    ap.add_argument("--out", default="test/estcalib.manifest")
    args = ap.parse_args()

    import tiktoken
    o200k = tiktoken.get_encoding("o200k_base")
    cl100k = tiktoken.get_encoding("cl100k_base")

    binpath = os.path.abspath(args.bin)
    fixture = os.path.abspath(args.fixture)
    out_path = os.path.abspath(args.out)

    lines = [
        "# est_calib pins — REAL tokenizer counts of ripwire's output on test/estcalibfix.",
        "# label o200k cl100k est_at_pin_time argv...   (space-separated; no argv may contain a space)",
        "# Regenerate: python3 bench/tokenaudit/pin.py --bin build/ripwire   (needs tiktoken)",
        "# Read by: test/tokenbudgetcheck.sh #18 — the calibration band. See bench/tokenaudit/README.md.",
    ]
    tmp = tempfile.mkdtemp()
    try:
        shutil.copytree(fixture, os.path.join(tmp, "f"))
        for label, argv in PINNED:
            p = subprocess.run([binpath, "f"] + argv, capture_output=True, cwd=tmp)
            if p.returncode != 0:
                print("pin.py: '%s' exited %d" % (label, p.returncode), file=sys.stderr)
                return 1
            est = est_of(p.stdout)
            if est is None:
                print("pin.py: '%s' printed no est_tokens — remove it from PINNED" % label, file=sys.stderr)
                return 1
            text = p.stdout.decode("utf-8", "replace")
            lines.append("%s %d %d %d %s" % (label, len(o200k.encode(text)),
                                             len(cl100k.encode(text)), est, " ".join(argv)))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
