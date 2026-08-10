#!/usr/bin/env python3
"""svectorab.py — the IN-SITU four-way A/B for ripwire's small-vector choice.

This is the AUTHORITATIVE measurement. bench/bench_svector3.cpp is a microbenchmark and its committed
"rw::svector is ~25% faster than ankerl" figure is explicitly NOT transferable: its working set is small
and cache-resident, so it understates the cost of a container's SIZE and overstates the cost of its
size() BRANCH. This script measures the whole pipeline instead, over real corpora, flipping one type
alias (src/smallvec.h) between:

    arm 0  std::vector<T>            24 B, a malloc per non-empty list  (the pre-conversion baseline)
    arm 1  ankerl::svector<T,N>      16 B, size() branches on the SVO tag  (third_party, MIT)
    arm 2  rw::svector<T,N>          24 B, size() branch-free              (the shipped default)
    arm 3  rwx::svector16<T,N>       16 B, size() branch-free              (bench/, the union experiment)

WHAT IT ENFORCES SO THE NUMBERS MEAN SOMETHING
  * a FRESH build directory per arm — never an incremental rebuild. A stale object from a mid-edit build
    produces plausible, wrong results, and this project has lost hours to exactly that.
  * --no-cache on EVERY run, on every side of every comparison. A cached A/B manufactures fake deltas.
  * NON-VACUITY: the four binaries must not be byte-identical, or the alias flip did nothing and every
    delta below is noise being read as signal.
  * OUTPUT EQUIVALENCE: all four arms must emit a byte-identical map. If they do not, they are not doing
    the same work and no timing comparison between them is meaningful.
  * INTERLEAVED repetitions with the arm order rotated per rep, so thermal drift cannot be attributed to
    whichever arm happened to run first.
  * median plus min/max spread, never a bare mean. A 25% claim with overlapping spreads is not a claim.

USAGE
    bench/svectorab.py                                   # timing pass, both default corpora
    bench/svectorab.py --reps 9
    bench/svectorab.py --instrumented                    # + per-phase timing, PMC counters, alloc counts
    bench/svectorab.py --corpus src --corpus /path/to/other
    sudo bench/svectorab.py --instrumented               # PMC counters need root on Apple (kperf)

The instrumented pass builds a SECOND set of trees with -DRIPWIRE_PROFILE=ON -DRIPWIRE_ALLOC_COUNT=ON.
Its wall-clock is perturbed by the allocation counter and is NOT the timing answer — the timing pass is.
What it is for: which PHASE moved, whether the phase is memory-bound, and how many allocations each arm
performs.
"""

import argparse
import hashlib
import os
import re
import shutil
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ARMS = {
    0: ("std::vector", "24 B, malloc per list"),
    1: ("ankerl::svector", "16 B, branching size()"),
    2: ("rw::svector", "24 B, branch-free size()"),
    3: ("rwx::svector16", "16 B, branch-free size()"),
}

