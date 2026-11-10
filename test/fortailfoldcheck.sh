#!/usr/bin/env bash
# fortailfoldcheck.sh — SIZE-2: a code question's --for <tail> folds its widened path-only rows of non-code file classes.
#
# WHY. FOR-TAIL-WIDE walks 160 code rows of the file page; a row past the old 40-row cut prints p= only. On a code question the
# path-only rows of doc, config, script, test-data and other files carried no graded item on the 258 saved 0.6.10 answers
# (reports: size-offline, SIZE-2 A) yet were resent on every later agent call. They are now counted per class on the tail
# (folded="doc=N,config=N,…"), not listed; next= pages to the first one, so the cut is disclosed and recoverable. Code rows and
# test CODE rows (a code file under a test path) are never folded; a class the task names (test data, config, scripts) is kept; an
# add-a-new-X task (the exemplar-family reading) keeps its docs and config (round 2: the 321 lost a package.json peer dependency
# and an API golden .md when they folded); a docs question takes the plain walk.
#
# Arms (each reads the exit code of the command it parses; an empty or crashed answer fails every arm):
#   1  fold:     the default tail carries folded= and lists no path-only row of a non-code class / the ablated tail
#                (RIPWIRE_NO_TAIL_FOLD=1) lists such rows and carries no folded= (positive twin)
#   2  counts:   per class, folded= equals the ablated tail's path-only rows of that class the default tail does not list; the
#                code rows (sym= and path-only) are the ablated tail's, in order; shown= is the rows printed; capped="1"
#   3  next:     next= pages from at most the first folded row's page offset (the --limit=100000 page), so it serves every one
#   4  legend:   the folded= clause rides the compact and the full dialect beside folded=, and neither rides the ablated answer
#   5  asked:    a task naming config keeps the config rows (no config= in folded=, a conf/ path-only row listed);
#                test code: the default tail lists tests/ path-only rows and folded= has no test= (round 2); a shell test file
#                (tests/*.sh) is test code too, listed, not counted as testdata (CodeRabbit 4505000649, 2026-11-08)
#   6  JSON:     "tail"."folded" is the XML folded= as an object, with "folded_why"
#   7  MCP:      the `for` verb's tail carries folded= and the clause; the clause is a session-dictionary entry (CodeRabbit
#                4505000658, 2026-11-08): `--legend-dict` defines it, and a second identical call in the session carries folded= but
#                not the clause again (served once)
#   8  docs:     a docs question folds nothing (plain walk) / the code question does (arm 1)
#   9  add-new:  an add-a-new-X task lists its doc and config path-only rows (no doc= or config= in folded=) and still folds
#                scripts (script= in folded=: the exemption is those two classes, not the whole fold)
#  10  literal:  a task that quotes a message literal found only in a .json string table lists its doc and config path-only
#                rows (no doc= or config= in folded=; round 3: the graded sit lost two items when a quoted message's strings.json
#                rows folded) and still folds scripts / the same words unquoted still fold config (the quotes are the trigger)
#  11  sym wide: TAIL-SYM-WIDE (2026-11-10) names the widened rows (sym=), so arms 1-10 read a widened row as "path-only" on the
#                pre-card tail (RIPWIRE_TAIL_SYM_WIDE_ROWS=0, fortailwidecheck arm 14's ablation); this arm pins that the fold is
#                independent of the naming: the default tail lists the same rows and carries the same folded= as that ablation
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

