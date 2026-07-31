#!/usr/bin/env python3
# swebench_eval.py — generate SWE-bench predictions for TWO arms (baseline vs +ripwire context) so the
# OFFICIAL swebench harness can score them, and you read off ripwire's task-success contribution as the
# delta. This file owns ONLY the ripwire-specific part (prompt construction); scoring is delegated to
# `python -m swebench.harness.run_evaluation` (the standard sandboxed, non-gameable scorer). The bench/
# ANSWERQUALITY.md retrieval proxy is the leading indicator; THIS is the end-to-end number.
#
# Not run in CI — needs an API key + the dataset + Docker (for the scorer):
#   pip install datasets anthropic
#   export ANTHROPIC_API_KEY=...                         # ripwire must be on PATH (or set RIPWIRE=)
#   python bench/swebench_eval.py --n 50
#   python -m swebench.harness.run_evaluation --predictions_path preds_ripwire.jsonl  --run_id ctx  --dataset_name princeton-nlp/SWE-bench_Lite
#   python -m swebench.harness.run_evaluation --predictions_path preds_baseline.jsonl --run_id base --dataset_name princeton-nlp/SWE-bench_Lite
#   # compare the two "resolved" counts — the delta IS ripwire's contribution.
import argparse, json, os, re, subprocess, sys, pathlib

CTX        = os.environ.get("RIPWIRE", "ripwire")
MODEL      = os.environ.get("RIPWIRE_EVAL_MODEL", "claude-opus-4-8")
REPO_CACHE = pathlib.Path(os.environ.get("RIPWIRE_REPO_CACHE", "/tmp/ripwire_swebench_repos"))
SYS = ("You are an expert software engineer. Given a bug report and repository context, reply with a "
       "single unified diff (git patch) that fixes the issue. Output ONLY the diff, no prose.")

def sh(args, timeout=1800):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)

def checkout(repo, base_commit):
    # clone once per repo (cached), then hard-checkout the instance's base commit → the worktree path.
    dst = REPO_CACHE / repo.replace("/", "__")
    if not dst.exists():
        REPO_CACHE.mkdir(parents=True, exist_ok=True)
        sh(["git", "clone", f"https://github.com/{repo}.git", str(dst)])
    sh(["git", "-C", str(dst), "checkout", "-f", base_commit])
    sh(["git", "-C", str(dst), "clean", "-fdx"])
    return dst

def ripwire_context(repo_path, problem, budget=2000):
    # the ripwire arm's extra context: a ranked, task-lensed signatures inventory for the bug report.
    q = " ".join(problem.split())[:300]
    r = sh([CTX, str(repo_path), "--for", q, "--max-tokens", str(budget)])
    return r.stdout if r.returncode == 0 else ""

def ask(system, user):
    import anthropic
    msg = anthropic.Anthropic().messages.create(
        model=MODEL, max_tokens=4096, system=system,
        messages=[{"role": "user", "content": user}])
    return "".join(b.text for b in msg.content if getattr(b, "type", "") == "text")

def extract_patch(text):
    m = re.search(r"```(?:diff|patch)?\n(.*?)```", text, re.S)   # first fenced diff, else raw
    return (m.group(1) if m else text).strip() + "\n"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", default="princeton-nlp/SWE-bench_Lite")
    ap.add_argument("--split", default="test")
    ap.add_argument("--n", type=int, default=50)
    a = ap.parse_args()
    from datasets import load_dataset
    ds = load_dataset(a.dataset, split=a.split)
    with open("preds_baseline.jsonl", "w") as bf, open("preds_ripwire.jsonl", "w") as cf:
        for i, inst in enumerate(ds):
            if i >= a.n: break
            iid, repo, bc, prob = inst["instance_id"], inst["repo"], inst["base_commit"], inst["problem_statement"]
            print(f"[{i+1}/{a.n}] {iid}", file=sys.stderr)
            try:
                ctx = ripwire_context(checkout(repo, bc), prob)
            except Exception as e:
                print(f"  skip ({e})", file=sys.stderr); continue
            base = extract_patch(ask(SYS, f"# Bug report\n{prob}\n\nReply with the fixing diff."))
            ctxd = extract_patch(ask(SYS, f"# Repository map (ripwire)\n{ctx}\n\n# Bug report\n{prob}\n\nReply with the fixing diff."))
            for f, patch in ((bf, base), (cf, ctxd)):
                f.write(json.dumps({"instance_id": iid, "model_name_or_path": MODEL, "model_patch": patch}) + "\n"); f.flush()
    print("wrote preds_baseline.jsonl + preds_ripwire.jsonl — score BOTH with the official swebench harness (see header).", file=sys.stderr)

if __name__ == "__main__":
    main()
