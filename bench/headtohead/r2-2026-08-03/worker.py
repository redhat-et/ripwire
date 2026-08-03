#!/usr/bin/env python3
# Head-to-head #2 competitor arm worker.
# Reuses the LocBench harness's checkout + metric code (imported UNMODIFIED) and the
# ripwire arm's json-out as the single source of the slice, gold, and query construction.
# Conventions (documented in the report):
#   universe (competitor arms) = `git ls-files` of the shared checkout (B5.3 convention)
#   ranked files              = first appearance of a result's file path in the tool's output order
#   codeseek_raw              = `codeseek search "<issue 1200ch>" --limit 300 --json` (fallback mode, no embedder)
#   codeseek_idents           = imposed convention: identifier mentions regex-extracted from the issue,
#                               each searched separately, merged by (per-ident rank, ident order)
#   repowise                  = MCP `search_codebase` (query=<issue 1200ch>, limit=300, mode=auto -> FTS,
#                               no embedder); ranked file = first appearance of each result target_path
#                               (file.py::Symbol spotlights mapped to file.py; rank matching against gold
#                               is done by RL.file_ranks over the universe, non-file pages simply never match)
import argparse, json, os, pathlib, re, subprocess, sys, time

HERE = pathlib.Path(__file__).resolve().parent
RIPWIRE_REPO = pathlib.Path("/Users/qgames/AppDevelopLocal/project2/ripwire")
sys.path.insert(0, str(RIPWIRE_REPO / "bench" / "locbench"))
import run_locbench as RL  # file_ranks, acc metrics, checkout — imported unmodified

CODESEEK = pathlib.Path.home() / ".codeseek" / "bin" / "codeseek"
REPOWISE = HERE / "tools" / "repowise-venv" / "bin" / "repowise"
REPOS = HERE / "repos"          # competitor checkout tree, separate from the ripwire arm's
RESULTS = HERE / "results"
QUERY_CHARS = 1200

def load_slice():
    d = json.load(open(RESULTS / "ripwire_for.json"))
    rows = json.load(open(HERE / "work" / "datasets" / "rows_czlll__Loc-Bench_V1_test_560.json"))
    meta = {r["instance_id"]: r for r in rows}
    out = []
    for inst in d["instances"]:
        m = meta[inst["instance_id"]]
        query = " ".join(m.get("problem_statement", "").split())[:QUERY_CHARS]
        out.append(dict(instance_id=inst["instance_id"], repo=inst["repo"],
                        base_commit=m["base_commit"], query=query,
                        primary_files=inst["primary_files"], gold_files=inst["gold_files"]))
    return out

def git_ls_files(repo_path):
    r = subprocess.run(["git", "ls-files"], capture_output=True, text=True, cwd=repo_path)
    return [RL.norm_path(f) for f in r.stdout.splitlines() if f]

def timed(args, cwd, timeout=3600, stdin_data=None):
    t0 = time.monotonic()
    r = subprocess.run(args, capture_output=True, text=True, cwd=cwd, timeout=timeout, input=stdin_data)
    return r, time.monotonic() - t0

# ── codeseek ─────────────────────────────────────────────────────────────────
def codeseek_index(repo_path):
    r, wall = timed([str(CODESEEK), "init"], repo_path)
    if r.returncode != 0:
        raise RuntimeError(f"codeseek init failed: {r.stderr[-400:]}")
    return wall

def codeseek_search(repo_path, query, limit=300):
    r, wall = timed([str(CODESEEK), "search", query, "--limit", str(limit), "--json"], repo_path)
    if r.returncode != 0:
        raise RuntimeError(f"codeseek search failed: {r.stderr[-400:]}")
    try:
        hits = json.loads(r.stdout)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"codeseek search emitted non-JSON ({e}): {r.stdout[:200]!r}")
    files, seen = [], set()
    for h in hits:
        p = os.path.relpath(h["file_path"], repo_path)
        if p not in seen:
            seen.add(p); files.append(RL.norm_path(p))
    return files, wall, len(r.stdout)

IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
def issue_idents(query, cap=8):
    # imposed convention: code-shaped tokens only — snake_case, camelCase, or dotted mentions
    out, seen = [], set()
    for tok in IDENT_RE.findall(query):
        if len(tok) < 3 or tok in seen: continue
        codey = "_" in tok or (tok[0].islower() and any(c.isupper() for c in tok[1:]))
        if codey:
            seen.add(tok); out.append(tok)
        if len(out) >= cap: break
    return out

def codeseek_idents_search(repo_path, query, per_ident_limit=50):
    idents = issue_idents(query)
    merged, seen, total_wall, total_bytes = [], set(), 0.0, 0
    per = []
    for ident in idents:
        files, wall, nbytes = codeseek_search(repo_path, ident, per_ident_limit)
        per.append((ident, files)); total_wall += wall; total_bytes += nbytes
    # merge by (per-ident rank, ident order)
    rank = 0
    while True:
        emitted = False
        for ident, files in per:
            if rank < len(files):
                f = files[rank]
                if f not in seen:
                    seen.add(f); merged.append(f)
                emitted = True
        if not emitted: break
        rank += 1
    return merged, total_wall, total_bytes, idents

# ── repowise ─────────────────────────────────────────────────────────────────
def repowise_index(repo_path, mode=None):
    args = [str(REPOWISE), "init", "--no-prose", "-y"]
    if mode: args += ["--mode", mode]
    args.append(".")
    r, wall = timed(args, repo_path, timeout=7200)
    if r.returncode != 0:
        raise RuntimeError(f"repowise init failed: {(r.stderr or r.stdout)[-600:]}")
    return wall

