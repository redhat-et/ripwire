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
import re
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
def _root_key():
    return hashlib.sha1(root.encode("utf-8")).hexdigest()[:16]


def _timings_path():
    return os.path.join(tempfile.gettempdir(), f"ripwire-pargates-timings-{_root_key()}.json")


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
#
# binoverridecheck / estchargecheck / pagingsweepcheck (2026-08-23): the same story a third time, and the
# reds were counted as three separate mysteries before anyone lined them up. All three hit rc=124 at
# exactly 300.0-300.1 s on the ubuntu legs of CI run 32609218692 -- "exactly the budget" is the signature
# of a cap, not of a hang, and a real hang does not stop at the cap on four legs and finish in under a
# minute on the fifth. Measured on an idle dev machine against the same commit: 54 s, 26 s and 34 s wall.
# binoverridecheck is the heaviest because it is a META-gate -- it re-runs a slice of the suite against a
# sentinel binary, so it pays the suite's own cost while competing for the same -j 3 -- which is why it
# also overran on macos-14 Release where the other two fit. A 4-vCPU runner at -j 3 is roughly a 6-11x
# multiplier on these, putting the honest CI numbers well past 300 s and under 900 s; 900 matches what the
# six *importprecisecheck/*condcheck entries above already use for the same reason. Per the house rule
# that build and CI cost never gate on wall clock, a budget here is a hang tripwire, not a perf bar.
DEFAULT_TIMEOUT_SEC = 300
GATE_BUDGET_SEC = {
    "crossdirincludecheck.sh":    900,
    "nestedimportcheck.sh":       900,
    "preproccondcheck.sh":        900,
    "pyimportprecisecheck.sh":    900,
    "rustimportprecisecheck.sh":  900,
    "tsimportprecisecheck.sh":    900,
    "bodydialectcheck.sh":        900,   # T3 gave --for/--pack-task real body assembly (v0.3.5/6);
                                         # ~160 s CPU -- a plain -O0 CI runner overruns the flat cap
                                         # while a healthy local run takes ~17 s wall.
    "binoverridecheck.sh":        900,   # meta-gate: re-runs a suite slice against a sentinel binary,
                                         # so it pays the suite's cost while competing for the same -j.
                                         # ~54 s idle local; rc=124 at the flat cap on 5 of 6 CI legs.
    "estchargecheck.sh":          900,   # ~26 s idle local; rc=124 at the flat cap on all ubuntu legs.
    "pagingsweepcheck.sh":        900,   # ~34 s idle local; rc=124 at the flat cap on all ubuntu legs.
    "slicediffcheck.sh":          900,   # replays 57 labelled commits (checkout + --slice --since each); ~80 s local
    # 2026-09-05 (capture-audit round landed, CI run 33978240573): three universe-sweep gates from that round hit
    # rc=124 at exactly 300.0-300.1 s -- the cap signature again, not a hang. compactlegendcheck overran on ALL
    # FIVE failing legs (it runs the compact legend rewrite over every XML verb, full and compact, plus the MCP
    # twins), shapingflagcheck on the four ubuntu legs (every kShapingVerbs row probed on a shape where the budget
    # binds, un-budgeted and budgeted), collectioncapcheck on macos-14 Release only (15 s idle local -- it lost
    # the CPU to the two above at -j 3, the pagingsweepcheck story). Measured on the dev machine with the three
    # running concurrently: 107 s, 166 s, 15 s wall. At the runner's 6-11x, the first two land past 900, so they
    # take the 1200 that cppbenchcheck/regexbombcheck already use; collectioncapcheck takes 900 like pagingsweep.
    # Making the two sweeps cheaper (one ingest shared across probes) is registered for the terminality round's
    # battery-hygiene lane; a budget here is the hang tripwire, never the perf bar.
    #
    # 2026-09-05, LATER (terminality round A, lane V2): that registered work LANDED, and these two rows come
    # DOWN 1200 -> 900. Both gates now redirect $TMPDIR into their own scratch dir and warm each root they
    # probe ONCE, instead of passing --no-cache on every probe; the private TMPDIR is what makes a warm probe
    # safe beside a parallel battery, because both gates assert byte-identity between two runs of the same
    # argv and a sibling gate's blob write would otherwise move a cache-reporting row (--doctor's cache-dir
    # bytes=) between them. Identical arm sets before and after, ALL PASS both ways.
    #
    # THE ARITHMETIC, measured the same way the paragraph above measured it -- the three gates running
    # concurrently on the dev machine, before and after, same machine, same binary:
    #     compactlegendcheck  74.1 s -> 53.9 s   (-27%)      solo: 68.6 s -> 49.4 s
    #     shapingflagcheck   107.2 s -> 71.1 s   (-34%)      solo: 105.6 s -> 66.5 s
    #     collectioncapcheck   8.8 s ->  9.6 s   (untouched; the noise band on this measurement)
    # Scaling the budget by the measured ratio: 1200 x 53.9/74.1 = 873 and 1200 x 71.1/107.2 = 796 -- both
    # land on the 900 tier pagingsweep/collectioncap already use. Cross-checked against the runner factor
    # this file's own rows are derived from: at 6-11x, 53.9 s projects to 323-593 s and 71.1 s to 427-782 s,
    # so 900 still clears the SLOWEST projection with headroom, which is the property a hang tripwire needs.
    # NOT taken: 4x the local wall (216 s / 284 s). That is below the flat 300 s default and would re-create
    # exactly the rc=124 reds these rows were added to fix -- these gates got ~30% cheaper, not 4x cheaper,
    # and a budget has to survive the slowest leg, not the machine it was measured on.
    # WHERE THE REST OF THE TIME IS, so the next lane does not re-run this experiment: profiled with a
    # timing shim, shapingflagcheck makes 890 binary invocations totalling well under a third of its wall.
    # The binary is no longer the dominant cost of either gate -- the residual is the per-row shell/awk/
    # python glue of the universe sweeps. Another round of ingest-sharing buys nothing; only fewer
    # subprocesses per row would.
    #
    # 2026-09-05, LATER STILL (terminality round A wave-2 verifier, N1; lane V3): shapingflagcheck goes back
    # UP to 1200 and compactlegendcheck STAYS at 900. Nothing about the gates changed -- the BASIS did. V2
    # measured the pair with only their two siblings running; the verifier re-timed them at the same commit
    # under a full parallel battery (load average 19), which is the contention shape a CI leg at -j actually
    # has and closer to it than a three-gates-only run. Both ALL PASS; the walls are higher:
    #     gate                V2 concurrent   V2 solo   verifier, LOADED   x6      x11     budget   margin
    #     compactlegendcheck        53.9 s     49.4 s          69 s       414 s   759 s     900     141 s
    #     shapingflagcheck          71.1 s     66.5 s          80 s       480 s   880 s     900      20 s
    # At the 6-11x runner factor THIS FILE's own rows are derived from (see the header paragraph),
    # compactlegendcheck projects to 759 s at the top of the range and clears 900 by 16%; shapingflagcheck
    # projects to 880 s and clears it by 20 s, which is 2.2% -- less headroom than the round's own
    # measurement noise, on the gate CI run 33978240573 went red on across four ubuntu legs. A budget here is
    # a hang tripwire, never a perf bar (the house rule that build and CI cost never gate on wall clock), so
    # the two errors are not symmetric: a too-generous budget costs nothing at all, and a thin one costs a
    # red CI leg and the hour spent re-deciding whether it was a hang. 1200 is the tier
    # cppbenchcheck/regexbombcheck already use for exactly this reason. compactlegendcheck's 141 s is real
    # headroom and is left alone -- the row that needs the margin is the one that gets it.
    "compactlegendcheck.sh":      900,
    "shapingflagcheck.sh":       1200,
    "collectioncapcheck.sh":      900,
                                          # under -j6, rc=124 at the flat cap on both ubuntu PLAIN legs of run
                                          # 33762934972 (Release legs and macOS fit). Warm replay landed with this row.
    "cppbenchcheck.sh":          1200,
    "regexbombcheck.sh":         1200,
}
parallel_gates = [g for g in gates if g not in exclusive]
exclusive_gates = [g for g in gates if g in exclusive]


