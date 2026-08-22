#!/usr/bin/env python3
"""run_extcorpus.py — absolute per-bucket scorer for the EXTERNAL-CORPUS retrieval slice.

WHY THIS EXISTS. Four retrieval-loss shapes were diagnosed against outside repositories and none of
them can be measured on this tree, because this tree does not contain the populations that produce
them (no vendored asset directory, no numbered migrations, no thin one-hook registration classes, no
directory-per-subsystem layout with a diagnostic-class sibling per mechanism). A gate written here
for those shapes is green because the population is absent — green-while-inert. This harness scores
the same `--for` computation against two PINNED outside trees (bench/recalleval/extcorpus.lock) and
reports a rate PER LOSS SHAPE, which is the granularity a per-bucket band needs.

WHAT IT IS NOT. It is not a floor and it is not wired into any gate. It builds the baseline half of a
registration and computes the same numbers again afterwards; the accept/reject arithmetic lives in the
registration document, not in this file. Nothing here can turn a measurement red.

CONVENTIONS REUSED, NOT A NEW FORMAT (same posture as run_r3diff.py): the label files are
labels_ranking.tsv's own 4-column TSV, and the loader, candidate parser, matcher and binary
invocation are IMPORTED from run_recalleval.py rather than re-implemented. The only thing this module
adds is (a) manifest verification, (b) the per-bucket partition, and (c) the asset-slot-share metric,
which is a different predicate from run_recalleval.py's `is_polluted` and is stated below rather than
folded into it.

TWO METRICS, AND WHY BOTH. Gold rank answers "did the on-task file surface at all". Asset-slot share
answers "what fraction of the top-5 was spent on vendored/generated paths". A bundle can hit its gold
at rank 1 while three of its five slots are admin javascript; only the second number sees that, and
only the second number can be moved by a path de-prioritization. Neither substitutes for the other,
so both are reported for every bucket — not just the one named after the asset problem.

REFUSAL POSTURE. A corpus whose `git rev-parse HEAD` or `HEAD^{tree}` does not match the pinned value
is a hard refusal (exit 2) before any query runs. Silently scoring a different tree than the one the
baseline was taken on is the one failure that would make every number in the registration a lie, and
it is exactly what an unpinned clone drifts into on its own.

Usage:
  python3 bench/recalleval/run_extcorpus.py --bin BIN [--corpora-dir DIR]
                                            [--repo django|webpack|both] [--top-k N] [--verbose]
  RIPWIRE_BIN overrides --bin (gate convention); RIPWIRE_EXTCORPORA overrides --corpora-dir.

Output: a human table per repo plus machine-readable `BUCKET\t...` and `AGG\t...` rows (greppable,
diff-stable — no timestamps, no PIDs, no absolute paths in the report body).

Exit codes mirror the gate family: 0 ok, 1 measurement failure (malformed labels, binary crashed),
2 setup error (no binary, missing/unpinned corpus, bad arguments).
"""

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from run_recalleval import (  # noqa: E402  (sys.path must be set first)
    BUCKET_CLASSES, load_labels, target_present, ranked_for, first_hit_rank, pct,
)

LOCK_PATH = os.path.join(HERE, "extcorpus.lock")
LOCK_FIELDS = ("url", "commit", "tree", "commit_date", "labels", "buckets")

# THE ASSET PREDICATE, stated once. A path is a vendored/generated asset when any of these holds. It
# is deliberately NOT run_recalleval.py's `is_polluted`: that one hunts test fixtures and this one
# hunts shipped-but-not-authored files, and conflating them would let a fixture-demotion change take
# credit for an asset-demotion measurement.
#   * a '/'-component is `static`, `locale`, `vendor`, `node_modules`, `dist` or `min`
#   * the basename matches `0<digits>_*.py` under a `migrations` component (a numbered migration; an
#     unnumbered file such as `migrations/__init__.py` is ordinary source and is NOT counted)
#   * the basename ends `.min.js` or `.min.css`
# Counted per SLOT over a fixed top-5 denominator, matching run_recalleval.py's pollution@5 shape, so
# an empty slot is never scored as clean.
ASSET_COMPONENTS = frozenset(("static", "locale", "vendor", "node_modules", "dist", "min"))


def norm_path(path):
    return path[2:] if path.startswith("./") else path


def is_vendored_asset(path):
    p = norm_path(path)
    comps = p.split("/")
    base = comps[-1]
    if base.endswith(".min.js") or base.endswith(".min.css"):
        return True
    if any(c.lower() in ASSET_COMPONENTS for c in comps[:-1]):
        return True
    if "migrations" in [c.lower() for c in comps[:-1]] and base.endswith(".py"):
        stem = base[:-3]
        if stem[:1] == "0" and stem[1:2].isdigit():
            return True
    return False


