#!/usr/bin/env python3
"""Run every test/*check.sh gate in parallel and report pass/fail.

The repo's own test/regression.sh runs ~210 gates in ONE sequential for-loop, which
exceeds the agent harness time ceiling. This runs the same scripts concurrently so a
full verification fits in one window. It does NOT modify regression.sh.

usage: pargates.py <repo-root> <ripwire-bin> [-j N] [--only substr] [--json out.json]
"""
import concurrent.futures as cf
import hashlib
import json
import os
import subprocess
import sys
import tempfile
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

# --- longest-first (LPT) scheduling -----------------------------------------------------------
# A greedy scheduler minimizes wall time by handing the slowest jobs to workers FIRST -- a long
# gate started late is a long gate that ends up running solo after every worker finishes its
# short queue. We persist each gate's measured seconds across runs and sort by that next time.
#
# The timings file must NOT live under test/ (item 7 above already burned us once on a scanner
# that discovers anything in that directory and treats it as a gate) and must not need
# committing -- it's a per-machine measurement, not project state. tempfile.gettempdir() honors
# $TMPDIR first, same as the binary's own cacheDirLadder(), so this is the same convention the
# rest of the repo already uses for scratch state. Keyed by the repo root's absolute path (hashed,
# so worktrees/checkouts of the same repo at different paths don't collide or share a stale file).
def _timings_path():
    key = hashlib.sha1(root.encode("utf-8")).hexdigest()[:16]
    return os.path.join(tempfile.gettempdir(), f"ripwire-pargates-timings-{key}.json")


def _load_timings(path):
    # Corrupt/missing/foreign-shaped JSON must degrade to "no history" -- never crash the run.
    # A stale or hand-edited file is exactly the kind of thing that WILL show up in the wild.
    try:
        with open(path) as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            return {g: dt for g, dt in data.items() if isinstance(dt, (int, float))}
    except (OSError, ValueError):
        pass
    return {}


prior_timings = _load_timings(_timings_path())

# Sort longest-first using recorded durations. A gate with NO recorded duration is unknown, not
# fast -- treat it as potentially the slowest thing in the batch (float('inf')) so it schedules
# EARLY, alongside the known-long gates, rather than drifting to the tail of the run where an
# unlucky first-time-seen slow gate would extend the wall clock the same way a genuinely-slow
# gate starting late would.
gates.sort(key=lambda g: -prior_timings.get(g, float("inf")))


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

# Persist fresh durations for next run's LPT sort. Best-effort: a write failure (read-only temp
# dir, a concurrent pargates run racing us) must not turn a passing gate run into a failing one --
# worst case the next run just falls back to whatever it could load, same as a missing file today.
# Written via a pid-suffixed temp file + os.replace so a concurrent writer never sees a half-written
# JSON file (os.replace is an atomic rename on POSIX).
try:
    tpath = _timings_path()
    ttmp = f"{tpath}.tmp{os.getpid()}"
    with open(ttmp, "w") as fh:
        json.dump({g: dt for g, rc, dt, _out, _sk in results}, fh)
    os.replace(ttmp, tpath)
except OSError:
    pass

# --- slowness tripwire -------------------------------------------------------------------------
# A gate that quietly grows from 1s to 8s over a series of unrelated commits is invisible in the
# "slowest" top-8 (it's still nowhere near the top) and doesn't fail anything -- so nobody notices
# until it's a 60s gate someone finally complains about. Flag it the day it happens: >=2x its own
# prior measurement AND over 5s absolute, so a gate going from 0.1s to 0.3s (3x, but trivial) stays
# quiet. Non-failing by design -- this is a heads-up, not a gate of its own, so it must never touch
# the exit code below.
tripwire = []
for g, rc, dt, _out, _sk in results:
    prev = prior_timings.get(g)
    if prev and dt >= 2 * prev and dt > 5.0:
        tripwire.append((g, prev, dt))

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
if tripwire:
    print("\nSLOWER (>=2x prior measured time and over 5s -- not a failure, worth a look):")
    for g, prev, dt in sorted(tripwire, key=lambda t: -t[2]):
        print(f"  {g}  {prev:.1f}s -> {dt:.1f}s")
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
