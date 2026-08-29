#!/usr/bin/env python3
"""run_arb.py — Agent Retrieval Bench adapter: ripwire's mapped verbs scored on the ARB tasks.

WHY THIS EXISTS. Agent Retrieval Bench (arXiv 2607.24882) scores repository-context retrieval on
four tasks that are, one for one, the questions ripwire's verb catalog claims to answer:
code2test -> --affected, comment2context -> --for, trace2code -> --from-trace,
edit2ripple -> --impact. The paper's winning vectorless family ("RepoMap") is the family ripwire
belongs to; this harness runs the REAL verbs (not a re-implementation) against the benchmark's own
repo snapshots and scores them with the benchmark's own metric definitions. The registration lives
in docs/EVALS.md ("Agent Retrieval Bench — external loss-first lane"); this file is the instrument
half. It is LOSS-FIRST tooling: its output feeds a loss-bucket report, not a published number.

WHAT IT IS NOT. Not a gate, not wired into test/regression.sh, and not a leaderboard submission.
Nothing here can turn CI red. No number it prints is published anywhere until a fix round completes
and re-measures (the improve-first house rule).

DATA IS PINNED, NOT COMMITTED. Everything under bench/external/arb/ (dataset bundles, bare mirrors,
materialized snapshots, run outputs) is gitignored: the corpus files keep their upstream licences
and are fetched, never vendored. Snapshots are materialized per (repo, base_commit) from full bare
mirrors via `git archive` — the dataset's own chunk corpus ships TRUNCATED file texts (a 725-line
file's "file" chunk carries 242 lines), so indexing the chunk corpus would feed ripwire a mutilated
tree; the benchmark's `candidate_corpus.type` is `repo_at_base_commit` and that is what ripwire gets.
The dataset's chunk texts are still used for one thing: the budget metric (below), where charging
the SAME text the benchmark's own baselines were charged is what makes the number comparable.

RANK COMPOSITION PER TASK — the adapter's one real decision, stated here rather than tuned quietly:
ripwire's verbs return sets/short heads, the benchmark wants a >=20-deep file ranking, so each task
ranks in tiers: the mapped verb's own answer first, then the production task lens (--for --json),
then the plain-BM25 wide map (--query --top-k=200) as tail — later tiers only append files the
earlier tiers did not already rank.
  trace2code:      --from-trace frame/suspect files (innermost-first) | --for | --query
  comment2context: --for | --query                       (given_file stays IN the ranking: the
                   benchmark's own RepoMap down-weights it by -1.0 but does not remove it, and
                   removing it here would manufacture a rank the tool did not earn)
  code2test:       --affected=<changed files> (the query's changed_file OR implementation_files —
                   both spellings ship) returns a SET (alphabetical); it is ordered by each
                   test's rank in the --for/--query lens (unlensed members follow alphabetically),
                   then the lens tiers append the rest
  edit2ripple:     --impact seeded from the symbols named in the anchor_diff's @@ hunk headers
                   (func/def/fn/method name before the paren; seeds capped at 4, resolved as
                   anchor_file:SYM first, bare SYM fallback), files by best rank across seeds |
                   ordered --affected=<anchor_file> tests | --for | --query
  abstention:      --for | --query, scored as refusal-quality (no_gold rows have no gold to rank);
                   the top BM25 score and the routed header are recorded per sample so no-gold vs
                   positive separability can be read from the run output.

METRICS — the benchmark's own definitions, mirrored from its scorer (agent_retrieval_bench/
baseline.py) rather than re-invented: MRR = reciprocal rank of the first gold file over UNIQUE
ranked file paths; Recall@k = |gold ∩ top-k unique files| / |gold|; gold_coverage@8k (the paper's
budgeted-context-yield surface, tau=1 at file grain) walks the ranked files, charges each file's
dataset chunk text at len(text) against a budget of 8000, breaking when the budget would be
exceeded (after at least one chunk), and reports the fraction of gold files seen inside the budget.
Gold files mirror the scorer's target_gold_files (task-specific field fallback chain).

DETERMINISM GATE (registration): --determinism-check runs the first sample of every requested task
twice through the full composition and refuses the sweep (exit 3) on any byte-difference in the
ranked list. Run it before trusting any sweep on a new binary or dataset.

SUBSET DISCLOSURE. The default sweep is the 9-repo stratified subset below (all four tasks, four
languages: Go, Python, Rust, TypeScript; 300 of 427 samples, 202 snapshots) — repos whose full bare
mirrors are cheap enough to hold locally. --repos overrides it (comma-separated), --all-repos lifts
the filter; a sweep beyond the subset must first `git clone --bare` the extra mirrors. Every run
prints how many samples the filter kept, so a subset can never look like the full benchmark.

Usage:
  python3 bench/arb/run_arb.py --bin BIN [--data DIR] [--task T[,T...]] [--limit N]
                               [--sample-id ID] [--determinism-check] [--keep-snapshots]
  RIPWIRE_BIN overrides --bin (gate convention); RIPWIRE_ARB_DATA overrides --data.

Output: per-sample JSONL under <data>/runs/<task>_details.jsonl (ranked files, gold ranks, metrics,
tier provenance per gold hit) and greppable `ARB\t<task>\t<metric>\t<value>` aggregate rows on
stdout — no timestamps, no PIDs, no absolute paths in the report body.

Exit codes: 0 ok, 1 measurement failure (binary crashed on a sample after snapshot OK), 2 setup
error (no binary, no data, no mirror), 3 determinism-check failure.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

TASKS = ("code2test", "comment2context", "trace2code", "edit2ripple", "abstention")

# The stratified default subset: every task covered, four languages, mirrors cheap to hold.
SUBSET_REPOS = (
    "gin-gonic/gin",        # Go
    "caddyserver/caddy",    # Go
    "etcd-io/etcd",         # Go
    "pallets/click",        # Python
    "pytest-dev/pytest",    # Python
    "pypa/pip",             # Python
    "tokio-rs/tokio",       # Rust
    "clap-rs/clap",         # Rust
    "vitejs/vite",          # TypeScript
)

QUERY_CAP = 4000          # chars of query text handed to --for/--query
FOR_TOKEN_BUDGET = 48000  # widens --for's payload so the sigs head is not the 7.5KB default
CONTEXT_BUDGET = 8000     # the benchmark scorer's 8k budget (charged in len(text), as it does)
RECALL_KS = (5, 10, 20)


def fail(msg, code=2):
    sys.stderr.write("run_arb: %s\n" % msg)
    sys.exit(code)


# ---------------------------------------------------------------- dataset

def load_samples(data_dir, task):
    path = os.path.join(data_dir, "extracted", "benchmark", "v2_%s" % task, "samples.jsonl")
    if not os.path.isfile(path):
        fail("missing %s — download + extract the v2_%s bundle first (see bench/arb/ in the EVALS registration)" % (path, task))
    with open(path, encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def target_gold_files(sample):
    """Mirror of the benchmark scorer's target_gold_files fallback chain."""
    gold = sample.get("gold") or {}
    if gold.get("no_gold") is True:
        return []

    def _paths(values):
        out, seen = [], set()
        for value in values or []:
            path = value.get("path") if isinstance(value, dict) else value
            if path and path not in seen:
                seen.add(path)
                out.append(path)
        return out

    explicit = _paths(gold.get("files"))
    if explicit:
        return explicit
    if sample.get("task_type") == "code2test":
        return _paths(gold.get("related_tests"))
    if sample.get("task_type") == "comment2context":
        context = _paths(gold.get("must_context_files") or gold.get("context_files"))
        if context:
            return context
    root = _paths(gold.get("root_cause_files"))
    return root or _paths(gold.get("related_tests"))


