#!/usr/bin/env bash
# actedgescheck.sh — LANE ACT-EDGES (src/foractedgesswitch.h, src/foractline.h ACT-8): on a `--for` page 1 the act line lists up to
# 8 ranges (the top 3 sigs rows, then the next ranged ones). RIPWIRE_ACT_EDGES=0 is off.
# ARMS (every one NEW: a binary without the lane writes at most 3 ranges, so A fails)
#   (A)  ACT-8: Q1's act read= holds 4..8 ranges, the first 3 the top 3 sigs <d> rows, none held by an earlier one; the full legend
#        (--legend=full) carries the wide clause once
#   (P)  BYTES FROM THE BOTTOM: ON page 1 is at most the OFF page 1 plus the core-legend clauses (200 B), and withholds at least the
#        OFF page's rows less those clauses: the added ranges' bytes came out of the bottom of the page, not on top of it
#   (P2) NEVER FROM AN ITEM: at the smallest --page-bytes the OFF answer is served whole at (one page, found to the byte), the ON
#        answer is served whole too: the lane's bytes never push a whole answer's last rows onto a page 2 (mf1-ninja-01 R3, measured)
#   (K)  THE ARM: RIPWIRE_ACT_EDGES=1 is ACT-8, as the default
#   (B)  BUDGET: a --token-budget the ON answer fits returns it with the wide act line; MCP `for` carries it
#   (O)  OFF: RIPWIRE_ACT_EDGES=0 writes <= 3 ranges (more only in θ17's edit form, as main), no wide clause; with RIPWIRE_PARENT_BIN (a binary from before
#        the lane) every OFF answer is the parent's byte for byte (Q1, Q2, Q1 page 2, Q1 whole, --legend=full, --legend=first, --json,
#        --token-budget, MCP)
#   (D)  well formed (xmllint) and deterministic (two ON runs)
#   (M)  MUTATION NEGATIVE CONTROL: A's detector FAILS on the OFF page
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "actedgescheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "actedgescheck: xmllint required"; exit 2; }
PARENT="${RIPWIRE_PARENT_BIN:-}"
echo "actedgescheck: BIN=$BIN${PARENT:+ PARENT=$PARENT}"
cd "$ROOT" || exit 2
unset RIPWIRE_ACT_EDGES RIPWIRE_NO_ACTLINE RIPWIRE_NO_CORE_LEGEND
exec python3 - "$BIN" "$PARENT" "$ROOT" <<'PY'
import json, os, re, subprocess, sys
BIN, PARENT, ROOT = sys.argv[1], sys.argv[2], sys.argv[3]
Q1 = "where does the paging cut a for answer into pages"   # paged, ranged sigs rows, callers in other files
Q2 = "fix the act line insertion in a for answer"           # an edit task (θ17's form composes with ACT-8)
fail = 0
def ok(m): print("  PASS  " + m)
def no(m):
    global fail; fail = 1; print("  FAIL  " + m)
QM = "rank symbols by pagerank and serialize the map"         # an MCP `for` task that carries an act line (actlinecheck (M))
def run(argv, env=None, binary=None, root="src"):
    e = dict(os.environ); e.update(env or {})
    p = subprocess.run([binary or BIN, root, "--no-cache"] + argv, capture_output=True, env=e, stdin=subprocess.DEVNULL)
    if p.returncode != 0:
        no(f"{argv} {env or ''} exited {p.returncode}: {p.stderr.decode('utf8', 'replace').strip()[:400]}")
    return p.stdout.decode("utf8", "replace")
def mcp(args, env=None, binary=None):
    e = dict(os.environ); e.update(env or {})
    req = [{"jsonrpc": "2.0", "id": 0, "method": "initialize"}, {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "for", "arguments": args}}]
    p = subprocess.run([binary or BIN, "src", "--mcp"], input="".join(json.dumps(r) + "\n" for r in req).encode(), capture_output=True, env=e)
    for line in p.stdout.decode("utf8", "replace").splitlines():
        try: r = json.loads(line)
        except ValueError: continue
        if r.get("id") == 1: return "".join(c.get("text", "") for c in r.get("result", {}).get("content", []))
    return ""
