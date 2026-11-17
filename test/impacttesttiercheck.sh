#!/usr/bin/env bash
# impacttesttiercheck.sh — IMPACT-TEST-TIER: --impact (and --safe-delete) must not count TEST DEFINITIONS as untested
# production code. Found in the 0.7.0 comparison rehearsal.
#
# THE DEFECT. radius_tested= counts graph.h isTestedByReach, which never counts a test symbol (a test is a SEED of the
# tested lens, never a covered row), and radius_untested= was `reaches - radius_tested`. So every test that calls the
# target landed in radius_untested=: textual --impact=Widget.arrange printed reaches="221" radius_tested="31"
# radius_untested="190" while 172 of the 221 reached symbols were test definitions. Better test coverage made a symbol
# look MORE dangerous on the verb whose job is "is it safe to change X?". --ignore-tests failed the other way and
# silently: it drops every test before the walk, so radius_tested="0" came back as a measurement beside
# importers_tests="45".
#
# THE FIX TIERS AND LABELS; IT DOES NOT EXCLUDE. Tests are legitimate dependents (a gold that requires a test file
# must still find it in the answer), so they stay in reaches= and stay listed; they move to their own count,
# radius_tests=, and their rows carry test="1".
#
# FIXTURE (written below, Python): target() is called by prod_tested (reached by a test), prod_untested and, through it,
# prod_untested2 (no test reaches either), and by three TEST definitions under tests/ (test_target, test_prod_tested and
# a non-test_-named helper in the test file). lonely() has one production caller and no test anywhere near it.
#
# ARMS (each counts its premise and FAILS on zero)
#   (1) TEST TIER: --impact=target carries radius_tests= equal to the number of test-file rows it lists (premise >= 1).
#   (2) PRODUCTION ONLY: radius_tested=1 and radius_untested=2 (the production rows), and
#       radius_tested + radius_untested + radius_tests == reaches=.
#   (3) LISTED AND LABELLED: every test-file row is still printed and carries test="1"; no production row does; the
#       JSON dialect labels the same rows "test":true; the MCP twin prints the same root counts and labels.
#   (4) --ignore-tests: the run drops the tests, so its root says so (tests_ignored="1") and its legend defines it;
#       radius_tests= is absent there (nothing was counted).
#   (5) --safe-delete=target: the same tiers (radius_tests=3, radius_untested=2).
#   (6) NEGATIVE: --impact=lonely (no test in reach) prints exactly main's counts (reaches="1" radius_tested="0"
#       radius_untested="1"), no radius_tests=, no test= row, and no test-tier legend clause.
#   (7) LEGEND: the full and compact legends define radius_tests= and test="1" exactly when they ride.
#
# Usage: bash test/impacttesttiercheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/impacttesttiercheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXD="$TMP/fix"; mkdir -p "$FIXD/geom" "$FIXD/tests"
cat >"$FIXD/geom/shapes.py" <<'EOF'
def target(x):
    return x + 1


def prod_tested(x):
    return target(x)


def prod_untested(x):
    return target(x) * 2


def prod_untested2(x):
    return prod_untested(x) - 1


def lonely(x):
    return x


def lonely_caller(x):
    return lonely(x)
EOF
cat >"$FIXD/tests/test_shapes.py" <<'EOF'
from geom.shapes import target, prod_tested


def test_target():
    assert target(1) == 2


def test_prod_tested():
    assert prod_tested(1) == 2


def make_case():
    return target(3)
EOF

echo "impacttesttiercheck: $BIN"
BIN="$BIN" FIXD="$FIXD" python3 - <<'PY'
import json, os, re, subprocess, sys
BIN, FIXD = os.environ["BIN"], os.environ["FIXD"]
fail = [0]
def ok(m): print("  PASS  " + m)
def no(m): print("  FAIL  " + m); fail[0] = 1

def run(*args):
    p = subprocess.run([BIN, ".", "--no-cache"] + list(args), cwd=FIXD, capture_output=True, text=True, timeout=300)
    return p.stdout

def root_attrs(doc, tag):
    m = re.search(r"<%s ([^>]*)>" % tag, doc)
    return dict(re.findall(r'(\w[\w-]*)="([^"]*)"', m.group(1))) if m else {}