def chunk_text_index(data_dir, task, repo, base_commit):
    """path -> dataset 'file' chunk text, for budget charging at parity with the shipped baselines."""
    name = repo.replace("/", "__")
    path = os.path.join(data_dir, "extracted", "corpus", "v2_%s" % task, name, "%s.chunks.jsonl" % base_commit)
    index = {}
    if not os.path.isfile(path):
        return index
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            row = json.loads(line)
            if row.get("kind") == "file":
                index[row.get("path", "")] = str(row.get("text", ""))
    return index


# ---------------------------------------------------------------- snapshots

def snapshot_key(repo, sha):
    return "%s__%s" % (repo.replace("/", "__"), sha[:12])


def materialize(data_dir, repo, sha):
    mirror = os.path.join(data_dir, "mirrors", "%s.git" % repo.replace("/", "_"))
    if not os.path.isdir(mirror):
        fail("no bare mirror at %s — clone it first (git clone --bare https://github.com/%s.git)" % (mirror, repo))
    dest = os.path.join(data_dir, "snapshots", snapshot_key(repo, sha))
    if os.path.isdir(dest):
        return dest
    os.makedirs(dest)
    archive = subprocess.Popen(["git", "-C", mirror, "archive", sha], stdout=subprocess.PIPE)
    extract = subprocess.run(["tar", "-x", "-C", dest], stdin=archive.stdout)
    archive.stdout.close()
    if archive.wait() != 0 or extract.returncode != 0:
        shutil.rmtree(dest, ignore_errors=True)
        return None  # commit not in mirror (rewritten upstream) — recorded, never silently scored
    return dest


