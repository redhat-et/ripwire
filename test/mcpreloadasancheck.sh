#!/usr/bin/env bash
# mcpreloadasancheck.sh — ONE long-lived `ripwire --mcp` session on a sanitizer build, put through every index
# REBUILD path 20 times over, with each answer checked against a fresh one-shot CLI run on the same tree state.
#
# THE CLASS. The MCP server keeps one McpIndex for its whole life and rebuilds it IN PLACE when the tree moves.
# Anything derived from the index that holds pointers or ids into it dangles the moment the index is reassigned.
# A cached ValueRefIndex shipped doing exactly that: it outlived the IngestResult it pointed into after a rebuild
# that kept its content stamp (a chmod, a new non-source file) and read freed bindings — a heap-use-after-free that a
# plain build only shows as different rows. It is a LIFETIME bug: no single query shows it, only query → rebuild →
# query on one process does, and only a sanitizer makes it loud. `ix.ing` is rewritten in exactly two places
# (getIndex's rebuild and releaseMcpIndexMemory), so this gate drives both, and every cause that reaches them.
#
# EVERY CACHED VIEW THE INDEX HOLDS (src/mcpindex.h McpIndex), and the query that reads it here:
#   ing                 IngestResult (symbols, references, import bindings)   every verb below; fetch_body spans
#   g                   Graph (edges, canonId)                                find_symbol / find_referencing_symbols / impact / path_between
#   valueRefs           ValueRefIndex, built lazily, points INTO ing          find_symbol valueRefs/valueCallees, find_referencing_symbols, impact, uses, path_between
#   rank, prDisclosure  PageRank of the graph (+ what the iteration did)      analyze, rank_by (pagerank|authority|rrf), under --top-k=6 so rank picks the rows
#   workingSetHash,     the uncommitted-diff mask the rank was biased to      analyze on a DIRTY git root, against a cold server on the same tree
#    isCleanWorkingSet
#   fileMtime/Size/Ctime, per-file stat + byte-hash arrays, the content stamp  fetch_body with a handle minted before a mutation (must refuse, not
#    fileByteHash,       the handles carry                                     serve the old body) and with a fresh one (must equal the bytes on disk)
#    contentHash
#   dirMtime, watcher   the staleness watch-list and the FS-event watcher     the three stamp-keeping mutations below
#   incrementalPasses,  process history behind _reingest / _fresh             asserted through RIPWIRE_MCP_TIMINGS rebuilt= on every request
#    lastReingestFiles,
#    lastStale/ChangedFiles
#   mcpWorkspaceRegistry the multi-root key → roots table                     find_symbol with `paths` [A,B]
#   the ingest cache blob (ix.cacheFile) the warm rebuild reads               every rebuild goes through it
# dead-code is a CLI-only verb and holds no index cache; it is read on the CLI side and cross-checked against the
# MCP valueRefs (a function with a value-site is not dead, a static one with neither is).
#
# FIXTURES (generated, never committed: nothing here may move another gate's crawl): JS and TS (import bindings, a
# callback passed to run(), a table), Go (a same-package handler passed and stored), Python (imports, a list, a dict),
# C (a function pointer, a table, static functions). Per language a `gen` file is regenerated every cycle.
#
# ONE CYCLE (k = 1..N), all on one session started with --top-k=6, ASAN_OPTIONS halt/abort + a log dir:
#   Q0   query every view on tree A, compare with the CLI on the same state
#   M1   a STAMP-KEEPING mutation (k%3: chmod / a new non-source file / an empty directory): content unchanged, so
#        contentHash and the reference count survive. Rebuild must fire (rebuilt=1) and every answer must still match.
#        This is the arm that went red at the pre-fix head.
#   M2   a CONTENT mutation: a gen function added and the previous one removed, a value reference retargeted, written
#        by the shell on even cycles and through replace_symbol_body / insert_after_symbol on odd ones (invalidateMcpIndex)
#   RS   root switch: dirty git root B (its rank checked against a cold server), then the workspace [A,B], then back to A
#   RL   memory release (cycles 1, 6, 11, ...): --max-memory has a 64M floor and is server-wide, and a sanitizer process
#        that has run the whole cycle never falls back under it, so this arm gets its own short process (same binary,
#        same options): root R (2400 files) carries the footprint over the floor; the NEXT call on R releases the index
#        (releaseMcpIndexMemory) and rebuilds the very same tree, then A again
# Each rebuild is proved by the server's own timing line (rebuilt=1), so an arm that no longer reaches its path FAILs
# instead of passing blind. A mutation that no compared answer shows (the new reference equal to the old) FAILs too.
#
# LeakSanitizer is OFF here on BOTH CI legs (detect_leaks=0 in every sanitizer process of this gate; the ubuntu leg's job-level
# detect_leaks=1 is overridden inside them, and macOS has no LeakSanitizer): the subject is lifetime, not leaks, and a leak
# report at the exit of a long-lived server would be a different finding with its own gate. It is not switched on for Linux
# because the Linux leg has never run this gate, so nothing proves that leg's exit-time leak set is empty, and an unproven
# rc 23 would fail the gate for a reason that is not its subject. Turn it on once the train's first Linux run shows a clean set.
# The freed-chunk quarantine stays ON everywhere but the memory-release sessions (RLSANENV: quarantine_size_mb=0 and
# allocator_release_to_os_interval_ms=0, because that arm's footprint must fall back under the 64M floor, which a quarantine
# prevents). With it off, a freed chunk is handed out again at once, and a use-after-free that lands on a same-size reuse reads
# live memory and reports nothing: the class this gate exists to catch. (The known bug reported as heap-buffer-overflow with
# the quarantine off everywhere, and as the heap-use-after-free it is with it on.)
#
# Usage:
#   bash test/mcpreloadasancheck.sh [PLAIN_BIN]        # CLI reference binary (default build/ripwire); ASan binary asan/ripwire
#   RIPWIRE_ASAN_BIN=path bash test/mcpreloadasancheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/mcpreloadasancheck.sh      # CI's asan job: one binary plays both roles
#   RIPWIRE_RELOAD_CYCLES=20 (default)
# No sanitizer build (no asan/ripwire, llvm@22 tree: cmake -DRIPWIRE_ASAN=ON, see CONTRIBUTING.md) → SKIP, named.
# Exits non-zero on any failure. The memory-release arm needs two host premises (R's parse inside the memory guard's five-second
# clock; the footprint back under the 64M floor after the release): when none of its attempts met them it prints a named SKIP row
# and the other arms still decide the verdict.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
. "$ROOT/scripts/gatebound.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CYCLES="${RIPWIRE_RELOAD_CYCLES:-20}"
SESSION_CAP="${RIPWIRE_GATE_SESSION_CAP_SEC:-1500}"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }   # an ABSENT PRECONDITION with a named reason — never a silent pass

# the premises that are FAILURES, not skips: the binary under test and the tools the driver needs
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
case "$CYCLES" in ''|*[!0-9]*) echo "RIPWIRE_RELOAD_CYCLES='$CYCLES' is not a number"; exit 2;; esac
[ "$CYCLES" -ge 1 ] || { echo "RIPWIRE_RELOAD_CYCLES must be >= 1"; exit 2; }
BIN_VER="$( "$BIN" --version 2>&1 )" || { echo "$BIN does not run (--version failed): $BIN_VER"; exit 2; }
case "$BIN_VER" in ripwire*) ;; *) echo "$BIN --version printed no ripwire banner: $BIN_VER"; exit 2;; esac