def srows(doc):
    """[(name, path, is_test_label)] for the <s> rows inside <impact>"""
    body = doc[doc.index("<impact "):] if "<impact " in doc else ""
    out = []
    for r in re.findall(r"<s [^>]*/>", body):
        out.append((re.search(r' n="([^"]*)"', r).group(1), re.search(r' p="([^"]*)"', r).group(1).split(":")[0], ' test="1"' in r))
    return out

def legend(doc, tag):
    return "".join(re.findall(r"<!--.*?-->", doc[:doc.index("<%s " % tag)] if ("<%s " % tag) in doc else doc, re.S))

def is_test_path(p):
    return p.startswith("tests/") or "/tests/" in p

TESTS = {"test_target", "test_prod_tested", "make_case"}

full = run("--impact=target", "--limit=100", "--legend=full")
ra = root_attrs(full, "impact")
rows = srows(full)
test_rows = [r for r in rows if is_test_path(r[1])]
prod_rows = [r for r in rows if not is_test_path(r[1])]
reaches = int(ra.get("reaches", "-1"))

# (1) test tier
if len(test_rows) == 0:
    no("(1) premise: --impact=target lists no test-file row (rows=%r) — the fixture does not exercise the defect" % rows)
elif ra.get("radius_tests") == str(len(test_rows)) and {r[0] for r in test_rows} == TESTS:
    ok('(1) radius_tests="%s" == the %d test-file rows listed %s' % (ra.get("radius_tests"), len(test_rows), sorted(r[0] for r in test_rows)))
else:
    no("(1) radius_tests=%r but %d test-file rows are listed (%s); root %r" % (ra.get("radius_tests"), len(test_rows), sorted(r[0] for r in test_rows), ra))

# (2) production only
rt, ru, rx = (int(ra.get(k, "0")) for k in ("radius_tested", "radius_untested", "radius_tests"))
if len(prod_rows) == 0:
    no("(2) premise: no production row in --impact=target (rows=%r)" % rows)
elif (rt, ru) == (1, 2) and rt + ru == len(prod_rows) and rt + ru + rx == reaches:
    ok("(2) radius_tested=%d radius_untested=%d count the %d production rows only; %d+%d+%d == reaches=%d" % (rt, ru, len(prod_rows), rt, ru, rx, reaches))
else:
    no("(2) radius_tested=%d radius_untested=%d radius_tests=%d reaches=%d production rows=%d (want 1, 2, sum == reaches)" % (rt, ru, rx, reaches, len(prod_rows)))

# (3) listed and labelled: XML, JSON, MCP
lab_ok = len(test_rows) > 0 and all(r[2] for r in test_rows) and not any(r[2] for r in prod_rows) and len(rows) == reaches
if lab_ok:
    ok('(3a) every one of the %d test rows is listed with test="1"; none of the %d production rows is' % (len(test_rows), len(prod_rows)))
else:
    no("(3a) test labels wrong or rows missing: rows=%r reaches=%d" % (rows, reaches))
js = run("--impact=target", "--limit=100", "--json")
try:
    jd = json.loads(js)
    jtest = sorted(r.get("name", r.get("n", "")) for r in jd.get("impact", []) if r.get("test") is True)
    if len(test_rows) > 0 and jd.get("radius_tests") == len(test_rows) and jd.get("radius_untested") == ru and len(jtest) == len(test_rows):
        ok("(3b) --json: radius_tests=%d, radius_untested=%d and %d rows carry \"test\":true" % (jd.get("radius_tests"), jd.get("radius_untested"), len(jtest)))
    else:
        no("(3b) --json radius_tests=%r radius_untested=%r test rows=%r (want %d / %d)" % (jd.get("radius_tests"), jd.get("radius_untested"), jtest, len(test_rows), ru))
except Exception as e:
    no("(3b) --json did not parse: %s / %s" % (e, js[:300]))
req = "\n".join([json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize"}),
                 json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "impact",
                            "arguments": {"path": FIXD, "symbol": "target", "limit": 100, "legend": "full"}}})]) + "\n"
p = subprocess.run([BIN, "--mcp"], input=req, capture_output=True, text=True, timeout=300)
try:
    mt = json.loads(p.stdout.strip().splitlines()[-1])["result"]["content"][0]["text"]
    ma = root_attrs(mt, "impact")
    mrows = srows(mt)
    same = all(ma.get(k) == ra.get(k) for k in ("reaches", "radius_tested", "radius_untested", "radius_tests"))
    if len(test_rows) > 0 and same and sorted(mrows) == sorted(rows) and "radius_tests=" in legend(mt, "impact"):
        ok("(3c) MCP impact: the same radius_tested/untested/tests, the same labelled rows, and the clause in its legend")
    else:
        no("(3c) MCP impact root %r rows %r (CLI %r %r)" % (ma, mrows, ra, rows))