def drop_snapshot(data_dir, repo, sha):
    dest = os.path.join(data_dir, "snapshots", snapshot_key(repo, sha))
    shutil.rmtree(dest, ignore_errors=True)


# ---------------------------------------------------------------- ripwire invocation + parsing

def run_bin(bin_path, snap, args, stdin_text=None):
    proc = subprocess.run([bin_path, snap] + args, capture_output=True, text=True,
                          input=stdin_text, timeout=600)
    return proc.returncode, proc.stdout, proc.stderr


def norm_path(path, snap):
    path = path.strip()
    prefix = snap.rstrip("/") + "/"
    if path.startswith(prefix):
        path = path[len(prefix):]
    if path.startswith("./"):
        path = path[2:]
    return path.split(":", 1)[0] if re.search(r":\d+(-\d+)?$", path) else path


def for_files(bin_path, snap, query):
    """--for --json: files in sigs order (ripwire's own best-symbol file grouping)."""
    code, out, _err = run_bin(bin_path, snap, ["--for=%s" % query[:QUERY_CAP], "--json",
                                              "--token-budget=%d" % FOR_TOKEN_BUDGET])
    if code != 0 or not out:
        return []
    try:
        doc = json.loads(out)
    except ValueError:
        return []
    return [norm_path(f.get("p", ""), snap) for f in doc.get("sigs", []) if f.get("p")]


FILE_GROUP_RE = re.compile(r'<f p="([^"]+)"')


def query_files(bin_path, snap, query, top_k=200):
    """--query (plain BM25 map, XML): file groups in document order = important-first."""
    code, out, _err = run_bin(bin_path, snap, ["--query=%s" % query[:QUERY_CAP], "--top-k=%d" % top_k])
    if code != 0 or not out:
        return []
    return [norm_path(m, snap) for m in FILE_GROUP_RE.findall(out)]


FRAME_RE = re.compile(r'<frame[^>]*? p="([^"]+)"')


def trace_files(bin_path, snap, trace_text):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as tmp:
        tmp.write(trace_text)
        tmp_path = tmp.name
    try:
        code, out, _err = run_bin(bin_path, snap, ["--from-trace=%s" % tmp_path])
    finally:
        os.unlink(tmp_path)
    if code != 0 or not out:
        return []
    ranked = [norm_path(m, snap) for m in FRAME_RE.findall(out)]
    ranked += [norm_path(m, snap) for m in FILE_GROUP_RE.findall(out)]
    return ranked


