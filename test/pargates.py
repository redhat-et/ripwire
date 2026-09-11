#!/usr/bin/env python3
"""Run every test/*check.sh gate in parallel and report pass/fail.

The repo's own test/regression.sh runs ~210 gates in ONE sequential for-loop, which
exceeds the agent harness time ceiling. This runs the same scripts concurrently so a
full verification fits in one window. It does NOT modify regression.sh.

usage: pargates.py <repo-root> <ripwire-bin> [-j N] [--only substr] [--json out.json]
                   [--shard K/N] [--shard-plan] [--budget-scale F] [--exclude-list FILE]
"""
import concurrent.futures as cf
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time

root = os.path.abspath(sys.argv[1])
binp = os.path.abspath(sys.argv[2])
jobs = 6
only = None
jsonout = None
shard = None          # (k, n): run only the k-th of n deterministic slices of the gate list
shard_plan = False    # print every slice's membership and predicted weight, run nothing
budget_scale = 1.0    # scales the DEFAULT budget; a declared override acts as a FLOOR under it -- CI passes >1
exclude_list = None   # a committed file naming gates this leg does not run (one per line, # comments)
args = sys.argv[3:]
for i, a in enumerate(args):
    if a == "-j":
        jobs = int(args[i + 1])
    elif a == "--only":
        only = args[i + 1]
    elif a == "--json":
        jsonout = args[i + 1]
    elif a == "--shard":
        k, n = args[i + 1].split("/")
        shard = (int(k), int(n))
        if not (1 <= shard[0] <= shard[1]):
            sys.exit(f"--shard K/N needs 1 <= K <= N, got {args[i + 1]}")
    elif a == "--shard-plan":
        shard_plan = True
    elif a == "--exclude-list":
        exclude_list = args[i + 1]
    elif a == "--budget-scale":
        budget_scale = float(args[i + 1])
        if budget_scale <= 0:
            sys.exit(f"--budget-scale needs a positive factor, got {args[i + 1]}")

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

# --exclude-list: a leg may decline a NAMED set of gates, and only by pointing at a committed file whose
# every line says which gate and why. The use it exists for (2026-09-07): the macOS plain leg -- an -O0
# binary on a 3-core runner -- was the critical path of the whole workflow at 33-37 min, and its four
# slowest gates (binoverridecheck, knownitemcheck, ripwirepubliccheck, xmlwellformed) assert nothing
# platform-specific and run unchanged on the macOS Release leg and all four Linux legs. Applied BEFORE the
# shard split so the remaining gates rebalance; the count is printed so a log reader sees the omission
# instead of inferring it from a shorter gate total. A name in the file that matches no gate is an error:
# a stale exclusion silently excluding nothing is how a list like this rots.
excluded = []
if exclude_list:
    with open(os.path.join(root, exclude_list)) as fh:
        wanted = [ln.split("#", 1)[0].strip() for ln in fh]
    wanted = [w for w in wanted if w]
    unknown = [w for w in wanted if w not in gates and not (only and only not in w)]
    if unknown and not only:
        sys.exit(f"--exclude-list {exclude_list} names gates that do not exist: {' '.join(unknown)}")
    excluded = [g for g in gates if g in wanted]
    gates = [g for g in gates if g not in wanted]
    print(f"exclude-list {exclude_list}: {len(excluded)} gate(s) not run on this leg: {' '.join(excluded)}")

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

