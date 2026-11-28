#!/usr/bin/env bash
# actedgescheck.sh — LANE ACT-EDGES (src/foractedgesswitch.h, src/foractedges.h, src/foractline.h ACT-8): on a `--for` page 1 the act
# line lists up to 8 ranges (the top 3 sigs rows, then the next ranged ones), and right after it an EDGES line (callers and other-file
# callees of the act line's first 3 symbols) and a WHERE line (their tests, docs, changelog, build file). RIPWIRE_ACT_EDGES=0 is off.
# ARMS (every one NEW: a binary without the lane writes at most 3 ranges and no <edges>/<where>, so A/E/W fail)
#   (A)  ACT-8: Q1's act read= holds 4..8 ranges, the first 3 the top 3 sigs <d> rows, none held by an earlier one; the full legend
#        (--legend=full) carries the wide clause once
#   (E)  EDGES: Q1 has <edges>; each group "NAME: called by P:L N, ..; calls P:L N" names an act symbol; every P:L is a line of a real
#        file whose text holds N; no P:L inside an act range; at most 2 callers and 2 callees shown per group
#   (W)  WHERE, on test/actedgesfix (a parser with a test, a doc, a changelog and a CMake test list; src/ has no tests or docs beside
#        it): QF's <where> names tests/test_parser.cpp, docs/parser.md, CHANGELOG.md and tests/CMakeLists.txt; on Q1 and QF every path
#        a <where> names exists under the root; tests= paths are test paths
#   (P)  BYTES FROM THE BOTTOM: at the default size no row is pulled onto ON page 1, and it grows by the lane's own bytes at most (they
#        may use room page 1 had); at the smallest --page-bytes the OFF page 1 still holds its rows at, the ON page 1 withholds more
#        and is at most the OFF page 1 plus the core-legend clauses (200 B): the lane's bytes are counted and come off the bottom
#   (P2) NEVER FROM AN ITEM: at the smallest --page-bytes the OFF answer is served whole at (one page, found to the byte), the ON
#        answer is served whole too: the lane's bytes never push a whole answer's last rows onto a page 2 (mf1-ninja-01 R3, measured)
#   (T)  THE TWIN IS THE OFF ANSWER: test/actedgestwin_unit.cpp prints forpages::detail::withoutLane of the whole ON answer (Q1, Q2, QF,
#        --page-bytes=900000 under RIPWIRE_NO_CORE_LEGEND=1): it is the OFF answer byte for byte, est_tokens= aside — pageAnswer serves an answer whole when its twin is, so a
#        twin that differs pages differently (measured: one that kept 3 bytes of range 4 and lost the act element's close made 11 DEV
#        answers OFF pages served whole, +57 KB)
#   (K)  THE ARMS: RIPWIRE_ACT_EDGES=1 is ACT-8 alone (no <edges>, no <where>), =2 EDGES alone (3 ranges), =4 WHERE alone
#   (B)  BUDGET: a --token-budget the ON answer fits returns it with the lines; MCP `for` carries the wide act line and <edges>
#   (O)  OFF: RIPWIRE_ACT_EDGES=0 writes <= 3 ranges (more only in θ17's edit form, as main), no <edges>, no <where>, no lane clause; with RIPWIRE_PARENT_BIN (a binary from before
#        the lane) every OFF answer is the parent's byte for byte (Q1, Q2, Q1 page 2, Q1 whole, --legend=full, --legend=first, --json,
#        --token-budget, MCP)
#   (D)  well formed (xmllint) and deterministic (two ON runs)
#   (M)  MUTATION NEGATIVE CONTROLS: A's, E's and W's detectors FAIL on the OFF page
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
# (T) the lane-off twin driver, compiled with the flags CMake used for $BIN (the cxxflags.sh parse, as forrowfeaturescheck's (U))
. "$ROOT/test/lib/cxxflags.sh"
TWIN_TMP="$( mktemp -d )"; trap 'rm -rf "$TWIN_TMP"' EXIT
TWIN="" TWIN_WHY="no CMake flags.make beside $BIN"
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"; FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"; LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
if [ -f "$FLAGS_MK" ] && [ -f "$LINK_TXT" ] && cxxflags_load "$FLAGS_MK"; then
    CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
    [ -n "$CXX" ] && command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
    DIAG_OBJ="$BUILD_DIR/CMakeFiles/ripwire.dir/src/infra/diagnostics.cpp.o"; DIAG_LINK=(); [ -f "$DIAG_OBJ" ] && DIAG_LINK=( "$DIAG_OBJ" )
    if "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" "${CXX_INCLUDES[@]}" -I"$ROOT/src" "$ROOT/test/actedgestwin_unit.cpp" "${DIAG_LINK[@]}" \
         -o "$TWIN_TMP/twin" >"$TWIN_TMP/build.log" 2>&1; then TWIN="$TWIN_TMP/twin"; TWIN_WHY=""
    else TWIN_WHY="actedgestwin_unit does not compile: $( grep -m2 -E 'error' "$TWIN_TMP/build.log" | tr '\n' ' ' | cut -c1-300 )"; fi
