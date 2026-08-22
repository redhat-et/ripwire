#!/usr/bin/env python3
"""run_recalleval.py — the held-out recall/ranking eval (the retrieval-evaluation plan).

WHY THIS EXISTS: two deferred ranking changes are blocked on a measuring instrument —
  the generated-doc demotion  default de-prioritization of generated docs in the RECALL lens (--recall), and
  the fixture demotion   fixture/present de-prioritization in the RANKING lenses (--for and friends).
This harness is that instrument: it runs the SHIPPING BINARY on two labelled query sets and reports
recall@1/@5 + MRR per lane plus the POLLUTION rate — the fraction of top-5 slots occupied by
fixture / present/ / generated-capture paths. That pollution number is the one a future the fixture demotion/the generated-doc demotion fix
must move DOWN without dropping recall.

WHY A bench/ PYTHON HARNESS AND NOT A NEW --eval-recall VERB (the justification the task requires):
  * The blocked changes alter the EMITTED OUTPUT of --recall and --for. An in-binary eval scoring
    internal vectors could pass while the verb output stays polluted (or the reverse); a black-box
    harness over the built binary measures exactly the artifact agents consume — the same posture as
    bench/locbench/run_locbench.py, the established python-harness precedent here.
  * Zero C++ changes: no risk of touching ranking behavior (a hard constraint of the round), no
    parseArgs churn (test/argvdiffcheck.sh's 282-vector surface stays untouched).

CONVENTIONS REUSED (not a fifth format): TSV label files with '#' comment heads in the
test/skillevalfix/prompts.tsv style; metric names/shapes mirror --eval-retrieval (MRR, recall@k,
deterministic aggregate rows); exit codes mirror the gate family (0 ok, 1 failure, 2 setup error).

POLLUTION PREDICATE (mirrors src/exemplar.h INVARIANT 2's kFixtureComponents, extended by the two the fixture demotion
path families that are neither test nor source): a path is polluted when any '/'-component equals
test|tests|fixture|fixtures|testdata, or a component equals `present`, or the path contains the
`docs/captures/` prefix pair (generated command captures).

Usage:
  python3 bench/recalleval/run_recalleval.py [--bin BIN] [--root DIR] [--lane recall|ranking|both]
                                             [--top-k N] [--verbose]
  RIPWIRE_BIN overrides --bin (gate convention). Default bin: <repo>/build/ripwire.

Output: per-lane human table + machine-readable `AGG\t<lane>\t...` rows (greppable, diff-stable —
the determinism gate runs the harness twice and diffs stdout byte-for-byte).

BOTH LANES SCORE FROZEN CORPORA (recall 2026-08-07, ranking 2026-08-19 — see make_snapshot.py and the
gate header's two FROZEN SNAPSHOT entries):
  * RECALL scores bench/recalleval/snapshot.mdpack — every tracked *.md at the pinned commit.
  * RANKING scores bench/recalleval/snapshot.srcpack — every tracked file the crawl can reach at the
    pinned commit, i.e. the whole indexed tree, because --for's universe is the whole indexed tree.
Each is unpacked into its own temp root per run, so a lane's recall/MRR can move only when the RANKER
moves — a red floor is a ranker regression BY CONSTRUCTION, never this repository gaining a document
or a symbol. The ranking lane's freeze exists because it hit the identical failure the recall lane
did: three independent measurements (docs/EVALS.md §6 probe 4's three-cell control, the wave-2
verifier's follow-up F, the subtoken round's 2×2) each showed a −3.1pp step with the ranker provably
neutral and the corpus — this repo's own new symbols displacing its own gold — carrying all of it.

The LIVE root is still measured, and only where live composition is the question: `recall_livepol`
re-runs the recall queries against it and reports pollution@5 only. The ranking lens's live
anti-pollution property is asserted directly by the gate's check #6 (--for at the live repo root),
which is why this harness grows no second live probe.
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

FIXTURE_COMPONENTS = {"test", "tests", "fixture", "fixtures", "testdata", "present"}
GENERATED_PREFIX = "docs/captures/"

# The class vocabulary the 4-column label format accepts. BASE_CLASSES are the QUERY SHAPES the two
# in-tree label files use (this harness's own two lanes score nothing else, and its per-class report
# below still leads with them, in this order). BUCKET_CLASSES are the RETRIEVAL LOSS SHAPES the
# external-corpus slice uses instead — same file format, same loader, same matcher, different thing
# being partitioned, because that slice exists to produce a rate PER LOSS SHAPE rather than per query
# shape. Widening the vocabulary here rather than forking a fifth parser is deliberate: a second
# loader is a second place for the column contract to drift. It costs one thing and the cost is named
# — labels_ranking.tsv/labels_recall.tsv would no longer be rejected for carrying a bucket class, so
# the header comments in those two files remain the statement of which vocabulary each one uses.
BASE_CLASSES = ("name", "concept", "task", "adversarial")
BUCKET_CLASSES = ("diagnostic-class", "thin-registration", "subsystem-directory", "vendored-asset")
VALID_CLASSES = BASE_CLASSES + BUCKET_CLASSES

RECALL_SEP_RE = re.compile(r"━━ (\S+)\s+\(relevance")          # "━━ <path>  (relevance X) ━━"
CAND_TAG_RE = re.compile(r"<cand ([^>]*?)/?>")
ATTR_RE = re.compile(r'([a-zA-Z_]+)="([^"]*)"')


def norm(path):
    return path[2:] if path.startswith("./") else path


def is_polluted(path):
    p = norm(path)
    if GENERATED_PREFIX in p:
        return True
    # A README is documentation by convention, wherever it sits: test/README.md explains the gate
    # suite and IS the right answer to a question about the gate suite. Counting it as fixture noise
    # measures the path, not the content. This is a rule about READMEs, not a special case for one
    # file, and it can only ever LOWER a pollution figure — the published ranking-lane 0.0% is
    # unaffected, since it was already zero. Added 2026-07-31 with the recall labels' re-authoring.
    if os.path.basename(p).lower() == "readme.md":
        return False
    return any(comp.lower() in FIXTURE_COMPONENTS for comp in p.split("/"))


class Label:
    __slots__ = ("query", "primary", "acceptable", "qclass")

    def __init__(self, query, primary, acceptable, qclass):
        self.query, self.primary, self.acceptable, self.qclass = query, primary, acceptable, qclass


def parse_target(tok):
    """'path#Symbol' -> (path, symbol|None)."""
    if "#" in tok:
        path, sym = tok.split("#", 1)
        return path, sym
    return tok, None


def load_labels(tsv_path):
    labels = []
    with open(tsv_path, "r", encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) != 4:
                raise ValueError("%s:%d: expected 4 tab-separated fields, got %d" % (tsv_path, lineno, len(cols)))
            query, primary, acceptable, qclass = cols
            if qclass not in VALID_CLASSES:
                raise ValueError("%s:%d: unknown class '%s'" % (tsv_path, lineno, qclass))
            prim = [parse_target(t) for t in primary.split(",") if t]
            acc = [] if acceptable == "-" else [parse_target(t) for t in acceptable.split(",") if t]
            if not prim:
                raise ValueError("%s:%d: empty primary" % (tsv_path, lineno))
            labels.append(Label(query, prim, acc, qclass))
    return labels


def target_present(root, targets):
    return all(os.path.exists(os.path.join(root, path)) for path, _ in targets)


def matches(target, cand_path, cand_name):
    path, sym = target
    p = norm(cand_path)
    if not (p == path or p.endswith("/" + path)):
        return False
    return sym is None or cand_name == sym


def run_binary(bin_path, root, args):
    proc = subprocess.run([bin_path, "."] + args, cwd=root, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError("ripwire %s exited %d" % (" ".join(args), proc.returncode))
    return proc.stdout.decode("utf-8", errors="replace")


def ranked_recall(bin_path, root, query):
    """[(path, name=None), ...] best-first from --recall's separator lines (depth = the verb's own k=8)."""
    out = run_binary(bin_path, root, ["--recall=%s" % query])
    return [(m.group(1), None) for m in RECALL_SEP_RE.finditer(out)]


def ranked_for(bin_path, root, query, top_k):
    """[(path, name), ...] best-first from --for --format=candidates."""
    out = run_binary(bin_path, root, ["--for=%s" % query, "--format=candidates", "--top-k=%d" % top_k])
    rows = []
    for tag in CAND_TAG_RE.finditer(out):
        attrs = dict(ATTR_RE.findall(tag.group(1)))
        if "r" in attrs and "p" in attrs:
            rows.append((int(attrs["r"]), attrs["p"], attrs.get("n", "")))
    rows.sort(key=lambda t: t[0])
    return [(p, n) for _, p, n in rows]


def first_hit_rank(ranked, targets):
    for i, (path, name) in enumerate(ranked, 1):
        if any(matches(t, path, name) for t in targets):
            return i
    return None


class Agg:
    def __init__(self):
        self.n = 0
        self.strict_r1 = self.strict_r5 = self.lenient_r1 = self.lenient_r5 = 0
        self.mrr_strict = self.mrr_lenient = 0.0
        self.polluted_slots = 0
        self.slot_total = 0
        self.by_class = {}

    # named accumulate (not `add`): a bare `add` def would collide with other repo symbols named add in the
    # name-based call graph and misattribute their call edges (observed via --quality-delta on this very file).
    def accumulate(self, qclass, rs, rl, ranked):
        self.n += 1
        if rs is not None:
            self.mrr_strict += 1.0 / rs
            self.strict_r1 += rs <= 1
            self.strict_r5 += rs <= 5
        if rl is not None:
            self.mrr_lenient += 1.0 / rl
            self.lenient_r1 += rl <= 1
            self.lenient_r5 += rl <= 5
        top5 = ranked[:5]
        pol = sum(1 for path, _ in top5 if is_polluted(path))
        self.polluted_slots += pol
        self.slot_total += 5                      # fixed denominator: an empty slot is not polluted
        cls = self.by_class.setdefault(qclass, [0, 0, 0, 0])   # n, lenient_r5, polluted, slots
        cls[0] += 1
        cls[1] += rl is not None and rl <= 5
        cls[2] += pol
        cls[3] += 5


def pct(num, den):
    return 100.0 * num / den if den else 0.0


def materialize_snapshot(tmp_root, corpus_key):
    """Unpack a frozen corpus into tmp_root as real files; return (commit, entry count).

    One function for both lanes (docs -> *.md, src -> the whole crawlable tree): the pack format,
    the lock keys and the failure modes are identical, so a second copy of this would be a clone of
    a helper the tree already reuses. Cheap structural sanity only (lock present, count matches);
    the byte-level corpus_sha256 verification is single-sourced in make_snapshot.py --verify, which
    gate check #0 runs first.
    """
    sys.path.insert(0, HERE)
    from make_snapshot import CORPORA, read_pack
    corpus = CORPORA[corpus_key]
    if not os.path.isfile(corpus.lock_path) or not os.path.isfile(corpus.pack_path):
        raise RuntimeError("frozen %s corpus missing (%s / %s) — run make_snapshot.py --freeze --corpus %s in a recalibration commit"
                           % (corpus_key, corpus.pack_path, corpus.lock_path, corpus_key))
    lock = {}
    with open(corpus.lock_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                lock[key] = val
    entries = read_pack(corpus)
    for rel, content in entries:
        dest = os.path.join(tmp_root, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as fh:
            fh.write(content)
    if len(entries) != int(lock.get("files", "-1")):
        raise RuntimeError("frozen %s corpus mismatch: %d entries in the pack vs files=%s in %s"
                           % (corpus_key, len(entries), lock.get("files"), os.path.basename(corpus.lock_path)))
    return lock["source_commit"], len(entries)


def run_live_pollution(labels, bin_path, root):
    """The live-corpus composition reporter: same queries, LIVE root, pollution@5 only.

    No recall/MRR and no skip logic on purpose — labelled targets are irrelevant to a slot-share
    metric, and printing live recall here would re-open the ratchet the frozen lane retired.
    """
    polluted_slots = 0
    slot_total = 0
    for lab in labels:
        ranked = ranked_recall(bin_path, root, lab.query)
        polluted_slots += sum(1 for path, _ in ranked[:5] if is_polluted(path))
        slot_total += 5
    print("lane=recall_livepol  n=%d queries (LIVE corpus; pollution@5 only — composition, not ranking)" % len(labels))
    print("  pollution@5 = %.1f%% of top-5 slots are fixture/present/generated paths" % pct(polluted_slots, slot_total))
    print("AGG\trecall_livepol\tn=%d\tpollution5=%.1f" % (len(labels), pct(polluted_slots, slot_total)))


def run_lane(name, labels, bin_path, root, ranker, verbose):
    agg = Agg()
    skipped = 0
    for lab in labels:
        if not (target_present(root, lab.primary) and target_present(root, lab.acceptable)):
            skipped += 1
            if verbose:
                print("SKIP\t%s\t%s\t(labelled path absent on disk)" % (name, lab.query))
            continue
        ranked = ranker(lab.query)
        rs = first_hit_rank(ranked, lab.primary)
        rl = first_hit_rank(ranked, lab.primary + lab.acceptable)
        agg.accumulate(lab.qclass, rs, rl, ranked)
        if verbose:
            print("Q\t%s\t%s\tstrict=%s\tlenient=%s\tpolluted_top5=%d\t%s"
                  % (name, lab.qclass, rs if rs else "-", rl if rl else "-",
                     sum(1 for p, _ in ranked[:5] if is_polluted(p)), lab.query))

    n = agg.n if agg.n else 1
    print("lane=%s  n=%d queries (skipped=%d)" % (name, agg.n, skipped))
    print("  %-8s %9s %9s %7s" % ("grade", "recall@1", "recall@5", "MRR"))
    print("  %-8s %8.1f%% %8.1f%% %7.3f" % ("strict", pct(agg.strict_r1, n), pct(agg.strict_r5, n), agg.mrr_strict / n))
    print("  %-8s %8.1f%% %8.1f%% %7.3f" % ("lenient", pct(agg.lenient_r1, n), pct(agg.lenient_r5, n), agg.mrr_lenient / n))
    print("  pollution@5 = %.1f%% of top-5 slots are fixture/present/generated paths" % pct(agg.polluted_slots, agg.slot_total))
    for cls in VALID_CLASSES:
        if cls in agg.by_class:
            cn, cr5, cpol, cslots = agg.by_class[cls]
            print("  CLASS\t%s\t%s\tn=%d\tlenient_r5=%.1f%%\tpollution5=%.1f%%" % (name, cls, cn, pct(cr5, cn), pct(cpol, cslots)))
    print("AGG\t%s\tn=%d\tskipped=%d\tstrict_r1=%.1f\tstrict_r5=%.1f\tlenient_r1=%.1f\tlenient_r5=%.1f\tmrr_strict=%.3f\tmrr_lenient=%.3f\tpollution5=%.1f"
          % (name, agg.n, skipped, pct(agg.strict_r1, n), pct(agg.strict_r5, n),
             pct(agg.lenient_r1, n), pct(agg.lenient_r5, n), agg.mrr_strict / n, agg.mrr_lenient / n,
             pct(agg.polluted_slots, agg.slot_total)))
    return agg.n, skipped


def main():
    ap = argparse.ArgumentParser(description="held-out recall/ranking eval over the built ripwire binary")
    ap.add_argument("--bin", default=os.environ.get("RIPWIRE_BIN", os.path.join(REPO, "build", "ripwire")))
    ap.add_argument("--root", default=REPO,
                    help="the LIVE root. Both scored lanes read their frozen packs and ignore this; it is "
                         "the corpus the recall_livepol composition probe measures.")
    ap.add_argument("--lane", choices=("recall", "ranking", "both"), default="both")
    ap.add_argument("--top-k", type=int, default=10, help="candidate depth for the ranking lane")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    bin_path = os.path.abspath(args.bin)
    root = os.path.abspath(args.root)
    if not os.access(bin_path, os.X_OK):
        print("run_recalleval: no executable binary at %s — build first" % bin_path, file=sys.stderr)
        return 2

    try:
        recall_labels = load_labels(os.path.join(HERE, "labels_recall.tsv"))
        ranking_labels = load_labels(os.path.join(HERE, "labels_ranking.tsv"))
    except (OSError, ValueError) as e:
        print("run_recalleval: label load FAILED: %s" % e, file=sys.stderr)
        return 1
    print("labels OK: recall=%d ranking=%d" % (len(recall_labels), len(ranking_labels)))

    try:
        if args.lane in ("recall", "both"):
            frozen_root = tempfile.mkdtemp(prefix="recalleval_frozen_")
            try:
                commit, count = materialize_snapshot(frozen_root, "docs")
                print("snapshot OK: commit=%s files=%d (frozen corpus materialized)" % (commit, count))
                run_lane("recall", recall_labels, bin_path, frozen_root,
                         lambda q: ranked_recall(bin_path, frozen_root, q), args.verbose)
            finally:
                shutil.rmtree(frozen_root, ignore_errors=True)
            run_live_pollution(recall_labels, bin_path, root)
        if args.lane in ("ranking", "both"):
            frozen_src = tempfile.mkdtemp(prefix="recalleval_frozensrc_")
            try:
                commit, count = materialize_snapshot(frozen_src, "src")
                print("snapshot OK (ranking): commit=%s files=%d (frozen source corpus materialized)" % (commit, count))
                run_lane("ranking", ranking_labels, bin_path, frozen_src,
                         lambda q: ranked_for(bin_path, frozen_src, q, args.top_k), args.verbose)
            finally:
                shutil.rmtree(frozen_src, ignore_errors=True)
    except (RuntimeError, subprocess.TimeoutExpired) as e:
        print("run_recalleval: FAILED: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
