#!/usr/bin/env python3
"""Run the tgrep head-to-head over the corpus ladder.

  RW_H2H_HOME=<scratch> RIPWIRE_BIN=... TGREP_BIN=... python3 run.py [corpus ...]

RW_H2H_HOME holds:  corpus/<name>   the trees (or they are named absolutely in LADDER)
                    idx/<name>      tgrep's index, one per corpus
                    tmp/<name>      the TMPDIR that holds ripwire's warm cache
                    tmp/cold-<n>    a fresh TMPDIR per cold run
Raw arm output goes to raw/ and is NOT tracked - ripwire echoes root= and the scratch
path carries a session id.
"""

import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arms  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.environ.get("RW_H2H_HOME") or os.path.join(HERE, "scratch")
REPS = int(os.environ.get("REPS", "5"))
COLD_REPS = int(os.environ.get("COLD_REPS", "3"))
TIMEOUT = int(os.environ.get("TIMEOUT", "300"))
# The top rung is wall-clock asymmetric: on llvm-project a single ripwire --regex run is 3-4
# MINUTES (std::regex over 182,555 files) where tgrep and rg answer in under a second. A median
# of five on every ripwire cell there would cost hours, so the ripwire arms take their own
# repetition count and their own query subset on that rung. Both are DECLARED, never silent:
# results.json records reps per cell and the README names the subset and the reason.
RW_REPS = int(os.environ.get("RW_REPS", "0")) or REPS
RW_QUERIES = [q for q in os.environ.get("RW_QUERIES", "").split(",") if q]

# corpus ladder: name -> path.  Absolute paths win; otherwise $RW_H2H_HOME/corpus/<name>.
LADDER = json.loads(os.environ["RW_H2H_LADDER"]) if os.environ.get("RW_H2H_LADDER") else {}


def sh(argv, **kw):
    return subprocess.run(argv, capture_output=True, text=True, **kw)


def dirbytes(p):
    n = 0
    for r, _, fs in os.walk(p):
        for f in fs:
            try:
                n += os.path.getsize(os.path.join(r, f))
            except OSError:
                pass
    return n


def peak_rss_run(argv, env=None, timeout=1800):
    """Wall + peak RSS via /usr/bin/time -l (macOS) / -v (GNU)."""
    e = dict(os.environ)
    if env:
        e.update(env)
    t0 = time.perf_counter()
    p = subprocess.run(["/usr/bin/time", "-l"] + list(argv), env=e, capture_output=True,
                       text=True, timeout=timeout)
    dt = time.perf_counter() - t0
    rss = 0
    for line in p.stderr.splitlines():
        s = line.strip()
        if "maximum resident set size" in s:
            try:
                rss = int(s.split()[0])
            except ValueError:
                pass
    return dt, rss, p.returncode, p.stdout, p.stderr


# ── tgrep server lifecycle ────────────────────────────────────────────────────────────
def tgrep_index(root, idx):
    shutil.rmtree(idx, ignore_errors=True)
    os.makedirs(idx, exist_ok=True)
    dt, rss, rc, out, err = peak_rss_run([arms.TGREP, "index", root, "--index-path", idx])
    return {"wall_s": round(dt, 3), "peak_rss_bytes": rss, "rc": rc,
            "index_bytes": dirbytes(idx), "stdout": out.strip()[-400:], "stderr": err.strip()[-400:]}