# fixture F: 60 code files, then test code, docs, config and scripts that all match the question past the page's first 40 rows
F="$TMP/fold"; mkdir -p "$F/tests" "$F/docs" "$F/conf" "$F/scripts"
i=0
while [ $i -lt 60 ]; do
    n=$( printf '%03d' $i )
    printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$n" > "$F/c$n.py"
    if [ $i -lt 40 ]; then
        printf 'def test_widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    assert True\n' "$n" > "$F/tests/test_w$n.py"
        printf '# Widget frobnicate helper %s\n\nThe widget frobnicate helper %s notes.\n' "$n" "$n" > "$F/docs/w$n.md"
    fi
    if [ $i -lt 20 ]; then
        printf 'widget_frobnicate_%s:\n  helper: widget frobnicate helper\n' "$n" > "$F/conf/w$n.yaml"
    fi
    if [ $i -lt 40 ]; then   # 40 scripts: past the old 40-code-row cut they are widened p= rows, so a script class folds
        printf 'frobnicate_%s() {\n  echo "widget"\n}\n' "$n" > "$F/scripts/w$n.sh"   # weaker match: ranks past the code rows
    fi
    if [ $i -lt 10 ]; then   # 10 shell tests: test code, so they stay listed (arm 5)
        printf 'test_widget_frobnicate_%s() {\n  echo "widget frobnicate helper"\n}\n' "$n" > "$F/tests/test_w$n.sh"   # ranks inside the walk
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
run "$TMP/f.sw" "--for=$Q"   # arm 11: the default (named widened rows); every run below reads the pre-card tail
export RIPWIRE_TAIL_SYM_WIDE_ROWS=0
run "$TMP/f.xml"  "--for=$Q"
run "$TMP/f.full" "--for=$Q" --legend=full
run "$TMP/f.json" "--for=$Q" --json
run "$TMP/f.page" "--for=$Q" --limit=100000
run "$TMP/f.tests" "--for=$Q config"
run "$TMP/f.new" "--for=add a new widget frobnicate helper"
run "$TMP/f.docs" "--for=$Q documentation docs"
( export RIPWIRE_NO_TAIL_FOLD=1; run "$TMP/a.xml" "--for=$Q" )
# fixture L (arm 10): F plus 20 .json string tables; the message literal is in one of them only
L="$TMP/lit"; cp -R "$F" "$L"
i=0
while [ $i -lt 20 ]; do
    n=$( printf '%03d' $i )
    printf '{"error": {"widget_frobnicate_%s": "widget frobnicate helper"}}\n' "$n" > "$L/conf/s$n.json"
    i=$(( i + 1 ))
