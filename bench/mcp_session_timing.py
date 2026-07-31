#!/usr/bin/env python3
"""Measure analyze requests inside one already-started ripwire MCP stdio session."""

import json
import statistics
import subprocess
import sys
import tempfile
import time
import os


def exchange(process: subprocess.Popen[str], request: dict) -> dict:
    assert process.stdin is not None and process.stdout is not None
    process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
    process.stdin.flush()
    line = process.stdout.readline()
    if not line:
        raise RuntimeError("ripwire MCP closed before responding")
    return json.loads(line)


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: mcp_session_timing.py RIPWIRE_BIN CORPUS RUNS", file=sys.stderr)
        return 2
    binary, corpus, runs_text = sys.argv[1:]
    runs = int(runs_text)
    if runs < 5:
        raise RuntimeError("MCP timing requires at least five requests")
    timing_log = tempfile.TemporaryFile(mode="w+t")
    environment = os.environ.copy()
    environment["RIPWIRE_MCP_TIMINGS"] = "1"
    process = subprocess.Popen(
        [binary, "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=timing_log,
        text=True, bufsize=1, env=environment,
    )
    try:
        initialized = exchange(process, {"jsonrpc": "2.0", "id": 1, "method": "initialize"})
        if initialized.get("id") != 1 or "result" not in initialized:
            raise RuntimeError("initialize semantic preflight failed")
        warm = exchange(process, {
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "analyze", "arguments": {"path": corpus}},
        })
        if warm.get("id") != 2 or "result" not in warm:
            raise RuntimeError("unmeasured warm request semantic preflight failed")
        samples = []
        for sample_index in range(runs):
            request_id = sample_index + 3
            request = {
                "jsonrpc": "2.0", "id": request_id, "method": "tools/call",
                "params": {"name": "analyze", "arguments": {"path": corpus}},
            }
            begin = time.perf_counter()
            response = exchange(process, request)
            samples.append((time.perf_counter() - begin) * 1000.0)
            if response.get("id") != request_id or "result" not in response:
                raise RuntimeError(f"analyze semantic preflight failed for id {request_id}")
    finally:
        if process.stdin is not None:
            process.stdin.close()
        process.wait(timeout=10)
    timing_log.seek(0)
    timing_lines = [line.strip() for line in timing_log if "verb=analyze" in line]
    timing_log.close()
    if len(timing_lines) != runs + 1:
        raise RuntimeError(f"expected {runs + 1} analyze timing records, got {len(timing_lines)}")
    if any("rebuilt=0" not in line for line in timing_lines[1:]):
        raise RuntimeError("a timed MCP request rebuilt its index instead of using the warm session")
    print(f"{statistics.median(samples):.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
