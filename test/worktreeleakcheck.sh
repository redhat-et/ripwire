#!/usr/bin/env bash
# worktreeleakcheck.sh — a gate that is KILLED mid-run leaves nothing registered in the repository's shared .git.
#
# WHY. On 2026-09-10 `git worktree list` on the dev machine carried 20 registrations under the per-user temp dir —
# `tmp.XXXXXXXX/head` and `ripwire-headbin-<uid>/<sha>.lock/work/head` — 11 hours to 5 days old, each checkout still on
# disk. Five sites checked out a commit of the repository under test with `git worktree add` and undid it only on the
# way out: the monotonicity arms of crossdirincludecheck, nestedimportcheck and preproccondcheck (an EXIT trap), arm (E)
# of qdrefpaircheck (an EXIT trap that also ran `git worktree prune` on the shared .git), and headbinlib.sh's
# _headbin_build (inline, after cmake). A registration lives in .git/worktrees/, which every checkout of the repository
# shares — every session on the machine — and it outlives a process killed before its cleanup runs; `git worktree prune`
# leaves it alone while the directory still exists.
#
# No trap closes that. Measured 2026-09-10, one bash script per case, signalled once it was ready:
#                                                  macOS /bin/bash 3.2.57            Linux bash 5.2.21
#     TERM to its pid                              EXIT trap runs                    runs
#     TERM while it waits inside $( ... )          runs only once $( ) returns       runs
#     INT to its process group (Ctrl-C)            does NOT run                      runs
#     KILL to its pid                              does NOT run                      does NOT run
#     TERM during the ( git worktree add ) subshell: bash runs the trap it had and exits; the orphaned git registers
#     afterwards, on both.
# test/pargates.py enforced a gate's budget with subprocess.run(timeout=), whose timeout path is Popen.kill(): SIGKILL
# to the gate's bash, the one case no shell intercepts. (Since 2026-09-10 it TERMs the gate's whole process group and
# KILLs only what outlives a grace; a SIGKILL from anywhere still runs no trap.) The real crossdirincludecheck, run on the
# live repository the same day and signalled after its registration, bore that out: TERM and Ctrl-C ran its trap, SIGKILL
# left `$TMP/head` registered with the checkout on disk, and Ctrl-C during the HEAD-binary build left the builder's
# `lock/work/head`.
#
# THE FIX is one function, ripwire_private_checkout in test/lib/headbinlib.sh: `git clone --shared --no-checkout`, then
# the commit checked out detached. The clone borrows the objects through its OWN alternates file and writes nothing into
# the source repository, so a killed caller leaves one directory in its temp dir and nothing anywhere else. It carries
# the whole history `--cochange` and qdrefpaircheck's pinned wave need, and the monotonicity arms read the same bytes
# from it: `--no-cache`, `--deps` and `--cochange` over HEAD's src/ were byte-identical between a worktree and a shared
# clone after the root path (2026-09-10).
#
# Three sections over the real tree, each with a control that must go red:
#   (A) SCAN     — no test/*.sh or test/lib/*.sh line runs `git worktree add` or `git worktree prune` against the
#                  repository under test: a code line naming $ROOT (headbinlib: $_root) beside `worktree add|prune`.
#                  Line-based, so a `cd "$ROOT"` on one line and `git worktree add` on the next is not seen. This gate
#                  is left out: its control spells the reverted line on purpose. Controls: crossdirincludecheck with its
#                  checkout reverted, and headbinlib.sh with the helper reverted, must both be flagged.
#   (B) KILL     — every gate that checks out a commit of the repository under test (it calls the helper, or (A) flags
#                  it), derived from the tree, copied into a throwaway repository so the live .git is never touched,
#                  run for real against a stub ripwire that sleeps at its first run inside that checkout, and signalled:
#                      TERM>gate   TERM to the gate's bash; its group SIGKILLed if still alive 4 s later (bash 3.2
#                                  defers TERM while the gate waits inside $( ), which is where these gates wait)
#                      INT>group   Ctrl-C: SIGINT to the whole process group
#                      KILL>gate   SIGKILL to the gate's bash alone (test/pargates.py's timeout until 2026-09-10)
#                  Then whatever is left in the group is SIGKILLed, as a job teardown does, and the throwaway
#                  repository's .git/worktrees must be empty. The HEAD-binary builder is killed the same three ways
#                  mid-cmake (a sleeping cmake shim), through the first caller that also asks headbinlib for a binary.
#                  Every scenario puts a cmake first on PATH (outside the builder scenarios one that exits at once),
#                  because the monotonicity arms skip before their checkout on a host with no cmake at all.
#                  A gate whose pinned commit is absent from this clone (shallow, or a fork) is reported, not faked.
#                  Control: headbinlib.sh with ripwire_private_checkout reverted to `git worktree add`, KILL>gate — every
#                  caller and the builder must leave a registration. The revert drops the old removal on purpose: under
#                  SIGKILL no removal of any kind runs, and KILL is the only mode the control asserts.
#   (C) CONTRACT — headbinlib.sh still sets no traps and its builder checks out through the helper; this gate registered
#                  nothing in the live repository.
#
# Usage: bash test/worktreeleakcheck.sh   (no ripwire binary needed: the gates it kills run against a stub it writes)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
LIB="$ROOT/test/lib/headbinlib.sh"
SELF="$( basename "$0" )"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }
[ -f "$LIB" ] || { echo "no $LIB"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "worktreeleakcheck: ROOT=$ROOT  TMP=$TMP  bash=$BASH_VERSION"

PY="$TMP/worktreeleak.py"
cat > "$PY" <<'PYEOF'
import io, os, re, shutil, signal, subprocess, sys, tempfile, threading, time
from concurrent.futures import ThreadPoolExecutor

HELPER = "ripwire_private_checkout"
LIVE = re.compile(r'\$\{?(?:ROOT|_root)\}?(?![A-Za-z0-9_])')
RAW = re.compile(r'\bworktree\s+(?:add|prune)\b')
ARG = r'("?\$?\{?[A-Za-z0-9_]+\}?"?)'
VAR = r'"(\$\{?[A-Za-z_]+\}?)"'
CALL = re.compile(r'\b' + HELPER + r'\s+' + VAR + r'\s+' + ARG + r'\s+' + VAR)
RAWADD = re.compile(r'\bworktree\s+add\b[^"]*' + VAR + r'\s+' + ARG)
MODES = (("TERM>gate", signal.SIGTERM, False), ("INT>group", signal.SIGINT, True), ("KILL>gate", signal.SIGKILL, False))
REACH_SEC, GRACE_SEC = 90, 4

STUB = r'''#!/bin/sh
# worktreeleakcheck's stub ripwire. It answers --version with the throwaway repository's HEAD stamp (headbinlib's staged
# verification), and anything else with one empty element, because nestedimportcheck and preproccondcheck stop at an
# empty --deps capture long before their checkout. When its first argument lies inside a private checkout OF THAT
# REPOSITORY -- another top-level whose common git dir, or whose alternates, is the throwaway repository's -- it records
# that top-level and sleeps there, so the gate can be signalled while the checkout is in use.
if [ "${1:-}" = "--version" ]; then echo "ripwire 0.0.0 (dev, worktreeleakcheck stub, built_from=$WL_STAMP)"; exit 0; fi
echo '<ripwire stub="worktreeleakcheck"/>'
[ -d "${1:-}" ] || exit 0
top="$( git -C "$1" rev-parse --show-toplevel 2>/dev/null )" || exit 0
[ -n "$top" ] && [ "$top" != "$WL_TOP" ] || exit 0
common="$( cd "$top" 2>/dev/null && cd "$( git rev-parse --git-common-dir 2>/dev/null )" 2>/dev/null && pwd -P )"
alt=""
if [ -f "$top/.git/objects/info/alternates" ]; then
    alt="$( cd "$( head -n 1 "$top/.git/objects/info/alternates" )" 2>/dev/null && pwd -P )"
fi
if [ "$common" = "$WL_GIT" ] || [ "$alt" = "$WL_GIT/objects" ]; then
    printf '%s\n' "$top" >> "$WL_MARK"
    exec sleep 30
fi
exit 0
'''

SHIM = r'''#!/bin/sh
# worktreeleakcheck's cmake shim: the configure step records the source tree it was handed and sleeps there, so the
# HEAD-binary builder can be signalled mid-build with its checkout in use.
src=""; prev=""
for a in "$@"; do
    [ "$prev" = "-S" ] && src="$a"
    prev="$a"
done
if [ -n "$src" ]; then
    top="$( git -C "$src" rev-parse --show-toplevel 2>/dev/null )"
    printf '%s\n' "${top:-$src}" >> "$WL_MARK"
    exec sleep 30
fi
exit 0
'''

def read(path):
    return io.open(path, encoding="utf-8", errors="replace").read()

def code(path):
    for n, l in enumerate(read(path).split("\n"), 1):
        if l.strip() and not l.lstrip().startswith("#"):
            yield n, l

def hits(path):
    return [(n, l.strip()) for n, l in code(path) if RAW.search(l) and LIVE.search(l)]

# scan ROOT SELF -> SCANNED n; HIT file:line text; GATE name rev headbin(0|1) helper|raw
def scan_main(root, self_name):
    t = os.path.join(root, "test")
    tops = sorted(f for f in os.listdir(t) if f.endswith(".sh") and f not in ("regression.sh", self_name))
    libs = sorted(os.path.join("lib", f) for f in os.listdir(os.path.join(t, "lib")) if f.endswith(".sh"))
    print("SCANNED %d" % (len(tops) + len(libs)))
    for rel in tops + libs:
        path = os.path.join(t, rel)
        for n, l in hits(path):
            print("HIT %s:%d %s" % (rel, n, l))
        if os.sep in rel:
            continue
        found = None
        for n, l in code(path):
            m = CALL.search(l)
            if m and LIVE.search(m.group(1)):
                found = (m.group(2), "helper")
                break
            m = RAWADD.search(l)
            if m and LIVE.search(l):
                found = (m.group(2), "raw")
                break
        if found:
            # a regex, not the literal call text: test/headbinstagecheck.sh counts any code line spelling that literal as a caller
            headbin = any(re.search(r'\bripwire_head_binary\s+"', l) for _, l in code(path))
            print("GATE %s %s %d %s" % (rel, found[0].strip('"'), 1 if headbin else 0, found[1]))

def hits_main(paths):
    for path in paths:
        for n, l in hits(path):
            print("HIT %s:%d %s" % (os.path.basename(path), n, l))

# revert-caller SRC DST -> the gate with every helper call put back to the `git worktree add` it replaced
def revert_caller(src, dst):
    new, n = re.subn(r'\b' + HELPER + r'\s+' + VAR + r'\s+' + ARG + r'\s+' + VAR,
                     lambda m: '( cd "%s" && git worktree add -q --detach "%s" %s )' % (m.group(1), m.group(3), m.group(2)), read(src))
    io.open(dst, "w", encoding="utf-8").write(new)
    print("REVERTED %d" % n)

# revert-lib SRC DST -> headbinlib.sh with ripwire_private_checkout's body put back to `git worktree add`
def revert_lib(src, dst):
    text = read(src)
    m = re.search(r'^' + HELPER + r'\(\)\n\{\n.*?^\}\n', text, re.S | re.M)
    if not m:
        print("SITES 0")
        return
    body = (HELPER + '()\n{\n'
            '    local _root="$1" _rev="$2" _dest="$3"\n'
            '    ( cd "$_root" && git worktree add -q --detach "$_dest" "$_rev" )\n'
            '}\n')
    io.open(dst, "w", encoding="utf-8").write(text[:m.start()] + body + text[m.end():])
    print("REVERTED lines %d-%d" % (text[:m.start()].count("\n") + 1, text[:m.end()].count("\n")))

# contract LIB -> TRAP line text; HELPER n; BUILDER found(0|1) helper_calls
def contract_main(lib):
    text = read(lib)
    for n, l in code(lib):
        if re.search(r'(?:^|[;&|{(])\s*trap\s', l):
            print("TRAP %d %s" % (n, l.strip()))
    print("HELPER %d" % len(re.findall(r'^' + HELPER + r'\(\)', text, re.M)))
    m = re.search(r'^_headbin_build\(\)\n\{\n(.*?)^\}', text, re.S | re.M)
    body = m.group(1) if m else ""
    calls = [l for l in body.split("\n") if not l.lstrip().startswith("#") and re.search(r'\b' + HELPER + r'\s+"', l)]
    print("BUILDER %d %d" % (1 if m else 0, len(calls)))

def run_q(args, cwd=None):
    return subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True)