OFF = {"RIPWIRE_ACT_EDGES": "0"}
WIDE = "the act line: read= P:L-E of the top 3 sigs d rows by r=, then the next ranged ones, up to 8 ranges"
LANE_CLAUSES = (WIDE,)
prose = lambda t: re.sub(r'<!\[CDATA\[.*?\]\]>', '', t, flags=re.S)   # a clause outside the rows (a row may quote the source that defines it)
def lane(t):
    """the page's own act element -> its read= value, None when absent; anchored at the first <act/> OUTSIDE every CDATA section (a row may quote the source that writes them)"""
    spans = [(m.start(), m.end()) for m in re.finditer(r'<!\[CDATA\[.*?\]\]>', t, re.S)]
    m = next((m for m in re.finditer(r'<act read="([^"]*)"/>', t) if not any(a <= m.start() < b for a, b in spans)), None)
    return m.group(1) if m else None
def act(t):
    v = lane(t)
    return [] if not v else [(x.rsplit(":", 1)[0], *map(int, x.rsplit(":", 1)[1].split("-"))) for x in v.split(",")]
def held(rs, p, l, e): return any(q == p and a <= l and b >= e for q, a, b in rs)
def act_ok(t):   # A's detector
    a = act(t)
    return 4 <= len(a) <= 8 and all(not held(a[:i], *a[i]) for i in range(len(a)))
attr = lambda t, k: int((re.search(r' ' + k + r'="(\d+)"', t.split(">", 1)[0]) or [0, "0"])[1])
A1, A2 = run(["--for=" + Q1]), run(["--for=" + Q2])
O1, O2 = run(["--for=" + Q1], OFF), run(["--for=" + Q2], OFF)
FULL = run(["--for=" + Q1, "--legend=full"])
# A
if act_ok(A1): ok(f"(A) Q1: act read= holds {len(act(A1))} ranges, none held by an earlier one")
else: no(f"(A) Q1: act read= {act(A1)} is not 4..8 distinct ranges")
if prose(FULL).count(WIDE) == 1: ok("(A) Q1 --legend=full: the wide act clause once")
else: no(f"(A) Q1 --legend=full: the wide act clause {prose(FULL).count(WIDE)} times")
if act(A1)[:3] == act(O1)[:3]: ok("(A) Q1: the first 3 ranges are the shipped act line's")
else: no(f"(A) Q1: the first 3 ranges moved: {act(A1)[:3]} vs OFF {act(O1)[:3]}")
if 'body_form="edit"' in A2.split(">", 1)[0] and all(not held(act(A2)[:i], *act(A2)[i]) for i in range(len(act(A2)))):
    ok(f"(A) Q2 (edit form): {len(act(A2))} act ranges, none duplicated by the edit-file body ranges")
elif 'body_form="edit"' not in A2.split(">", 1)[0]: ok("(A) Q2: no edit form on this tree (composition arm not reached)")
else: no(f"(A) Q2: an act range is held by an earlier one: {act(A2)}")
# P
b_on, b_off = len(A1.encode()), len(O1.encode())
if b_on <= b_off + 200 and attr(A1, "withheld_bytes") + 200 >= attr(O1, "withheld_bytes"):
    ok(f"(P) Q1: page 1 {b_off} -> {b_on} B, withheld {attr(O1, 'withheld_bytes')} -> {attr(A1, 'withheld_bytes')}: the added ranges' bytes came from the bottom")
