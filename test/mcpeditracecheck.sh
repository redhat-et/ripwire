#!/usr/bin/env bash
# mcpeditracecheck.sh — the F1 / F4 robustness gate for the MCP edit + fetch_body paths (audit  §F1, §F4).
#
# F1 (MEDIUM): the edit verbs (replace_symbol_body / insert_*) did an UNLOCKED read→freshness-check→splice→
#   atomic-rename. A concurrent writer committing to the same file in the [read..rename] window had its write
#   SILENTLY LOST while BOTH parties reported success (audit: 24-25/25 LOST_W). The fix is two-layered:
#     (1) a per-file advisory flock so two COOPERATING ripwire edits (or any writer that respects the lock)
#         fully SERIALIZE — this is a HARD, deterministic guarantee (checks 1 + 3 below), and
#     (2) a freshness RE-CHECK immediately before the atomic rename, so a NON-cooperating external writer's
#         committed change is DETECTED and the edit REFUSES instead of silently clobbering (check 2).
#   HONEST RESIDUAL: (2) shrinks but cannot fully CLOSE the window vs a non-cooperating writer — a rename that
#   lands in the tiny [re-check..rename] gap is still lost. That residual is documented in the verb schema and
#   is why check 2 is a QUANTIFYING/no-torn check, not a lost==0 assertion (a race gate that asserts a
#   timing-residual is 0 would flake — worse than none). The deterministic lost==0 guarantee is checks 1 + 3.
#
# F4 (LOW): fetch_body on a name with same-scope OVERLOADS sharing one handle used to serve the lowest-id body
#   SILENTLY. The fix emits ambiguous_handle + ambiguity_note. Check 4 asserts fetch_body on an overloaded name
#   carries that signal (not a silent lowest-id body).
#
# Discrimination: check 1 FAILS on the current HEAD binary (no lock → the cooperating writer's commit is lost
# every trial) and PASSES on the fixed binary (lock serializes → 0 lost). Check 4 likewise fails on HEAD
# (silent body) and passes on the fix. Big files (~998 KB, just under the 1 MB ingest cap) widen the window so
# the race is exercised, mirroring the audit harness.
#
# Usage:
#   test/mcpeditracecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/mcpeditracecheck.sh
#   RACE_TRIALS=20 test/mcpeditracecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
TRIALS="${RACE_TRIALS:-15}"

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "mcpeditracecheck: BIN=$BIN  TRIALS=$TRIALS"

# ─── the shared MCP-driver Python preamble (server spawn + JSON-RPC send/recv on a big-file corpus) ──────────
read -r -d '' PREAMBLE <<'PYEOF'
import sys, os, json, subprocess, threading, time, tempfile, fcntl
BIN = sys.argv[1]

def atomic_write(path, data):                          # a concurrent atomic commit (mirrors ripwire's atomicWrite)
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d)
    os.fdopen(fd, "w").write(data)
    os.rename(tmp, path)

