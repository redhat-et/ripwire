#!/usr/bin/env python3
"""run_depthinvariance.py — does `--recall` rank the SAME corpus differently at different CHECKOUT DEPTHS?

THE QUESTION. `test/rootrelemitcheck.sh` closed the EMISSION half of the root-relative contract: every
emitted p=/id= is relative to the corpus root, so the document a consumer receives no longer depends on
where the repo happens to sit on disk. That lane closed with one disclosed residual (its report, §6): the
relevance SCORES still move, because `lexical.h` pass 1.5 tokenizes `ing.files[]` — the STORED spelling,
which the emission lane deliberately left absolute. This script measures that residual.

THE ORACLE IS NOT INVENTED. A RELATIVE root (`ripwire .` from inside the corpus) already stores "./docs/x.md",
whose only path tokens are corpus-internal, so it is already depth-invariant. The correct ranking therefore
already exists and already ships; absolute-root runs simply disagree with it. That is why arm C/D below is
measured too — as a control that the oracle really is flat — and why arm A/C states the target as an
EQUALITY (absolute must reproduce relative) rather than as a tolerance.

FOUR ARMS over the frozen recall corpus (snapshot.mdpack; every tracked *.md at the commit in snapshot.lock)
and its 42 held-out labelled queries (labels_recall.tsv — the query set, not the labels: this measures
INVARIANCE, so whether an answer is RIGHT is a different instrument's job, run_recalleval.py):

  A  absolute root, shallow checkout
  B  absolute root, deep checkout, NEUTRAL segments (share no vocabulary with corpus or queries)
  P  absolute root, deep checkout, ADVERSARIAL segments (every segment IS corpus vocabulary)
  C  relative root ".", cwd = the shallow checkout          <- the oracle
  D  relative root ".", cwd = the deep checkout             <- the oracle's own flatness control

and reports, for each comparison, how many of the 42 queries differ in RANK ORDER, in TOP-K MEMBERSHIP
(a different SET of documents returned for the same query on the same commit — the harm a user sees), and
in RELEVANCE SCORE (the finest signal; the first to move and the last to settle).

NEUTRAL vs ADVERSARIAL is the distinction that matters and the reason both are measured. A neutral deep path
only inflates BM25 length normalization, so it shifts every score slightly and reorders near-ties. A path
whose directories spell query words ALSO collapses those words' idf across the whole corpus — the same word
now matches every document — which reorders answers outright. A gate that tested only neutral depth would
under-report the defect it exists to catch.

USAGE
    python3 bench/recalleval/run_depthinvariance.py --bin ./build/ripwire
    python3 bench/recalleval/run_depthinvariance.py --bin ./build/ripwire --verbose

Exit 0 = ran (the numbers are the result; this script never asserts a floor — test/recallrankdepthcheck.sh
is the gate). Exit 2 = setup error.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

# "━━ <path>  (relevance N.NNN) ━━" — the same separator run_recalleval.py parses, one source of truth for
# what "the ranking" means on this verb.
RECALL_SEP_RE = re.compile(r"^━━ (\S+)\s+\(relevance ([0-9.]+)\)", re.M)

# Nine segments that appear nowhere in the corpus or the query set: depth WITHOUT vocabulary.
NEUTRAL_SEGMENTS = ["qqqqqqqqq"] * 9 + ["q"]
# Nine segments drawn from the corpus's own vocabulary: depth WITH vocabulary. Deliberately SHORTER than
# the neutral path, so any additional damage cannot be attributed to length.
ADVERSARIAL_SEGMENTS = ["ripwire", "docs", "recall", "memory", "design",
                        "architecture", "quality", "ranking", "eval", "d"]


def materialize(tmp_root):
    """Unpack the frozen docs corpus. Reuses run_recalleval.py's own helper — one unpacker, not two."""
    sys.path.insert(0, HERE)
    from run_recalleval import materialize_snapshot
    return materialize_snapshot(tmp_root, "docs")


