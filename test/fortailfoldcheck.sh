#!/usr/bin/env bash
# fortailfoldcheck.sh — SIZE-2: a code question's --for <tail> folds its widened path-only rows of non-code file classes.
#
# WHY. FOR-TAIL-WIDE walks 160 code rows of the file page; a row past the old 40-row cut prints p= only. On a code question the
# path-only rows of doc, test, config, script, test-data and other files carried no graded item on the 258 saved 0.6.10 answers
# (reports: size-offline, SIZE-2 A: 7,111 rows, 0 items lost) yet were resent on every later agent call. They are now counted per
# class on the tail (folded="doc=N,test=N,…"), not listed; next= pages to the first one, so the cut is disclosed and recoverable.
# Code rows are never folded; a class the task names (tests, config, scripts) is kept; a docs question takes the plain walk.
#
# Arms (each reads the exit code of the command it parses; an empty or crashed answer fails every arm):
#   1  fold:     the default tail carries folded= and lists no path-only row of a non-code class / the ablated tail
#                (RIPWIRE_NO_TAIL_FOLD=1) lists such rows and carries no folded= (positive twin)
#   2  counts:   per class, folded= equals the ablated tail's path-only rows of that class the default tail does not list; the
#                code rows (sym= and path-only) are the ablated tail's, in order; shown= is the rows printed; capped="1"
#   3  next:     next= pages from at most the first folded row's page offset (the --limit=100000 page), so it serves every one
#   4  legend:   the folded= clause rides the compact and the full dialect beside folded=, and neither rides the ablated answer
#   5  asked:    a task naming tests keeps the test rows (no test= in folded=, a tests/ path-only row listed)
#   6  JSON:     "tail"."folded" is the XML folded= as an object, with "folded_why"
#   7  MCP:      the `for` verb's tail carries folded= and the clause
#   8  docs:     a docs question folds nothing (plain walk) / the code question does (arm 1)
#
# Usage: test/fortailfoldcheck.sh [BIN]   (default build/ripwire; RIPWIRE_BIN also honoured)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "fortailfoldcheck: BIN=$BIN"

# fixture F: 90 code files, then test code, docs, config and scripts that all match the question past the page's first 40 rows
F="$TMP/fold"; mkdir -p "$F/tests" "$F/docs" "$F/conf" "$F/scripts"
i=0
while [ $i -lt 90 ]; do
    n=$( printf '%03d' $i )
    printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$n" > "$F/c$n.py"
    if [ $i -lt 40 ]; then
        printf 'def test_widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    assert True\n' "$n" > "$F/tests/test_w$n.py"
        printf '# Widget frobnicate helper %s\n\nThe widget frobnicate helper %s notes.\n' "$n" "$n" > "$F/docs/w$n.md"
    fi
    if [ $i -lt 20 ]; then
        printf 'widget_frobnicate_%s:\n  helper: widget frobnicate helper\n' "$n" > "$F/conf/w$n.yaml"
        printf 'widget_frobnicate_%s() {\n  echo "widget frobnicate helper"\n}\n' "$n" > "$F/scripts/w$n.sh"
    fi
    i=$(( i + 1 ))
done
Q="widget frobnicate helper"

