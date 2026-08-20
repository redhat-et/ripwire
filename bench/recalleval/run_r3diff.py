#!/usr/bin/env python3
"""run_r3diff.py — R3 instrument: per-query comparative eval diff between two ripwire binaries.

WHY THIS EXISTS (haystack#3, "build this instrument FIRST, it pays for every later round"): every
ranking round in this repo is decided by frozen query sets and pre-registered bands (docs/EVALS.md),
but today comparing two binaries on those sets means ad-hoc one-off scripts, each reinventing label
parsing and re-deriving pass/fail by eye from two separate aggregate reports. This harness runs BOTH
binaries over the SAME frozen query set and the SAME corpus and emits one deterministic PER-QUERY
diff: did the gold symbol/skill move up, move down, get newly served, get dropped, or stay put — plus
a summary (wins/losses/net, broken out by query class when the set has one).

CONVENTIONS REUSED, NOT A NEW FORMAT: this module imports its label parser, its candidate-line
parsers and its binary-invocation helper straight from bench/recalleval/run_recalleval.py — the
established black-box-harness precedent in this repo (same posture as bench/locbench/run_locbench.py).
Two query-set shapes are supported because they are the two ALREADY-FROZEN sets named in the round
brief:

  * "ranking" / "recall"  — bench/recalleval/labels_ranking.tsv / labels_recall.tsv's own 4-column
    TSV: query<TAB>primary<TAB>acceptable<TAB>class. Driven through --for --format=candidates
    (ranking) or --recall (recall), exactly as run_recalleval.py drives them. Gold = a repo-relative
    path, optionally `path#Symbol`; the reported rank is the 1-based position of the first candidate
    matching a gold target (strict = primary only, lenient = primary+acceptable).
  * "skills"  — test/skillevalfix/prompts.tsv's own 4-column TSV: prompt<TAB>expected<TAB>
    provenance<TAB>split, expected = comma-separated skill dirnames or the literal `none`. Driven
    through --for --format=candidates over a skills/ root (one arm --eval-skills itself documents as
    "the SHIPPING --for computation over the skills/ ingest"), candidate paths deduped to skill-dir
    granularity, best-rank-first. This is a single-arm PROXY for --eval-skills' own multi-selector
    routing report, not a reimplementation of it — see the module docstring's LIMITATIONS note below
    and the lane report for the caveat spelled out for a reader deciding how much to trust it.

    LIMITATION: --eval-skills scores several selectors (keyword overlap, BM25-desc, name-match, the
    routed --for ranker) and reports top-1-in-permitted-set; this harness exercises only the routed
    --for arm, deduped to skill granularity. Treat "skills" mode as directional signal on THAT one
    arm, not a replacement for --eval-skills' own aggregate report.

TWO BINARIES, TWO WAYS TO NAME THEM: --a/--b take a path to an already-built executable; --a-ref/
--b-ref take a git ref and build it fresh in its own scratch worktree (git worktree add, never a
branch switch in a tree that might be mid-build — see CLAUDE.md's build/branch-switch race). Mixing
a literal binary on one side and a ref on the other is fine and is the common case (ship vs HEAD~1).

DETERMINISM: no timestamps, no PIDs, no absolute paths in the report body; rows are emitted in the
query file's own line order (never re-sorted by score, which would make the report order depend on
the very ranking under test). Two runs over the same binaries/queries/root byte-diff identical.

REFUSAL: a query-set file that fails column-count / empty-field / unknown-class validation is
rejected with a line number before either binary is ever invoked (exit 1) — the same "refuse loudly"
posture run_recalleval.py's load_labels already established for the ranking/recall formats; this
module adds the matching check for the skills format.

Usage:
  python3 bench/recalleval/run_r3diff.py --a BIN_A --b BIN_B --queries TSV --root DIR [--format …]
  python3 bench/recalleval/run_r3diff.py --a BIN_A --b-ref REF --queries TSV --root DIR
  RIPWIRE_BIN is NOT consulted here (unlike run_recalleval.py) — both sides must be named explicitly;
  a comparative tool with a silent default on one arm is a footgun the other harnesses don't have.

Exit codes: 0 = ran to completion (the report may still show wins/losses — that's data, not failure).
            1 = malformed query-set file, or a binary invocation failed/crashed mid-run.
            2 = setup error (missing binary, ref build failed, bad arguments).
"""

import argparse
import collections
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from run_recalleval import (  # noqa: E402  (sys.path must be set first)
    load_labels, target_present,
    run_binary, ranked_for, ranked_recall, first_hit_rank,
)