def repowise_search(repo_path, query, limit=300):
    t0 = time.monotonic()
    p = subprocess.Popen([str(REPOWISE), "mcp", "."], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, cwd=repo_path)
    def send(m): p.stdin.write(json.dumps(m) + "\n"); p.stdin.flush()
    def recv():
        while True:
            line = p.stdout.readline()
            if not line: raise RuntimeError("repowise mcp died")
            try: return json.loads(line)
            except json.JSONDecodeError: continue
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "h2h", "version": "0"}}})
    recv()
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    send({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
          "params": {"name": "search_codebase", "arguments": {"query": query, "limit": limit, "mode": "auto"}}})
    r = recv()
    p.kill()
    wall = time.monotonic() - t0
    txt = r["result"]["content"][0]["text"]
    data = json.loads(txt)
    files, seen, raw = [], set(), []
    for res in data.get("results", []):
        # symbol_spotlight pages use "file.py::Symbol" targets — map to the file
        tp = RL.norm_path((res.get("target_path", "") or "").split("::")[0])
        raw.append({k: res.get(k) for k in ("page_type", "target_path", "relevance_score")})
        if tp and tp not in seen:
            seen.add(tp); files.append(tp)
    return files, wall, len(txt), raw

# ── main loop ────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", required=True, choices=["codeseek", "repowise"])
    ap.add_argument("--repowise-mode", default="", help="'' = full --no-prose; 'fast' = --mode fast")
    ap.add_argument("--only", default="", help="comma-separated instance_ids (probe mode)")
    ap.add_argument("--limit", type=int, default=300)
    args = ap.parse_args()
    insts = load_slice()
    if args.only:
        keep = set(args.only.split(","))
        insts = [i for i in insts if i["instance_id"] in keep]
    out_path = RESULTS / f"{args.arm}{'_fast' if args.repowise_mode else ''}.jsonl"
    done = set()
    if out_path.exists():
        for line in out_path.read_text().splitlines():
            done.add(json.loads(line)["instance_id"])
    REPOS.mkdir(exist_ok=True)
    for n, inst in enumerate(insts):
        iid = inst["instance_id"]
        if iid in done:
            print(f"[{n+1}/{len(insts)}] {iid}: already done", flush=True); continue
        repo_path = RL.checkout(inst["repo"], inst["base_commit"], REPOS)
        if not repo_path:
            raise SystemExit(f"{iid}: checkout FAILED (zero-silent-skip)")
        universe = git_ls_files(repo_path)
        rec = dict(instance_id=iid, repo=inst["repo"], base_commit=inst["base_commit"],
                   n_universe=len(universe))
        try:
            if args.arm == "codeseek":
                subprocess.run([str(CODESEEK), "uninit", "--force"], capture_output=True, text=True, cwd=repo_path)
                rec["index_wall"] = codeseek_index(repo_path)
                files, wall, nbytes = codeseek_search(repo_path, inst["query"], args.limit)
                rec["raw"] = dict(ranked=files[:50], wall=wall, bytes=nbytes)
                mfiles, mwall, mbytes, idents = codeseek_idents_search(repo_path, inst["query"])
                rec["idents"] = dict(ranked=mfiles[:50], wall=mwall, bytes=mbytes, idents=idents)
                for key, fl in (("raw", files), ("idents", mfiles)):
                    fr = RL.file_ranks(fl, inst["primary_files"], universe)
                    afr = RL.file_ranks(fl, inst["gold_files"], universe)
                    rec[key]["franks"] = fr
                    rec[key]["file_first"] = RL.first_hit(fr)
                    rec[key]["file_worst"] = max(fr) if fr and all(r is not None for r in fr) else None
                    rec[key]["all_file_worst"] = max(afr) if afr and all(r is not None for r in afr) else None
                subprocess.run([str(CODESEEK), "uninit", "--force"], capture_output=True, text=True, cwd=repo_path)
            else:
                import shutil
                shutil.rmtree(repo_path / ".repowise", ignore_errors=True)
                rec["index_wall"] = repowise_index(repo_path, args.repowise_mode or None)
                files, wall, nbytes, raw = repowise_search(repo_path, inst["query"], args.limit)
                fr = RL.file_ranks(files, inst["primary_files"], universe)
                afr = RL.file_ranks(files, inst["gold_files"], universe)
                rec["search"] = dict(ranked=files[:50], wall=wall, bytes=nbytes, raw_top=raw[:20],
                                     franks=fr, file_first=RL.first_hit(fr),
                                     file_worst=max(fr) if fr and all(r is not None for r in fr) else None,
                                     all_file_worst=max(afr) if afr and all(r is not None for r in afr) else None)
                shutil.rmtree(repo_path / ".repowise", ignore_errors=True)
        except Exception as e:
            raise SystemExit(f"{iid}: ARM FAIL: {e} (zero-silent-skip)")
        with open(out_path, "a") as f:
            f.write(json.dumps(rec) + "\n")
        print(f"[{n+1}/{len(insts)}] {iid}: idx={rec.get('index_wall',0):.1f}s "
              + (f"raw_ff={rec['raw']['file_first']} id_ff={rec['idents']['file_first']}" if args.arm == "codeseek"
                 else f"ff={rec['search']['file_first']} wall={rec['search']['wall']:.1f}s"), flush=True)

if __name__ == "__main__":
    main()
