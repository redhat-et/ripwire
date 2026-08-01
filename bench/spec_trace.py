#!/usr/bin/env python3
# spec_trace.py — the MEASURE-FIRST experiment for the speculative-prefetch design.
#
# WHAT THIS IS. Drives a live `ripwire --mcp` server over stdin/stdout with a realistic ~20-call agent
# session and measures the per-request wall time, attributing each request to "warm reuse" vs a full index
# "rebuild" (the only latency the speculative-prefetch design could hide). It exists to DECIDE whether the
# mechanism is worth building — "measure says don't build it" is a first-class, expected outcome (design §0).
#
# HOW IT MEASURES. The server, run with RIPWIRE_MCP_TIMINGS=1 (env var — the design named a `--mcp-timings`
# CLI flag but cli.h/main.cpp are owned by a concurrent agent this round; the env var mirrors the existing
# RIPWIRE_CACHE_STATS precedent in ingest.cpp, zero-cost when unset), emits ONE stderr line per request:
#     ripwire-timing verb=<v> wall_ms=<f> rebuilt=<0|1>
# stdout stays pure JSON-RPC. This harness zips those stderr lines (in order) with the requests it sent.
#
# CORPORA. (a) this repo (writable → gets the edit-verb step on a throwaway scratch file it creates and
# deletes) and (b) a large private C++ corpus, if RIPWIRE_BENCH_ROOT points at one (READ-ONLY → the edit
# step is SKIPPED and noted; nothing under it is modified — quality_delta/read verbs write only to the
# cache dir, never the repo). Historical numbers measured against such a corpus are not reproducible
# publicly; re-run against your own to reproduce the shape.
#
# GO/NO-GO (design §4, decided up front):
#   (a) edit-rebuild is DEAD if total edit-triggered rebuild time < 500 ms OR its p95 < 200 ms.
#   (d) post-commit quality_delta is GO only if its cold p95 > 1000 ms (the cold-qsnap Snapshot recompute,
#       clones-dominated). A fresh-process first quality_delta pays the SAME cold-qsnap path a post-commit
#       first call hits — so we measure the first (cold) quality_delta without needing a real commit (the
#       harness never commits: honoring the "no git commit/add" rule).
#
# USAGE:
#   python3 bench/spec_trace.py --bin build/ripwire                 # both default corpora, 5 reps
#   python3 bench/spec_trace.py --bin build_ic2/ripwire --reps 7
#   python3 bench/spec_trace.py --bin build/ripwire --repo .        # a single corpus
#   python3 bench/spec_trace.py --bin build/ripwire --determinism   # A/B: prot. bytes identical on/off env
#
# Stdlib-only, deterministic control flow, no network. Wall times are machine/thermal-dependent (medians
# over reps, same discipline as bench/perfgate.sh) — run on a quiet machine.

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import time

THIS_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CANYON = os.environ.get("RIPWIRE_BENCH_ROOT", "/path/to/your/large/private/cpp/corpus")

TIMING_RE = re.compile(r"^ripwire-timing verb=(\S+) wall_ms=([0-9.]+) rebuilt=([01])")