done
printf '{"error": {"widget_frobnicate_019": "widget frobnicate helper", "cannot_link": "Link dropped by remote"}}\n' > "$L/conf/s019.json"
LQ='where does the widget frobnicate helper error get its "Link dropped by remote" text'
( F="$L"; run "$TMP/l.quoted" "--for=$LQ"; run "$TMP/l.bare" "--for=$( printf '%s' "$LQ" | tr -d '"' )" )
( cd "$F" || exit 9; printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$F" "$Q" \
    | HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" --mcp ) > "$TMP/m.def" 2> "$TMP/m.def.err"
echo $? > "$TMP/m.def.rc"
( cd "$F" || exit 9; for id in 1 2; do printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$id" "$F" "$Q"; done \
    | HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" --mcp ) > "$TMP/m.two" 2> "$TMP/m.two.err"
echo $? > "$TMP/m.two.rc"
( cd "$F" || exit 9; HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" --legend-dict ) > "$TMP/dict" 2> "$TMP/dict.err"
echo $? > "$TMP/dict.rc"

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
    if p.endswith((".yaml", ".json")): return "config"
    if p.startswith("tests/") and p.endswith((".py", ".sh")): return "test"   # test code, a shell test included
    if p.endswith(".sh"): return "script"
    if p.startswith("tests/"): return "test"
    return "code"
KEPT = ("code", "test")   # never folded: code, and test code
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
    say(bool(fd) and all(klass(p) in KEPT for p in pod), f"1 fold: folded={dA.get('folded')!r}, every listed path-only row is code or test code ({len(pod)})")
    say("folded" not in aA and any(klass(p) not in KEPT for p in poa), f"1 twin: the ablated tail lists non-code path-only rows ({sum(klass(p) not in KEPT for p in poa)}), no folded=")
    gone = [p for p in poa if p not in set(pod)]
    want = {}
    for p in gone:
        want[klass(p)] = want.get(klass(p), 0) + 1
    say(fd == want and not set(KEPT) & set(want), f"2 counts: folded= {fd} equals the ablated tail's unlisted path-only rows by class {want}")
    say([r for r in aR if klass(r[0]) in KEPT or r[1]] == dR, "2 order: the default rows are the ablated rows minus the folded ones, in order")
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
say(tt is not None and "config" not in folded(tt[0]) and any(klass(p) == "config" and not s for p, s in tt[1]),
    f"5 asked: a config task keeps its config rows (folded={tt[0].get('folded') if tt else None!r})")
say(td is not None and "test" not in folded(td[0]) and any(klass(p) == "test" and not s for p, s in td[1]),
    f"5 test code: the default tail lists tests/ path-only rows, no test= (folded={td[0].get('folded') if td else None!r})")
say(td is not None and ta is not None and "testdata" not in folded(td[0]) and any(p.endswith(".sh") and p.startswith("tests/") for p, s in ta[1])
    and {p for p, s in ta[1] if p.startswith("tests/") and p.endswith(".sh")} <= {p for p, s in td[1]},
    f"5 shell test: every tests/*.sh row of the ablated tail is listed, no testdata= (folded={td[0].get('folded') if td else None!r})")
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
two = load("m.two")
try:
    second = "".join(c.get("text", "") for c in json.loads(two.splitlines()[-1])["result"]["content"]) if two else ""
except (ValueError, KeyError, IndexError, TypeError):
    second = ""
say("for: tail folded=class=N:" in (load("dict") or ""), "7 dictionary: --legend-dict defines the folded= clause")
say('folded="' in second and "tail folded=class=N:" not in second, "7 served once: the session's second call carries folded=, not the clause")
tn = tail_of(load("f.new"))
fn = folded(tn[0]) if tn else {}
say(tn is not None and "doc" not in fn and "config" not in fn and any(klass(p) == "doc" and not s for p, s in tn[1])
    and any(klass(p) == "config" and not s for p, s in tn[1]), f"9 add-new: docs and config path-only rows listed (folded={fn})")
say(tn is not None and fn.get("script", 0) > 0, f"9 twin: the add-new task still folds scripts (folded={fn})")
lq, lb = tail_of(load("l.quoted")), tail_of(load("l.bare"))
fq, fb = (folded(lq[0]) if lq else {}), (folded(lb[0]) if lb else {})
lit_file = lq is not None and any(p == "conf/s019.json" for p, s in lq[1])
say(lq is not None and "doc" not in fq and "config" not in fq and lit_file and any(klass(p) == "config" and not s for p, s in lq[1])
    and any(klass(p) == "doc" and not s for p, s in lq[1]), f"10 literal: a quoted message keeps doc and config rows, its .json listed (folded={fq})")
say(lq is not None and fq.get("script", 0) > 0, f"10 twin: the quoted task still folds scripts (folded={fq})")
say(lb is not None and fb.get("config", 0) > 0, f"10 twin: the same words unquoted fold config (folded={fb})")
td2 = tail_of(docs)
say(td2 is not None and "folded" not in td2[0], "8 docs: a docs question folds nothing")
sw, ab = tail_of(load("f.sw")), tail_of(load("f.xml"))
say(sw is not None and ab is not None and [q for q, _ in sw[1]] == [q for q, _ in ab[1]] and sw[0].get("folded") == ab[0].get("folded")
    and bool(sw[0].get("folded")) and sum(1 for _, y in sw[1] if y) > sum(1 for _, y in ab[1] if y),
    f"11 sym wide: the default tail lists the ablation's rows with the same folded= ({None if sw is None else sw[0].get('folded')}), more of them with sym=")
print("fortailfoldcheck:", "FAIL" if fails else "PASS", f"({fails} failing)")
sys.exit(1 if fails else 0)
PY
