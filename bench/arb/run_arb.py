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
import collections
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


def run_bin_or_none(bin_path, snap, cli_args, stdin_text=None):
    """The one guard every parser below repeats: run the binary, and hand back its stdout only
    on a clean exit with non-empty output — None on a crash, a timeout, or silence, so a missing
    signal reads as missing rather than as an empty ranking."""
    code, out, _err = run_bin(bin_path, snap, cli_args, stdin_text=stdin_text)
    return out if code == 0 and out else None


def for_json(bin_path, snap, query):
    """--for --json, parsed once. The single source of both the file ranking AND the
    confidence=/margin_pct= root facts (arXiv 2607.24882's abstention axis) — one call serves
    both so the calibration lane below spends no extra invocation over the parent lane's tiers."""
    out = run_bin_or_none(bin_path, snap, ["--for=%s" % query[:QUERY_CAP], "--json",
                                           "--token-budget=%d" % FOR_TOKEN_BUDGET])
    if out is None:
        return None
    try:
        return json.loads(out)
    except ValueError:
        return None


def for_files_from_doc(doc, snap):
    """files in sigs order (ripwire's own best-symbol file grouping) from an already-parsed doc."""
    if doc is None:
        return []
    # instrument v2 (2026-08-29): sigs rows now carry the per-symbol rank fact "r"; file order is
    # best-symbol rank when present (document order untouched otherwise), and the file-grain
    # "tail" extends the depth after the head — both surfaces registered in EVALS before re-measure.
    groups = [g for g in doc.get("sigs", []) if g.get("p")]
    def best_rank(g):
        ranks = [s_["r"] for s_ in g.get("symbols") or [] if isinstance(s_.get("r"), int)]
        return min(ranks) if ranks else float("inf")
    if any(best_rank(g) != float("inf") for g in groups):
        groups = sorted(groups, key=best_rank)
    ranked = [norm_path(g.get("p", ""), snap) for g in groups]
    seen = set(ranked)
    for t in (doc.get("tail") or {}).get("files") or []:
        tp = norm_path(t, snap)
        if tp not in seen:
            seen.add(tp)
            ranked.append(tp)
    return ranked


def for_confidence_from_doc(doc):
    """The two facts deriveForConfidence ships on every --for --json root: confidence is
    "high"/"low", margin_pct an int 0-100 (always 0 when confidence=="low" — see the EVALS
    abstention-calibration registration). None/None when the call failed or returned no doc,
    recorded as signal_missing by callers rather than silently coerced to a value."""
    if doc is None:
        return {"confidence": None, "margin_pct": None}
    return {"confidence": doc.get("confidence"), "margin_pct": doc.get("margin_pct")}


FILE_GROUP_RE = re.compile(r'<f p="([^"]+)"')


def query_files(bin_path, snap, query, top_k=200):
    """--query (plain BM25 map, XML): file groups in document order = important-first."""
    out = run_bin_or_none(bin_path, snap, ["--query=%s" % query[:QUERY_CAP], "--top-k=%d" % top_k])
    return [norm_path(m, snap) for m in FILE_GROUP_RE.findall(out)] if out is not None else []


FRAME_RE = re.compile(r'<frame[^>]*? p="([^"]+)"')
HOP_RE = re.compile(r'<hop [^>]*?p="([^"]+)"')


def trace_files(bin_path, snap, trace_text):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as tmp:
        tmp.write(trace_text)
        tmp_path = tmp.name
    try:
        out = run_bin_or_none(bin_path, snap, ["--from-trace=%s" % tmp_path])
    finally:
        os.unlink(tmp_path)
    if out is None:
        return []
    frames = [norm_path(m, snap) for m in FRAME_RE.findall(out)]
    # instrument v2 (2026-08-29): the binary's test-to-source hop rows are served beside the
    # innermost frame (the emitted legend states the served order), so the composition splices
    # them after frame 1 — faithful reading of the disclosed serving, registered in EVALS.
    hops = [norm_path(m, snap) for m in HOP_RE.findall(out)]
    ranked = frames[:1] + hops + frames[1:]
    ranked += [norm_path(m, snap) for m in FILE_GROUP_RE.findall(out)]
    return ranked