# ── a driven MCP server session ─────────────────────────────────────────────────────────────────────
class Server:
    """One live `ripwire --mcp` process. Requests go in one at a time; the matching response line is read
    back synchronously (the server flushes per line). Per-request timing lands on stderr, collected on close."""

    def __init__(self, binpath, timings=True):
        env = dict(os.environ)
        if timings:
            env["RIPWIRE_MCP_TIMINGS"] = "1"
        else:
            env.pop("RIPWIRE_MCP_TIMINGS", None)
        self.errfile = open(_tmp("stderr"), "w+")
        self.proc = subprocess.Popen(
            [binpath, "--mcp"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.errfile,
            text=True, bufsize=1, env=env,
        )

    def call(self, method, params=None, rid=1):
        req = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            req["params"] = params
        self.proc.stdin.write(json.dumps(req) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            return None
        return json.loads(line)

    def tool(self, name, args, rid=1):
        return self.call("tools/call", {"name": name, "arguments": args}, rid)

    def close(self):
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        self.proc.wait(timeout=30)
        self.errfile.flush()
        self.errfile.seek(0)
        timings = []
        for ln in self.errfile:
            m = TIMING_RE.match(ln.strip())
            if m:
                timings.append((m.group(1), float(m.group(2)), int(m.group(3))))
        self.errfile.close()
        return timings


_TMP_SEQ = [0]


def _tmp(tag):
    _TMP_SEQ[0] += 1
    d = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    return f"{d}/spec_trace_{os.getpid()}_{tag}_{_TMP_SEQ[0]}.tmp"


def _text(resp):
    if not resp or "result" not in resp:
        return ""
    c = resp["result"].get("content", [])
    return c[0].get("text", "") if c else ""


# ── candidate (d): the qsnap cache is on-disk and process-persistent (quality.h:467, cacheDirLadder =
# $TMPDIR ladder). A quality_delta whose qsnap file already exists is NOT cold — so to measure the cold
# HEAD-snapshot cost the prefetch would hide, we delete the qsnap + qheadsnap families first. These are
# pure, regenerable caches (never source); deleting them only forces the next call to recompute. We can't
# cheaply derive this repo's repoHex, so we clear the whole family across the candidate cache dirs — benign.
def clear_qsnap_caches():
    dirs = []
    for d in (os.environ.get("TMPDIR"), os.environ.get("XDG_CACHE_HOME"),
              os.path.expanduser("~/.cache"), "/tmp"):
        if d and os.path.isdir(d) and d not in dirs:
            dirs.append(d.rstrip("/"))
    removed = 0
    for d in dirs:
        for pat in ("ripwire-qsnap-*", "ripwire-qheadsnap-*"):
            for f in glob.glob(os.path.join(d, pat)):
                try:
                    os.remove(f)
                    removed += 1
                except OSError:
                    pass
    return removed


# ── the ~20-call session ────────────────────────────────────────────────────────────────────────────
# Each step appends a (phase, verb-label) to `plan`; the timing lines returned by close() align 1:1 and
# IN ORDER with these (every request carries an id ⇒ exactly one timing line ⇒ no notifications to skip).
def run_session(binpath, repo, writable):
    plan = []            # ordered (phase, label) — matches the stderr timing lines
    scratch = None
    if writable:
        scratch = os.path.join(repo, f"_spec_trace_scratch_{os.getpid()}.py")
        with open(scratch, "w") as f:
            f.write("def spec_trace_target():\n    return 41\n")

    srv = Server(binpath, timings=True)
    try:
        srv.call("initialize", rid=1);                                    plan.append(("init", "initialize"))

        # orient burst
        srv.tool("for", {"path": repo, "task": "rank symbols by relevance"}, 2)
        plan.append(("orient", "for(cold)"))                              # FIRST verb ⇒ cold rebuild

        ex = _text(srv.tool("exemplar", {"path": repo, "kind": "fn"}, 3))
        plan.append(("orient", "exemplar"))
        m = re.search(r'\bn="([^"]+)"', ex)
        seed = m.group(1) if m else "main"

        fs = srv.tool("find_symbol", {"path": repo, "symbol": seed}, 4)
        plan.append(("read", "find_symbol"))
        handle, caller = _parse_find_symbol(_text(fs))

        srv.tool("fetch_body", {"path": repo, "handle": handle or "sym#0@0"}, 5)
        plan.append(("read", "fetch_body#1"))

        frs = srv.tool("find_referencing_symbols", {"path": repo, "symbol": seed}, 6)
        plan.append(("read", "callers"))
        h2, _ = _parse_find_symbol(_text(frs))
        srv.tool("fetch_body", {"path": repo, "handle": h2 or handle or "sym#0@0"}, 7)
        plan.append(("read", "fetch_body#2"))

        srv.tool("impact", {"path": repo, "symbol": seed}, 8);            plan.append(("read", "impact"))
        srv.tool("uses", {"path": repo, "symbol": seed}, 9);              plan.append(("read", "uses"))
        srv.tool("grep", {"path": repo, "pattern": seed}, 10);           plan.append(("read", "grep"))
        srv.tool("mentions", {"path": repo, "symbol": seed}, 11);        plan.append(("read", "mentions"))
        srv.tool("path_between", {"path": repo, "from": caller or seed, "to": seed}, 12)
        plan.append(("read", "path_between"))
        srv.tool("analyze", {"path": repo}, 13);                          plan.append(("read", "analyze"))

        # edit verb — WRITABLE corpus only (the design's candidate (a) trigger). The edit invalidates the
        # index; the edit response envelope's own _index stamp forces the rebuild inline, so the rebuild wall
        # is attributed to replace_symbol_body itself (verified: rebuilt=1 on that line).
        if writable:
            srv.tool("replace_symbol_body",
                     {"path": repo, "symbol": "spec_trace_target",
                      "new_body": "def spec_trace_target():\n    return 42\n"}, 14)
            plan.append(("edit", "replace_symbol_body(rebuild)"))
            # a follow-up read verb — expected warm (edit already rebuilt) — confirms the flag flips back.
            srv.tool("for", {"path": repo, "task": "rank symbols by relevance"}, 15)
            plan.append(("post-edit", "for(warm)"))
        else:
            plan.append(("edit", "SKIPPED(read-only corpus)"))           # placeholder, no request sent

        # quality reflex — candidate (d). The prefetchable cost is ONLY the HEAD-side qsnap (git archive +
        # ingest + clone detection over the immutable HEAD tree). The working-tree side (its own clone pass +
        # ingest) is recomputed on EVERY call and is NOT prefetchable (quality.h comment) — so the figure that
        # decides (d) is the DELTA cold−warm, not the absolute quality_delta wall. We clear the on-disk qsnap
        # families so the "cold" call genuinely recomputes the HEAD Snapshot (== the post-new-commit path); the
        # "warm" call then finds the qsnap the cold call just wrote.
        clear_qsnap_caches()
        srv.tool("quality_delta", {"path": repo}, 16);                    plan.append(("quality", "quality_delta(cold)"))
        srv.tool("quality_delta", {"path": repo}, 17);                    plan.append(("quality", "quality_delta(warm)"))

        # closing situational awareness (runs git diff over the working tree)
        srv.tool("situational_awareness", {"path": repo}, 18);            plan.append(("situ", "situational_awareness"))
    finally:
        timings = srv.close()
        if scratch and os.path.exists(scratch):
            os.remove(scratch)

    # align: the SKIPPED placeholder sent no request ⇒ drop it before zipping with the timing lines.
    sent = [p for p in plan if not p[1].startswith("SKIPPED")]
    rows = []
    for (phase, label), t in zip(sent, timings):
        rows.append({"phase": phase, "label": label, "verb": t[0], "wall_ms": t[1], "rebuilt": t[2]})
    return rows


def _parse_find_symbol(txt):
    """(handle, first-caller-name) from a find_symbol / find_referencing_symbols JSON payload, or (None,None)."""
    try:
        o = json.loads(txt)
    except Exception:
        return None, None
    handle = o.get("symbol", {}).get("handle")
    caller = None
    for k in ("calledBy", "calls"):
        lst = o.get(k) or []
        if lst:
            caller = lst[0].get("name")
            if not handle:
                handle = lst[0].get("handle")
            break
    return handle, caller


# ── aggregation + the decision table ──────────────────────────────────────────────────────────────────
def pct(vals, p):
    if not vals:
        return 0.0
    s = sorted(vals)
    k = max(0, min(len(s) - 1, int(round((p / 100.0) * (len(s) - 1)))))
    return s[k]


def aggregate(all_rows):
    """all_rows: list (per rep) of row-lists. Returns per-label {p50,p95,rebuilt_any,phase,samples}."""
    by_label = {}
    order = []
    for rep in all_rows:
        for r in rep:
            key = r["label"]
            if key not in by_label:
                by_label[key] = {"phase": r["phase"], "walls": [], "rebuilt": []}
                order.append(key)
            by_label[key]["walls"].append(r["wall_ms"])
            by_label[key]["rebuilt"].append(r["rebuilt"])
    out = []
    for key in order:
        d = by_label[key]
        out.append({
            "label": key, "phase": d["phase"],
            "p50": pct(d["walls"], 50), "p95": pct(d["walls"], 95),
            "rebuilt_any": max(d["rebuilt"]) if d["rebuilt"] else 0,
            "n": len(d["walls"]),
        })
    return out


def print_table(name, agg):
    print(f"\n=== {name} — per-request wall (ms), medians over reps ===")
    print(f"{'phase':<10} {'verb / step':<28} {'p50':>9} {'p95':>9} {'rebuilt':>8} {'n':>3}")
    print("-" * 72)
    for r in agg:
        print(f"{r['phase']:<10} {r['label']:<28} {r['p50']:>9.2f} {r['p95']:>9.2f} {r['rebuilt_any']:>8} {r['n']:>3}")


def verdict(name, agg, all_rows):
    edit = [r for r in agg if r["phase"] == "edit" and r["rebuilt_any"] == 1]
    lines = [f"\n--- VERDICT [{name}] ---"]

    # candidate (a): edit-triggered rebuild
    if not edit:
        lines.append("(a) edit-rebuild: N/A — no edit-triggered rebuild in this corpus "
                     "(read-only, edit step SKIPPED). Cold full rebuild reference below.")
        cold = [r for r in agg if r["label"] == "for(cold)"]
        if cold:
            lines.append(f"    for(cold) full rebuild p50={cold[0]['p50']:.1f}ms — an UPPER bound; the "
                         f"warm edit-rebuild (~280ms/PROFILE) is un-reproducible read-only.")
        a_go = None
    else:
        total = sum(r["p50"] for r in edit)
        p95 = max(r["p95"] for r in edit)
        dead = (total < 500.0) or (p95 < 200.0)
        lines.append(f"(a) edit-rebuild: total_p50={total:.1f}ms  p95={p95:.1f}ms  "
                     f"→ {'DEAD (below threshold: <500ms total OR p95<200ms)' if dead else 'SURVIVES threshold'}")
        a_go = not dead

    # candidate (d): the PREFETCHABLE portion = per-rep (cold_qsnap − warm_qsnap) quality_delta delta.
    diffs = []
    colds = []
    for rep in all_rows:
        c = next((r["wall_ms"] for r in rep if r["label"] == "quality_delta(cold)"), None)
        w = next((r["wall_ms"] for r in rep if r["label"] == "quality_delta(warm)"), None)
        if c is not None and w is not None:
            diffs.append(c - w)
            colds.append(c)
    if not diffs:
        lines.append("(d) quality_delta: N/A — verb not measured.")
        d_go = None
    else:
        d95 = pct(diffs, 95)
        d50 = pct(diffs, 50)
        c50 = pct(colds, 50)
        go = d95 > 1000.0
        lines.append(f"(d) quality_delta prefetchable HEAD-snapshot (cold−warm): p50={d50:.1f}ms p95={d95:.1f}ms "
                     f"(of a ~{c50:.0f}ms total cold call — the rest is the un-prefetchable working-tree pass) "
                     f"→ {'GO (prefetchable qsnap p95 > 1s)' if go else 'NO-GO (prefetchable qsnap p95 <= 1s — nothing worth a bg thread)'}")
        d_go = go

    return "\n".join(lines), a_go, d_go


# ── determinism A/B: protocol bytes must be identical with the env var ON vs OFF ───────────────────────
def determinism_check(binpath, repo):
    reqs = [
        ("initialize", None),
        ("tools/call", {"name": "for", "arguments": {"path": repo, "task": "rank symbols"}}),
        ("tools/call", {"name": "impact", "arguments": {"path": repo, "symbol": "main"}}),
        ("tools/call", {"name": "analyze", "arguments": {"path": repo}}),
        ("tools/call", {"name": "quality_delta", "arguments": {"path": repo}}),
    ]

    def drive(timings):
        srv = Server(binpath, timings=timings)
        out = []
        for i, (m, p) in enumerate(reqs, 1):
            out.append(json.dumps(srv.call(m, p, rid=i), sort_keys=True))
        srv.close()
        return out

    on = drive(True)
    off = drive(False)
    ok = on == off
    print(f"\n=== determinism A/B (env ON vs OFF) on {repo} ===")
    print("  protocol responses byte-identical:", "PASS" if ok else "FAIL")
    if not ok:
        for i, (a, b) in enumerate(zip(on, off)):
            if a != b:
                print(f"  MISMATCH at request {i+1}:\n    ON : {a[:200]}\n    OFF: {b[:200]}")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", default=os.path.join(THIS_REPO, "build", "ripwire"))
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--repo", default=None, help="single corpus; default = both (this repo + $RIPWIRE_BENCH_ROOT, if set and present)")
    ap.add_argument("--determinism", action="store_true", help="run only the env ON/OFF byte-identity A/B")
    args = ap.parse_args()

    binpath = args.bin if os.path.isabs(args.bin) else os.path.join(os.getcwd(), args.bin)
    if not os.access(binpath, os.X_OK):
        print(f"no executable ripwire at {binpath} — build first", file=sys.stderr)
        return 2

    if args.determinism:
        ok = determinism_check(binpath, THIS_REPO)
        return 0 if ok else 1

    if args.repo:
        corpora = [(args.repo, os.path.abspath(args.repo) == os.path.abspath(THIS_REPO))]
    else:
        corpora = [(THIS_REPO, True)]
        if os.path.isdir(CANYON):
            corpora.append((CANYON, False))     # READ-ONLY — edit step skipped
        else:
            print(f"note: {CANYON} not present — running this repo only", file=sys.stderr)

    summary = []
    for repo, writable in corpora:
        name = os.path.basename(repo.rstrip("/")) + ("" if writable else " (read-only)")
        all_rows = []
        for _ in range(args.reps):
            all_rows.append(run_session(binpath, repo, writable))
        agg = aggregate(all_rows)
        print_table(name, agg)
        v, a_go, d_go = verdict(name, agg, all_rows)
        print(v)
        summary.append((name, a_go, d_go))

    print("\n" + "=" * 72)
    print("OVERALL GO/NO-GO")
    for name, a_go, d_go in summary:
        print(f"  {name:<28}  (a) edit-rebuild: {_g(a_go):<10}  (d) quality_delta: {_g(d_go)}")
    return 0


def _g(x):
    return "N/A" if x is None else ("GO/SURVIVES" if x else "NO-GO/DEAD")


if __name__ == "__main__":
    sys.exit(main())
