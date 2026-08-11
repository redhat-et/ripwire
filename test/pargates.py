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

# A wall-clock budget cannot be interpreted while five unrelated compiler/git-heavy gates are saturating
# the machine beside it. Keep the measured gate in this same authoritative run, but give its timing window
# exclusive ownership after the parallel correctness wave.
exclusive = {"editcheckcheck.sh"}

# --- per-gate budget overrides (W1-V4, 2026-08-11) ---------------------------------------------
# A flat cap is wrong for the minority of gates whose HONEST work exceeds it -- the fix is a per-gate
# override, not a raised global ceiling that would blunt the tripwire for the other ~370 gates that
# really do finish in seconds. This is a declared table (gate name -> budget seconds), not a marker
# line grepped out of each gate file: the table is the single place a reviewer checks "is this gate's
# timeout honest", and it can't drift out of sync with a comment buried in a script nobody re-reads.
#
# DEFAULT_TIMEOUT_SEC applies to every gate not named below.
#
# The six *importprecisecheck/*condcheck entries build a SECOND ripwire from git HEAD to diff today's
# resolver against it, sharing one sha-keyed binary through test/lib/headbinlib.sh: one elected
# builder, the rest wait on its lock. A full build is ~50s on the dev machine but several minutes on a
# 4-vCPU CI runner with -j 3 gates already competing for it, so DEFAULT_TIMEOUT_SEC is not a budget
# for them -- it is shorter than the work. Measured: rc=124 at 300.1 s on ALL FOUR Linux legs of CI run
# 31182301976, green on macOS where the same build fits in ~60 s. headbinlib.sh's own waiter budget
# must stay well under 900 -- its comment explains the coupling.
#
# cppbenchcheck / regexbombcheck: legitimate ASan-on-a-cold-cache work, not a hang -- ~856 s and ~804 s
# measured respectively -- so the old flat 300 s cap read a healthy run as a timeout. 1200 s leaves
# headroom above both measurements without being so loose it stops meaning anything.
DEFAULT_TIMEOUT_SEC = 300
GATE_BUDGET_SEC = {
    "crossdirincludecheck.sh":    900,
    "nestedimportcheck.sh":       900,
    "preproccondcheck.sh":        900,
    "pyimportprecisecheck.sh":    900,
    "rustimportprecisecheck.sh":  900,
    "tsimportprecisecheck.sh":    900,
    "cppbenchcheck.sh":          1200,
    "regexbombcheck.sh":         1200,
}
parallel_gates = [g for g in gates if g not in exclusive]
exclusive_gates = [g for g in gates if g in exclusive]


def run(g):
    env = dict(os.environ, RIPWIRE_BIN=binp)
    limit = GATE_BUDGET_SEC.get(g, DEFAULT_TIMEOUT_SEC)
    t0 = time.time()
    try:
        p = subprocess.run(
            ["bash", os.path.join(testdir, g)],
            cwd=root, env=env, capture_output=True, timeout=limit,
        )
        rc, out = p.returncode, (p.stdout + p.stderr).decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        # the budget itself is part of the message -- a red names its own declared budget instead of
        # making the reader go look it up in GATE_BUDGET_SEC.
        rc, out = 124, f"TIMEOUT after {limit}s (declared budget={limit}s)"
    # A gate that SKIPS is not a gate that PASSED. argvdiffcheck skips without a RIPWIRE_BASE
    # reference binary, and reporting that as a pass is exactly the green-while-inert failure this
    # suite exists to catch elsewhere (the CI/NDEBUG blindness is the same family).
    skipped = rc == 0 and "SKIP" in out[:400]
    return g, rc, round(time.time() - t0, 1), out[-2500:], skipped


# --- shared-binary tripwire ---------------------------------------------------------------------
# A gate that rebuilds the binary under test hands every CONCURRENT gate either a missing file
# (rc=2, "no ripwire binary") or one the loader refuses while the linker still holds it
# (ETXTBSY -> exit 126, printed as "Permission denied"). CI run 31145553507 lost 126 of 361 gates
# that way to naminglocalscheck.sh's old source-mutation arm, and every one of the 126 reported a
# plausible-looking failure of its OWN subject -- swiftcheck "non-deterministic", rubymetricscheck
# "ccx should be > 0", type3check "XML not well-formed". Reading that log costs an hour before the
# common cause is visible. Fingerprint the binary before and after: if it moved, say so first, and
# say it loudly enough that nobody triages the 126 individually.
def _bin_fingerprint():
    try:
        st = os.stat(binp)
        return (st.st_size, st.st_mtime_ns, st.st_ino)
    except OSError:
        return None


bin_before = _bin_fingerprint()

t0 = time.time()
results = []
with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
    for r in ex.map(run, parallel_gates):
        results.append(r)
        sys.stderr.write("s" if r[4] else ("." if r[1] == 0 else "X"))
        sys.stderr.flush()
for g in exclusive_gates:
    r = run(g)
    results.append(r)
    sys.stderr.write("s" if r[4] else ("." if r[1] == 0 else "X"))
    sys.stderr.flush()
sys.stderr.write("\n")

bin_after = _bin_fingerprint()
bin_moved = bin_before != bin_after

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
if bin_moved:
    print(f"\n*** THE BINARY UNDER TEST CHANGED WHILE THE SUITE RAN: {binp}")
    print(f"***   before={bin_before}  after={bin_after}")
    print("***   Some gate rebuilt it in place. Every gate that ran concurrently saw it missing")
    print("***   (rc=2) or busy (exit 126 / 'Permission denied'), so THOSE FAILURES ARE NOT REAL.")
    print("***   Find the gate that writes to the shared build tree and fix that first.")
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