TEST_RE = re.compile(r'<test p="([^"]+)"')


def affected_tests(bin_path, snap, changed_file):
    out = run_bin_or_none(bin_path, snap, ["--affected=%s" % changed_file])
    return [norm_path(m, snap) for m in TEST_RE.findall(out)] if out is not None else []


def impact_files(bin_path, snap, seeds):
    """Best rank per file across --impact runs of each seed symbol."""
    best = {}
    for seed in seeds:
        out = run_bin_or_none(bin_path, snap, ["--impact=%s" % seed, "--json", "--limit=200"])
        if out is None:
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
    """Returns (ranked_files, tier_provenance, confidence_facts). confidence_facts is
    for_confidence_from_doc's dict, read from the SAME --for --json call already made as one of
    the task's tiers — no extra invocation per sample, and the abstention-calibration lane below
    reuses it verbatim for every task, not just the abstention task."""
    query_obj = sample.get("query") or {}
    if task == "trace2code":
        trace_text = "%s\n%s" % (query_obj.get("command", ""), query_obj.get("failure_excerpt", ""))
        lens_query = one_line(query_obj.get("failure_excerpt", ""))
        doc = for_json(bin_path, snap, lens_query)
        ranked, provenance = merge_tiers(("from-trace", trace_files(bin_path, snap, trace_text)),
                                         ("for", for_files_from_doc(doc, snap)),
                                         ("query", query_files(bin_path, snap, lens_query)))
        return ranked, provenance, for_confidence_from_doc(doc)
    if task == "comment2context":
        lens_query = one_line(" ".join(str(query_obj.get(k, "")) for k in
                                       ("pr_title", "path", "review_comment", "diff_hunk_context")))
        doc = for_json(bin_path, snap, lens_query)
        ranked, provenance = merge_tiers(("for", for_files_from_doc(doc, snap)),
                                         ("query", query_files(bin_path, snap, lens_query)))
        return ranked, provenance, for_confidence_from_doc(doc)
    if task == "code2test":
        changed = changed_files(query_obj)
        lens_query = one_line("%s %s %s" % (query_obj.get("pr_title", ""), " ".join(changed),
                                            query_obj.get("pr_body", "")))
        tests = affected_tests(bin_path, snap, ",".join(changed)) if changed else []
        doc = for_json(bin_path, snap, lens_query)
        lens = for_files_from_doc(doc, snap)
        wide = query_files(bin_path, snap, lens_query)
        ranked, provenance = merge_tiers(("affected", ordered_by_lens(tests, lens, wide)),
                                         ("for", lens), ("query", wide))
        return ranked, provenance, for_confidence_from_doc(doc)
    if task == "edit2ripple":
        anchor = query_obj.get("anchor_file", "")
        seeds = diff_seed_symbols(query_obj.get("anchor_diff", ""), anchor)
        lens_query = one_line("%s %s" % (query_obj.get("intent", ""), anchor))
        doc = for_json(bin_path, snap, lens_query)
        lens = for_files_from_doc(doc, snap)
        wide = query_files(bin_path, snap, lens_query)
        tests = affected_tests(bin_path, snap, anchor) if anchor else []
        ranked, provenance = merge_tiers(("impact", impact_files(bin_path, snap, seeds)),
                                         ("affected", ordered_by_lens(tests, lens, wide)),
                                         ("for", lens), ("query", wide))
        return ranked, provenance, for_confidence_from_doc(doc)
    # abstention
    lens_query = one_line(str(query_obj.get("text", "")))
    doc = for_json(bin_path, snap, lens_query)
    ranked, provenance = merge_tiers(("for", for_files_from_doc(doc, snap)),
                                     ("query", query_files(bin_path, snap, lens_query)))
    return ranked, provenance, for_confidence_from_doc(doc)


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

