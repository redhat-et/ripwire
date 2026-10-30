#!/usr/bin/env bash
# forheadrrcheck.sh — the HEAD ROUND-ROBIN of a routed --for answer and the DECLARATION-TWIN tier (lane hrr, train 31;
# src/serialize.h reorderHeadRoundRobin / headRoundRobinIds / forHeadRoundRobinOn, src/filter.h declarationTwinFileMultipliers).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary b112e8ac; [G] arms are twins and near-miss
# negatives that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   WHAT     inside the SHOWN <d> rows (none added, none removed, the same row text), ranks 1..8 take each distinct file's best
#            row first, in score order; a row whose name a head row already holds does not open a new file (a C typedef/struct
#            pair, overloads, a vendored copy); the rows that gives up keep score order after it. Rank 1 never moves.
#            <sigs files_first=N> counts the rows whose rank changed, with its reading in the legend (present-only).
#   WHO      the routed subtoken+body answer (CLI XML, CLI --json, MCP `for`). Exempt, byte-identical to RIPWIRE_NO_HEAD_RR=1
#            (the A/B handle): the name-exact route, --no-route, a question that names an indexed file, a tight explicit
#            --token-budget (the reading is uncharged, the docs_after_code= rule).
#   FOLD     the body-tail fold and the compact hops keep SCORE order (the bodies served are the score top three, the
#            RIPWIRE_NO_HEAD_RR=1 answer's r=1..3) — measured: following the reordered head lost graded rows; the reading says so.
#   TIER     a .d.ts/.pyi row is ranked x0.7 when its PACKAGE (nearest package.json / pyproject.toml / setup.py / setup.cfg
#            directory, else the root) holds an implementation of its family; a types-only package keeps 1.0.
#
# Arms (colour on b112e8ac in brackets):
#   H1 [P] one file holding most matching rows (mono): ON order == the round-robin of the OFF order (the model below), the same
#          rows, more distinct files in the head-8 (a file the OFF head-8 left out enters it), r=1 unchanged, files_first= == the rows whose rank changed, reading present
#   H2 [P] a C typedef/struct pair (pair): the same, and the fixture exercises the name rule (the model without it differs)
#   H3 [G] the fold serves the score top three: the first three rows of the RIPWIRE_NO_HEAD_RR=1 answer (mono, pair)
#   H3b [P fix1] the loop aggregator dispatchQueuedJobs (mono) is never followed (review F6; red on 5351fbbb)
#   H4 [P] --json: the rows in the XML ON order, "files_first" present;  H4m [P] MCP `for`: the same order, files_first= present
#   H5 [G] exempt, byte-identical to RIPWIRE_NO_HEAD_RR=1: the name-exact route, --no-route, a question naming src/scheduler.ts,
#          --token-budget=1200
#   H6 [P] the declaration twin (decl): with the round-robin off, the types-only package's declaration (ztypes/index.d.ts) ranks
#          above the same-content declaration whose package has an implementation (withimpl/types/server.d.ts)
#   H6t/H6p/H6q [R on 051101f1] the same with a type test (index.test-d.ts), the row's manifest (setup.py), or a tests/ file added
#          to the types-only package: none is implementation evidence (FIX2 M2)
#   X1 [G] determinism   X2 [G] xmllint well-formed   X3 [G] no "--" inside a legend comment
#
# Usage:  bash test/forheadrrcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forheadrrcheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_HEAD_RR RIPWIRE_NO_BODY_FOLD RIPWIRE_NO_DOCS_AFTER_CODE
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forheadrrcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
FIX="$ROOT/test/forheadrrfix"
[ -d "$FIX/mono/src" ] && [ -d "$FIX/pair" ] && [ -d "$FIX/decl" ] || { echo "fixture test/forheadrrfix missing"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

Q_MONO="How does the scheduler dispatch queued jobs to workers?"
Q_PAIR="How is the job scheduler initialised and run?"
Q_DECL="How does the server handle an incoming request and run the request hooks?"

# run OUT ROOTDIR OFF(0|1) ARGS... — one --for call, rc kept beside the output (an empty answer is not evidence)
run(){ local out="$1" dir="$2" off="$3"; shift 3
    ( cd "$dir" || exit 97
      if [ "$off" = 1 ]; then RIPWIRE_NO_HEAD_RR=1 "$BIN" "$dir" --no-cache "$@"; else "$BIN" "$dir" --no-cache "$@"; fi ) >"$out" 2>"$out.err"
    printf '%s' "$?" >"$out.rc"; }
ran(){ [ "$( cat "$1.rc" )" = 0 ] && [ -s "$1" ] && return 0; no "$2: rc=$( cat "$1.rc" ) bytes=$( wc -c <"$1" | tr -d ' ' )"; return 1; }

cat > "$TMP/chk.py" <<'PY'
import html, json, re, sys
cmd, args = sys.argv[1], sys.argv[2:]
def load(p): return open(p, "rb").read().decode("utf-8", "replace")
def attrs(s): return dict((k, html.unescape(v)) for k, v in re.findall(r'(\w+)="([^"]*)"', s))
def rows(t):
    out = []
    for m in re.finditer(r'<d ([^>]*)>', t):
        a = attrs(m.group(1))
        if "r" in a: out.append((int(a["r"]), a.get("p", ""), a.get("n", "")))
    return [(p, n) for r, p, n in sorted(out)]
def sigs(t):
    m = re.search(r'<sigs\b([^>]*)>', t); return attrs(m.group(1)) if m else {}
def legend(t): return " ".join(re.findall(r'<!--(.*?)-->', t, re.S))
def model(rs, names=True, k=8):
    """the round-robin, independently: each file's best row first (score order), a taken name opens no file"""
    head, files, nms, taken = [], set(), set(), set()
    for i, (p, n) in enumerate(rs):
        if len(head) == k: break
        if p in files or (names and n in nms): continue
        head.append(i); taken.add(i); files.add(p); nms.add(n)
    return [rs[i] for i in head] + [rs[i] for i in range(len(rs)) if i not in taken]
def fail(msg): print(msg); sys.exit(1)
if cmd == "rr":            # ON OFF [names] — ON is the round-robin of OFF; files_first= and its reading agree
    on, off = load(args[0]), load(args[1]); ron, roff = rows(on), rows(off)
    if sorted(ron) != sorted(roff): fail("the shown rows differ (a row added or removed)")
    want = model(roff)
    if ron != want: fail("order %s, expected %s" % (ron[:8], want[:8]))
    if ron[:1] != roff[:1]: fail("rank 1 moved")
    moved = sum(1 for a, b in zip(ron, roff) if a != b)
    if moved == 0: fail("nothing moved: the fixture no longer exercises the head")
    if "morefiles" in args[2:] and len({p for p, n in ron[:8]}) <= len({p for p, n in roff[:8]}): fail("no more distinct files in the head-8")
    ff = sigs(on).get("files_first")
    if ff != str(moved): fail("files_first=%s, expected %d" % (ff, moved))
    if "files_first=N:" not in legend(on): fail("files_first= without its reading")
    if "files_first" in sigs(off) or "files_first=N:" in legend(off): fail("the RIPWIRE_NO_HEAD_RR=1 answer carries files_first=")
    if "names" in args[2:] and model(roff, names=False) == want: fail("the fixture does not exercise the name rule")
    print("head-8 files %d -> %d, files_first=%s" % (len({p for p, n in roff[:8]}), len({p for p, n in ron[:8]}), ff))
elif cmd == "fold":        # ON OFF — the fold's rows are the score top three (OFF's first three rows), and ON's fold is OFF's
    t = load(args[0]); m = re.search(r'<fold [^>]*>(.*?)</fold>', t, re.S)
    if not m: fail("no <fold>")
    # WRAPPER-FOLLOW (src/hopbody.h): a <b follow_of=> is a thin wrapper's callee riding after it, not a ranked row — the ranked rows
    # are still exactly the score top three; a follow body must name a wrapper the fold serves
    pieces = [attrs(x.group(1)) for x in re.finditer(r'<(?:b|skip|slice) ([^>]*)>', m.group(1))]
    got = [a.get("n") for a in pieces if "follow_of" not in a]
    # a follow names (as Owner.name or bare) the body just before it: a ranked row, an earlier follow (a 2-level chain), or the
    # slot owner's body served ahead of the fold (review F6: each of the three is a legitimate wrapper)
    slot = [attrs(x.group(1)).get("n") for x in re.finditer(r'<b ([^>]*)>', t[:t.find('<fold ')])]
    wrappers = set(got) | {a.get("n") for a in pieces if "follow_of" in a} | set(slot)
    spell = lambda q: {q, q.split(".")[-1], q.split("::")[-1]} | ({q.split("#", 1)[1]} if "#" in q[1:] and "." not in q else set())
    if any(not (spell(a["follow_of"]) & wrappers) for a in pieces if "follow_of" in a): fail("a follow_of body names no served wrapper")
    want = [n for p, n in rows(load(args[1]))[:3]]
    mo = re.search(r'<fold [^>]*>.*?</fold>', load(args[1]), re.S)
    if not mo or mo.group(0) != m.group(0): fail("the fold differs from the RIPWIRE_NO_HEAD_RR=1 answer's")
    if got != want: fail("fold rows %s, head rows %s" % (got, want))
    print("fold %s" % got)
elif cmd == "json":        # JSON XMLON — the JSON rows in the XML order, files_first key present
    j = json.loads(load(args[0])); x = rows(load(args[1]))
    def find(o):
        if isinstance(o, dict):
            if "sigs" in o and isinstance(o["sigs"], list): return o["sigs"]
            for v in o.values():
                r = find(v)
                if r is not None: return r
        if isinstance(o, list):
            for v in o:
                r = find(v)
                if r is not None: return r
        return None
    js = find(j) or []
    flat = []
    for e in js:
        if isinstance(e, dict) and "r" in e: flat.append((int(e["r"]), e.get("p", ""), e.get("n", "")))
        if isinstance(e, dict) and isinstance(e.get("syms"), list):
            for s in e["syms"]:
                if "r" in s: flat.append((int(s["r"]), e.get("p", s.get("p", "")), s.get("n", "")))
    jr = [(p, n) for r, p, n in sorted(flat)]
    if [n for p, n in jr] != [n for p, n in x]: fail("json order %s, xml %s" % ([n for p, n in jr][:8], [n for p, n in x][:8]))
    if '"files_first"' not in load(args[0]): fail("no files_first key")
    print("json order == xml order (%d rows)" % len(jr))
elif cmd == "mcp":         # MCPOUT XMLON — the MCP for answer's rows in the XML order, files_first= present
    t = load(args[0]); body = ""
    for line in t.splitlines():
        try: o = json.loads(line)
        except ValueError: continue
        if o.get("id") == 2:
            for c in o.get("result", {}).get("content", []): body += c.get("text", "")
    x = rows(load(args[1])); m = rows(body)
    if [n for p, n in m] != [n for p, n in x]: fail("mcp order %s, xml %s" % ([n for p, n in m][:8], [n for p, n in x][:8]))
    if "files_first=" not in body: fail("no files_first= on the MCP answer")
    print("mcp order == xml order (%d rows)" % len(m))
elif cmd == "above":       # FILE P1 N1 P2 N2 — row (P1,N1) ranks above row (P2,N2)
    rs = rows(load(args[0]))
    try: a, b = rs.index((args[1], args[2])), rs.index((args[3], args[4]))
    except ValueError: fail("a row is missing: %s" % rs)
    if a >= b: fail("%s:%s at r=%d, not above %s:%s at r=%d" % (args[1], args[2], a + 1, args[3], args[4], b + 1))
    print("r=%d above r=%d" % (a + 1, b + 1))
elif cmd == "nodash":
    bad = [c for c in re.findall(r'<!--(.*?)-->', load(args[0]), re.S) if "--" in c]
    if bad: fail("a legend comment holds --")
PY
chk(){ local label="$1"; shift; local msg; if msg="$( python3 "$TMP/chk.py" "$@" 2>&1 )"; then ok "$label: $msg"; else no "$label: $msg"; fi; }

# ── H1/H2/H3: the head, the name rule, the fold ───────────────────────────────────────────────────────────────────────────
run "$TMP/mono.on" "$FIX/mono" 0 --for="$Q_MONO"; run "$TMP/mono.off" "$FIX/mono" 1 --for="$Q_MONO"
if ran "$TMP/mono.on" H1 && ran "$TMP/mono.off" "H1 (twin)"; then
    chk "H1 one file holds most rows: the head names each file first" rr "$TMP/mono.on" "$TMP/mono.off" morefiles
    chk "H3 mono: the fold serves the score top three" fold "$TMP/mono.on" "$TMP/mono.off"
    # fix1 (review F6): dispatchQueuedJobs is a loop aggregator (let n; for … { dispatchJobToWorker(…); n++ } return n), not a thin
    # delegator — its one call is not its last statement, so it is never followed (RED on 5351fbbb, where H3 went red in CI)
    if grep -q 'follow_of="[^"]*dispatchQueuedJobs"' "$TMP/mono.on"; then no "H3b mono: the loop aggregator dispatchQueuedJobs is followed"; else ok "H3b mono: the loop aggregator dispatchQueuedJobs is never followed"; fi
fi
run "$TMP/pair.on" "$FIX/pair" 0 --for="$Q_PAIR"; run "$TMP/pair.off" "$FIX/pair" 1 --for="$Q_PAIR"
if ran "$TMP/pair.on" H2 && ran "$TMP/pair.off" "H2 (twin)"; then
    chk "H2 a typedef/struct pair counts once" rr "$TMP/pair.on" "$TMP/pair.off" names
    chk "H3 pair: the fold serves the score top three" fold "$TMP/pair.on" "$TMP/pair.off"
fi

# ── H4: the --json and MCP twins ──────────────────────────────────────────────────────────────────────────────────────────
run "$TMP/mono.json" "$FIX/mono" 0 --for="$Q_MONO" --json
ran "$TMP/mono.json" H4 && chk "H4 --json: the XML order, files_first" json "$TMP/mono.json" "$TMP/mono.on"
mkdir -p "$TMP/mcphome"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
              '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$FIX/mono"'","task":"'"$Q_MONO"'"}}}' \
    | ( cd "$FIX/mono" || exit 97; TMPDIR="$TMP/mcphome" "$BIN" --mcp ) >"$TMP/mono.mcp" 2>/dev/null
printf '%s' "$?" >"$TMP/mono.mcp.rc"
ran "$TMP/mono.mcp" H4m && chk "H4m MCP for: the XML order, files_first=" mcp "$TMP/mono.mcp" "$TMP/mono.on"

# ── H5: exempt answers are the RIPWIRE_NO_HEAD_RR=1 answer byte for byte ────────────────────────────────────────────────
h5(){ local label="$1"; shift
    run "$TMP/x.on" "$FIX/mono" 0 "$@"; run "$TMP/x.off" "$FIX/mono" 1 "$@"
    ran "$TMP/x.on" "H5 $label" && ran "$TMP/x.off" "H5 $label (twin)" || return 0
    if cmp -s "$TMP/x.on" "$TMP/x.off" && ! grep -q 'files_first' "$TMP/x.on"; then ok "H5 $label: byte-identical to RIPWIRE_NO_HEAD_RR=1"
    else no "H5 $label: differs from RIPWIRE_NO_HEAD_RR=1 (or carries files_first=)"; fi; }
h5 "name-exact route" --for=dispatchQueuedJobs
h5 "--no-route" --for="$Q_MONO" --no-route
h5 "a question naming an indexed file" --for="How does src/scheduler.ts dispatch queued jobs to workers?"
h5 "--token-budget=1200" --for="$Q_MONO" --token-budget=1200

# ── H6: the declaration twin ─────────────────────────────────────────────────────────────────────────────────────────────
run "$TMP/decl.off" "$FIX/decl" 1 --for="$Q_DECL"
ran "$TMP/decl.off" H6 && chk "H6 a types-only declaration ranks above the twin whose package has an implementation" \
    above "$TMP/decl.off" ztypes/index.d.ts serveRequest withimpl/types/server.d.ts handleRequest
# H6t/H6p/H6q (FIX2 M2, review rv-hrr): IMPLEMENTATION EVIDENCE is a file of the package's own code — not a type test, not the
# row's manifest, not a path-tiered file (tests/). Each arm adds one such file to a types-only package; the package must stay
# untiered, so its declaration still ranks above the twin whose package has real code. Red on 051101f1 (the leaky guard).
mkdir -p "$TMP/ts1" && cp -R "$FIX/decl/." "$TMP/ts1/"
printf '%s\n' "import { expectType } from 'tsd'" "import { serveRequest } from '.'" "expectType<void>(serveRequest(1, 2))" >"$TMP/ts1/ztypes/index.test-d.ts"
run "$TMP/ts1.off" "$TMP/ts1" 1 --for="$Q_DECL"
ran "$TMP/ts1.off" H6t && chk "H6t a tsd type test (index.test-d.ts) is no implementation: the types-only declaration still ranks above the twin" \
    above "$TMP/ts1.off" ztypes/index.d.ts serveRequest withimpl/types/server.d.ts handleRequest
pyfix(){ local d="$1"; mkdir -p "$d/cext" "$d/withimpl"
    printf '%s\n' '[project]' 'name="cext"' >"$d/cext/pyproject.toml"
    printf '%s\n' 'def serve_request(request: object, reply: object) -> None:' \
        '    """Serve an incoming request: route the request, run the request hooks, and send the reply for the request."""' '    ...' >"$d/cext/core.pyi"
    printf '%s\n' '[project]' 'name="withimpl"' >"$d/withimpl/pyproject.toml"
    printf '%s\n' 'def handle_request(request: object, reply: object) -> None:' \
        '    """Handle an incoming request: route the request, run the request hooks, and send the reply for the request."""' '    ...' >"$d/withimpl/server.pyi"
    printf '%s\n' 'def handle_request(request, reply):' '    reply.send(request.body)' >"$d/withimpl/server.py"; }
pyfix "$TMP/py1"
printf '%s\n' 'from setuptools import setup, Extension' 'setup(ext_modules=[Extension("cext._core", ["src/core.c"])])' >"$TMP/py1/cext/setup.py"
run "$TMP/py1.off" "$TMP/py1" 1 --for="$Q_DECL"
ran "$TMP/py1.off" H6p && chk "H6p a compiled core's setup.py (the row's own manifest) is no implementation: core.pyi still ranks above the twin" \
    above "$TMP/py1.off" cext/core.pyi serve_request withimpl/server.pyi handle_request
pyfix "$TMP/py2"; mkdir -p "$TMP/py2/cext/tests"
printf '%s\n' 'import cext' 'def test_serve():' '    assert cext.core.serve_request' >"$TMP/py2/cext/tests/test_core.py"
run "$TMP/py2.off" "$TMP/py2" 1 --for="$Q_DECL"
ran "$TMP/py2.off" H6q && chk "H6q a tests/ file (path-tiered) is no implementation: core.pyi still ranks above the twin" \
    above "$TMP/py2.off" cext/core.pyi serve_request withimpl/server.pyi handle_request

# ── X: determinism, well-formed, no "--" in a comment ───────────────────────────────────────────────────────────────────
run "$TMP/mono.on2" "$FIX/mono" 0 --for="$Q_MONO"
if cmp -s "$TMP/mono.on" "$TMP/mono.on2"; then ok "X1 deterministic"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/mono.on" 2>/dev/null && xmllint --noout "$TMP/pair.on" 2>/dev/null; then ok "X2 well-formed"; else no "X2 xmllint rejects an answer"; fi
else ok "X2 xmllint not installed: not judged"; fi
chk "X3 no -- in a legend comment" nodash "$TMP/mono.on"

[ "$fail" = 0 ] && echo "forheadrrcheck: PASS" || echo "forheadrrcheck: FAIL"
exit "$fail"