TEST_RE = re.compile(r'<test p="([^"]+)"')


def affected_tests(bin_path, snap, changed_file):
    code, out, _err = run_bin(bin_path, snap, ["--affected=%s" % changed_file])
    if code != 0 or not out:
        return []
    return [norm_path(m, snap) for m in TEST_RE.findall(out)]


def impact_files(bin_path, snap, seeds):
    """Best rank per file across --impact runs of each seed symbol."""
    best = {}
    for seed in seeds:
        code, out, _err = run_bin(bin_path, snap, ["--impact=%s" % seed, "--json", "--limit=200"])
        if code != 0 or not out:
            continue
        try:
            doc = json.loads(out)
        except ValueError:
            continue
        for rank, row in enumerate(doc.get("impact", [])):
            path = norm_path(row.get("p", ""), snap)
            if path and (path not in best or rank < best[path]):
                best[path] = rank
    return [path for path, _rank in sorted(best.items(), key=lambda kv: (kv[1], kv[0]))]


HUNK_SYMBOL_RE = re.compile(
    r"@@[^@\n]*@@[^\n]*?(?:func|def|fn|class|impl|pub fn|function)\s+(?:\([^)]*\)\s*)?([A-Za-z_][A-Za-z0-9_]*)")


def diff_seed_symbols(anchor_diff, anchor_file, cap=4):
    seeds, seen = [], set()
    for name in HUNK_SYMBOL_RE.findall(anchor_diff or ""):
        if name not in seen:
            seen.add(name)
            seeds.append("%s:%s" % (anchor_file, name) if anchor_file else name)
        if len(seeds) >= cap:
            break
    return seeds


# ---------------------------------------------------------------- rank composition

def merge_tiers(*tiers):
    ranked, seen = [], set()
    provenance = {}
    for tier_name, files in tiers:
        for path in files:
            if path and path not in seen:
                seen.add(path)
                ranked.append(path)
                provenance[path] = tier_name
    return ranked, provenance


def compose_ranking(task, sample, bin_path, snap):
    query_obj = sample.get("query") or {}
    if task == "trace2code":
        trace_text = "%s\n%s" % (query_obj.get("command", ""), query_obj.get("failure_excerpt", ""))
        lens_query = one_line(query_obj.get("failure_excerpt", ""))
        return merge_tiers(("from-trace", trace_files(bin_path, snap, trace_text)),
                           ("for", for_files(bin_path, snap, lens_query)),
                           ("query", query_files(bin_path, snap, lens_query)))
    if task == "comment2context":
        lens_query = one_line(" ".join(str(query_obj.get(k, "")) for k in
                                       ("pr_title", "path", "review_comment", "diff_hunk_context")))
        return merge_tiers(("for", for_files(bin_path, snap, lens_query)),
                           ("query", query_files(bin_path, snap, lens_query)))
    if task == "code2test":
        changed = changed_files(query_obj)
        lens_query = one_line("%s %s %s" % (query_obj.get("pr_title", ""), " ".join(changed),
                                            query_obj.get("pr_body", "")))
        tests = affected_tests(bin_path, snap, ",".join(changed)) if changed else []
        lens = for_files(bin_path, snap, lens_query)
        wide = query_files(bin_path, snap, lens_query)
        return merge_tiers(("affected", ordered_by_lens(tests, lens, wide)),
                           ("for", lens), ("query", wide))
    if task == "edit2ripple":
        anchor = query_obj.get("anchor_file", "")
        seeds = diff_seed_symbols(query_obj.get("anchor_diff", ""), anchor)
        lens_query = one_line("%s %s" % (query_obj.get("intent", ""), anchor))
        lens = for_files(bin_path, snap, lens_query)
        wide = query_files(bin_path, snap, lens_query)
        tests = affected_tests(bin_path, snap, anchor) if anchor else []
        return merge_tiers(("impact", impact_files(bin_path, snap, seeds)),
                           ("affected", ordered_by_lens(tests, lens, wide)),
                           ("for", lens), ("query", wide))
    # abstention
    lens_query = one_line(str(query_obj.get("text", "")))
    return merge_tiers(("for", for_files(bin_path, snap, lens_query)),
                       ("query", query_files(bin_path, snap, lens_query)))