# --- a failing gate's output: kept whole, and summarised by the line that FAILED ------------------
# (F1/F2, terminality round A 2026-09-05.) The summary used to print a failing gate's last 12 non-blank
# lines out of a 2500-char tail, which is the wrong 12 lines for the way this repo's gates are written:
# a gate prints `  FAIL  arm (X) ...` at the moment the arm fails and then keeps going through its
# remaining arms, so the tail is a wall of PASS rows and a closing `SOME CHECKS FAILED`. That is
# literally what three rounds of readers saw -- V1 ("eleven PASS lines then SOME FAILED"), V2 and the
# capture-audit close all recorded the same loss, each time for `gitstampcheck`, and each time the arm
# that failed stayed unknown. Printing FEWER trailing lines would not have helped; the fix is to select
# the failure-carrying lines, not to move the window.
#
# Three changes, all in service of "a red names what failed":
#   1. stdout and stderr are captured MERGED, in the order the gate wrote them (stderr=STDOUT), instead
#      of concatenated after the fact -- a message written to stderr next to the FAIL row it explains
#      no longer teleports to the end of the transcript.
#   2. A failing gate's FULL output is written to FAIL_LOG_DIR/<gate>.log and the path is printed. The
#      summary is a summary; nothing is destroyed by it any more.
#   3. The summary prints, in this order: the failure-shaped lines with their line numbers, then the
#      LAST 5 lines of the transcript. Failure shapes are the repo's own markers first, anchored and
#      case-sensitive (`  FAIL  `, `FAILURES ABOVE`, `SOME CHECKS FAILED`, `TIMEOUT after`) exactly as
#      regression.sh's absorb window does it, so a PASS row whose prose contains the word "fail" cannot
#      hijack the selection; only if a gate produced none of those (it died before its own reporting)
#      do the loose shapes -- `error:`, `fatal`, `Sanitizer`, a Python traceback, a missing binary --
#      get a turn.
FAIL_TAIL_LINES = 5
FAIL_MARK_LINES = 10
_MARKER_RE = re.compile(r"^\s*FAIL\b|^FAILURES ABOVE|SOME CHECKS FAILED|^\s*TIMEOUT after")
_LOOSE_RE = re.compile(r"error:|fatal|Sanitizer|Traceback|command not found|no ripwire binary|required$")