# ── skills-format loader (the one gold shape run_recalleval.py does not already parse) ───────────────

SkillRow = collections.namedtuple("SkillRow", ("prompt", "expected", "provenance", "split"))


def load_skill_rows(tsv_path):
    rows = []
    with open(tsv_path, "r", encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) not in (3, 4):
                raise ValueError("%s:%d: expected 3 or 4 tab-separated fields, got %d" % (tsv_path, lineno, len(cols)))
            prompt = cols[0]
            expected_raw = cols[1]
            provenance = cols[2]
            split = cols[3] if len(cols) == 4 else ""
            if not prompt.strip():
                raise ValueError("%s:%d: empty prompt field" % (tsv_path, lineno))
            if not expected_raw.strip():
                raise ValueError("%s:%d: empty expected field (use 'none' for no-skill-should-fire rows)" % (tsv_path, lineno))
            if expected_raw == "none":
                expected = None
            else:
                expected = [e for e in expected_raw.split(",") if e]
                if not expected:
                    raise ValueError("%s:%d: expected field '%s' has no usable skill names" % (tsv_path, lineno, expected_raw))
            rows.append(SkillRow(prompt, expected, provenance, split))
    if not rows:
        raise ValueError("%s: no data rows (every line was blank/comment)" % tsv_path)
    return rows


def ranked_skills(bin_path, root, prompt, top_k):
    """[skillDirName, ...] best-first: --for candidates over ROOT, deduped to skill-dir granularity.

    ROOT is expected to be a skills/ directory (one SKILL.md per subdir, as --eval-skills itself
    requires); a candidate path is root-relative (run_binary cwd's into ROOT), so its first path
    component IS the skill dirname. Multiple sections of the same SKILL.md rank as separate
    candidates; only the first (best) occurrence of each skill dirname is kept, in rank order.
    """
    out = run_binary(bin_path, root, ["--for=%s" % prompt, "--format=candidates", "--top-k=%d" % top_k])
    seen = set()
    order = []
    for tag in _CAND_RE.finditer(out):
        attrs = dict(_ATTR_RE.findall(tag.group(1)))
        p = attrs.get("p", "")
        if not p or "r" not in attrs:
            continue
        if p.startswith("./"):
            p = p[2:]
        skill = p.split("/", 1)[0]
        if skill not in seen:
            seen.add(skill)
            order.append((int(attrs["r"]), skill))
    order.sort(key=lambda t: t[0])
    return [s for _, s in order]


_CAND_RE = re.compile(r"<cand ([^>]*?)/?>")
_ATTR_RE = re.compile(r'([a-zA-Z_]+)="([^"]*)"')


def first_hit_rank_skill(ranked_skill_names, expected):
    if expected is None:
        return None
    for i, name in enumerate(ranked_skill_names, 1):
        if name in expected:
            return i
    return None


# ── query-set format sniffing ─────────────────────────────────────────────────────────────────────────

def sniff_format(tsv_path):
    with open(tsv_path, "r", encoding="utf-8") as fh:
        head = "".join(fh.readline() for _ in range(20))
    if "--eval-skills" in head or "skill[,skill]|none" in head or "skill-ROUTING" in head:
        return "skills"
    if "RECALL lane" in head or "--recall" in head:
        return "recall"
    if "RANKING lane" in head or "--for and friends" in head:
        return "ranking"
    raise ValueError(
        "%s: could not infer query-set format from its header comment (looked for the "
        "labels_ranking.tsv / labels_recall.tsv / prompts.tsv marker phrases) — pass --format explicitly "
        "(ranking|recall|skills)" % tsv_path)


# ── binary resolution: a literal path, or build one from a git ref in a scratch worktree ─────────────

ResolvedBinary = collections.namedtuple("ResolvedBinary", ("label", "path", "worktree_dir"))