# task_of(sample) resolves the per-sample verb-mapping key: a constant for a plain TASKS sweep
# (every sample already IS that task), sample["task_type"] for a selective split (each row keeps
# its own source task). It doubles as the chunk-corpus subdir (chunk_text_index's own "task" arg)
# because the two are the same string in both cases.
#
# extra_fields(sample) supplies the two dataset families' different ground-truth annotation: plain
# tasks carry gold.no_gold/reason; the selective splits (registered below) carry
# metadata.selective_label in {"positive", "no_gold"} instead.

def plain_task_extra_fields(sample):
    gold = sample.get("gold") or {}
    return {"no_gold": gold.get("no_gold", False), "abstention_reason": gold.get("reason")}


def selective_extra_fields(sample):
    return {"selective_label": (sample.get("metadata") or {}).get("selective_label")}


# Bundles the two things that differ between a plain-task sweep and a selective-split sweep, so
# sweep()/determinism_check() take one extra argument instead of two.
RunSpec = collections.namedtuple("RunSpec", ["task_of", "extra_fields"])


def sweep(args, bin_path, data_dir, name, samples, spec):
    details_dir = os.path.join(data_dir, "runs")
    os.makedirs(details_dir, exist_ok=True)
    details_path = os.path.join(details_dir, "%s_details.jsonl" % name)
    aggregates, evaluated, skipped_snapshots = {}, 0, 0
    chunk_cache = {}

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
            for sample in group:
                task = spec.task_of(sample)
                cache_key = (task, repo, sha)
                if cache_key not in chunk_cache:
                    chunk_cache[cache_key] = chunk_text_index(data_dir, task, repo, sha)
                ranked, provenance, confidence = compose_ranking(task, sample, bin_path, snap)
                gold = target_gold_files(sample)
                metrics = score_sample(gold, ranked, chunk_cache[cache_key])
                ranks = {g: (ranked.index(g) + 1 if g in ranked else None) for g in gold}
                row = {"sample_id": sample["id"], "repo": repo, "base_commit": sha, "task_type": task,
                       "gold_files": gold, "gold_ranks": ranks,
                       "gold_tiers": {g: provenance.get(g) for g in gold if g in provenance},
                       "ranked_files": ranked[:60], "ranked_total": len(ranked),
                       "confidence": confidence["confidence"], "margin_pct": confidence["margin_pct"],
                       "metrics": metrics}
                row.update(spec.extra_fields(sample))
                out.write(json.dumps(row, sort_keys=True) + "\n")
                evaluated += 1
                for key, value in metrics.items():
                    aggregates.setdefault(key, []).append(value)
            if not args.keep_snapshots:
                drop_snapshot(data_dir, repo, sha)

    print("ARB\t%s\tevaluated\t%d" % (name, evaluated))
    print("ARB\t%s\tskipped_snapshots\t%d" % (name, skipped_snapshots))
    for key in sorted(aggregates):
        values = aggregates[key]
        print("ARB\t%s\t%s\t%.4f" % (name, key, sum(values) / len(values)))
    print("ARB\t%s\tdetails\t%s" % (name, os.path.relpath(details_path, REPO)))


def determinism_check(args, bin_path, data_dir, name, samples, task_of):
    if not samples:
        return True
    sample = samples[0]
    snap = materialize(data_dir, sample["repo"], sample["base_commit"])
    if snap is None:
        print("ARB\t%s\tdeterminism\tSKIP (first sample's commit not in mirror)" % name)
        return True
    task = task_of(sample)
    first, _, first_conf = compose_ranking(task, sample, bin_path, snap)
    second, _, second_conf = compose_ranking(task, sample, bin_path, snap)
    if not args.keep_snapshots:
        drop_snapshot(data_dir, sample["repo"], sample["base_commit"])
    same = (json.dumps(first) == json.dumps(second)
            and json.dumps(first_conf, sort_keys=True) == json.dumps(second_conf, sort_keys=True))
    print("ARB\t%s\tdeterminism\t%s" % (name, "OK" if same else "FAIL"))
    return same