def _fail_log_dir():
    return os.path.join(tempfile.gettempdir(), f"ripwire-pargates-fails-{_root_key()}")


def failure_lines(out):
    """The lines a reader needs: the markers this repo's gates print when an arm fails."""
    lines = out.splitlines()
    marked = [(i + 1, ln) for i, ln in enumerate(lines) if ln.strip() and _MARKER_RE.search(ln)]
    if not marked:
        marked = [(i + 1, ln) for i, ln in enumerate(lines) if ln.strip() and _LOOSE_RE.search(ln)]
    return marked


def failure_report(out, logpath):
    """The block printed under FAILURES for one gate: what failed, then how it ended, then where the
    whole thing is. Composed here so the run's result rows stay small -- only this summary is carried
    back from the worker, never every gate's full transcript."""
    lines = out.splitlines()
    total = len(lines)
    marked = failure_lines(out)
    block = []
    if marked:
        block.append(f"what failed ({len(marked)} failure-shaped line(s)):")
        for lineno, ln in marked[:FAIL_MARK_LINES]:
            block.append(f"  L{lineno}: {ln}")
        if len(marked) > FAIL_MARK_LINES:
            block.append(f"  ... {len(marked) - FAIL_MARK_LINES} more — see the full log")
    else:
        block.append("what failed: no failure-shaped line in the transcript (the gate died before its own reporting)")
    tail = [(i + 1, ln) for i, ln in enumerate(lines) if ln.strip()][-FAIL_TAIL_LINES:]
    block.append(f"last {len(tail)} line(s) of {total}:")
    for lineno, ln in tail:
        block.append(f"  L{lineno}: {ln}")
    block.append(f"full output: {logpath}")
    return "\n".join(block)


def run(g):
    env = dict(os.environ, RIPWIRE_BIN=binp)
    limit = GATE_BUDGET_SEC.get(g, DEFAULT_TIMEOUT_SEC)
    t0 = time.time()
    try:
        p = subprocess.run(
            ["bash", os.path.join(testdir, g)],
            cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=limit,
        )
        rc, out = p.returncode, p.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired as e:
        # the budget itself is part of the message -- a red names its own declared budget instead of
        # making the reader go look it up in GATE_BUDGET_SEC. Whatever the gate managed to print before
        # the budget expired is kept ahead of it: a gate killed at 300 s that had already announced a
        # failing arm used to report ONLY the word TIMEOUT.
        partial = (e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, (bytes, bytearray)) else (e.stdout or "")
        rc, out = 124, partial + f"\nTIMEOUT after {limit}s (declared budget={limit}s)"
    # A gate that SKIPS is not a gate that PASSED. argvdiffcheck skips without a RIPWIRE_BASE
    # reference binary, and reporting that as a pass is exactly the green-while-inert failure this
    # suite exists to catch elsewhere (the CI/NDEBUG blindness is the same family).
    skipped = rc == 0 and "SKIP" in out[:400]
    report = ""
    if skipped:
        report = out[:2000]                      # enough for the caller to quote the SKIP's own reason
    elif rc != 0:
        # best-effort: a full-output write that fails must never turn the report into a second failure.
        logpath = "(not written)"
        try:
            d = _fail_log_dir()
            os.makedirs(d, exist_ok=True)
            logpath = os.path.join(d, g + ".log")
            with open(logpath, "w") as fh:
                fh.write(out)
        except OSError:
            logpath = "(not written)"
        report = failure_report(out, logpath)
    return g, rc, round(time.time() - t0, 1), report, skipped


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
    for g, rc, dt, report, _sk in fails:
        print(f"\n=== {g} (rc={rc}, {dt}s) ===")
        print("\n".join("    " + ln for ln in report.splitlines()))
else:
    print("\nALL PASS")

if jsonout:
    with open(jsonout, "w") as fh:
        json.dump({g: {"rc": rc, "sec": dt, "skipped": sk} for g, rc, dt, _, sk in results}, fh, indent=1)
sys.exit(1 if fails else 0)