def git_out(cwd, *a):
    r = run_q(["git", "-C", cwd] + list(a))
    return r.stdout.strip() if r.returncode == 0 else ""

def tiny_corpus(d):
    c = os.path.join(d, "corpus")
    os.makedirs(os.path.join(c, "src"))
    io.open(os.path.join(c, "src", "probe.cpp"), "w").write("int probe()\n{\n    return 0;\n}\n")
    for a in (["init", "-q"], ["config", "user.email", "t@t"], ["config", "user.name", "t"], ["config", "commit.gpgsign", "false"],
              ["add", "src"], ["commit", "-qm", "base"]):
        if run_q(["git", "-C", c] + a).returncode != 0:
            raise RuntimeError("git %s failed in the throwaway repository" % a[0])
    return c

def history_corpus(d, common):
    c = os.path.join(d, "corpus")
    if run_q(["git", "clone", "-q", "--shared", "--no-checkout", common, c]).returncode != 0:
        raise RuntimeError("git clone --shared --no-checkout of the live repository failed")
    return c

def install(corpus, root, gate, lib):
    t = os.path.join(corpus, "test")
    os.makedirs(os.path.join(t, "lib"), exist_ok=True)
    for f in os.listdir(os.path.join(root, "test", "lib")):
        if f.endswith(".sh"):
            shutil.copy(os.path.join(root, "test", "lib", f), os.path.join(t, "lib", f))
    shutil.copy(lib, os.path.join(t, "lib", "headbinlib.sh"))
    shutil.copy(os.path.join(root, "test", gate), os.path.join(t, gate))
    for fx in re.findall(r'\$ROOT/test/([A-Za-z0-9_-]+)"', read(os.path.join(root, "test", gate))):
        os.makedirs(os.path.join(t, fx), exist_ok=True)       # a fixture directory the gate refuses to start without