fi
export TWIN TWIN_WHY TWIN_TMP
python3 - "$BIN" "$PARENT" "$ROOT" <<'PY'
import json, os, re, subprocess, sys
BIN, PARENT, ROOT = sys.argv[1], sys.argv[2], sys.argv[3]
Q1 = "where does the paging cut a for answer into pages"   # paged, ranged sigs rows, callers in other files
Q2 = "fix the act line insertion in a for answer"           # an edit task (θ17's form composes with ACT-8)
fail = 0
def ok(m): print("  PASS  " + m)
def no(m):
    global fail; fail = 1; print("  FAIL  " + m)
FIX = "test/actedgesfix"
QF = "how does the parser parse the header body and footer"   # the fixture's act symbols have a test, a doc, a changelog, a build list
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
LANE_CLAUSES = (WIDE, "the edges line:", "the where line:", "edges: per act symbol", "where: tests= docs=")
prose = lambda t: re.sub(r'<!\[CDATA\[.*?\]\]>', '', t, flags=re.S)   # a clause outside the rows (a row may quote the source that defines it)
def lane(t):
    """the page's own act element and the lines right after it -> (read= value, <edges> CDATA text, <where> attributes text), each
    None when absent; anchored at the first <act/> OUTSIDE every CDATA section (a row may quote the source that writes them)"""
    spans = [(m.start(), m.end()) for m in re.finditer(r'<!\[CDATA\[.*?\]\]>', t, re.S)]
    m = next((m for m in re.finditer(r'<act read="([^"]*)"/>', t) if not any(a <= m.start() < b for a, b in spans)), None)
    if not m: return None, None, None
    rest = t[m.end():]
    e = re.match(r'<edges><!\[CDATA\[(.*?)\]\]></edges>', rest, re.S)
    w = re.match(r'<where([^>]*)/>', rest[e.end():] if e else rest)
    return m.group(1), e.group(1) if e else None, w.group(1) if w else None
def act(t):
    v = lane(t)[0]
    return [] if not v else [(x.rsplit(":", 1)[0], *map(int, x.rsplit(":", 1)[1].split("-"))) for x in v.split(",")]
has_edges = lambda t: lane(t)[1] is not None
def lane_len(t):   # the bytes of the page's act element and the lane lines after it
    v, e, w = lane(t)
    return ( len(v) + len('<act read=""/>') if v is not None else 0 ) + ( len(e) + len('<edges><![CDATA[]]></edges>') if e is not None else 0 ) + ( len(w) + len('<where/>') if w is not None else 0 )
has_where = lambda t: lane(t)[2] is not None
def held(rs, p, l, e): return any(q == p and a <= l and b >= e for q, a, b in rs)
def act_ok(t):   # A's detector
    a = act(t)
    return 4 <= len(a) <= 8 and all(not held(a[:i], *a[i]) for i in range(len(a)))
