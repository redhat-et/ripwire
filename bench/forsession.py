#!/usr/bin/env python3
"""forsession.py — the per-WARM-QUERY cost of an MCP session, which is the only framing in which a
per-call cost can be judged.

WHY THIS SHAPE. `rankGraphTeleport` is the PERSONALIZED rank: it runs once per query, from a
different seed set each time. `buildGraph` runs once per index. Comparing them as shares of one cold
run prices a per-call cost against a one-time one -- the error that made personalized ranking look
like ~1% of the work when it is ~400 ms of every warm llvm-project query. So this harness drives ONE
session that holds the graph in memory, issues N `for` calls with N DIFFERENT tasks, and reads the
per-scope aggregate the profile build prints at exit:

    rankGraph: PageRank (power iteration)   calls=N  total_ms=<sum over the N queries>
    buildGraph: resolve refs + build CSR    calls=1  total_ms=<paid once for the session>

`calls=` is the whole point: it is the proof of which costs are per-query and which are per-index.

THE TRANSPORT IS A ONE-WAY STREAM, DELIBERATELY. An earlier version of this file spoke JSON-RPC
interactively -- write a request, read its reply, repeat -- and it DEADLOCKED on llvm-project twice,
in two different ways. First it gave the child stderr=PIPE and drained it only after closing stdin,
which deadlocks once the 64 KiB buffer fills. Then, with that fixed, it still hung: the read loop
assumed one reply is one line, and a large llvm answer spans many, so stdout was under-drained until
the server blocked writing it. Both sides sat at 0.0% CPU and looked like a slow run from outside.

The fix is not a better read loop -- it is noticing that the read loop buys nothing. Nothing here
needs a reply: the clock is the server's own `RIPWIRE_MCP_TIMINGS` stderr line per request, and the
attribution is the #PROF_TSV block at exit. So every request is written up front, stdin is closed,
stdout goes to /dev/null and stderr goes to a FILE. There is no interactive state to deadlock, no
reply framing to get wrong, and no pipe this process can under-drain. Reply BYTES are the one thing
this shape cannot report, and they are not what it measures.

usage: forsession.py PROF_BIN ROOT TASKS_FILE [N]
  PROF_BIN must be a -DRIPWIRE_PROFILE=ON build, or there is no #PROF_TSV block to read.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile

# Scopes worth printing, ordered so the per-query / per-index split reads top to bottom.
PER_CALL_SCOPE = "mcp: handle one request (the per-call unit of a session)"
ONCE_SCOPES = ("buildGraph: resolve refs + build CSR", "ingest: total (crawl + parse + model)")
NAMED_QUERY_SCOPES = (
    "rankGraph: PageRank (power iteration)",
    "lexical: lexicalScores (BM25 over symbols)",
    "lexical: lexicalScoresNameExact (whole-name BM25 over symbols)",
    "lexical: pass 2 via persisted subtoken stats (cached tf/dl, no corpus re-tokenize)",
    "main: computeQMetrics + change-amplification",
    "gitmine: popenTrimmed (one shell + git child, block read)",
)
SCOPES = (PER_CALL_SCOPE,) + NAMED_QUERY_SCOPES + ONCE_SCOPES


def build_stream(root, tasks):
    """Every request of the session, one JSON object per line, written before the child starts."""
    lines = [json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                         "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                                    "clientInfo": {"name": "forsession", "version": "1"}}})]
    for i, task in enumerate(tasks):
        lines.append(json.dumps({"jsonrpc": "2.0", "id": i + 2, "method": "tools/call",
                                 "params": {"name": "for",
                                            "arguments": {"path": root, "task": task}}}))
    return "\n".join(lines) + "\n"


def parse_tsv(block):
    """{scope: (calls, total_ms)} from the fenced block, plus the rows that did not parse."""
    rows, unparsed = {}, []
    for line in block.splitlines()[2:]:
        cols = line.split("\t")
        if len(cols) < 5:
            if line.strip():
                unparsed.append(line)
            continue
        try:
            rows[cols[0]] = (int(cols[3]), float(cols[4]))
        except ValueError:
            unparsed.append(line)
    return rows, unparsed


# ONE clock, generous, and far above the slowest cell. Two clocks close together is what cost a
# measurement window: an inner 600 s per-request deadline sat just under a 900 s outer bound, the
# inner one fired, and from outside the kill was indistinguishable from a normal finish. There is now
# a single bound on the whole session and the result says in words how the run ended, so no reader has
# to infer it. llvm-project's slowest observed session is ~75 s (a 35 s index build plus eight ~2 s
# queries) under a profile build, so 1800 s is ~24x headroom: it bounds a hang without ever being the
# thing that stops a working run.
SESSION_TIMEOUT_S = 1800.0


def run_session(prof_bin, root, tasks):
    env = dict(os.environ)
    env["RIPWIRE_MCP_TIMINGS"] = "1"   # one `ripwire-timing verb=… wall_ms=…` line per request
    errf = tempfile.NamedTemporaryFile("w+", prefix="forsession-err-", suffix=".txt", delete=False)
    with errf, open(os.devnull, "wb") as devnull:
        try:
            done = subprocess.run([prof_bin, "--mcp"], input=build_stream(root, tasks),
                                  stdout=devnull, stderr=errf, env=env, text=True,
                                  timeout=SESSION_TIMEOUT_S)
            ended = f"the server exited normally, rc={done.returncode}"
            rc = done.returncode
        except subprocess.TimeoutExpired:
            ended = (f"KILLED at the {SESSION_TIMEOUT_S:.0f}s session bound — this cell FAILED, it did "
                     f"not finish; nothing below is a complete session")
            rc = -1
        errf.flush()
        errf.seek(0)
        return rc, errf.read(), errf.name, ended


def report(rows, tasks):
    print(f"\n  {'calls':>6} {'total_ms':>11} {'per_call_ms':>12}  scope")
    for scope in SCOPES:
        if scope in rows:
            calls, ms = rows[scope]
            print(f"  {calls:>6} {ms:>11.1f} {ms / max(calls, 1):>12.2f}  {scope}")

    per_request = rows.get(PER_CALL_SCOPE)
    if not per_request or not tasks:
        print("\n  (no per-request scope in this build — the per-query residual needs "
              "dispatchMcpLine's scope)", file=sys.stderr)
        return
    once = sum(rows[s][1] for s in ONCE_SCOPES if s in rows)
    query = (per_request[1] - once) / len(tasks)
    print(f"\n  per warm `for`: {query:,.0f} ms  (= {per_request[1]:,.0f} ms over "
          f"{per_request[0]} requests, less the {once:,.0f} ms of ingest + buildGraph a session "
          f"pays ONCE, over {len(tasks)} calls)")
    named = sum(rows[s][1] / max(rows[s][0], 1) for s in NAMED_QUERY_SCOPES if s in rows)
    print(f"  of which named scopes account for {named:,.0f} ms; {query - named:,.0f} ms is "
          f"unattributed inside the verb")
    print("  NOTE: a -DRIPWIRE_PROFILE=ON build carries the instrumentation tax and is NOT the "
          "PGO build; these are attribution shares, not a publishable wall clock.")


def main():
    if len(sys.argv) < 4:
        raise SystemExit("usage: forsession.py PROF_BIN ROOT TASKS_FILE [N]")
    prof_bin, root, tasks_file = sys.argv[1], sys.argv[2], sys.argv[3]
    limit = int(sys.argv[4]) if len(sys.argv) > 4 else 99
    tasks = [t.strip() for t in open(tasks_file) if t.strip()][:limit]

    rc, err, err_path, ended = run_session(prof_bin, root, tasks)
    print(f"# session over {root}: {len(tasks)} `for` calls, a different task each time")
    print(f"# HOW IT ENDED: {ended}")
    for line in err.splitlines():
        if line.startswith("ripwire-timing"):
            print("  " + line)

    start, end = err.find("#PROF_TSV_BEGIN"), err.find("#PROF_TSV_END")
    if start < 0:
        print(f"!! no #PROF_TSV block — is {prof_bin} a -DRIPWIRE_PROFILE=ON build? "
              f"stderr kept at {err_path}", file=sys.stderr)
        return
    rows, unparsed = parse_tsv(err[start:end])
    if unparsed:
        # A silently dropped row is how a measurement harness reports a cost of zero for a scope it
        # merely failed to read. Say how many, and show one.
        print(f"!! {len(unparsed)} #PROF_TSV row(s) did not parse, e.g. {unparsed[0][:120]!r} — "
              f"the table below may be incomplete", file=sys.stderr)
    report(rows, tasks)
    print(f"\n  [stderr kept at {err_path}]")


if __name__ == "__main__":
    main()
