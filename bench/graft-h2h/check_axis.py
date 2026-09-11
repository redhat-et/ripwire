#!/usr/bin/env python3
"""The CHECK axis: "I have a change in my working tree — which tests must run?"

Paired, N = 6, on the FROZEN S3 commits of the Round C instrument (qid 7..12). For each commit c:
  1. a dedicated worktree is checked out at c~1 (the code as it was before the change);
  2. the SOURCE half of c's own diff (its non-test files) is applied to the working tree — the change the
     developer has just made, uncommitted;
  3. each arm is asked, from that state, what its verb says about the change:
        graft   `graft blast`            (working tree vs HEAD, its default depth 2, default owners)
        ripwire `ripwire --situ`         (default = git diff) and `ripwire --test-gate` (default = git diff)
  4. gold = the TEST files c itself touched (the same S3 gold as the retrieval half) — the tests the real
     change needed, established by the repository, not by any arm.
The scorer is the same scorer.py. The test files are NOT in the applied diff, so neither arm can read the
gold off the diff itself.

Graft's graph is built once at the first checkout and then left to its own refresh-first posture on every
later checkout (that is the documented behaviour: "every query refreshes the graph before it answers");
its build cost is reported once as setup. ripwire runs cold on every checkout (no cache reuse across
commits, `--no-cache`), so its parse is inside the measured window — the asymmetry is declared, not smoothed.

Usage: RW_H2H_HOME=<h2h tree> RIPWIRE_BIN=<ripwire> python3 check_axis.py
"""
from __future__ import annotations
import json, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'roundc-h2h'))
import arms            # noqa: E402
import arms_graft      # noqa: E402
from scorer import score  # noqa: E402

H = os.environ['RW_H2H_HOME']
WT = f"{H}/corpus-check/rocksdb"
SRC_REPO = f"{H}/corpus/rocksdb"
qs = [q for q in json.load(open(os.path.join(HERE, '..', 'roundc-h2h', 'questions.json'))) if q['shape'] == 'S3']


def sh(argv, cwd=None, check=True):
    p = subprocess.run(argv, cwd=cwd, capture_output=True, text=True)
    if check and p.returncode:
        sys.exit(f"FAILED {argv}: {p.stderr[-800:]}")
    return p


def timed(argv, cwd):
    t0 = time.perf_counter()
    p = subprocess.run(argv, cwd=cwd, capture_output=True, timeout=600)
    return p.stdout + p.stderr, (time.perf_counter() - t0) * 1000, p.returncode


if not os.path.isdir(WT):
    sh(['git', '-C', SRC_REPO, 'worktree', 'add', '--detach', '-q', WT, qs[0]['commit'] + '~1'])
gitdir = sh(['git', '-C', WT, 'rev-parse', '--git-path', 'info'], ).stdout.strip()
os.makedirs(os.path.join(WT, gitdir) if not os.path.isabs(gitdir) else gitdir, exist_ok=True)
excl = os.path.join(WT, gitdir, 'exclude') if not os.path.isabs(gitdir) else os.path.join(gitdir, 'exclude')
open(excl, 'a').write('/graft/\n/.ignore\n/.ripwire*\n')

rows, setup = [], {}
for i, q in enumerate(qs):
    c = q['commit']
    sh(['git', '-C', WT, 'checkout', '-q', '--force', c + '~1'])
    sh(['git', '-C', WT, 'clean', '-fdq', '-e', 'graft', '-e', '.ignore'])
    # source-only half of the commit's own diff, applied to the working tree
    names = sh(['git', '-C', WT, 'show', '--name-only', '--format=', c]).stdout.split()
    srcs = [f for f in names if f not in q['gold'] and not f.endswith('_test.cc')]
    if not srcs:
        print(f"q{q['qid']} has no source half — skipped as a metric finding", file=sys.stderr); continue
    patch = sh(['git', '-C', WT, 'diff', c + '~1', c, '--'] + srcs).stdout
    p = subprocess.run(['git', '-C', WT, 'apply', '--3way', '-'], input=patch, capture_output=True, text=True)
    if p.returncode:
        p = subprocess.run(['git', '-C', WT, 'apply', '-'], input=patch, capture_output=True, text=True)
        if p.returncode:
            print(f"q{q['qid']}: patch did not apply ({p.stderr[-200:]}) — skipped as a metric finding", file=sys.stderr); continue
    if i == 0:
        t0 = time.perf_counter()
        b = subprocess.run([arms_graft.SENV, arms_graft.GRAFT, 'build', WT], capture_output=True)
        setup['graft_build_ms'] = round((time.perf_counter() - t0) * 1000)
        sh(['git', '-C', WT, 'checkout', '--', '.gitignore'], check=False)
    per = {}
    order = [('graft-blast', lambda: timed([arms_graft.SENV, arms_graft.GRAFT, 'blast', WT], WT)),
             ('ripwire-situ', lambda: timed([arms.RIPWIRE, WT, '--no-cache', '--situ'], WT)),
             ('ripwire-test-gate', lambda: timed([arms.RIPWIRE, WT, '--no-cache', '--test-gate'], WT))]
    if q['qid'] % 2: order.reverse()
    for name, fn in order:
        out, ms, rc = fn()
        per[name] = score(q['qid'], name, out, q['gold'], ms, rc, [name, 'wt@' + c[:9] + '~1+src-diff'])
        os.makedirs(os.path.join(HERE, 'raw_check'), exist_ok=True)
        open(os.path.join(HERE, 'raw_check', f"q{q['qid']:02d}.{name}.txt"), 'wb').write(out)
    rows.extend(per.values())
    print(f"q{q['qid']:2d} n={q['n']} " + "  ".join(f"{n}={r['ttca_bytes']}{'' if r['complete'] else '*'}({r['hits']}/{r['n_gold']})" for n, r in per.items()), file=sys.stderr)
    sh(['git', '-C', WT, 'checkout', '-q', '--force', '--', '.'])

json.dump({'setup': setup, 'rows': rows}, open(os.path.join(HERE, 'results_check.json'), 'w'), indent=1)
print("wrote results_check.json", setup, file=sys.stderr)