# The phase the conversion actually touches. End-to-end is dominated by tree-sitter parsing (~6.5 s cold
# on a large corpus) and would hide a 10 ms win entirely, so the per-phase row is the one to read.
AFFECTED_PHASE = "buildGraph: resolve refs + build CSR"


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def build_arm(arm, instrumented, jobs):
    """Configure and build one arm in its OWN fresh directory. Never incremental."""
    tag = f"build_sv{arm}" + ("_i" if instrumented else "")
    bdir = os.path.join(ROOT, tag)
    if os.path.isdir(bdir):
        shutil.rmtree(bdir)                    # fresh tree == --clean-first, with no stale-object risk
    cfg = ["cmake", "-S", ".", "-B", tag, f"-DRIPWIRE_SMALLVEC={arm}"]
    if instrumented:
        cfg += ["-DRIPWIRE_PROFILE=ON", "-DRIPWIRE_ALLOC_COUNT=ON"]
    r = run(cfg)
    if r.returncode != 0:
        print(f"  configure FAILED for arm {arm}:\n{r.stdout[-2000:]}{r.stderr[-2000:]}")
        return None
    t0 = time.perf_counter()
    r = run(["cmake", "--build", tag, "-j", str(jobs)])
    if r.returncode != 0:
        print(f"  build FAILED for arm {arm}:\n{r.stdout[-3000:]}{r.stderr[-3000:]}")
        return None
    binp = os.path.join(bdir, "ripwire")
    print(f"  arm {arm} {ARMS[arm][0]:<16} built in {time.perf_counter()-t0:6.1f}s -> {tag}/ripwire")
    return binp


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def timed_run(binp, corpus, extra=None):
    """One --no-cache run. Returns (seconds, stdout_bytes, stderr_text)."""
    cmd = [binp, corpus, "--no-cache"] + (extra or [])
    t0 = time.perf_counter()
    p = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return time.perf_counter() - t0, p.stdout, p.stderr.decode("utf-8", "replace")


def fmt_spread(xs):
    return f"{statistics.median(xs)*1000:8.1f}  [{min(xs)*1000:7.1f}..{max(xs)*1000:7.1f}]"


def timing_pass(bins, corpora, reps):
    print("\n== TIMING PASS (authoritative) — plain builds, --no-cache every run ==")
    results = {}
    for corpus in corpora:
        # Non-vacuity + equivalence: every arm must emit the SAME map, or the comparison is meaningless.
        outs = {}
        for arm, binp in bins.items():
            _, out, _ = timed_run(binp, corpus)
            outs[arm] = hashlib.sha256(out).hexdigest()
            if len(out) == 0:
                print(f"  FAIL  arm {arm} produced EMPTY output on {corpus} — nothing was measured")
                return None
        distinct = set(outs.values())
        if len(distinct) != 1:
            print(f"  FAIL  arms disagree on {corpus}: {outs}")
            print("        the arms are not doing the same work; no timing comparison is valid")
            return None
        print(f"\n  corpus {corpus}  (all {len(bins)} arms byte-identical output, sha {list(distinct)[0][:12]})")
        print(f"    {'arm':<18} {'median ms':>10}  {'[min..max]':>20}   vs arm2")
        samples = {arm: [] for arm in bins}
        order = sorted(bins)
        for rep in range(reps):
            # rotate, so no arm is systematically first (thermal drift / page-cache warmth)
            for arm in order[rep % len(order):] + order[:rep % len(order)]:
                dt, _, _ = timed_run(bins[arm], corpus)
                samples[arm].append(dt)
        base = statistics.median(samples[2]) if 2 in samples else None
        for arm in sorted(samples):
            med = statistics.median(samples[arm])
            rel = f"{(med/base - 1)*100:+6.1f}%" if base else "   n/a"
            print(f"    {ARMS[arm][0]:<18} {fmt_spread(samples[arm])}   {rel}")
        results[corpus] = samples
    return results


PHASE_RE = re.compile(r"^\s*(.*?)\s{2,}.*?([\d.]+)\s*ms", re.M)


def parse_alloc(stderr):
    m = re.search(r"ALLOC_REPORT allocs=(\d+) bytes=(\d+) frees=(\d+) peak_live_bytes=(\d+)", stderr)
    return tuple(int(x) for x in m.groups()) if m else None


def parse_phase(stderr, phase):
    """Pull one PROFILE_SCOPE row's wall-ms and any counter columns out of the report."""
    for line in stderr.splitlines():
        if phase in line:
            return line.strip()
    return None