def entries(corpus):
    w = os.path.join(corpus, ".git", "worktrees")
    return sorted(os.listdir(w)) if os.path.isdir(w) else []

def nonempty(p):
    return os.path.isfile(p) and os.path.getsize(p) > 0

def lines_of(p):
    return [l for l in read(p).split("\n") if l] if os.path.isfile(p) else []

def gate_tmps(logpath, marks, work):
    out = set()
    first = read(logpath).split("\n", 1)[0] if os.path.isfile(logpath) else ""
    m = re.search(r'\bTMP=(\S+)', first)
    if m:
        out.add(m.group(1).rstrip("/"))
    out.update(os.path.dirname(x.rstrip("/")) for x in marks)
    rw = os.path.realpath(work)
    return {x for x in out if os.path.basename(x).startswith("tmp.") and not (rw + os.sep).startswith(os.path.realpath(x) + os.sep)}

def short(p, names):
    for base, label in names:
        if p == base or p.startswith(base + os.sep):
            return label + p[len(base):]
    return p

def of_corpus(dp, cgit):
    # a checkout OF the throwaway repository: a linked worktree whose common dir is its .git, or a clone borrowing its objects
    common = git_out(dp, "rev-parse", "--git-common-dir")
    if common and os.path.realpath(os.path.join(dp, common)) == cgit:
        return True
    alt = os.path.join(dp, ".git", "objects", "info", "alternates")
    first = lines_of(alt)[:1]
    return bool(first) and os.path.realpath(first[0]) == os.path.join(cgit, "objects")