# is a binary sanitizer-instrumented? (the runtime symbol cachefuzzcheck's bound_mode_of reads)
is_asan(){ LC_ALL=C grep -q -a '__asan_init' "$1" 2>/dev/null; }

# the sanitizer binary: RIPWIRE_ASAN_BIN, else the binary under test when it is one (RIPWIRE_BIN=asan/ripwire), else asan/ripwire
if [ -n "${RIPWIRE_ASAN_BIN:-}" ]; then
    ASAN_BIN="$RIPWIRE_ASAN_BIN"; [ "${ASAN_BIN#/}" = "$ASAN_BIN" ] && ASAN_BIN="$ROOT/$ASAN_BIN"
    # an override that names nothing is a typo, not the expected "this checkout has no asan/ build": exit 2, never SKIP
    [ -x "$ASAN_BIN" ] || { echo "RIPWIRE_ASAN_BIN is set to '$RIPWIRE_ASAN_BIN' but no executable is there"; exit 2; }
elif is_asan "$BIN"; then
    ASAN_BIN="$BIN"
else
    ASAN_BIN="$ROOT/asan/ripwire"
fi
echo "mcpreloadasancheck: BIN=$BIN  ASAN_BIN=$ASAN_BIN  cycles=$CYCLES"

# the named, expected missing premise: this checkout has no sanitizer build. Announced BEFORE any PASS row.
if [ ! -x "$ASAN_BIN" ]; then
    skip "no sanitizer binary at $ASAN_BIN (configure the llvm@22 tree: cmake -S . -B asan -DRIPWIRE_ASAN=ON, CONTRIBUTING.md; or set RIPWIRE_ASAN_BIN)"
    echo "SKIP — nothing asserted (no sanitizer build)"
    exit 0
fi
# present but not a sanitizer build, or one that cannot start: a different premise, and a failure
if ! is_asan "$ASAN_BIN"; then
    echo "$ASAN_BIN is not a sanitizer build (no __asan_init): this gate would test a plain binary and say it was ASan"; exit 2
fi
ASAN_VER="$( gate_bounded 90 "$ASAN_BIN" --version 2>&1 )" || { echo "$ASAN_BIN does not start within 90 s (AppleClang's ASan hangs before main on macOS 26: build the asan tree with llvm@22, CONTRIBUTING.md): $ASAN_VER"; exit 2; }
fromOf(){ printf '%s\n' "$1" | sed -n 's/.*built_from=\([0-9a-f]*\).*/\1/p' | head -1; }
BIN_FROM="$( fromOf "$BIN_VER" )"; ASAN_FROM="$( fromOf "$ASAN_VER" )"
if [ -z "$BIN_FROM" ] || [ -z "$ASAN_FROM" ] || [ "$BIN_FROM" != "$ASAN_FROM" ]; then
    echo "the CLI reference binary (built_from='$BIN_FROM') and the sanitizer binary (built_from='$ASAN_FROM') are not one source tree: rebuild asan/ so the answers compared are from the same code"; exit 2
fi