def tgrep_serve(root, idx):
    p = subprocess.Popen([arms.TGREP, "serve", root, "--index-path", idx],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(1800):
        time.sleep(1)
        st = sh([arms.TGREP, "status", root, "--index-path", idx])
        if "Indexing:   complete" in st.stdout or "Indexing: complete" in st.stdout:
            return p, st.stdout
    return p, "TIMEOUT waiting for index"


def stop(p):
    if p and p.poll() is None:
        p.terminate()
        try:
            p.wait(30)
        except subprocess.TimeoutExpired:
            p.kill()


# ── one corpus ────────────────────────────────────────────────────────────────────────
def run_corpus(name, root, qs, raw):
    idx = os.path.join(HOME, "idx", name)
    warmtmp = os.path.join(HOME, "tmp", name)
    os.makedirs(warmtmp, exist_ok=True)
    os.makedirs(raw, exist_ok=True)

    rec = {"corpus": name, "root": root, "queries": {}}
    rec["files_rg"] = int(sh([arms.RG, "--files", root]).stdout.count("\n"))

    # ---- ripwire cold: a property of the corpus, measured once (COLD_REPS) --------
    cold = []
    for i in range(COLD_REPS):
        t = os.path.join(HOME, "tmp", "cold-%s-%d" % (name, i))
        shutil.rmtree(t, ignore_errors=True)
        os.makedirs(t, exist_ok=True)
        dt, rss, rc, _, _ = peak_rss_run(arms.rw_argv(root, "zzqxvnotpresentzz", False),
                                         env={"TMPDIR": t})
        cold.append((dt, rss))
        if i == COLD_REPS - 1:
            rec["rw_cache_bytes"] = dirbytes(os.path.join(t, "ripwire"))
        shutil.rmtree(t, ignore_errors=True)
    rec["rw_cold"] = {"wall_s": round(arms.median([c[0] for c in cold]), 3),
                      "peak_rss_bytes": int(arms.median([c[1] for c in cold])),
                      "reps": COLD_REPS}

    # ---- ripwire warm cache primed ------------------------------------------------
    arms._wall(arms.rw_argv(root, "zzqxvnotpresentzz", False), env={"TMPDIR": warmtmp},
               timeout=TIMEOUT)
    rec["rw_cache_bytes_warm"] = dirbytes(os.path.join(warmtmp, "ripwire"))

    # ---- tgrep index build --------------------------------------------------------
    rec["tgrep_index"] = tgrep_index(root, idx)
    proc, status = tgrep_serve(root, idx)
    rec["tgrep_status"] = status.strip()

    try:
        for q in qs:
            qid, pat, isre = q["id"], q["pat"], q["id"].startswith("R")
            row = {"pat": pat, "regex": isre}
            plans = {
                "rw-warm":     (arms.rw_argv(root, pat, isre), {"TMPDIR": warmtmp}),
                "rw-warm-all": (arms.rw_argv(root, pat, isre, limit=1000000), {"TMPDIR": warmtmp}),
                "tgrep-warm":  (arms.tgrep_argv(root, pat, isre, idx), None),
                "tgrep-cold":  (arms.tgrep_argv(root, pat, isre, idx, no_index=True), None),
                "rg":          (arms.rg_argv(root, pat, isre), None),
            }
            for arm, (argv, env) in plans.items():
                isrw = arm.startswith("rw-")
                if isrw and RW_QUERIES and qid not in RW_QUERIES:
                    row[arm] = {"skipped": "not in RW_QUERIES (declared subset for this rung)"}
                    print("  %-6s %-11s SKIPPED (declared subset)" % (qid, arm), flush=True)
                    continue
                reps = RW_REPS if isrw else REPS
                walls, rc = [], None
                for _ in range(reps):
                    dt, _, rc, _ = arms._wall(argv, env=env, timeout=TIMEOUT)
                    walls.append(dt)
                dt, nbytes, rc2, out = arms._wall(argv, env=env, timeout=TIMEOUT, capture=True)
                row[arm] = {"median_s": round(arms.median(walls), 4),
                            "min_s": round(min(walls), 4), "max_s": round(max(walls), 4),
                            "reps": reps, "bytes": nbytes, "rc": rc, "argv": argv}
                if out is not None:
                    with open(os.path.join(raw, "%s.%s.%s.out" % (name, qid, arm)), "wb") as f:
                        f.write(out)
                    if arm == "rw-warm-all":
                        row[arm]["hits_set"] = len(arms.rw_hitset(out, root))
                        row[arm]["header"] = arms.rw_header(out)
                    elif arm in ("tgrep-warm", "rg"):
                        row[arm]["hits_set"] = len(arms.grep_hitset(out, root))
                print("  %-6s %-11s med=%8.4fs bytes=%-10s rc=%s" %
                      (qid, arm, row[arm]["median_s"], row[arm]["bytes"], rc), flush=True)
            rec["queries"][qid] = row
    finally:
        stop(proc)
    return rec


def main():
    qs = json.load(open(os.path.join(HERE, "queries.json")))
    allq = qs["literals"] + qs["regexes"]
    want = sys.argv[1:] or list(LADDER)
    # raw/ lives OUTSIDE the checkout on purpose. An untracked file anywhere inside this
    # tree makes `git status --porcelain` dirty, and every stamped verb reads that command
    # from any crawl root inside the checkout for the `+dirty` half of its at= anchor - so a
    # raw/ directory beside this script would flip every determinism arm running in parallel
    # with the harness (the 2026-09-09 gate-isolation finding; see .gitignore's .gateprobe.*).
    raw = os.environ.get("RAW_DIR", os.path.join(HOME, "raw"))
    outp = os.environ.get("OUT", os.path.join(HERE, "results.json"))
    res = json.load(open(outp)) if os.path.exists(outp) else {"corpora": {}}
    res["ripwire_bin"] = arms.RIPWIRE
    res["tgrep_bin"] = arms.TGREP
    for name in want:
        root = LADDER[name]
        print("== %s (%s)" % (name, root), flush=True)
        res["corpora"][name] = run_corpus(name, root, allq, raw)
        # SCRUB before writing: every recorded argv carries the corpus root, and a scratch root
        # under a session scratchpad carries a session id. results.json is committed; the raw
        # outputs are not, for the same reason. Placeholders, not deletion, so a re-run reads.
        blob = json.dumps(res, indent=1, sort_keys=True)
        for real, ph in ((HOME, "$RW_H2H_HOME"), (os.path.expanduser("~"), "$HOME")):
            blob = blob.replace(real, ph)
        with open(outp, "w") as f:
            f.write(blob)
    print("wrote", outp)


if __name__ == "__main__":
    main()