def build_from_ref(repo, ref, jobs, label):
    wt = tempfile.mkdtemp(prefix="r3diff_wt_")
    os.rmdir(wt)  # git worktree add refuses an existing (even empty) directory
    proc = subprocess.run(["git", "-C", repo, "worktree", "add", "--detach", wt, ref],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        raise RuntimeError("git worktree add %s %s FAILED:\n%s" % (wt, ref, proc.stdout.decode("utf-8", "replace")))
    build_dir = os.path.join(wt, "build")
    cfg = subprocess.run(["cmake", "-S", wt, "-B", build_dir], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if cfg.returncode != 0:
        raise RuntimeError("cmake configure for %s (%s) FAILED:\n%s" % (label, ref, cfg.stdout.decode("utf-8", "replace")[-4000:]))
    bld = subprocess.run(["cmake", "--build", build_dir, "-j", str(jobs)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if bld.returncode != 0:
        raise RuntimeError("build for %s (%s) FAILED:\n%s" % (label, ref, bld.stdout.decode("utf-8", "replace")[-4000:]))
    binp = os.path.join(build_dir, "ripwire")
    if not os.access(binp, os.X_OK):
        raise RuntimeError("build for %s (%s) produced no executable at %s" % (label, ref, binp))
    return ResolvedBinary("%s@%s" % (label, ref), binp, wt)


def cleanup_worktree(repo, resolved):
    if resolved.worktree_dir is None:
        return
    subprocess.run(["git", "-C", repo, "worktree", "remove", "--force", resolved.worktree_dir],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ── the diff itself ────────────────────────────────────────────────────────────────────────────────────

def classify(rank_a, rank_b):
    if rank_a is None and rank_b is None:
        return "both-unserved"
    if rank_a is None:
        return "gained"
    if rank_b is None:
        return "lost"
    if rank_b < rank_a:
        return "moved-up"
    if rank_b > rank_a:
        return "moved-down"
    return "unchanged"


WINS = ("gained", "moved-up")
LOSSES = ("lost", "moved-down")


def fmt_rank(r):
    return str(r) if r is not None else "-"


def run_ranking_or_recall(qformat, labels, a, b, root, top_k):
    ranker_a = (lambda q: ranked_for(a.path, root, q, top_k)) if qformat == "ranking" else (lambda q: ranked_recall(a.path, root, q))
    ranker_b = (lambda q: ranked_for(b.path, root, q, top_k)) if qformat == "ranking" else (lambda q: ranked_recall(b.path, root, q))
    rows = []
    for lab in labels:
        if not (target_present(root, lab.primary) and target_present(root, lab.acceptable)):
            rows.append(dict(query=lab.query, cls=lab.qclass, skip="gold-absent-on-disk"))
            continue
        ranked_a = ranker_a(lab.query)
        ranked_b = ranker_b(lab.query)
        ra_s = first_hit_rank(ranked_a, lab.primary)
        rb_s = first_hit_rank(ranked_b, lab.primary)
        ra_l = first_hit_rank(ranked_a, lab.primary + lab.acceptable)
        rb_l = first_hit_rank(ranked_b, lab.primary + lab.acceptable)
        rows.append(dict(query=lab.query, cls=lab.qclass, skip=None,
                          rank_a=ra_s, rank_b=rb_s, rank_a_len=ra_l, rank_b_len=rb_l,
                          cat=classify(ra_s, rb_s)))
    return rows


def run_skills(rows_in, a, b, root, top_k):
    rows = []
    for r in rows_in:
        cls = r.split or "-"
        if r.expected is None:
            rows.append(dict(query=r.prompt, cls=cls, skip="no-gold(none)"))
            continue
        ranked_a = ranked_skills(a.path, root, r.prompt, top_k)
        ranked_b = ranked_skills(b.path, root, r.prompt, top_k)
        ra = first_hit_rank_skill(ranked_a, r.expected)
        rb = first_hit_rank_skill(ranked_b, r.expected)
        rows.append(dict(query=r.prompt, cls=cls, skip=None,
                          rank_a=ra, rank_b=rb, rank_a_len=ra, rank_b_len=rb,
                          cat=classify(ra, rb)))
    return rows


def report(rows, a, b, qformat, queries_path, root, top_k):
    out = []
    out.append("r3diff: A=%s B=%s format=%s queries=%s root=%s top_k=%d"
               % (a.label, b.label, qformat, os.path.basename(queries_path), os.path.basename(os.path.normpath(root)), top_k))
    n_scored = n_skipped = wins = losses = ties = 0
    by_class = {}
    for row in rows:
        if row.get("skip"):
            out.append("Q\t%s\tskip=%s\t%s" % (row["cls"], row["skip"], row["query"]))
            n_skipped += 1
            continue
        n_scored += 1
        cat = row["cat"]
        lenient_note = ""
        if row.get("rank_a_len") != row.get("rank_a") or row.get("rank_b_len") != row.get("rank_b"):
            lenient_note = "\tA_len=%s\tB_len=%s" % (fmt_rank(row["rank_a_len"]), fmt_rank(row["rank_b_len"]))
        out.append("Q\t%s\tA=%s\tB=%s\tcat=%s%s\t%s"
                   % (row["cls"], fmt_rank(row["rank_a"]), fmt_rank(row["rank_b"]), cat, lenient_note, row["query"]))
        if cat in WINS:
            wins += 1
        elif cat in LOSSES:
            losses += 1
        else:
            ties += 1
        bc = by_class.setdefault(row["cls"], [0, 0, 0, 0])  # n, wins, losses, ties
        bc[0] += 1
        bc[1] += cat in WINS
        bc[2] += cat in LOSSES
        bc[3] += cat not in WINS and cat not in LOSSES

    for cls in sorted(by_class):
        n, w, l, t = by_class[cls]
        out.append("CLASS\t%s\tn=%d\twins=%d\tlosses=%d\tnet=%+d\tties=%d" % (cls, n, w, l, w - l, t))

    out.append("SUMMARY\tscored=%d\tskipped=%d\twins=%d\tlosses=%d\tnet=%+d\tties=%d"
               % (n_scored, n_skipped, wins, losses, wins - losses, ties))
    out.append("AGG\tr3diff\tscored=%d\tskipped=%d\twins=%d\tlosses=%d\tnet=%+d\tties=%d"
               % (n_scored, n_skipped, wins, losses, wins - losses, ties))
    return "\n".join(out)


def run_r3diff_cli():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--a", help="binary A (baseline)")
    ap.add_argument("--a-ref", help="git ref to build as binary A (mutually exclusive with --a)")
    ap.add_argument("--b", help="binary B (candidate)")
    ap.add_argument("--b-ref", help="git ref to build as binary B (mutually exclusive with --b)")
    ap.add_argument("--repo", default=REPO, help="ripwire source repo, used only to build --a-ref/--b-ref (default: this checkout)")
    ap.add_argument("--queries", required=True, help="frozen query-set TSV (labels_ranking.tsv / labels_recall.tsv / prompts.tsv shape)")
    ap.add_argument("--root", required=True, help="corpus directory both binaries are run against")
    ap.add_argument("--format", choices=("ranking", "recall", "skills"), help="override query-set format auto-detection")
    ap.add_argument("--top-k", type=int, default=20, help="candidate depth for --for-driven lanes (ranking/skills)")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4, help="build parallelism for --a-ref/--b-ref")
    ap.add_argument("--keep-worktrees", action="store_true", help="do not remove scratch worktrees built for --a-ref/--b-ref")
    args = ap.parse_args()

    if bool(args.a) == bool(args.a_ref):
        print("r3diff: pass exactly one of --a / --a-ref", file=sys.stderr)
        return 2
    if bool(args.b) == bool(args.b_ref):
        print("r3diff: pass exactly one of --b / --b-ref", file=sys.stderr)
        return 2

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print("r3diff: --root %s is not a directory" % root, file=sys.stderr)
        return 2

    try:
        qformat = args.format or sniff_format(args.queries)
    except ValueError as e:
        print("r3diff: %s" % e, file=sys.stderr)
        return 1

    try:
        if qformat == "skills":
            rows_in = load_skill_rows(args.queries)
        else:
            rows_in = load_labels(args.queries)
    except (OSError, ValueError) as e:
        print("r3diff: malformed query-set: %s" % e, file=sys.stderr)
        return 1

    resolved = []
    try:
        if args.a:
            a = ResolvedBinary("A", os.path.abspath(args.a), None)
            if not os.access(a.path, os.X_OK):
                print("r3diff: --a %s is not an executable" % a.path, file=sys.stderr)
                return 2
        else:
            a = build_from_ref(args.repo, args.a_ref, args.jobs, "A")
            resolved.append(a)
        if args.b:
            b = ResolvedBinary("B", os.path.abspath(args.b), None)
            if not os.access(b.path, os.X_OK):
                print("r3diff: --b %s is not an executable" % b.path, file=sys.stderr)
                return 2
        else:
            b = build_from_ref(args.repo, args.b_ref, args.jobs, "B")
            resolved.append(b)
    except RuntimeError as e:
        print("r3diff: %s" % e, file=sys.stderr)
        for r in resolved:
            if not args.keep_worktrees:
                cleanup_worktree(args.repo, r)
        return 2

    try:
        if qformat == "skills":
            rows = run_skills(rows_in, a, b, root, args.top_k)
        else:
            rows = run_ranking_or_recall(qformat, rows_in, a, b, root, args.top_k)
    except (RuntimeError, subprocess.TimeoutExpired) as e:
        print("r3diff: a binary invocation failed: %s" % e, file=sys.stderr)
        return 1
    finally:
        if not args.keep_worktrees:
            for r in resolved:
                cleanup_worktree(args.repo, r)

    print(report(rows, a, b, qformat, args.queries, root, args.top_k))
    return 0


if __name__ == "__main__":
    sys.exit(run_r3diff_cli())
