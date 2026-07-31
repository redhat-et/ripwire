#!/usr/bin/env python3
"""Run every test/*check.sh gate in parallel and report pass/fail.

The repo's own test/regression.sh runs ~210 gates in ONE sequential for-loop, which
exceeds the agent harness time ceiling. This runs the same scripts concurrently so a
full verification fits in one window. It does NOT modify regression.sh.

usage: pargates.py <repo-root> <ripwire-bin> [-j N] [--only substr] [--json out.json]
"""
import concurrent.futures as cf
import json
import os
import subprocess
import sys
import time

root = os.path.abspath(sys.argv[1])
binp = os.path.abspath(sys.argv[2])
jobs = 6
only = None
jsonout = None
args = sys.argv[3:]
for i, a in enumerate(args):
    if a == "-j":
        jobs = int(args[i + 1])
    elif a == "--only":
        only = args[i + 1]
    elif a == "--json":
        jsonout = args[i + 1]

testdir = os.path.join(root, "test")
# item 7 (§B12 polish round): os.listdir returns dotfiles too (unlike a shell glob without dotglob), so a
# leftover probe script such as a gate's own `.gateprobe.*.sh` scratch file would be discovered and RUN AS
# A GATE. Skip anything starting with "." — a real gate is never a dotfile.
gates = sorted(f for f in os.listdir(testdir) if f.endswith(".sh") and not f.startswith("."))
# regression.sh is the driver itself; det-gate is invoked inside it.
skip = {"regression.sh"}
gates = [g for g in gates if g not in skip]
if only:
    gates = [g for g in gates if only in g]


def run(g):
    env = dict(os.environ, RIPWIRE_BIN=binp)
    t0 = time.time()
    try:
        p = subprocess.run(
            ["bash", os.path.join(testdir, g)],
            cwd=root, env=env, capture_output=True, timeout=300,
        )
        rc, out = p.returncode, (p.stdout + p.stderr).decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        rc, out = 124, "TIMEOUT after 300s"
    # A gate that SKIPS is not a gate that PASSED. argvdiffcheck skips without a RIPWIRE_BASE
    # reference binary, and reporting that as a pass is exactly the green-while-inert failure this
    # suite exists to catch elsewhere (the CI/NDEBUG blindness is the same family).
    skipped = rc == 0 and "SKIP" in out[:400]
    return g, rc, round(time.time() - t0, 1), out[-2500:], skipped


t0 = time.time()
results = []
with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
    for r in ex.map(run, gates):
        results.append(r)
        sys.stderr.write("s" if r[4] else ("." if r[1] == 0 else "X"))
        sys.stderr.flush()
sys.stderr.write("\n")

fails = [r for r in results if r[1] != 0]
skips = [r for r in results if r[4]]
slow = sorted(results, key=lambda r: -r[2])[:8]

print(f"gates={len(results)} pass={len(results)-len(fails)-len(skips)} "
      f"skip={len(skips)} fail={len(fails)} wall={round(time.time()-t0,1)}s jobs={jobs}")
if skips:
    print("\nSKIPPED (ran, but proved nothing — not counted as passing):")
    for g, rc, dt, out, _ in skips:
        why = next((ln.strip() for ln in out.splitlines() if "SKIP" in ln), "")
        print(f"  {g}  {why}")
print(f"bin={binp}")
print("\nslowest:")
for g, rc, dt, _, _sk in slow:
    print(f"  {dt:6.1f}s  {g}")
if fails:
    print("\nFAILURES:")
    for g, rc, dt, out, _sk in fails:
        print(f"\n=== {g} (rc={rc}, {dt}s) ===")
        tail = [ln for ln in out.splitlines() if ln.strip()][-12:]
        print("\n".join("    " + ln for ln in tail))
else:
    print("\nALL PASS")

if jsonout:
    with open(jsonout, "w") as fh:
        json.dump({g: {"rc": rc, "sec": dt, "skipped": sk} for g, rc, dt, _, sk in results}, fh, indent=1)
sys.exit(1 if fails else 0)