def edges_groups(t):
    e = lane(t)[1]
    return [] if e is None else e.split(" | ")
def edge_refs(g):
    return [(m.group(1), int(m.group(2)), m.group(3)) for m in re.finditer(r'([^\s,;:]+):(\d+) ([^\s,;()]+)', g.split(": ", 1)[1] if ": " in g else "")]
def line_of(p, l, root="src"):
    try:
        with open(os.path.join(ROOT, root, p), errors="replace") as f:
            for i, x in enumerate(f, 1):
                if i == l: return x
    except OSError: return None
    return None
def edges_ok(t, root="src"):   # E's detector
    gs = edges_groups(t); a = act(t)
    if not gs: return False
    for g in gs:
        refs = edge_refs(g)
        if not refs: return False
        cb = g.split("; calls")[0] if "called by" in g else ""
        cl = g.split("calls", 1)[1] if re.search(r'(^|; )calls ', g.split(": ", 1)[1]) else ""
        if len(re.findall(r':\d+ ', cb)) > 2 or len(re.findall(r':\d+ ', cl.split("(+")[0])) > 2: return False
        for p, l, n in refs:
            x = line_of(p, l, root)
            if x is None or n not in x or held(a, p, l, l): return False
    return True
def where_attrs(t):
    w = lane(t)[2]
    return dict(re.findall(r' (\w+)="([^"]*)"', w)) if w is not None else {}
def where_ok(t, root="src"):   # W's detector
    w = where_attrs(t)
    if not w: return False
    for k in ("tests", "docs", "changelog", "build"):
        for p in (w.get(k, "").split(",") if w.get(k) else []):
            if not os.path.exists(os.path.join(ROOT, root, p.rstrip("/"))): return False
            if k == "tests" and not re.search(r'(^|/)(tests?|__tests__)/|_test\.|test_', p): return False
    return True
attr = lambda t, k: int((re.search(r' ' + k + r'="(\d+)"', t.split(">", 1)[0]) or [0, "0"])[1])
A1, A2, AF = run(["--for=" + Q1]), run(["--for=" + Q2]), run(["--for=" + QF], root=FIX)
O1, O2, OF = run(["--for=" + Q1], OFF), run(["--for=" + Q2], OFF), run(["--for=" + QF], OFF, root=FIX)
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
# E
if edges_ok(A1): ok(f"(E) Q1: <edges> with {len(edges_groups(A1))} group(s), every P:L a real line holding N, none inside an act range")
else: no(f"(E) Q1: <edges> missing or malformed: {edges_groups(A1)}")
# W
want = {"tests": "tests/test_parser.cpp", "docs": "docs/parser.md", "changelog": "CHANGELOG.md", "build": "tests/CMakeLists.txt"}
wf = where_attrs(AF)
if where_ok(AF, FIX) and all(wf.get(k) == v for k, v in want.items()): ok(f"(W) fixture: <where> {wf}: test, doc, changelog and build list, every path exists")
else: no(f"(W) fixture: <where> {wf}, want {want}, every path existing")
if not has_where(A1) or where_ok(A1): ok(f"(W) Q1: <where> {where_attrs(A1)}: every path it names exists")
else: no(f"(W) Q1: <where> names a path that does not exist: {where_attrs(A1)}")
# P
b_on, b_off, grow = len(A1.encode()), len(O1.encode()), lane_len(A1) - lane_len(O1)
if b_on - b_off <= grow + 200 and attr(A1, "withheld_bytes") + 200 >= attr(O1, "withheld_bytes"):
    ok(f"(P) Q1: page 1 {b_off} -> {b_on} B (lane {grow:+} B), withheld {attr(O1, 'withheld_bytes')} -> {attr(A1, 'withheld_bytes')}: no row pulled on")