def one_line(text):
    return re.sub(r"\s+", " ", text or "").strip()


def ordered_by_lens(tests, lens, wide):
    """--affected returns a SET (alphabetical); order it by each member's lens rank, alpha tail."""
    lens_rank = {p: i for i, p in enumerate(lens + [p for p in wide if p not in lens])}
    return sorted(tests, key=lambda p: (lens_rank.get(p, len(lens_rank)), p))


def changed_files(query_obj):
    """code2test names its changed files as `changed_file` (str) OR `implementation_files` (list) —
    78 of the 106 shipped samples use the list form; reading only the scalar silently unseeds
    --affected for all of them (found the hard way: vite MRR 0.009 in the first sweep)."""
    single = query_obj.get("changed_file")
    if isinstance(single, str) and single:
        return [single]
    values = query_obj.get("implementation_files")
    if isinstance(values, str):
        values = [v.strip(" '\"") for v in values.strip("[]").split(",")]
    return [v for v in (values or []) if v]


# ---------------------------------------------------------------- scoring (the benchmark's own definitions)

def score_sample(gold_files, ranked_files, chunk_texts):
    gold = set(gold_files)
    metrics = {}
    if gold:
        metrics["MRR"] = next((1.0 / i for i, p in enumerate(ranked_files, 1) if p in gold), 0.0)
        for k in RECALL_KS:
            metrics["Recall@%d" % k] = len(gold & set(ranked_files[:k])) / len(gold)
        used, covered = 0, set()
        for path in ranked_files:
            text = chunk_texts.get(path, "")
            if used + len(text) > CONTEXT_BUDGET and used > 0:
                break
            used += len(text)
            if path in gold:
                covered.add(path)
        metrics["gold_coverage@8k"] = len(covered) / len(gold)
    return metrics


# ---------------------------------------------------------------- driver

def sweep(args, bin_path, data_dir, task, samples):
    details_dir = os.path.join(data_dir, "runs")
    os.makedirs(details_dir, exist_ok=True)
    details_path = os.path.join(details_dir, "%s_details.jsonl" % task)
    aggregates, evaluated, skipped_snapshots = {}, 0, 0

    by_snapshot = {}
    for sample in samples:
        by_snapshot.setdefault((sample["repo"], sample["base_commit"]), []).append(sample)

    with open(details_path, "w", encoding="utf-8") as out:
        for (repo, sha), group in sorted(by_snapshot.items()):
            snap = materialize(data_dir, repo, sha)
            if snap is None:
                skipped_snapshots += 1
                for sample in group:
                    out.write(json.dumps({"sample_id": sample["id"], "repo": repo,
                                          "base_commit": sha, "skipped": "commit_not_in_mirror"}) + "\n")
                continue
            chunks = chunk_text_index(data_dir, task, repo, sha)
            for sample in group:
                ranked, provenance = compose_ranking(task, sample, bin_path, snap)
                gold = target_gold_files(sample)
                metrics = score_sample(gold, ranked, chunks)
                ranks = {g: (ranked.index(g) + 1 if g in ranked else None) for g in gold}
                row = {"sample_id": sample["id"], "repo": repo, "base_commit": sha,
                       "task_type": sample.get("task_type"), "gold_files": gold,
                       "gold_ranks": ranks,
                       "gold_tiers": {g: provenance.get(g) for g in gold if g in provenance},
                       "no_gold": (sample.get("gold") or {}).get("no_gold", False),
                       "abstention_reason": (sample.get("gold") or {}).get("reason"),
                       "ranked_files": ranked[:60], "ranked_total": len(ranked),
                       "metrics": metrics}
                out.write(json.dumps(row, sort_keys=True) + "\n")
                evaluated += 1
                for key, value in metrics.items():
                    aggregates.setdefault(key, []).append(value)
            if not args.keep_snapshots:
                drop_snapshot(data_dir, repo, sha)

    print("ARB\t%s\tevaluated\t%d" % (task, evaluated))
    print("ARB\t%s\tskipped_snapshots\t%d" % (task, skipped_snapshots))
    for key in sorted(aggregates):
        values = aggregates[key]
        print("ARB\t%s\t%s\t%.4f" % (task, key, sum(values) / len(values)))
    print("ARB\t%s\tdetails\t%s" % (task, os.path.relpath(details_path, REPO)))