def checkouts(bases, names, cgit):
    found = set()
    for b in bases:
        if not os.path.isdir(b):
            continue
        depth0 = b.rstrip(os.sep).count(os.sep)
        for dp, dns, fns in os.walk(b):
            if ".git" in dns or ".git" in fns:
                if of_corpus(dp, cgit):
                    found.add(os.path.realpath(dp))
                dns[:] = []
            elif dp.count(os.sep) - depth0 >= 5:
                dns[:] = []
    return [short(x, names) for x in sorted(found)]

def reap(p):
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except OSError:
        pass

def run_scenario(ctx, sc):
    r = {"reached": False, "rc": None, "escalated": False, "at_kill": [], "after": [], "present": [], "marks": [],
         "tmps": set(), "err": None, "tail": ""}
    d = tempfile.mkdtemp(prefix="s.", dir=ctx["work"])
    held = sc["kind"] == "history"
    if held:
        ctx["hist"].acquire()         # one pinned-commit checkout on disk at a time: each is a full tree of the repository
    p = None
    logpath = os.path.join(d, "gate.log")
    try:
        corpus = history_corpus(d, ctx["common"]) if held else tiny_corpus(d)
        install(corpus, ctx["root"], sc["gate"], sc["lib"])
        tmpdir = os.path.join(d, "tmpdir")
        os.makedirs(tmpdir)
        mark = os.path.join(d, "mark")
        env = dict(os.environ)
        for k in ("RIPWIRE_HEADBIN", "RIPWIRE_HEADBIN_BUILD_LOG", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
            env.pop(k, None)
        env.update(RIPWIRE_BIN=ctx["stub"], WL_STAMP=git_out(corpus, "rev-parse", "-q", "--verify", "HEAD")[:9],
                   WL_TOP=git_out(corpus, "rev-parse", "--show-toplevel"), WL_GIT=os.path.realpath(os.path.join(corpus, ".git")),
                   WL_MARK=mark, TMPDIR=tmpdir)
        # a cmake always comes first on PATH: the monotonicity arms skip before their checkout on a host without one
        if sc["stage"] == "build":
            env["PATH"] = ctx["shimdir"] + os.pathsep + env.get("PATH", "")
        else:
            env["PATH"] = ctx["idledir"] + os.pathsep + env.get("PATH", "")
            env["RIPWIRE_HEADBIN"] = ctx["stub"]
        with open(logpath, "wb") as log:
            p = subprocess.Popen(["bash", os.path.join(corpus, "test", sc["gate"])], cwd=corpus, env=env,
                                 stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            t0 = time.time()
            while time.time() - t0 < REACH_SEC and p.poll() is None and not nonempty(mark):
                time.sleep(0.05)
            r["reached"] = nonempty(mark) and p.poll() is None
            if r["reached"]:
                time.sleep(0.3)
                r["marks"] = lines_of(mark)
                r["tmps"] = gate_tmps(logpath, r["marks"], ctx["work"])
                names = []
                for x in sorted(r["tmps"]):
                    names += [(os.path.realpath(x), "$TMP"), (x, "$TMP")]
                names += [(os.path.realpath(tmpdir), "$TMPDIR"), (tmpdir, "$TMPDIR")]
                r["present"] = checkouts(sorted(r["tmps"]) + [tmpdir], names, env["WL_GIT"])
                r["marks"] = [short(os.path.realpath(x), names) for x in r["marks"]]
                r["at_kill"] = entries(corpus)
                try:
                    if sc["group"]:
                        os.killpg(p.pid, sc["sig"])
                    else:
                        os.kill(p.pid, sc["sig"])
                except OSError:
                    pass
                try:
                    r["rc"] = p.wait(timeout=GRACE_SEC)
                except subprocess.TimeoutExpired:
                    r["escalated"] = True
            reap(p)
            rc = p.wait()
            if r["rc"] is None:
                r["rc"] = rc
            time.sleep(0.3)
            r["after"] = entries(corpus)
    except Exception as e:
        r["err"] = "%s: %s" % (type(e).__name__, e)
        if p is not None:
            reap(p)
            p.wait()
    finally:
        r["tail"] = " | ".join(lines_of(logpath)[-3:])
        r["tmps"] |= gate_tmps(logpath, lines_of(os.path.join(d, "mark")), ctx["work"])
        for x in r["tmps"]:
            shutil.rmtree(x, ignore_errors=True)     # a killed gate's own temp dir, which may hold a full checkout
        if held:
            ctx["hist"].release()
    return r

# kill ROOT WORK LIB MUTLIB|- BUILDGATE|- NAME:REV... -> ROW PASS|FAIL text ...; DONE n
def kill_main(root, work, lib, mutlib, buildgate, specs):
    os.makedirs(work, exist_ok=True)
    stub = os.path.join(work, "ripwire-stub")
    io.open(stub, "w").write(STUB)
    os.chmod(stub, 0o755)
    shimdir, idledir = os.path.join(work, "shim"), os.path.join(work, "idle")
    for dirpath, body in ((shimdir, SHIM), (idledir, "#!/bin/sh\nexit 0\n")):
        os.makedirs(dirpath, exist_ok=True)
        io.open(os.path.join(dirpath, "cmake"), "w").write(body)
        os.chmod(os.path.join(dirpath, "cmake"), 0o755)
    cg = git_out(root, "rev-parse", "--git-common-dir")
    common = os.path.realpath(os.path.join(root, cg)) if cg else ""
    ctx = dict(root=root, work=work, stub=stub, shimdir=shimdir, idledir=idledir, common=common, hist=threading.Semaphore(1))
    rows, scen = [], []
    gates = [tuple(s.split(":", 1)) for s in specs]
    if gates:
        rows.append(("PASS", "(B) %d gate(s) check out a commit of the repository under test, derived from the tree: %s"
                     % (len(gates), " ".join(g for g, _ in gates))))
    else:
        rows.append(("FAIL", "(B) no gate checks out a commit of the repository under test -- the derivation found nothing to kill (a renamed helper, or the scan broke)"))
    kinds = {}
    for gate, rev in gates:
        if rev == "HEAD":
            kinds[gate] = "tiny"
            continue
        var = re.sub(r'[${}"]', "", rev)
        m = re.search(r'^\s*%s=([0-9a-fA-F]{7,40})\s*$' % re.escape(var), read(os.path.join(root, "test", gate)), re.M)
        if not m:
            rows.append(("FAIL", "(B) %s checks out %s, which this harness cannot resolve to a commit -- teach it where that value comes from" % (gate, rev)))
            continue
        sha = git_out(root, "rev-parse", "-q", "--verify", m.group(1) + "^{commit}") if common else ""
        if not re.match(r'^[0-9a-f]{40}$', sha):
            rows.append(("PASS", "(B) %s: not exercised here -- its pinned commit %s is not in this clone (shallow, or another repository's history), and the gate skips that arm the same way" % (gate, m.group(1))))
            continue
        kinds[gate] = "history"
    runnable = [g for g, _ in gates if g in kinds]
    for g in runnable:
        for name, sig, group in MODES:
            scen.append(dict(gate=g, kind=kinds[g], lib=lib, control=False, stage="stub", mode=name, sig=sig, group=group))
    if buildgate == "-":
        rows.append(("FAIL", "(B) no gate that checks out HEAD also asks headbinlib for a binary -- the builder cannot be reached to kill it"))
    else:
        for name, sig, group in MODES:
            scen.append(dict(gate=buildgate, kind="tiny", lib=lib, control=False, stage="build", mode=name, sig=sig, group=group))
    name, sig, group = MODES[2]
    if mutlib == "-":
        rows.append(("FAIL", "(B control) headbinlib.sh defines no %s to revert -- the fix is absent, so there is no control to run" % HELPER))
    else:
        for g in runnable:
            scen.append(dict(gate=g, kind=kinds[g], lib=mutlib, control=True, stage="stub", mode=name, sig=sig, group=group))
        if buildgate != "-":
            scen.append(dict(gate=buildgate, kind="tiny", lib=mutlib, control=True, stage="build", mode=name, sig=sig, group=group))
    with ThreadPoolExecutor(max_workers=4) as ex:
        results = list(ex.map(lambda sc: run_scenario(ctx, sc), scen))
    seen = set()
    for sc, r in zip(scen, results):
        seen |= r["tmps"]
        where = "mid-cmake in the HEAD-binary builder" if sc["stage"] == "build" else "at its first ripwire run inside the checkout"
        label = "%s %s, %s" % (sc["gate"], where, sc["mode"])
        tag = "(B control)" if sc["control"] else "(B)"
        if sc["control"]:
            label += ", helper reverted to git worktree add"
        if r["err"]:
            rows.append(("FAIL", "%s %s: the harness itself failed: %s" % (tag, label, r["err"])))
            continue
        if not r["reached"]:
            rows.append(("FAIL", "%s %s: never reached a checkout of the commit (gate rc=%s) -- nothing was killed mid-flight, so nothing is proven; last output: %s"
                         % (tag, label, r["rc"], r["tail"])))
            continue
        if sc["stage"] == "build" and not [x for x in r["marks"] if x.endswith("/work/head") or x.endswith("/headbin.wt/head")]:
            rows.append(("FAIL", "%s %s: the sleep reached was not the builder's (%s) -- the builder was not killed mid-build" % (tag, label, ", ".join(r["marks"]))))
            continue
        rc = r["rc"]
        how = "gate rc=%s%s" % (rc, ", its group SIGKILLed after the %d s grace" % GRACE_SEC if r["escalated"] else "")
        present = ", ".join(r["present"]) or "none"
        if rc is None or not (rc < 0 or rc >= 128):
            rows.append(("FAIL", "%s %s: the gate was not killed by the signal (%s) -- nothing was proven mid-flight" % (tag, label, how)))
        elif not sc["control"] and r["after"]:
            rows.append(("FAIL", "%s %s: %d registration(s) survive in .git/worktrees (%s; %d at the kill; checkouts on disk: %s; %s) -- a killed gate leaves every session's worktree list dirty"
                         % (tag, label, len(r["after"]), " ".join(r["after"]), len(r["at_kill"]), present, how)))
        elif not sc["control"]:
            rows.append(("PASS", "%s %s: killed with %d checkout(s) on disk (%s), %d registered; %s; .git/worktrees empty afterwards"
                         % (tag, label, len(r["present"]), present, len(r["at_kill"]), how)))
        elif r["after"]:
            rows.append(("PASS", "%s %s: %d registration(s) survive (%s) -- the kill arm sees the defect it exists for" % (tag, label, len(r["after"]), " ".join(r["after"]))))
        else:
            rows.append(("FAIL", "%s %s: NO registration survived (%s) -- the kill arm cannot tell the fix from its absence" % (tag, label, how)))
    if common:
        bases = [os.path.realpath(work)] + [os.path.realpath(x) for x in seen]
        live = [l[len("worktree "):] for l in git_out(root, "worktree", "list", "--porcelain").split("\n") if l.startswith("worktree ")]
        bad = [w for w in live if any(os.path.realpath(w) == b or os.path.realpath(w).startswith(b + os.sep) for b in bases)]
        if bad:
            rows.append(("FAIL", "(C) this gate registered %d worktree(s) in the LIVE repository: %s" % (len(bad), " ".join(bad))))
        else:
            rows.append(("PASS", "(C) this gate registered nothing in the live repository (%d registrations there, none under its own or its gates' temp dirs)" % len(live)))
    else:
        rows.append(("PASS", "(C) %s is not a git checkout, so there is no live .git/worktrees to compare against" % root))
    for v, t in rows:
        print("ROW %s %s" % (v, t))
    print("DONE %d" % len(scen))

cmd = sys.argv[1]
if cmd == "scan":
    scan_main(sys.argv[2], sys.argv[3])
elif cmd == "hits":
    hits_main(sys.argv[2:])
elif cmd == "revert-caller":
    revert_caller(sys.argv[2], sys.argv[3])
elif cmd == "revert-lib":
    revert_lib(sys.argv[2], sys.argv[3])
elif cmd == "contract":
    contract_main(sys.argv[2])
elif cmd == "kill":
    kill_main(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7:])
PYEOF

# ── (A) SCAN: nothing registers or prunes a worktree of the repository under test ──────────────────────────────────
scanOut="$( python3 "$PY" scan "$ROOT" "$SELF" 2>&1 )"
nScanned="$( printf '%s\n' "$scanOut" | sed -n 's/^SCANNED //p' | head -1 )"
nHits="$( printf '%s\n' "$scanOut" | grep -c '^HIT ' || true )"
if [ "${nScanned:-0}" -ge 1 ] && [ "$nHits" -eq 0 ]; then
    ok "(A) none of $nScanned test/*.sh and test/lib/*.sh files runs 'git worktree add|prune' against the repository under test"
else
    no "(A) $nHits line(s) register or prune a worktree of the repository under test (${nScanned:-0} files scanned) -- a killed gate leaves that in every session's shared .git:"
    printf '%s\n' "$scanOut" | grep -v -E '^(SCANNED|GATE) ' | sed 's/^/    /'
fi

# controls: a real caller with its checkout reverted, and the library with the helper reverted, must be flagged
CALLER="$( printf '%s\n' "$scanOut" | awk '$1 == "GATE" && $5 == "helper" { print $2; exit }' )"
if [ -n "$CALLER" ]; then
    mkdir -p "$TMP/revert"
    rv="$( python3 "$PY" revert-caller "$ROOT/test/$CALLER" "$TMP/revert/$CALLER" 2>&1 )"
    nRv="$( python3 "$PY" hits "$TMP/revert/$CALLER" 2>&1 | grep -c '^HIT ' || true )"
    case "$rv" in
        "REVERTED 0"|"") no "(A control) $CALLER: no ripwire_private_checkout call could be reverted ($rv)" ;;
        REVERTED*) [ "$nRv" -ge 1 ] \
                       && ok "(A control) $CALLER with its checkout reverted to git worktree add is flagged ($nRv line(s)) -- the scan is not vacuous" \
                       || no "(A control) $CALLER with its checkout reverted to git worktree add was NOT flagged -- the scan cannot see the defect it exists for" ;;
        *) no "(A control) reverting $CALLER failed: $rv" ;;
    esac