else: no(f"(P) Q1: page 1 {b_off} -> {b_on} B (lane {grow:+} B), withheld {attr(O1, 'withheld_bytes')} -> {attr(A1, 'withheld_bytes')}: rows pulled on or the page grew past the lane")
withheld_at = lambda n, env=None: attr(run(["--for=" + Q1, f"--page-bytes={n}"], env), "withheld_bytes")
lo, hi = 1000, 12000   # OFF withholds more at lo than at hi (the default size)
w_hi = withheld_at(hi, OFF)
if withheld_at(lo, OFF) > w_hi:
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if withheld_at(mid, OFF) > w_hi: lo = mid
        else: hi = mid
    t_on, t_off = run(["--for=" + Q1, f"--page-bytes={hi}"]), run(["--for=" + Q1, f"--page-bytes={hi}"], OFF)
    wn, wf = attr(t_on, "withheld_bytes"), attr(t_off, "withheld_bytes")
    if wn > wf and len(t_on.encode()) <= len(t_off.encode()) + 200:
        ok(f"(P) at --page-bytes={hi}, the smallest the OFF page 1 holds its rows at: withheld {wf} -> {wn}, page 1 {len(t_off.encode())} -> {len(t_on.encode())} B: counted, off the bottom")
    else: no(f"(P) at --page-bytes={hi}: withheld {wf} -> {wn}, page 1 {len(t_off.encode())} -> {len(t_on.encode())} B: the lane's bytes were not taken off the bottom")
else: no("(P) premise: the OFF answer withholds no more at 1000 B than at 12000 B")
# P2
paged = lambda t: ' pages="' in t.split(">", 1)[0]
lo, hi = 1000, 200000   # OFF is paged at lo, whole at hi
if paged(run(["--for=" + Q1, f"--page-bytes={lo}"], OFF)) and not paged(run(["--for=" + Q1, f"--page-bytes={hi}"], OFF)):
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if paged(run(["--for=" + Q1, f"--page-bytes={mid}"], OFF)): lo = mid
        else: hi = mid
    on = run(["--for=" + Q1, f"--page-bytes={hi}"])
    if not paged(on) and has_edges(on) and paged(run(["--for=" + Q1, f"--page-bytes={hi - 1}"], OFF)):
        ok(f"(P2) at --page-bytes={hi}, the smallest the OFF answer is whole at, the ON answer is whole too, with its lines")
    else: no(f"(P2) at --page-bytes={hi} the OFF answer is whole and the ON answer {'is paged' if paged(on) else 'lacks <edges>'}")
else: no("(P2) premise: the OFF answer is not paged at 1000 B and whole at 200000 B")
# T
est = lambda t: re.sub(r' est_tokens="\d+"', ' est_tokens="*"', t, count=1)
if not os.environ.get("TWIN"): no("(T) " + os.environ.get("TWIN_WHY", "no twin driver"))
else:
    pts, same = [], []
    for q, root in ((Q1, "src"), (Q2, "src"), (QF, FIX)):
        whole = ["--for=" + q, "--page-bytes=900000"]   # one page, the document legend as rendered (no core legend), as pageAnswer sees it
        on, off = run(whole, {"RIPWIRE_NO_CORE_LEGEND": "1"}, root=root), run(whole, dict(OFF, RIPWIRE_NO_CORE_LEGEND="1"), root=root)
        f = os.path.join(os.environ["TWIN_TMP"], "on.xml"); open(f, "w").write(on)
        p = subprocess.run([os.environ["TWIN"], f], capture_output=True)
        if p.returncode == 0: pts.append(q[:24]); same += [q[:24]] if est(p.stdout.decode("utf8", "replace")) == est(off) else []
    if pts and len(same) == len(pts):
        ok(f"(T) the lane-off twin of the ON answer IS the OFF answer (est_tokens= aside) on {len(pts)} answers: {', '.join(pts)}")
    else: no(f"(T) the lane-off twin is the OFF answer on {len(same)} of {len(pts)} answers: the twin pages differently from OFF")