def fnv1a64(data, offset=1469598103934665603):
    h = offset
    for c in data:
        h = ((h ^ c) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return h

def edit_lock_path(target):                            # A3-F8: mirror C++ mcpedit::editLockPath (cache-dir keyed lock,
    h = fnv1a64(target.encode("utf-8", "surrogateescape")) # NOT a repo-tree "<path>.ripwire-lock" sidecar). FNV-1a-64 of
    name = "ripwire-edit-%016x.lock" % h
    tmpdir = os.environ.get("TMPDIR")                  # same cacheDirLadder(): $TMPDIR/ripwire → XDG/ripwire → /tmp/ripwire-uid
    if tmpdir:
        base = os.path.join(tmpdir, "ripwire")
    else:
        xdg = os.environ.get("XDG_CACHE_HOME")
        base = os.path.join(xdg, "ripwire") if xdg else os.path.join("/tmp", "ripwire-%d" % os.getuid())
    lockdir = os.path.join(base, "locks")
    shard = "%02x" % (fnv1a64(name.encode(), 14695981039346656037) & 0xff)
    d = os.path.join(lockdir, shard); os.makedirs(d, mode=0o700, exist_ok=True)
    return os.path.join(d, name)

PAD = ("// pad " + "x"*60 + "\n") * 14000               # ~980 KB comment pad → widens the [read..rename] window
def src(canary):
    return PAD + "// CANARY=%d\n" % canary + "int target() { return 424242; }\n"

def spawn():
    return subprocess.Popen([BIN, "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, bufsize=1)
def send(s, o): s.stdin.write(json.dumps(o) + "\n"); s.stdin.flush()
def recv(s, i):
    while True:
        ln = s.stdout.readline()
        if not ln: return None
        ln = ln.strip()
        if not ln: continue
        try: r = json.loads(ln)
        except Exception: continue
        if r.get("id") == i: return r
def kill(s):
    try: s.stdin.close(); s.terminate(); s.wait(timeout=5)
    except Exception:
        try: s.kill()
        except Exception: pass
def inner_text(r):
    if r and "result" in r:
        try: return r["result"]["content"][0]["text"]
        except Exception: return ""
    if r and "error" in r: return r["error"].get("message", "")
    return ""
PYEOF

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1. F1 — a COOPERATING concurrent writer NEVER loses its committed write ($TRIALS trials, deterministic) ==="
# ═══════════════════════════════════════════════════════════════════════════
# The writer takes the SAME per-file advisory lock (A3-F8: edit_lock_path(tgt) in the per-user cache dir, keyed
# by the target path — NOT a repo-tree sidecar; flock LOCK_EX) the edit verb takes, so
# it BLOCKS until the edit releases — the two fully serialize. On the FIXED binary the writer's committed
# canary=1 always survives (edit refuses-as-stale OR splices over the post-writer base). On HEAD the edit
# ignores the lock, so it races and the writer's commit is silently lost. Deterministic: no timing residual.
python3 - "$BIN" "$TRIALS" "$TMP/coop" <<PYEOF > "$TMP/coop.out" 2>/dev/null
$PREAMBLE
TRIALS = int(sys.argv[2]); WORK = sys.argv[3]; os.makedirs(WORK, exist_ok=True)
lost = served = 0
for t in range(TRIALS):
    d = os.path.join(WORK, "t%03d" % t); os.makedirs(d, exist_ok=True)
    tgt = os.path.join(d, "big.cpp"); atomic_write(tgt, src(0))
    s = spawn()
    send(s, {"jsonrpc":"2.0","id":1,"method":"initialize"}); recv(s, 1)
    send(s, {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":d,"symbol":"target"}}}); recv(s, 2)
    def writer():
        time.sleep(0.0005)
        lf = open(edit_lock_path(tgt), "a+")
        fcntl.flock(lf, fcntl.LOCK_EX)                 # cooperate: block on the edit's lock
        atomic_write(tgt, src(1))
        fcntl.flock(lf, fcntl.LOCK_UN); lf.close()
    wt = threading.Thread(target=writer); wt.start()
    send(s, {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"path":d,"symbol":"target","new_body":"int target() { return 999999; }"}}})
    r = recv(s, 3); wt.join(); kill(s)
    txt = inner_text(r); disk = open(tgt).read()
    applied = '"applied"' in txt
    canary1 = "// CANARY=1" in disk
    if applied and not canary1: lost += 1       # writer's commit silently gone → the F1 bug
    else: served += 1                           # writer's commit survives (serialized or edit refused)
print(json.dumps({"serialized": served, "lost": lost}))
PYEOF
COOP="$( tail -1 "$TMP/coop.out" )"
echo "  cooperating-writer summary: $COOP"
COOP_LOST="$( printf '%s' "$COOP" | python3 -c 'import sys,json;print(json.load(sys.stdin)["lost"])' 2>/dev/null )"
COOP_SER="$( printf '%s' "$COOP" | python3 -c 'import sys,json;print(json.load(sys.stdin)["serialized"])' 2>/dev/null )"
[ "${COOP_LOST:-1}" = "0" ] && [ "${COOP_SER:-0}" = "$TRIALS" ] \
    && ok "F1: cooperating writer serialized every trial (serialized=$COOP_SER, lost=0) — advisory lock holds" \
    || no "F1: $COOP_LOST/$TRIALS cooperating-writer commits SILENTLY LOST (no lock serialization — the F1 bug)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 2. F1 — a NON-cooperating external writer is DETECTED (re-check), never a torn file (quantified) ==="
# ═══════════════════════════════════════════════════════════════════════════
# The audit harness: a forked writer that does NOT take the lock, committing at a fixed delay into the window.
# The pre-rename re-check catches writes landing in the [read..re-check] span → REFUSED-as-stale; writes in the
# tiny [re-check..rename] residual are still lost (the documented advisory-lock limit). We QUANTIFY the split
# and HARD-assert only what is deterministic: (i) no torn/garbled file ever, (ii) whenever the edit reports
# 'applied', the on-disk file is well-formed (either the writer's content or the edit's, never a mangled mix).
python3 - "$BIN" "$TRIALS" "$TMP/ext" <<PYEOF > "$TMP/ext.out" 2>/dev/null
$PREAMBLE
TRIALS = int(sys.argv[2]); WORK = sys.argv[3]; os.makedirs(WORK, exist_ok=True)
refused = applied_serialized = lost = torn = 0
for t in range(TRIALS):
    d = os.path.join(WORK, "t%03d" % t); os.makedirs(d, exist_ok=True)
    tgt = os.path.join(d, "big.cpp"); atomic_write(tgt, src(0))
    s = spawn()
    send(s, {"jsonrpc":"2.0","id":1,"method":"initialize"}); recv(s, 1)
    send(s, {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":d,"symbol":"target"}}}); recv(s, 2)
    committed = {"ok": False}
    def writer():
        time.sleep(0.0004)                             # aim into the [read..re-check] window (NON-cooperating)
        atomic_write(tgt, src(1)); committed["ok"] = True
    wt = threading.Thread(target=writer); wt.start()
    send(s, {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"path":d,"symbol":"target","new_body":"int target() { return 999999; }"}}})
    r = recv(s, 3); wt.join(); kill(s)
    txt = inner_text(r); disk = open(tgt).read()
    # a well-formed file has EXACTLY ONE target() def and its CANARY line intact; torn = anything else.
    n_target = disk.count("int target()")
    has_canary = ("// CANARY=0" in disk) or ("// CANARY=1" in disk)
    well_formed = (n_target == 1) and has_canary
    if not well_formed: torn += 1; continue
    canary1 = "// CANARY=1" in disk; edited = "999999" in disk
    if ("changed since index" in txt) or ("stale" in txt):
        refused += 1                                   # re-check caught the concurrent write
    elif '"applied"' in txt:
        if (not committed["ok"]) or canary1: applied_serialized += 1
        else: lost += 1                                # residual-window loss (documented, not gated)
print(json.dumps({"refused": refused, "applied_serialized": applied_serialized,
                  "lost_in_residual": lost, "torn": torn}))
PYEOF
EXT="$( tail -1 "$TMP/ext.out" )"
echo "  external-writer summary: $EXT"
EXT_TORN="$( printf '%s' "$EXT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["torn"])' 2>/dev/null )"
EXT_REF="$( printf '%s' "$EXT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["refused"])' 2>/dev/null )"
EXT_LOST="$( printf '%s' "$EXT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["lost_in_residual"])' 2>/dev/null )"
echo "  detected-and-refused: ${EXT_REF:-?}   residual-window losses (documented limit): ${EXT_LOST:-?}   torn: ${EXT_TORN:-?}"
[ "${EXT_TORN:-1}" = "0" ] \
    && ok "F1: no torn/garbled file across $TRIALS non-cooperating-writer trials (atomic rename holds)" \
    || no "F1: $EXT_TORN/$TRIALS trials produced a torn/garbled file"