def instrumented_pass(bins, corpora, dumpdir=None):
    print("\n== INSTRUMENTED PASS — per-phase timing, PMC counters, allocation counts ==")
    print("   (wall-clock here is PERTURBED by the allocation counter; read the timing pass for speed)")
    for corpus in corpora:
        print(f"\n  corpus {corpus}")
        base_allocs = None
        for arm in sorted(bins):
            wall, _, err = timed_run(bins[arm], corpus)
            if dumpdir:
                os.makedirs(dumpdir, exist_ok=True)
                tag = os.path.basename(corpus.rstrip("/")) or "root"
                with open(os.path.join(dumpdir, f"profile_arm{arm}_{tag}.txt"), "w") as f:
                    f.write(err)
            alloc = parse_alloc(err)
            row = parse_phase(err, AFFECTED_PHASE)
            if alloc:
                if base_allocs is None:
                    base_allocs = alloc
                d = alloc[0] - base_allocs[0]
                db = alloc[1] - base_allocs[1]
                # only the DELTA is attributable to the container; the absolute includes tree-sitter,
                # every std::string in the symbol table, and the map's own bucket arrays.
                print(f"    {ARMS[arm][0]:<18} allocs={alloc[0]:>9,} ({d:+,})  bytes={alloc[1]:>12,} ({db:+,})"
                      f"  peak={alloc[3]:>11,}  wall={wall*1000:7.1f}ms")
            else:
                print(f"    {ARMS[arm][0]:<18} allocs=UNAVAILABLE (built without -DRIPWIRE_ALLOC_COUNT=ON?)")
            if row:
                print(f"      affected phase | {row[:160]}")
            else:
                print(f"      affected phase | UNAVAILABLE — '{AFFECTED_PHASE}' not in the report"
                      f" (built without -DRIPWIRE_PROFILE=ON?)")
        if not prof_has_counters(bins, corpora[0]):
            print("    counters=UNAVAILABLE (kperf needs root on Apple; Linux needs perf_event_paranoid<=2)"
                  " — re-run under sudo for the cache columns. Timing and allocation counts are unaffected.")


def prof_has_counters(bins, corpus):
    _, _, err = timed_run(bins[sorted(bins)[0]], corpus)
    return "PMC (per-scope counters" in err


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--corpus", action="append", default=None)
    ap.add_argument("--arms", default="0,1,2,3")
    ap.add_argument("--instrumented", action="store_true")
    ap.add_argument("--keep", action="store_true", help="keep the build trees")
    args = ap.parse_args()

    corpora = args.corpus or ["src"]
    arms = [int(a) for a in args.arms.split(",")]

    print("svectorab: the in-situ four-way small-vector A/B")
    print(f"  corpora: {corpora}   reps: {args.reps}   arms: {arms}")

    print("\n== BUILD (a FRESH tree per arm — never incremental) ==")
    bins = {}
    for arm in arms:
        b = build_arm(arm, args.instrumented, args.jobs)
        if b is None:
            return 2
        bins[arm] = b

    # NON-VACUITY. If two arms produced the same bytes, the alias flip did nothing and every number
    # below would be noise presented as signal. This is the "green while inert" guard.
    hashes = {arm: sha(b) for arm, b in bins.items()}
    if len(set(hashes.values())) != len(hashes):
        print("\n  FAIL  two or more arm binaries are byte-identical — the alias flip did not take effect:")
        for arm, h in hashes.items():
            print(f"          arm {arm} {ARMS[arm][0]:<18} {h[:16]}")
        return 2
    print(f"\n  non-vacuity OK: {len(hashes)} distinct binaries")

    for arm, b in bins.items():
        print(f"    arm {arm} {ARMS[arm][0]:<18} {os.path.getsize(b):>10,} B  {hashes[arm][:12]}")

    if args.instrumented:
        instrumented_pass(bins, corpora, dumpdir=os.path.join(ROOT, "build_svprof"))
    else:
        if timing_pass(bins, corpora, args.reps) is None:
            return 2

    if not args.keep:
        for arm in arms:
            d = os.path.join(ROOT, f"build_sv{arm}" + ("_i" if args.instrumented else ""))
            shutil.rmtree(d, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