run() {   # run OUTFILE ARGS... -> rc file beside the output; HOME/TMPDIR private, cwd = the fixture
    local o="$1"; shift
    ( cd "$F" || exit 9; HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" "$F" --no-cache "$@" ) > "$o" 2> "$o.err"
    echo $? > "$o.rc"
}
mkdir -p "$TMP/home"
run "$TMP/f.xml"  "--for=$Q"
run "$TMP/f.full" "--for=$Q" --legend=full
run "$TMP/f.json" "--for=$Q" --json
run "$TMP/f.page" "--for=$Q" --limit=100000
run "$TMP/f.tests" "--for=$Q tests"
run "$TMP/f.docs" "--for=$Q documentation docs"
( export RIPWIRE_NO_TAIL_FOLD=1; run "$TMP/a.xml" "--for=$Q"; run "$TMP/a.tests" "--for=$Q tests" )
( cd "$F" || exit 9; printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$F" "$Q" \
    | HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" --mcp ) > "$TMP/m.def" 2> "$TMP/m.def.err"
echo $? > "$TMP/m.def.rc"

python3 - "$TMP" <<'PY'
import html, json, re, sys
T = sys.argv[1]; fails = 0
def say(ok, msg):
    global fails
    print(("PASS " if ok else "FAIL ") + msg)
    fails += 0 if ok else 1
def load(name):
    try:
        rc = open(f"{T}/{name}.rc").read().strip(); tx = open(f"{T}/{name}", errors="replace").read()
    except OSError:
        return None
    return tx if rc == "0" and tx.strip() else None
def tail_of(tx):
    m = re.search(r'<tail((?:\s+[\w:-]+="[^"]*")*)\s*>(.*?)</tail>', tx or "", re.S)
    if not m:
        return None
    attrs = dict(re.findall(r'([\w:-]+)="([^"]*)"', m.group(1)))
    rows = [(html.unescape(p), s) for p, s in re.findall(r'<t p="([^"]*)"(?: sym="([^"]*)")?\s*/>', m.group(2))]
    return attrs, rows
def klass(p):
    if p.endswith(".md"): return "doc"
    if p.endswith(".yaml"): return "config"
    if p.endswith(".sh"): return "script"
    if p.startswith("tests/"): return "test"
    return "code"
def folded(attrs):
    v = attrs.get("folded", "")
    return {k: int(n) for k, n in (kv.split("=") for kv in v.split(",") if kv)} if v else {}

d, a, page = load("f.xml"), load("a.xml"), load("f.page")
td, ta = tail_of(d), tail_of(a)
ok = td is not None and ta is not None
say(ok, "0 both answers ran (rc 0, non-empty) and carry a <tail>")
if ok:
    (dA, dR), (aA, aR) = td, ta
    fd = folded(dA)
    pod = [p for p, s in dR if not s]; poa = [p for p, s in aR if not s]
    say(bool(fd) and all(klass(p) == "code" for p in pod), f"1 fold: folded={dA.get('folded')!r}, every listed path-only row is code ({len(pod)})")
    say("folded" not in aA and any(klass(p) != "code" for p in poa), f"1 twin: the ablated tail lists non-code path-only rows ({sum(klass(p) != 'code' for p in poa)}), no folded=")
    gone = [p for p in poa if p not in set(pod)]
    want = {}
    for p in gone:
        want[klass(p)] = want.get(klass(p), 0) + 1
    say(fd == want and "code" not in want, f"2 counts: folded= {fd} equals the ablated tail's unlisted path-only rows by class {want}")
    say([r for r in aR if klass(r[0]) == "code" or r[1]] == dR, "2 order: the default rows are the ablated rows minus the folded ones, in order")
    say(dA.get("shown") == str(len(dR)) and dA.get("capped") == "1", f"2 shown={dA.get('shown')} rows={len(dR)} capped={dA.get('capped')}")
    pt = tail_of(page) if page else None
    prow = re.findall(r'<f p="([^"]*)"', page or "") or re.findall(r'<t p="([^"]*)"', page or "")
    nxt = re.search(r"--offset=(\d+)", html.unescape(dA.get("next", "")))
    first = min((prow.index(p) for p in gone if p in prow), default=None)
    say(nxt is not None and first is not None and int(nxt.group(1)) <= first,
        f"3 next: offset {nxt.group(1) if nxt else None} <= first folded row's page index {first}")
full, json_tx, tests, docs, mcp = load("f.full"), load("f.json"), load("f.tests"), load("f.docs"), load("m.def")
CL = "; t folded=class=N:"; FL = "; tail folded=class=N:"
say(d is not None and CL in d and full is not None and FL in full and 'folded="' in full,
    "4 legend: the compact and the full clause ride beside folded=")
say(a is not None and CL not in a and FL not in a, "4 twin: no folded clause on the ablated answer")
tt = tail_of(tests)
say(tt is not None and "test" not in folded(tt[0]) and any(klass(p) == "test" and not s for p, s in tt[1]),
    f"5 asked: a tests task keeps its test rows (folded={tt[0].get('folded') if tt else None!r})")
try:
    jt = json.loads(json_tx)["tail"] if json_tx else None
except (ValueError, KeyError, TypeError):
    jt = None
say(jt is not None and ok and jt.get("folded") == folded(td[0]) and bool(jt.get("folded_why")),
    f"6 JSON: folded {jt.get('folded') if jt else None} with folded_why")
try:
    mt = "".join(c.get("text", "") for c in json.loads(mcp.splitlines()[-1])["result"]["content"]) if mcp else ""
except (ValueError, KeyError, IndexError, TypeError):
    mt = ""
say('folded="' in mt and "; tail folded=class=N:" in mt, "7 MCP: the for verb's tail carries folded= and its clause")
td2 = tail_of(docs)
say(td2 is not None and "folded" not in td2[0], "8 docs: a docs question folds nothing")
print("fortailfoldcheck:", "FAIL" if fails else "PASS", f"({fails} failing)")
sys.exit(1 if fails else 0)
PY