# informational: the re-check demonstrably converts silent losses into refusals (not gated — timing-dependent).
echo "  (informational) the pre-rename re-check refused $EXT_REF concurrent writes that HEAD would have lost silently;"
echo "  (informational) residual [re-check..rename] window is minimized-but-nonzero vs a non-cooperating writer (documented in the verb schema)."

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 3. F1 ripwire-vs-ripwire — two concurrent EDIT ops on one file cannot both clobber (exactly one body) ==="
# ═══════════════════════════════════════════════════════════════════════════
# Two ripwire edit ops on the SAME file at once: the advisory lock serializes them, so the file ends with
# EXACTLY ONE of the two edited bodies (never a torn interleave, never both-lost).
python3 - "$BIN" "$TMP/vs" <<PYEOF > "$TMP/vs.out" 2>/dev/null
$PREAMBLE
WORK = sys.argv[2]; os.makedirs(WORK, exist_ok=True)
tgt = os.path.join(WORK, "f.cpp")
open(tgt, "w").write(PAD + "int fn() { return 1; }\n")
def one(ret, out):
    s = spawn()
    send(s, {"jsonrpc":"2.0","id":1,"method":"initialize"}); recv(s, 1)
    send(s, {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":WORK,"symbol":"fn"}}}); recv(s, 2)
    send(s, {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"path":WORK,"symbol":"fn","new_body":"int fn() { return %d; }" % ret}}})
    r = recv(s, 3); kill(s)
    out["applied"] = ('"applied"' in inner_text(r))
a = {}; b = {}
ta = threading.Thread(target=one, args=(1000, a)); tb = threading.Thread(target=one, args=(2000, b))
ta.start(); tb.start(); ta.join(); tb.join()
disk = open(tgt).read()
h1 = "return 1000;" in disk; h2 = "return 2000;" in disk
print(json.dumps({"a_applied": a.get("applied"), "b_applied": b.get("applied"),
                  "exactly_one_body": bool(h1 ^ h2), "n_fn": disk.count("int fn()")}))