# K
k1, k2 = run(["--for=" + Q1], {"RIPWIRE_ACT_EDGES": "1"}), run(["--for=" + Q1], {"RIPWIRE_ACT_EDGES": "2"})
if act_ok(k1) and not has_edges(k1) and not has_where(k1): ok("(K) =1: ACT-8 alone")
else: no("(K) =1 is not ACT-8 alone")
if len(act(k2)) <= 3 and edges_ok(k2) and not has_where(k2): ok("(K) =2: EDGES alone")
else: no("(K) =2 is not EDGES alone")
k4 = run(["--for=" + QF], {"RIPWIRE_ACT_EDGES": "4"}, root=FIX)
if len(act(k4)) <= 3 and not has_edges(k4) and where_ok(k4, FIX): ok("(K) =4: WHERE alone")
else: no("(K) =4 is not WHERE alone")
# B
big = run(["--for=" + Q1, "--token-budget=60000"])
if has_edges(big) and act_ok(big): ok("(B) a budget the answer fits carries the wide act line and <edges>")
else: no("(B) a fitting budget lost a line")
m1 = mcp({"task": QM})
if has_edges(m1) and len(act(m1)) >= 4: ok("(B) MCP for carries the wide act line and <edges>")
else: no("(B) MCP for lacks a lane line")
# O
off_args = [["--for=" + Q1], ["--for=" + Q2], ["--for=" + Q1, "--page-bytes=12000:2"], ["--for=" + Q1, "--page-bytes=0"], ["--for=" + Q1, "--legend=full"],
            ["--for=" + Q1, "--legend=first"], ["--for=" + Q1, "--json"], ["--for=" + Q1, "--token-budget=60000"]]
offs = {" ".join(a): (a, run(a, OFF)) for a in off_args}
offs["mcp"] = (None, mcp({"task": QM}, OFF))
offs["fixture"] = ("fix", OF)
edit = lambda t: 'body_form="edit"' in t.split(">", 1)[0]   # θ17's edit form appends the edit file's body ranges on main too
bad = [k for k, (_, t) in offs.items() if not (t and (len(act(t)) <= 3 or edit(t)) and not has_edges(t) and not has_where(t) and not any(c in prose(t) for c in LANE_CLAUSES))]
if not bad: ok(f"(O) RIPWIRE_ACT_EDGES=0: <= 3 ranges (edit form aside), no <edges>/<where>, no lane clause on {len(offs)} answers")
else: no(f"(O) an OFF answer is empty or carries a lane line or clause: {bad}")
if PARENT:
    for k, (a, t) in offs.items():
        p = mcp({"task": QM}, binary=PARENT) if a is None else run(["--for=" + QF], binary=PARENT, root=FIX) if a == "fix" else run(a, binary=PARENT)
        if t == p: ok(f"(O) {k}: the OFF answer is the parent's byte for byte")
        else: no(f"(O) {k}: the OFF answer moved against the parent")
else: ok("(O) no RIPWIRE_PARENT_BIN: parent comparison skipped (the lane runs it)")
# D
for k, t in (("Q1", A1), ("Q2", A2), ("QF", AF), ("Q1 full", FULL)):
    if subprocess.run(["xmllint", "--noout", "-"], input=t.encode(), capture_output=True).returncode == 0: ok(f"(D) {k}: well formed")
    else: no(f"(D) {k}: xmllint rejects it")
if run(["--for=" + Q1]) == A1: ok("(D) two ON runs byte-identical")
else: no("(D) two ON runs differ")
# M
if not act_ok(O1) and not edges_ok(O1) and not where_ok(OF, FIX): ok("(M) mutation: A's, E's and W's detectors fail on the OFF pages")
else: no("(M) a detector passed the OFF page")
print("actedgescheck: " + ("PASS" if fail == 0 else "FAIL"))
sys.exit(fail)
PY