def determinism_check(args, bin_path, data_dir, task, samples):
    if not samples:
        return True
    sample = samples[0]
    snap = materialize(data_dir, sample["repo"], sample["base_commit"])
    if snap is None:
        print("ARB\t%s\tdeterminism\tSKIP (first sample's commit not in mirror)" % task)
        return True
    first, _ = compose_ranking(task, sample, bin_path, snap)
    second, _ = compose_ranking(task, sample, bin_path, snap)
    if not args.keep_snapshots:
        drop_snapshot(data_dir, sample["repo"], sample["base_commit"])
    same = json.dumps(first) == json.dumps(second)
    print("ARB\t%s\tdeterminism\t%s" % (task, "OK" if same else "FAIL"))
    return same


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bin", default=os.environ.get("RIPWIRE_BIN", "ripwire"))
    parser.add_argument("--data", default=os.environ.get("RIPWIRE_ARB_DATA",
                                                         os.path.join(REPO, "bench", "external", "arb")))
    parser.add_argument("--task", default=",".join(TASKS),
                        help="comma-separated subset of: %s" % ", ".join(TASKS))
    parser.add_argument("--repos", default=",".join(SUBSET_REPOS),
                        help="comma-separated repo filter (the disclosed default subset)")
    parser.add_argument("--all-repos", action="store_true", help="lift the repo filter entirely")
    parser.add_argument("--limit", type=int, default=0, help="first N samples per task (0 = all)")
    parser.add_argument("--sample-id", default="", help="run exactly one sample by id")
    parser.add_argument("--determinism-check", action="store_true",
                        help="run each task's first sample twice; exit 3 on any ranking mismatch")
    parser.add_argument("--keep-snapshots", action="store_true",
                        help="keep materialized snapshots on disk after their samples ran")
    args = parser.parse_args()

    bin_path = shutil.which(args.bin) or (args.bin if os.path.isfile(args.bin) else None)
    if bin_path is None:
        fail("binary not found: %s" % args.bin)
    if not os.path.isdir(args.data):
        fail("data dir not found: %s (download the bundles first — see the EVALS registration)" % args.data)

    tasks = [t.strip() for t in args.task.split(",") if t.strip()]
    for task in tasks:
        if task not in TASKS:
            fail("unknown task %r — expected one of %s" % (task, ", ".join(TASKS)))

    repo_filter = None if args.all_repos else {r.strip() for r in args.repos.split(",") if r.strip()}
    ok = True
    for task in tasks:
        samples = load_samples(args.data, task)
        total = len(samples)
        if repo_filter is not None:
            samples = [s for s in samples if s["repo"] in repo_filter]
        if args.sample_id:
            samples = [s for s in samples if s["id"] == args.sample_id]
        if args.limit:
            samples = samples[:args.limit]
        print("ARB\t%s\tsamples\t%d of %d%s" % (task, len(samples), total,
                                                "" if repo_filter is None else " (repo subset)"))
        if args.determinism_check:
            ok = determinism_check(args, bin_path, args.data, task, samples) and ok
        else:
            sweep(args, bin_path, args.data, task, samples)
    if not ok:
        sys.exit(3)


if __name__ == "__main__":
    main()