# --- sharding: one deterministic slice of the suite per CI job -------------------------------------
# CI runs this suite on every release leg; at 560+ gates that is ~150 CPU-minutes, i.e. ~60 min wall at
# -j 3 on a 4-vCPU runner, and the wall clock of the whole workflow IS one leg's suite. Splitting the
# list across N runner jobs divides that. The split has to be (a) deterministic -- every job computes
# the same partition from the same inputs, no shared state -- and (b) balanced by cost, or the shard
# that draws binoverridecheck + pagingsweepcheck + knownitemcheck finishes last and nothing was gained.
# So the weights come from a COMMITTED table (.github/pargates-shard-weights.json: median measured
# seconds per gate, regenerated from the local timings file when the suite's shape moves), not from
# the per-machine scratch timings above, and the assignment is longest-processing-time-first: gates
# sorted by weight descending (name ascending on ties), each handed to the currently lightest shard.
# A gate missing from the table gets the table's median -- unknown is not free, and it is not the
# slowest thing in the batch either when the question is which shard, not which worker. The scheduler
# below still orders the shard's own gates by the local scratch timings, exactly as before.
def _shard_weights():
    path = os.path.join(root, ".github", "pargates-shard-weights.json")
    w = _load_timings(path) if os.path.isfile(path) else {}
    if not w:
        return {}, 1.0
    med = sorted(w.values())[len(w) // 2]
    return w, med


def shard_plan_for(gate_names, n):
    weights, median = _shard_weights()
    order = sorted(gate_names, key=lambda g: (-weights.get(g, median), g))
    buckets = [[] for _ in range(n)]
    load = [0.0] * n
    for g in order:
        i = min(range(n), key=lambda j: (load[j], j))
        buckets[i].append(g)
        load[i] += weights.get(g, median)
    return buckets, load


if shard_plan:
    n = shard[1] if shard else 4
    buckets, load = shard_plan_for(gates, n)
    for i, (b, w) in enumerate(zip(buckets, load), 1):
        print(f"shard {i}/{n}: {len(b)} gates, predicted {w:.0f}s")
    print(f"total {len(gates)} gates, predicted {sum(load):.0f}s; largest shard {max(load):.0f}s")
    sys.exit(0)

if shard:
    buckets, load = shard_plan_for(gates, shard[1])
    gates = buckets[shard[0] - 1]
    print(f"shard {shard[0]}/{shard[1]}: {len(gates)} gates, predicted {load[shard[0] - 1]:.0f}s "
          f"(largest shard {max(load):.0f}s)")

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
# Since 2026-09-10 CI no longer builds that binary inside any gate: ci.yml builds it in its own step BEFORE this
# harness starts and exports RIPWIRE_HEADBIN, and headbinlib's STAGED mode then never builds and never waits
# (test/headbinstagecheck.sh). No timeout could have fixed it -- the build is super-linear in the -j contention
# these budgets run under, so a slow draw outgrew 900 s and then 1200 s. The six numbers stay as declared because
# the unstaged path (a local run with RIPWIRE_HEADBIN unset) still builds inside the first gate and still waits.
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
# --budget-scale (2026-09-07, first sharded CI runs): the flat default is a HANG tripwire calibrated on an idle
# dev machine, and a 4-vCPU runner at -j 3 is a 3-8x multiplier on any gate's wall time (mcpframehonestycheck
# 151 s local -> rc=124 at 300.1 s; paginationcheck 53 s local -> rc=124 at 300.0 s). Sixty-four uncapped gates
# sit inside that multiplier of the cap, so per-gate entries would be the wrong shape -- and raising the constant
# itself would blunt the tripwire on the machines it was measured on. So CI passes a scale factor that applies
# to the DEFAULT, and a declared entry below acts as a FLOOR under it rather than a ceiling over it. The
# TIMEOUT message names the effective budget and the scale, so a red still names its own limit.
#
# The floor (2026-09-10) repairs an inversion the first shape had. Skipping the scale for declared entries
# meant that under CI's --budget-scale 4 the gates this table calls out as HEAVY were the only gates in the
# job running on LESS time than an ordinary one: crossdirincludecheck, which builds a whole second ripwire
# from git HEAD, got 900 s while xmlwellformed -- which pipes one map through xmllint -- got 300 x 4 = 1200.
# Measured on a CI run of main (34479806177, macos-14 Release shard 2/2): crossdirincludecheck rc=124 at
# 900.1 s in a shard whose wall was 3588.6 s, with xmlwellformed at 585.8 s and rootrelcheck at 345.9 s in
# the same job -- every gate on that runner ran 6-10x its idle-local wall, and only the UNDECLARED ones had
# a budget that had moved with it. max(declared, default x scale) keeps each declared number meaningful on
# the machine it was measured on (at scale 1.0 the declared value still wins, unchanged) and stops the table
# from buying a gate less time than saying nothing would have. It never loosens a tripwire below today.
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
    "mcpframehonestycheck.sh":    900,   # 2026-09-07 (first sharded CI run 34145918269): rc=124 at 300.1 s on three of
                                         # four Linux legs' shard 2 -- "exactly the cap" again. ~150 s local; a shard
                                         # job hands it fewer neighbours to hide behind than the whole suite did.
    "knownitemcheck.sh":          900,   # 2026-09-05: --eval-retrieval stopped sampling 150 symbols in PATH order and
                                         # now grades its whole population exhaustively (the sampler measured the corpus,
                                         # not the ranker -- docs/EVALS.md section 7). The gate runs it twice on src/ for
                                         # the determinism arm plus three bounded corpora for the order-independence arm:
                                         # ~132 s idle local, where it was ~10 s. Under the flat cap this is the same
                                         # rc=124-at-300.0 s signature the three gates above carry, and the two entries
                                         # directly above are 26 s and 34 s local -- a 4-vCPU leg running -j 3 has no
                                         # chance of fitting 132 s. Per the header: a budget here is a HANG TRIPWIRE,
                                         # not a perf bar; the eval is deliberately exhaustive and its cost is the price
                                         # of a number that no longer moves with a file's path.
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
    # PYTHONDONTWRITEBYTECODE: a gate that imports a module straight out of the checkout (agentlooplockcheck:
    # bench/agentloop/; aiderbytescheck: bench/headtohead/r4-2026-08-06/) would otherwise have Python drop a
    # __pycache__/ beside it. That directory is gitignored, so the tree tripwire below cannot see it, and its
    # name is on the crawl's built-in denylist, so every crawl of the live repo still counts it
    # (corpus_pruned_dirs=). Created between the two re-crawls of pagingsweepcheck's cold grep (G) pair, it
    # made that pair disagree on main twice (CI runs 34534320580, 34536435376). pargatescheck.sh pins it.
    env = dict(os.environ, RIPWIRE_BIN=binp, PYTHONDONTWRITEBYTECODE="1")
    scaled_default = int( round( DEFAULT_TIMEOUT_SEC * budget_scale ) )
    if g in GATE_BUDGET_SEC:
        # A declared entry is a FLOOR, not a ceiling: it is the number below which this gate would be a
        # hang even on an idle machine. It must never buy the gate LESS time than an undeclared one gets.
        declared = GATE_BUDGET_SEC[g]
        limit = max( declared, scaled_default )
        scaled = "" if limit == declared else f", declared {declared}s raised to the scaled default {DEFAULT_TIMEOUT_SEC}s x --budget-scale {budget_scale:g}"
    else:
        limit = scaled_default
        scaled = "" if budget_scale == 1.0 else f", default {DEFAULT_TIMEOUT_SEC}s x --budget-scale {budget_scale:g}"
    t0 = time.time()
    with running_lock:
        running.add(g)          # the tree tripwire names whoever is in flight when it sees new dirt
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
        rc, out = 124, partial + f"\nTIMEOUT after {limit}s (declared budget={limit}s{scaled})"
    finally:
        with running_lock:
            running.discard(g)
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


# --- shared-tree tripwire ----------------------------------------------------------------------
# The sibling of the binary tripwire above, for the OTHER thing every gate shares: the checkout. A
# gate that writes a transient file anywhere under the repo root -- a probe copy beside the script
# it copies, an appended function it then `git checkout`s away -- makes `git status --porcelain`
# non-empty for as long as the file exists, and every stamped verb (--for, --pr-context,
# --edit-check, --slice, --situ, --hotspots, --doctor, ...) reads exactly that command, from ANY
# crawl root inside the checkout, for the `+dirty` half of its at="<sha>[+dirty]" anchor
# (src/gitstamp.h stampAt). CI run 34298150602, macOS plain shard 2/2: tokenbudgetcheck's `--for`
# determinism arm got est_tokens 3949 then 3947 -- the six bytes of "+dirty" at 2.5 B/tok -- while
# gateexitcheck, three worker slots away, had test/gateexitfix/.gateprobe.*.sh on disk. The red
# named an innocent gate on an innocent tree, and the issue thread named a third gate that had
# never written outside its own mktemp at all.
#
# So: baseline `git status` before the run, sample it while the run is in flight, and report every
# NEW line together with the gates that were running when it was seen. This is a SAMPLER (every
# PARGATES_DIRT_POLL_SEC, default 0.25 s): a window shorter than the interval can be missed, so a
# clean report is "none found", never "none exists" -- the floor rule the binary applies to its own
# counts. A hit FAILS the run: a writer is a defect whether or not a determinism arm happened to be
# reading in that window, and the same suite would only flake somewhere else next time.
# `--no-optional-locks` keeps the sampler from ever taking the index lock a gate might need.
#
# Its blind spot is a write git ignores. That is usually harmless, because the crawl skips gitignored paths
# too -- EXCEPT a directory whose NAME is on the crawl's own denylist (build, __pycache__, node_modules, ...):
# a crawl of the live repo still counts it in corpus_pruned_dirs= while `git status` stays empty. Python's
# bytecode cache was one such writer (see run()'s PYTHONDONTWRITEBYTECODE); a clean report stays "none found".
DIRT_POLL_SEC = float(os.environ.get("PARGATES_DIRT_POLL_SEC", "0.25"))


def _tree_dirt():
    """The set of `git status --porcelain` lines for the shared checkout, or None when git cannot
    answer (no git, not a repository, a lock held elsewhere) -- a skipped sample, never a false clean."""
    try:
        p = subprocess.run(["git", "--no-optional-locks", "-C", root, "status", "--porcelain", "--untracked-files=all"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0:
        return None
    return set(p.stdout.decode("utf-8", "replace").splitlines())


running = set()                 # gates in flight right now; run() keeps it under running_lock
running_lock = threading.Lock()
dirt_baseline = _tree_dirt()    # None: git cannot see this root -- the tripwire is disarmed, and says so
dirt_seen = {}                  # status line -> [first_t, last_t, samples, gates running when seen]
dirt_stop = threading.Event()


def _dirt_sample():
    now = _tree_dirt()
    if now is None:
        return
    new = now - dirt_baseline
    if not new:
        return
    with running_lock:
        snap = sorted(running)
    t = round(time.time() - t0, 1)
    for ln in new:
        e = dirt_seen.setdefault(ln, [t, t, 0, set()])
        e[1] = t
        e[2] += 1
        e[3].update(snap)


def _dirt_watch():
    while not dirt_stop.wait(DIRT_POLL_SEC):
        _dirt_sample()


bin_before = _bin_fingerprint()

t0 = time.time()
dirt_thread = None
if dirt_baseline is not None:
    dirt_thread = threading.Thread(target=_dirt_watch, name="tree-dirt-tripwire", daemon=True)
    dirt_thread.start()
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
if dirt_thread is not None:
    dirt_stop.set()
    dirt_thread.join()
    _dirt_sample()          # one last look: a file a gate LEFT BEHIND is a hit with no gate in flight

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
      f"skip={len(skips)} fail={len(fails)} wall={round(time.time()-t0,1)}s jobs={jobs}"
      + (f" tree_writes={len(dirt_seen)}" if dirt_baseline is not None else " tree_writes=unwatched"))
if bin_moved:
    print(f"\n*** THE BINARY UNDER TEST CHANGED WHILE THE SUITE RAN: {binp}")
    print(f"***   before={bin_before}  after={bin_after}")
    print("***   Some gate rebuilt it in place. Every gate that ran concurrently saw it missing")
    print("***   (rc=2) or busy (exit 126 / 'Permission denied'), so THOSE FAILURES ARE NOT REAL.")
    print("***   Find the gate that writes to the shared build tree and fix that first.")
if dirt_baseline is None:
    print("\ntree tripwire: DISARMED -- git cannot report status for this root, so a gate writing into the shared checkout goes unseen here")
if dirt_seen:
    print(f"\n*** A GATE WROTE INTO THE SHARED CHECKOUT WHILE THE SUITE RAN: {root}")
    print(f"***   sampled every {DIRT_POLL_SEC:g}s -- a shorter window can be missed, so this list is a floor, not a total:")
    for ln, (t_first, t_last, n, gs) in sorted(dirt_seen.items(), key=lambda kv: kv[1][0]):
        who = ", ".join(sorted(gs)) if gs else "(no gate in flight -- left behind after the run)"
        print(f"***   {ln}  seen {n}x, T+{t_first}s..T+{t_last}s; running then: {who}")
    print("***   Every stamped verb reads `git status --porcelain` for its at=\"...+dirty\" bit from ANY crawl root")
    print("***   inside this checkout, so a determinism arm that ran in that window can red with the tree innocent.")
    print("***   Fix the writer first (work on a copy, or a gitignored name that is not a crawl-pruned directory")
    print("***   name -- never build/, __pycache__/ or node_modules/); only then triage the arms above.")
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
elif dirt_seen:
    print("\nNO GATE FAILED, BUT THE SUITE IS NOT CLEAN -- a gate wrote into the shared checkout (see the tree tripwire above)")
else:
    print("\nALL PASS")

if jsonout:
    with open(jsonout, "w") as fh:
        json.dump({g: {"rc": rc, "sec": dt, "skipped": sk} for g, rc, dt, _, sk in results}, fh, indent=1)
sys.exit(1 if fails or dirt_seen else 0)