TMP="$( mktemp -d )"
TMP="$( cd "$TMP" && pwd -P )"          # realpath: both surfaces print the root they were given, and /var is a symlink on macOS
cleanup(){ gate_bounded_reap; chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT; gate_bounded_arm
mkdir -p "$TMP/san" "$TMP/srvtmp" "$TMP/clitmp"

cat >"$TMP/driver.py" <<'PYEOF'
#!/usr/bin/env python3
"""The session driver. argv: PLAIN_BIN ASAN_BIN WORK CYCLES. Prints PASS/FAIL/SKIP/NOTE rows and one SUMMARY line."""
import hashlib, json, os, re, select, shutil, signal, stat, subprocess, sys, time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor

BIN, ASAN, WORK, CYCLES = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
A, B, R = (os.path.join(WORK, d) for d in ("a", "b", "r"))
SAN = os.path.join(WORK, "san")
SRVTMP, CLITMP = os.path.join(WORK, "srvtmp"), os.path.join(WORK, "clitmp")
DARWIN = sys.platform == "darwin"
SANENV = {
    "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1:abort_on_error=1:log_path=%s/asan" % (SAN,),
    "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1:log_path=%s/ubsan" % SAN,
}
for cand in ("/opt/homebrew/opt/llvm@22/bin/llvm-symbolizer", "/usr/bin/llvm-symbolizer"):
    # the sanitizer's own symbolizer: macOS's default (atos) can take minutes on a loaded host while the process waits to abort
    if os.path.exists(cand):
        SANENV["ASAN_OPTIONS"] += ":external_symbolizer_path=" + cand
        SANENV["UBSAN_OPTIONS"] += ":external_symbolizer_path=" + cand
        break
TOPK = "6"
# the release arm only: its footprint must fall under the 64M floor, so the freed-chunk quarantine is off THERE
RLSANENV = dict(SANENV, ASAN_OPTIONS=SANENV["ASAN_OPTIONS"] + ":quarantine_size_mb=0:allocator_release_to_os_interval_ms=0")
fails, notes = [], []
checks = 0
stats = {"stamp": 0, "content": 0, "edit": 0, "switch": 0, "release": 0, "cold": 0, "changed": 0}
server = None


def row(kind, text):
    print("  %-4s  %s" % (kind, text), flush=True)


def fail(text):
    fails.append(text)
    row("FAIL", text[:3500])


def check(cond, label, detail=""):
    global checks
    checks += 1
    if not cond:
        fail("%s%s" % (label, (": " + detail) if detail else ""))
    return cond


# ───────────────────────────────────────────────── the one session ──────────────────────────────────────────────────
class Dead(Exception):
    pass


class Server:
    def __init__(self, binp, args, tmpdir, errpath, extra_env):
        env = dict(os.environ, RIPWIRE_MCP_TIMINGS="1", TMPDIR=tmpdir)
        env.update(extra_env)
        self.err = open(errpath, "w+")
        self.errpath = errpath
        # --mcp-legend=inline: every answer carries its root facts on its own root, the spelling the one-shot CLI oracle
        # writes. The default session posture moves them to a closing <about legend="ref"/> after the first answer; its
        # equality with the CLI is held by mcpincrementalcheck's and pathgapcheck's posture twins and by legendrefcheck.
        self.p = subprocess.Popen([binp, "--mcp", "--mcp-legend=inline"] + args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.err,
                                  text=True, env=env)
        self.id = 0
        self.timing_seen = 0

    def timings(self):
        self.err.flush()
        with open(self.errpath, errors="replace") as f:
            return [l for l in f.read().splitlines() if l.startswith("ripwire-timing ")]

    def rpc(self, method, params=None, wait=240):
        t0 = time.time()
        try:
            return self.rpc_(method, params, wait)
        finally:
            T["mcp"] += time.time() - t0
            T["nmcp"] += 1

    def rpc_(self, method, params=None, wait=240):
        self.id += 1
        msg = {"jsonrpc": "2.0", "id": self.id, "method": method}
        if params is not None:
            msg["params"] = params
        try:
            self.p.stdin.write(json.dumps(msg) + "\n")
            self.p.stdin.flush()
        except (BrokenPipeError, ValueError):
            raise Dead("the server closed its input (died)")
        waited = 0
        while True:
            r, _, _ = select.select([self.p.stdout], [], [], 1.0)
            if r:
                break
            waited += 1
            if self.p.poll() is not None:
                raise Dead("the server exited (rc=%s) before answering %s" % (self.p.returncode, method))
            if waited >= 8 and os.listdir(SAN):
                # a sanitizer report is on disk and the process has not answered: it is aborting (the abort and the symbolizer
                # can take minutes on a loaded macOS host); the report is the finding, so stop waiting
                raise Dead("a sanitizer report was written and the server stopped answering %s" % method)
            if waited >= wait:
                raise Dead("no answer within %d s to %s" % (wait, method))
        line = self.p.stdout.readline()
        if not line:
            raise Dead("the server exited mid-request (rc=%s)" % self.p.poll())
        resp = json.loads(line)
        # one timing line per request, printed after the response: wait for it so rebuilt= is read for THIS request
        t0 = time.time()
        while True:
            tl = self.timings()
            if len(tl) > self.timing_seen or time.time() - t0 > 20:
                break
            time.sleep(0.005)
        t = {}
        if len(tl) > self.timing_seen:
            t = dict(kv.split("=", 1) for kv in tl[self.timing_seen].split()[1:] if "=" in kv)
        self.timing_seen = len(tl)
        return resp, t

    def tool(self, name, **args):
        """-> (kind, payload, timing): kind 'ok' (payload = text) or 'err' (payload = (code, message))."""
        resp, t = self.rpc("tools/call", {"name": name, "arguments": args})
        if "error" in resp:
            return "err", (resp["error"].get("code"), resp["error"].get("message", "")), t
        return "ok", resp["result"]["content"][0]["text"], t

    def close(self):
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            return self.p.wait(timeout=180)
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait()
            return "timeout"

    def kill(self):
        try:
            self.p.kill()
            self.p.wait(timeout=10)
        except Exception:
            pass


def on_signal(signum, _frame):
    if server is not None:
        server.kill()
    row("FAIL", "session stopped by signal %d (the wall-clock cap, or the gate was stopped)" % signum)
    row("NOTE", "time: CLI %.0fs in %d runs, MCP %.0fs in %d requests" % (T["cli"], T["ncli"], T["mcp"], T["nmcp"]))
    print("SUMMARY checks=%d fails=%d cycles=-1 aborted=1" % (checks, len(fails) + 1), flush=True)
    sys.exit(124)


for s in (signal.SIGALRM, signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
    signal.signal(s, on_signal)


# ───────────────────────────────────────────────── fixtures ─────────────────────────────────────────────────────────
def put(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def base_tree(a, v):
    """The static + variant part of tree A. v (0/1) retargets the value references the main files pass."""
    cbx = "cb2" if v else "cb"
    ev = "on_event2" if v else "on_event"
    put(a + "/js/cb.js", "export function cb(x) { return x + 1; }\nexport function cb2(x) { return x + 2; }\n")
    put(a + "/js/run.js", "export function run(f, x) { return f(x); }\n")
    put(a + "/js/main.js", "import { run } from './run.js';\nimport { cb, cb2 } from './cb.js';\n"
        "export function go() { return run(%s, 1); }\nexport const table = { onEvent: cb2 };\n"
        "function jsDead() { return 0; }\nfunction jsVonly() { return 1; }\nconst jsSlot = { h: jsVonly };\n" % cbx)
    put(a + "/ts/handlers.ts", "export function onTs(x: number): number { return x * 2; }\n"
        "export function onTs2(x: number): number { return x * 3; }\n")
    put(a + "/ts/app.ts", "import { onTs, onTs2 } from './handlers';\n"
        "export function registerTs(f: (n: number) => number): number { return f(1); }\n"
        "export function bootTs(): number { return registerTs(%s); }\n"
        "export const tsTable: { [k: string]: (n: number) => number } = { k: onTs2 };\n" % ("onTs2" if v else "onTs"))
    put(a + "/go/go.mod", "module example.com/gate\n\ngo 1.21\n")
    put(a + "/go/handlers/handlers.go", "package handlers\n\nfunc OnEvent(x int) int  { return x + 1 }\nfunc OnEvent2(x int) int { return x + 2 }\n")
    put(a + "/go/main.go", "package main\n\nimport \"example.com/gate/handlers\"\n\nfunc register(f func(int) int) int { return f(1) }\n\n"
        "func localHandler(x int) int { return x * 4 }\n\nfunc Boot() int { return register(handlers.OnEvent) + register(%s) }\n\n"
        "var table = map[string]func(int) int{\"k\": handlers.OnEvent2, \"l\": localHandler}\n\nfunc main() { _ = Boot() }\n\n"
        "func deadGo() int { return 0 }\n\nfunc vonlyGo() int { return 1 }\n\nvar slots = []func() int{vonlyGo}\n"
        % ("localHandler" if not v else "func(x int) int { return x }"))
    put(a + "/py/handlers.py", "def on_event(x):\n    return x + 1\n\n\ndef on_event2(x):\n    return x + 2\n")
    put(a + "/py/app.py", "from handlers import on_event, on_event2\n\n\ndef register(f):\n    return f(1)\n\n\ndef boot():\n    return register(%s)\n\n\n"
        "TABLE = {\"k\": on_event2}\n\n\ndef _py_dead():\n    return 0\n\n\ndef _py_vonly():\n    return 1\n\n\nSLOTS = [_py_vonly]\n" % ev)
    put(a + "/c/handlers.h", "int c_on_event(int x);\nint c_on_event2(int x);\n")
    put(a + "/c/handlers.c", "#include \"handlers.h\"\nint c_on_event(int x) { return x + 1; }\nint c_on_event2(int x) { return x + 2; }\n")
    put(a + "/c/app.c", "#include \"handlers.h\"\ntypedef int (*fn_t)(int);\nstatic fn_t fp;\nstruct ops { fn_t op; };\n"
        "static const struct ops tbl = { c_on_event2 };\nvoid c_setup(void) { fp = %s; }\nint c_boot(void) { return fp(1) + tbl.op(2); }\n"
        "static int c_dead(void) { return 0; }\nstatic int c_vonly(void) { return 1; }\nstatic fn_t slot2 = c_vonly;\n"
        % ("c_on_event2" if v else "c_on_event"))


def gen_tree(a, k, v):
    """The gen files of cycle k: gen<k> added, the previous one gone, the value reference retargeted by v."""
    put(a + "/js/gen.js", "import { cb, cb2 } from './cb.js';\nexport function jsgen%d() { return %d; }\n"
        "export const JSGEN = { h: jsgen%d, c: %s };\n" % (k, k, k, "cb2" if v else "cb"))
    put(a + "/ts/gen.ts", "import { onTs, onTs2 } from './handlers';\nexport function tsgen%d(): number { return %d; }\n"
        "export const TSGEN = [tsgen%d, %s];\n" % (k, k, k, "onTs2" if v else "onTs"))
    put(a + "/go/gen.go", "package main\n\nfunc gogen%d() int { return %d }\n\nvar genSlots = []func() int{gogen%d}\n" % (k, k, k))
    put(a + "/py/gen.py", "from handlers import on_event, on_event2\n\n\ndef pygen_%d():\n    return %d\n\n\nPYGEN = [pygen_%d, %s]\n"
        % (k, k, k, "on_event2" if v else "on_event"))
    put(a + "/c/gen.c", "#include \"handlers.h\"\nstatic int cgen_%d(void) { return %d; }\nstatic int cdead_%d(void) { return 0; }\n"
        "static int (*cgen_slot)(void) = cgen_%d;\nint cgen_use(void) { return cgen_slot() + %s(1); }\n"
        % (k, k, k, k, "c_on_event2" if v else "c_on_event"))


def bulk_tree(r):
    """Root R: the JS value-reference trio plus 2400 small C files — enough that the resident index alone carries the
    server over the 64M floor, so the NEXT call releases it."""
    put(r + "/js/cb.js", "export function cb(x) { return x + 1; }\n")
    put(r + "/js/run.js", "export function run(f, x) { return f(x); }\n")
    put(r + "/js/main.js", "import { run } from './run.js';\nimport { cb } from './cb.js';\nexport function go() { return run(cb, 1); }\n")
    for d in range(12):
        for f in range(200):
            put("%s/bulk/d%d/f%d.c" % (r, d, f), "".join(
                "int b%d_%d_%d(int x) { return x > 0 ? b%d_%d_%d(x - 1) + %d : %d; }\n" % (d, f, k, d, f, (k + 1) % 30, k, k)
                for k in range(30)))


def tree_b(b, k):
    """Root B: a git repo (so the rank is biased to the uncommitted diff); bgen.js is rewritten every cycle."""
    put(b + "/js/bcb.js", "export function bcb(x) { return x + 1; }\n")
    put(b + "/js/brun.js", "export function brun(f, x) { return f(x); }\n")
    put(b + "/js/bmain.js", "import { brun } from './brun.js';\nimport { bcb } from './bcb.js';\nexport function bgo() { return brun(bcb, 1); }\n")
    put(b + "/py/bh.py", "def bh_event(x):\n    return x\n\n\ndef bh_reg(f):\n    return f(1)\n\n\ndef bh_boot():\n    return bh_reg(bh_event)\n")
    bump_b(b, k)


def bump_b(b, k):
    put(b + "/js/bgen.js", "import { bcb } from './bcb.js';\nexport function bgen%d() { return %d; }\nexport const BGEN = { h: bgen%d, c: bcb };\n" % (k, k, k))


def fingerprint(root):
    h = hashlib.sha1()
    for dp, dn, fn in os.walk(root):
        dn[:] = sorted(d for d in dn if d != ".git")
        for f in sorted(fn):
            p = os.path.join(dp, f)
            h.update(os.path.relpath(p, root).encode() + b"\0")
            with open(p, "rb") as fh:
                h.update(fh.read())
    return h.hexdigest()


# ───────────────────────────────────────── the two surfaces, normalised ─────────────────────────────────────────────
COMMENT = re.compile(r"<!--.*?-->", re.S)
HINT = re.compile(r' hint="[^"]*"')
VRKEYS = ("in_id", "to", "def", "bind", "into", "called_by", "through", "sites")


def xml_clean(t):
    return HINT.sub("", COMMENT.sub("", t)).strip()


def boolstr(v):
    return "1" if v is True else "0" if v is False else str(v)


def vr_window(total, shown, capped, rows):
    return (str(total), str(shown), boolstr(capped), tuple(sorted(tuple(str(r.get(k, "")) for k in VRKEYS) for r in rows)))


NOWIN = ("0", "0", "0", ())


T = {"cli": 0.0, "mcp": 0.0, "ncli": 0, "nmcp": 0}


def cli(binp, root, *args, tmp=CLITMP):
    t0 = time.time()
    try:
        return cli_(binp, root, *args, tmp=tmp)
    finally:
        T["cli"] += time.time() - t0   # summed over the worker threads
        T["ncli"] += 1


def cli_(binp, root, *args, tmp=CLITMP):
    env = dict(os.environ, TMPDIR=tmp)
    env.update(SANENV)
    p = subprocess.run([binp, root, "--no-cache", "--legend=compact"] + list(args), capture_output=True, text=True, timeout=300, env=env)
    return p.returncode, p.stdout, p.stderr


def cli_view(root, verb, sym):
    """CLI answer of --callers/--callees as (kind, data); NOTFOUND when the CLI says found=0 (rc 1)."""
    rc, out, err = cli(BIN, root, "--%s=%s" % (verb, sym))
    c = xml_clean(out)
    if rc == 1 and 'found="0"' in c:
        return ("NOTFOUND",)
    if rc != 0 or not c.startswith("<"):
        return ("CLIERR", rc, err[:200], c[:200])
    el = ET.fromstring(c)
    syms = tuple(sorted((s.get("n"), s.get("p")) for s in el.findall("s")))
    w = el.find("vrs")
    win = vr_window(w.get("total"), w.get("shown"), w.get("capped"), [v.attrib for v in w.findall("vr")]) if w is not None else NOWIN
    return ("OK", el.get("defs"), syms, win)


def mcp_fs_view(kind, payload):
    if kind == "err":
        return ("NOTFOUND",) if payload[0] == -32602 and "not found" in payload[1] else ("MCPERR", payload)
    j = json.loads(payload)

    def win(k):
        w = j.get(k)
        return vr_window(w["total"], w["shown"], w["capped"], w["rows"]) if w else NOWIN

    def syms(k):
        return tuple(sorted((s["name"], "%s:%s" % (s["file"], s["line"])) for s in j.get(k, [])))
    return ("OK", str(j.get("defs")), syms("calledBy"), win("valueRefs"), syms("calls"), win("valueCallees"))


def cli_refs(root, syms, paths, greps, rankbys, with_map=True):
    """The one-shot CLI answers for one tree state, keyed like the MCP side (the runs are independent: six at a time)."""
    def fs_task(s):
        cal = cli_view(root, "callers", s)
        # a leaf (a handler or a generated function) calls nothing: the callees run is skipped and the MCP side must say the same
        cee = cli_view(root, "callees", s) if s in CALLERS_OF else ("OK", None, (), NOWIN)
        if cal[0] == "NOTFOUND" or cee[0] == "NOTFOUND":
            return [(("fs", s), ("NOTFOUND",)), (("frs", s), ("NOTFOUND",))]
        return [(("fs", s), ("OK", cal[1], cal[2], cal[3], cee[2], cee[3])), (("frs", s), ("OK", cal[1], cal[2], cal[3]))]

    def xml_task(key, *args):
        rc, out, err = cli(BIN, root, *args)
        return [(key, ("NOTFOUND",) if (rc == 1 and 'found="0"' in out) else ("OK", xml_clean(out)) if rc == 0 else ("CLIERR", rc, err[:200]))]

    def grep_task(g):
        rc, out, err = cli(BIN, root, "--grep=%s" % g)
        hits = set()
        if rc == 0:
            for f in ET.fromstring(xml_clean(out)).findall("f"):
                for h in f.findall("hit"):
                    hits.add((f.get("p"), int(h.get("l"))))
        return [(("grep", g), ("OK", tuple(sorted(hits))) if rc == 0 else ("CLIERR", rc, err[:200]))]

    def dead_task():
        rc, out, err = cli(BIN, root, "--dead-code")
        dead = set()
        if rc == 0:
            for d in ET.fromstring(xml_clean(out)).findall("d"):
                dead.add(d.get("n"))
        return [(("dead",), ("OK", tuple(sorted(dead))) if rc == 0 else ("CLIERR", rc, err[:200]))]

    tasks = [lambda s=s: fs_task(s) for s in syms]
    for s in syms[:5]:
        for verb in ("impact", "uses"):
            tasks.append(lambda s=s, verb=verb: xml_task((verb, s), "--%s=%s" % (verb, s)))
    for f, t in paths:
        tasks.append(lambda f=f, t=t: xml_task(("path", f, t), "--path=%s,%s" % (f, t)))
    tasks += [lambda g=g: grep_task(g) for g in greps]
    if with_map:
        tasks.append(lambda: xml_task(("map",), "--order=stable", "--top-k=" + TOPK))
        for rb in rankbys:
            tasks.append(lambda rb=rb: xml_task(("rank_by", rb), "--rank-by=" + rb, "--order=stable", "--top-k=" + TOPK))
    tasks.append(dead_task)
    ref = {}
    with ThreadPoolExecutor(max_workers=6) as ex:
        for rows in ex.map(lambda t: t(), tasks):
            ref.update(rows)
    return ref


def mcp_xml(srv, name, notfound_ok=True, **args):
    kind, payload, t = srv.tool(name, **args)
    if kind == "err":
        return (("NOTFOUND",) if (payload[0] == -32602 and "not found" in payload[1]) else ("MCPERR", payload)), t
    return ("OK", xml_clean(payload)), t


def mcp_views(srv, root, syms, paths, greps, rankbys, with_map=True):
    """Every view, asked of the long-lived session. -> (answers, timings of the first request)."""
    got, first = {}, None
    for s in syms:
        kind, payload, t = srv.tool("find_symbol", path=root, symbol=s)
        first = first or t
        got[("fs", s)] = mcp_fs_view(kind, payload)
        kind, payload, t = srv.tool("find_referencing_symbols", path=root, symbol=s)
        v = mcp_fs_view(kind, payload)
        got[("frs", s)] = v if v[0] != "OK" else v[:4]
    for s in syms[:5]:
        for verb in ("impact", "uses"):
            got[(verb, s)], _ = mcp_xml(srv, verb, path=root, symbol=s)
    for f, tt in paths:
        got[("path", f, tt)], _ = mcp_xml(srv, "path_between", path=root, **{"from": f, "to": tt})
    for g in greps:
        kind, payload, _ = srv.tool("grep", path=root, pattern=g)
        if kind == "err":
            got[("grep", g)] = ("MCPERR", payload)
        else:
            j = json.loads(payload)
            got[("grep", g)] = ("OK", tuple(sorted(set((h["file"], int(h["line"])) for h in j["hits"]))))
    if with_map:
        got[("map",)], _ = mcp_xml(srv, "analyze", path=root)
        for rb in rankbys:
            got[("rank_by", rb)], _ = mcp_xml(srv, "rank_by", path=root, rank_by=rb)
    return got, first


def compare(label, ref, got, skip=()):
    """Every key the reference has must be answered identically; returns (compared, bad keys)."""
    bad = []
    for key, rv in ref.items():
        if key[0] in skip or key[0] == "dead":
            continue
        gv = got.get(key)
        if gv != rv:
            bad.append((key, rv, gv))
    return bad


def short(v, n=330):
    s = repr(v)
    return s if len(s) <= n else s[:n] + "...(%d)" % len(s)


def check_dead(label, ref, got):
    """dead-code (CLI, fresh) against the session's valueRefs: a static function with no caller is dead only when no
    value-site holds it. The CLI lists the dead set; the session says per function whether anything holds it."""
    dead = set(ref[("dead",)][1]) if ref[("dead",)][0] == "OK" else None
    if dead is None:
        check(False, "%s dead-code ran on the CLI" % label, short(ref[("dead",)]))
        return
    for s, expectDead in (("c_dead", True), ("c_vonly", False)):
        g = got.get(("fs", s))
        if not g or g[0] != "OK":
            check(False, "%s MCP find_symbol(%s) answered" % (label, s), short(g))
            continue
        noCallers = g[2] == ()
        holdsValue = g[3][0] != "0"
        check(noCallers and ((s in dead) == expectDead) and (holdsValue == (not expectDead)),
              "%s dead-code agrees with the session's valueRefs for %s" % (label, s),
              "dead=%s callers=%s valueRefs=%s" % (s in dead, g[2], g[3][0]))


# ───────────────────────────────────────────────── the session ──────────────────────────────────────────────────────
CALLERS_OF = {"run", "register", "c_boot", "go", "Boot", "cgen_use", "brun", "bgo", "bh_reg", "bh_boot"}     # the symbols that call something; every other one is a leaf


def symbols_at(k):
    cur = ["jsgen%d" % k, "pygen_%d" % k, "cgen_%d" % k, "cdead_%d" % k]
    old = ["jsgen%d" % (k - 1)] if k > 1 else []
    return ["cb", "cb2", "run", "on_event", "c_on_event", "onTs", "localHandler", "c_vonly", "c_dead", "jsVonly",
            "register", "c_boot", "go", "Boot", "cgen_use"] + cur + old


PATHS = [("Boot", "register"), ("go", "cb"), ("c_boot", "c_on_event")]
GREPS = ["cb2"]
RANKBYS = ["pagerank", "rrf"]


def cold_map(root):
    """A fresh server (fresh TMPDIR, plain binary) answering `analyze` on `root`: the instrument for a rank this CLI has no twin of."""
    tmp = os.path.join(WORK, "coldtmp")
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    s = Server(BIN, ["--top-k=" + TOPK], tmp, os.path.join(WORK, "cold.err"), {})
    try:
        s.rpc("initialize")
        kind, payload, _ = s.tool("analyze", path=root)
    finally:
        s.close()
    stats["cold"] += 1
    return ("OK", xml_clean(payload)) if kind == "ok" else ("MCPERR", payload)


def release_attempt(k, refR, refA, kk):
    """One fresh process under the 64M floor. -> 'ok' | 'partial' | 'refused' | 'noreleased'; the last three are premises this
    host did not meet (named by the caller), never a pass. --max-memory has a 64M floor and is server-wide, and a sanitizer
    process that has run the whole cycle never falls back under it, so the release path gets a fresh process. Root R's
    resident index alone carries it over the line, so the SECOND call on R releases that index (releaseMcpIndexMemory) and
    rebuilds the unchanged tree; the next call, on A, releases R's rebuild again and rebuilds A. Only those calls are made."""
    s = Server(ASAN, ["--top-k=" + TOPK, "--max-memory=64M"], SRVTMP + "_rl", os.path.join(WORK, "release.err"), RLSANENV)
    status = "ok"
    try:
        s.rpc("initialize")
        kind, payload, t1 = s.tool("find_symbol", path=R, symbol="cb")
        v1 = mcp_fs_view(kind, payload)
        if v1[0] != "OK":
            return "partial"          # the memory guard's soft stop (a parse past five seconds under a 64M limit) left R without its symbols
        check(t1.get("rebuilt") == "1", "cycle %d RL: root R built (rebuilt=1)" % k, short(t1))
        check(v1 == refR, "cycle %d RL: root R's answer equals the one-shot CLI" % k, "cli=%s mcp=%s" % (short(refR), short(v1)))
        kind, payload, t2 = s.tool("find_symbol", path=R, symbol="cb")
        if kind == "err" and "memory limit" in payload[1]:
            return "refused"
        v2 = mcp_fs_view(kind, payload)
        if v2[0] != "OK":
            return "partial"
        if t2.get("rebuilt") != "1":
            return "noreleased"
        stats["release"] += 1
        check(v2 == refR, "cycle %d RL: the unchanged tree R, released and rebuilt, answers equal the one-shot CLI" % k, "cli=%s mcp=%s" % (short(refR), short(v2)))
        gotA, fA = mcp_views(s, A, symbols_at(kk), PATHS, GREPS, RANKBYS)
        # the memory guard may refuse ANY call on A by name, not only the first (a bigger index reaches the floor later in the
        # sequence): such a refusal is the named premise "the footprint stayed over the floor", and every call it did
        # answer must still equal the one-shot CLI
        refusedA = [key for key, v in gotA.items() if v and v[0] == "MCPERR" and "memory limit" in str(v[1])]
        if refusedA:
            row("NOTE", "cycle %d RL: the release was proved; %d call(s) on A after it were refused by name (the footprint stayed over the floor)"
                % (k, len(refusedA)))
            badA = [b_ for b_ in compare("RL A", refA, gotA) if b_[0] not in refusedA]
            check(not badA, "cycle %d RL: after the release, every call on tree A the guard answered equals the one-shot CLI" % k,
                  "; ".join("%s: cli=%s mcp=%s" % (a_, short(b_), short(c_)) for a_, b_, c_ in badA[:2]))
            return "ok"
        bad = compare("RL A", refA, gotA)
        check(not bad, "cycle %d RL: after the release, tree A answers equal the one-shot CLI" % k,
              "; ".join("%s: cli=%s mcp=%s" % (a_, short(b_), short(c_)) for a_, b_, c_ in bad[:2]))
        check(fA and fA.get("rebuilt") == "1", "cycle %d RL: A was rebuilt after R's release" % k, short(fA))
    finally:
        rc = s.close()
        check(rc == 0, "cycle %d RL: the release session ended with exit status 0" % k, "rc=%s" % rc)
        with open(os.path.join(WORK, "release.err"), errors="replace") as fh:
            e = fh.read()
        check("Sanitizer" not in e and "runtime error:" not in e, "cycle %d RL: no sanitizer text on the release session's stderr" % k, e[:600])
    return status


def release_session(k, refR, refA, kk):
    os.makedirs(SRVTMP + "_rl", exist_ok=True)
    if not stats.get("rl_warm"):
        # the memory guard stops a parse that runs past five seconds, and a cold sanitizer parse of R can: warm the ingest
        # cache once, unlimited, so every limited session below reads facts from it and its ingest is short
        w = Server(ASAN, ["--top-k=" + TOPK], SRVTMP + "_rl", os.path.join(WORK, "warm.err"), RLSANENV)
        try:
            w.rpc("initialize")
            kind, payload, _ = w.tool("find_symbol", path=R, symbol="cb")
            check(kind == "ok", "release sessions: the unlimited warm-up build of R answered", short(payload))
        finally:
            check(w.close() == 0, "release sessions: the warm-up session ended with exit status 0")
        stats["rl_warm"] = 1
    for attempt in range(1, 5):
        st = release_attempt(k, refR, refA, kk)
        if st == "ok":
            return
        stats["rl_miss"] = stats.get("rl_miss", 0) + 1
        row("NOTE", "cycle %d RL attempt %d: premise not met (%s)" % (k, attempt, {
            "partial": "the memory guard's 5 s soft-stop clock cut R's parse on this host",
            "refused": "the footprint stayed over the 64M floor after the release, so the rebuild was refused by name",
            "noreleased": "the footprint stayed under the floor, so no release fired"}[st]))


def sanitizer_findings():
    found = []
    for f in sorted(os.listdir(SAN)):
        with open(os.path.join(SAN, f), errors="replace") as fh:
            found.append((f, fh.read()))
    err = ""
    if server is not None:
        server.err.flush()
        with open(server.errpath, errors="replace") as fh:
            err = fh.read()
    for pat in ("ERROR: AddressSanitizer", "ERROR: LeakSanitizer", "runtime error:", "SUMMARY: AddressSanitizer", "SUMMARY: UndefinedBehaviorSanitizer"):
        if pat in err:
            found.append(("server stderr", err[err.index(pat):err.index(pat) + 3000]))
            break
    return found


def main():
    global server
    shutil.rmtree(WORK + "/a", ignore_errors=True)
    for r in (A, B, R):
        os.makedirs(r, exist_ok=True)
    base_tree(A, 0)
    gen_tree(A, 0, 0)
    tree_b(B, 0)
    bulk_tree(R)
    gitenv = dict(os.environ)
    for cmd in (["init", "-q"], ["add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init"]):
        subprocess.run(["git", "-C", B] + cmd, check=True, capture_output=True, env=gitenv)
    row("NOTE", "fixtures: A (js/ts/go/py/c, %d files), B (git repo, dirty), R (%d files); CLI reference binary %s" % (
        sum(len(f) for _, _, f in os.walk(A)), sum(len(f) for _, _, f in os.walk(R)), BIN))

    server = Server(ASAN, ["--top-k=" + TOPK], SRVTMP, os.path.join(WORK, "server.err"), SANENV)
    refs = {}            # fingerprint of tree A -> CLI answers (the CLI is a function of tree state)
    refR = None
    prev_ref = None
    live_handles = {}    # symbol -> handle minted at some earlier state
    done = 0
    try:
        server.rpc("initialize")
        v = 0
        state = {"k": 0, "v": 0}

        def ref_for(k, root=A, syms=None):
            fp = fingerprint(root)
            if fp not in refs:
                refs[fp] = cli_refs(root, syms or symbols_at(k), PATHS, GREPS, RANKBYS)
            return refs[fp]

        def qpoint(label, k, expect_rebuild, kind):
            """query every view on A, compare with the CLI on this state; assert the first request rebuilt (or not)."""
            nonlocal prev_ref
            ref = ref_for(k)
            got, first = mcp_views(server, A, symbols_at(k), PATHS, GREPS, RANKBYS)
            bad = compare(label, ref, got)
            check(not bad, "cycle %d %s: all %d answers equal the one-shot CLI" % (k, label, len(ref) - 1),
                  "; ".join("%s: cli=%s mcp=%s" % (key, short(rv), short(gv)) for key, rv, gv in bad[:3]) + (" (+%d more)" % (len(bad) - 3) if len(bad) > 3 else ""))
            check_dead("cycle %d %s" % (k, label), ref, got)
            if expect_rebuild is not None:
                check(first and first.get("rebuilt") == ("1" if expect_rebuild else "0"),
                      "cycle %d %s: the first request %s the index (rebuilt=%s)" % (k, label, "rebuilt" if expect_rebuild else "reused", first and first.get("rebuilt")),
                      "timing %s" % first)
                if expect_rebuild and first and first.get("rebuilt") == "1":
                    stats[kind] += 1
            return ref, got

        # cycle 0: the cold build
        ref0, got0 = qpoint("cold", 0, True, "stamp")
        stats["stamp"] -= 1
        prev_ref = ref0
        stableK = 0

        for k in range(1, CYCLES + 1):
            kk = k
            # ── M1: a stamp-keeping mutation ──────────────────────────────────────────────────────────────────────
            which = k % 3
            if which == 1:
                f = A + "/js/main.js"
                m = os.stat(f).st_mode
                os.chmod(f, m ^ stat.S_IXUSR)
                os.chmod(f, m)
                what = "chmod (ctime only)"
            elif which == 2:
                put(A + "/notes_%d.txt" % k, "x\n")
                what = "a new non-source file"
            else:
                os.makedirs(A + "/empty_%d" % k, exist_ok=True)
                what = "an empty directory"
            # the state before this cycle's content change (the previous cycle's, plus the stamp-keeping change)
            ref, got = qpoint("M1 " + what, kk - 1, True, "stamp")
            changed_by_m1 = ref != prev_ref
            prev_ref = ref

            # ── M2: a content mutation ────────────────────────────────────────────────────────────────────────────
            v = k % 2
            old_handles = dict(live_handles)
            base_tree(A, v)
            gen_tree(A, k, v)
            via_edit = (k % 2 == 1)
            if via_edit:
                kind, payload, t = server.tool("insert_after_symbol", path=A, symbol="jsgen%d" % k, file="js/gen.js",
                                               text="export function jsins%d() { return %d; }" % (k, k))
                check(kind == "ok" and t.get("rebuilt") == "1", "cycle %d M2: insert_after_symbol applied and the index was rebuilt around it" % k, short((kind, payload, t)))
                kind, payload, t = server.tool("replace_symbol_body", path=A, symbol="jsVonly", file="js/main.js",
                                               new_body="function jsVonly() { return %d; }" % (100 + k))
                check(kind == "ok", "cycle %d M2: replace_symbol_body applied" % k, short((kind, payload)))
                stats["edit"] += 1
            # an edit verb rebuilds the index itself, after its write: the first QUERY then reuses it (rebuilt=0)
            ref2, got2 = qpoint("M2 content (%s)" % ("MCP edit verbs" if via_edit else "file rewrite"), kk, None if via_edit else True, "content")
            if via_edit:
                stats["content"] += 1
            check(ref2 != prev_ref, "cycle %d M2: the mutation is visible in at least one compared answer (a stale index would be caught)" % k)
            stats["changed"] += 1 if ref2 != prev_ref else 0
            prev_ref = ref2

            # handles: minted before the mutation must refuse, minted now must serve the bytes on disk
            for sym in ("jsgen%d" % (k - 1), "jsVonly"):
                h = old_handles.get(sym)
                if h:
                    kind, payload, _ = server.tool("fetch_body", path=A, handle=h)
                    check(kind == "err" and ("stale handle" in payload[1] or "does not resolve" in payload[1]), "cycle %d: a handle minted before the rewrite is refused as stale (%s)" % (k, sym), short((kind, payload)))
            for sym, rel in (("jsgen%d" % k, "js/gen.js"), ("cgen_%d" % k, "c/gen.c"), ("pygen_%d" % k, "py/gen.py")):
                kind, payload, _ = server.tool("find_symbol", path=A, symbol=sym)
                if kind == "ok":
                    h = json.loads(payload)["symbol"]["handle"]
                    live_handles[sym] = h
                    kind, payload, _ = server.tool("fetch_body", path=A, handle=h)
                    body = json.loads(payload)["body"] if kind == "ok" else None
                    text = open(os.path.join(A, rel)).read()
                    check(body is not None and sym in body and body in text, "cycle %d: fetch_body(%s) with a fresh handle is the bytes on disk" % (k, sym), short((kind, payload)))
                else:
                    check(False, "cycle %d: find_symbol(%s) answered" % (k, sym), short(payload))
            for sym in ("jsVonly",):
                kind, payload, _ = server.tool("find_symbol", path=A, symbol=sym)
                if kind == "ok":
                    live_handles[sym] = json.loads(payload)["symbol"]["handle"]

            # ── RS: root switches ─────────────────────────────────────────────────────────────────────────────────
            bump_b(B, k)
            bsyms = ["bcb", "bgen%d" % k, "bh_event", "bh_reg"]
            bref = cli_refs(B, bsyms, [("bh_boot", "bh_reg")], ["bcb"], [], with_map=False)
            bgot, first = mcp_views(server, B, bsyms, [("bh_boot", "bh_reg")], ["bcb"], [], with_map=False)
            check(first and first.get("rebuilt") == "1", "cycle %d RS: switching to root B rebuilt the index" % k, short(first))
            stats["switch"] += 1 if first and first.get("rebuilt") == "1" else 0
            bad = compare("B", bref, bgot)
            check(not bad, "cycle %d RS: root B (dirty git repo) answers equal the one-shot CLI" % k, "; ".join("%s: cli=%s mcp=%s" % (a, short(b), short(c)) for a, b, c in bad[:2]))
            kind, payload, _ = server.tool("analyze", path=B)
            coldB = cold_map(B)
            check(kind == "ok" and ("OK", xml_clean(payload)) == coldB, "cycle %d RS: analyze on the dirty root equals a cold server's (working-set rank)" % k, short(coldB))
            # the workspace key
            kind, payload, t = server.tool("find_symbol", paths=[A, B], symbol="c_vonly")
            wsOK = kind == "ok"
            check(wsOK and t.get("rebuilt") == "1", "cycle %d RS: the workspace [A,B] rebuilt the index" % k, short((kind, payload if kind == "err" else "", t)))
            if wsOK:
                wj = json.loads(payload)
                check(wj.get("valueRefs", {"total": 0})["total"] == int(ref2[("fs", "c_vonly")][3][0]), "cycle %d RS: the workspace answer for c_vonly carries A's value references" % k,
                      "ws=%s a=%s" % (wj.get("valueRefs", {}).get("total"), ref2[("fs", "c_vonly")][3][0]))
            stats["switch"] += 1 if t.get("rebuilt") == "1" else 0
            # and back to A
            refA, gotA = qpoint("RS back to A", kk, True, "switch")

            # ── RL: the memory-release path, in its own short session under the 64M floor ────────────────────────
            if refR is None:
                cal, cee = cli_view(R, "callers", "cb"), cli_view(R, "callees", "cb")
                refR = ("OK", cal[1], cal[2], cal[3], cee[2], cee[3])
            if k % 5 == 1:
                release_session(k, refR, ref_for(kk), kk)
                stats["rl_cycles"] = stats.get("rl_cycles", 0) + 1
            done = k
            row("PASS" if not fails else "NOTE", "cycle %d/%d done (checks so far %d, failures %d)" % (k, CYCLES, checks, len(fails)))
    except Dead as e:
        fail("the server died: %s" % e)
        # let the report finish landing in the log directory (the symbolizer can take a while on a loaded host): wait for its
        # SUMMARY line, or for the process to be gone, for at most two minutes
        t0 = time.time()
        while time.time() - t0 < 120 and server.p.poll() is None:
            if any("SUMMARY:" in open(os.path.join(SAN, f), errors="replace").read() for f in os.listdir(SAN)):
                break
            time.sleep(1)
        server.kill()
    except Exception as e:  # a driver bug must be loud, never a pass
        import traceback
        fail("driver error: %r\n%s" % (e, traceback.format_exc()[-1500:]))
    rc = server.close() if server.p.poll() is None else server.p.returncode
    found = sanitizer_findings()
    check(not found, "no sanitizer report in the log directory or on stderr (halt_on_error, abort_on_error, log_path)",
          " | ".join("%s: %s" % (n, t[:3000]) for n, t in found[:1]))
    check(rc == 0, "the session ended with exit status 0 after its input closed", "rc=%s" % rc)
    row("NOTE", "time: CLI %.0fs in %d runs, MCP %.0fs in %d requests" % (T["cli"], T["ncli"], T["mcp"], T["nmcp"]))
    print("SUMMARY checks=%d fails=%d cycles=%d stamp=%d content=%d edit=%d switch=%d release=%d cold=%d changed=%d missed=%d rc=%s san=%d" % (
        checks, len(fails), done, stats["stamp"], stats["content"], stats["edit"], stats["switch"], stats["release"], stats["cold"],
        stats["changed"], stats.get("rl_miss", 0), rc, len(found)), flush=True)
    sys.exit(1 if fails else 0)


main()
PYEOF

echo "-- one session, $CYCLES cycles: stamp-keeping rebuild, content rebuild (shell + MCP edit verbs), root switch, workspace, memory release"
START="$( date +%s )"
# the driver's stdout goes to a file so its status is the gate's own: $( ) would swallow a stop
gate_bounded "$SESSION_CAP" python3 "$TMP/driver.py" "$BIN" "$ASAN_BIN" "$TMP" "$CYCLES" >"$TMP/driver.out" 2>"$TMP/driver.err"
drc=$?
ELAPSED=$(( $( date +%s ) - START ))
cat "$TMP/driver.out"
[ -s "$TMP/driver.err" ] && sed 's/^/        | /' "$TMP/driver.err" | head -20

# ── the verdict, read off values the run produced present, numeric, and the premises met ─────────────
SUMMARY="$( grep '^SUMMARY ' "$TMP/driver.out" | tail -1 )"
getn(){ printf '%s\n' "$SUMMARY" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -1; }
if [ -z "$SUMMARY" ]; then
    no "the driver printed no SUMMARY line (rc=$drc): the session did not run to its end"
else
    for key in checks fails cycles stamp content edit switch release cold changed missed san; do
        val="$( getn "$key" )"
        case "$val" in ''|*[!0-9-]*) no "SUMMARY field $key='$val' is not numeric: $SUMMARY"; val=-9;; esac
        eval "S_$key=\$val"
    done
    if [ "${S_cycles:--9}" = "$CYCLES" ]; then ok "all $CYCLES cycles ran (checks=$S_checks)"; else no "cycles=$S_cycles, expected $CYCLES"; fi
    if [ "${S_san:--9}" = 0 ]; then ok "zero sanitizer reports (ASAN_OPTIONS halt_on_error=1 abort_on_error=1 log_path; log directory and stderr empty of reports)"; else no "sanitizer reports: $S_san"; fi
    if [ "${S_stamp:--9}" -ge "$CYCLES" ]; then ok "stamp-keeping rebuilds proved by rebuilt=1: $S_stamp"; else no "only $S_stamp stamp-keeping rebuilds were proved (need >= $CYCLES)"; fi
    if [ "${S_content:--9}" -ge "$CYCLES" ]; then ok "content rebuilds proved: $S_content (MCP edit-verb cycles: $S_edit)"; else no "only $S_content content rebuilds were proved"; fi
    if [ "${S_switch:--9}" -ge $(( CYCLES * 3 )) ]; then ok "root-switch / workspace rebuilds proved: $S_switch"; else no "only $S_switch root-switch rebuilds were proved (need >= $(( CYCLES * 3 )))"; fi
    if [ "${S_cold:--9}" -ge "$CYCLES" ]; then ok "cold-server rank comparisons: $S_cold"; else no "only $S_cold cold-server comparisons ran"; fi
    if [ "${S_changed:--9}" -ge "$CYCLES" ]; then ok "every content mutation changed a compared answer ($S_changed/$CYCLES)"; else no "only $S_changed of $CYCLES mutations changed a compared answer"; fi
    # the release arm needs the host to meet two premises (R's parse inside the memory guard's 5 s clock; the footprint back
    # under the 64M floor after the release). Each missed attempt is counted and named above; with NONE proven the arm is a
    # named SKIP, never a pass, and the other arms still stand.
    if [ "${S_release:--9}" -ge 1 ]; then
        ok "memory-release rebuilds proved (rebuilt=1 on an unchanged tree, in a session that released the index): $S_release (premise misses: $S_missed)"
    elif [ "${S_release:--9}" = 0 ]; then
        skip "memory-release arm: not one release session met its premises on this host in $S_missed attempts (a parse past the memory guard's 5 s clock, or a footprint that stayed over/under the 64M floor); the stamp-keeping, content and root-switch arms are unaffected"
    else
        no "memory-release counter missing"
    fi
    if [ "${S_fails:--9}" = 0 ]; then ok "no comparison failed"; else no "$S_fails comparison(s) failed"; fi
fi
if [ "$drc" = 0 ]; then ok "the session driver exited 0"; else no "the session driver exited $drc (124 = the ${SESSION_CAP} s cap)"; fi
# an orphan is a failure of this gate, whatever else passed (no orphans)
if pgrep -f "$TMP" >/dev/null 2>&1; then
    no "a process started by this gate is still running: $( pgrep -fl "$TMP" | head -3 | tr '\n' ' ' )"
    pkill -f "$TMP" 2>/dev/null
else
    ok "no process of this gate outlives it"
fi
echo "mcpreloadasancheck: ${ELAPSED}s"
# keep the sanitizer reports past the mktemp cleanup, where CI's failure upload (/tmp/asanlog*) finds them: the FAIL row above
# keeps only the first 3000 characters of one report, and the freed-by / allocated-by stacks are the part that follows
if [ "$fail" -ne 0 ] && [ -n "$( ls -A "$TMP/san" 2>/dev/null )" ]; then
    KEEP="$( mktemp -d "${RIPWIRE_SAN_KEEP_DIR:-/tmp}/asanlog-mcpreload.XXXXXX" 2>/dev/null )" \
        && cp "$TMP"/san/* "$TMP"/*.err "$KEEP"/ 2>/dev/null \
        && echo "mcpreloadasancheck: sanitizer reports kept in $KEEP"
fi
if [ "$fail" -eq 0 ]; then echo "mcpreloadasancheck: ALL PASS"; else echo "mcpreloadasancheck: FAIL"; fi
exit "$fail"
