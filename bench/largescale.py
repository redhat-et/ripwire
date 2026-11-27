#!/usr/bin/env python3
"""bench/largescale.py — where wall clock and peak RSS go at LARGE repo scale, and whether
anything in the pipeline is SUPER-LINEAR in files/symbols.

WHY THIS EXISTS, stated before any number is taken. `bench/PROFILE.md`'s phase tables were all
measured on a ~1,500-1,850-file corpus. Everything the small corpus says about the BALANCE of the
pipeline is a statement about small repos: a phase that is 1% at 1,849 files and grows with the
square of the symbol count is invisible there and dominant at 72,925. This harness measures the
same pipeline at five corpus sizes spanning 6,282 -> 72,925 source files, so the question "is any
phase super-linear" can be answered by a slope instead of by intuition.

WHAT IT MEASURES, and with which binary (the two are deliberately different):

  * HEADLINE wall clock and peak RSS come from the PLAIN dev binary (`build/ripwire`, no build
    type: the house configure is already -O2, see CMakeLists.txt's RIPWIRE_OPT_REMARKS note).
    PROFILE_SCOPE is compiled out of it, so these numbers carry no instrumentation tax. Wall is
    `time.perf_counter()` around the child; peak RSS is `ru_maxrss` from `os.wait4`, which on
    macOS is BYTES and is the max over the child and every descendant it reaped (git children
    included) -- a peak, never a sum, which matches the owner's "memory is one lifecycle peak".
  * PHASE ATTRIBUTION comes from the instrumented binary (`-DRIPWIRE_PROFILE=ON`, a separate
    tree), parsed out of the `#PROF_TSV_BEGIN..#PROF_TSV_END` block it writes to stderr at exit.
    Those milliseconds are NOT comparable to the headline wall clock and this harness never mixes
    them into one table, for two reasons stated here rather than discovered later:
      - `total_ms` is per-site, aggregated ACROSS THREADS and top-level INCLUSIVE. For a parallel
        scope (the parse pool's workers) it is thread-time, so it can exceed the run's wall clock.
        Shares within one run are the signal; absolute ms are not a wall-clock claim.
      - the instrumentation itself costs a CNTVCT read plus relaxed atomic adds per scope ENTRY,
        and several scopes are per-symbol or per-file. At 72,925 files that tax is real and it
        falls on exactly the phases with the most entries, i.e. it biases the attribution TOWARD
        fine-grained scopes. So a phase is only called hot here if it is hot by `calls`-normalised
        cost too, and any decision gets re-measured on the plain binary's wall clock.

HOW COLD AND WARM ARE DEFINED (the single biggest way to get this wrong):

  * COLD: a private, empty `XDG_CACHE_HOME` and `TMPDIR` per repetition PLUS `--no-cache`. Both
    halves are needed -- `--no-cache` alone still lets a warm snapshot from an earlier run short
    the crawl, and a fresh cache dir alone still lets the record cache be written and read.
  * WARM: one persistent private `XDG_CACHE_HOME`/`TMPDIR` per corpus, primed by a discarded run,
    then N measured repetitions with the tree untouched between them. `RIPWIRE_CACHE_STATS=1` is
    set on every warm run and the harness RECORDS `reparsed=`/`reused=`; a warm cell whose
    `reparsed=` is not 0 is reported as such and is not a warm number. This is the check that
    turns "I ran it twice" into "the second run was actually warm".
  * The OS page cache is deliberately NOT dropped: it needs sudo, the lane may not use sudo, and
    an agent's second question about a repo always lands on a warm page cache. Cold here means
    "ripwire has no index", not "the disk is cold". Stated so the number is read correctly.

REPETITIONS AND THE STATISTIC. `--reps` repetitions per cell, interleaved per corpus; the harness
reports the MEDIAN and also the MIN and MAX, because a single number from one run is how an
optimistic estimate gets made (MEMORY: "Estimates from one measurement"). Nothing here is a gate:
the house rule is no perf-budget gates, so this harness prints and never fails on a time.

THE LINEARITY TEST. For each phase and for the whole run, the harness fits a slope on log(metric)
vs log(files) across the corpora measured, and prints the pairwise local slope between adjacent
sizes. A slope near 1.0 is linear in files; >= ~1.3 sustained across the top pair is the thing this
lane is looking for. Slopes are also computed against SYMBOL count (read out of the map header),
because a phase that is linear in symbols can look super-linear in files when symbol density
differs between repos -- llvm-project and kubernetes do not have the same symbols per file, and
attributing a density difference to a complexity defect would be a false alarm.

USAGE
  python3 bench/largescale.py --bin build/ripwire --prof-bin build_prof/ripwire \
      --corpus angular=/path/angular --corpus envoy=/path/envoy ... \
      --reps 3 --out /tmp/ls --mode both
  python3 bench/largescale.py --replot --out /tmp/ls        # re-render tables from saved JSON

Each cell is written to <out>/cells.jsonl as it completes, so an interrupted run keeps its work
and `--replot` can render whatever was finished. Scratch dirs live under <out>/arena.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time

# ---------------------------------------------------------------------------- running one child

def run_once(binary, root, args, env_extra, cwd=None):
    """Run the binary once. Returns dict with wall_s, max_rss_bytes, rc, stderr text.

    stdout goes to /dev/null: the map is not the subject and writing 100+ MB of XML to a pipe
    would time the pipe. stderr is captured to a temp file (not a pipe) so a large profile report
    cannot deadlock the child.
    """
    env = dict(os.environ)
    env.update(env_extra)
    cmd = [binary, root] + list(args)
    with open(os.devnull, "wb") as devnull:
        err_path = os.path.join(env.get("TMPDIR", "/tmp"), "ls_stderr.txt")
        with open(err_path, "w+b") as errf:
            t0 = time.perf_counter()
            proc = subprocess.Popen(cmd, stdout=devnull, stderr=errf, env=env, cwd=cwd)
            pid, status, ru = os.wait4(proc.pid, 0)
            wall = time.perf_counter() - t0
            proc.returncode = os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else status
            errf.seek(0)
            err = errf.read().decode("utf-8", errors="replace")
    rc = proc.returncode
    return {
        "wall_s": wall,
        # macOS ru_maxrss is bytes; Linux reports kilobytes. Normalise and say which.
        "max_rss_bytes": int(ru.ru_maxrss) if sys.platform == "darwin" else int(ru.ru_maxrss) * 1024,
        "user_s": float(ru.ru_utime),
        "sys_s": float(ru.ru_stime),
        "rc": rc,
        "stderr": err,
    }


def fresh_arena(base, tag):
    path = os.path.join(base, tag)
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(os.path.join(path, "cache"), exist_ok=True)
    os.makedirs(os.path.join(path, "tmp"), exist_ok=True)
    return {"XDG_CACHE_HOME": os.path.join(path, "cache"), "TMPDIR": os.path.join(path, "tmp")}


# ---------------------------------------------------------------------------- parsing output

CACHE_STATS_RE = re.compile(r"\breparsed=(\d+)\b.*?\breused=(\d+)\b")
# The map prints its counts UNQUOTED inside a trailing XML comment -- `files=103 symbols=612
# edges=245` -- not as attributes. A `files="(\d+)"` pattern finds nothing and would read as
# "this corpus has no files" (MEMORY: a quoted-pattern grep that could never match).
FILES_ATTR_RE = re.compile(r"\bfiles=(\d+)\b")
SYMS_ATTR_RE = re.compile(r"\bsymbols=(\d+)\b")
EDGES_ATTR_RE = re.compile(r"\bedges=(\d+)\b")


def parse_cache_stats(err):
    m = CACHE_STATS_RE.search(err)
    if not m:
        return None
    return {"reparsed": int(m.group(1)), "reused": int(m.group(2))}


def parse_prof_tsv(err):
    """Return list of {scope, file, line, calls, total_ms} from the fenced block."""
    start = err.find("#PROF_TSV_BEGIN")
    end = err.find("#PROF_TSV_END")
    if start < 0 or end < 0:
        return []
    block = err[start:end].splitlines()
    rows = []
    header = None
    for line in block[1:]:
        if not line.strip():
            continue
        cols = line.split("\t")
        if header is None:
            header = cols
            continue
        if len(cols) < 5:
            continue
        try:
            rows.append({
                "scope": cols[0],
                "file": cols[1],
                "line": int(cols[2]),
                "calls": int(cols[3]),
                "total_ms": float(cols[4]),
            })
        except ValueError:
            continue
    return rows


def header_counts(binary, root, env_extra):
    """files= and symbol count from one cheap run's map header (stdout, first 4 KiB)."""
    env = dict(os.environ)
    env.update(env_extra)
    try:
        done = subprocess.run([binary, root, "--top-k=1"], stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, env=env, timeout=7200)
    except Exception:
        return {}
    if done.returncode != 0:
        # A non-zero exit means the map is partial or absent; counts read off it would be a
        # silently wrong x-axis, so report nothing rather than something.
        print(f"!! header_counts: {binary} exited {done.returncode} on {root}", file=sys.stderr)
        return {}
    text = done.stdout.decode("utf-8", errors="replace")
    res = {}
    for key, rx in (("files", FILES_ATTR_RE), ("syms", SYMS_ATTR_RE), ("edges", EDGES_ATTR_RE)):
        m = rx.search(text)
        if m:
            res[key] = int(m.group(1))
    return res