# ---------------------------------------------------------------- selective splits (abstention calibration)
#
# The docs/EVALS.md "Agent Retrieval Bench — abstention calibration round" registration governs this
# section: it names the verdict rule, the datasets/n, the metrics and the bands BEFORE any row here
# was scored. v2_selective_retrieval_{natural,balanced} mix the four positive tasks' own rows with
# the no_gold rows (task_type=="abstention") into one samples.jsonl per split — same path shape as
# load_samples's TASKS ("extracted/benchmark/v2_<name>/samples.jsonl"), so no separate loader is
# needed. compose_ranking already reads a --for --json doc as one of every task's tiers, so the
# confidence facts the calibration score reuses come from that SAME call — no query invented here.

SELECTIVE_SPLITS = ("selective_retrieval_natural", "selective_retrieval_balanced")


def parse_names(raw, valid, label):
    """--task/--split's shared shape: comma-separated, validated against a fixed vocabulary."""
    names = [n.strip() for n in raw.split(",") if n.strip()]
    for name in names:
        if name not in valid:
            fail("unknown %s %r — expected one of %s" % (label, name, ", ".join(valid)))
    return names


def build_runs(tasks, splits):
    """(name, loader, RunSpec) per requested task/split. A plain task is fixed-task-for-every-row;
    a selective split resolves its task per-row from the sample's own task_type. Both use the same
    loader (load_samples: the two bundle families share one path shape) and the same sweep/
    determinism_check — only the RunSpec differs."""
    runs = [(task, load_samples, RunSpec((lambda t: (lambda s: t))(task), plain_task_extra_fields))
            for task in tasks]
    runs += [(split, load_samples, RunSpec(lambda s: s.get("task_type"), selective_extra_fields))
             for split in splits]
    return runs


def filter_samples(args, samples, repo_filter):
    if repo_filter is not None:
        samples = [s for s in samples if s["repo"] in repo_filter]
    if args.sample_id:
        samples = [s for s in samples if s["id"] == args.sample_id]
    if args.limit:
        samples = samples[:args.limit]
    return samples


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bin", default=os.environ.get("RIPWIRE_BIN", "ripwire"))
    parser.add_argument("--data", default=os.environ.get("RIPWIRE_ARB_DATA",
                                                         os.path.join(REPO, "bench", "external", "arb")))
    parser.add_argument("--task", default=",".join(TASKS),
                        help="comma-separated subset of: %s" % ", ".join(TASKS))
    parser.add_argument("--split", default="",
                        help="comma-separated selective splits to also/instead run: %s "
                             "(abstention-calibration lane; empty = none)" % ", ".join(SELECTIVE_SPLITS))
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

    tasks = parse_names(args.task, TASKS, "task")
    splits = parse_names(args.split, SELECTIVE_SPLITS, "split")
    repo_filter = None if args.all_repos else {r.strip() for r in args.repos.split(",") if r.strip()}

    ok = True
    for name, loader, spec in build_runs(tasks, splits):
        samples = loader(args.data, name)
        total = len(samples)
        samples = filter_samples(args, samples, repo_filter)
        print("ARB\t%s\tsamples\t%d of %d%s" % (name, len(samples), total,
                                                "" if repo_filter is None else " (repo subset)"))
        if args.determinism_check:
            ok = determinism_check(args, bin_path, args.data, name, samples, spec.task_of) and ok
        else:
            sweep(args, bin_path, args.data, name, samples, spec)
    if not ok:
        sys.exit(3)


if __name__ == "__main__":
    main()