except Exception as e:
    no("(3c) MCP impact answered nothing parseable: %s / %s" % (e, p.stdout[-300:]))

# (4) --ignore-tests
ig = run("--impact=target", "--limit=100", "--legend=full", "--ignore-tests")
ia = root_attrs(ig, "impact")
if len(test_rows) == 0:
    no("(4) premise: the un-ignored run lists no test row, so --ignore-tests drops nothing here")
elif ia.get("tests_ignored") == "1" and "radius_tests" not in ia and "tests_ignored=" in legend(ig, "impact") \
        and int(ia.get("reaches", "-1")) == len(prod_rows):
    ok('(4) --ignore-tests: tests_ignored="1" on the root, defined in the legend; radius_tests= absent; reaches=%s (production only)' % ia.get("reaches"))
else:
    no("(4) --ignore-tests root %r; legend defines tests_ignored=: %s (the zero radius_tested= reads as measured)" % (ia, "tests_ignored=" in legend(ig, "impact")))
igc = run("--impact=target", "--limit=100", "--ignore-tests")
if (root_attrs(igc, "impact").get("tests_ignored") == "1") and "tests_ignored=" in legend(igc, "impact"):
    ok("(4b) --ignore-tests under the default (compact) legend: tests_ignored= rides and reads")
else:
    no("(4b) --ignore-tests compact: root %r, legend reads tests_ignored=: %s" % (root_attrs(igc, "impact"), "tests_ignored=" in legend(igc, "impact")))

# (5) safe-delete
sd = run("--safe-delete=target", "--legend=full")
sa = root_attrs(sd, "safe-delete")
if int(sa.get("impact_reaches", "0")) == 0:
    no("(5) premise: --safe-delete=target has impact_reaches=0 (%r)" % sa)
elif sa.get("radius_tests") == "3" and sa.get("radius_untested") == "2" and sa.get("radius_tested") == "1" \
        and "radius_tests=" in legend(sd, "safe-delete"):
    ok('(5) --safe-delete=target: radius_tested="1" radius_untested="2" radius_tests="3", defined in its legend')
else:
    no("(5) --safe-delete=target root %r; legend defines radius_tests=: %s" % (sa, "radius_tests=" in legend(sd, "safe-delete")))

# (6) negative: no test in reach
for posture in ("full", "compact"):
    z = run("--impact=lonely", "--legend=" + posture)
    za = root_attrs(z, "impact")
    zr = srows(z)
    if len(zr) == 0:
        no("(6) premise: --impact=lonely --legend=%s lists no row" % posture)
    elif (za.get("reaches"), za.get("radius_tested"), za.get("radius_untested")) == ("1", "0", "1") and "radius_tests" not in za \
            and "tests_ignored" not in za and not any(r[2] for r in zr) and "radius_tests=" not in legend(z, "impact") \
            and 'test="1"' not in legend(z, "impact") and "test=1" not in legend(z, "impact"):
        ok('(6) --impact=lonely --legend=%s: reaches="1" radius_tested="0" radius_untested="1" as on main; no radius_tests=, no test= row, no clause' % posture)
    else:
        no("(6) --impact=lonely --legend=%s: root %r rows %r; clause present: %s" % (posture, za, zr, "radius_tests=" in legend(z, "impact")))

# (7) legends define what rides
comp = run("--impact=target", "--limit=100")
lf, lc = legend(full, "impact"), legend(comp, "impact")
if len(test_rows) == 0:
    no("(7) premise: no test row rides, so there is nothing for the legend to define")
elif "radius_tests=" in lf and 'test="1"' in lf and "radius_tests" in lc and "test=1" in lc:
    ok("(7) full and compact legends define radius_tests= and the row's test=1 where they ride")
else:
    no("(7) full defines radius_tests=%s test=%s; compact radius_tests=%s test=%s" % ("radius_tests=" in lf, 'test="1"' in lf, "radius_tests" in lc, "test=1" in lc))

print("ALL PASS" if not fail[0] else "FAILED")
sys.exit(fail[0])
PY