else
    no "(A control) no gate calls ripwire_private_checkout against the repository under test -- nothing to revert (the fix is absent, or the helper was renamed)"
fi
MUTLIB="$TMP/headbinlib.reverted.sh"
mutOut="$( python3 "$PY" revert-lib "$LIB" "$MUTLIB" 2>&1 )"
case "$mutOut" in
    REVERTED*)
        nMh="$( python3 "$PY" hits "$MUTLIB" 2>&1 | grep -c '^HIT ' || true )"
        [ "$nMh" -ge 1 ] \
            && ok "(A control) headbinlib.sh with ripwire_private_checkout reverted to git worktree add ($mutOut) is flagged" \
            || no "(A control) headbinlib.sh with ripwire_private_checkout reverted ($mutOut) was NOT flagged" ;;
    *)
        no "(A control) headbinlib.sh has no ripwire_private_checkout to revert: $mutOut"
        MUTLIB="-" ;;
esac

# ── (B) KILL: every checkout-taking gate, and the builder, signalled mid-flight ───────────────────────────────────────
GATES="$( printf '%s\n' "$scanOut" | awk '$1 == "GATE" { print $2 ":" $3 }' )"
BUILDGATE="$( printf '%s\n' "$scanOut" | awk '$1 == "GATE" && $3 == "HEAD" && $4 == 1 { print $2; exit }' )"
# shellcheck disable=SC2086   # one NAME:REV word per gate
python3 "$PY" kill "$ROOT" "$TMP/kill" "$LIB" "$MUTLIB" "${BUILDGATE:--}" $GATES >"$TMP/kill.out" 2>&1; killRc=$?
while IFS= read -r line; do
    case "$line" in
        "ROW PASS "*) ok "${line#ROW PASS }" ;;
        "ROW FAIL "*) no "${line#ROW FAIL }" ;;
    esac