def load_queries():
    """The 42 held-out recall queries, in file order. Labels are ignored on purpose — see the docstring."""
    qs = []
    with open(os.path.join(HERE, "labels_recall.tsv"), encoding="utf-8") as fh:
        for line in fh:
            if line.strip() and not line.startswith("#"):
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2:
                    qs.append(parts[0].strip())
    return qs


def recall(binary, root_arg, cwd, query):
    proc = subprocess.run([binary, root_arg, "--recall=%s" % query], stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, cwd=cwd, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError("ripwire --recall exited %d for %r" % (proc.returncode, query))
    out = proc.stdout.decode("utf-8", errors="replace")
    return [(m.group(1), m.group(2)) for m in RECALL_SEP_RE.finditer(out)]


class Cmp:
    """One pairwise comparison's three counters."""

    def __init__(self, label, why):
        self.label, self.why = label, why
        self.order = self.topk = self.score = 0
        self.examples = []

    def feed(self, query, left, right):
        lp = [p for p, _ in left]
        rp = [p for p, _ in right]
        if lp != rp:
            self.order += 1
            if len(self.examples) < 4:
                self.examples.append((query, lp[:5], rp[:5]))
        if set(lp) != set(rp):
            self.topk += 1
        if left != right:
            self.score += 1

    def line(self, n):
        return "AGG\tdepthinv\t%-14s order=%d/%d\ttopk=%d/%d\tscore=%d/%d\t%s" % (
            self.label, self.order, n, self.topk, n, self.score, n, self.why)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", default=os.environ.get("RIPWIRE_BIN", os.path.join(REPO, "build", "ripwire")))
    ap.add_argument("--verbose", action="store_true", help="print the reordered queries, best-5 either side")
    args = ap.parse_args()

    binary = os.path.abspath(args.bin)
    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        print("no ripwire binary at %s — build first (cmake --build build -j)" % binary)
        return 2

    tmp = tempfile.mkdtemp(prefix="depthinv_")
    try:
        shallow = os.path.join(tmp, "a")
        deep = os.path.join(tmp, *NEUTRAL_SEGMENTS)
        poll = os.path.join(tmp, *ADVERSARIAL_SEGMENTS)
        for d in (shallow, deep, poll):
            os.makedirs(d)
            commit, count = materialize(d)
        print("snapshot OK: commit=%s files=%d (frozen corpus materialized ×3)" % (commit, count))
        print("roots: shallow=%dch  neutral-deep=%dch (delta %d)  adversarial-deep=%dch (delta %d)"
              % (len(shallow), len(deep), len(deep) - len(shallow), len(poll), len(poll) - len(shallow)))

        queries = load_queries()
        print("queries: %d (labels_recall.tsv, labels ignored — this measures invariance, not correctness)"
              % len(queries))

        ab = Cmp("A-vs-B", "absolute root, neutral depth delta — THE DEFECT")
        ap_ = Cmp("A-vs-P", "absolute root, adversarial depth delta — tf-idf pollution")
        cd = Cmp("C-vs-D", "relative root at both depths — the oracle's own flatness control")
        ac = Cmp("A-vs-C", "absolute vs relative spelling, same corpus — the equality the cure means")

        for q in queries:
            A = recall(binary, shallow, None, q)
            B = recall(binary, deep, None, q)
            P = recall(binary, poll, None, q)
            C = recall(binary, ".", shallow, q)
            D = recall(binary, ".", deep, q)
            ab.feed(q, A, B)
            ap_.feed(q, A, P)
            cd.feed(q, C, D)
            ac.feed(q, A, C)

        n = len(queries)
        print("")
        for c in (ab, ap_, cd, ac):
            print(c.line(n))
        if args.verbose:
            for c in (ab, ap_, cd, ac):
                for q, lp, rp in c.examples:
                    print("")
                    print("%s reordered: %r" % (c.label, q))
                    print("   left : %s" % lp)
                    print("   right: %s" % rp)
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
