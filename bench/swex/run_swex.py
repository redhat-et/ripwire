#!/usr/bin/env python3
"""SWE-Explore adapter — the two ripwire explorer arms, registered in docs/EVALS.md
("SWE-Explore exploration lane (2026-08-28)").

Arms (both single-invocation uses of the shipped binary on the instance's snapshot):
  FOR   ripwire <snapshot> --for="<issue>" --json     -> sigs section, document order
  PACK  ripwire <snapshot> --pack-task="<issue>" --json -> ranking section then far section,
                                                          document order

Symbol -> region: p= and l= from the ranked row; end line from the symbol's own body extent,
obtained with chunked --expand calls (selector = canonical id when present, else FILE:NAME).
A row whose expand returns no body becomes the single-line region (p, l, l) — counted in the
prediction record (n_sig_only), never dropped. Regions are deduplicated (highest rank wins)
and the ranked list is cut at --budget cumulative lines (a straddling region is kept whole,
matching the scorer's own budget semantics).

The scorer of record is the benchmark's own eval.py (ExploreEvaluator), imported unmodified
from the untracked clone under --data-dir. LOSS-FIRST: numbers produced here are local
loss-bucket inputs, not publishable comparatives (docs/EVALS.md registration).

Data layout (untracked, gitignored — see .gitignore "/bench/external/"):
  <data-dir>/bench.final.public.jsonl   ground truth (848 rows; HF SWE-Explore-Bench)
  <data-dir>/upstream_meta.json         instance_id -> {repo, base_commit, problem_statement}
  <data-dir>/subset.json                the registered stratified subset
  <data-dir>/snapshots/<instance_id>/   repo checked out at base_commit
  <data-dir>/SWE-Explore-Bench/         benchmark code clone (MIT; eval.py = scorer)

Usage:
  run_swex.py predict --bin BIN --data-dir DIR [--arm for|pack|both] [--budget 500]
                      [--instances id1,id2] [--out-suffix S]
  run_swex.py score   --data-dir DIR [--arm for|pack|both]
  run_swex.py determinism --bin BIN --data-dir DIR --instance ID
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

BUDGET_DEFAULT = 500
EXPAND_CHUNK = 3          # small chunks: the expand pack-budget caps bodies rank-first
MAX_RANKED_ROWS = 120     # safety cap on rows fed to extent resolution

METRICS = [
    "precision", "recall", "f1_score", "hit_file_rate", "noise_file_rate",
    "hit_region_rate", "noise_region_rate", "weighted_core_coverage",
    "context_efficiency", "optional_coverage", "first_useful_hit",
    "ndcg_at_100", "ndcg_at_300", "ndcg_at_500",
    "recall_at_100", "recall_at_300", "recall_at_500",
]


def run_binary(bin_path, snapshot, args, timeout=600):
    """Run ripwire foreground; stdout as text (errors='replace' — foreign repos)."""
    proc = subprocess.run(
        [str(bin_path), str(snapshot)] + args,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=timeout,
    )
    return proc.returncode, proc.stdout.decode("utf-8", errors="replace")


def flatten_ranked(file_groups):
    """[{p, symbols:[{l,n,id?...}]}] -> [(p, n, l, id_or_None)] in document order."""
    out = []
    for grp in file_groups or []:
        p = grp.get("p")
        for s in grp.get("symbols") or []:
            if p is None or "l" not in s or "n" not in s:
                continue
            out.append((p, s["n"], int(s["l"]), s.get("id")))
    return out


def ranked_rows_for_arm(bin_path, snapshot, issue, arm):
    """Invoke the arm; return ranked (p, n, l, id) rows in served (document) order."""
    flag = "--for=" if arm == "for" else "--pack-task="
    rc, out = run_binary(bin_path, snapshot, [flag + issue, "--json"])
    if rc != 0 or not out.strip():
        return None, f"exit={rc}"
    try:
        doc = json.loads(out)
    except json.JSONDecodeError as e:
        return None, f"json:{e}"
    if arm == "for":
        rows = flatten_ranked(doc.get("sigs"))
    else:
        rows = flatten_ranked(doc.get("ranking"))
        # the far section is part of the served ranking (ranked-but-over-1-hop);
        # its rows carry p="path:line"
        for far in doc.get("far") or []:
            p = far.get("p", "")
            n = far.get("n")
            m = re.match(r"^(.*):(\d+)$", p)
            if n and m:
                rows.append((m.group(1), n, int(m.group(2)), None))
    return rows[:MAX_RANKED_ROWS], None


CDATA_SPLIT = "]]]]><![CDATA[>"  # appendCdataSafe's escape for a literal "]]>"


def parse_expand_bodies(out):
    """<bodies>...<b l= p= n= ...><![CDATA[body]]></b>... -> {(p, n): [(l, nlines)]}"""
    result = {}
    for m in re.finditer(r"<b ([^>]*)>", out):
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        if "l" not in attrs or "p" not in attrs or "n" not in attrs:
            continue
        rest = out[m.end():]
        close = rest.find("</b>")
        if close < 0:
            continue
        inner = rest[:close]
        cs = inner.find("<![CDATA[")
        ce = inner.rfind("]]>")
        if cs < 0 or ce < 0 or ce <= cs:
            continue
        body = inner[cs + len("<![CDATA["):ce].replace(CDATA_SPLIT, "]]>")
        key = (attrs["p"], attrs["n"])
        result.setdefault(key, []).append((int(attrs["l"]), body.count("\n") + 1))
    return result


def expand_chunk(bin_path, snapshot, chunk, timeout=90):
    """One --expand call for `chunk` rows -> ({(p, n, l): end_line}, timed_out).

    The timeout guards against pathological expands (symbols ranked inside vendored /
    minified bundles, e.g. .yarn/releases/*.cjs); the caller poisons the offending path.
    """
    selectors = [sid if sid else f"{p}:{n}" for p, n, l, sid in chunk]
    try:
        rc, out = run_binary(bin_path, snapshot,
                             ["--expand=" + ",".join(selectors)], timeout=timeout)
    except subprocess.TimeoutExpired:
        return {}, True
    if rc != 0:
        return {}, False
    bodies = parse_expand_bodies(out)
    extents = {}
    for p, n, l, _sid in chunk:
        cands = bodies.get((p, n))
        if not cands:
            continue
        # several defs of the name in the file: take the one whose start is closest
        best = min(cands, key=lambda t: abs(t[0] - l))
        extents[(p, n, l)] = best[0] + best[1] - 1
    return extents, False


def build_regions(bin_path, snapshot, rows, budget):
    """Ranked rows -> deduped (path, start, end) regions cut at `budget` cumulative lines.

    Streaming: extents resolve in small chunks in rank order and stop at the budget, so
    the expand call's own pack-budget cap never starves the rows that matter. A row whose
    chunk lost it to that cap is retried alone; only a genuinely body-less row (or an
    expand timeout) falls back to the single-line region (l, l), counted in n_sig_only.
    """
    regions, seen, n_sig_only, cum = [], set(), 0, 0
    bad_paths = set()  # paths whose expand timed out once: their rows go single-line
    i = 0
    while i < len(rows) and cum < budget:
        window = rows[i:i + EXPAND_CHUNK]
        chunk = [r for r in window if r[0] not in bad_paths]
        i += EXPAND_CHUNK
        extents = {} if not chunk else expand_chunk(bin_path, snapshot, chunk)[0]
        for row in window:
            p, n, l, _sid = row
            end = extents.get((p, n, l))
            if end is None and p not in bad_paths and len(chunk) > 1:
                end_map, timed_out = expand_chunk(bin_path, snapshot, [row], timeout=30)
                end = end_map.get((p, n, l))
                if timed_out:
                    bad_paths.add(p)
            if end is None:
                end, n_sig_only = l, n_sig_only + 1
            start, end = min(l, end), max(l, end)
            key = (p, start, end)
            if key in seen:
                continue
            seen.add(key)
            regions.append([p, start, end])
            cum += end - start + 1
            if cum >= budget:
                break
    return regions, n_sig_only


def load_subset(data_dir):
    return json.load(open(data_dir / "subset.json"))


def load_meta(data_dir):
    return json.load(open(data_dir / "upstream_meta.json"))


def predict(args):
    data_dir = Path(args.data_dir)
    subset = load_subset(data_dir)
    meta = load_meta(data_dir)
    wanted = set(args.instances.split(",")) if args.instances else None
    arms = ["for", "pack"] if args.arm == "both" else [args.arm]
    for arm in arms:
        out_path = data_dir / f"preds_{arm}_b{args.budget}{args.out_suffix}.jsonl"
        with open(out_path, "w") as fout:
            for s in subset:
                iid = s["instance_id"]
                if wanted and iid not in wanted:
                    continue
                snapshot = data_dir / "snapshots" / iid
                rec = {"instance_id": iid, "arm": arm, "lang": s["lang"],
                       "preds": [], "n_sig_only": 0, "error": None}
                if not snapshot.is_dir():
                    rec["error"] = "no-snapshot"
                else:
                    issue = meta[iid]["problem_statement"]
                    rows, err = ranked_rows_for_arm(Path(args.bin), snapshot, issue, arm)
                    if err:
                        rec["error"] = err
                    elif rows:
                        rec["preds"], rec["n_sig_only"] = build_regions(
                            Path(args.bin), snapshot, rows, args.budget)
                fout.write(json.dumps(rec, sort_keys=True) + "\n")
                fout.flush()
                print(f"[{arm}] {iid}: {len(rec['preds'])} regions"
                      f" ({rec['n_sig_only']} sig-only)"
                      + (f" ERROR {rec['error']}" if rec["error"] else ""),
                      file=sys.stderr)
        print(f"wrote {out_path}", file=sys.stderr)


def file_line_count(snapshot, rel):
    f = snapshot / rel
    if not f.is_file():
        return None
    try:
        with open(f, "rb") as fh:
            data = fh.read()
    except OSError:
        return None
    if not data:
        return 0
    return data.count(b"\n") + (0 if data.endswith(b"\n") else 1)


def gt_paths(gt):
    paths = set()
    for r in gt.get("read_core_regions") or []:
        paths.add(r["path"])
    for regions in (gt.get("read_optional_regions_map") or {}).values():
        for r in regions:
            paths.add(r["path"])
    paths.update(gt.get("read_core_files") or [])
    return paths


def score(args):
    data_dir = Path(args.data_dir)
    sys.path.insert(0, str(data_dir / "SWE-Explore-Bench"))
    from eval import ExploreEvaluator  # the benchmark's scorer, unmodified

    evaluator = ExploreEvaluator(data_dir / "bench.final.public.jsonl")
    arms = ["for", "pack"] if args.arm == "both" else [args.arm]
    all_scores = {}
    for arm in arms:
        preds_path = data_dir / f"preds_{arm}_b{args.budget}{args.out_suffix}.jsonl"
        with open(preds_path) as f:
            for line in f:
                rec = json.loads(line)
                iid = rec["instance_id"]
                if rec["error"]:
                    all_scores.setdefault(iid, {})[arm] = {"error": rec["error"]}
                    continue
                gt = evaluator.bench_data_dict[iid]["ground_truth"]
                snapshot = data_dir / "snapshots" / iid
                counts = {}
                for p in gt_paths(gt) | {r[0] for r in rec["preds"]}:
                    n = file_line_count(snapshot, p)
                    if n is not None:
                        counts[p] = n
                evaluator._current_instance_id = iid
                evaluator._current_file_line_counts = counts
                preds = [tuple(r) for r in rec["preds"]]
                row = {m: getattr(evaluator, f"evaluate_{m}")(preds, gt) for m in METRICS}
                row["lang"] = rec["lang"]
                row["n_preds"] = len(preds)
                row["n_sig_only"] = rec["n_sig_only"]
                all_scores.setdefault(iid, {})[arm] = row
    out = data_dir / f"scores_b{args.budget}{args.out_suffix}.json"
    json.dump(all_scores, open(out, "w"), indent=1, sort_keys=True)
    print(f"wrote {out}", file=sys.stderr)


def determinism(args):
    data_dir = Path(args.data_dir)
    ns = argparse.Namespace(**vars(args))
    outs = []
    for tag in ("_det1", "_det2"):
        ns.out_suffix, ns.arm, ns.instances = tag, "both", args.instance
        predict(ns)
        pair = []
        for arm in ("for", "pack"):
            pair.append((data_dir / f"preds_{arm}_b{args.budget}{tag}.jsonl").read_bytes())
        outs.append(pair)
    same = outs[0] == outs[1]
    print("DETERMINISM: " + ("byte-identical" if same else "MISMATCH"))
    return 0 if same else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--data-dir", required=True)
    common.add_argument("--budget", type=int, default=BUDGET_DEFAULT)
    common.add_argument("--out-suffix", default="")
    p = sub.add_parser("predict", parents=[common])
    p.add_argument("--bin", required=True)
    p.add_argument("--arm", choices=["for", "pack", "both"], default="both")
    p.add_argument("--instances", default=None)
    s = sub.add_parser("score", parents=[common])
    s.add_argument("--arm", choices=["for", "pack", "both"], default="both")
    d = sub.add_parser("determinism", parents=[common])
    d.add_argument("--bin", required=True)
    d.add_argument("--instance", required=True)
    args = ap.parse_args()
    if args.cmd == "predict":
        predict(args)
    elif args.cmd == "score":
        score(args)
    else:
        sys.exit(determinism(args))


if __name__ == "__main__":
    main()