else: no(f"(P) Q1: page 1 {b_off} -> {b_on} B, withheld {attr(O1, 'withheld_bytes')} -> {attr(A1, 'withheld_bytes')}: the added ranges grew the page")
# P2
paged = lambda t: ' pages="' in t.split(">", 1)[0]
lo, hi = 1000, 200000   # OFF is paged at lo, whole at hi
if paged(run(["--for=" + Q1, f"--page-bytes={lo}"], OFF)) and not paged(run(["--for=" + Q1, f"--page-bytes={hi}"], OFF)):
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if paged(run(["--for=" + Q1, f"--page-bytes={mid}"], OFF)): lo = mid
        else: hi = mid
    on = run(["--for=" + Q1, f"--page-bytes={hi}"])
    if not paged(on) and act_ok(on) and paged(run(["--for=" + Q1, f"--page-bytes={hi - 1}"], OFF)):
        ok(f"(P2) at --page-bytes={hi}, the smallest the OFF answer is whole at, the ON answer is whole too, with its wide act line")
    else: no(f"(P2) at --page-bytes={hi} the OFF answer is whole and the ON answer {'is paged' if paged(on) else 'lacks the wide act line'}")
else: no("(P2) premise: the OFF answer is not paged at 1000 B and whole at 200000 B")
# K
k1 = run(["--for=" + Q1], {"RIPWIRE_ACT_EDGES": "1"})
if act_ok(k1) and k1 == A1: ok("(K) =1: ACT-8, the default's answer")
else: no("(K) =1 is not the default's ACT-8 answer")
# B
big = run(["--for=" + Q1, "--token-budget=60000"])
if act_ok(big): ok("(B) a budget the answer fits carries the wide act line")
else: no("(B) a fitting budget lost a line")
m1 = mcp({"task": QM})
if len(act(m1)) >= 4: ok("(B) MCP for carries the wide act line")
else: no("(B) MCP for lacks the wide act line")
# O
off_args = [["--for=" + Q1], ["--for=" + Q2], ["--for=" + Q1, "--page-bytes=12000:2"], ["--for=" + Q1, "--page-bytes=0"], ["--for=" + Q1, "--legend=full"],
            ["--for=" + Q1, "--legend=first"], ["--for=" + Q1, "--json"], ["--for=" + Q1, "--token-budget=60000"]]
offs = {" ".join(a): (a, run(a, OFF)) for a in off_args}
offs["mcp"] = (None, mcp({"task": QM}, OFF))
edit = lambda t: 'body_form="edit"' in t.split(">", 1)[0]   # θ17's edit form appends the edit file's body ranges on main too
bad = [k for k, (_, t) in offs.items() if not (t and (len(act(t)) <= 3 or edit(t)) and not any(c in prose(t) for c in LANE_CLAUSES))]
if not bad: ok(f"(O) RIPWIRE_ACT_EDGES=0: <= 3 ranges (edit form aside), no wide clause on {len(offs)} answers")
else: no(f"(O) an OFF answer is empty or carries the wide line or its clause: {bad}")
if PARENT:
    for k, (a, t) in offs.items():
        p = mcp({"task": QM}, binary=PARENT) if a is None else run(a, binary=PARENT)
        if t == p: ok(f"(O) {k}: the OFF answer is the parent's byte for byte")
        else: no(f"(O) {k}: the OFF answer moved against the parent")
else: ok("(O) no RIPWIRE_PARENT_BIN: parent comparison skipped (the lane runs it)")
# D
for k, t in (("Q1", A1), ("Q2", A2), ("Q1 full", FULL)):
    if subprocess.run(["xmllint", "--noout", "-"], input=t.encode(), capture_output=True).returncode == 0: ok(f"(D) {k}: well formed")
    else: no(f"(D) {k}: xmllint rejects it")
if run(["--for=" + Q1]) == A1: ok("(D) two ON runs byte-identical")
else: no("(D) two ON runs differ")
# M
if not act_ok(O1): ok("(M) mutation: A's detector fails on the OFF page")
else: no("(M) a detector passed the OFF page")
print("actedgescheck: " + ("PASS" if fail == 0 else "FAIL"))
sys.exit(fail)
PY