# ---------------------------------------------------------------------------- stats

def median(xs):
    s = sorted(xs)
    n = len(s)
    if n == 0:
        return float("nan")
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


def loglog_slope(pairs):
    """Least-squares slope of log(y) on log(x) over [(x, y), ...]."""
    pts = [(math.log(x), math.log(y)) for x, y in pairs if x > 0 and y > 0]
    if len(pts) < 2:
        return float("nan")
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    num = sum((p[0] - mx) * (p[1] - my) for p in pts)
    den = sum((p[0] - mx) ** 2 for p in pts)
    return num / den if den else float("nan")


# ---------------------------------------------------------------------------- the sweep

def measure_cell(args, job):
    """`args.reps` repetitions of one (corpus, mode) cell, as a record ready for cells.jsonl.

    `job` is one Job: the corpus name and root, the mode, the scratch arena, the primed warm
    environment and the corpus's counts. They travel together because every one of them is fixed
    for the whole cell, and a six-argument call site is where the mode and the arena get swapped.
    """
    name, root, mode = job["name"], job["root"], job["mode"]
    arena, warm_env, counts = job["arena"], job["warm_env"], job["counts"]
    reps = []
    for i in range(args.reps):
        if mode == "cold":
            env = fresh_arena(arena, f"{name}-cold-{i}")
            verb = list(args.verb) + ["--no-cache"]
        else:
            env = dict(warm_env)
            env["RIPWIRE_CACHE_STATS"] = "1"
            verb = list(args.verb)
        r = run_once(args.bin, root, verb, env)
        r["cache_stats"] = parse_cache_stats(r["stderr"])
        r.pop("stderr", None)
        reps.append(r)
        print(f"   [{name}/{mode}] rep{i}: {r['wall_s']:.2f}s "
              f"rss={r['max_rss_bytes']/2**20:.0f}MiB rc={r['rc']} "
              f"{r['cache_stats'] or ''}", file=sys.stderr)
        if mode == "cold":
            shutil.rmtree(os.path.join(arena, f"{name}-cold-{i}"), ignore_errors=True)
    return {
        "corpus": name, "root": root, "mode": mode, "binary": args.bin,
        "verb": args.verb, "reps": reps,
        "wall_med_s": median([r["wall_s"] for r in reps]),
        "wall_min_s": min(r["wall_s"] for r in reps),
        "wall_max_s": max(r["wall_s"] for r in reps),
        "rss_med_bytes": median([r["max_rss_bytes"] for r in reps]),
        "rss_max_bytes": max(r["max_rss_bytes"] for r in reps),
        "counts": counts,
        "quiet_window": args.window_label,
        "stamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }


def measure_phases(args, job):
    """One instrumented run, parsed into per-scope rows. Not a timing: see the module header."""
    name, root, mode = job["name"], job["root"], job["mode"]
    arena, warm_env, counts = job["arena"], job["warm_env"], job["counts"]
    if mode == "cold":
        penv = fresh_arena(arena, f"{name}-prof-cold")
        pverb = list(args.verb) + ["--no-cache"]
    else:
        penv = dict(warm_env)
        pverb = list(args.verb)
    pr = run_once(args.prof_bin, root, pverb, penv)
    rows = parse_prof_tsv(pr["stderr"])
    print(f"   [{name}/{mode}] phases: {len(rows)} scopes, prof wall {pr['wall_s']:.2f}s", file=sys.stderr)
    if mode == "cold":
        shutil.rmtree(os.path.join(arena, f"{name}-prof-cold"), ignore_errors=True)
    return {
        "corpus": name, "mode": mode, "kind": "phases", "binary": args.prof_bin,
        "wall_s": pr["wall_s"], "max_rss_bytes": pr["max_rss_bytes"],
        "rc": pr["rc"], "rows": rows, "counts": counts,
        "quiet_window": args.window_label,
        "stamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }


def sweep(args):
    os.makedirs(args.out, exist_ok=True)
    arena = os.path.join(args.out, "arena")
    os.makedirs(arena, exist_ok=True)
    cells_path = os.path.join(args.out, "cells.jsonl")
    sink = open(cells_path, "a", buffering=1)

    corpora = []
    for spec in args.corpus:
        name, _, path = spec.partition("=")
        corpora.append((name, os.path.abspath(path)))

    modes = ["cold", "warm"] if args.mode == "both" else [args.mode]

    for name, root in corpora:
        if not os.path.isdir(root):
            print(f"!! {name}: {root} is not a directory, skipped", file=sys.stderr)
            continue

        # ---- warm arena, primed once and reused by every warm rep of this corpus
        warm_env = fresh_arena(arena, f"{name}-warm")
        counts = {}

        for mode in modes:
            if mode == "warm":
                prime = run_once(args.bin, root, args.verb, warm_env)
                print(f"   [{name}] warm prime: {prime['wall_s']:.2f}s rc={prime['rc']}", file=sys.stderr)
                if not counts:
                    counts = header_counts(args.bin, root, warm_env)

            job = {"name": name, "root": root, "mode": mode,
                   "arena": arena, "warm_env": warm_env, "counts": counts}
            sink.write(json.dumps(measure_cell(args, job)) + "\n")
            if args.prof_bin:
                sink.write(json.dumps(measure_phases(args, job)) + "\n")

    sink.close()
    shutil.rmtree(arena, ignore_errors=True)
    render(args)


# ---------------------------------------------------------------------------- rendering

def load_cells(cells_path):
    """The saved cells, newest per (corpus, mode) winning: (wall cells, phase cells)."""
    latest, latest_ph = {}, {}
    with open(cells_path) as f:
        for line in f:
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            target = latest_ph if rec.get("kind") == "phases" else latest
            target[(rec["corpus"], rec["mode"])] = rec
    return latest, latest_ph


def corpus_order(latest, counts_for):
    """Corpora as (name, files), smallest first. files=0 means the counts run did not answer."""
    seen = {}
    for (cname, _mode), _rec in latest.items():
        seen[cname] = (counts_for.get(cname) or {}).get("files") or 0
    return sorted(seen.items(), key=lambda t: t[1])


def counts_by_corpus(latest, latest_ph):
    """Indexed counts per corpus, from whichever cell answered.

    The counts are a property of the CORPUS, not of the mode: the harness reads them off one cheap
    warm run, so a cold cell has none of its own. Resolving them per corpus is what keeps a cold row
    from printing "?" for an x-axis that was in fact measured. With `--mode cold` alone nothing reads
    them and the column stays "?" — honestly, because nothing measured it.
    """
    res = {}
    for store in (latest, latest_ph):
        for (cname, _mode), rec in store.items():
            counts = rec.get("counts") or {}
            if counts.get("files"):
                res.setdefault(cname, counts)
    return res


def wall_table(latest, order, counts_for):
    out = ["## Wall clock and peak RSS by corpus size\n",
           "| corpus | files | syms | mode | wall med (s) | min | max | peak RSS (MiB) | warm reparsed |",
           "|---|---|---|---|---|---|---|---|---|"]
    for cname, _files in order:
        for mode in ("cold", "warm"):
            rec = latest.get((cname, mode))
            if not rec:
                continue
            stats = [r.get("cache_stats") for r in rec["reps"] if r.get("cache_stats")]
            # "-" is not 0: a cold arm sets no RIPWIRE_CACHE_STATS, so it has nothing to report,
            # which is a different statement from "it reparsed nothing".
            rep = stats[-1]["reparsed"] if stats else "-"
            counts = counts_for.get(cname) or rec.get("counts") or {}
            out.append(f"| {cname} | {counts.get('files','?')} | {counts.get('syms','?')} | {mode} | "
                       f"{rec['wall_med_s']:.3f} | {rec['wall_min_s']:.3f} | {rec['wall_max_s']:.3f} | "
                       f"{rec['rss_med_bytes']/2**20:.0f} | {rep} |")
    out.append("")
    return out


def points_for(latest, order, mode, field):
    """[(files, metric)] for one mode, corpora whose file count is known, smallest first."""
    pts = []
    for cname, files in order:
        rec = latest.get((cname, mode))
        if not rec:
            continue
        if files and rec[field] > 0:
            pts.append((files, rec[field]))
    pts.sort()
    return pts


def local_slopes(pts):
    return ", ".join(f"{a[0]}->{b[0]}: {math.log(b[1]/a[1])/math.log(b[0]/a[0]):.2f}"
                     for a, b in zip(pts, pts[1:]))


def slope_lines(latest, order):
    out = []
    for mode in ("cold", "warm"):
        pts = points_for(latest, order, mode, "wall_med_s")
        if len(pts) < 2:
            continue
        out.append(f"**{mode} wall vs files:** log-log slope {loglog_slope(pts):.2f} over "
                   f"{len(pts)} sizes ({pts[0][0]} -> {pts[-1][0]} files). "
                   f"Local slopes: {local_slopes(pts)}")
        rpts = points_for(latest, order, mode, "rss_med_bytes")
        if len(rpts) >= 2:
            out.append(f"**{mode} peak RSS vs files:** log-log slope {loglog_slope(rpts):.2f}.")
        out.append("")
    return out


def phase_scores(latest_ph, order, mode):
    """(ms, scope, calls, overall slope, top-pair slope) per scope at the largest corpus."""
    rows_by_scope, sizes = {}, {}
    for cname, files in order:
        rec = latest_ph.get((cname, mode))
        if rec is None or not files:
            continue
        sizes[cname] = files
        for row in rec["rows"]:
            rows_by_scope.setdefault(row["scope"], {})[cname] = row
    if not sizes:
        return None, []
    biggest = max(sizes, key=lambda c: sizes[c])
    scored = []
    for scope, per in rows_by_scope.items():
        if biggest not in per:
            continue
        pts = sorted((sizes[c], per[c]["total_ms"]) for c in per if per[c]["total_ms"] > 0)
        slope = loglog_slope(pts) if len(pts) >= 2 else float("nan")
        top = float("nan")
        if len(pts) >= 2 and pts[-2][0] != pts[-1][0]:
            a, b = pts[-2], pts[-1]
            top = math.log(b[1] / a[1]) / math.log(b[0] / a[0])
        scored.append((per[biggest]["total_ms"], scope, per[biggest]["calls"], slope, top))
    scored.sort(reverse=True)
    return biggest, scored


def phase_tables(latest_ph, order, top_n):
    out = []
    for mode in ("cold", "warm"):
        biggest, scored = phase_scores(latest_ph, order, mode)
        if not scored:
            continue
        out.append(f"### {mode}: per-phase cost at the largest corpus ({biggest}), and its slope\n")
        out.append("| phase | ms @ largest | calls @ largest | slope vs files | local slope (top pair) |")
        out.append("|---|---|---|---|---|")
        for ms, scope, calls, slope, pair in scored[:top_n]:
            out.append(f"| {scope[:88]} | {ms:.1f} | {calls} | {slope:.2f} | {pair:.2f} |")
        out.append("")
        out.append("Super-linear candidates (top-pair slope >= 1.25 and >= 50 ms at the largest corpus):")
        hits = sorted((s for s in scored if s[4] >= 1.25 and s[0] >= 50.0), key=lambda t: -t[4])
        for ms, scope, _calls, slope, pair in hits:
            out.append(f"- `{scope[:100]}` — {ms:.1f} ms, top-pair slope {pair:.2f}, overall {slope:.2f}")
        if not hits:
            out.append("- none met the bar in this run (this is 'none found here', not 'none exists')")
        out.append("")
    return out


def render(args):
    cells_path = os.path.join(args.out, "cells.jsonl")
    if not os.path.exists(cells_path):
        print("no cells.jsonl", file=sys.stderr)
        return
    latest, latest_ph = load_cells(cells_path)
    counts_for = counts_by_corpus(latest, latest_ph)
    order = corpus_order(latest, counts_for)
    out = wall_table(latest, order, counts_for) + slope_lines(latest, order) \
        + phase_tables(latest_ph, order, args.top)
    text = "\n".join(out)
    path = os.path.join(args.out, "report.md")
    with open(path, "w") as f:
        f.write(text + "\n")
    print(text)
    print(f"\n[written to {path}]", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", default="build/ripwire")
    ap.add_argument("--prof-bin", default=None)
    ap.add_argument("--corpus", action="append", default=[], metavar="NAME=PATH")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--mode", choices=["cold", "warm", "both"], default="both")
    ap.add_argument("--verb", action="append", default=None,
                    help="extra args passed to ripwire (default: the flagless core map)")
    ap.add_argument("--out", default="/tmp/ripwire-largescale")
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--window-label", default="", help="recorded in every cell: which quiet window this was")
    ap.add_argument("--replot", action="store_true")
    args = ap.parse_args()
    if args.verb is None:
        args.verb = []
    if args.replot:
        render(args)
        return
    if not args.corpus:
        ap.error("--corpus NAME=PATH is required unless --replot")
    sweep(args)


if __name__ == "__main__":
    main()