def load_manifest(path):
    """extcorpus.lock -> ordered [(name, {field: value}), ...]. Unknown keys are an error."""
    repos = []
    index = {}
    with open(path, "r", encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                raise ValueError("%s:%d: expected key=value" % (path, lineno))
            key, val = line.split("=", 1)
            parts = key.split(".")
            if len(parts) != 3 or parts[0] != "repo":
                raise ValueError("%s:%d: unknown key '%s' (expected repo.<name>.<field>)" % (path, lineno, key))
            _, name, field = parts
            if field not in LOCK_FIELDS:
                raise ValueError("%s:%d: unknown field '%s' (known: %s)" % (path, lineno, field, ", ".join(LOCK_FIELDS)))
            if name not in index:
                index[name] = {}
                repos.append((name, index[name]))
            index[name][field] = val
    if not repos:
        raise ValueError("%s: no repo entries" % path)
    for name, fields in repos:
        missing = [f for f in LOCK_FIELDS if f not in fields]
        if missing:
            raise ValueError("%s: repo '%s' is missing %s" % (path, name, ", ".join(missing)))
        for bucket in fields["buckets"].split(","):
            if bucket not in BUCKET_CLASSES:
                raise ValueError("%s: repo '%s' names unknown bucket '%s'" % (path, name, bucket))
    return repos


def verify_pin(root, name, fields):
    """Refuse loudly unless ROOT is a git checkout sitting on exactly the pinned commit AND tree."""
    if not os.path.isdir(os.path.join(root, ".git")):
        raise RuntimeError("corpus '%s': %s is not a git checkout — materialize it with the recipe in "
                           "bench/recalleval/extcorpus.lock" % (name, root))
    for rev, field in (("HEAD", "commit"), ("HEAD^{tree}", "tree")):
        proc = subprocess.run(["git", "-C", root, "rev-parse", rev], stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL)
        got = proc.stdout.decode("utf-8", "replace").strip()
        if proc.returncode != 0 or not got:
            raise RuntimeError("corpus '%s': git rev-parse %s failed in %s" % (name, rev, root))
        if got != fields[field]:
            raise RuntimeError("corpus '%s' is NOT at its pinned %s: %s on disk, %s in extcorpus.lock. "
                               "Refusing to score a different tree than the baseline was taken on."
                               % (name, field, got, fields[field]))


class BucketAgg:
    """One bucket's running totals. `absorb` (not `add`): a bare `add` def collides by name with
    other symbols in the call graph and misattributes their edges — the same reason
    run_recalleval.py's Agg.accumulate is named that."""

    __slots__ = ("n", "s1", "s5", "s10", "l1", "l5", "l10", "mrr_s", "mrr_l", "asset_slots", "slots")

    def __init__(self):
        self.n = 0
        self.s1 = self.s5 = self.s10 = self.l1 = self.l5 = self.l10 = 0
        self.mrr_s = self.mrr_l = 0.0
        self.asset_slots = 0
        self.slots = 0

    def absorb(self, rs, rl, ranked):
        self.n += 1
        if rs is not None:
            self.mrr_s += 1.0 / rs
            self.s1 += rs <= 1
            self.s5 += rs <= 5
            self.s10 += rs <= 10
        if rl is not None:
            self.mrr_l += 1.0 / rl
            self.l1 += rl <= 1
            self.l5 += rl <= 5
            self.l10 += rl <= 10
        self.asset_slots += sum(1 for path, _ in ranked[:5] if is_vendored_asset(path))
        self.slots += 5                      # fixed denominator: an empty slot is not an asset


def score_repo(name, fields, root, bin_path, top_k, verbose, out):
    labels = load_labels(os.path.join(HERE, fields["labels"]))
    buckets = {}
    order = []
    skipped = 0
    for lab in labels:
        if lab.qclass not in buckets:
            buckets[lab.qclass] = BucketAgg()
            order.append(lab.qclass)
        if not (target_present(root, lab.primary) and target_present(root, lab.acceptable)):
            skipped += 1
            out.append("Q\t%s\t%s\tskip=gold-absent-on-disk\t%s" % (name, lab.qclass, lab.query))
            continue
        ranked = ranked_for(bin_path, root, lab.query, top_k)
        rs = first_hit_rank(ranked, lab.primary)
        rl = first_hit_rank(ranked, lab.primary + lab.acceptable)
        buckets[lab.qclass].absorb(rs, rl, ranked)
        if verbose:
            out.append("Q\t%s\t%s\tstrict=%s\tlenient=%s\tasset_top5=%d\t%s"
                       % (name, lab.qclass, rs if rs else "-", rl if rl else "-",
                          sum(1 for p, _ in ranked[:5] if is_vendored_asset(p)), lab.query))

    out.append("repo=%s  labels=%d  scored=%d  skipped=%d  top_k=%d"
               % (name, len(labels), len(labels) - skipped, skipped, top_k))
    out.append("  %-20s %4s %8s %8s %8s %8s %8s %8s %8s %8s" %
               ("bucket", "n", "s@1", "s@5", "s@10", "l@1", "l@5", "l@10", "MRR_s", "asset@5"))
    for cls in order:
        b = buckets[cls]
        n = b.n if b.n else 1
        out.append("  %-20s %4d %7.1f%% %7.1f%% %7.1f%% %7.1f%% %7.1f%% %7.1f%% %8.3f %7.1f%%"
                   % (cls, b.n, pct(b.s1, n), pct(b.s5, n), pct(b.s10, n),
                      pct(b.l1, n), pct(b.l5, n), pct(b.l10, n), b.mrr_s / n, pct(b.asset_slots, b.slots)))
    for cls in order:
        b = buckets[cls]
        n = b.n if b.n else 1
        out.append("BUCKET\t%s\t%s\tn=%d\tstrict_r1=%.1f\tstrict_r5=%.1f\tstrict_r10=%.1f"
                   "\tlenient_r1=%.1f\tlenient_r5=%.1f\tlenient_r10=%.1f\tmrr_strict=%.3f"
                   "\tmrr_lenient=%.3f\tasset5=%.1f"
                   % (name, cls, b.n, pct(b.s1, n), pct(b.s5, n), pct(b.s10, n),
                      pct(b.l1, n), pct(b.l5, n), pct(b.l10, n), b.mrr_s / n, b.mrr_l / n,
                      pct(b.asset_slots, b.slots)))
    return buckets, order, skipped


def run_extcorpus_cli():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--bin", default=os.environ.get("RIPWIRE_BIN", os.path.join(REPO, "build", "ripwire")))
    ap.add_argument("--corpora-dir", default=os.environ.get("RIPWIRE_EXTCORPORA", ""),
                    help="directory holding the pinned clones named in extcorpus.lock (required)")
    ap.add_argument("--repo", default="both", help="one repo name from extcorpus.lock, or 'both'")
    ap.add_argument("--top-k", type=int, default=10, help="candidate depth (recall@10 needs >= 10)")
    ap.add_argument("--verbose", action="store_true", help="one Q row per query")
    args = ap.parse_args()

    bin_path = os.path.abspath(args.bin)
    if not os.access(bin_path, os.X_OK):
        print("run_extcorpus: no executable binary at %s — build first" % bin_path, file=sys.stderr)
        return 2
    if not args.corpora_dir:
        print("run_extcorpus: --corpora-dir (or RIPWIRE_EXTCORPORA) is required; the pinned clones are "
              "NOT committed — see the materialize recipe in bench/recalleval/extcorpus.lock", file=sys.stderr)
        return 2
    corpora = os.path.abspath(args.corpora_dir)

    try:
        manifest = load_manifest(LOCK_PATH)
    except (OSError, ValueError) as e:
        print("run_extcorpus: manifest load FAILED: %s" % e, file=sys.stderr)
        return 1

    selected = [(n, f) for n, f in manifest if args.repo in ("both", n)]
    if not selected:
        print("run_extcorpus: --repo %s names no entry in extcorpus.lock (known: %s)"
              % (args.repo, ", ".join(n for n, _ in manifest)), file=sys.stderr)
        return 2

    try:
        for name, fields in selected:
            verify_pin(os.path.join(corpora, name), name, fields)
    except RuntimeError as e:
        print("run_extcorpus: %s" % e, file=sys.stderr)
        return 2

    out = []
    totals = {}
    try:
        for name, fields in selected:
            buckets, order, _ = score_repo(name, fields, os.path.join(corpora, name),
                                           bin_path, args.top_k, args.verbose, out)
            for cls in order:
                b = buckets[cls]
                t = totals.setdefault(cls, BucketAgg())
                t.n += b.n
                for attr in ("s1", "s5", "s10", "l1", "l5", "l10", "asset_slots", "slots"):
                    setattr(t, attr, getattr(t, attr) + getattr(b, attr))
                t.mrr_s += b.mrr_s
                t.mrr_l += b.mrr_l
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as e:
        print("run_extcorpus: FAILED: %s" % e, file=sys.stderr)
        return 1

    for cls in BUCKET_CLASSES:
        if cls not in totals:
            continue
        t = totals[cls]
        n = t.n if t.n else 1
        out.append("AGG\textcorpus\t%s\tn=%d\tstrict_r1=%.1f\tstrict_r5=%.1f\tstrict_r10=%.1f"
                   "\tlenient_r1=%.1f\tlenient_r5=%.1f\tlenient_r10=%.1f\tmrr_strict=%.3f"
                   "\tmrr_lenient=%.3f\tasset5=%.1f"
                   % (cls, t.n, pct(t.s1, n), pct(t.s5, n), pct(t.s10, n),
                      pct(t.l1, n), pct(t.l5, n), pct(t.l10, n), t.mrr_s / n, t.mrr_l / n,
                      pct(t.asset_slots, t.slots)))
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(run_extcorpus_cli())