PYEOF
VS="$( tail -1 "$TMP/vs.out" )"
echo "  vs summary: $VS"
VS_ONE="$( printf '%s' "$VS" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["exactly_one_body"] and d["n_fn"]==1)' 2>/dev/null )"
[ "$VS_ONE" = "True" ] \
    && ok "F1 vs: two concurrent ripwire edits serialized — exactly one well-formed body on disk" \
    || no "F1 vs: file did not end with exactly one of the two edited bodies: $VS"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 4. F4 — fetch_body on an OVERLOADED name emits an ambiguity signal (not a silent lowest-id body) ==="
# ═══════════════════════════════════════════════════════════════════════════
OVL="$TMP/ovl"; mkdir -p "$OVL"
cat >"$OVL/overloads.cpp" <<'EOF'
namespace ov {
int process( int a ) { return a + 1; }
int process( double d ) { return (int)d + 2; }
int process( const char* s, int n ) { return n + 3; }
}
EOF
F4_OUT="$( printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$OVL\",\"symbol\":\"process\"}}}" \
    | "$BIN" --mcp 2>/dev/null )"
HANDLE="$( printf '%s' "$F4_OUT" | python3 -c '
import sys, json, re
h = None
for ln in sys.stdin:
    ln = ln.strip()
    if not ln: continue
    try: r = json.loads(ln)
    except Exception: continue
    if r.get("id") == 2 and "result" in r:
        m = re.search(r"sym#[0-9a-f]+@[0-9a-f]+", r["result"]["content"][0]["text"])
        if m: h = m.group(0)
print(h or "")
' )"
if [ -z "$HANDLE" ]; then
    no "F4: could not obtain a handle for the overloaded name (find_symbol output shape changed?)"
else
    FB="$( printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"fetch_body\",\"arguments\":{\"path\":\"$OVL\",\"handle\":\"$HANDLE\"}}}" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print(r["result"]["content"][0]["text"]) if "result" in r else print("__ERROR__")
' )"
    case "$FB" in
        *ambiguous_handle*ambiguity_note*overloads*)
            ok "F4: fetch_body on the overloaded handle carries ambiguous_handle + ambiguity_note (honest)";;
        *)
            no "F4: fetch_body served a body with NO ambiguity signal (silent lowest-id — the F4 bug): $( echo "$FB" | head -c 160 )";;
    esac
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 5. determinism of the staleness refusal message (edit refused when the base changed) ==="
# ═══════════════════════════════════════════════════════════════════════════
# Deterministically force a staleness refusal (the same SHAPE the pre-rename re-check emits) and confirm the
# message is byte-identical run-to-run (path-normalized) — a race gate's refusal text must not flake. We warm
# the index on a symbol, then rewrite the file so the symbol is GONE; getIndex rebuilds from the new content and
# the edit refuses ("changed since index" or "not found" — both are the deterministic staleness family, matching
# the established mcpeditcheck §5 pattern). The MESSAGE (path-normalized) must be identical across two runs.
stale_refusal() {
    local d="$1"; mkdir -p "$d"
    printf 'int detfn() { return 1; }\n' > "$d/d.cpp"
    local FIFO="$d/in.fifo"; mkfifo "$FIFO"
    "$BIN" --mcp <"$FIFO" >"$d/out.txt" 2>/dev/null &
    local SRV=$!
    exec 7>"$FIFO"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&7
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$d\",\"symbol\":\"detfn\"}}}" >&7
    for _ in $( seq 1 100 ); do grep -q '"id":2' "$d/out.txt" 2>/dev/null && break; sleep 0.05; done
    # rewrite so the target symbol no longer exists → the edit is refused (stale-index or not-found family).
    printf 'int other_symbol_entirely() { return 0; }\n' > "$d/d.cpp"
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$d\",\"symbol\":\"detfn\",\"new_body\":\"int detfn() { return 3; }\"}}}" >&7
    for _ in $( seq 1 100 ); do grep -q '"id":3' "$d/out.txt" 2>/dev/null && break; sleep 0.05; done
    exec 7>&-
    wait "$SRV" 2>/dev/null
    grep '"id":3' "$d/out.txt" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:"+r["error"].get("message","")) if "error" in r else print(r["result"]["content"][0]["text"])
'
}
M1="$( stale_refusal "$TMP/det/a" )"
M2="$( stale_refusal "$TMP/det/b" )"
case "$M1" in
    __ERROR__*changed\ since\ index*|__ERROR__*not\ found*) : ;;
    *) no "determinism: the base-changed edit was NOT refused (staleness gate miss): $( echo "$M1" | head -c 120 )";;
esac
N1="$( printf '%s' "$M1" | sed "s#$TMP/det/a##g" )"
N2="$( printf '%s' "$M2" | sed "s#$TMP/det/b##g" )"
[ "$N1" = "$N2" ] \
    && ok "determinism: the staleness refusal message is stable across runs (path-normalized)" \
    || no "determinism: refusal message differs run-to-run: [$N1] vs [$N2]"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