done < "$TMP/kill.out"
if [ "$killRc" -ne 0 ] || ! grep -q '^DONE ' "$TMP/kill.out"; then
    no "(B) the kill harness did not finish (rc=$killRc): $( grep -v '^ROW ' "$TMP/kill.out" | tail -6 | tr '\n' '|' )"
fi

# ── (C) CONTRACT: headbinlib.sh sets no traps, and its builder checks out through the helper ─────────────────────────
conOut="$( python3 "$PY" contract "$LIB" 2>&1 )"
nTrap="$( printf '%s\n' "$conOut" | grep -c '^TRAP ' || true )"
if [ "$nTrap" -eq 0 ] && printf '%s\n' "$conOut" | grep -q '^HELPER '; then
    ok "(C) headbinlib.sh sets no traps -- callers own their EXIT trap, as its header promises"
else
    no "(C) headbinlib.sh sets a trap, or could not be read ($nTrap trap line(s)): $( printf '%s' "$conOut" | tr '\n' '|' )"
fi
printf '%s\n' "$conOut" | grep -q '^HELPER 1$' \
    && ok "(C) headbinlib.sh defines ripwire_private_checkout exactly once" \
    || no "(C) headbinlib.sh does not define ripwire_private_checkout exactly once ($( printf '%s\n' "$conOut" | grep '^HELPER' ))"
bl="$( printf '%s\n' "$conOut" | sed -n 's/^BUILDER //p' )"
case "$bl" in
    "1 0"|"") no "(C) _headbin_build does not check out through ripwire_private_checkout (BUILDER ${bl:-?}) -- a killed builder registers its checkout again" ;;
    "0 "*)    no "(C) headbinlib.sh has no _headbin_build to inspect" ;;
    *)        ok "(C) _headbin_build checks out through ripwire_private_checkout" ;;
esac

[ "$fail" -eq 0 ] && echo "worktreeleakcheck: ALL PASS" || { echo "worktreeleakcheck: SOME CHECKS FAILED"; exit 1; }
