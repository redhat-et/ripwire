#!/usr/bin/env python3
"""forsession.py — the per-WARM-QUERY cost of personalized ranking, which is the only framing in
which RANK-SPEED step 2 can be judged.

WHY THIS SHAPE. `rankGraphTeleport` is the PERSONALIZED rank: it runs once per query, from a
different seed set each time. `buildGraph` runs once per index. Comparing them as shares of one cold
run prices a per-call cost against a one-time one -- the same amortisation error that makes the git
walk look expensive until the qchurn cache is accounted for. So this harness drives ONE MCP session
that holds the graph in memory and issues N `for` calls with N DIFFERENT tasks, which is the real
agent use case, and reads the per-scope aggregate the profile build prints at exit:

    rankGraph: PageRank (power iteration)   calls=N  total_ms=<sum over the N queries>

calls=N is the proof that the scope really ran per query rather than once, and total_ms/N is the
per-warm-query ranking cost. `main: query + emit` beside it, also calls=N, is the rest of the verb.
An `ingest: total` with calls=1 confirms the session paid ingest once, not per call.

usage: forsession.py PROF_BIN ROOT TASKS_FILE [N]
"""
import json
import os
import select
import subprocess
import sys
import tempfile
import time

# WHY STDERR GOES TO A FILE AND NOT A PIPE. The first version of this harness gave the child
# stderr=PIPE and drained it only after closing stdin. That is a deadlock by construction: once the
# 64 KiB pipe buffer fills, the server blocks WRITING stderr while this process blocks READING
# stdout, and neither can proceed. Both sides sat at 0.0% CPU for 16 minutes on llvm-project.
# `bench/largescale.py`'s own run_once already routes child stderr to a file for exactly this
# reason, with a comment saying so, and I did not apply it here.
#
# WHAT FILLED IT IS UNCONFIRMED, and an earlier version of this comment guessed wrong. It blamed
# "a run of `[math degraded]` alerts" on llvm-project. Counted, llvm-project emits exactly TWO such
# lines, one per site as designed (~400 bytes), so they cannot fill 64 KiB and were not the cause.
# The profile report printed at exit -- the human table plus the #PROF_TSV block, one row per scope
# per rendering, over ~100 scopes for a rich llvm ingest -- is the plausible writer, but the stderr
# of the deadlocked run was lost with the process, so this is a hypothesis and is labelled one.
# The fix does not depend on which writer it was: an undrained pipe deadlocks whatever fills it.
# A deadline on every read is the second half: a hang now fails one cell instead of the lane.
REPLY_TIMEOUT_S = 600.0


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


def report(rows, scopes):
    print(f"\n  {'calls':>6} {'total_ms':>10} {'per_call_ms':>12}  scope")
    for scope in scopes:
        if scope in rows:
            calls, ms = rows[scope]
            print(f"  {calls:>6} {ms:>10.1f} {ms / max(calls, 1):>12.2f}  {scope}")


def main():
    prof_bin, root, tasks_file = sys.argv[1], sys.argv[2], sys.argv[3]
    tasks = [t.strip() for t in open(tasks_file) if t.strip()][: int(sys.argv[4]) if len(sys.argv) > 4 else 99]

    env = dict(os.environ)
    env["RIPWIRE_MCP_TIMINGS"] = "1"
    errf = tempfile.NamedTemporaryFile(prefix="forsession-err-", suffix=".txt", delete=False)
    proc = subprocess.Popen([prof_bin, "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=errf, env=env, text=True, bufsize=1)

    def call(method, params, rid):
        proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": rid, "method": method,
                                     "params": params}) + "\n")
        proc.stdin.flush()
        t0 = time.perf_counter()
        ready, _, _ = select.select([proc.stdout], [], [], REPLY_TIMEOUT_S)
        if not ready:
            proc.kill()
            raise SystemExit(f"!! no reply to {method} within {REPLY_TIMEOUT_S:.0f}s — cell failed, "
                             f"not hung (child killed); stderr at {errf.name}")
        line = proc.stdout.readline()
        return time.perf_counter() - t0, len(line)

    call("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                        "clientInfo": {"name": "forsession", "version": "1"}}, 1)
    print(f"# session over {root}: {len(tasks)} `for` calls, different task each time")
    for i, task in enumerate(tasks):
        wall, nbytes = call("tools/call", {"name": "for", "arguments": {"path": root, "task": task}}, i + 2)
        print(f"  call {i + 1:2d}  wall {wall * 1000:8.1f} ms  reply {nbytes:7d} B  task={task[:52]!r}")
    proc.stdin.close()
    proc.wait()
    errf.flush()
    err = open(errf.name, errors="replace").read()

    # the per-scope aggregate the profile build prints at exit
    start, end = err.find("#PROF_TSV_BEGIN"), err.find("#PROF_TSV_END")
    if start < 0:
        print("!! no #PROF_TSV block -- is this the -DRIPWIRE_PROFILE=ON binary?", file=sys.stderr)
        print(err[-1500:], file=sys.stderr)
        return

    want = ("rankGraph: PageRank (power iteration)",
            "main: query + emit (the verb, after the graph)",
            "lexical: lexicalScores (BM25 over symbols)",
            "lexical: lexicalScoresNameExact (whole-name BM25 over symbols)",
            "lexical: pass 2 via persisted subtoken stats (cached tf/dl, no corpus re-tokenize)",
            "main: computeQMetrics + change-amplification",
            "buildGraph: resolve refs + build CSR",
            "ingest: total (crawl + parse + model)",
            "gitmine: popenTrimmed (one shell + git child, block read)")
    rows, unparsed = parse_tsv(err[start:end])
    if unparsed:
        # A silently dropped row is how a measurement harness reports a cost of zero for a scope it
        # simply failed to read. Say how many and show one, rather than passing on the exception.
        print(f"!! {len(unparsed)} #PROF_TSV row(s) did not parse, e.g. {unparsed[0][:120]!r} — "
              f"the scopes below may be incomplete", file=sys.stderr)
    report(rows, want)
    for line in err.splitlines():
        if line.startswith("ripwire-timing"):
            print("  " + line)


if __name__ == "__main__":
    main()
